# بنية Staging محفوظة · 2026-11-11 (قبل المرحلة 0)

**الملف:** `staging_structure_2026-11-11.sql`

- **المصدر:** CSV من تصدير `tp-structure-export.sql` v3.1، شغّله صاحب المشروع على Staging (`axzlshimvtskkxknlwoz`) الساعة 21:01 UTC.
- **التحقق من سلامة التحميل:** 1330 أمراً في 34 صفاً، وبصمة md5 مطابقة لصف التحقق، فالتحميل كامل ولم يتغيّر.
- **بصمة الملف:** MD5 `48e5260b43a8cf66f80b021e99b5d715`، وطوله 3012 سطراً.

## ما يحتويه

- **الامتدادات:** pgcrypto، uuid-ossp، pg_stat_statements، supabase_vault.
- **27 جدولاً:**
  - 22 في `public`، منها 4 غير موجودة في Production: `"user"` و`transactions` و`topup_requests` و`wallet_orders`.
  - 5 في schema اسمها **`tp_dev`**، وهي غير موثّقة في أي ملف على GitHub: `accounts` و`demo_balances` و`demo_transactions` و`pin_attempts` و`requests`.
- **94 دالة بكودها الكامل:** منها 4 دوال `tp_dev_*` تستعمل Supabase Auth (`auth.uid()`)، ولا يستطيع `anon` استدعاءها.
- **بقية البنية:** القيود، الفهارس، الـ Triggers، تشغيل RLS على كل جدول، و813 أمر صلاحيات.
- **صفوف الإعدادات:**
  - `categories`: تصنيفات تجريبية.
  - `app_settings` و`app_text_settings`: **فارغان على Staging**.
- **سياسات RLS:** لا يوجد أي منها، لا على جداول التطبيق ولا على Storage. RLS مفعّل بلا سياسات، والوصول يمر عبر الدوال فقط.
- **Storage buckets:** لا يوجد أي منها على Staging (`buckets=0`).

## ما لا يحتويه

- بيانات الزبائن والتجار والمحافظ والمعاملات والنقاط.
- حسابات الأدمن ورموز PIN.
- كلمات السر والمفاتيح. فُحص الملف ولم يُعثر على JWT ولا مفاتيح API ولا bcrypt.
- كود Edge Functions وإعدادات Auth وAPI. هذه خارج قاعدة البيانات، وتُحفظ من Dashboard.

## إعادة البناء

- **على Supabase:** على مشروع فارغ، يشغَّل الملف كما هو.
- **محلياً (PostgreSQL 16):**
  1. يُشغَّل أولاً `../local-test/supabase_stub_for_local_rebuild.sql`، وهو بديل بسيط عن `auth.users` و`auth.uid()` وstorage.
  2. يُحذف من الملف سطر `supabase_vault`، لأنه امتداد خاص بـ Supabase.
  3. تُحذف منه 72 صلاحية من نوع `MAINTAIN`، لأنها موجودة في PostgreSQL 17 فقط.

## نتيجة الاختبار المحلي

- **إعادة البناء:** نجحت بصفر أخطاء.
- **مقارنة مع الأصل:** إعادة التصدير من القاعدة المبنية تطابق تصدير Staging سطراً بسطر، ما عدا أوقات `created_at` في التصنيفات، وهي نفس اللحظة بمنطقة زمنية مختلفة.
- **فحص الحالة على القاعدة المبنية:** يعطي نفس أرقام Staging: 68 من 94 دالة مفتوحة، وWhish `false`، و`VERDICT = true`.
