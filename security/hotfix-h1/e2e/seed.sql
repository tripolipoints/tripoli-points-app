-- synthetic fixtures for the end-to-end run (local replica only)
insert into public.merchants(id, name, phone, pin_hash, status, pct, tier, redeem_pct, cat, lat, lng, area, page_enabled)
values ('11111111-1111-4111-8111-111111111111', 'محل اختبار H1', '76000111', extensions.crypt('1111', extensions.gen_salt('bf')), 'active', 5, 'small', 5, 'cafe', 34.4365, 35.835, '', true);
insert into public.topups(merchant_id, amount, source, ref) values ('11111111-1111-4111-8111-111111111111', 50, 'admin', 'SEED');
insert into public.admin_users(username, pin_hash, is_primary) values ('h1admin', extensions.crypt('2468', extensions.gen_salt('bf')), true);
insert into public.topup_orders(id, merchant_id, amount, points, ref, status, method)
values ('22222222-2222-4222-8222-222222222222', '11111111-1111-4111-8111-111111111111', 5, 500, 'TP-E2E001', 'REVIEW', 'manual');
insert into public.app_settings(key, value) values ('rate_pts_per_usd', 100), ('redeem_cap_pct', 70) on conflict (key) do nothing;
insert into public.app_text_settings(key, value) values ('welcome_bonus', '3000'), ('welcome_days', '7') on conflict (key) do nothing;
