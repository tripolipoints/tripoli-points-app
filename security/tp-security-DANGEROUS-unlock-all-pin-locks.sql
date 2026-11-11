-- =====================================================================================================
-- Tripoli Points — DANGEROUS ADMIN OPERATION: RELEASE EVERY PIN LOCK · v1.3 · 2026-11-11
-- NOT PART OF ANY ROLLBACK. NOT EXECUTED BY CLAUDE ON STAGING OR PRODUCTION.
--
-- ⚠ What it does: deletes EVERY record of public.auth_rate_limits — all customers, merchants and admins, including
--   the accounts that someone is trying to break into right now. Each attacker gets 5 new guesses per account at once.
-- ⚠ Use it only when many legitimate accounts are locked by mistake (for example a bug in the app sent wrong PINs),
--   AFTER the cause is fixed. During a guessing attack: do not use it — the locks are the protection; wait 15 minutes.
-- ⚠ For one or a few accounts use tp-security-phase0-urgent-rollback.sql (v_keys) instead.
--
-- Safety built in: as shipped it refuses (empty confirmation) and changes nothing. To run it you must type the
-- exact phrase and today's date (UTC) in v_confirm, and a reason. Every released record is copied to
-- tp_backup.lock_releases first. The protections are re-checked at the end; if one is missing, everything is undone.
-- It does not reopen any function, does not touch PIN checks, data, wallets or wipe copies.
-- =====================================================================================================
begin;

do $$ declare
  v_confirm text := '';   -- type exactly:  RELEASE ALL PIN LOCKS YYYY-MM-DD   (today's date, UTC)
  v_reason  text := '';   -- required: why every lock must go, who decided
  expected  text := 'RELEASE ALL PIN LOCKS ' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD');
  n int;
begin
  if to_regprocedure('public._phase0_selfcheck()') is null or to_regclass('tp_backup.lock_releases') is null then
    raise exception 'phase 0 (v1.3) is not applied on this database — nothing changed';
  end if;
  if v_confirm is distinct from expected then
    raise exception 'REFUSED: v_confirm must be exactly "%". Nothing changed. % record(s) stay.', expected, (select count(*) from public.auth_rate_limits);
  end if;
  if length(btrim(v_reason)) < 10 then raise exception 'REFUSED: write the reason in v_reason. Nothing changed.'; end if;
  insert into tp_backup.lock_releases(reason, key, record)
    select 'ALL: ' || btrim(v_reason), l.key, to_jsonb(l) from public.auth_rate_limits l;
  delete from public.auth_rate_limits;
  get diagnostics n = row_count;
  raise notice 'released % lock record(s); copies in tp_backup.lock_releases', n;
end $$;

do $$ declare bad text; begin
  select string_agg(check_name || ' [' || coalesce(detail, '') || ']', '; ') into bad from public._phase0_selfcheck() where not ok;
  if bad is not null then raise exception 'STOP — protection missing: %. Nothing changed.', bad; end if;
end $$;

commit;
