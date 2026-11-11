-- =====================================================================================================
-- Tripoli Points — PHASE 0: URGENT CLOSURES THAT NEED NO APP CHANGE          Prepared 2026-11-11 · NOT EXECUTED
-- =====================================================================================================
-- v1.3 · 2026-11-11 · run on STAGING first (instructions: tp-security-phase0-RUNBOOK.md), then Production.
-- Built on October 2026 (merchant PIN limit, _rl_* helpers, auth_rate_limits, merchant_reset_pin closed): it requires
-- them and changes none of them.
-- Part 0  pre-flight, nothing changed yet: October fixes present; customer_verify_pin, admin_verify_pin and
--         admin_wipe_all_data are exactly the reviewed versions (else STOP: the file would replace code it has not
--         seen); a picture of who may execute every function and use every table is kept for the final guard.
-- Part A  closes functions the app never calls to the public key. Whatever is already closed stays closed;
--         service_role keeps exactly the access it had (the Whish callback) and gains nothing it did not have.
-- Part B  wrong-PIN limit on customer_verify_pin and admin_verify_pin (same arguments and answers; October helpers, keys).
-- Part C  admin_wipe_all_data closed to every API key; every wipe first copies all affected tables into the private
--         schema tp_backup; owner-only restore with full content check; copies are never replaced or deleted
--         without an explicit, typed owner action. The app's «wipe» button stops working until phase 1.
-- Part D  rate-limit table closed to the API keys; lock releases are logged.
-- Part E  _phase0_selfcheck(): CALLS the functions as anon / authenticated inside a step that is undone.
-- Final   guard: no API key (anon, authenticated, service_role) may execute or use anything it could not before;
--         service_role loses nothing but the wipe; every closure still holds at the very end.
--         Any failed check or guard stops the file and undoes ALL of it (one transaction).
-- It changes no data: no customer, merchant, transaction, wallet, point or setting row is written.
-- Undo: tp-security-phase0-urgent-rollback.sql — by default it changes nothing; it only releases the PIN locks you
-- name, and re-checks every protection. Releasing every lock is a separate file with a typed confirmation
-- (tp-security-DANGEROUS-unlock-all-pin-locks.sql). Reopening functions: tp-security-DANGEROUS-reopen-phase0.sql.
-- =====================================================================================================
begin;

-- ---------------------------------------------------------------- 0) pre-flight (reads only)
do $$ declare v text; h text; okv text[]; begin
  -- October 2026 must be in place
  if to_regclass('public.auth_rate_limits') is null or to_regprocedure('public._rl_locked(text)') is null
     or to_regprocedure('public._rl_record_fail(text)') is null or to_regprocedure('public._rl_reset(text)') is null then
    raise exception 'STOP: the October 2026 fixes are missing on this database (auth_rate_limits / _rl_*). Nothing changed.';
  end if;
  if position('_rl_locked' in coalesce((select prosrc from pg_proc where oid = to_regprocedure('public.merchant_verify_pin(text,text)')), '')) = 0 then
    raise exception 'STOP: October merchant PIN limit not found in merchant_verify_pin. Nothing changed.';
  end if;
  -- the three functions this file replaces must be the reviewed code: the Production version of 2026-11-11, or this
  -- file's own version (re-run). Whitespace and letter case are ignored.
  foreach v in array array['customer_verify_pin(text,text)|c804486649aadaa57bc5a87fc8b6bcdf',
                           'admin_verify_pin(text,text)|a0e676d3290388fde1feae6f3d17564d',
                           'admin_wipe_all_data(uuid,text)|bd7d4982c8e56ca244c87eda058356f3'] loop
    okv := string_to_array(v, '|');
    select md5(regexp_replace(lower(prosrc), '\s+', '', 'g')) || case when prosrc like '%tp-phase0%' then ':p0' else '' end
      into h from pg_proc where oid = to_regprocedure('public.' || okv[1]);
    if h is null then raise exception 'STOP: public.% not found. Nothing changed.', okv[1]; end if;
    if h <> okv[2] and h not like '%:p0' then
      raise exception 'STOP: public.% differs from the reviewed version (fingerprint %). Nothing changed — send its definition for review.', okv[1], h;
    end if;
  end loop;
end $$;

-- who may do what before this file (compared at the end: nothing may be gained)
create temp table _p0_before on commit drop as
  select r.rol, 'f' as kind, p.oid as obj from pg_proc p, unnest(array['anon','authenticated','service_role']) r(rol)
   where p.pronamespace = 'public'::regnamespace and has_function_privilege(r.rol, p.oid, 'EXECUTE')
  union all
  select r.rol, 't', c.oid from pg_class c, unnest(array['anon','authenticated','service_role']) r(rol)
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v','m','p','f')
     and has_table_privilege(r.rol, c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER');

-- ---------------------------------------------------------------- A) close functions the app never calls
do $$ declare f regprocedure; n int := 0; svc boolean; begin
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
    svc := has_function_privilege('service_role', f, 'EXECUTE');   -- today, often only through PUBLIC
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    if svc then execute format('grant execute on function %s to service_role', f); end if;   -- kept, never added
    n := n + 1;
  end loop;
  raise notice 'phase 0: % function(s) closed to the public key', n;
end $$;

-- ---------------------------------------------------------------- B) wrong-PIN limit on customer and admin PIN checks
-- same signature and answers as today; after 5 wrong PINs the account answers {ok:false, reason:'locked'} for 15 minutes
create or replace function public.customer_verify_pin(p_phone text, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare r public.customers; rl_key text := 'customer:' || coalesce(p_phone, '');
begin -- tp-phase0
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
begin -- tp-phase0
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
-- a copy's record cannot be deleted or rewritten; restored / deleted are set once, by the functions below
create or replace function tp_backup._wipe_runs_guard() returns trigger language plpgsql as $g$
begin
  if tg_op = 'DELETE' then raise exception 'TP_BACKUP: copy records cannot be deleted (%).', old.stamp; end if;
  if new.stamp is distinct from old.stamp or new.made_at is distinct from old.made_at or new.made_by is distinct from old.made_by
     or new.admin_id is distinct from old.admin_id or new.tables is distinct from old.tables
     or (old.restored_at is not null and new.restored_at is distinct from old.restored_at)
     or (old.dropped_at is not null and new.dropped_at is distinct from old.dropped_at) then
    raise exception 'TP_BACKUP: copy record % cannot be rewritten.', old.stamp;
  end if;
  return new;
end $g$;
revoke all on function tp_backup._wipe_runs_guard() from public, anon, authenticated, service_role;
drop trigger if exists wipe_runs_guard on tp_backup.wipe_runs;
create trigger wipe_runs_guard before update or delete on tp_backup.wipe_runs for each row execute function tp_backup._wipe_runs_guard();
create or replace function tp_backup._no_truncate() returns trigger language plpgsql as $g$
begin raise exception 'TP_BACKUP: % cannot be emptied.', tg_table_name; end $g$;
revoke all on function tp_backup._no_truncate() from public, anon, authenticated, service_role;
drop trigger if exists wipe_runs_no_truncate on tp_backup.wipe_runs;
create trigger wipe_runs_no_truncate before truncate on tp_backup.wipe_runs for each statement execute function tp_backup._no_truncate();

-- every PIN lock released by hand is written here (who, when, why, the record as it was)
create table if not exists tp_backup.lock_releases(
  id bigint generated always as identity primary key, released_at timestamptz not null default now(),
  released_by text not null default current_user, reason text not null, key text not null, record jsonb not null);
revoke all on table tp_backup.lock_releases from public, anon, authenticated, service_role;
alter table tp_backup.wipe_runs enable row level security;
alter table tp_backup.lock_releases enable row level security;

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

-- C3) snapshot: a full copy of every table in the scope into tp_backup."<stamp>__<table>", recorded in wipe_runs with
-- the row count and a checksum of the whole content of each copy. A new copy never replaces an older one.
create or replace function public._tp_wipe_snapshot(p_by text, p_admin uuid default null) returns text
language plpgsql set search_path = public, pg_temp as $f$
declare stamp text := 'w' || to_char(clock_timestamp() at time zone 'UTC', 'YYYYMMDD_HH24MISS_US');
        t regclass; b text; n bigint; h text; info jsonb := '[]';
begin
  foreach t in array public._tp_wipe_scope() loop
    b := stamp || '__' || (select relname from pg_class where oid = t);
    if length(b) > 63 then raise exception 'TP_WIPE_NAME: % too long', b; end if;
    if to_regclass(format('tp_backup.%I', b)) is not null then raise exception 'TP_BACKUP: % already exists, never replaced', b; end if;
    execute format('create table tp_backup.%I as table %s', b, t);
    execute format('revoke all on table tp_backup.%I from public, anon, authenticated, service_role', b);
    execute format('alter table tp_backup.%I enable row level security', b);
    execute format('select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from tp_backup.%I r', b) into n, h;
    info := info || jsonb_build_object('t', t::text, 'b', b, 'rows', n, 'md5', h);
  end loop;
  insert into tp_backup.wipe_runs(stamp, made_by, admin_id, tables) values (stamp, coalesce(p_by, current_user), p_admin, info);
  return stamp;
end $f$;

-- C4) restore (owner only, SQL editor): first proves each copy is unchanged since it was made; puts every row back, parent tables first, keeps ids (identity columns too),
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
  -- the copy must be exactly what was saved (count + checksum of every column) before anything is put back
  for e in select x from jsonb_array_elements(run.tables) x loop
    if to_regclass(format('tp_backup.%I', e->>'b')) is null then raise exception 'TP_RESTORE: copy table % is missing — nothing restored', e->>'b'; end if;
    execute format('select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from tp_backup.%I r', e->>'b') into n, h2;
    if n <> (e->>'rows')::bigint or (e ? 'md5' and h2 <> e->>'md5') then
      raise exception 'TP_RESTORE: copy % was changed after it was made — nothing restored', e->>'b';
    end if;
  end loop;
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
  return jsonb_build_object('ok', true, 'stamp', p_stamp, 'tables', out, 'copy_kept', true);
end $f$;

-- C5) delete a copy: owner only, with the typed confirmation 'DELETE COPY <stamp>'. The record stays (dropped_at).
-- Nothing else ever deletes or replaces a copy (wipes, restores and re-runs of this file keep every copy).
create or replace function public._tp_wipe_drop(p_stamp text, p_confirm text) returns int
language plpgsql set search_path = public, pg_temp as $f$
declare e jsonb; n int := 0; run tp_backup.wipe_runs;
begin
  if p_confirm is distinct from 'DELETE COPY ' || p_stamp then
    raise exception 'TP_BACKUP: to delete copy % type exactly: DELETE COPY %', p_stamp, p_stamp;
  end if;
  select * into run from tp_backup.wipe_runs where stamp = p_stamp for update;
  if run.stamp is null or run.dropped_at is not null then raise exception 'TP_BACKUP: no live copy %', p_stamp; end if;
  for e in select x from jsonb_array_elements(run.tables) x loop
    execute format('drop table if exists tp_backup.%I', e->>'b'); n := n + 1;
  end loop;
  update tp_backup.wipe_runs set dropped_at = now() where stamp = p_stamp;
  return n;
end $f$;
drop function if exists public._tp_wipe_drop(text);   -- v1.2 form without confirmation

-- C6) the wipe itself: same arguments and answers as today, the October PIN limit (key 'admin:<id>', shared with
-- admin_reset_merchant_pin), a full copy before emptying anything, and the copy's stamp in the answer.
-- CLOSED to every API key (public, anon, authenticated, service_role): the app's «wipe» button stops working until
-- phase 1 (admin_wipe_all_data_v2: primary-admin session + PIN + typed confirmation + switch off by default).
create or replace function public.admin_wipe_all_data(p_admin_id uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare a public.admin_users; ok boolean; err text; stamp text; rl_key text := 'admin:' || coalesce(p_admin_id::text, '');
begin -- tp-phase0
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
                           'public._tp_wipe_restore(text)', 'public._tp_wipe_drop(text,text)'] loop
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
    -- service_role's access to whish_* is kept exactly as it was (checked by the final guard of the migration)
    res := res || jsonb_build_object('c', 'service_role cannot wipe, copy or restore', 'ok', not (
             has_function_privilege('service_role', 'public.admin_wipe_all_data(uuid,text)', 'EXECUTE')
             or has_function_privilege('service_role', 'public._tp_wipe_snapshot(text,uuid)', 'EXECUTE')
             or has_function_privilege('service_role', 'public._tp_wipe_restore(text)', 'EXECUTE')
             or has_function_privilege('service_role', 'public._tp_wipe_drop(text,text)', 'EXECUTE')), 'd', null);
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

-- ---------------------------------------------------------------- final guard: nothing gained by any API key
do $$ declare gained text; bk text; begin
  with now_ as (
    select r.rol, 'f' as kind, p.oid as obj, p.oid::regprocedure::text as name from pg_proc p, unnest(array['anon','authenticated','service_role']) r(rol)
     where p.pronamespace = 'public'::regnamespace and has_function_privilege(r.rol, p.oid, 'EXECUTE')
    union all
    select r.rol, 't', c.oid, c.oid::regclass::text from pg_class c, unnest(array['anon','authenticated','service_role']) r(rol)
     where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','v','m','p','f')
       and has_table_privilege(r.rol, c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))
  select string_agg(n.rol || ' → ' || n.name, ', ') into gained
    from now_ n where not exists (select 1 from _p0_before b where b.rol = n.rol and b.kind = n.kind and b.obj = n.obj);
  if gained is not null then raise exception 'STOP: phase 0 would give access that did not exist before: %. Nothing changed.', gained; end if;
  -- server jobs keep what they had: service_role loses nothing except the wipe (Whish callback, timers)
  select string_agg(b.obj::regprocedure::text, ', ') into gained from _p0_before b
   where b.rol = 'service_role' and b.kind = 'f' and b.obj <> 'public.admin_wipe_all_data(uuid,text)'::regprocedure
     and not has_function_privilege('service_role', b.obj, 'EXECUTE');
  if gained is not null then raise exception 'STOP: service_role (server jobs, Whish) would lose access to: %. Nothing changed.', gained; end if;
  -- and every closure still holds at the very end (nothing re-opened after the self-check)
  select string_agg(check_name, '; ') into gained from public._phase0_selfcheck() where not ok;
  if gained is not null then raise exception 'STOP: protection missing at the end: %. Nothing changed.', gained; end if;
  select string_agg(r.rol, ', ') into bk from unnest(array['anon','authenticated','service_role']) r(rol)
   where has_schema_privilege(r.rol, 'tp_backup', 'USAGE');
  if bk is not null then raise exception 'STOP: the backup schema would be reachable by %. Nothing changed.', bk; end if;
  raise notice 'phase 0 guard: no API key gained any access; % access(es) removed',
    (select count(*) from _p0_before b where not (case b.kind when 'f' then has_function_privilege(b.rol, b.obj, 'EXECUTE')
                                                    else has_table_privilege(b.rol, b.obj, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') end));
end $$;

commit;
