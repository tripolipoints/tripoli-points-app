# Tripoli Points — المرحلة 0 v1.3.1: خطوات التنفيذ على Supabase Staging

- **المشروع:** Staging `axzlshimvtskkxknlwoz` فقط. لا Production قبل موافقة منفصلة بعد نجاح Staging.
- **المدة:** حوالي 15 دقيقة. التطبيق يبقى شغالاً خلال التنفيذ.
- **البيانات:** المرحلة 0 لا تكتب أي صف في الزبائن أو التجار أو المعاملات أو المحافظ أو النقاط أو الإعدادات.
- **الملفات الخطرة:** لا تشغّل أي ملف اسمه يبدأ بـ `DANGEROUS`.

## قبل التنفيذ

1. **تحقق أنك على Staging.** في Supabase Dashboard، تأكد أن الرابط يحتوي `axzlshimvtskkxknlwoz`.
2. **خذ نسخة احتياطية.** من Database → Backups تأكد من وجود نسخة من اليوم، أو خذ نسخة يدوية إذا كانت خطتك تسمح بذلك.
3. **شغّل فحص الحالة v1.3.1 (قراءة فقط).** في SQL Editor → New query، الصق `tp-security-status-check.sql` كاملاً واضغط Run. احفظ النتيجة (Download CSV). يجب أن تظهر:
   - صفوف `pre`: كل قيم عمود `applied` = `true`، وآخرها `VERDICT: … can be applied on this database` = `true`.
   - صفوف `oct`: كلها `true`.
   - إذا كان أي صف `pre` = `false`: **توقف** وأرسل لي الـ CSV. نص الصف يذكر السبب، مثل `DIFFERENT, fingerprint …` أو `extra: …`. ملف المرحلة 0 سيرفض التنفيذ في هذه الحالة على أي حال.
4. **شغّل ملف الفحص (قراءة فقط)** `tp-security-staging-inspect.sql`. فيه 3 استعلامات، شغّل كل واحد وحده واحفظ CSV لكل نتيجة:
   - تواقيع الدوال التي تلمسها المرحلة 0 وصلاحياتها الحالية.
   - ما يستطيع المفتاح العام استدعاءه اليوم، وماذا ستفعل المرحلة 0 بكل دالة.
   - أعداد طلبات شحن Whish خلال آخر 90 يوماً (أعداد فقط، بلا بيانات شخصية).
   دوّن قيمة صفَّي `info | service_role can execute whish_…` من فحص الحالة. المرحلة 0 ستُبقيهما كما هما بالضبط.
4b. **اختبر Whish على Staging قبل المرحلة 0.** نفّذ عملية شحن تجريبية وسجّل النتيجة كخط أساس للمقارنة. على Staging اليوم ليس عند `service_role` صلاحية على `whish_confirm_payment`، لذلك قد لا يتأكد الشحن حتى قبل المرحلة 0.

## التنفيذ

5. **شغّل ملف المرحلة 0.** في New query، الصق `tp-security-phase0-urgent.sql` كاملاً، من `begin;` إلى `commit;`، واضغط Run مرة واحدة.
   - النجاح: تظهر في Notices ثلاث رسائل:
     - `phase 0: N function(s) closed to the public key`
     - `phase 0 self-check: 52 behavioural checks passed` (العدد الفعلي حسب قاعدتك)
     - `phase 0 guard: no API key gained any access; N access(es) removed`
   - الفشل: إذا ظهر `ERROR` أو `STOP`، فالملف تراجع عن كل شيء ولم يتغيّر أي شيء. انسخ رسالة الخطأ كاملة وأرسلها لي، ولا تعِد المحاولة بتعديل الملف.

## التحقق بعد التنفيذ

6. **أعد فحص الحالة.** شغّل `tp-security-status-check.sql` مرة ثانية. يجب أن تكون:
   - كل صفوف `p0` = `t`. الصف `old register / offer / location overloads closed` قد يكون فارغاً إذا لم تكن تلك النسخ موجودة.
   - كل صفوف `oct` = `t`.
   - صفّا `service_role can execute whish_…` = نفس قيم الخطوة 4.
7. **شغّل الفحص السلوكي.** في New query:
   ```sql
   select * from public._phase0_selfcheck() where not ok;
   ```
   النتيجة الصحيحة: **صفر صفوف**.
8. **شغّل الاختبارات الكاملة.** الصق `tp-security-phase0-tests.sql` كاملاً واضغط Run.
   - النتيجة في آخر جدولين: `failed = 0`. العدد المتوقع حوالي 70، وقد يختلف قليلاً حسب الدوال الموجودة.
   - الاختبارات تنتهي بـ `ROLLBACK`، فلا يبقى منها أي حساب أو قفل أو نسخة.
   - تحذير: الاختبارات تمسح الجداول وتعيدها داخل transaction، فتبقى مقفلة بضع ثوانٍ. لذلك تُشغَّل على Staging فقط، **ولا تُشغَّل على Production أبداً**.
9. **شغّل ملف الرجوع بوضعه الافتراضي.** الصق `tp-security-phase0-urgent-rollback.sql` كما هو بلا أي تعديل.
   - يجب أن تظهر الرسائل `no account named in v_keys: no lock released (default)` و`all … behavioural checks pass`.
   - هذا يثبت أن تشغيل الرجوع العادي لا يغيّر شيئاً.
10. **اختبر التطبيق على Staging يدوياً:**
    - دخول زبون بـ PIN صحيح.
    - دخول تاجر.
    - دخول أدمن.
    - شراء عادي: تاجر ينشئ وزبون يوافق.
    - إذا كان Whish مفعّلاً على Staging: عملية شحن تجريبية.
    - المتوقع: كل ذلك يعمل كما قبل.
11. **اختبر القفل يدوياً (اختياري).** على حساب زبون تجريبي: 5 رموز خاطئة، ثم الرمز الصحيح يجب أن يُرفض لمدة 15 دقيقة. لفكّ القفل، راجع البند «زبون حقيقي مقفول» في جدول الأخطاء.
12. **زر «مسح كل البيانات» في لوحة الأدمن.** يجب أن يعطي خطأ صلاحية، وهذا هو المقصود. لا تحاول تجاوزه.

## خطة التعامل مع الأخطاء

| ما حصل | ماذا تفعل |
|---|---|
| `STOP: … differs from the reviewed version (fingerprint …)` | لم يتغيّر شيء. أرسل لي الـ fingerprint ونتيجة: `select pg_get_functiondef('public.customer_verify_pin(text,text)'::regprocedure);` (أو الدالة المذكورة في الرسالة). |
| `STOP: the October 2026 fixes are missing` | لم يتغيّر شيء. يجب تطبيق ملفات أكتوبر أولاً. أرسل لي نتيجة فحص الحالة. |
| `phase 0 self-check failed …` أو `STOP: protection missing at the end` | لم يتغيّر شيء. أرسل لي الرسالة كاملة، ففيها اسم الفحص الذي فشل. |
| `permission denied to set role "anon"` | لم يتغيّر شيء. حساب SQL Editor لا يملك صلاحية تقمّص دور anon. أرسل لي نتيجة: `select rolname from pg_roles r where pg_has_role(current_user, r.oid, 'member');` |
| `STOP: service_role … would lose access` | لم يتغيّر شيء. هذا يعني تعارضاً مع إعدادات Whish. أرسل لي الرسالة. |
| بعد التنفيذ: زبون أو تاجر حقيقي مقفول | انتظر 15 دقيقة، أو في ملف الرجوع اكتب في `v_keys` المفتاح بالضبط (مثل `array['customer:70123456']`) واكتب السبب في `v_reason`، ثم شغّله. |
| بعد التنفيذ: حسابات كثيرة مقفولة بسبب خطأ في التطبيق | أوقف السبب أولاً، ثم راسلني قبل استعمال `tp-security-DANGEROUS-unlock-all-pin-locks.sql`. |
| بعد التنفيذ: الدخول لا يعمل لأحد | لا تشغّل أي ملف DANGEROUS. أرسل لي رسالة الخطأ من التطبيق (Console) ونتيجة الخطوة 7. الحل يكون بإعادة تشغيل ملف المرحلة 0 أو بتصحيح، وليس بإعادة فتح الدوال. |
| بعد التنفيذ: شحن Whish لا يتأكد | قارن مع خط الأساس في الخطوة 4b. إذا كان لا يتأكد قبل المرحلة 0 أيضاً، فالسبب سابق لها (`service_role` = `false` على Staging). أرسل لي كود Edge Function الخاص بالتأكيد وسجلّه. إعطاء الصلاحية لـ `service_role` فقط قرار منفصل بموافقتك، ولا يُعطى لـ `anon` أبداً. |
| مسح بالخطأ (فقط إذا شغّل المالك المسح من SQL Editor) | استخرج رقم النسخة: `select stamp, made_at from tp_backup.wipe_runs order by made_at desc;` ثم شغّل: `select public._tp_wipe_restore('<stamp>');` |

## ما لا يُفعل أبداً

- لا تشغّل `tp-security-DANGEROUS-reopen-phase0.sql`. كل سطوره معطّلة (comments)، ووجوده للتوثيق فقط.
- لا تعطِ `anon` أو `authenticated` أي صلاحية على `customer_reset_pin` أو `whish_confirm_payment` أو `admin_wipe_all_data` أو `tp_backup`.
- لا تحذف نسخة من `tp_backup` إلا بالأمر الصريح: `select public._tp_wipe_drop('<stamp>', 'DELETE COPY <stamp>');`
- لا تشغّل `tp-security-phase0-tests.sql` على Production.
