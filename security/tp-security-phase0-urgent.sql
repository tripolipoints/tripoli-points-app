-- =====================================================================================================
-- Tripoli Points — PHASE 0: URGENT CLOSURES THAT NEED NO APP CHANGE          Prepared 2026-11-11 · NOT EXECUTED
-- =====================================================================================================
-- Every function below is reachable today by anyone holding the public (anon) key, which ships inside the app.
-- None of them is called by the app (checked against index.html of main a54a85c and Staging):
--   · the Whish payment callback calls whish_* with the service_role key, which keeps its access;
--   · the old register / offer / location overloads are not the ones the app calls.
-- Part B adds a wrong-PIN limit to customer_verify_pin and admin_verify_pin (the merchant check, merchant_set_logo and
-- admin_reset_merchant_pin have had one since October), same arguments and answers, October helpers and keys.
-- Part C closes admin_wipe_all_data to every API key (public, anon, authenticated, service_role). A PIN limit alone is not
-- enough for an action that empties the database; the app's «wipe» button stops working until phase 1 brings
-- admin_wipe_all_data_v2 (primary-admin session + PIN + typed confirmation + switch off by default + snapshot first).
-- Every wipe now first copies all affected tables into the private schema tp_backup (not reachable with any API key);
-- the owner can put the data back from the SQL editor with _tp_wipe_restore('<stamp>') — the authorised path.
-- Part D closes the rate-limit table to the API keys. Part E installs _phase0_selfcheck(): it CALLS the functions as
-- anon / authenticated (not a text search), inside a step that is rolled back, and the file stops if any check fails.
-- Run on STAGING first, test login (customer, merchant, admin) and a Whish payment, then the same file on Production.
-- Undo: tp-security-phase0-urgent-rollback.sql. It never removes a protection: it clears the PIN locks (all, or one
-- account), re-checks every protection behaviourally, and says what to do for each kind of problem.
-- Anything that reopens a function to the app key is only in tp-security-DANGEROUS-reopen-phase0.sql (commented out).
-- =====================================================================================================
begin;

-- ---------------------------------------------------------------- A) close functions the app never calls
do $$ declare f regprocedure; n int := 0; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and (
        p.proname in ('customer_reset_pin',            -- anyone sets a new PIN for any phone number → account takeover
                      'customer_set_pin',              -- creates accounts with no checks
                      'admin_grant_customer_gift',     -- anyone adds points to any customer
                      'admin_delete_topup_order_only', -- anyone deletes top-up orders
                      'whish_confirm_payment',         -- anyone marks a top-up as paid → free wallet credit
                      'whish_set_collect_url',         -- anyone rewrites the payment link of an order
                      '_expire_topup_orders', 'customer_check_welcome_expiry',
                      'customer_notes_mark_read', 'merchant_notes_mark_read', '_test_noop')
     or (p.proname = 'customer_register' and p.pronargs in (3, 5))          -- old overloads (the app uses the 6-argument one)
     or (p.proname = 'merchant_register' and p.pronargs in (11, 12, 13, 14)) -- old overloads (the app uses the 15-argument one)
     or (p.proname = 'merchant_add_offer' and p.pronargs = 14)               -- old overload (the app uses the 15-argument one)
     or (p.proname = 'admin_update_merchant_location' and p.pronargs = 6))   -- old overload (the app uses the 7-argument one)
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
    n := n + 1;
  end loop;
  raise notice 'phase 0: % function(s) closed to the public key', n;
end $$;

-- ---------------------------------------------------------------- B) wrong-PIN limit on customer and admin PIN checks
-- same signature and answers as today; after 5 wrong PINs the account answers {ok:false, reason:'locked'} for 15 minutes
create or replace function public.customer_verify_pin(p_phone text, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare r public.customers; rl_key text := 'customer:' || coalesce(p_phone, '');
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.customers where phone = p_phone;
  if r is null then perform public._rl_record_fail(rl_key); return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.status <> 'active' then return jsonb_build_object('ok', false, 'reason', 'frozen'); end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl_reset(rl_key);
  perform public.customer_check_welcome_expiry(p_phone);
  select * into r from public.customers where phone = p_phone;
  return jsonb_build_object('ok', true, 'customer', jsonb_build_object(
    'phone', r.phone, 'name', r.name, 'last_name', r.last_name, 'photo_url', r.photo_url, 'points', r.points, 'status', r.status,
    'welcome_remain', r.welcome_remain, 'welcome_exp', r.welcome_exp));
end;
$function$;

create or replace function public.admin_verify_pin(p_username text, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare r public.admin_users; rl_key text := 'adminlogin:' || lower(coalesce(p_username, ''));
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.admin_users where username = p_username;
  if r is null then perform public._rl_record_fail(rl_key); return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl_reset(rl_key);
  return jsonb_build_object('ok', true, 'admin', jsonb_build_object('id', r.id, 'username', r.username, 'is_primary', r.is_primary));
end; $function$;

-- ---------------------------------------------------------------- C) admin_wipe_all_data: closed, and never without a copy
-- C1) private backup schema: not exposed to the API (no USAGE for any API key); only the owner (SQL editor) reads it.
create schema if not exists tp_backup;
revoke all on schema tp_backup from public, anon, authenticated, service_role;
create table if not exists tp_backup.wipe_runs(
  stamp text primary key, made_at timestamptz not null default now(), made_by text not null, admin_id uuid,
  tables jsonb not null, restored_at timestamptz, restored_by text, dropped_at timestamptz);
revoke all on table tp_backup.wipe_runs from public, anon, authenticated, service_role;

-- C2) the tables a wipe empties: merchants, customers and every table that points to them (what TRUNCATE … CASCADE
-- reaches), in parent-first order so a restore never breaks a foreign key. Computed each time, so tables added later
-- (phase 1, e-mail) are covered without editing this file.
create or replace function public._tp_wipe_scope() returns regclass[]
language plpgsql set search_path = public, pg_temp as $f$
declare todo oid[]; done oid[] := '{}'; nxt oid[]; t oid;
begin
  with recursive s(rel) as (
      select c.oid from pg_class c where c.oid in ('public.merchants'::regclass, 'public.customers'::regclass)
      union select k.conrelid from pg_constraint k join s on k.confrelid = s.rel where k.contype = 'f')
  select array_agg(rel) into todo from s;
  while cardinality(todo) > 0 loop
    nxt := array(select x from unnest(todo) x where not exists (
             select 1 from pg_constraint k where k.contype = 'f' and k.conrelid = x and k.confrelid <> x
                and k.confrelid = any(todo)));
    if cardinality(nxt) = 0 then raise exception 'TP_WIPE_SCOPE: circular foreign keys between %', todo::regclass[]; end if;
    done := done || array(select x from unnest(nxt) x order by x::regclass::text);
    todo := array(select x from unnest(todo) x where x <> all(nxt));
  end loop;
  return done::regclass[];
end $f$;

-- C3) snapshot: a full copy of every table in the scope into tp_backup."<stamp>__<table>", recorded in wipe_runs.
create or replace function public._tp_wipe_snapshot(p_by text, p_admin uuid default null) returns text
language plpgsql set search_path = public, pg_temp as $f$
declare stamp text := 'w' || to_char(clock_timestamp() at time zone 'UTC', 'YYYYMMDD_HH24MISS_US');
        t regclass; b text; n bigint; info jsonb := '[]';
begin
  foreach t in array public._tp_wipe_scope() loop
    b := stamp || '__' || (select relname from pg_class where oid = t);
    if length(b) > 63 then raise exception 'TP_WIPE_NAME: % too long', b; end if;
    execute format('create table tp_backup.%I as table %s', b, t);
    execute format('revoke all on table tp_backup.%I from public, anon, authenticated, service_role', b);
    execute format('select count(*) from tp_backup.%I', b) into n;
    info := info || jsonb_build_object('t', t::text, 'b', b, 'rows', n);
  end loop;
  insert into tp_backup.wipe_runs(stamp, made_by, admin_id, tables) values (stamp, coalesce(p_by, current_user), p_admin, info);
  return stamp;
end $f$;

-- C4) restore (owner only, SQL editor): puts every row back, parent tables first, keeps ids (identity columns too),
-- with user triggers paused so restored rows do not fire app logic again; resets id sequences; then compares every
-- table with its copy (row count + checksum over the copied columns) and undoes everything if one differs.
-- Refuses if a table already has rows again (the app was used after the wipe): nothing is merged silently. Only
-- sessions, e-mail codes and purchase QRs created since the wipe are replaced (they are short-lived by design).
create or replace function public._tp_wipe_restore(p_stamp text) returns jsonb
language plpgsql set search_path = public, pg_temp as $f$
declare run tp_backup.wipe_runs; e jsonb; t regclass; b text; cols text; n bigint; busy text; out jsonb := '[]';
        h1 text; h2 text; sq record;
begin
  select * into run from tp_backup.wipe_runs where stamp = p_stamp for update;
  if run.stamp is null then raise exception 'TP_RESTORE: no snapshot %', p_stamp; end if;
  if run.restored_at is not null then raise exception 'TP_RESTORE: snapshot % was already restored at %', p_stamp, run.restored_at; end if;
  if run.dropped_at is not null then raise exception 'TP_RESTORE: snapshot % was deleted', p_stamp; end if;
  for e in select x from jsonb_array_elements(run.tables) x loop
    continue when (e->>'t') in ('app_sessions', 'email_tokens', 'purchase_codes');   -- short-lived, see below
    execute format('select count(*) from %s', (e->>'t')::regclass) into n;
    if n > 0 then busy := concat_ws(', ', busy, (e->>'t') || ' (' || n || ')'); end if;
  end loop;
  if busy is not null then raise exception 'TP_RESTORE: these tables have rows again, restore refused: %', busy; end if;
  -- logins, e-mail codes and purchase QRs made after the wipe (e.g. the admin logging in again) are replaced by the copy
  for e in select x from jsonb_array_elements(run.tables) with ordinality q(x, i) order by i desc loop
    if (e->>'t') in ('app_sessions', 'email_tokens', 'purchase_codes') then execute format('delete from %s', (e->>'t')::regclass); end if;
  end loop;
  for e in select x from jsonb_array_elements(run.tables) x loop execute format('alter table %s disable trigger user', (e->>'t')::regclass); end loop;
  for e in select x from jsonb_array_elements(run.tables) x loop          -- stored in parent-first order
    t := (e->>'t')::regclass; b := e->>'b';
    select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into cols
      from pg_attribute a where a.attrelid = t and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
       and exists (select 1 from pg_attribute z where z.attrelid = format('tp_backup.%I', b)::regclass and z.attname = a.attname and not z.attisdropped);
    execute format('insert into %s (%s) overriding system value select %s from tp_backup.%I', t, cols, cols, b);
    execute format('select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from (select row(%s) r from %s) q', cols, t) into n, h1;
    execute format('select md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from (select row(%s) r from tp_backup.%I) q', cols, b) into h2;
    if n <> (e->>'rows')::bigint or h1 is distinct from h2 then
      raise exception 'TP_RESTORE: % differs from its copy (% of % rows) — nothing restored', t, n, e->>'rows';
    end if;
    for sq in select a.attname, pg_get_serial_sequence(t::text, a.attname) s from pg_attribute a
               where a.attrelid = t and a.attnum > 0 and not a.attisdropped and pg_get_serial_sequence(t::text, a.attname) is not null loop
      execute format('select setval(%L, coalesce((select max(%I) from %s), 1), (select max(%I) from %s) is not null)', sq.s, sq.attname, t, sq.attname, t);
    end loop;
    out := out || jsonb_build_object('table', t::text, 'rows', n);
  end loop;
  for e in select x from jsonb_array_elements(run.tables) x loop execute format('alter table %s enable trigger user', (e->>'t')::regclass); end loop;
  update tp_backup.wipe_runs set restored_at = now(), restored_by = current_user where stamp = p_stamp;
  return jsonb_build_object('ok', true, 'stamp', p_stamp, 'tables', out);
end $f$;

-- C5) delete a copy once it is no longer needed (owner only); the run stays listed as dropped.
create or replace function public._tp_wipe_drop(p_stamp text) returns int
language plpgsql set search_path = public, pg_temp as $f$
declare e jsonb; n int := 0;
begin
  for e in select x from jsonb_array_elements((select tables from tp_backup.wipe_runs where stamp = p_stamp and dropped_at is null)) x loop
    execute format('drop table if exists tp_backup.%I', e->>'b'); n := n + 1;
  end loop;
  update tp_backup.wipe_runs set dropped_at = now() where stamp = p_stamp;
  return n;
end $f$;

-- C6) the wipe itself: same arguments and answers as today, the October PIN limit (key 'admin:<id>', shared with
-- admin_reset_merchant_pin), a full copy before emptying anything, and the copy's stamp in the answer.
-- CLOSED to every API key (public, anon, authenticated, service_role): the app's «wipe» button stops working until
-- phase 1 (admin_wipe_all_data_v2: primary-admin session + PIN + typed confirmation + switch off by default).
create or replace function public.admin_wipe_all_data(p_admin_id uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare a public.admin_users; ok boolean; err text; stamp text; rl_key text := 'admin:' || coalesce(p_admin_id::text, '');
begin
  if public._rl_locked(rl_key) then
    return jsonb_build_object('ok', false, 'reason', 'locked', 'error', 'عدد محاولات خاطئة كبير، حاول مجدداً بعد 15 دقيقة');
  end if;
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false) and a.pin_hash is not null and crypt(p_pin, a.pin_hash) = a.pin_hash;
  if a.id is not null and coalesce(a.is_primary,false) and not ok then perform public._rl_record_fail(rl_key); end if;
  if ok then
    perform public._rl_reset(rl_key);
    stamp := public._tp_wipe_snapshot('admin:' || a.username, a.id);
    truncate table public.merchants, public.customers cascade;
  end if;
  err := case when a.id is null then 'جلسة غير صالحة، أعد تسجيل الدخول' when not coalesce(a.is_primary,false) then 'هذا الإجراء مسموح للأدمن الأساسي فقط' when not ok then 'رمز الإدارة غير صحيح' else null end;
  return jsonb_build_object('ok', ok, 'error', err, 'snapshot', stamp);
end; $function$;

do $$ declare f text; begin
  foreach f in array array['public.admin_wipe_all_data(uuid,text)', 'public._tp_wipe_scope()', 'public._tp_wipe_snapshot(text,uuid)',
                           'public._tp_wipe_restore(text)', 'public._tp_wipe_drop(text)'] loop
    execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
  end loop;
end $$;

-- ---------------------------------------------------------------- D) the rate-limit table is not readable or writable with the API keys
revoke all on table public.auth_rate_limits from public, anon, authenticated;

-- ---------------------------------------------------------------- E) behavioural self-check
-- Calls every closed function as anon and as authenticated (with empty arguments: a closed function refuses before
-- running; one found open is reported and never called), tries the rate-limit table and helpers, and exercises the PIN locks on throw-away accounts. All of it
-- happens inside a block that is rolled back, so it leaves no account, lock or row behind. Owner-only.
create or replace function public._phase0_selfcheck() returns table(check_name text, ok boolean, detail text)
language plpgsql set search_path = public, extensions, pg_temp as $sc$
declare res jsonb := '[]'::jsonb; f regprocedure; rl text; e text; r jsonb; i int; nm int; nc int;
  closed regprocedure[];
begin
  select array_agg(p.oid::regprocedure) into closed from pg_proc p
   where p.pronamespace = 'public'::regnamespace and (
         p.proname in ('customer_reset_pin','customer_set_pin','admin_grant_customer_gift','admin_delete_topup_order_only',
                       'whish_confirm_payment','whish_set_collect_url','_expire_topup_orders','customer_check_welcome_expiry',
                       'customer_notes_mark_read','merchant_notes_mark_read','_test_noop','merchant_reset_pin','admin_wipe_all_data',
                       '_rl_locked','_rl_record_fail','_rl_reset','_tp_wipe_scope','_tp_wipe_snapshot','_tp_wipe_restore','_tp_wipe_drop')
      or (p.proname = 'customer_register' and p.pronargs in (3, 5)) or (p.proname = 'merchant_register' and p.pronargs in (11, 12, 13, 14))
      or (p.proname = 'merchant_add_offer' and p.pronargs = 14) or (p.proname = 'admin_update_merchant_location' and p.pronargs = 6));
  begin
    -- throw-away accounts (rolled back with the block)
    insert into public.customers(phone, pin_hash, name, status) values ('tp-selfcheck-c', crypt('1234', gen_salt('bf', 4)), 'selfcheck', 'active');
    insert into public.admin_users(id, username, pin_hash, is_primary)
      values ('00000000-0000-4000-8000-00000000fff1', 'tp-selfcheck-admin', crypt('9999', gen_salt('bf', 4)), true);
    select count(*) into nm from public.merchants; select count(*) into nc from public.customers;
    foreach rl in array array['anon', 'authenticated'] loop
      execute format('set local role %I', rl);
      foreach f in array coalesce(closed, '{}') loop
        -- an open function is reported, never called (no side effect even in a rolled-back block)
        if has_function_privilege(rl, f::oid, 'EXECUTE') then
          res := res || jsonb_build_object('c', rl || ' cannot call ' || f::text, 'ok', false, 'd', 'OPEN to ' || rl);
          continue;
        end if;
        begin
          execute format('select %s(%s)', (select p.oid::regproc::text from pg_proc p where p.oid = f::oid),
                         (select coalesce(string_agg('null', ', '), '') from pg_proc p, unnest(p.proargtypes) where p.oid = f::oid));
          e := 'RAN';
        exception when insufficient_privilege then e := 'denied'; when others then e := 'RAN: ' || sqlerrm;
        end;
        res := res || jsonb_build_object('c', rl || ' cannot call ' || f::text, 'ok', e = 'denied', 'd', e);
      end loop;
      -- the app's wipe call, with a real primary admin and the RIGHT PIN, is refused and deletes nothing
      if has_function_privilege(rl, 'public.admin_wipe_all_data(uuid,text)', 'EXECUTE') then e := 'OPEN, not called';
      else
        begin perform public.admin_wipe_all_data('00000000-0000-4000-8000-00000000fff1', '9999'); e := 'RAN';
        exception when insufficient_privilege then e := 'denied'; end;
      end if;
      res := res || jsonb_build_object('c', rl || ': wipe with a valid primary admin and PIN is refused', 'ok', e = 'denied', 'd', e);
      begin execute 'select count(*) from public.auth_rate_limits'; e := 'RAN';
      exception when insufficient_privilege then e := 'denied'; end;
      res := res || jsonb_build_object('c', rl || ' cannot read the rate-limit table', 'ok', e = 'denied', 'd', e);
      begin execute $q$insert into public.auth_rate_limits(key) values ('tp-selfcheck')$q$; e := 'RAN';
      exception when insufficient_privilege then e := 'denied'; end;
      res := res || jsonb_build_object('c', rl || ' cannot write the rate-limit table', 'ok', e = 'denied', 'd', e);
      execute 'reset role';
    end loop;
    res := res || jsonb_build_object('c', 'no data deleted by the attempts', 'ok',
             (select count(*) from public.merchants) = nm and (select count(*) from public.customers) = nc, 'd', null);
    -- PIN locks, called as the app (anon)
    set local role anon;
    r := public.customer_verify_pin('tp-selfcheck-c', '1234');
    res := res || jsonb_build_object('c', 'customer: the right PIN works', 'ok', coalesce((r->>'ok')::boolean, false), 'd', r->>'reason');
    for i in 1..5 loop r := public.customer_verify_pin('tp-selfcheck-c', '0000'); end loop;
    r := public.customer_verify_pin('tp-selfcheck-c', '1234');
    res := res || jsonb_build_object('c', 'customer: locked after 5 wrong PINs, even with the right one', 'ok', r->>'reason' = 'locked', 'd', r::text);
    r := public.admin_verify_pin('tp-selfcheck-admin', '9999');
    res := res || jsonb_build_object('c', 'admin: the right PIN works', 'ok', coalesce((r->>'ok')::boolean, false), 'd', r->>'reason');
    for i in 1..5 loop r := public.admin_verify_pin('tp-selfcheck-admin', '0000'); end loop;
    r := public.admin_verify_pin('tp-selfcheck-admin', '9999');
    res := res || jsonb_build_object('c', 'admin: locked after 5 wrong PINs, even with the right one', 'ok', r->>'reason' = 'locked', 'd', r::text);
    reset role;
    res := res || jsonb_build_object('c', 'service_role (Whish callback) can still confirm payments', 'ok',
             coalesce(has_function_privilege('service_role', 'public.whish_confirm_payment(uuid,text,numeric,bigint)', 'EXECUTE'), true), 'd', null);
    res := res || jsonb_build_object('c', 'service_role cannot wipe, copy or restore', 'ok', not (
             has_function_privilege('service_role', 'public.admin_wipe_all_data(uuid,text)', 'EXECUTE')
             or has_function_privilege('service_role', 'public._tp_wipe_snapshot(text,uuid)', 'EXECUTE')
             or has_function_privilege('service_role', 'public._tp_wipe_restore(text)', 'EXECUTE')
             or has_function_privilege('service_role', 'public._tp_wipe_drop(text)', 'EXECUTE')), 'd', null);
    res := res || jsonb_build_object('c', 'no API key can open the backup schema', 'ok', not (
             has_schema_privilege('anon', 'tp_backup', 'USAGE') or has_schema_privilege('authenticated', 'tp_backup', 'USAGE')
             or has_schema_privilege('service_role', 'tp_backup', 'USAGE')), 'd', null);
    res := res || jsonb_build_object('c', 'the app can still call its PIN checks', 'ok',
             has_function_privilege('anon', 'public.customer_verify_pin(text,text)', 'EXECUTE')
             and has_function_privilege('anon', 'public.merchant_verify_pin(text,text)', 'EXECUTE')
             and has_function_privilege('anon', 'public.admin_verify_pin(text,text)', 'EXECUTE'), 'd', null);
    raise exception 'tp_selfcheck_rollback';
  exception when others then
    if sqlerrm <> 'tp_selfcheck_rollback' then raise; end if;
  end;
  return query select x->>'c', (x->>'ok')::boolean, x->>'d' from jsonb_array_elements(res) x;
end $sc$;
revoke all on function public._phase0_selfcheck() from public, anon, authenticated, service_role;

do $$ declare bad text; n int; begin
  select string_agg(check_name || ' [' || coalesce(detail, '') || ']', '; '), count(*) into bad, n from public._phase0_selfcheck() where not ok;
  if bad is not null then raise exception 'phase 0 self-check failed (% of the checks): %', n, bad; end if;
  raise notice 'phase 0 self-check: % behavioural checks passed', (select count(*) from public._phase0_selfcheck());
end $$;

commit;
