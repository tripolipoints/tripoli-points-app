-- BATCH 3i TESTS (Staging-safe): one transaction ending in ROLLBACK; synthetic phones 799985xx. No wipe / truncate.
-- sub_enforce is switched on ONLY inside this rolled-back run.
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
create function pg_temp.listed(p_mid uuid) returns boolean language sql as $$
  select exists (select 1 from jsonb_array_elements(public.list_merchants()) x where (x->>'id')::uuid = p_mid) $$;
do $$ begin
  if exists (select 1 from public.customers where phone like '799985__') or exists (select 1 from public.merchants where phone like '799985__') then raise exception 'test phones exist'; end if;
end $$;
insert into public.customers(phone, pin_hash, name, status, points) values
  ('79998501', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'رامي', 'active', 0),
  ('79998502', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0);
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
  ('00000000-0000-4000-8000-0000000b3501', 'فرع الدوام', '79998511', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 50, 'active'),
  ('00000000-0000-4000-8000-0000000b3502', 'فرع الإغلاق', '79998512', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 50, 'active');
insert into public.topups(merchant_id, amount, source) values ('00000000-0000-4000-8000-0000000b3501', 100, 'test'), ('00000000-0000-4000-8000-0000000b3502', 100, 'test');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000b35a1', 'tp_test_b3i_a1', extensions.crypt('3333', extensions.gen_salt('bf', 4)), true);
do $$ begin
  perform pg_temp.set('c1', public.customer_login('79998501', '1111')->>'session');
  perform pg_temp.set('c2', public.customer_login('79998502', '1111')->>'session');
  perform pg_temp.set('m1', public.merchant_login('79998511', '2222')->>'session');
  perform pg_temp.set('m2', public.merchant_login('79998512', '2222')->>'session');
  perform pg_temp.set('a1', public.admin_login('tp_test_b3i_a1', '3333')->>'session');
end $$;

-- §05 grace (switch on only here)
do $$ declare st jsonb; begin
  perform pg_temp.ok('§05 switch off (Staging default): every active shop listed', public._setting('sub_enforce', 0) = 0 and pg_temp.listed('00000000-0000-4000-8000-0000000b3501'));
  update public.app_settings set value = 1 where key = 'sub_enforce';
  perform pg_temp.ok('§05 switch on: a shop with no subscription and no card balance is hidden, and cannot sell',
    not pg_temp.listed('00000000-0000-4000-8000-0000000b3501') and public._tx_quote2('00000000-0000-4000-8000-0000000b3501', '79998501', 10, false, null, null)->>'error' = 'shop_closed');
  insert into public.merchant_subscriptions(merchant_id, plan_code, period_start, period_end) values ('00000000-0000-4000-8000-0000000b3501', 'x', now() - interval '40 days', now() - interval '9 days');
  perform pg_temp.ok('§05 ended 9 days ago: still listed (10-day grace)', pg_temp.listed('00000000-0000-4000-8000-0000000b3501'));
  update public.merchant_subscriptions set period_end = now() - interval '11 days' where merchant_id = '00000000-0000-4000-8000-0000000b3501';
  perform pg_temp.ok('§05 ended 11 days ago: hidden', not pg_temp.listed('00000000-0000-4000-8000-0000000b3501'));
  perform public._allow_add('00000000-0000-4000-8000-0000000b3501', 500, 'package', now(), now() + interval '30 days', null, 'p', null, null, null, 'test');
  perform pg_temp.ok('§05 a valid card balance brings it back', pg_temp.listed('00000000-0000-4000-8000-0000000b3501'));
  st := public.merchant_sub_status_v2(pg_temp.get('m1'));
  perform pg_temp.ok('§05 the shop sees its status (enforced, grace date, card balance)', (st->>'enforced')::boolean and (st->>'card_balance')::numeric = 500 and st->>'grace_until' is not null, st::text);
  update public.app_settings set value = 0 where key = 'sub_enforce';
end $$;

-- §14 hours and temporary closure
do $$ declare r jsonb; dow int := extract(dow from now() at time zone 'Asia/Beirut')::int; lt time := (now() at time zone 'Asia/Beirut')::time; cid bigint; begin
  perform pg_temp.ok('§14 no hours entered = open', public._shop_state('00000000-0000-4000-8000-0000000b3501') = 'open');
  r := public.merchant_hours_set_v2(pg_temp.get('m1'), jsonb_build_array(jsonb_build_object('dow', dow, 'opens', to_char(lt + interval '2 hours', 'HH24:MI'), 'closes', to_char(lt + interval '3 hours', 'HH24:MI'))));
  perform pg_temp.ok('§14 outside today''s hours: closed, no new points purchase', public._shop_state('00000000-0000-4000-8000-0000000b3501') = 'closed_hours'
    and public._tx_quote2('00000000-0000-4000-8000-0000000b3501', '79998501', 10, false, null, null)->>'error' = 'shop_closed', r::text);
  r := public.merchant_hours_set_v2(pg_temp.get('m1'), jsonb_build_array(jsonb_build_object('dow', dow, 'opens', to_char(lt - interval '1 hour', 'HH24:MI'), 'closes', to_char(lt + interval '1 hour', 'HH24:MI'))));
  perform pg_temp.ok('§14 inside today''s hours: open', public._shop_state('00000000-0000-4000-8000-0000000b3501') = 'open', r::text);
  perform pg_temp.ok('§14 bad hours refused', public.merchant_hours_set_v2(pg_temp.get('m1'), '[{"dow":9,"opens":"25:00","closes":"10:00"}]')->>'error' = 'bad_hours');
  r := public.merchant_closure_start_v2(pg_temp.get('m1'), null, null, 'صيانة'); cid := (r->>'id')::bigint;
  perform pg_temp.ok('§14 temporary closure: «مغلق مؤقتاً», still listed (pin + page), no new points purchase',
    public._shop_state('00000000-0000-4000-8000-0000000b3501') = 'closed_temp' and pg_temp.listed('00000000-0000-4000-8000-0000000b3501')
    and (select x->>'open_state' from jsonb_array_elements(public.list_merchants()) x where (x->>'id')::uuid = '00000000-0000-4000-8000-0000000b3501') = 'closed_temp'
    and public._tx_quote2('00000000-0000-4000-8000-0000000b3501', '79998501', 10, false, null, null)->>'error' = 'shop_closed', r::text);
  perform pg_temp.ok('§14 public page shows the state and hours', public.shop_hours_public('00000000-0000-4000-8000-0000000b3501')->>'state' = 'closed_temp');
  perform public.merchant_closure_end_v2(pg_temp.get('m1'), cid);
  perform pg_temp.ok('§14 reopened', public._shop_state('00000000-0000-4000-8000-0000000b3501') = 'open');
  perform pg_temp.ok('§14 staff cannot change hours (owner only)', pg_temp.err(format('select public.merchant_closure_start_v2(%L, null, null, null)', pg_temp.get('c1'))) like 'TP_SESSION%');
  r := public.report_shop_info_v2(pg_temp.get('c1'), '00000000-0000-4000-8000-0000000b3501', 'الدوام غير صحيح');
  perform pg_temp.ok('§14 a customer reports wrong hours → Admin feed', (r->>'ok')::boolean and exists (select 1 from jsonb_array_elements(public.admin_security_feed_v2(pg_temp.get('a1'), 50)->'events') e where e->>'event' = 'alert_shop_info'));
end $$;

-- §15 permanent closure
do $$ declare r jsonb; begin
  perform public._allow_add('00000000-0000-4000-8000-0000000b3502', 1000, 'adjust', now(), now() + interval '30 days', null, null, null, null, null, 'test');
  perform public.admin_points_adjust_v2(pg_temp.get('a1'), '79998502', 500, 'test');
  perform pg_temp.ok('§15 wrong PIN refused', public.merchant_close_shop_request_v2(pg_temp.get('m2'), '0000')->>'error' = 'wrong_pin');
  r := public.merchant_close_shop_request_v2(pg_temp.get('m2'), '2222');
  perform pg_temp.ok('§15 owner asks for permanent closure → Admin alert', (r->>'ok')::boolean and exists (select 1 from public.tx_events where event = 'alert_closure_request' and merchant_id = '00000000-0000-4000-8000-0000000b3502'));
  r := public.admin_closure_review_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3502');
  perform pg_temp.ok('§15 Admin review shows balances / complaints / purchases', (r->>'allowance_remaining')::numeric = 1000 and r ? 'open_reports', r::text);
  r := public.admin_close_shop_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3502', true, 'إغلاق نهائي بطلب المالك');
  perform pg_temp.ok('§15 closed: hidden from the map, no purchases, owner logged out, records kept',
    (r->>'closed')::boolean and not pg_temp.listed('00000000-0000-4000-8000-0000000b3502')
    and public._shop_state('00000000-0000-4000-8000-0000000b3502') = 'closed_final'
    and pg_temp.err(format('select public.merchant_me_v2(%L)', pg_temp.get('m2'))) like 'TP_SESSION%'
    and exists (select 1 from public.merchants where id = '00000000-0000-4000-8000-0000000b3502') and public._allow_remaining('00000000-0000-4000-8000-0000000b3502') = 1000, r::text);
  perform pg_temp.ok('§15 customers keep their points (no transfer)', public._pts_spendable('79998502') = 500);
end $$;

-- account deletion + marketing consent
do $$ declare r jsonb; begin
  r := public.customer_privacy_v2(pg_temp.get('c1'));
  perform pg_temp.ok('privacy: marketing consent off by default, separate from the terms', (r->>'marketing_consent')::boolean = false, r::text);
  r := public.customer_set_marketing_v2(pg_temp.get('c1'), true);
  perform pg_temp.ok('privacy: consent on, with its time; can be withdrawn', (r->>'marketing_consent')::boolean
    and (select marketing_consent_at is not null from public.customers where phone = '79998501')
    and (public.customer_set_marketing_v2(pg_temp.get('c1'), false)->>'marketing_consent')::boolean = false);
  perform public.admin_points_adjust_v2(pg_temp.get('a1'), '79998501', 1000, 'test');
  perform pg_temp.ok('deletion: wrong PIN refused', public.customer_delete_request_v2(pg_temp.get('c1'), '0000')->>'error' = 'wrong_pin');
  r := public.customer_delete_request_v2(pg_temp.get('c1'), '1111');
  perform pg_temp.ok('deletion: request accepted, 7 days to cancel, shows the points', (r->>'ok')::boolean and (r->>'effective_in_days')::int = 7 and (r->>'points')::numeric = 1000, r::text);
  r := public.customer_delete_cancel_v2(pg_temp.get('c1'));
  perform pg_temp.ok('deletion: cancel within the 7 days', (r->>'ok')::boolean and (select deletion_requested_at is null from public.customers where phone = '79998501'), r::text);
  perform public.customer_delete_request_v2(pg_temp.get('c1'), '1111');
  update public.customers set deletion_requested_at = now() - interval '8 days' where phone = '79998501';
  r := public._process_account_closures();
  perform pg_temp.ok('deletion: after 7 days the account is disabled, sessions end, points kept',
    (select status = 'frozen' and deactivated_at is not null from public.customers where phone = '79998501')
    and pg_temp.err(format('select public.customer_profile_v2(%L)', pg_temp.get('c1'))) like 'TP_SESSION%'
    and public._pts_spendable('79998501') = 1000, r::text);
  perform pg_temp.ok('deletion: a disabled account cannot log in', public.customer_login('79998501', '1111')->>'reason' = 'frozen');
  r := public.admin_customer_reactivate_v2(pg_temp.get('a1'), '79998501', 'تحقق من الهوية');
  perform pg_temp.ok('deletion: reactivated within 3 months keeps only still-valid points', (r->>'ok')::boolean and (r->>'points')::numeric = 1000, r::text);
  perform public.customer_delete_request_v2(public.customer_login('79998501', '1111')->>'session', '1111');
  update public.customers set deletion_requested_at = now() - interval '100 days' where phone = '79998501';
  perform public._process_account_closures();
  update public.customers set deactivated_at = now() - interval '3 months 1 day' where phone = '79998501';
  r := public._process_account_closures();
  perform pg_temp.ok('deletion: after 3 months remaining points are cancelled (recorded) and personal data removed',
    public._pts_spendable('79998501') = 0 and (select name = 'حساب محذوف' and pin_hash is null and data_removed_at is not null from public.customers where phone = '79998501')
    and exists (select 1 from public.point_movements where customer_phone = '79998501' and actor = 'account_closed'), r::text);
  perform pg_temp.ok('deletion: closed account cannot be reactivated', public.admin_customer_reactivate_v2(pg_temp.get('a1'), '79998501', 'محاولة')->>'error' = 'closed');
  perform pg_temp.ok('Admin job runs everything', (public.admin_run_jobs_v2(pg_temp.get('a1'))->>'ok')::boolean);
  perform pg_temp.ok('ledger = cached points; gift settings untouched',
    not exists (select 1 from public.customers where phone like '799985__' and coalesce(points,0) <> public._pts_spendable(phone))
    and (select value from public.app_text_settings where key = 'welcome_bonus') = '3000' and (select value from public.app_text_settings where key = 'welcome_days') = '7');
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
