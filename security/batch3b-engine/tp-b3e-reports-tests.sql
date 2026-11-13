-- BATCH 3e TESTS (Staging): one transaction ending in ROLLBACK; synthetic phones 799981xx only.
begin;
set local client_min_messages = warning;
create temp table _t (n serial primary key, name text, ok boolean, detail text) on commit drop;
create temp table _ctx (k text primary key, v text) on commit drop;
create function pg_temp.ok(p_name text, p_cond boolean, p_detail text default null) returns void language sql as $$
  insert into _t(name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail) $$;
create function pg_temp.set(p_k text, p_v text) returns void language sql as $$
  insert into _ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.get(p_k text) returns text language sql as $$ select v from _ctx where k = p_k $$;
do $$ begin
  if exists (select 1 from public.customers where phone like '799981__') or exists (select 1 from public.merchants where phone like '799981__') then
    raise exception 'test phones 799981xx exist — stopped'; end if;
end $$;
insert into public.customers(phone, pin_hash, name, status, points) values
  ('79998101', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 1000);
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
  ('00000000-0000-4000-8000-0000000b3e01', 'فرع بلاغات', '79998111', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 5, 'active');
insert into public.topups(merchant_id, amount, source) values ('00000000-0000-4000-8000-0000000b3e01', 100, 'test');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000b3ea1', 'tp_test_b3e_a1', extensions.crypt('3333', extensions.gen_salt('bf', 4)), true);

do $$
declare c text; m text; a text; q jsonb; s jsonb; r jsonb; tx uuid; rep uuid;
begin
  c := public.customer_login('79998101', '1111')->>'session';
  m := public.merchant_login('79998111', '2222')->>'session';
  a := public.admin_login('tp_test_b3e_a1', '3333')->>'session';
  perform public._allow_add('00000000-0000-4000-8000-0000000b3e01', 1000, 'adjust', now(), now() + interval '30 days', null, null, null, null, null, 'test');
  q := public.customer_qr_issue(c);
  s := public.merchant_scan_code(m, q->>'qr');
  r := public.merchant_create_tx_v2(m, (s->>'code_id')::uuid, 100, true, null, '[]'::jsonb, 'idem-b3e-0001');
  tx := (r->'tx'->>'id')::uuid;
  perform pg_temp.ok('setup: pending purchase holds 500 of the branch allowance', public._allow_remaining('00000000-0000-4000-8000-0000000b3e01') = 500, r::text);
  r := public.report_tx(c, 'not_my_purchase', tx, null, 'لم أشترِ');
  perform pg_temp.ok('customer report: accepted', (r->>'ok')::boolean, r::text);
  perform pg_temp.ok('report cancels the pending purchase', (select status from public.pos_transactions where id = tx) = 'CANCELLED');
  perform pg_temp.ok('FIX: the branch reservation is returned (R back to 1000)', public._allow_remaining('00000000-0000-4000-8000-0000000b3e01') = 1000
    and (select status from public.allowance_holds where tx_id = tx) = 'released');
  perform pg_temp.ok('no points moved for the customer', public._pts_spendable('79998101') = 1000);
  rep := (select id from public.tx_reports where tx_id = tx);
  r := public.admin_security_feed_v2(a, 50);
  perform pg_temp.ok('admin feed lists the report', exists (select 1 from jsonb_array_elements(r->'reports') x where (x->>'id')::uuid = rep));
  r := public.admin_resolve_report_v2(a, rep, 'reviewed', 'تم التواصل مع المحل');
  perform pg_temp.ok('admin resolves the report', (r->>'ok')::boolean, r::text);
  perform pg_temp.ok('NEW: the customer is notified with the admin note',
    exists (select 1 from public.customer_notes where customer_phone = '79998101' and title like 'راجعت الإدارة بلاغك%' and body = 'تم التواصل مع المحل'));
  -- merchant report on a claimed code
  q := public.customer_qr_issue(c);
  s := public.merchant_scan_code(m, q->>'qr');
  r := public.report_tx(m, 'not_account_owner', null, (s->>'code_id')::uuid, 'الشخص ليس صاحب الحساب');
  perform pg_temp.ok('shop report on a scanned code: accepted, code released', (r->>'ok')::boolean
    and (select superseded_at is not null from public.purchase_codes where id = (s->>'code_id')::uuid), r::text);
  rep := (select id from public.tx_reports where code_id = (s->>'code_id')::uuid and reporter_role = 'merchant');
  perform public.admin_resolve_report_v2(a, rep, 'dismissed', null);
  perform pg_temp.ok('NEW: the shop is notified', exists (select 1 from public.merchant_notes where merchant_id = '00000000-0000-4000-8000-0000000b3e01' and title like 'راجعت الإدارة بلاغك%'));
  perform pg_temp.ok('a customer cannot report someone else''s purchase', (public.report_tx(c, 'other', gen_random_uuid(), null, null)->>'error') = 'not_found');
  perform pg_temp.ok('_report_notify is not reachable by anon', not has_function_privilege('anon', 'public._report_notify(uuid)', 'execute'));
  perform pg_temp.ok('Admin gift settings untouched', (select value from public.app_text_settings where key = 'welcome_bonus') = '3000'
    and (select value from public.app_text_settings where key = 'welcome_days') = '7');
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
