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


create or replace function public.customer_reset_pin(p_phone text, p_new_pin text) returns jsonb language sql security definer as $$ select '{"ok":true}'::jsonb $$;
create or replace function public.customer_set_pin(p_phone text, p_pin text, p_name text default 'x') returns jsonb language sql security definer as $$ select '{}'::jsonb $$;
create or replace function public.admin_grant_customer_gift(p_phone text, p_amount numeric, p_days integer) returns jsonb language sql security definer as $$ select '{}'::jsonb $$;
create or replace function public.admin_delete_topup_order_only(p_order_id uuid) returns jsonb language sql security definer as $$ select '{}'::jsonb $$;
create or replace function public.whish_confirm_payment(p_order_id uuid, p_result text, p_paid_amount numeric default null, p_external_id bigint default null) returns jsonb language sql security definer as $$ select '{}'::jsonb $$;
create or replace function public.whish_set_collect_url(p_order_id uuid, p_collect_url text, p_external_id bigint) returns jsonb language sql security definer as $$ select '{}'::jsonb $$;
create or replace function public.customer_notes_mark_read(p_phone text) returns jsonb language sql security definer as $$ select '{}'::jsonb $$;
create or replace function public.merchant_notes_mark_read(p_merchant_id uuid) returns jsonb language sql security definer as $$ select '{}'::jsonb $$;
create or replace function public._test_noop() returns integer language sql as $$ select 1 $$;
grant all on table public.auth_rate_limits to anon, authenticated;

-- login-screen phone check (exists on Production; body simplified for the local replica)
create or replace function public.customer_check_phone(p_phone text) returns jsonb
language sql security definer set search_path to 'public' as $$
  select jsonb_build_object('exists', exists (select 1 from public.customers where phone = p_phone)) $$;
