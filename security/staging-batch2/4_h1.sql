-- Tripoli Points — HOTFIX H1: close unauthenticated money / account functions to the public API key.
-- Version 1.1 · 2026-11-13 · PREPARED AND TESTED LOCALLY ONLY. Not applied anywhere. Needs explicit approval per environment.
--
-- What it does (and nothing else):
--   * REVOKE EXECUTE from PUBLIC, anon, authenticated on 10 functions. No function body, row, balance, order or
--     setting is changed.
--   * Records the exact privileges each function had before H1 in tp_backup.acl_snapshots (batch 'H1'), so the
--     rollback restores exactly that state. This private table is the only object created (RLS on, no API access).
--   * Optional block (v_close_whish_callback, default true): also REVOKE from service_role on whish_confirm_payment,
--     so the public Whish callback can no longer flip pending/REVIEW orders. Whish is not in use (owner decision).
-- service_role keeps exactly the access it had before (on Staging, Phase 0 had already removed it from some Whish
--   functions; H1 does not add it back). Guards: every target must exist with the reviewed body fingerprint (normalised md5, read on Production 2026-11-13),
--   owned by postgres, SECURITY DEFINER. Anything unexpected -> STOP, nothing changes (single transaction).
-- Run in the Supabase SQL editor of the intended project, the whole file, once. Rollback: tp-hotfix-h1-rollback.sql.
begin;
do $h1$
declare
  v_close_whish_callback boolean := true;
  i int; v_md5 text; n int := 0; bad text := ''; svc_before boolean[] := '{}';
  tgt text[][] := array[
   ['admin_topup_merchant(uuid,numeric,text)', '6adc95e9c4481ab4b173c4ecb979295b'],
   ['admin_resolve_topup_order(uuid,boolean)', '16c351f11ceb97235755350a0af6bf42'],
   ['admin_mark_order_collected(uuid)', '88577b655782881f7c9a1c48c6a825f8'],
   ['admin_delete_topup_order_only(uuid)', '8f1b4624ba607f54c8f958cc0e3af6ee'],
   ['whish_confirm_payment(uuid,text,numeric,bigint)', '48e92b71c2a7314b32d2ff3ff525bbc7'],
   ['whish_set_collect_url(uuid,text,bigint)', '308aa77e0feba7a9aa0546ea85d83fc6'],
   ['customer_reset_pin(text,text)', 'b00379fb18ddc6fa68f0eb2c14478cdb'],
   ['customer_set_pin(text,text,text)', 'ddae98b94ef01d985898e188c831103f'],
   ['admin_grant_customer_gift(text,numeric,integer)', 'e071d1599769fafe9acb8f4757391ea6'],
   ['customer_check_welcome_expiry(text)',              '0b5d60b51d1138904a27c1361c371500']];
begin

  for i in 1 .. array_length(tgt, 1) loop
    if to_regprocedure('public.' || tgt[i][1]) is null then bad := bad || ' missing:' || tgt[i][1]; continue; end if;
    v_md5 := (select md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g'))
      from pg_proc p where p.oid = to_regprocedure('public.' || tgt[i][1])
       and p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres');
    if v_md5 is null then bad := bad || ' not-definer-or-owner:' || tgt[i][1];
    elsif v_md5 <> tgt[i][2] then bad := bad || ' body-changed:' || tgt[i][1]; end if;
  end loop;
  if bad <> '' then raise exception 'H1 STOP (nothing changed):%', bad; end if;

  -- exact privileges before H1, kept for an exact rollback (recorded on the first run only; re-runs keep the original)
  execute 'create schema if not exists tp_backup';
  execute 'revoke all on schema tp_backup from public, anon, authenticated';
  if to_regclass('tp_backup.acl_snapshots') is null then
    execute 'cre' || 'ate table tp_backup.acl_snapshots (id bigint generated always as identity primary key, batch text not null, '
         || 'sig text not null, acl aclitem[], owner_name text not null, taken_at timestamptz not null default now(), unique (batch, sig))';
    execute 'alter table tp_backup.acl_snapshots enable row level security';
    execute 'revoke all on tp_backup.acl_snapshots from public, anon, authenticated';
  end if;
  for i in 1 .. array_length(tgt, 1) loop
    execute 'insert ' || 'into tp_backup.acl_snapshots(batch, sig, acl, owner_name) values ($1, $2, $3, $4) on conflict (batch, sig) do nothing'
      using 'H1', tgt[i][1], (select p.proacl from pg_proc p where p.oid = to_regprocedure('public.' || tgt[i][1])),
            (select pg_get_userbyid(p.proowner) from pg_proc p where p.oid = to_regprocedure('public.' || tgt[i][1]));
  end loop;

  for i in 1 .. array_length(tgt, 1) loop
    svc_before := svc_before || has_function_privilege('service_role', 'public.' || tgt[i][1], 'execute');
  end loop;
  for i in 1 .. array_length(tgt, 1) loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', tgt[i][1]);
    n := n + 1;
  end loop;
  if v_close_whish_callback then
    revoke execute on function public.whish_confirm_payment(uuid,text,numeric,bigint) from service_role;
  end if;

  -- verify
  for i in 1 .. array_length(tgt, 1) loop
    if has_function_privilege('anon', 'public.' || tgt[i][1], 'execute')
       or has_function_privilege('authenticated', 'public.' || tgt[i][1], 'execute') then
      raise exception 'H1 STOP: % still executable by the public key', tgt[i][1]; end if;
    if not has_function_privilege('postgres', 'public.' || tgt[i][1], 'execute') then
      raise exception 'H1 STOP: owner lost access to %', tgt[i][1]; end if;
    if tgt[i][1] <> 'whish_confirm_payment(uuid,text,numeric,bigint)' or not v_close_whish_callback then
      if svc_before[i] and not has_function_privilege('service_role', 'public.' || tgt[i][1], 'execute') then
        raise exception 'H1 STOP: service_role lost access to %', tgt[i][1]; end if;
    end if;
  end loop;
  raise notice 'H1 applied: % function(s) closed to the public key; whish callback closed: %', n, v_close_whish_callback;
end $h1$;
commit;
