# Tripoli Points — المرحلة 0 v1.3.1: خطوات التنفيذ على Supabase Staging (النسخة النهائية)

| | |
|---|---|
| المشروع | Staging فقط: `axzlshimvtskkxknlwoz`. لا Production. |
| الملف | `2_tp-security-phase0-urgent.sql` من `Tripoli_Points_Phase0_v1.3.1_Staging_0b6dfb8.zip`، ولم يتغيّر بعدها. MD5 الملف: `140f1b066f00ffc1392c62648553bdb3` |
| المدة | حوالي 30 دقيقة مع النسخة الاحتياطية والفحوص. |
| البيانات | المرحلة 0 لا تكتب أي صف في الزبائن أو التجار أو المحافظ أو الشحن أو المعاملات أو النقاط أو الإعدادات. ملف البصمة يثبت ذلك قبل وبعد. |
| ممنوع | أي ملف `DANGEROUS`. المرحلة 1. البريد. QR. أي تغيير على Whish. |

## أ) بوابة النسخة الاحتياطية: لا تنفيذ قبل اكتمالها

ملف الرجوع **ليس نسخة احتياطية**: هو يفكّ الأقفال ويتحقق فقط. النسخة الاحتياطية الحقيقية تكون خارج قاعدة البيانات.

**أ1. اعرف خطة مشروع Staging.** من Dashboard → Settings → Billing (أو شارة الخطة أعلى الصفحة):
- **Pro أو أعلى:** يوجد نسخ يومي تلقائي (7 أيام في Pro). تأكد من Database → Backups أن آخر نسخة من **اليوم** أو أمس. انتبه: الاسترجاع من هنا يعيد **كل** المشروع إلى لحظة تلك النسخة، والمشروع يتوقف عن العمل أثناء الاسترجاع.
- **Free:** لا يوجد نسخ تلقائي قابل للاسترجاع. **أ2 إلزامية.**

**أ2. خذ نسخة يدوية لحظة التنفيذ (موصى بها في الحالتين)** على حاسوبك، عبر Supabase CLI مع Docker:
1. Dashboard → Connect → انسخ **Direct connection string**. إذا كانت شبكتك بلا IPv6، انسخ **Session pooler** بدلاً منه. ضع كلمة سر قاعدة البيانات مكان `[YOUR-PASSWORD]`. إذا نسيتها: Database → Settings → Reset.
2. في الطرفية:
   ```bash
   supabase db dump --remote="[CONNECTION_STRING]" -f staging_before_p0_roles.sql --role-only
   supabase db dump --remote="[CONNECTION_STRING]" -f staging_before_p0_schema.sql
   supabase db dump --remote="[CONNECTION_STRING]" -f staging_before_p0_data.sql --use-copy --data-only -x "storage.buckets_vectors" -x "storage.vector_indexes"
   ```
3. تأكد أن الملفات الثلاثة **ليست فارغة**، وأن `staging_before_p0_data.sql` يحتوي `COPY public.customers` و`COPY public.merchants` و`COPY public.topups`.
4. احفظ الملفات في مكان خاص. فيها أرقام هواتف الزبائن ورموزهم المشفّرة، فلا ترسلها لأحد.

**أ3. إثبات أن النسخة قابلة للاسترجاع** (موصى به). المقصود إمكانية الاسترجاع الفعلية، لا مجرد وجود الملف:
1. أنشئ مشروع Supabase مؤقتاً وفارغاً (Free يكفي)، وانسخ Direct connection string الخاص به.
2. استرجع إليه:
   ```bash
   psql --single-transaction --variable ON_ERROR_STOP=1 \
     --file staging_before_p0_roles.sql --file staging_before_p0_schema.sql \
     --command 'SET session_replication_role = replica' --file staging_before_p0_data.sql \
     --dbname "[TEMP_PROJECT_CONNECTION_STRING]"
   ```
3. شغّل `0_tp-data-fingerprint.sql` على المشروع المؤقت وعلى Staging. يجب أن تتطابق صفوف الجزء 1 والجزء 2.
4. احذف المشروع المؤقت بعد ذلك.

**أ4. ملفات Storage** (الصور) لا تدخل في أي نسخة من النسخ السابقة. المرحلة 0 لا تلمس Storage إطلاقاً، فلا حاجة لنسخها من أجل هذه المرحلة.

**البوابة:** تابع فقط إذا تحقق **أ1 (Pro مع نسخة حديثة)** أو **أ2**. والأفضل الاثنان مع أ3.

## ب) قبل التنفيذ مباشرة (قراءة فقط)

1. **اختر وقتاً هادئاً:** لا أحد يستعمل Staging خلال التنفيذ والفحوص، حتى تبقى البصمة نظيفة.
2. **فحص الحالة:** SQL Editor → New query → الصق `1_tp-security-status-check.sql` → Run → Download CSV باسم `status_before.csv`.
   - يجب أن يكون `VERDICT … = true`، وكل صفوف `pre` = `true`، وكل صفوف `oct` = `true`.
   - إذا لم يتحقق ذلك: **توقف**.
3. **بصمة البيانات:** New query → الصق `0_tp-data-fingerprint.sql` → Run → Download CSV باسم `fingerprint_before.csv`.

## ج) التنفيذ

4. New query → الصق `2_tp-security-phase0-urgent.sql` **كاملاً**، من `begin;` حتى `commit;` → Run **مرة واحدة**.
5. **النجاح:** لا يظهر `ERROR`، وتظهر هذه الرسائل:
   - `phase 0: N function(s) closed to the public key`
   - `phase 0 self-check: 52 behavioural checks passed` (العدد الفعلي حسب قاعدتك)
   - `phase 0 guard: no API key gained any access; N access(es) removed`
6. **الفشل:** أي `ERROR` أو `STOP` معناه أن الملف تراجع عن **كل شيء**، فهو transaction واحدة، ولم يتغيّر شيء. **لا تعِد المحاولة ولا تعدّل الملف.** انسخ الرسالة كاملة وأرسلها لي (راجع جدول الأخطاء).

## د) فحوصات ما بعد التنفيذ، بهذا الترتيب

| # | الفحص | كيف | المطلوب |
|---|---|---|---|
| 7 | الحماية فعّالة | `1_tp-security-status-check.sql` → `status_after.csv` | كل صفوف `p0` = `true` (صف «old register … overloads» قد يكون `true` أو فارغاً)، وكل صفوف `oct` = `true` كما قبل، وصفّا `info` الخاصان بـ Whish كما قبل (`false`). |
| 8 | الفحص السلوكي | `select * from public._phase0_selfcheck() where not ok;` | صفر صفوف. |
| 9 | اختبارات Staging | `3_tp-security-phase0-tests.sql` كاملاً | آخر جدول: `failed = 0`، وحوالي 70 اختباراً. الملف ينتهي بـ ROLLBACK. تحذير: يقفل الجداول بضع ثوانٍ. **لا يُشغَّل على Production.** |
| 10 | الرجوع الآمن لا يغيّر شيئاً | `4_tp-security-phase0-urgent-rollback.sql` **كما هو** | تظهر `no lock released (default)` و`all … behavioural checks pass`. |
| 11 | لا فقدان بيانات ولا تغيير أرصدة | `0_tp-data-fingerprint.sql` → `fingerprint_after.csv` | مطابق **تماماً** لـ `fingerprint_before.csv` في الجزأين 1 و2. الجزء 3 (أقفال PIN) قد يتغيّر فقط إذا جرّب أحد الدخول. |
| 12 | الدخول يعمل | من نسخة Staging من التطبيق | دخول زبون، دخول تاجر، دخول أدمن بـ PIN صحيح. |
| 13 | القفل يعمل (اختياري) | حساب زبون تجريبي: 5 رموز خاطئة ثم الرمز الصحيح | الصحيح يُرفض لمدة 15 دقيقة. لفكّه قبل ذلك: الملف 4 مع `v_keys := array['customer:<الرقم>']` وسبب في `v_reason`. |
| 14 | الشراء العادي | تاجر ينشئ معاملة وزبون يوافق | يعمل كما قبل. |
| 15 | زر «مسح كل البيانات» | لوحة الأدمن | **خطأ صلاحية، وهذا مقصود.** |

اختبارات أكتوبر لا تُشغَّل على Staging، لأنها تكتب بيانات ولا تنتهي بـ ROLLBACK. حماية أكتوبر يثبتها الفحص 7 (صفوف `oct`) والفحص 8، وقد طوبقت مخرجاتها محلياً بدون المرحلة 0 ومعها.

أرسل لي: `status_before.csv` و`status_after.csv` و`fingerprint_before.csv` و`fingerprint_after.csv` ونتيجة الفحص 9 ورسائل الخطوة 5.

## هـ) التعامل مع الأخطاء

| ما حصل | الحالة | ماذا تفعل |
|---|---|---|
| `STOP: … differs from the reviewed version` / `October … missing` / `self-check failed` / `would give access` / `would lose access` / `protection missing at the end` | لم يتغيّر شيء | أرسل الرسالة كاملة. لا تعديل ولا إعادة. |
| `permission denied to set role "anon"` | لم يتغيّر شيء | أرسل نتيجة صف `pre` الخاص بـ «act as anon». |
| انقطع الاتصال أثناء التشغيل | إما طُبّق كله أو لم يُطبَّق شيء | شغّل فحص الحالة (الخطوة 7). إذا كانت `p0` كلها `false` فلم يُطبَّق، ويمكن التشغيل مرة أخرى. إذا كانت `true` فقد طُبّق؛ تابع الفحوص. |
| الفحص 8 أو 9 فشل بعد تطبيق ناجح | الحماية مطبّقة | لا تشغّل أي ملف DANGEROUS. أرسل النتيجة. غالباً يكفي إعادة تشغيل الملف 2، فهو idempotent. |
| الفحص 11: البصمة تختلف | — | قارن الجداول المختلفة: إذا استُعمل Staging أثناء ذلك فهو السبب. إذا لم يُستعمل، أرسل الملفين فوراً **ولا تستعمل التطبيق**؛ القرار التالي هو الاسترجاع من النسخة (أ2/أ3). |
| الدخول لا يعمل لأحد (الفحص 12) | — | أرسل رسالة الخطأ من Console التطبيق ونتيجة الفحص 8. **لا تعِد فتح أي دالة.** |
| حساب حقيقي مقفول | — | انتظر 15 دقيقة، أو استعمل الملف 4 مع اسم الحساب بالضبط وسبب. |
| حسابات كثيرة مقفولة بخطأ | — | راسلني أولاً. الملف `DANGEROUS-unlock-all` يتطلّب عبارة تأكيد مكتوبة، ولا يُستعمل أثناء هجوم. |
| كارثة بيانات (لن يسببها هذا الملف) | — | الاسترجاع الكامل: من Database → Backups (Pro) أو من ملفات أ2 إلى مشروع جديد. القرار لك وبعد مراجعتي. |

## Whish

**القرار:** لا شحن إلكتروني حالياً.
- المرحلة 0 **لا تلمس** دوال Whish: لا تغيّر جسمها، ولا تعطي `service_role` أي صلاحية جديدة (الحارس النهائي يمنع ذلك)، وتبقى مغلقة على المفتاح العام.
- **لا اختبار Whish** ضمن هذه الخطوات.
- مسار الشحن اليدوي له ملاحظة أمنية مهمة، وهي منفصلة عن المرحلة 0 (راجع تقرير الجاهزية).
