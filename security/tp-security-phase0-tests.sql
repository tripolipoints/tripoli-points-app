-- =====================================================================================================
-- Tripoli Points — PHASE 0 TESTS (run on STAGING after tp-security-phase0-urgent.sql)
-- One transaction ending in ROLLBACK: test accounts and lock counters disappear. Calls run as the public role (anon),
-- the way the app calls them. admin_wipe_all_data is only ever called with WRONG PINs here.
-- Test numbers 70999801-70999802, test admins tp_p0_test_*. Last statements print PASS/FAIL per check and a summary.
-- =====================================================================================================
begin;
set local client_min_messages = warning;
create temp table _t (n serial primary key, name text, ok boolean, detail text) on commit drop;
grant all on _t to anon; grant usage on sequence _t_n_seq to anon;
create function pg_temp.ok(p_name text, p_cond boolean, p_detail text default null) returns void language sql as $$
  insert into _t(name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail) $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'NO_ERROR'; exception when others then return sqlerrm; end $$;

do $$ begin
  if exists (select 1 from public.customers where phone like '709998__') or exists (select 1 from public.merchants where phone like '709998__')
     or exists (select 1 from public.admin_users where username like 'tp_p0_test_%') then
    raise exception 'test fixtures already exist — tests stopped';
  end if;
end $$;

insert into public.customers(phone, pin_hash, name, status) values ('70999801', extensions.crypt('1234', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active');
insert into public.merchants(id, name, phone, pin_hash, status) values
  ('00000000-0000-4000-8000-0000000008a1', 'p0 test shop', '70999802', extensions.crypt('4321', extensions.gen_salt('bf', 4)), 'active');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000008b1', 'tp_p0_test_primary', extensions.crypt('9999', extensions.gen_salt('bf', 4)), true),
  ('00000000-0000-4000-8000-0000000008b2', 'tp_p0_test_second',  extensions.crypt('9999', extensions.gen_salt('bf', 4)), true);
create temp table _counts on commit drop as select (select count(*) from public.merchants) m, (select count(*) from public.customers) c;
grant select on _counts to anon;

set local role anon;
do $$
declare r jsonb; i int; e text;
begin
  -- closed functions
  e := pg_temp.err($q$select public.customer_reset_pin('70999801', '0000')$q$);
  perform pg_temp.ok('customer_reset_pin is closed to the public key', e like 'permission denied%', e);
  e := pg_temp.err($q$select public.whish_confirm_payment(gen_random_uuid(), 'success', null, null)$q$);
  perform pg_temp.ok('whish_confirm_payment is closed to the public key', e like 'permission denied%', e);
  e := pg_temp.err($q$select public.admin_grant_customer_gift('70999801', 1000, 30)$q$);
  perform pg_temp.ok('admin_grant_customer_gift is closed to the public key', e like 'permission denied%', e);
  e := pg_temp.err($q$select count(*) from public.auth_rate_limits$q$);
  perform pg_temp.ok('the rate-limit table cannot be read with the public key', e like 'permission denied%', e);
  e := pg_temp.err($q$select public.merchant_reset_pin('70999802', '0000')$q$);
  perform pg_temp.ok('October: merchant_reset_pin still closed', e like 'permission denied%', e);

  -- customer PIN
  r := public.customer_verify_pin('70999801', '1234');
  perform pg_temp.ok('customer: the right PIN still works', (r->>'ok')::boolean, r::text);
  for i in 1..5 loop r := public.customer_verify_pin('70999801', '0000'); end loop;
  r := public.customer_verify_pin('70999801', '1234');
  perform pg_temp.ok('customer: 5 wrong PINs lock the account, even the right PIN', r->>'reason' = 'locked', r::text);

  -- admin PIN (login)
  r := public.admin_verify_pin('tp_p0_test_second', '9999');
  perform pg_temp.ok('admin: the right PIN still works', (r->>'ok')::boolean);
  for i in 1..5 loop r := public.admin_verify_pin('tp_p0_test_second', '0000'); end loop;
  r := public.admin_verify_pin('tp_p0_test_second', '9999');
  perform pg_temp.ok('admin: 5 wrong PINs lock the admin login', r->>'reason' = 'locked', r::text);

  -- wipe: wrong PINs only; shares the October key with admin_reset_merchant_pin
  for i in 1..3 loop r := public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008b1', '0000'); end loop;
  perform pg_temp.ok('wipe: a wrong PIN is refused', (r->>'ok')::boolean = false and r->>'error' = 'رمز الإدارة غير صحيح', r::text);
  for i in 1..2 loop r := public.admin_reset_merchant_pin('00000000-0000-4000-8000-0000000008b1', '0000', '00000000-0000-4000-8000-0000000008a1', '1111'); end loop;
  r := public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008b1', '0000');
  perform pg_temp.ok('wipe + admin PIN reset share one limit: 3 + 2 wrong PINs lock both', r->>'reason' = 'locked', r::text);
  r := public.admin_reset_merchant_pin('00000000-0000-4000-8000-0000000008b1', '9999', '00000000-0000-4000-8000-0000000008a1', '1111');
  perform pg_temp.ok('October: admin_reset_merchant_pin is locked too', r->>'reason' = 'locked', r::text);

  -- functions the app uses stay open
  r := public.merchant_verify_pin('70999802', '4321');
  perform pg_temp.ok('merchant login still works', (r->>'ok')::boolean, left(r::text, 80));
  e := pg_temp.err($q$select public.customer_check_phone('70999801')$q$);
  perform pg_temp.ok('customer_check_phone still open (login screen)', e = 'NO_ERROR', e);
end $$;
reset role;

do $$ begin
  perform pg_temp.ok('wipe: no data was deleted', (select m from _counts) = (select count(*) from public.merchants) and (select c from _counts) = (select count(*) from public.customers));
  perform pg_temp.ok('the Whish callback key (service_role) can still confirm payments',
    has_function_privilege('service_role', 'public.whish_confirm_payment(uuid,text,numeric,bigint)', 'EXECUTE'));
  perform pg_temp.ok('registration overload the app uses is still open',
    has_function_privilege('anon', 'public.customer_register(text,text,text,numeric,integer,text)', 'EXECUTE'));
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
