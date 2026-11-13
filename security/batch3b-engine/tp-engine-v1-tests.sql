-- =====================================================================================================
-- Tripoli Points — BATCH 3b ENGINE TESTS (Staging, after tp-engine-v1.sql)
-- One transaction ending in ROLLBACK: nothing stays. Test phones 799980xx (must not exist).
-- No real account, PIN or password is used or printed.
-- =====================================================================================================
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
-- a full purchase up to PENDING: QR → scan → create. Returns the create result (+ code)
create function pg_temp.buy(p_c text, p_m text, p_inv numeric, p_redeem boolean, p_idem text) returns jsonb language plpgsql as $$
declare q jsonb; s jsonb;
begin
  q := public.customer_qr_issue(p_c);
  s := public.merchant_scan_code(p_m, q->>'qr');
  if not coalesce((s->>'ok')::boolean, false) then return s; end if;
  return public.merchant_create_tx_v2(p_m, (s->>'code_id')::uuid, p_inv, p_redeem, null, '[]'::jsonb, p_idem);
end $$;
create function pg_temp.confirm(p_c text, p_tx uuid) returns jsonb language sql as $$
  select public.customer_decide_tx_v2(p_c, p_tx, true, (select detail_hash from public.pos_transactions where id = p_tx)) $$;

do $$ begin
  if exists (select 1 from public.customers where phone like '799980__') or exists (select 1 from public.merchants where phone like '799980__')
     or exists (select 1 from public.merchant_staff where phone like '799980__') then
    raise exception 'test phones 799980xx already exist — stopped';
  end if;
end $$;

-- ---------------------------------------------------------------- fixtures (test-only, rolled back)
insert into public.customers(phone, pin_hash, name, status, points) values
  ('79998001', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0),
  ('79998002', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0),
  ('79998004', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0);
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
  ('00000000-0000-4000-8000-0000000b3b01', 'فرع اختبار 1', '79998011', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 5, 'active'),
  ('00000000-0000-4000-8000-0000000b3b02', 'فرع اختبار 2', '79998012', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 5, 'active');
insert into public.topups(merchant_id, amount, source) values
  ('00000000-0000-4000-8000-0000000b3b01', 500, 'test'), ('00000000-0000-4000-8000-0000000b3b02', 500, 'test');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000b3ba1', 'tp_test_b3b_a1', extensions.crypt('3333', extensions.gen_salt('bf', 4)), true),
  ('00000000-0000-4000-8000-0000000b3ba2', 'tp_test_b3b_a2', extensions.crypt('3333', extensions.gen_salt('bf', 4)), false);

do $$ begin
  perform pg_temp.set('c1', public.customer_login('79998001', '1111')->>'session');
  perform pg_temp.set('c2', public.customer_login('79998002', '1111')->>'session');
  perform pg_temp.set('c4', public.customer_login('79998004', '1111')->>'session');
  perform pg_temp.set('m1', public.merchant_login('79998011', '2222')->>'session');
  perform pg_temp.set('m2', public.merchant_login('79998012', '2222')->>'session');
  perform pg_temp.set('a1', public.admin_login('tp_test_b3b_a1', '3333')->>'session');
  perform pg_temp.set('a2', public.admin_login('tp_test_b3b_a2', '3333')->>'session');
end $$;

-- ---------------------------------------------------------------- 1. welcome gift from the server (G-1) opens a ledger batch
do $$ declare r jsonb; b public.point_batches; begin
  r := public.customer_register('79998003', '1111', null, 99999, 999, null);
  select * into b from public.point_batches where customer_phone = '79998003';
  perform pg_temp.ok('register: gift = Admin setting (not the browser value)', (r->>'points')::numeric = (select value::numeric from public.app_text_settings where key = 'welcome_bonus'), r::text);
  perform pg_temp.ok('register: welcome batch with the gift validity', b.kind = 'welcome' and b.remaining = (r->>'points')::numeric
    and b.expires_at = (select welcome_exp from public.customers where phone = '79998003'), to_jsonb(b)::text);
  -- the gift expires: old check function → ledger expiry, single deduction
  update public.point_batches set expires_at = now() - interval '1 second' where customer_phone = '79998003';
  perform public.customer_check_welcome_expiry('79998003');
  perform pg_temp.ok('gift expiry: points 0, welcome_remain 0, one expire movement, one note',
    (select points from public.customers where phone = '79998003') = 0 and (select welcome_remain from public.customers where phone = '79998003') = 0
    and (select count(*) from public.point_movements where customer_phone = '79998003' and reason = 'expire') = 1
    and (select count(*) from public.customer_notes where customer_phone = '79998003' and title like 'انتهت صلاحية هدية الترحيب%') = 1);
  perform public.customer_check_welcome_expiry('79998003');
  perform pg_temp.ok('gift expiry: running it again changes nothing', (select count(*) from public.point_movements where customer_phone = '79998003') = 2);
end $$;

-- ---------------------------------------------------------------- 2. ledger: FIFO, expiry, guard
do $$ declare r jsonb; got numeric; e text; begin
  perform public._pts_add('79998004', 1000, 'adjust', now() + interval '20 days', null, null, 'test', null);
  perform public._pts_add('79998004', 500, 'earn', now() + interval '2 days', null, null, 'test', null);
  perform public._pts_add('79998004', 300, 'legacy', null, null, null, 'test', null);
  perform public._pts_sync('79998004');
  got := public._pts_take('79998004', 700, 'spend', null, 'test');
  perform pg_temp.ok('FIFO: earliest-expiring batch emptied first (500 then 200 of the 1000), no-expiry last',
    got = 700 and (select remaining from public.point_batches where customer_phone = '79998004' and kind = 'earn') = 0
    and (select remaining from public.point_batches where customer_phone = '79998004' and kind = 'adjust') = 800
    and (select remaining from public.point_batches where customer_phone = '79998004' and kind = 'legacy') = 300);
  perform pg_temp.ok('FIFO: asking for more than the valid balance takes nothing', public._pts_take('79998004', 5000, 'spend', null, 'test') = -1
    and public._pts_spendable('79998004') = 1100);
  update public.point_batches set expires_at = now() - interval '1 second' where customer_phone = '79998004' and kind = 'adjust';
  perform pg_temp.ok('expiry: expired batch not spendable before the job runs', public._pts_spendable('79998004') = 300);
  perform public._pts_expire('79998004');
  perform pg_temp.ok('expiry: expired points removed, cached total synced, note', (select points from public.customers where phone = '79998004') = 300
    and exists (select 1 from public.customer_notes where customer_phone = '79998004' and title = 'انتهت صلاحية 800 نقطة'));
  -- legacy function path (non-strict): a direct change is mirrored into the ledger. After the close-old step Staging runs
  -- with engine_strict = 1; the transition mode is switched on for this rolled-back run only, and restored below.
  perform pg_temp.set('strict0', (select value::text from public.app_settings where key = 'engine_strict'));
  update public.app_settings set value = 0 where key = 'engine_strict';
  update public.customers set points = points + 200 where phone = '79998004';
  perform pg_temp.ok('guard (transition): a legacy +200 becomes a mirror batch valid 3 months',
    exists (select 1 from public.point_batches where customer_phone = '79998004' and kind = 'mirror' and initial = 200
            and expires_at = now() + interval '3 months') and public._pts_spendable('79998004') = 500);
  update public.customers set points = points - 100 where phone = '79998004';
  perform pg_temp.ok('guard (transition): a legacy −100 is taken FIFO', public._pts_spendable('79998004') = 400);
  update public.app_settings set value = 1 where key = 'engine_strict';
  e := pg_temp.err($q$update public.customers set points = points + 1000000 where phone = '79998004'$q$);
  perform pg_temp.ok('guard (strict): a direct balance change is refused', e like 'TP_LEDGER_ONLY%', e);
  update public.app_settings set value = pg_temp.get('strict0')::numeric where key = 'engine_strict';
end $$;

-- ---------------------------------------------------------------- 3. allowance rule
do $$ begin
  perform pg_temp.ok('cap: R=1000 → 700', public._allow_cap(1000) = 700);
  perform pg_temp.ok('cap: R=11 → 7 (floor)', public._allow_cap(11) = 7);
  perform pg_temp.ok('cap: R=10 → 10 (all)', public._allow_cap(10) = 10);
  perform pg_temp.ok('cap: R=3 → 3', public._allow_cap(3) = 3);
  perform pg_temp.ok('cap: R=0 → 0', public._allow_cap(0) = 0);
end $$;

-- ---------------------------------------------------------------- 4. catalogue + manual payment
do $$ declare r jsonb; r2 jsonb; id1 uuid; g public.allowance_grants; s public.merchant_subscriptions; begin
  r := public.merchant_payment_request_v2(pg_temp.get('m1'), 'subscription', 'm-basic', 'TRX-0001', null, 'idem-pay-0001');
  perform pg_temp.ok('payment: closed while the Admin has no transfer number', r->>'error' = 'payments_closed', r::text);
  perform pg_temp.ok('catalogue: a secondary admin cannot edit plans',
    pg_temp.err(format('select public.admin_plan_save_v2(%L, %L, %L, %L, 20, 2000, 1, true)', pg_temp.get('a2'), 'm-basic', 'Basic', 'medium')) like 'TP_FORBIDDEN%');
  perform pg_temp.ok('catalogue: a merchant session cannot edit plans',
    pg_temp.err(format('select public.admin_plan_save_v2(%L, %L, %L, %L, 20, 2000, 1, true)', pg_temp.get('m1'), 'm-basic', 'Basic', 'medium')) like 'TP_SESSION%');
  r := public.admin_plan_save_v2(pg_temp.get('a1'), 'm-basic', 'اشتراك تجريبي', 'medium', 20, 2000, 1, true);
  r2 := public.admin_package_save_v2(pg_temp.get('a1'), 'p-500', 'باقة تجريبية', 5, 500, 30, true);
  perform pg_temp.ok('catalogue: primary admin saves a plan and a package (provisional by default)',
    (r->>'ok')::boolean and (r2->>'ok')::boolean and (r->'plan'->>'provisional')::boolean, r::text);
  perform pg_temp.ok('catalogue: bad values refused', public.admin_plan_save_v2(pg_temp.get('a1'), 'X!', 't', null, -1, 0, 0, true)->>'error' = 'bad_request');
  r := public.admin_pay_settings_v2(pg_temp.get('a1'), '+961 70 000000', 'حوّل المبلغ ثم أدخل رقم المرجع');
  perform pg_temp.ok('pay settings: saved by primary admin', (r->>'ok')::boolean);
  r := public.merchant_catalog_v2(pg_temp.get('m1'));
  perform pg_temp.ok('merchant catalogue: shows the transfer number, the tier plan and the package',
    r->>'transfer_number' = '+961 70 000000' and jsonb_array_length(r->'plans') = 1 and jsonb_array_length(r->'packages') = 1, left(r::text, 200));

  r := public.merchant_payment_request_v2(pg_temp.get('m1'), 'subscription', 'm-basic', 'trx 0001', 'إيصال رقم 1', 'idem-pay-0001');
  id1 := (r->'request'->>'id')::uuid; perform pg_temp.set('pr1', id1::text);
  perform pg_temp.ok('payment request: pending, amount = plan price', r->'request'->>'status' = 'pending' and (r->'request'->>'amount')::numeric = 20, r::text);
  r := public.merchant_payment_request_v2(pg_temp.get('m1'), 'subscription', 'm-basic', 'trx 0001', null, 'idem-pay-0001');
  perform pg_temp.ok('payment request: same idempotency key → same request (no duplicate)', (r->>'replayed')::boolean and (r->'request'->>'id')::uuid = id1);
  r := public.merchant_payment_request_v2(pg_temp.get('m2'), 'package', 'p-500', 'TRX-0001', null, 'idem-pay-0002');
  perform pg_temp.ok('payment request: the same transfer reference (other format, other branch) is refused', r->>'error' = 'duplicate_ref', r::text);

  perform pg_temp.ok('approve: secondary admin refused',
    pg_temp.err(format('select public.admin_payment_decide_v2(%L, %L, true, 20, %L)', pg_temp.get('a2'), id1, 'TRX0001')) like 'TP_FORBIDDEN%');
end $$;
do $$ declare r jsonb; id1 uuid := pg_temp.get('pr1')::uuid; g public.allowance_grants; s public.merchant_subscriptions; begin
  r := public.admin_payment_decide_v2(pg_temp.get('a1'), id1, true, 25, 'TRX0001');
  perform pg_temp.ok('approve: wrong verified amount refused', r->>'error' = 'amount_mismatch', r::text);
  r := public.admin_payment_decide_v2(pg_temp.get('a1'), id1, true, 20, 'TRX0002');
  perform pg_temp.ok('approve: wrong verified reference refused', r->>'error' = 'ref_mismatch', r::text);
  perform pg_temp.ok('approve: nothing granted by refused attempts', not exists (select 1 from public.allowance_grants where merchant_id = '00000000-0000-4000-8000-0000000b3b01'));
  r := public.admin_payment_decide_v2(pg_temp.get('a1'), id1, true, 20, 'trx-0001');
  select * into g from public.allowance_grants where payment_request_id = id1;
  select * into s from public.merchant_subscriptions where payment_request_id = id1;
  perform pg_temp.ok('approve: one grant of 2000, valid for the period + 1 month carry-over',
    (r->>'ok')::boolean and g.initial = 2000 and g.remaining = 2000 and g.valid_from = s.period_start
    and s.period_end = s.period_start + interval '1 month' and g.expires_at = s.period_end + interval '1 month', r::text);
  r := public.admin_payment_decide_v2(pg_temp.get('a1'), id1, true, 20, 'trx-0001');
  perform pg_temp.ok('approve twice: refused, still exactly one grant', r->>'error' = 'already_decided'
    and (select count(*) from public.allowance_grants where payment_request_id = id1) = 1, r::text);
  r := public.merchant_payment_request_v2(pg_temp.get('m2'), 'package', 'p-500', 'TRX0001', null, 'idem-pay-0003');
  perform pg_temp.ok('approved reference cannot be submitted again', r->>'error' = 'duplicate_ref', r::text);
  r := public.merchant_allowance_v2(pg_temp.get('m1'));
  perform pg_temp.ok('merchant allowance: remaining 2000, per purchase max 1400', (r->>'remaining')::numeric = 2000 and (r->>'per_purchase_max')::numeric = 1400, left(r::text, 200));
  perform pg_temp.ok('audit: approval and plan changes are logged',
    exists (select 1 from public.audit_log where action = 'payment_approve' and target_id = id1::text)
    and exists (select 1 from public.audit_log where action = 'plan_save') and exists (select 1 from public.audit_log where action = 'payment_amount_mismatch'));
  -- renewal: starts at the end of the current period, not usable before
  r := public.merchant_payment_request_v2(pg_temp.get('m1'), 'renewal', 'm-basic', 'TRX-0009', null, 'idem-pay-0009');
  r := public.admin_payment_decide_v2(pg_temp.get('a1'), (r->'request'->>'id')::uuid, true, 20, 'TRX-0009');
  perform pg_temp.ok('renewal: new period starts when the current one ends; its allowance is not usable yet',
    (r->>'ok')::boolean and (select valid_from from public.allowance_grants where id = (r->>'grant_id')::bigint) = s.period_end
    and public._allow_remaining('00000000-0000-4000-8000-0000000b3b01') = 2000, r::text);
  -- reject needs a reason; cancel by merchant
  r := public.merchant_payment_request_v2(pg_temp.get('m2'), 'package', 'p-500', 'TRX-0020', null, 'idem-pay-0020');
  perform pg_temp.ok('reject: reason required', public.admin_payment_decide_v2(pg_temp.get('a1'), (r->'request'->>'id')::uuid, false)->>'error' = 'note_required');
  perform pg_temp.ok('reject: with a reason', public.admin_payment_decide_v2(pg_temp.get('a1'), (r->'request'->>'id')::uuid, false, null, null, 'لم يصل التحويل')->>'status' = 'rejected');
  r := public.merchant_payment_request_v2(pg_temp.get('m2'), 'package', 'p-500', 'TRX-0020', null, 'idem-pay-0021');
  perform pg_temp.ok('a rejected reference can be submitted again', r->'request'->>'status' = 'pending', r::text);
  perform pg_temp.ok('merchant cancels his pending request', (public.merchant_payment_cancel_v2(pg_temp.get('m2'), (r->'request'->>'id')::uuid)->>'ok')::boolean);
end $$;

-- ---------------------------------------------------------------- 5. purchases with ledger + allowance
do $$ declare r jsonb; tx uuid; b public.point_batches; begin
  r := public.admin_points_adjust_v2(pg_temp.get('a1'), '79998001', 5000, 'رصيد اختبار');
  perform pg_temp.ok('admin points adjust: +5000 batch, audit', (r->>'points')::numeric = 5000
    and exists (select 1 from public.audit_log where action = 'points_adjust' and target_id = '79998001'), r::text);
  r := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('m1'), 100, true, 'idem-tx-0001');
  tx := (r->'tx'->>'id')::uuid;
  perform pg_temp.ok('purchase 1: redeem = min(5000 customer, 500 invoice %, 2500 tier, 1400 branch) = 500',
    (r->'tx'->>'redeemPts')::numeric = 500, r::text);
  perform pg_temp.ok('purchase 1: 500 reserved on the branch (R 2000 → 1500)', public._allow_remaining('00000000-0000-4000-8000-0000000b3b01') = 1500
    and (select sum(pts) from public.allowance_holds where tx_id = tx and status = 'held') = 500);
  perform pg_temp.ok('purchase 1: nothing moves on the customer before confirmation', public._pts_spendable('79998001') = 5000);
  r := pg_temp.confirm(pg_temp.get('c1'), tx);
  select * into b from public.point_batches where tx_id = tx and kind = 'earn';
  perform pg_temp.ok('confirm: 500 spent, 475 earned in a batch valid 3 calendar months, total 4975',
    (r->>'points')::numeric = 4975 and b.initial = 475 and b.expires_at = now() + interval '3 months' and public._pts_spendable('79998001') = 4975, r::text);
  perform pg_temp.ok('confirm: the reservation is consumed (R stays 1500)', public._allow_remaining('00000000-0000-4000-8000-0000000b3b01') = 1500
    and (select status from public.allowance_holds where tx_id = tx) = 'consumed');
  perform pg_temp.ok('confirm twice: refused, balance unchanged', pg_temp.confirm(pg_temp.get('c1'), tx)->>'error' = 'already_decided'
    and public._pts_spendable('79998001') = 4975);
  -- 2nd purchase cancelled by the merchant: reservation released, does not count for the daily limit
  r := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('m1'), 100, true, 'idem-tx-0002');
  tx := (r->'tx'->>'id')::uuid;
  perform pg_temp.ok('cancel: reserved while pending (R 1000)', public._allow_remaining('00000000-0000-4000-8000-0000000b3b01') = 1000);
  r := public.merchant_cancel_tx(pg_temp.get('m1'), tx);
  perform pg_temp.ok('cancel: merchant cancels, reservation returned (R 1500)', (r->>'ok')::boolean
    and public._allow_remaining('00000000-0000-4000-8000-0000000b3b01') = 1500, r::text);
  -- customer rejects: released
  r := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('m1'), 50, true, 'idem-tx-0003');
  tx := (r->'tx'->>'id')::uuid;
  r := public.customer_decide_tx_v2(pg_temp.get('c1'), tx, false);
  perform pg_temp.ok('reject: customer rejects, reservation returned, no points move', r->>'status' = 'CANCELLED'
    and public._allow_remaining('00000000-0000-4000-8000-0000000b3b01') = 1500 and public._pts_spendable('79998001') = 4975);
  r := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('m1'), 40, false, 'idem-tx-0004');
  perform pg_temp.ok('purchase without redeem: confirmed (2nd of the day)', (pg_temp.confirm(pg_temp.get('c1'), (r->'tx'->>'id')::uuid)->>'ok')::boolean, r::text);
  r := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('m1'), 40, false, 'idem-tx-0005');
  perform pg_temp.ok('daily limit: 3rd purchase of the day in the same branch refused', r->>'error' = 'daily_limit', r::text);
  r := pg_temp.buy(pg_temp.get('c1'), pg_temp.get('m2'), 40, false, 'idem-tx-0006');
  perform pg_temp.ok('daily limit is per branch: another branch still works', (r->>'ok')::boolean, r::text);
  perform public.merchant_cancel_tx(pg_temp.get('m2'), (r->'tx'->>'id')::uuid);
end $$;

-- ---------------------------------------------------------------- 6. edge cases
do $$ declare r jsonb; tx uuid; e text; begin
  -- branch without allowance: no redeem, earning unaffected
  r := public.admin_points_adjust_v2(pg_temp.get('a1'), '79998002', 1000, 'رصيد اختبار');
  r := pg_temp.buy(pg_temp.get('c2'), pg_temp.get('m2'), 100, true, 'idem-tx-0101');
  perform pg_temp.ok('zero allowance: redeem 0, earn still computed', (r->'tx'->>'redeemPts')::numeric = 0 and (r->'tx'->>'earn')::numeric = 500, r::text);
  perform public.merchant_cancel_tx(pg_temp.get('m2'), (r->'tx'->>'id')::uuid);
  -- VIP is subject to the allowance: R = 11 → max 7
  perform public.admin_allowance_adjust_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3b02', 11, 30, 'اختبار VIP');
  insert into public.merchant_vips(merchant_id, customer_phone, cap_points) values ('00000000-0000-4000-8000-0000000b3b02', '79998002', 100000);
  r := pg_temp.buy(pg_temp.get('c2'), pg_temp.get('m2'), 100, true, 'idem-tx-0102');
  tx := (r->'tx'->>'id')::uuid;
  perform pg_temp.ok('VIP: limited by the branch rule (R 11 → 7)', (r->'tx'->>'redeemPts')::numeric = 7, r::text);
  -- the pending purchase times out: reservation returned
  update public.pos_transactions set created_at = now() - interval '10 minutes' where id = tx;
  perform public._expire_pending(null, null);
  perform pg_temp.ok('expiry of a pending purchase returns the reservation', (select status from public.pos_transactions where id = tx) = 'EXPIRED'
    and public._allow_remaining('00000000-0000-4000-8000-0000000b3b02') = 11);
  -- points expire between creation and confirmation: nothing applied
  perform public.admin_allowance_adjust_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-0000000b3b02', 989, 30, 'اختبار');
  delete from public.merchant_vips where merchant_id = '00000000-0000-4000-8000-0000000b3b02' and customer_phone = '79998002';
  r := pg_temp.buy(pg_temp.get('c2'), pg_temp.get('m2'), 100, true, 'idem-tx-0103');
  tx := (r->'tx'->>'id')::uuid;
  update public.point_batches set expires_at = now() - interval '1 second' where customer_phone = '79998002';
  r := pg_temp.confirm(pg_temp.get('c2'), tx);
  perform pg_temp.ok('expired points at confirmation: refused, cancelled, reservation returned, no earn',
    r->>'error' = 'insufficient_points' and (select status from public.pos_transactions where id = tx) = 'CANCELLED'
    and public._allow_remaining('00000000-0000-4000-8000-0000000b3b02') = 1000
    and not exists (select 1 from public.point_batches where tx_id = tx), r::text);
  -- an expired branch grant is not usable
  update public.allowance_grants set expires_at = now() - interval '1 second', valid_from = now() - interval '2 days' where merchant_id = '00000000-0000-4000-8000-0000000b3b02';
  perform pg_temp.ok('expired allowance: R = 0', public._allow_remaining('00000000-0000-4000-8000-0000000b3b02') = 0);
  perform public._allow_expire('00000000-0000-4000-8000-0000000b3b02');
  perform pg_temp.ok('allowance expiry job zeroes and logs', (select coalesce(sum(remaining),0) from public.allowance_grants where merchant_id = '00000000-0000-4000-8000-0000000b3b02') = 0
    and exists (select 1 from public.allowance_movements where merchant_id = '00000000-0000-4000-8000-0000000b3b02' and kind = 'expire'));
  -- daily eligible amount (provisional setting)
  perform public.admin_engine_setting_v2(pg_temp.get('a1'), 'daily_eligible_usd_medium', 50);
  r := public._tx_quote('00000000-0000-4000-8000-0000000b3b02', '79998004', 100, false, null);
  perform pg_temp.ok('daily eligible amount: earn on 50 of 100 when the setting is 50', (r->>'eligible')::numeric = 50 and (r->>'earn')::numeric = 250, r::text);
  perform pg_temp.ok('engine setting: unknown key refused', public.admin_engine_setting_v2(pg_temp.get('a1'), 'hack', 1)->>'error' = 'unknown_key');
  perform pg_temp.ok('engine setting: secondary admin refused',
    pg_temp.err(format('select public.admin_engine_setting_v2(%L, %L, 1)', pg_temp.get('a2'), 'engine_strict')) like 'TP_FORBIDDEN%');
end $$;

-- ---------------------------------------------------------------- 7. staff (employees)
do $$ declare r jsonb; st uuid; tok text; tx uuid; e text; begin
  perform pg_temp.ok('staff: a staff phone cannot be created by a customer session',
    pg_temp.err(format('select public.merchant_staff_save_v2(%L, null, %L, %L, %L, array[%L])', pg_temp.get('c1'), 'x', '79998021', '5555', 'sell')) like 'TP_SESSION%');
  r := public.merchant_staff_save_v2(pg_temp.get('m1'), null, 'موظف اختبار', '79998021', '5555', array['sell']);
  st := (r->'staff'->>'id')::uuid;
  perform pg_temp.ok('staff: owner adds a cashier (PIN stored hashed)', (r->>'ok')::boolean
    and (select pin_hash from public.merchant_staff where id = st) like '$2%', r::text);
  perform pg_temp.ok('staff: wrong PIN refused', public.staff_login('79998021', '0000')->>'reason' = 'wrong_pin');
  r := public.staff_login('79998021', '5555'); tok := r->>'session';
  perform pg_temp.ok('staff: login gives a branch session', (r->>'ok')::boolean and r->'merchant'->>'id' = '00000000-0000-4000-8000-0000000b3b01');
  perform pg_temp.ok('staff: can read the branch profile', (public.merchant_me_v2(tok)->>'ok')::boolean);
  perform pg_temp.ok('staff: cannot manage staff (owner only)', pg_temp.err(format('select public.merchant_staff_list_v2(%L)', tok)) like 'TP_FORBIDDEN%');
  perform pg_temp.ok('staff: cannot change offers / redeem % (owner only)', pg_temp.err(format('select public.merchant_offers_v2(%L)', tok)) like 'TP_FORBIDDEN%');
  perform pg_temp.ok('staff: no history permission', pg_temp.err(format('select public.merchant_transactions_v2(%L)', tok)) like 'TP_FORBIDDEN%');
  perform pg_temp.ok('staff: no payments permission', pg_temp.err(format('select public.merchant_catalog_v2(%L)', tok)) like 'TP_FORBIDDEN%');
  r := pg_temp.buy(pg_temp.get('c4'), tok, 30, false, 'idem-tx-0201');
  tx := (r->'tx'->>'id')::uuid;
  perform pg_temp.ok('staff: sells in his branch, the purchase records the employee', (r->>'ok')::boolean
    and (select staff_id from public.pos_transactions where id = tx) = st, r::text);
  perform pg_temp.ok('staff: cannot cancel without the cancel permission', pg_temp.err(format('select public.merchant_cancel_tx(%L, %L)', tok, tx)) like 'TP_FORBIDDEN%');
  perform public.merchant_cancel_tx(pg_temp.get('m1'), tx);
  r := public.merchant_staff_save_v2(pg_temp.get('m1'), st, 'موظف اختبار', null, null, array['sell'], false);
  perform pg_temp.ok('staff: disabling ends his sessions', pg_temp.err(format('select public.merchant_me_v2(%L)', tok)) like 'TP_SESSION%');
  perform pg_temp.ok('staff: disabled staff cannot log in', public.staff_login('79998021', '5555')->>'reason' = 'frozen');
  r := public.merchant_staff_save_v2(pg_temp.get('m2'), st, 'سرقة', null, '9999', array['sell','payments']);
  perform pg_temp.ok('staff: another branch cannot edit this employee', r->>'error' = 'not_found', r::text);
end $$;

-- ---------------------------------------------------------------- 8. unauthorized access
do $$ declare e text; begin
  perform pg_temp.ok('anon cannot execute ledger / allowance helpers',
    not has_function_privilege('anon', 'public._pts_take(text,numeric,text,uuid,text,boolean)', 'execute')
    and not has_function_privilege('anon', 'public._allow_reserve(uuid,uuid,numeric)', 'execute')
    and not has_function_privilege('anon', 'public._pts_add(text,numeric,text,timestamptz,uuid,uuid,text,text)', 'execute')
    and not has_function_privilege('anon', 'public._allow_add(uuid,numeric,text,timestamptz,timestamptz,text,text,uuid,bigint,uuid,text)', 'execute'));
  perform pg_temp.ok('anon cannot read or write the new tables',
    not has_table_privilege('anon', 'public.point_batches', 'select') and not has_table_privilege('anon', 'public.allowance_grants', 'update')
    and not has_table_privilege('anon', 'public.payment_requests', 'insert') and not has_table_privilege('authenticated', 'public.audit_log', 'select'));
  perform pg_temp.ok('a customer session cannot adjust points', pg_temp.err(format('select public.admin_points_adjust_v2(%L, %L, 100, %L)', pg_temp.get('c1'), '79998001', 'xxx')) like 'TP_SESSION%');
  perform pg_temp.ok('a secondary admin cannot adjust points', pg_temp.err(format('select public.admin_points_adjust_v2(%L, %L, 100, %L)', pg_temp.get('a2'), '79998001', 'xxx')) like 'TP_FORBIDDEN%');
  perform pg_temp.ok('a merchant session cannot approve payments', pg_temp.err(format('select public.admin_payment_decide_v2(%L, %L, true, 20, %L)', pg_temp.get('m1'), pg_temp.get('pr1'), 'x')) like 'TP_SESSION%');
  perform pg_temp.ok('a made-up session is refused', pg_temp.err(format('select public.customer_points_v2(%L)', 'tps1_' || repeat('B', 43))) like 'TP_SESSION%');
  perform pg_temp.ok('admin reads: secondary admin may view requests / audit', (public.admin_payment_requests_v2(pg_temp.get('a2'), null)->>'ok')::boolean
    and (public.admin_audit_log_v2(pg_temp.get('a2'))->>'ok')::boolean);
end $$;

-- ---------------------------------------------------------------- 9. customer view + consistency + gift settings intact
do $$ declare r jsonb; begin
  r := public.customer_points_v2(pg_temp.get('c1'));
  perform pg_temp.ok('customer points view: total, batches with expiry, movements', (r->>'points')::numeric = 4975 + 200
    and jsonb_array_length(r->'batches') >= 2 and jsonb_array_length(r->'movements') >= 3, left(r::text, 300));
  perform pg_temp.ok('consistency: customers.points = valid ledger total for every test customer',
    not exists (select 1 from public.customers where phone like '799980__' and coalesce(points, 0) <> public._pts_spendable(phone)));
  perform pg_temp.ok('consistency: no branch grant below 0 or above its initial; holds match',
    not exists (select 1 from public.allowance_grants where remaining < 0 or remaining > initial)
    and not exists (select 1 from public.allowance_holds h join public.pos_transactions t on t.id = h.tx_id where h.status = 'held' and t.status <> 'PENDING'));
  perform pg_temp.ok('Admin gift settings untouched (3000 / 7)', (select value from public.app_text_settings where key = 'welcome_bonus') = '3000'
    and (select value from public.app_text_settings where key = 'welcome_days') = '7');
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
