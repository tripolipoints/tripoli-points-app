-- =====================================================================================================
-- Tripoli Points — PHASE 0: URGENT CLOSURES THAT NEED NO APP CHANGE          Prepared 2026-11-11 · NOT EXECUTED
-- =====================================================================================================
-- Every function below is reachable today by anyone holding the public (anon) key, which ships inside the app.
-- None of them is called by the app (checked against index.html of main a54a85c and Staging):
--   · the Whish payment callback calls whish_* with the service_role key, which keeps its access;
--   · the old register / offer / location overloads are not the ones the app calls.
-- Part B adds a wrong-PIN limit to the customer and admin PIN checks and to admin_wipe_all_data (the merchant check,
-- merchant_set_logo and admin_reset_merchant_pin already have one since October), with the same arguments and answers.
-- It reuses the October helpers (_rl_locked / _rl_record_fail / _rl_reset, table auth_rate_limits) and their keys.
-- Part C removes the table grants the public key still has on auth_rate_limits (RLS hides the rows today; this
-- closes it one level higher, as October intended with REVOKE … FROM PUBLIC). Part D checks that it all took effect.
-- Run on STAGING first, test login (customer, merchant, admin) and a Whish payment, then the same file on Production.
-- Undo: tp-security-phase0-urgent-rollback.sql restores the three PIN functions only. Following the October rule,
-- a routine rollback never reopens a closed function; that lives only in tp-security-DANGEROUS-reopen-phase0.sql.
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

-- admin_wipe_all_data: same arguments, checks and answers as today, plus the October limit. The key 'admin:<id>' is the
-- one admin_reset_merchant_pin already uses, so wrong admin PINs on both actions count together.
create or replace function public.admin_wipe_all_data(p_admin_id uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare a public.admin_users; ok boolean; err text; rl_key text := 'admin:' || coalesce(p_admin_id::text, '');
begin
  if public._rl_locked(rl_key) then
    return jsonb_build_object('ok', false, 'reason', 'locked', 'error', 'عدد محاولات خاطئة كبير، حاول مجدداً بعد 15 دقيقة');
  end if;
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false) and a.pin_hash is not null and crypt(p_pin, a.pin_hash) = a.pin_hash;
  if a.id is not null and coalesce(a.is_primary,false) and not ok then perform public._rl_record_fail(rl_key); end if;
  if ok then perform public._rl_reset(rl_key); truncate table public.merchants, public.customers cascade; end if;
  err := case when a.id is null then 'جلسة غير صالحة، أعد تسجيل الدخول' when not coalesce(a.is_primary,false) then 'هذا الإجراء مسموح للأدمن الأساسي فقط' when not ok then 'رمز الإدارة غير صحيح' else null end;
  return jsonb_build_object('ok', ok, 'error', err);
end; $function$;

-- ---------------------------------------------------------------- C) the rate-limit table is not readable or writable with the public key
revoke all on table public.auth_rate_limits from public, anon, authenticated;

-- ---------------------------------------------------------------- D) check: everything above really took effect (stops the file otherwise)
do $$ declare bad text; begin
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'EXECUTE')
     and (p.proname in ('customer_reset_pin','customer_set_pin','admin_grant_customer_gift','admin_delete_topup_order_only','whish_confirm_payment','whish_set_collect_url','merchant_reset_pin')
          or (p.proname = 'customer_register' and p.pronargs in (3, 5)) or (p.proname = 'merchant_register' and p.pronargs in (11, 12, 13, 14)));
  if bad is not null then raise exception 'phase 0 check failed, still open: %', bad; end if;
  if has_table_privilege('anon', 'public.auth_rate_limits', 'SELECT') then raise exception 'phase 0 check failed: auth_rate_limits still readable'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('customer_verify_pin','admin_verify_pin','admin_wipe_all_data') and position('_rl_locked' in prosrc) > 0) < 3 then
    raise exception 'phase 0 check failed: a PIN function has no limit';
  end if;
  raise notice 'phase 0 check: all closed, all PIN checks limited';
end $$;

commit;
