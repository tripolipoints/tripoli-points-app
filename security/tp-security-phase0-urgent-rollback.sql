-- =====================================================================================================
-- Tripoli Points — PHASE 0 ROLLBACK (functional only)
-- Puts back the original customer_verify_pin, admin_verify_pin and admin_wipe_all_data (copied from Production,
-- 2026-11-11) in case the PIN limit causes a problem. It does NOT reopen any function phase 0 closed and does not give
-- the public key back the auth_rate_limits table: October rule — a routine rollback never reopens a closed vulnerability.
-- Reopening is only possible with tp-security-DANGEROUS-reopen-phase0.sql (all statements commented out).
-- =====================================================================================================
begin;
create or replace function public.customer_verify_pin(p_phone text, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare r public.customers;
begin
  select * into r from public.customers where phone = p_phone;
  if r is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.status <> 'active' then return jsonb_build_object('ok', false, 'reason', 'frozen'); end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public.customer_check_welcome_expiry(p_phone);
  select * into r from public.customers where phone = p_phone;
  return jsonb_build_object('ok', true, 'customer', jsonb_build_object(
    'phone', r.phone, 'name', r.name, 'last_name', r.last_name, 'photo_url', r.photo_url, 'points', r.points, 'status', r.status,
    'welcome_remain', r.welcome_remain, 'welcome_exp', r.welcome_exp));
end;
$function$;

create or replace function public.admin_verify_pin(p_username text, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare r public.admin_users;
begin
  select * into r from public.admin_users where username = p_username;
  if r is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  return jsonb_build_object('ok', true, 'admin', jsonb_build_object('id', r.id, 'username', r.username, 'is_primary', r.is_primary));
end; $function$;

create or replace function public.admin_wipe_all_data(p_admin_id uuid, p_pin text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' as $function$
declare a public.admin_users; ok boolean; err text;
begin
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false) and a.pin_hash is not null and crypt(p_pin, a.pin_hash) = a.pin_hash;
  if ok then truncate table public.merchants, public.customers cascade; end if;
  err := case when a.id is null then 'جلسة غير صالحة، أعد تسجيل الدخول' when not coalesce(a.is_primary,false) then 'هذا الإجراء مسموح للأدمن الأساسي فقط' when not ok then 'رمز الإدارة غير صحيح' else null end;
  return jsonb_build_object('ok', ok, 'error', err);
end; $function$;

-- safety check: the functions phase 0 closed are still closed after this rollback
do $$ declare bad text; begin
  select string_agg(p.oid::regprocedure::text, ', ') into bad from pg_proc p
   where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'EXECUTE')
     and p.proname in ('customer_reset_pin','admin_grant_customer_gift','whish_confirm_payment','whish_set_collect_url','merchant_reset_pin');
  if bad is not null then raise exception 'STOP: a closed function is open again (%). Investigate before continuing.', bad; end if;
end $$;
commit;
