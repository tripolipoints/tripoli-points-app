-- Tripoli Points — HOTFIX H1 ROLLBACK (emergency only). Restores the exact privileges read on Production 2026-11-13:
--   {=X/postgres, postgres=X, anon=X, authenticated=X, service_role=X} on each of the 10 functions.
-- WARNING: this REOPENS the vulnerabilities (anyone can top up wallets, take over customer accounts, grant points).
-- Use only if H1 broke something critical and a safer fix is not possible; tell the developer first.
begin;
do $rb$
declare s text; n int := 0;
begin
  foreach s in array array[
   'admin_topup_merchant(uuid,numeric,text)','admin_resolve_topup_order(uuid,boolean)','admin_mark_order_collected(uuid)',
   'admin_delete_topup_order_only(uuid)','whish_confirm_payment(uuid,text,numeric,bigint)','whish_set_collect_url(uuid,text,bigint)',
   'customer_reset_pin(text,text)','customer_set_pin(text,text,text)','admin_grant_customer_gift(text,numeric,integer)',
   'customer_check_welcome_expiry(text)'] loop
    if to_regprocedure('public.' || s) is null then raise exception 'ROLLBACK STOP: % missing', s; end if;
    execute format('grant execute on function public.%s to public, anon, authenticated, service_role', s);
    n := n + 1;
  end loop;
  raise notice 'H1 rolled back: % function(s) reopened (vulnerable again)', n;
end $rb$;
commit;
