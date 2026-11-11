-- =====================================================================================================
-- Tripoli Points — PHASE 0 SAFE ROLLBACK · v1.2 · 2026-11-11 · run on Staging first, then Production
-- What it does NOT do (October rule: a routine rollback never reopens a closed vulnerability):
--   · it does not put back PIN checks without a wrong-PIN limit (customer, admin, wipe) — none exists in this file;
--   · it does not reopen any function phase 0 closed, nor the rate-limit table, nor the wipe, nor the backup schema.
-- What it does:
--   1) clears PIN locks: everyone (default) or only the accounts you list in v_keys — legitimate users get in again;
--   2) runs the behavioural self-check of phase 0 and STOPS (nothing changed) if any protection is missing;
--   3) lists the wipe copies kept in tp_backup (nothing deleted).
-- If a protection is missing or a PIN check misbehaves: run tp-security-phase0-urgent.sql again — it is idempotent and
-- recreates the limited versions. Reopening anything to the app key is only in tp-security-DANGEROUS-reopen-phase0.sql.
--
-- Problem after phase 0                                   → what to do
--   a customer / merchant / admin is locked (5 wrong PINs) → this file, with their key in v_keys (or all), or wait 15 min
--   the app's «wipe» button answers an error               → expected: closed until phase 1 (session + PIN + confirmation)
--   data was wiped by mistake (owner, SQL editor)          → select public._tp_wipe_restore('<stamp>');  (stamps: part 3)
--   the Whish callback stops confirming payments           → check it calls with the service_role key (it keeps access)
--   a closed function is really needed by a server job     → grant execute on function … to service_role;  never anon
--   a PIN check returns an error                           → re-run tp-security-phase0-urgent.sql, then this file
-- =====================================================================================================
begin;

-- 1) clear PIN locks. Keys: 'customer:<phone>', 'merchant:<phone>', 'adminlogin:<username, lower case>', 'admin:<admin id>'
do $$ declare
  v_keys text[] := '{}';            -- e.g. array['customer:70123456', 'adminlogin:rami'];  empty = clear every lock
  n int;
begin
  if cardinality(v_keys) = 0 then delete from public.auth_rate_limits;
  else delete from public.auth_rate_limits where key = any(v_keys); end if;
  get diagnostics n = row_count;
  raise notice 'phase 0 rollback: % lock record(s) cleared', n;
end $$;

-- 2) every protection still in place, checked by calling the functions as anon / authenticated
do $$ declare bad text; n int; begin
  if to_regprocedure('public._phase0_selfcheck()') is null then
    raise exception 'phase 0 is not applied on this database (no _phase0_selfcheck): nothing to roll back — nothing changed';
  end if;
  select string_agg(check_name || ' [' || coalesce(detail, '') || ']', '; '), count(*) into bad, n from public._phase0_selfcheck() where not ok;
  if bad is not null then
    raise exception 'STOP — % protection(s) missing: %. Nothing changed. Run tp-security-phase0-urgent.sql again.', n, bad;
  end if;
  raise notice 'phase 0 rollback: all % behavioural checks pass, every protection stays', (select count(*) from public._phase0_selfcheck());
end $$;

commit;

-- 3) wipe copies kept (read only)
select stamp, made_at, made_by, restored_at, dropped_at,
       (select sum((x->>'rows')::bigint) from jsonb_array_elements(tables) x) as rows_copied
  from tp_backup.wipe_runs order by made_at desc;
