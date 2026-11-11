-- =====================================================================================================
-- Tripoli Points — PHASE 0: URGENT CLOSURES THAT NEED NO APP CHANGE          Prepared 2026-11-11 · NOT EXECUTED
-- =====================================================================================================
-- Every function below is reachable today by anyone holding the public (anon) key, which ships inside the app.
-- None of them is called by the app (checked against index.html of main a54a85c and Staging):
--   · the Whish payment callback calls whish_* with the service_role key, which keeps its access;
--   · the old register / offer / location overloads are not the ones the app calls.
-- Part B adds a wrong-PIN limit to the customer and admin PIN checks (the merchant check already has one),
-- with the same arguments and answers; the app already shows the «locked» message for customers.
-- Run on STAGING first, test login (customer, merchant, admin) and a Whish payment, then the same file on Production.
-- Undo: tp-security-phase0-urgent-rollback.sql (grants back, original PIN functions back).
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

commit;
