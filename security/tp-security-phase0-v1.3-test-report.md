# Tripoli Points — المرحلة 0 v1.3: تقرير الاختبارات · 2026-11-11

- **أين جرت الاختبارات:** كل النتائج من قاعدة محلية (PostgreSQL 16) مبنية لتطابق بنية Production وStaging الحالية، مع إصلاحات أكتوبر مطبّقة.
- **ما لم يحصل:** لم يُنفَّذ أي SQL على Staging أو Production، ولم يُشغَّل أي ملف DANGEROUS على Supabase، ولم يتغيّر `main`. ملفات المرحلة 1 والبريد والكنوز لم تتغيّر في هذا الإصدار.
- **أين تشغّلت ملفات DANGEROUS:** على القاعدة المحلية فقط، لاختبار أنها ترفض بلا تأكيد.

**النتيجة الإجمالية:**
- 50/50 فحصاً في سيناريو التشغيل الكامل (`local-test/run_phase0.sh`).
- 70/70 اختباراً سلوكياً في `tp-security-phase0-tests.sql`، على كل حالة بداية.
- المرحلة 1: 104/104. البريد: 48/48.

## ما الذي تغيّر عن v1.2

| الطلب | ما فُعل |
|---|---|
| الرجوع لا يفك كل الأقفال تلقائياً | الوضع الافتراضي **لا يغيّر شيئاً**، ويكتفي بعرض الأقفال الموجودة وإعادة الفحص. فك القفل يكون فقط لمفاتيح مكتوبة صراحة في `v_keys`، بشروط: سبب إلزامي، وحد أقصى 20 حساباً، وصيغة مفتاح دقيقة. أي نمط أو wildcard (`%`، `_`، `*`، مفتاح ناقص، محاولة حقن) يُرفض. كل فك قفل يُسجَّل في `tp_backup.lock_releases` مع السجل القديم. وإذا نقصت أي حماية، يُلغى فك القفل نفسه. |
| فك كل الأقفال في ملف منفصل | الملف `tp-security-DANGEROUS-unlock-all-pin-locks.sql` يرفض كما هو. يحتاج كتابة العبارة `RELEASE ALL PIN LOCKS <تاريخ اليوم UTC>` وسبباً. يحفظ كل سجل قبل حذفه، ثم يعيد فحص الحمايات. |
| لا إعادة فتح ولا PIN بلا حدود | ملف الرجوع لا يحتوي أي تعريف دالة ولا أي `GRANT` (فُحص تلقائياً). ملف المرحلة 0 أضاف **حارساً نهائياً** يوقف كل شيء ويتراجع في ثلاث حالات: (1) حصل أي مفتاح API (anon، authenticated، service_role) على صلاحية لم تكن عنده قبل الملف؛ (2) خسر service_role أي صلاحية غير المسح؛ (3) أي إغلاق لم يعد قائماً في آخر الملف. |
| التوافق مع Staging | **فحص مسبق** لا يغيّر شيئاً: يتأكد من وجود إصلاحات أكتوبر، ومن أن الدوال الثلاث التي يستبدلها الملف هي نفس النسخة التي راجعناها (بصمة المحتوى). إذا اختلفت أي دالة يتوقف ويطبع البصمة، فلا يستبدل كوداً لم نره. الإغلاق في الجزء A **يحافظ ولا يضيف**: ما هو مغلق يبقى مغلقاً، وservice_role يحتفظ بالضبط بما كان له. |
| النسخ والاسترجاع | (1) checksum لكل جدول يُحفظ لحظة النسخ. (2) قبل الاسترجاع، يتحقق الملف أن النسخة لم تتغيّر منذ حفظها؛ أي تعديل، حتى مع نفس عدد الصفوف، يمنع الاسترجاع. (3) بعد الاسترجاع، يقارن محتوى كل جدول بالكامل مع نسخته. (4) لا تُستبدل نسخة أبداً، وأي نسخة جديدة تأخذ اسماً جديداً. (5) سجلات النسخ لا تُحذف ولا تُعدَّل ولا تُفرَّغ (trigger). (6) حذف نسخة يحتاج كتابة `DELETE COPY <stamp>`. (7) RLS مفعّل على كل جدول نسخة. (8) لا يصل أي مفتاح API إلى `tp_backup`، حتى لو وُسّعت صلاحيات الجداول الافتراضية (جُرّب ذلك). |
| فحص الحالة | ما زال للقراءة فقط. أُضيفت صفوف `pre` تجيب «هل ستعمل المرحلة 0 هنا؟» قبل التنفيذ (البصمات وأكتوبر)، وصف `info` يعرض صلاحية service_role على Whish، و4 صفوف p0 للإصدار v1.3. |

## سيناريو التشغيل الكامل (`local-test/run_phase0.sh`): 50/50

```
== 1. October tests unchanged by phase 0
PASS  October security tests: identical output without and with phase 0 (bc2bfa4b41bb)
== 2. starting states (Production today; Staging variants)
PASS  prod: phase 0 applies; self-check + no-gain guard pass
PASS  prod: Whish + gift: service_role keeps exactly what it had (service_role:true service_role:true service_role:true )
PASS  prod: Whish + gift closed to anon/authenticated
PASS  prod: behavioural tests:  70 | 0 | 70
PASS  prod: re-running phase 0 changes nothing (idempotent)
PASS  stg_svc: phase 0 applies; self-check + no-gain guard pass
PASS  stg_svc: Whish + gift: service_role keeps exactly what it had (service_role:true service_role:true service_role:true )
PASS  stg_svc: Whish + gift closed to anon/authenticated
PASS  stg_svc: behavioural tests:  70 | 0 | 70
PASS  stg_svc: re-running phase 0 changes nothing (idempotent)
PASS  stg_closed: phase 0 applies; self-check + no-gain guard pass
PASS  stg_closed: Whish + gift: service_role keeps exactly what it had (service_role:false service_role:false service_role:false )
PASS  stg_closed: Whish + gift closed to anon/authenticated
PASS  stg_closed: behavioural tests:  70 | 0 | 70
PASS  stg_closed: re-running phase 0 changes nothing (idempotent)
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
== summary: 50 passed, 0 failed
```

**حالات البداية المختبرة:**
- `prod`: مثل Production اليوم.
- `stg_svc`: Whish وهدية الزبون مغلقتان على anon وauthenticated، وservice_role يحتفظ بالصلاحية.
- `stg_closed`: Whish وهدية الزبون مغلقتان على الجميع، بما فيه service_role.

في الحالات الثلاث: المرحلة 0 تُطبَّق، لا يُفتح أي شيء كان مغلقاً، وصلاحية service_role على Whish تبقى كما كانت (`true` في الحالتين الأوليين، `false` في الثالثة).

## الاختبارات السلوكية (`tp-security-phase0-tests.sql`): 70/70

| # | النتيجة | الاختبار |
|---|---|---|
| 1 | PASS | anon: every closed function is denied when called (20 functions) |
| 2 | PASS | anon: wipe with a valid primary admin and the RIGHT PIN is denied |
| 3 | PASS | anon: cannot read the rate-limit table |
| 4 | PASS | anon: cannot write the rate-limit table |
| 5 | PASS | anon: cannot clear the rate-limit table (unlock itself) |
| 6 | PASS | anon: cannot reset a lock through the helper |
| 7 | PASS | anon: cannot open the backup schema |
| 8 | PASS | authenticated: every closed function is denied when called (20 functions) |
| 9 | PASS | authenticated: wipe with a valid primary admin and the RIGHT PIN is denied |
| 10 | PASS | authenticated: cannot read the rate-limit table |
| 11 | PASS | authenticated: cannot write the rate-limit table |
| 12 | PASS | authenticated: cannot clear the rate-limit table (unlock itself) |
| 13 | PASS | authenticated: cannot reset a lock through the helper |
| 14 | PASS | authenticated: cannot open the backup schema |
| 15 | PASS | the denied calls deleted nothing |
| 16 | PASS | service_role → whish_confirm_payment behaves as granted (granted: false) |
| 17 | PASS | service_role: wipe with the right PIN is denied too |
| 18 | PASS | service_role: restore is owner-only |
| 19 | PASS | service_role: cannot open the backup schema |
| 20 | PASS | nothing deleted by the service_role attempts |
| 21 | PASS | app: customer login works |
| 22 | PASS | app: merchant login works |
| 23 | PASS | app: admin login works |
| 24 | PASS | app: phone check on the login screen works |
| 25 | PASS | app: the registration the app uses (6 arguments) runs |
| 26 | PASS | customer: 4 wrong then the right PIN logs in |
| 27 | PASS | customer: the right PIN reset the count (4 more wrong still not locked) |
| 28 | PASS | customer: the 5th wrong PIN still says wrong_pin |
| 29 | PASS | customer: then locked, even with the right PIN |
| 30 | PASS | customer: another account is not affected by that lock |
| 31 | PASS | customer: guessing an unknown number is limited too |
| 32 | PASS | admin: 5 wrong PINs lock the admin login |
| 33 | PASS | admin: changing upper/lower case does not escape the lock |
| 34 | PASS | admin: the other admin still logs in |
| 35 | PASS | October: merchant login locked after 5 wrong PINs |
| 36 | PASS | October: admin_reset_merchant_pin locked after 5 wrong admin PINs |
| 37 | PASS | customer: after the lock time the right PIN works again |
| 38 | PASS | customer: the successful login cleared the record |
| 39 | PASS | wipe: the lock of admin_reset_merchant_pin also stops the wipe (shared key), even for the owner |
| 40 | PASS | wipe: a wrong PIN is refused and deletes nothing |
| 41 | PASS | wipe: an unknown admin id is refused and deletes nothing |
| 42 | PASS | scope: merchants, customers and the tables pointing to them (12 tables) |
| 43 | PASS | owner wipe: answers ok with the copy stamp |
| 44 | PASS | owner wipe: the copy has every table with the same row counts |
| 45 | PASS | owner wipe: merchants and customers are empty |
| 46 | PASS | restore: every table is back, same rows and same checksum |
| 47 | PASS | restore: the test accounts log in again |
| 48 | PASS | restore: the copy is marked restored |
| 49 | PASS | restore: a second restore of the same copy is refused |
| 50 | PASS | restore: refused when the app was used after the wipe (no silent merge) |
| 51 | PASS | restore: works once the new rows are removed |
| 52 | PASS | restore: id counters continue after the restored rows (no duplicate ids later) |
| 53 | PASS | copies: a second wipe makes a new copy (different stamp) |
| 54 | PASS | copies: the earlier copies are all still there and unchanged |
| 55 | PASS | copies: the first copy still matches its saved checksum |
| 56 | PASS | integrity: a copy edited after the wipe is refused (content checksum, same row count) |
| 57 | PASS | integrity: once the copy is exactly as saved, it restores |
| 58 | PASS | records: a copy record cannot be deleted |
| 59 | PASS | records: a copy record cannot be rewritten |
| 60 | PASS | records: "restored" cannot be undone to restore twice |
| 61 | PASS | records: the list of copies cannot be emptied |
| 62 | PASS | delete copy: refused without the exact phrase, the copy stays |
| 63 | PASS | delete copy: with "DELETE COPY <stamp>" one table per copied table is dropped |
| 64 | PASS | delete copy: none of its tables remain |
| 65 | PASS | delete copy: the record stays, marked deleted |
| 66 | PASS | delete copy: a deleted copy cannot be restored |
| 67 | PASS | the v1.2 delete without confirmation no longer exists |
| 68 | PASS | copies: anon, authenticated and service_role cannot read any copy or the release log, even with widened default privileges |
| 69 | PASS | copies: every copy table has row-level security on |
| 70 | PASS | phase 0 self-check passes |

## ما لم أتمكن من التحقق منه (يتحقق منه تنفيذ Staging)

1. **نتيجة فحص Staging نفسها:** لم يصلني في هذه المحادثة جدول نتيجة `tp-security-status-check.sql` من Staging كملف، بل ملخصك فقط (أكتوبر مطبّق، Whish وهدية الزبون مغلقتان، المرحلة 1 غير موجودة). لذلك اختبرت ثلاث حالات بداية تغطي ما وصفته. أرسل لي CSV النتيجة إذا أردت مطابقة بنداً ببند.
2. **محتوى الدوال على Staging:** البصمات مأخوذة من نسخة Production التي نسختها في 2026-11-11. إذا كانت دوال Staging مختلفة، ستظهر في صفوف `pre` من فحص الحالة، وسيرفض ملف المرحلة 0 التنفيذ بلا أي تغيير.
3. **طريقة إغلاق Whish على Staging:** افترضت أن الإغلاق تم بسحب الصلاحيات. إذا كان بطريقة أخرى (مثلاً شرط داخل الدالة)، فالمرحلة 0 لا تلمس جسم دالة Whish أصلاً، وإنما الصلاحيات فقط.
4. **إعدادات خاصة بـ Supabase لا توجد محلياً:**
   - عضوية `postgres` في الأدوار anon وauthenticated، وهي لازمة للفحص السلوكي (مفترضة افتراضياً).
   - الـ schemas المكشوفة في PostgREST وGraphQL: `tp_backup` غير مكشوف، وحتى لو كُشف فلا صلاحية USAGE عليه.
   - صلاحيات افتراضية مخصّصة: جُرّبت الحالة الأسوأ.
   - ملكية الجداول: مفترض أنها لـ `postgres`.
5. **ملفات Storage:** الصور في Supabase Storage ليست جزءاً من نسخ `tp_backup`، لأن المسح أصلاً لا يحذفها. الشعارات المخزّنة كنص داخل قاعدة البيانات مشمولة.
6. **حجم البيانات الحقيقي:** حجم نسخة المسح يساوي حجم بيانات الزبائن والتجار، ولم يُقَس على Staging. هذا لا يؤثر على المرحلة 0 لأنها لا تنسخ شيئاً عند تطبيقها؛ النسخ يحصل فقط عند مسح ينفّذه المالك.
7. **اختبارات أكتوبر على Staging نفسه:** لم تُشغَّل هناك، لأنها تغيّر بيانات (لا تنتهي بـ ROLLBACK). طابقتها محلياً فقط: نفس المخرجات بدون المرحلة 0 ومعها.
8. **Whish الحقيقي:** لم يُجرَّب callback حقيقي. التحقق يكون في الخطوة 10 من `tp-security-phase0-RUNBOOK.md`.
