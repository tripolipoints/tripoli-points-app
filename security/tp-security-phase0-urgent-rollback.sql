-- Tripoli Points — PHASE 0 ROLLBACK: gives the public key back the functions phase 0 closed, and restores the
-- original customer_verify_pin and admin_verify_pin (copied from Production, 2026-11-11). Use only if phase 0 broke something.
begin;
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and (
        p.proname in ('customer_reset_pin','customer_set_pin','admin_grant_customer_gift','admin_delete_topup_order_only','whish_confirm_payment',
                      'whish_set_collect_url','_expire_topup_orders','customer_check_welcome_expiry','customer_notes_mark_read','merchant_notes_mark_read','_test_noop')
     or (p.proname = 'customer_register' and p.pronargs in (3, 5)) or (p.proname = 'merchant_register' and p.pronargs in (11, 12, 13, 14))
     or (p.proname = 'merchant_add_offer' and p.pronargs = 14) or (p.proname = 'admin_update_merchant_location' and p.pronargs = 6))
  loop execute format('grant execute on function %s to anon, authenticated', f); end loop;
end $$;

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
commit;
