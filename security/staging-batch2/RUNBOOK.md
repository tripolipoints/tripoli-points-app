# Staging — الدفعة 2: أساسات الأمان (H1 + C-1 + إعدادات مؤقتة)

**المشروع:** Staging فقط (`axzlshimvtskkxknlwoz`). **لا Production.**

**المدة:** حوالي 10 دقائق.

**طريقة التشغيل:** كل ملف يُلصق في SQL Editor ← New query ← Run.

**ما جُرّب محلياً:** نسخة من بنية Staging الحقيقية، والمرحلة 0 مطبّقة عليها. النتائج:

| الفحص | النتيجة |
|---|---|
| H1 | 34/34 |
| C-1 | 9/9 |
| الفحص الذاتي للمرحلة 0 بعدهما | 0 فشل |
| المحرر لا يضيف أي أمر RLS للملفات 2 إلى 5 | ✓ |

## الخطوات

| # | الملف | المتوقع |
|---|---|---|
| 1 | `1_fingerprint.sql`، ثم Download CSV باسم `fp_before.csv` | جدول البصمة |
| 2 | `2_h1-check.sql` | صف `VERDICT … = false` (ما زال مفتوحاً)، والدوال العشر موجودة (`ex = true`) |
| 3 | `3_staging-settings.sql` | رسالة `staging settings: rate_pts_per_usd=100, redeem_cap_pct=70 (legacy), welcome_bonus=3000, welcome_days=7` |
| 4 | `4_h1.sql` | `H1 applied: 10 function(s) closed …` |
| 5 | `5_c1.sql` | `C-1 applied: expired welcome gifts are no longer spendable; no balance changed` |
| 6 | `2_h1-check.sql` مرة ثانية | `VERDICT … = true` |
| 7 | `6_h1-tests.sql` | خطأ أحمر نصّه `H1_TESTS passed=34 failed=0`. هذه هي النتيجة، والملف يلغي كل ما كتبه |
| 8 | `7_c1-tests.sql` | `C1_TESTS passed=9 failed=0` |
| 9 | `select count(*) from public._phase0_selfcheck() where not ok;` | `0` |
| 10 | `1_fingerprint.sql` مرة ثانية، ثم CSV باسم `fp_after.csv` | مطابق لـ `fp_before.csv` |
| 11 | من موقع Staging | راجع البنود الستة تحت الجدول |

**بنود الخطوة 11 (موقع Staging):**
1. تسجيل زبون جديد بـ PIN.
2. دخول، ثم «نسيت رمز الحماية» تفتح شاشة الدعم.
3. دخول تاجر.
4. عملية شراء يؤكدها الزبون، والنقاط تُضاف مرة واحدة.
5. طلب شحن يدوي من التاجر.
6. دخول أدمن. زر «اعتماد» يُظهر خطأ صلاحية، وهذا مقصود.

**إذا ظهر `STOP` في أي ملف:**
- لم يتغيّر شيء، لأن كل ملف transaction واحدة.
- أرسل لي الرسالة.

## الرجوع

| الملف | ماذا يرجّع |
|---|---|
| `R4_h1-rollback.sql` | يعيد فتح الدوال العشر |
| `R5_c1-rollback.sql` | يعيد السطرين الأصليين |
| `R3_settings-rollback.sql` | يحذف الإعدادات الأربعة |

**ملاحظات:**
- لا شيء في هذه الدفعة يحذف بيانات.
- رجوع Netlify لا يرجّع أي تغيير في قاعدة البيانات.
