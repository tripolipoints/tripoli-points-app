-- =====================================================================================================
-- Tripoli Points — PHASE 0 BEHAVIOURAL TESTS · v1.2 · 2026-11-11 · STAGING ONLY (after tp-security-phase0-urgent.sql)
-- Every check CALLS something as a given key and looks at what happens (SQLSTATE 42501 = permission denied, the
-- answer, the rows left) — no search for words in function code.
--   1) matrix: anon and authenticated against every function phase 0 closed, the wipe/backup functions, the rate-limit
--      table and the backup schema; service_role against what it must keep (Whish) and what it must not (wipe);
--   2) the app's own calls still work as anon (logins, phone check, registration);
--   3) PIN locks: 5 wrong → locked even with the right PIN, a right PIN before that clears the count, expiry after
--      15 min, one account's lock does not touch another, unknown numbers count too, the October shared admin key;
--   4) wipe: refused to the API keys even with a valid primary admin + right PIN and nothing deleted; owner path
--      copies first, empties, restores every row (count + checksum per table), refuses a second restore and a restore
--      over new rows.
-- One transaction ending in ROLLBACK: accounts, locks, copies and the wipe itself disappear. Part 4 empties and refills
-- the tables inside that transaction (they are locked for a few seconds): Staging only, never Production.
-- Test numbers 709998xx, test admins tp_p0_test_*. The last two statements print PASS/FAIL per check and a summary.
-- =====================================================================================================
begin;
set local client_min_messages = warning;
create temp table _t (n serial primary key, name text, ok boolean, detail text) on commit drop;
grant all on _t to anon, authenticated, service_role; grant usage on sequence _t_n_seq to anon, authenticated, service_role;
create function pg_temp.ok(p_name text, p_cond boolean, p_detail text default null) returns void language sql as $$
  insert into _t(name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail) $$;
-- runs a statement, returns its SQLSTATE ('00000' when it ran)
create function pg_temp.st(p_sql text) returns text language plpgsql as $$
declare s text; begin execute p_sql; return '00000'; exception when others then get stacked diagnostics s = returned_sqlstate; return s; end $$;
-- the same call with null for every argument (a closed function refuses before running)
create function pg_temp.nullcall(f regprocedure) returns text language sql as $$
  select format('select %s(%s)', p.oid::regproc, coalesce((select string_agg('null', ', ') from unnest(p.proargtypes)), ''))
    from pg_proc p where p.oid = f $$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

do $$ begin
  if exists (select 1 from public.customers where phone like '709998__') or exists (select 1 from public.merchants where phone like '709998__')
     or exists (select 1 from public.admin_users where username like 'tp_p0_test_%') then
    raise exception 'test fixtures already exist — tests stopped';
  end if;
end $$;

insert into public.customers(phone, pin_hash, name, status) values
  ('70999801', extensions.crypt('1234', extensions.gen_salt('bf', 4)), 'زبون اختبار', 'active'),
  ('70999804', extensions.crypt('1234', extensions.gen_salt('bf', 4)), 'زبون اختبار 2', 'active');
insert into public.merchants(id, name, phone, pin_hash, status) values
  ('00000000-0000-4000-8000-0000000008a1', 'p0 test shop', '70999802', extensions.crypt('4321', extensions.gen_salt('bf', 4)), 'active');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000008b1', 'tp_p0_test_primary', extensions.crypt('9999', extensions.gen_salt('bf', 4)), true),
  ('00000000-0000-4000-8000-0000000008b2', 'tp_p0_test_second',  extensions.crypt('9999', extensions.gen_salt('bf', 4)), true);

-- the closed list, from the database itself
create temp table _closed on commit drop as
  select p.oid::regprocedure f from pg_proc p where p.pronamespace = 'public'::regnamespace and (
         p.proname in ('customer_reset_pin','customer_set_pin','admin_grant_customer_gift','admin_delete_topup_order_only',
                       'whish_confirm_payment','whish_set_collect_url','_expire_topup_orders','customer_check_welcome_expiry',
                       'customer_notes_mark_read','merchant_notes_mark_read','_test_noop','merchant_reset_pin','admin_wipe_all_data',
                       '_rl_locked','_rl_record_fail','_rl_reset','_tp_wipe_scope','_tp_wipe_snapshot','_tp_wipe_restore','_tp_wipe_drop',
                       '_phase0_selfcheck')
      or (p.proname = 'customer_register' and p.pronargs in (3, 5)) or (p.proname = 'merchant_register' and p.pronargs in (11, 12, 13, 14))
      or (p.proname = 'merchant_add_offer' and p.pronargs = 14) or (p.proname = 'admin_update_merchant_location' and p.pronargs = 6));
create temp table _counts on commit drop as select (select count(*) from public.merchants) m, (select count(*) from public.customers) c;
grant select on _closed, _counts to anon, authenticated, service_role;

-- ================================================================ 1) permission matrix
do $$ declare rl text; f regprocedure; s text; n int := 0; bad text; begin
  foreach rl in array array['anon', 'authenticated'] loop
    execute format('set local role %I', rl);
    n := 0; bad := null;
    for f in select x.f from _closed x loop
      if has_function_privilege(rl, f, 'EXECUTE') then s := 'OPEN';   -- an open function is reported, never called
      else s := pg_temp.st(pg_temp.nullcall(f)); end if;
      n := n + 1; if s <> '42501' then bad := concat_ws(', ', bad, f::text || '=' || s); end if;
    end loop;
    perform pg_temp.ok(rl || ': every closed function is denied when called (' || n || ' functions)', bad is null and n >= 20, bad);
    if has_function_privilege(rl, 'public.admin_wipe_all_data(uuid,text)', 'EXECUTE') then s := 'OPEN, not called';
    else s := pg_temp.st($q$select public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008b1', '9999')$q$); end if;
    perform pg_temp.ok(rl || ': wipe with a valid primary admin and the RIGHT PIN is denied', s = '42501', s);
    s := pg_temp.st($q$select count(*) from public.auth_rate_limits$q$);
    perform pg_temp.ok(rl || ': cannot read the rate-limit table', s = '42501', s);
    s := pg_temp.st($q$insert into public.auth_rate_limits(key) values ('customer:70999801')$q$);
    perform pg_temp.ok(rl || ': cannot write the rate-limit table', s = '42501', s);
    s := pg_temp.st($q$delete from public.auth_rate_limits$q$);
    perform pg_temp.ok(rl || ': cannot clear the rate-limit table (unlock itself)', s = '42501', s);
    s := pg_temp.st($q$select public._rl_reset('customer:70999801')$q$);
    perform pg_temp.ok(rl || ': cannot reset a lock through the helper', s = '42501', s);
    s := pg_temp.st($q$select count(*) from tp_backup.wipe_runs$q$);
    perform pg_temp.ok(rl || ': cannot open the backup schema', s = '42501', s);
    execute 'reset role';
  end loop;
end $$;
do $$ begin
  perform pg_temp.ok('the denied calls deleted nothing',
    (select m from _counts) = (select count(*) from public.merchants) and (select c from _counts) = (select count(*) from public.customers));
end $$;

set local role service_role;
do $$ declare s text; begin
  s := pg_temp.st($q$select public.whish_confirm_payment(gen_random_uuid(), 'success', null, null)$q$);
  perform pg_temp.ok('service_role (Whish callback) can still call whish_confirm_payment', s <> '42501', s);
  s := pg_temp.st($q$select public._expire_topup_orders()$q$);
  perform pg_temp.ok('service_role (server job) can still call _expire_topup_orders', s <> '42501', s);
  s := pg_temp.st($q$select public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008b1', '9999')$q$);
  perform pg_temp.ok('service_role: wipe with the right PIN is denied too', s = '42501', s);
  s := pg_temp.st($q$select public._tp_wipe_restore('x')$q$);
  perform pg_temp.ok('service_role: restore is owner-only', s = '42501', s);
  s := pg_temp.st($q$select count(*) from tp_backup.wipe_runs$q$);
  perform pg_temp.ok('service_role: cannot open the backup schema', s = '42501', s);
end $$;
reset role;
do $$ begin
  perform pg_temp.ok('nothing deleted by the service_role attempts',
    (select m from _counts) = (select count(*) from public.merchants) and (select c from _counts) = (select count(*) from public.customers));
end $$;

-- ================================================================ 2) the app's calls still work (as anon)
set local role anon;
do $$ declare r jsonb; s text; begin
  r := public.customer_verify_pin('70999801', '1234');
  perform pg_temp.ok('app: customer login works', (r->>'ok')::boolean, left(r::text, 80));
  r := public.merchant_verify_pin('70999802', '4321');
  perform pg_temp.ok('app: merchant login works', (r->>'ok')::boolean, left(r::text, 80));
  r := public.admin_verify_pin('tp_p0_test_primary', '9999');
  perform pg_temp.ok('app: admin login works', (r->>'ok')::boolean, left(r::text, 80));
  s := pg_temp.st($q$select public.customer_check_phone('70999801')$q$);
  perform pg_temp.ok('app: phone check on the login screen works', s = '00000', s);
  s := pg_temp.st($q$select public.customer_register('70999803', '1234', 'تسجيل اختبار', 0, 0, null)$q$);
  perform pg_temp.ok('app: the registration the app uses (6 arguments) runs', s = '00000', s);
end $$;
reset role;

-- ================================================================ 3) PIN locks (as anon, the way the app calls)
set local role anon;
do $$ declare r jsonb; i int; begin
  -- a right PIN before the 5th wrong one clears the count
  for i in 1..4 loop r := public.customer_verify_pin('70999801', '0000'); end loop;
  r := public.customer_verify_pin('70999801', '1234');
  perform pg_temp.ok('customer: 4 wrong then the right PIN logs in', (r->>'ok')::boolean, r->>'reason');
  for i in 1..4 loop r := public.customer_verify_pin('70999801', '0000'); end loop;
  r := public.customer_verify_pin('70999801', '1234');
  perform pg_temp.ok('customer: the right PIN reset the count (4 more wrong still not locked)', (r->>'ok')::boolean, r->>'reason');
  for i in 1..5 loop r := public.customer_verify_pin('70999801', '0000'); end loop;
  perform pg_temp.ok('customer: the 5th wrong PIN still says wrong_pin', r->>'reason' = 'wrong_pin', r::text);
  r := public.customer_verify_pin('70999801', '1234');
  perform pg_temp.ok('customer: then locked, even with the right PIN', r->>'reason' = 'locked', r::text);
  r := public.customer_verify_pin('70999804', '1234');
  perform pg_temp.ok('customer: another account is not affected by that lock', (r->>'ok')::boolean, r->>'reason');
  for i in 1..5 loop r := public.customer_verify_pin('70999899', '1234'); end loop;
  r := public.customer_verify_pin('70999899', '1234');
  perform pg_temp.ok('customer: guessing an unknown number is limited too', r->>'reason' = 'locked', r::text);
  -- admin login
  for i in 1..5 loop r := public.admin_verify_pin('tp_p0_test_second', '0000'); end loop;
  r := public.admin_verify_pin('tp_p0_test_second', '9999');
  perform pg_temp.ok('admin: 5 wrong PINs lock the admin login', r->>'reason' = 'locked', r::text);
  r := public.admin_verify_pin('TP_P0_TEST_SECOND', '9999');
  perform pg_temp.ok('admin: changing upper/lower case does not escape the lock', coalesce(r->>'reason', '') <> 'wrong_pin' and not coalesce((r->>'ok')::boolean, false), r::text);
  r := public.admin_verify_pin('tp_p0_test_primary', '9999');
  perform pg_temp.ok('admin: the other admin still logs in', (r->>'ok')::boolean, r->>'reason');
  -- merchant (October)
  for i in 1..5 loop r := public.merchant_verify_pin('70999802', '0000'); end loop;
  r := public.merchant_verify_pin('70999802', '4321');
  perform pg_temp.ok('October: merchant login locked after 5 wrong PINs', r->>'reason' = 'locked' or r->>'error' ilike '%15%', left(r::text, 120));
  -- October shared admin key: 5 wrong on admin_reset_merchant_pin lock that admin's sensitive actions
  for i in 1..5 loop r := public.admin_reset_merchant_pin('00000000-0000-4000-8000-0000000008b1', '0000', '00000000-0000-4000-8000-0000000008a1', '1111'); end loop;
  r := public.admin_reset_merchant_pin('00000000-0000-4000-8000-0000000008b1', '9999', '00000000-0000-4000-8000-0000000008a1', '1111');
  perform pg_temp.ok('October: admin_reset_merchant_pin locked after 5 wrong admin PINs', r->>'reason' = 'locked', r::text);
end $$;
reset role;
-- the lock ends after its time (moved to the past here instead of waiting 15 minutes)
update public.auth_rate_limits set locked_until = now() - interval '1 second' where key = 'customer:70999801';
set local role anon;
do $$ declare r jsonb; begin
  r := public.customer_verify_pin('70999801', '1234');
  perform pg_temp.ok('customer: after the lock time the right PIN works again', (r->>'ok')::boolean, r::text);
end $$;
reset role;
do $$ begin
  perform pg_temp.ok('customer: the successful login cleared the record', not exists (
    select 1 from public.auth_rate_limits where key = 'customer:70999801' and (fail_count > 0 or locked_until > now())));
end $$;

-- the wipe shares the October key 'admin:<id>' (locked above by admin_reset_merchant_pin) — owner path
do $$ declare r jsonb; begin
  r := public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008b1', '9999');
  perform pg_temp.ok('wipe: the lock of admin_reset_merchant_pin also stops the wipe (shared key), even for the owner',
    r->>'reason' = 'locked' and (select m from _counts) = (select count(*) from public.merchants), r::text);
end $$;
delete from public.auth_rate_limits where key = 'admin:00000000-0000-4000-8000-0000000008b1';
do $$ declare r jsonb; begin
  r := public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008b1', '0000');
  perform pg_temp.ok('wipe: a wrong PIN is refused and deletes nothing', not (r->>'ok')::boolean and r->>'error' = 'رمز الإدارة غير صحيح'
    and exists (select 1 from public.merchants where phone = '70999802'), r::text);
  r := public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008ff', '9999');
  perform pg_temp.ok('wipe: an unknown admin id is refused and deletes nothing', not (r->>'ok')::boolean
    and exists (select 1 from public.merchants where phone = '70999802'), r::text);
end $$;

-- ================================================================ 4) wipe → copy → restore (owner path)
do $$ declare t regclass; h text; n bigint; begin
  create temp table _snap(tname text, n bigint, h text) on commit drop;
  foreach t in array public._tp_wipe_scope() loop
    execute format('select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from %s r', t) into n, h;
    insert into _snap values (t::text, n, h);
  end loop;
  perform pg_temp.ok('scope: merchants, customers and the tables pointing to them (' || (select count(*) from _snap) || ' tables)',
    (select count(*) from _snap) >= 3 and exists (select 1 from _snap where tname = 'merchants') and exists (select 1 from _snap where tname = 'customers'));
end $$;
do $$ declare r jsonb; e int; stamp text; begin
  r := public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008b1', '9999');
  stamp := r->>'snapshot';
  select count(*) into e from _snap s where (select count(*) from tp_backup.wipe_runs w, jsonb_array_elements(w.tables) x
                                              where w.stamp = r->>'snapshot' and x->>'t' = s.tname and (x->>'rows')::bigint = s.n) = 1;
  perform pg_temp.ok('owner wipe: answers ok with the copy stamp', (r->>'ok')::boolean and stamp like 'w2%', r::text);
  perform pg_temp.ok('owner wipe: the copy has every table with the same row counts', e = (select count(*) from _snap), e::text);
  perform pg_temp.ok('owner wipe: merchants and customers are empty', not exists (select 1 from public.merchants) and not exists (select 1 from public.customers));
  create temp table _stamp on commit drop as select stamp;
end $$;
do $$ declare r jsonb; t text; vn bigint; vh text; bad text; begin
  r := public._tp_wipe_restore((select stamp from _stamp));
  for t in select s.tname from _snap s loop
    execute format('select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from public.%I r', t) into vn, vh;
    if not exists (select 1 from _snap s where s.tname = t and s.n = vn and s.h = vh) then bad := concat_ws(', ', bad, t); end if;
  end loop;
  perform pg_temp.ok('restore: every table is back, same rows and same checksum', (r->>'ok')::boolean and bad is null, coalesce(bad, r::text));
  perform pg_temp.ok('restore: the test accounts log in again', (public.customer_verify_pin('70999804', '1234')->>'ok')::boolean);
  perform pg_temp.ok('restore: the copy is marked restored', exists (select 1 from tp_backup.wipe_runs where stamp = (select stamp from _stamp) and restored_at is not null));
  perform pg_temp.ok('restore: a second restore of the same copy is refused', pg_temp.st(format('select public._tp_wipe_restore(%L)', (select stamp from _stamp))) = 'P0001');
end $$;
do $$ declare r jsonb; vstamp text; s text; begin
  r := public.admin_wipe_all_data('00000000-0000-4000-8000-0000000008b1', '9999');
  vstamp := r->>'snapshot';
  insert into public.customers(phone, pin_hash, name, status) values ('70999805', 'x', 'بعد المسح', 'active');
  s := pg_temp.st(format('select public._tp_wipe_restore(%L)', vstamp));
  perform pg_temp.ok('restore: refused when the app was used after the wipe (no silent merge)', s = 'P0001'
    and (select count(*) from public.customers) = 1, s);
  delete from public.customers where phone = '70999805';
  perform pg_temp.ok('restore: works once the new rows are removed', (public._tp_wipe_restore(vstamp)->>'ok')::boolean);
  perform pg_temp.ok('drop copy: removes one table per copied table', public._tp_wipe_drop(vstamp) = (select count(*) from _snap));
  perform pg_temp.ok('drop copy: the run stays listed as dropped and cannot be restored', exists (
    select 1 from tp_backup.wipe_runs where wipe_runs.stamp = vstamp and dropped_at is not null)
    and not exists (select 1 from pg_tables where schemaname = 'tp_backup' and tablename like vstamp || '\_\_%'));
end $$;

-- self-check of the phase 0 file still passes after all of this
do $$ begin
  perform pg_temp.ok('phase 0 self-check passes', not exists (select 1 from public._phase0_selfcheck() where not ok));
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
