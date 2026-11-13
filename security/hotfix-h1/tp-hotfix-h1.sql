-- Tripoli Points — HOTFIX H1: close unauthenticated money / account functions to the public API key.
-- Version 1.0 · 2026-11-13 · PREPARED AND TESTED LOCALLY ONLY. Not applied anywhere. Needs explicit approval per environment.
--
-- What it does (and nothing else):
--   * REVOKE EXECUTE from PUBLIC, anon, authenticated on 10 functions. No function body, table, row, balance,
--     order or setting is changed. No object is created.
--   * Optional block (v_close_whish_callback, default true): also REVOKE from service_role on whish_confirm_payment,
--     so the public Whish callback can no longer flip pending/REVIEW orders. Whish is not in use (owner decision).
-- Guards: every target must exist with the reviewed body fingerprint (normalised md5, read on Production 2026-11-13),
--   owned by postgres, SECURITY DEFINER. Anything unexpected -> STOP, nothing changes (single transaction).
-- Run in the Supabase SQL editor of the intended project, the whole file, once. Rollback: tp-hotfix-h1-rollback.sql.
begin;
do $h1$
declare
  v_close_whish_callback boolean := true;
  t record; v_md5 text; n int := 0; bad text := '';
begin
  create temp table _h1_targets(sig text primary key, md5 text) on commit drop;
  insert into _h1_targets values
   ('admin_topup_merchant(uuid,numeric,text)',          '6adc95e9c4481ab4b173c4ecb979295b'),
   ('admin_resolve_topup_order(uuid,boolean)',          '16c351f11ceb97235755350a0af6bf42'),
   ('admin_mark_order_collected(uuid)',                 '88577b655782881f7c9a1c48c6a825f8'),
   ('admin_delete_topup_order_only(uuid)',              '8f1b4624ba607f54c8f958cc0e3af6ee'),
   ('whish_confirm_payment(uuid,text,numeric,bigint)',  '48e92b71c2a7314b32d2ff3ff525bbc7'),
   ('whish_set_collect_url(uuid,text,bigint)',          '308aa77e0feba7a9aa0546ea85d83fc6'),
   ('customer_reset_pin(text,text)',                    'b00379fb18ddc6fa68f0eb2c14478cdb'),
   ('customer_set_pin(text,text,text)',                 'ddae98b94ef01d985898e188c831103f'),
   ('admin_grant_customer_gift(text,numeric,integer)',  'e071d1599769fafe9acb8f4757391ea6'),
   ('customer_check_welcome_expiry(text)',              '0b5d60b51d1138904a27c1361c371500');

  for t in select * from _h1_targets loop
    if to_regprocedure('public.' || t.sig) is null then bad := bad || ' missing:' || t.sig; continue; end if;
    select md5(regexp_replace(pg_get_functiondef(p.oid), '\s+', ' ', 'g')) into v_md5
      from pg_proc p where p.oid = to_regprocedure('public.' || t.sig)
       and p.prosecdef and pg_get_userbyid(p.proowner) = 'postgres';
    if v_md5 is null then bad := bad || ' not-definer-or-owner:' || t.sig;
    elsif v_md5 <> t.md5 then bad := bad || ' body-changed:' || t.sig; end if;
  end loop;
  if bad <> '' then raise exception 'H1 STOP (nothing changed):%', bad; end if;

  for t in select * from _h1_targets loop
    execute format('revoke execute on function public.%s from public, anon, authenticated', t.sig);
    n := n + 1;
  end loop;
  if v_close_whish_callback then
    revoke execute on function public.whish_confirm_payment(uuid,text,numeric,bigint) from service_role;
  end if;

  -- verify
  for t in select * from _h1_targets loop
    if has_function_privilege('anon', 'public.' || t.sig, 'execute')
       or has_function_privilege('authenticated', 'public.' || t.sig, 'execute') then
      raise exception 'H1 STOP: % still executable by the public key', t.sig; end if;
    if not has_function_privilege('postgres', 'public.' || t.sig, 'execute') then
      raise exception 'H1 STOP: owner lost access to %', t.sig; end if;
    if t.sig <> 'whish_confirm_payment(uuid,text,numeric,bigint)' or not v_close_whish_callback then
      if not has_function_privilege('service_role', 'public.' || t.sig, 'execute') then
        raise exception 'H1 STOP: service_role lost access to %', t.sig; end if;
    end if;
  end loop;
  raise notice 'H1 applied: % function(s) closed to the public key; whish callback closed: %', n, v_close_whish_callback;
end $h1$;
commit;
