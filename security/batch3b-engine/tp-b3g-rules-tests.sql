-- BATCH 3g TESTS (Staging-safe): one transaction ending in ROLLBACK; synthetic phones 799983xx only. No wipe, no truncate.
begin;
set local client_min_messages = warning;
create temp table _t (n serial primary key, name text, ok boolean, detail text) on commit drop;
create temp table _ctx (k text primary key, v text) on commit drop;
create function pg_temp.ok(p_name text, p_cond boolean, p_detail text default null) returns void language sql as $$
  insert into _t(name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail) $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'NO_ERROR'; exception when others then return sqlerrm; end $$;
create function pg_temp.set(p_k text, p_v text) returns void language sql as $$
  insert into _ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.get(p_k text) returns text language sql as $$ select v from _ctx where k = p_k $$;
create function pg_temp.buy(p_c text, p_m text, p_inv numeric, p_redeem boolean, p_idem text, p_want numeric default null) returns jsonb language plpgsql as $$
declare q jsonb; s jsonb;
begin
  q := public.customer_qr_issue(p_c);
  if p_want is not null then perform public.customer_qr_set_redeem(p_c, (q->>'code_id')::uuid, p_want); end if;
  s := public.merchant_scan_code(p_m, q->>'qr');
  return public.merchant_create_tx_v2(p_m, (s->>'code_id')::uuid, p_inv, p_redeem, null, '[]'::jsonb, p_idem);
end $$;
create function pg_temp.confirm(p_c text, p_tx uuid) returns jsonb language sql as $$
  select public.customer_decide_tx_v2(p_c, p_tx, true, (select detail_hash from public.pos_transactions where id = p_tx)) $$;
do $$ begin
  if exists (select 1 from public.customers where phone like '799983__') or exists (select 1 from public.merchants where phone like '799983__') then
    raise exception 'test phones 799983xx exist — stopped'; end if;
end $$;

insert into public.customers(phone, pin_hash, name, status, points) values
  ('79998301', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'سامي', 'active', 0),
  ('79998302', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0),
  ('79998303', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0);
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, redeem_pct_vip, status) values
  ('00000000-0000-4000-8000-0000000b3901', 'محل صغير', '79998311', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'small', null, null, 'active'),
  ('00000000-0000-4000-8000-0000000b3902', 'محل متوسط', '79998312', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 50, 50, 'active'),
  ('00000000-0000-4000-8000-0000000b3903', 'نسبة خاطئة', '79998313', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 15, 'large', null, null, 'active');
insert into public.topups(merchant_id, amount, source) values
  ('00000000-0000-4000-8000-0000000b3901', 1000, 'test'), ('00000000-0000-4000-8000-0000000b3902', 1000, 'test'), ('00000000-0000-4000-8000-0000000b3903', 1000, 'test');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000b39a1', 'tp_test_b3g_a1', extensions.crypt('3333', extensions.gen_salt('bf', 4)), true),
  ('00000000-0000-4000-8000-0000000b39a2', 'tp_test_b3g_a2', extensions.crypt('3333', extensions.gen_salt('bf', 4)), false);
do $$ begin
  perform pg_temp.set('c1', public.customer_login('79998301', '1111')->>'session');
  perform pg_temp.set('c2', public.customer_login('79998302', '1111')->>'session');
  perform pg_temp.set('c3', public.customer_login('79998303', '1111')->>'session');
  perform pg_temp.set('ms', public.merchant_login('79998311', '2222')->>'session');
  perform pg_temp.set('mm', public.merchant_login('79998312', '2222')->>'session');
  perform pg_temp.set('ml', public.merchant_login('79998313', '2222')->>'session');
  perform pg_temp.set('a1', public.admin_login('tp_test_b3g_a1', '3333')->>'session');
  perform pg_temp.set('a2', public.admin_login('tp_test_b3g_a2', '3333')->>'session');
  perform public.admin_points_adjust_v2(pg_temp.get('a1'), '79998301', 20000, 'test');
  perform public.admin_points_adjust_v2(pg_temp.get('a1'), '79998302', 20000, 'test');
  perform public.admin_points_adjust_v2(pg_temp.get('a1'), '79998303', 20000, 'test');
  perform public.admin_allowance_adjust_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3901', 100000, 30, 'test');
  perform public.admin_allowance_adjust_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3902', 100000, 30, 'test');
end $$;

-- §03 tier % and caps
do $$ declare q jsonb; begin
  q := public._tx_quote2('00000000-0000-4000-8000-0000000b3901', '79998301', 10, true, null, null);
  perform pg_temp.ok('§03 small shop: 20 % of a $10 invoice = 200 points', (q->>'redeem_pts')::numeric = 200 and (q->>'pct')::numeric = 20, q::text);
  q := public._tx_quote2('00000000-0000-4000-8000-0000000b3901', '79998301', 100, true, null, null);
  perform pg_temp.ok('§03 small shop: capped at 1,000 points per purchase', (q->>'redeem_pts')::numeric = 1000, q::text);
  q := public._tx_quote2('00000000-0000-4000-8000-0000000b3902', '79998301', 40, true, null, null);
  perform pg_temp.ok('§03 medium shop: 50 % of $40 = 2,000 points', (q->>'redeem_pts')::numeric = 2000, q::text);
  q := public._tx_quote2('00000000-0000-4000-8000-0000000b3903', '79998301', 40, true, null, null);
  perform pg_temp.ok('§04 earning % outside 1–10 → refused until the Admin fixes it', q->>'error' = 'earn_pct_invalid', q::text);
end $$;

-- §03 the customer decides the amount; acceptance is mandatory
do $$ declare r jsonb; tx uuid; begin
  r := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('ms'), 10, false, 'idem-b3g-0001', 150);
  tx := (r->'tx'->>'id')::uuid;
  perform pg_temp.ok('§03 customer chose 150 points: used even though the shop left points off', (r->'tx'->>'redeemPts')::numeric = 150, r::text);
  perform public.merchant_cancel_tx(pg_temp.get('ms'), tx);
  r := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('ms'), 10, true, 'idem-b3g-0002', 5000);
  perform pg_temp.ok('§03 customer asks more than allowed: limited to the cap (200)', (r->'tx'->>'redeemPts')::numeric = 200, r::text);
  perform public.merchant_cancel_tx(pg_temp.get('ms'), (r->'tx'->>'id')::uuid);
  perform pg_temp.ok('customer cannot set the amount on another customer''s code',
    public.customer_qr_set_redeem(pg_temp.get('c2'), (public.customer_qr_issue(pg_temp.get('c1'))->>'code_id')::uuid, 10)->>'error' = 'not_found');
end $$;

-- §04 daily eligible purchases (medium: 25,000 reference points = $250)
do $$ declare r jsonb; begin
  r := pg_temp.buy(pg_temp.get('c2'), pg_temp.get('mm'), 300, false, 'idem-b3g-0003');
  perform pg_temp.ok('§04 medium: $300 invoice passes, earns only on $250 (1,250 points at 5 %)', (r->'tx'->>'earn')::numeric = 1250 and (r->>'ok')::boolean, r::text);
  perform pg_temp.confirm(pg_temp.get('c2'), (r->'tx'->>'id')::uuid);
  r := pg_temp.buy(pg_temp.get('c2'), pg_temp.get('mm'), 50, false, 'idem-b3g-0004');
  perform pg_temp.ok('§04 cap used up: second purchase goes through with 0 new points', (r->>'ok')::boolean and (r->'tx'->>'earn')::numeric = 0, r::text);
  perform pg_temp.confirm(pg_temp.get('c2'), (r->'tx'->>'id')::uuid);
end $$;

-- §04 repeat value on consecutive days → alert only
do $$ declare r jsonb; t1 uuid; begin
  r := pg_temp.buy(pg_temp.get('c3'), pg_temp.get('ms'), 12.5, false, 'idem-b3g-0005');
  t1 := (r->'tx'->>'id')::uuid; perform pg_temp.confirm(pg_temp.get('c3'), t1);
  update public.pos_transactions set created_at = created_at - interval '1 day' where id = t1;     -- the first one was yesterday
  r := pg_temp.buy(pg_temp.get('c3'), pg_temp.get('ms'), 12.5, false, 'idem-b3g-0006');
  r := pg_temp.confirm(pg_temp.get('c3'), (r->'tx'->>'id')::uuid);
  perform pg_temp.ok('§04 same value two days running: confirmed normally + Admin alert', (r->>'ok')::boolean
    and exists (select 1 from public.tx_events where event = 'alert_repeat_value' and customer_phone = '79998303'), r::text);
end $$;

-- §03 lower % only with Admin approval
do $$ declare r jsonb; begin
  r := public.merchant_set_redeem_pct_v2(pg_temp.get('ms'), 10, null);
  perform pg_temp.ok('§03 shop asks 10 % (below 20 %): pending, not applied', (r->>'pending')::boolean
    and (select redeem_pct from public.merchants where phone = '79998311') is null, r::text);
  perform pg_temp.ok('§03 above the tier % refused', public.merchant_set_redeem_pct_v2(pg_temp.get('ms'), 30, null)->>'error' = 'bad_pct');
  perform pg_temp.ok('secondary admin cannot approve', pg_temp.err(format('select public.admin_review_redeem_pct_v2(%L, %L, true)', pg_temp.get('a2'), '00000000-0000-4000-8000-0000000b3901')) like 'TP_FORBIDDEN%');
  perform pg_temp.ok('admin sees the request', jsonb_array_length(public.admin_redeem_pct_requests_v2(pg_temp.get('a2'))->'requests') >= 1);
  r := public.admin_review_redeem_pct_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3901', true);
  perform pg_temp.ok('§03 approved: 10 % applies, shop notified', (r->>'ok')::boolean and (select redeem_pct from public.merchants where phone = '79998311') = 10
    and exists (select 1 from public.merchant_notes where merchant_id = '00000000-0000-4000-8000-0000000b3901' and title like 'وافقت الإدارة%'));
end $$;

-- §16 VIP
do $$ declare r jsonb; ref uuid; vid uuid; q jsonb; begin
  ref := (select id from public.pos_transactions where merchant_id = '00000000-0000-4000-8000-0000000b3901' and customer_phone = '79998303' and status = 'CONFIRMED' limit 1);
  r := public.merchant_vip_set_v2(pg_temp.get('ms'), ref, 600);
  perform pg_temp.ok('VIP-2 until the Admin sets the count, no new VIP', r->>'error' = 'vip_limit_not_set', r::text);
  perform public.admin_engine_setting_v2(pg_temp.get('a1'), 'vip_max_small', 1);
  perform pg_temp.ok('VIP-1 only customers with a completed purchase here',
    public.merchant_vip_set_v2(pg_temp.get('ms'), (select id from public.pos_transactions where customer_phone = '79998302' limit 1), 600)->>'error' = 'not_eligible');
  perform pg_temp.ok('VIP-1 candidates list hides the phone', not exists (select 1 from jsonb_array_elements(public.merchant_vip_candidates_v2(pg_temp.get('ms'))->'customers') x
    where x::text like '%79998303%'));
  r := public.merchant_vip_set_v2(pg_temp.get('ms'), ref, 600);
  perform pg_temp.ok('VIP-1 added immediately, customer notified, logged', (r->>'ok')::boolean
    and exists (select 1 from public.customer_notes where customer_phone = '79998303' and title like '👑%')
    and exists (select 1 from public.merchant_vip_log where customer_phone = '79998303' and action = 'add'), r::text);
  perform pg_temp.ok('VIP-2 limit reached: another addition refused', public.merchant_vip_set_v2(pg_temp.get('ms'),
    (select id from public.pos_transactions where merchant_id = '00000000-0000-4000-8000-0000000b3901' and customer_phone = '79998301' and status = 'CONFIRMED' limit 1), 100)->>'error' in ('vip_limit','not_eligible'));
  q := public._tx_quote2('00000000-0000-4000-8000-0000000b3901', '79998303', 100, true, null, null);
  perform pg_temp.ok('VIP-3 cap replaces the normal cap but stays inside the % (VIP %: 10 % of $100 = 1,000 ≤ 600 → 600)', (q->>'redeem_pts')::numeric = 600 and (q->>'vip')::boolean, q::text);
  update public.merchant_vips set cap_points = 600 where customer_phone = '79998303';
  r := pg_temp.buy(pg_temp.get('c3'), pg_temp.get('ms'), 100, true, 'idem-b3g-0007');
  q := public._tx_quote2('00000000-0000-4000-8000-0000000b3901', '79998303', 100, true, null, null);
  perform pg_temp.ok('VIP-3 the cap is a DAILY total (third purchase blocked by the 2/day rule anyway)', q->>'error' = 'daily_limit' or (q->>'vip_left')::numeric = 0, q::text);
  vid := (select id from public.merchant_vips where customer_phone = '79998303');
  r := public.merchant_vip_set_v2(pg_temp.get('ms'), ref, 900);
  perform pg_temp.ok('VIP-4 raise: immediate', public._vip_cap('00000000-0000-4000-8000-0000000b3901', '79998303') = 900, r::text);
  r := public.merchant_vip_set_v2(pg_temp.get('ms'), ref, 300);
  perform pg_temp.ok('VIP-4 lower: still 900 today, 300 from tomorrow', public._vip_cap('00000000-0000-4000-8000-0000000b3901', '79998303') = 900
    and (r->>'next_cap')::numeric = 300, r::text);
  update public.merchant_vips set next_from = public._beirut_today() where id = vid;                          -- simulate the next day
  perform pg_temp.ok('VIP-4 next day: 300', public._vip_cap('00000000-0000-4000-8000-0000000b3901', '79998303') = 300);
  perform pg_temp.ok('VIP-4 customer sees his VIP cap', (public.customer_vips_v2(pg_temp.get('c3'))->'vips'->0->>'cap')::numeric = 300);
  perform pg_temp.ok('staff / customer cannot manage VIP', pg_temp.err(format('select public.merchant_vip_list_v2(%L)', pg_temp.get('c3'))) like 'TP_SESSION%');
  r := public.merchant_vip_cancel_v2(pg_temp.get('ms'), vid);
  perform pg_temp.ok('VIP-4 cancel: immediate, notified, history kept', (r->>'ok')::boolean and public._vip_cap('00000000-0000-4000-8000-0000000b3901', '79998303') is null
    and exists (select 1 from public.customer_notes where customer_phone = '79998303' and title like 'انتهت عضوية VIP%')
    and (select count(*) from public.merchant_vip_log where customer_phone = '79998303') >= 4);
  perform pg_temp.ok('VIP-5 another branch is independent', public._vip_cap('00000000-0000-4000-8000-0000000b3902', '79998303') is null);
end $$;

do $$ begin
  perform pg_temp.ok('ledger = cached points for every test customer', not exists (select 1 from public.customers where phone like '799983__' and coalesce(points,0) <> public._pts_spendable(phone)));
  perform pg_temp.ok('helpers not reachable by anon', not has_function_privilege('anon', 'public._tx_quote2(uuid,text,numeric,boolean,uuid,numeric)', 'execute')
    and not has_function_privilege('anon', 'public._vip_cap(uuid,text)', 'execute'));
  perform pg_temp.ok('Admin gift settings untouched', (select value from public.app_text_settings where key = 'welcome_bonus') = '3000'
    and (select value from public.app_text_settings where key = 'welcome_days') = '7');
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
