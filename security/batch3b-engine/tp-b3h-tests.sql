-- BATCH 3h TESTS (Staging-safe): one transaction ending in ROLLBACK; synthetic phones 799984xx. No wipe / truncate.
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
create function pg_temp.buy(p_c text, p_m text, p_inv numeric, p_redeem boolean, p_idem text) returns uuid language plpgsql as $$
declare q jsonb; s jsonb; r jsonb; tx uuid;
begin
  q := public.customer_qr_issue(p_c); s := public.merchant_scan_code(p_m, q->>'qr');
  r := public.merchant_create_tx_v2(p_m, (s->>'code_id')::uuid, p_inv, p_redeem, null, '[]'::jsonb, p_idem); tx := (r->'tx'->>'id')::uuid;
  perform public.customer_decide_tx_v2(p_c, tx, true, (select detail_hash from public.pos_transactions where id = tx));
  return tx;
end $$;
create function pg_temp.ledger_ok() returns boolean language sql as $$
  select not exists (select 1 from public.customers c where c.phone like '799984__' and coalesce(c.points,0) <> public._pts_spendable(c.phone))
     and not exists (select 1 from public.point_batches b where b.customer_phone like '799984__'
                      and b.remaining <> coalesce((select sum(m.delta) from public.point_movements m where m.batch_id = b.id), 0))
     and not exists (select 1 from public.allowance_grants g where g.merchant_id = '00000000-0000-4000-8000-0000000b3401'
                      and g.remaining <> coalesce((select sum(m.delta) from public.allowance_movements m where m.grant_id = g.id), 0)) $$;
do $$ begin
  if exists (select 1 from public.customers where phone like '799984__') or exists (select 1 from public.merchants where phone like '799984__') then raise exception 'test phones exist'; end if;
end $$;
insert into public.customers(phone, pin_hash, name, status, points) values
  ('79998401', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0),
  ('79998402', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0);
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
  ('00000000-0000-4000-8000-0000000b3401', 'فرع الإرجاع', '79998411', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 10, 'medium', 50, 'active'),
  ('00000000-0000-4000-8000-0000000b3402', 'فرع آخر', '79998412', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 10, 'medium', 50, 'active');
insert into public.topups(merchant_id, amount, source) values ('00000000-0000-4000-8000-0000000b3401', 1000, 'test'), ('00000000-0000-4000-8000-0000000b3402', 1000, 'test');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000b34a1', 'tp_test_b3h_a1', extensions.crypt('3333', extensions.gen_salt('bf', 4)), true),
  ('00000000-0000-4000-8000-0000000b34a2', 'tp_test_b3h_a2', extensions.crypt('3333', extensions.gen_salt('bf', 4)), false);
do $$ begin
  perform pg_temp.set('c1', public.customer_login('79998401', '1111')->>'session');
  perform pg_temp.set('c2', public.customer_login('79998402', '1111')->>'session');
  perform pg_temp.set('m1', public.merchant_login('79998411', '2222')->>'session');
  perform pg_temp.set('m2', public.merchant_login('79998412', '2222')->>'session');
  perform pg_temp.set('a1', public.admin_login('tp_test_b3h_a1', '3333')->>'session');
  perform pg_temp.set('a2', public.admin_login('tp_test_b3h_a2', '3333')->>'session');
  perform public.admin_allowance_adjust_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3401', 10000, 30, 'test');
  perform public.admin_allowance_adjust_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3402', 10000, 30, 'test');
end $$;

-- §07 reminders
do $$ declare n int; begin
  perform public._pts_add('79998401', 300, 'adjust', now() + interval '2 days', null, null, 'test', null);
  perform public._pts_add('79998401', 200, 'adjust', now() + interval '2 days 5 hours', null, null, 'test', null);
  perform public._pts_add('79998401', 100, 'adjust', now() + interval '20 hours', null, null, 'test', null);
  perform public._pts_add('79998401', 5000, 'adjust', now() + interval '60 days', null, null, 'test', null);
  perform public._pts_sync('79998401');
  perform public._pts_expire('79998401');
  perform pg_temp.ok('§07 one grouped 3-day reminder (500 points) and one 24-hour reminder (100)',
    (select count(*) from public.customer_notes where customer_phone = '79998401' and title = 'تنتهي 500 نقطة خلال 3 أيام') = 1
    and (select count(*) from public.customer_notes where customer_phone = '79998401' and title = 'تنتهي 100 نقطة خلال 24 ساعة') = 1);
  perform public._pts_expire('79998401'); perform public._pts_expire('79998401');
  perform pg_temp.ok('§07 no repeated reminders', (select count(*) from public.customer_notes where customer_phone = '79998401' and title like 'تنتهي % نقطة خلال%') = 2);
  update public.point_batches set expires_at = now() + interval '10 hours' where customer_phone = '79998401' and initial = 300;
  perform public._pts_expire('79998401');
  perform pg_temp.ok('§07 the same batch later gets its 24-hour reminder', exists (select 1 from public.customer_notes where customer_phone = '79998401' and title = 'تنتهي 300 نقطة خلال 24 ساعة'));
  update public.point_batches set expires_at = now() - interval '1 second' where customer_phone = '79998401' and initial = 100;
  perform public._pts_expire('79998401');
  perform pg_temp.ok('§07 at expiry: expiry note', exists (select 1 from public.customer_notes where customer_phone = '79998401' and title = 'انتهت صلاحية 100 نقطة'));
  perform pg_temp.ok('§07 no reminder for points already used', not exists (select 1 from public.point_reminders r join public.point_batches b on b.id = r.batch_id where b.remaining = 0 and r.at > now()));
end $$;

-- §07 compensation
do $$ declare tx uuid; rep uuid; r jsonb; begin
  tx := pg_temp.buy(pg_temp.get('c2'), pg_temp.get('m1'), 20, false, 'idem-b3h-0001');
  r := public.report_tx(pg_temp.get('c2'), 'other', tx, null, 'خطأ تقني: لم تُحتسب النقاط');
  rep := (select id from public.tx_reports where tx_id = tx);
  perform pg_temp.ok('§07 secondary admin cannot compensate', pg_temp.err(format('select public.admin_compensate_v2(%L, %L, 200, %L)', pg_temp.get('a2'), rep, 'خطأ تقني مثبت')) like 'TP_FORBIDDEN%');
  r := public.admin_compensate_v2(pg_temp.get('a1'), rep, 200, 'خطأ تقني مثبت في الخادم');
  perform pg_temp.ok('§07 compensation: 200 points valid 7 days, notified, audited', (r->>'ok')::boolean
    and exists (select 1 from public.point_batches where id = (r->>'batch_id')::bigint and remaining = 200 and expires_at = now() + interval '7 days')
    and exists (select 1 from public.customer_notes where customer_phone = '79998402' and title like 'تعويض من الإدارة%')
    and exists (select 1 from public.audit_log where action = 'compensation' and target_id = rep::text), r::text);
  perform pg_temp.ok('§07 never twice for the same complaint', public.admin_compensate_v2(pg_temp.get('a1'), rep, 200, 'مرة ثانية للخطأ')->>'error' = 'already_compensated');
end $$;

-- §10 refunds
do $$ declare tx uuid; r jsonb; p0 numeric; p1 numeric; al0 numeric; begin
  p0 := public._pts_spendable('79998401'); al0 := public._allow_remaining('00000000-0000-4000-8000-0000000b3401');
  tx := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('m1'), 40, true, 'idem-b3h-0002');       -- redeem 2000 (50 %), earn 10 % of $20 = 200
  p1 := public._pts_spendable('79998401');
  perform pg_temp.ok('setup: purchase used 2000 and earned 200', (select redeem_pts from public.pos_transactions where id = tx) = 2000
    and (select earn from public.pos_transactions where id = tx) = 200 and p1 = p0 - 2000 + 200, format('%s → %s', p0, p1));
  perform pg_temp.ok('§10 needs both parties'' agreement', public.admin_tx_refund_v2(pg_temp.get('a1'), tx, 1, 'إرجاع البضاعة', true, false)->>'error' = 'agreement_required');
  r := public.admin_tx_refund_v2(pg_temp.get('a1'), tx, 0.5, 'إرجاع نصف البضاعة', true, true);
  perform pg_temp.ok('§10 half refund: 1000 used points back, 100 earned points out, 1000 allowance back to the branch',
    (r->>'redeem_back')::numeric = 1000 and (r->>'earn_back')::numeric = 100 and (r->>'allowance_back')::numeric = 1000
    and public._pts_spendable('79998401') = p1 + 1000 - 100 and public._allow_remaining('00000000-0000-4000-8000-0000000b3401') = al0 - 2000 + 1000, r::text);
  perform pg_temp.ok('§10 more than 100 % refused', public.admin_tx_refund_v2(pg_temp.get('a1'), tx, 0.6, 'إرجاع زائد', true, true)->>'error' = 'over_refund');
  r := public.admin_tx_refund_v2(pg_temp.get('a1'), tx, 0.5, 'إرجاع الباقي', true, true);
  perform pg_temp.ok('§10 second half: back to the balance before the purchase, branch allowance whole again',
    public._pts_spendable('79998401') = p0 and public._allow_remaining('00000000-0000-4000-8000-0000000b3401') = al0 and (r->>'refunded_total')::numeric = 1, r::text);
  perform pg_temp.ok('§10 the original purchase is kept (CONFIRMED) with two refund records', (select status from public.pos_transactions where id = tx) = 'CONFIRMED'
    and (select count(*) from public.tx_refunds where tx_id = tx) = 2);
  perform pg_temp.ok('§10 ledger invariants hold (balances, batches, grants)', pg_temp.ledger_ok());
end $$;

do $$ declare tx uuid; r jsonb; begin
  -- earned points spent at another branch: settlement documented, nothing taken from elsewhere
  tx := pg_temp.buy(pg_temp.get('c2'), pg_temp.get('m1'), 20, false, 'idem-b3h-0003');                       -- c2 earns 200
  perform public._pts_take('79998402', public._pts_spendable('79998402'), 'spend', null, 'test');            -- spends everything elsewhere
  perform public._pts_sync('79998402');
  r := public.admin_tx_refund_v2(pg_temp.get('a1'), tx, 1, 'إرجاع كامل بعد صرف المكافأة', true, true);
  perform pg_temp.ok('§10 earned points already spent: shortfall documented (200), no new or negative points', (r->>'earn_shortfall')::numeric = 200
    and (r->>'earn_back')::numeric = 0 and public._pts_spendable('79998402') = 0, r::text);
  -- used points whose batch expired meanwhile do not regain validity
  perform public._pts_add('79998402', 1000, 'adjust', now() + interval '1 day', null, null, 'test', null); perform public._pts_sync('79998402');
  tx := pg_temp.buy(pg_temp.get('c2'), pg_temp.get('m2'), 10, true, 'idem-b3h-0004');
  update public.point_batches set expires_at = now() - interval '1 second' where customer_phone = '79998402' and initial = 1000;
  r := public.admin_tx_refund_v2(pg_temp.get('a1'), tx, 1, 'إرجاع بعد انتهاء الصلاحية', true, true);
  perform pg_temp.ok('§10 returned points from an expired batch are not revived', (r->>'redeem_lapsed')::numeric = 500 and (r->>'redeem_back')::numeric = 0, r::text);
  perform pg_temp.ok('§12 receipts: both sides see the purchase with its refunds; other people cannot',
    jsonb_array_length(public.tx_receipt_v2(pg_temp.get('c2'), tx)->'receipt'->'refunds') = 1
    and jsonb_array_length(public.tx_receipt_v2(pg_temp.get('m2'), tx)->'receipt'->'refunds') = 1
    and public.tx_receipt_v2(pg_temp.get('c1'), tx)->>'error' = 'not_found' and public.tx_receipt_v2(pg_temp.get('m1'), tx)->>'error' = 'not_found');
  perform pg_temp.ok('ledger invariants hold after all refunds', pg_temp.ledger_ok());
  perform pg_temp.ok('helpers not reachable by anon; gift settings untouched', not has_function_privilege('anon', 'public._pts_remind(text)', 'execute')
    and (select value from public.app_text_settings where key = 'welcome_bonus') = '3000' and (select value from public.app_text_settings where key = 'welcome_days') = '7');
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
