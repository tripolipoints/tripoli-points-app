-- synthetic fixtures for the batch 3 end-to-end run (local copy only)
insert into public.merchants(id, name, phone, pin_hash, status, pct, tier, redeem_pct, cat, lat, lng, area, page_enabled)
values ('11111111-1111-4111-8111-1111111b3b11', 'مطعم اختبار B3', '79990111', extensions.crypt('1111', extensions.gen_salt('bf')), 'active', 5, 'medium', 5, 'cafe', 34.4365, 35.835, '', true);
insert into public.topups(merchant_id, amount, source, ref) values ('11111111-1111-4111-8111-1111111b3b11', 50, 'admin', 'SEED');
insert into public.admin_users(username, pin_hash, is_primary) values ('b3admin', extensions.crypt('2468', extensions.gen_salt('bf')), true);
insert into public.customers(phone, pin_hash, name, status, points) values ('79990333', extensions.crypt('2468', extensions.gen_salt('bf')), 'زبون جديد', 'active', 100);
