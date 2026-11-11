# Tripoli Points — مراجعة نتيجة فحص Staging وإصدار المرحلة 0 v1.3.1 · 2026-11-11

- **المصدر:** CSV فحص الحالة v1.3 الذي شغّلته على Staging `axzlshimvtskkxknlwoz`.
- **ما لم يحصل:** لم يُنفَّذ أي SQL على Staging أو Production من جهتي (لا وصول لي إلى Staging)، ولم يتغيّر `main`.

## الخلاصة

- **لا يمكن تطبيق v1.3 كما هي.** الاختبار على حالة مطابقة لـ CSV الخاص بك كشف أن الفحص الذاتي داخل الملف كان سيتوقف على Staging. السبب: الدوال القديمة `customer_register` (3 وسائط) و`merchant_register` موجودة ومغلقة على Staging (صف `old register … overloads closed = true`)، فصار استدعاؤها بالاسم ملتبساً (`is not unique`).
- **التوقف كان سيكون آمناً:** كل الملف transaction واحدة، فلا شيء كان سيتغيّر. لكن التنفيذ كان سيفشل.
- **الإصلاح في v1.3.1:** الفحص الذاتي يستدعي كل دالة بنسختها المحددة (typed nulls). إذا تشاركت عدة نسخ الاسم نفسه، تُفحص الصلاحية من سجل النظام (catalog)، وتُسجَّل على هذا الأساس صراحة.
- **v1.3.1 قابلة للتطبيق على Staging،** بشرط أن يُظهر فحص الحالة v1.3.1 القيمة `VERDICT = true`.

## الأجوبة

**1. لماذا كانت نتائج `pre` = `null`؟**
- لأن v1.3 وضعت نتيجة الفحص داخل نص العمود `fix`، وتركت العمود `applied` فارغاً (null) عن قصد. لم يكن ذلك فشلاً.
- النص في الـ CSV يقول أن الشروط متحققة:
  - الدوال الثلاث `= reviewed version: yes`.
  - `October helpers present …: true`.
- كان هذا تصميماً مربكاً. في v1.3.1 صارت النتيجة `true`/`false` في عمود `applied`، مع صف `VERDICT` نهائي يجمع كل الشروط.

**2. تواقيع الدوال وتعريفاتها على Staging**
- **ما يثبته الـ CSV:** `to_regprocedure` وجد الدوال الثلاث بالتواقيع الدقيقة (`customer_verify_pin(text,text)`، `admin_verify_pin(text,text)`، `admin_wipe_all_data(uuid,text)`)، ولو لم يجدها لظهر `MISSING`. كذلك بصمة المحتوى (md5 بعد تجاهل المسافات وحالة الأحرف) **تطابق** النسخة التي راجعتها، فالتعريفات هي نفسها.
- **ما لا أستطيع رؤيته مباشرة:** لا وصول لي إلى Staging.
- **ما أضفته لتسدّ هذه الثغرة:**
  - ملف `tp-security-staging-inspect.sql` للقراءة فقط. يعرض لكل دالة تلمسها المرحلة 0: التوقيع، المالك، SECURITY DEFINER، الإعدادات، الصلاحيات الحالية لكل دور، البصمة، وما ستفعله المرحلة 0 بها.
  - صف `pre` جديد يتأكد أنه لا توجد نسخ إضافية من دوال PIN أو المسح.

**3. صلاحية Whish لـ `service_role` = `false`**
- هذا **حال Staging قبل المرحلة 0**، وليس من فعلها، لأن المرحلة 0 لم تُطبَّق بعد. يتفق مع ملاحظتك أن Whish مغلقة على Staging: الإغلاق هناك شمل `service_role` أيضاً.
- على Production الوضع مختلف: `service_role` لديه الصلاحية عبر PUBLIC.
- **هل هو متوقع؟** يعتمد على طريقة تأكيد الدفع على Staging:
  - التطبيق يستدعي Edge Function اسمها `whish-create-payment`. أما تأكيد الدفع فيحصل على الخادم، وكوده غير موجود في المستودع.
  - إذا كان يستدعي `whish_confirm_payment` بمفتاح `service_role`، فتأكيد الشحن على Staging **لا يعمل اليوم أصلاً**، وهذه مشكلة سابقة.
  - إذا كان يحدّث الجداول مباشرة، فلا مشكلة.
- الاستعلام 3 في ملف الفحص يُظهر إن كانت طلبات الشحن تصل إلى حالة مدفوعة على Staging.
- **المرحلة 0 تُبقي الصلاحية `false` كما هي:** لا تفتحها ولا تغيّرها. إعطاء الصلاحية لـ `service_role` (وليس لـ anon) قرار منفصل بموافقتك بعد رؤية كود الـ Edge Function.

**4. فحص التوافق (v1.3.1، للقراءة فقط، استعلام SELECT واحد)**
- `applied` = true/false لكل شرط في صفوف `pre`. الشروط هي:
  - الدوال الثلاث بتوقيعها الدقيق ونسختها المراجَعة.
  - أدوات أكتوبر موجودة.
  - حدّ أكتوبر على دخول التاجر موجود.
  - لا نسخ إضافية من دوال PIN والمسح.
  - التطبيق يستطيع اليوم استدعاء فحوص PIN الثلاثة.
  - مستخدم SQL Editor يستطيع العمل بدور `anon` و`authenticated`، وهذا لازم للفحص الذاتي.
  - صلاحية إنشاء schema.
  - `crypt()` متاحة.
- صف `VERDICT` نهائي يجمع كل ما سبق.
- صفّا `info` يعرضان صلاحية `service_role` على `whish_confirm_payment` و`whish_set_collect_url`.
- جُرّب أن الصفوف تصبح `false` مع سبب واضح عند: دالة مختلفة، نسخة إضافية، أو مستخدم لا يملك دور anon.

**5. لا إعادة فتح ولا تعطيل لـ Whish**
- حالة جديدة `stg_csv` مطابقة لـ CSV الخاص بك:
  - Whish والهدية مغلقتان على كل الأدوار بما فيها `service_role`.
  - النسخ القديمة من التسجيل موجودة ومغلقة.
  - دوال إضافية خاصة بـ Staging، بعضها مفتوح وبعضها لـ `service_role` فقط.
- النتيجة على هذه الحالة:
  - المرحلة 0 تُطبَّق.
  - صلاحية `service_role` على Whish تبقى `false`.
  - النسخ القديمة تبقى مغلقة.
  - الدوال الإضافية لا تُمس.
  - إعادة التشغيل لا تغيّر شيئاً.
  - 70/70 اختباراً سلوكياً.
- الحارس النهائي في الملف يمنع ثلاثة أشياء:
  - أي صلاحية جديدة لأي مفتاح API.
  - خسارة `service_role` لأي صلاحية غير المسح.
  - بقاء أي إغلاق ناقصاً في نهاية الملف.
- لماذا لا يوجد خطر على Whish: المرحلة 0 لا تغيّر جسم أي دالة Whish، وتغيّر الصلاحيات فقط.

**6. النتيجة**
- v1.3 **تحتاج تعديلاً** (السبب في البند الأول من الخلاصة).
- v1.3.1 هي الإصدار المصحَّح، وجاهزة لـ Staging بعد أن تشغّل فحص الحالة v1.3.1 وتحصل على `VERDICT = true`.

## نتائج التشغيل المحلي (`local-test/run_phase0.sh`): 61/61

```
== 1. October tests unchanged by phase 0
PASS  October security tests: identical output without and with phase 0 (bc2bfa4b41bb)
== 2. starting states (Production today; Staging variants)
PASS  prod: status check (read-only) VERDICT before phase 0 = t
PASS  prod: phase 0 applies; self-check + no-gain guard pass
PASS  prod: Whish + gift: service_role keeps exactly what it had (service_role:true service_role:true service_role:true )
PASS  prod: Whish + gift closed to anon/authenticated
PASS  prod: behavioural tests:  70 | 0 | 70
PASS  prod: re-running phase 0 changes nothing (idempotent)
PASS  stg_svc: status check (read-only) VERDICT before phase 0 = t
PASS  stg_svc: phase 0 applies; self-check + no-gain guard pass
PASS  stg_svc: Whish + gift: service_role keeps exactly what it had (service_role:true service_role:true service_role:true )
PASS  stg_svc: Whish + gift closed to anon/authenticated
PASS  stg_svc: behavioural tests:  70 | 0 | 70
PASS  stg_svc: re-running phase 0 changes nothing (idempotent)
PASS  stg_closed: status check (read-only) VERDICT before phase 0 = t
PASS  stg_closed: phase 0 applies; self-check + no-gain guard pass
PASS  stg_closed: Whish + gift: service_role keeps exactly what it had (service_role:false service_role:false service_role:false )
PASS  stg_closed: Whish + gift closed to anon/authenticated
PASS  stg_closed: behavioural tests:  70 | 0 | 70
PASS  stg_closed: re-running phase 0 changes nothing (idempotent)
PASS  stg_csv: status check (read-only) VERDICT before phase 0 = t
PASS  stg_csv: phase 0 applies; self-check + no-gain guard pass
PASS  stg_csv: Whish + gift: service_role keeps exactly what it had (service_role:false service_role:false service_role:false )
PASS  stg_csv: Whish + gift closed to anon/authenticated
PASS  stg_csv: behavioural tests:  70 | 0 | 70
PASS  stg_csv: re-running phase 0 changes nothing (idempotent)
PASS  stg_csv: Staging-only functions untouched (open one still open, service_role-only one unchanged)
PASS  stg_csv: old register overloads stay closed to every key
== 3. pre-flight stops before changing anything
PASS  a different customer_verify_pin: STOP with its fingerprint, nothing changed
PASS  October fixes missing: STOP, nothing changed
PASS  final guard: customer_reset_pin re-opened late in the file is caught, nothing changed
PASS  final guard: an access anon never had (new owner-only function) is caught, nothing changed
PASS  final guard: Whish access removed from service_role is caught, nothing changed
== 4. safe rollback (default changes nothing; named accounts only)
PASS  default run: 3 locks stay, no privilege/function/data change
PASS  default run: nothing logged as released
PASS  a key without a reason: refused, nothing changed
PASS  pattern/wildcard key "customer:%": refused, nothing changed
PASS  pattern/wildcard key "customer:": refused, nothing changed
PASS  pattern/wildcard key "*": refused, nothing changed
PASS  pattern/wildcard key "customer:7099000_": refused, nothing changed
PASS  pattern/wildcard key "customer:70990001' or '1'='1": refused, nothing changed
PASS  named key: only 70990001 released (2 locks stay)
PASS  named key: release logged with reason and the old record
PASS  after the rollback the PIN limit still works: 5 wrong PINs lock 70990001 again
PASS  after the rollback customer_verify_pin still has its limit
PASS  after the rollback admin_verify_pin still has its limit
PASS  after the rollback admin_wipe_all_data still has its limit
PASS  after the rollback: customer_reset_pin, whish_confirm_payment, wipe still closed to anon + authenticated
PASS  a protection missing: rollback STOPS and its unlock is undone (3 locks stay)
PASS  rollback file: no function definition, no GRANT, no unconditional delete
PASS  rollback on a database without phase 0: refuses, nothing changed
PASS  behavioural tests after all rollback runs:  70 | 0 | 70
== 5. DANGEROUS unlock-all (separate file, typed confirmation)
PASS  as shipped: REFUSED, nothing changed
PASS  wrong date in the phrase: REFUSED, nothing changed
PASS  exact phrase + reason: every record released (3), each logged, protections re-checked
PASS  DANGEROUS reopen file: every statement commented out
== 6. full stack: phase 1 + e-mail on top, their rollbacks keep phase 0
PASS  phase 1 tests:  104 | 0 | 104
PASS  e-mail tests:  48 | 0 | 48
PASS  phase 0 tests with phase 1 + e-mail:  70 | 0 | 70
PASS  e-mail rollback: schema identical to after phase 1
PASS  phase 1 rollback: schema identical to after phase 0 (phase 0 protections intact)
PASS  phase 0 tests after both rollbacks:  70 | 0 | 70
== summary: 61 passed, 0 failed
```

## ما لم يتم التحقق منه

- كود الـ Edge Function التي تؤكد دفع Whish على Staging، والمفتاح الذي تستعمله.
- الدوال الإضافية الموجودة على Staging (94 دالة مقابل 90 على Production): الاستعلام 2 في ملف الفحص يعرضها بالاسم. التعامل معها مضمون بالحارس النهائي، والحالة `stg_csv` تُثبت أنها لا تُمس.
- عضوية `postgres` في الأدوار anon وauthenticated على Staging: يُظهرها صف `pre` الجديد.
