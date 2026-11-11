-- =====================================================================================================
-- Tripoli Points — PHASE 0 SAFE ROLLBACK · v1.3 · 2026-11-11 · Staging first, then Production
--
-- AS SHIPPED, THIS FILE CHANGES NOTHING. It lists the PIN locks that exist now and re-checks every protection.
-- It releases a lock ONLY for the accounts you write in v_keys below, each one explicitly, with a reason.
--
-- What it can never do (October rule: a routine rollback never reopens a closed vulnerability):
--   · release every lock at once — that is only in tp-security-DANGEROUS-unlock-all-pin-locks.sql (typed confirmation);
--   · put back a PIN check without the wrong-PIN limit — no function is defined in this file;
--   · reopen customer_reset_pin, whish_confirm_payment or any closed function, the rate-limit table, the wipe or the
--     backup schema — this file has no GRANT;
--   · delete or change a wipe copy in tp_backup.
-- If any protection is missing, it STOPS and undoes the whole run (released locks included).
--
-- Key format (exact, one per account):  customer:<phone>   merchant:<phone>   adminlogin:<username, lower case>
--                                        admin:<admin id>  (the admin's sensitive actions: merchant PIN reset, wipe)
--
-- Problem after phase 0                                   → what to do
--   one customer / merchant / admin is locked             → this file with that key in v_keys (or wait 15 minutes)
--   many accounts locked at once (an attack)              → wait 15 minutes; only if needed the DANGEROUS unlock-all file
--   the app's «wipe» button answers an error               → expected: closed until phase 1 (session + PIN + confirmation)
--   data was wiped by mistake (owner, SQL editor)          → select public._tp_wipe_restore('<stamp>');  (stamps: part 3)
--   the Whish callback stops confirming payments           → it must call with the service_role key: send me the error
--   a closed function is really needed by a server job     → send me which one; never re-grant it to anon
--   a PIN check returns an error / a check below fails     → re-run tp-security-phase0-urgent.sql, then this file
-- =====================================================================================================
begin;

-- 1) explicit unlock — EDIT ONLY THESE TWO LINES, nothing else in this file
do $$ declare
  v_keys   text[] := '{}';   -- e.g. array['customer:70123456']   or   array['adminlogin:rami', 'merchant:71111111']
  v_reason text   := '';     -- required when v_keys is not empty, e.g. 'customer called support, identity checked'
  k text; rec public.auth_rate_limits; n int := 0;
begin
  if to_regprocedure('public._phase0_selfcheck()') is null or to_regclass('tp_backup.lock_releases') is null then
    raise exception 'phase 0 (v1.3) is not applied on this database: nothing to roll back — nothing changed';
  end if;
  raise notice 'locks now: % account(s) locked, % with failed attempts',
    (select count(*) from public.auth_rate_limits where locked_until > now()), (select count(*) from public.auth_rate_limits);
  if cardinality(v_keys) = 0 then
    raise notice 'no account named in v_keys: no lock released (default)';
    return;
  end if;
  if length(btrim(v_reason)) < 5 then raise exception 'write the reason in v_reason — nothing changed'; end if;
  if cardinality(v_keys) > 20 then raise exception 'at most 20 accounts per run — nothing changed'; end if;
  foreach k in array v_keys loop
    if k !~ '^(customer|merchant):[0-9]{6,15}$' and k !~ '^adminlogin:[a-z0-9_.@-]{1,64}$'
       and k !~ '^admin:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'not an exact account key: "%" (patterns and wildcards are refused) — nothing changed', k;
    end if;
    select * into rec from public.auth_rate_limits where key = k;
    if rec.key is null then raise notice '% has no lock record (nothing to release)', k; continue; end if;
    insert into tp_backup.lock_releases(reason, key, record) values (btrim(v_reason), k, to_jsonb(rec));
    delete from public.auth_rate_limits where key = k;
    n := n + 1;
  end loop;
  raise notice 'released % lock record(s), logged in tp_backup.lock_releases', n;
end $$;

-- 2) every protection still in place, checked by calling the functions as anon / authenticated
do $$ declare bad text; n int; begin
  select string_agg(check_name || ' [' || coalesce(detail, '') || ']', '; '), count(*) into bad, n from public._phase0_selfcheck() where not ok;
  if bad is not null then
    raise exception 'STOP — % protection(s) missing: %. Nothing changed. Run tp-security-phase0-urgent.sql again.', n, bad;
  end if;
  raise notice 'all % behavioural checks pass: every protection stays', (select count(*) from public._phase0_selfcheck());
end $$;

commit;

-- 3) read only: locks left, last releases, wipe copies kept
select key, fail_count, locked_until from public.auth_rate_limits where locked_until > now() order by locked_until desc limit 50;
select released_at, released_by, key, reason from tp_backup.lock_releases order by released_at desc limit 20;
select stamp, made_at, made_by, restored_at, dropped_at,
       (select sum((x->>'rows')::bigint) from jsonb_array_elements(tables) x) as rows_copied
  from tp_backup.wipe_runs order by made_at desc;
