-- generated from the structure export CSV; run on an EMPTY Supabase project
begin;
-- Tripoli Points structure export · postgres · 2026-11-11 21:01 UTC · no data rows except configuration
set check_function_bodies = false;
create extension if not exists pg_stat_statements with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create extension if not exists supabase_vault with schema vault;
create extension if not exists "uuid-ossp" with schema extensions;
create schema if not exists tp_dev;
create table if not exists public."user" (id uuid not null, full_name text not null, phone text not null, email text not null, points bigint not null, created_at timestamp with time zone not null);
create table if not exists public.admin_users (id uuid not null, username text not null, pin_hash text not null, is_primary boolean, created_at timestamp with time zone);
create table if not exists public.app_settings (key text not null, value numeric not null);
create table if not exists public.app_text_settings (key text not null, value text);
create table if not exists public.auth_rate_limits (key text not null, fail_count integer not null, locked_until timestamp with time zone, updated_at timestamp with time zone not null);
create table if not exists public.categories (id uuid not null, slug text not null, name_ar text not null, name_en text, parent_id uuid, icon text, color text, image text, sort_order integer not null, is_active boolean not null, created_at timestamp with time zone not null, updated_at timestamp with time zone not null);
create table if not exists public.customer_notes (id uuid not null, customer_phone text, type text, title text, body text, read boolean, created_at timestamp with time zone);
create table if not exists public.customer_requests (id uuid not null, merchant_id uuid, customer_phone text, invoice numeric not null, offer_id uuid, status text not null, created_at timestamp with time zone not null);
create table if not exists public.customer_unlocks (id uuid not null, customer_phone text, pic_id uuid, unlocked_at timestamp with time zone);
create table if not exists public.customers (phone text not null, pin_hash text, name text, last_name text, photo_url text, points bigint, status text, src text, created_at timestamp with time zone, welcome_remain numeric not null, welcome_exp timestamp with time zone, terms_version text, terms_accepted_at timestamp with time zone);
create table if not exists public.merchant_gallery (id uuid not null, merchant_id uuid not null, name text not null, price numeric, img_url text not null, display_order integer not null, created_at timestamp with time zone not null);
create table if not exists public.merchant_notes (id uuid not null, merchant_id uuid, type text, title text, body text, cta text, severity text, read boolean, created_at timestamp with time zone);
create table if not exists public.merchant_vips (id uuid not null, merchant_id uuid, customer_phone text, created_at timestamp with time zone, cap_points numeric);
create table if not exists public.merchants (id uuid not null, name text not null, owner text, phone text not null, pin_hash text, cat text, pct numeric, tier text, redeem_pct numeric, redeem_pct_vip numeric, x numeric, y numeric, lat numeric, lng numeric, addr text, photo_url text, photo_pending_url text, status text, poster_printed boolean, warns integer, created_at timestamp with time zone, pending_name text, pending_addr text, extra_cats text[] not null, terms_version text, terms_accepted_at timestamp with time zone, page_blurb text, page_enabled boolean not null, area text, logo_url text);
create table if not exists public.offers (id uuid not null, merchant_id uuid, type text not null, badge text, val numeric, gift_text text, pts numeric, per numeric, img_url text, old_price numeric, new_price numeric, min_amount numeric, days integer, first_time_only boolean, active boolean, created_at timestamp with time zone, deleted boolean, title text, specs text);
create table if not exists public.pos_transactions (id uuid not null, merchant_id uuid, customer_phone text, invoice numeric not null, redeem_pts bigint, redeem_val numeric, net numeric, earn bigint, items jsonb, status text, created_at timestamp with time zone);
create table if not exists public.topup_orders (id uuid not null, merchant_id uuid not null, amount numeric not null, points numeric not null, pack_label text, ref text not null, status text not null, paid_amount numeric, whish_external_id bigint, whish_collect_url text, created_at timestamp with time zone not null, paid_at timestamp with time zone, method text not null, collected boolean not null);
create table if not exists public.topup_requests (id uuid not null, merchant_id uuid, amount numeric not null, status text, created_at timestamp with time zone);
create table if not exists public.topups (id uuid not null, merchant_id uuid, amount numeric not null, source text, ref text, created_at timestamp with time zone);
create table if not exists public.transactions (id uuid not null, user_id uuid, amount numeric, points_earned bigint, status text, created_at timestamp with time zone not null);
create table if not exists public.treasure_pics (id uuid not null, name text not null, note text, img_url text, display_order integer, created_at timestamp with time zone);
create table if not exists public.wallet_orders (id uuid not null, merchant_id uuid, amount numeric not null, status text, ref text, paid_amount numeric, created_at timestamp with time zone);
create table if not exists tp_dev.accounts (user_id uuid not null, role text not null, pin_hash text not null, email text not null, created_at timestamp with time zone not null);
create table if not exists tp_dev.demo_balances (user_id uuid not null, points bigint not null);
create table if not exists tp_dev.demo_transactions (id uuid not null, user_id uuid not null, status text not null, points bigint not null, created_at timestamp with time zone not null);
create table if not exists tp_dev.pin_attempts (user_id uuid not null, bad_count integer not null, locked_until timestamp with time zone, updated_at timestamp with time zone not null);
create table if not exists tp_dev.requests (id uuid not null, user_id uuid not null, merchant_ref text not null, idempotency_key uuid not null, amount numeric(12,2) not null, status text not null, created_at timestamp with time zone not null);
CREATE OR REPLACE FUNCTION public._expire_topup_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.topup_orders
    set status='EXPIRED'
    where status='PENDING' and now()-created_at > interval '30 minutes';
end; $function$
;
CREATE OR REPLACE FUNCTION public._rl_locked(p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1 from public.auth_rate_limits
    where key = p_key and locked_until is not null and locked_until > now()
  );
$function$
;
CREATE OR REPLACE FUNCTION public._rl_record_fail(p_key text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  insert into public.auth_rate_limits(key, fail_count, updated_at)
    values (p_key, 1, now())
  on conflict (key) do update set
    fail_count = case
      when public.auth_rate_limits.locked_until is not null and public.auth_rate_limits.locked_until > now()
        then public.auth_rate_limits.fail_count
      else public.auth_rate_limits.fail_count + 1
    end,
    updated_at = now()
  returning fail_count into n;
  if n >= 5 then
    update public.auth_rate_limits set locked_until = now() + interval '15 minutes' where key = p_key;
  end if;
end; $function$
;
CREATE OR REPLACE FUNCTION public._rl_reset(p_key text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  delete from public.auth_rate_limits where key = p_key;
$function$
;
CREATE OR REPLACE FUNCTION public._test_noop()
 RETURNS integer
 LANGUAGE sql
AS $function$ select 1 $function$
;
CREATE OR REPLACE FUNCTION public.active_offers(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'mid', merchant_id, 'type', type, 'badge', badge, 'val', val,
    'gift_text', gift_text, 'pts', pts, 'per', per, 'img_url', img_url,
    'old_price', old_price, 'new_price', new_price, 'min', min_amount,
    'days', days, 'first', first_time_only, 'active', active, 'title', title, 'specs', specs,
    'at', floor(extract(epoch from created_at)*1000)
  ) order by created_at desc), '[]'::jsonb) into r
  from public.offers
  where merchant_id = p_merchant_id and deleted = false and active = true
    and now() - created_at < (days || ' days')::interval;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_add_category(p_name_ar text, p_parent_id uuid, p_icon text DEFAULT '▦'::text, p_color text DEFAULT '#6b7a99'::text, p_image text DEFAULT NULL::text, p_slug text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare nid uuid; slg text; mx int;
begin
  if p_name_ar is null or length(trim(p_name_ar))=0 then return jsonb_build_object('ok',false,'error','اكتب اسم الفئة'); end if;
  slg := coalesce(p_slug, 'c_'||substr(md5(p_name_ar||clock_timestamp()::text),1,10));
  if exists(select 1 from public.categories where slug=slg) then
    return jsonb_build_object('ok',false,'error','هذا المعرف مستخدم مسبقاً');
  end if;
  select coalesce(max(sort_order),0)+10 into mx from public.categories where parent_id is not distinct from p_parent_id;
  insert into public.categories(slug,name_ar,parent_id,icon,color,image,sort_order)
  values(slg, trim(p_name_ar), p_parent_id, p_icon, p_color, p_image, mx)
  returning id into nid;
  return jsonb_build_object('ok',true,'id',nid,'slug',slg);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_approve_merchant_photo(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  update public.merchants set photo_url = photo_pending_url, photo_pending_url = null
  where id = p_merchant_id and photo_pending_url is not null returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'لا توجد صورة بانتظار الموافقة'); end if;
  return jsonb_build_object('ok', true, 'photo_url', r.photo_url);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_delete_customer(p_phone text, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.admin_users; cnt int; ok boolean;
begin
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false);
  if ok then delete from public.customers where phone = p_phone; get diagnostics cnt = row_count; end if;
  return jsonb_build_object('ok', coalesce(ok and cnt>0, false), 'error', case when not ok then 'هذا الإجراء مسموح للأدمن الأساسي فقط' else null end);
exception when foreign_key_violation then
  return jsonb_build_object('ok', false, 'error', 'لا يمكن حذف هذا الزبون لوجود عمليات مسجّلة عليه. جمّده بدلاً من الحذف.');
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_delete_merchant(p_merchant_id uuid, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.admin_users; cnt int; ok boolean;
begin
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false);
  if ok then delete from public.merchants where id = p_merchant_id; get diagnostics cnt = row_count; end if;
  return jsonb_build_object('ok', coalesce(ok and cnt>0, false), 'error', case when not ok then 'هذا الإجراء مسموح للأدمن الأساسي فقط' else null end);
exception when foreign_key_violation then
  return jsonb_build_object('ok', false, 'error', 'لا يمكن حذف هذا المحل لوجود عمليات أو مشتريات مسجّلة عليه. جمّده أو استبعده بدلاً من الحذف.');
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_delete_offer(p_offer_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.offers set deleted = true, active = false where id = p_offer_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'العرض غير موجود'); end if;
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_delete_topup_order_only(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.topup_orders where id=p_order_id;
  return jsonb_build_object('ok',true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_force_delete_customer(p_phone text, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.admin_users; ok boolean; cnt int;
begin
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false);
  if ok then
    delete from public.pos_transactions where customer_phone = p_phone;
    delete from public.customer_requests where customer_phone = p_phone;
    delete from public.merchant_vips where customer_phone = p_phone;
    delete from public.customer_unlocks where customer_phone = p_phone;
    delete from public.customer_notes where customer_phone = p_phone;
    delete from public.customers where phone = p_phone;
    get diagnostics cnt = row_count;
  end if;
  return jsonb_build_object('ok', coalesce(ok and cnt>0, false), 'error', case when not ok then 'هذا الإجراء مسموح للأدمن الأساسي فقط' else null end);
exception when foreign_key_violation then
  return jsonb_build_object('ok', false, 'error', 'تعذّر الحذف الكامل لوجود بيانات مرتبطة لم تُحذف بعد. حاول مجدداً أو تواصل مع الدعم الفني.');
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_force_delete_merchant(p_merchant_id uuid, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.admin_users; ok boolean; cnt int;
begin
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false);
  if ok then
    with d1 as (delete from public.topup_orders where merchant_id = p_merchant_id returning 1),
         d2 as (delete from public.wallet_orders where merchant_id = p_merchant_id returning 1),
         d3 as (delete from public.topup_requests where merchant_id = p_merchant_id returning 1),
         d4 as (delete from public.topups where merchant_id = p_merchant_id returning 1),
         d5 as (delete from public.pos_transactions where merchant_id = p_merchant_id returning 1),
         d6 as (delete from public.customer_requests where merchant_id = p_merchant_id returning 1),
         d7 as (delete from public.merchant_gallery where merchant_id = p_merchant_id returning 1),
         d8 as (delete from public.merchants where id = p_merchant_id returning 1)
    select count(*) into cnt from d8;
  end if;
  return jsonb_build_object('ok', coalesce(ok and cnt>0, false), 'error', case when not ok then 'هذا الإجراء مسموح للأدمن الأساسي فقط' else null end);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_grant_customer_gift(p_phone text, p_amount numeric, p_days integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.customers; new_exp timestamptz;
begin
  perform public.customer_check_welcome_expiry(p_phone);
  select * into r from public.customers where phone = p_phone for update;
  if r is null then return jsonb_build_object('ok', false, 'error', 'الزبون غير موجود'); end if;
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('ok', false, 'error', 'قيمة غير صحيحة'); end if;
  new_exp := case when coalesce(p_days,0) > 0 then now() + (p_days || ' days')::interval else r.welcome_exp end;
  update public.customers
    set points = points + p_amount,
        welcome_remain = coalesce(welcome_remain,0) + p_amount,
        welcome_exp = new_exp
    where phone = p_phone;
  insert into public.customer_notes(customer_phone, type, title, body)
  values (p_phone, 'points', format('هدية جديدة: %s نقطة', p_amount),
    format('تُضاف إلى نقاطك الحالية، صالحة %s يوماً إن لم تُصرف', coalesce(p_days,0)));
  return jsonb_build_object('ok', true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_list_all_offers()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', o.id, 'mid', o.merchant_id, 'mname', m.name, 'type', o.type, 'badge', o.badge, 'val', o.val,
    'gift_text', o.gift_text, 'pts', o.pts, 'per', o.per, 'img_url', o.img_url,
    'old_price', o.old_price, 'new_price', o.new_price, 'min', o.min_amount,
    'days', o.days, 'first', o.first_time_only, 'active', o.active, 'title', o.title, 'specs', o.specs,
    'at', floor(extract(epoch from o.created_at)*1000)
  ) order by o.created_at desc), '[]'::jsonb) into r
  from public.offers o left join public.merchants m on m.id = o.merchant_id
  where o.deleted = false;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_list_customers()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(t.obj order by t.created_at desc),'[]'::jsonb) into r
  from (
    select created_at, jsonb_build_object(
      'phone',phone,'name',name,'last_name',last_name,'photo_url',photo_url,
      'points',points,'status',status,'src',src,'at',floor(extract(epoch from created_at)*1000)
    ) as obj
    from public.customers
  ) t;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_list_merchants()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'phone', phone, 'cat', cat, 'extra_cats', extra_cats, 'pct', pct, 'tier', tier,
    'redeem_pct', redeem_pct, 'redeem_pct_vip', redeem_pct_vip,
    'addr', addr, 'lat', lat, 'lng', lng, 'x', x, 'y', y,
    'photo_url', photo_url, 'photo_pending_url', photo_pending_url, 'logo_url', logo_url,
    'status', status, 'poster_printed', poster_printed, 'warns', warns,
    'pending_name', pending_name, 'pending_addr', pending_addr,
    'page_blurb', page_blurb, 'page_enabled', page_enabled,
    'created_at', extract(epoch from created_at) * 1000
  ) order by created_at), '[]'::jsonb) into r
  from public.merchants;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_mark_order_collected(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.topup_orders;
begin
  select * into o from public.topup_orders where id=p_order_id;
  if o.id is null then return jsonb_build_object('ok',false,'error','لم يُعثر على الطلب'); end if;
  if o.status<>'PAID' then return jsonb_build_object('ok',false,'error','الطلب غير مكتمل'); end if;
  if o.collected then return jsonb_build_object('ok',true,'noop',true); end if;
  update public.topup_orders set collected=true where id=p_order_id;
  insert into public.merchant_notes(merchant_id,type,title,body)
    values (o.merchant_id,'wallet', format('تم تحصيل $%s نقداً', coalesce(o.paid_amount,o.amount)), format('مرجع %s',o.ref));
  return jsonb_build_object('ok',true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_reject_merchant_photo(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  update public.merchants set photo_pending_url = null
  where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_reset_merchant_pin(p_admin_id uuid, p_pin text, p_merchant_id uuid, p_new_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a public.admin_users; ok boolean; err text; rl_key text := 'admin:' || p_admin_id::text; mphone text;
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  if p_new_pin is null or length(p_new_pin) <> 4 then
    return jsonb_build_object('ok', false, 'error', 'رمز الحماية يجب أن يكون 4 أرقام');
  end if;
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary, false) and a.pin_hash is not null and crypt(p_pin, a.pin_hash) = a.pin_hash;
  if not ok then
    perform public._rl_record_fail(rl_key);
    err := case
      when a.id is null then 'جلسة غير صالحة، أعد تسجيل الدخول'
      when not coalesce(a.is_primary, false) then 'هذا الإجراء مسموح للأدمن الأساسي فقط'
      else 'رمز الإدارة غير صحيح'
    end;
    return jsonb_build_object('ok', false, 'error', err);
  end if;
  perform public._rl_reset(rl_key);
  select phone into mphone from public.merchants where id = p_merchant_id;
  if mphone is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  update public.merchants set pin_hash = crypt(p_new_pin, gen_salt('bf')) where id = p_merchant_id;
  perform public._rl_reset('merchant:' || mphone);
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_resolve_topup_order(p_order_id uuid, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.topup_orders;
begin
  select * into o from public.topup_orders where id=p_order_id;
  if o.id is null then return jsonb_build_object('ok',false,'error','لم يُعثر على الطلب'); end if;
  if o.status not in ('REVIEW') then return jsonb_build_object('ok',false,'error','الطلب ليس قيد المراجعة'); end if;
  if p_approve then
    insert into public.topups(merchant_id,amount,source,ref) values (o.merchant_id, coalesce(o.paid_amount,o.amount),'wish',o.ref);
    insert into public.merchant_notes(merchant_id,type,title,body)
      values (o.merchant_id,'wallet', format('تمت إضافة $%s إلى محفظتك', coalesce(o.paid_amount,o.amount)), format('مرجع %s',o.ref));
    update public.topup_orders set status='PAID', paid_at=now(), collected=(o.method='whish') where id=p_order_id;
  else
    insert into public.merchant_notes(merchant_id,type,title,body)
      values (o.merchant_id,'wallet','تم رفض طلب الشحن', format('مرجع %s',o.ref));
    update public.topup_orders set status='FAILED' where id=p_order_id;
  end if;
  return jsonb_build_object('ok',true,'mid',o.merchant_id,'method',o.method);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_review_info_change(p_merchant_id uuid, p_approve boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  select * into r from public.merchants where id = p_merchant_id;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  if r.pending_name is null and r.pending_addr is null then return jsonb_build_object('ok', false, 'error', 'لا يوجد طلب معلّق'); end if;
  if p_approve then
    update public.merchants set
      name = coalesce(pending_name, name),
      addr = coalesce(pending_addr, addr),
      pending_name = null, pending_addr = null
    where id = p_merchant_id returning * into r;
    insert into public.merchant_notes(merchant_id, type, title, body, severity)
    values (p_merchant_id, 'info', 'تمت الموافقة على تعديل معلومات محلك', 'أصبحت المعلومات الجديدة ظاهرة للزبائن.', 'ok');
  else
    update public.merchants set pending_name = null, pending_addr = null where id = p_merchant_id returning * into r;
    insert into public.merchant_notes(merchant_id, type, title, body, severity)
    values (p_merchant_id, 'info', 'لم تتم الموافقة على التعديل المطلوب', 'تواصل مع الإدارة لمعرفة السبب أو أعد إرسال الطلب.', 'warn');
  end if;
  return jsonb_build_object('ok', true, 'name', r.name, 'addr', r.addr);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_set_category_active(p_id uuid, p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.categories set is_active=p_active, updated_at=now() where id=p_id;
  if not found then return jsonb_build_object('ok',false,'error','الفئة غير موجودة'); end if;
  return jsonb_build_object('ok',true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_set_customer_status(p_phone text, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_status not in ('active','frozen') then return jsonb_build_object('ok',false,'error','حالة غير صحيحة'); end if;
  update public.customers set status=p_status where phone=p_phone;
  if not found then return jsonb_build_object('ok',false,'error','الزبون غير موجود'); end if;
  insert into public.customer_notes(customer_phone,type,title,body)
    values (p_phone,'account', case when p_status='active' then 'تم تفعيل حسابك' else 'تم تجميد حسابك' end, 'من الإدارة');
  return jsonb_build_object('ok',true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_set_merchant_category(p_merchant_id uuid, p_cat text, p_extra_cats text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_cat is null or not exists(select 1 from public.categories where slug=p_cat and parent_id is not null) then
    return jsonb_build_object('ok',false,'error','فئة غير صحيحة، اختر فئة فرعية موجودة');
  end if;
  update public.merchants set cat=p_cat, extra_cats=coalesce(p_extra_cats,'{}') where id=p_merchant_id;
  if not found then return jsonb_build_object('ok',false,'error','المحل غير موجود'); end if;
  return jsonb_build_object('ok',true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_set_merchant_photo(p_merchant_id uuid, p_photo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  update public.merchants set photo_url = p_photo_url, photo_pending_url = null
  where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'photo_url', r.photo_url);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_set_merchant_status(p_merchant_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  if p_status not in ('active','pending','frozen','excluded','rejected') then
    return jsonb_build_object('ok', false, 'error', 'حالة غير صحيحة');
  end if;
  update public.merchants set status = p_status where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_topup_merchant(p_merchant_id uuid, p_amount numeric, p_source text DEFAULT 'admin'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_amount is null or p_amount <= 0 then return jsonb_build_object('ok', false, 'error', 'قيمة غير صحيحة'); end if;
  insert into public.topups(merchant_id, amount, source) values (p_merchant_id, p_amount, coalesce(p_source,'admin'));
  insert into public.merchant_notes(merchant_id, type, title, body)
  values (p_merchant_id, 'wallet', format('تمت إضافة $%s إلى محفظتك التشغيلية', p_amount), 'من الإدارة');
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_topup_orders()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform public._expire_topup_orders();
  select coalesce(jsonb_agg(t.obj order by t.created_at desc),'[]'::jsonb) into r
  from (
    select o.created_at, jsonb_build_object(
      'id',o.id,'mid',o.merchant_id,'mname',m.name,'amount',o.amount,'points',o.points,'ref',o.ref,
      'status',o.status,'paid_amount',o.paid_amount,'method',o.method,'collected',o.collected,'at',floor(extract(epoch from o.created_at)*1000)
    ) as obj
    from public.topup_orders o join public.merchants m on m.id=o.merchant_id
    order by o.created_at desc limit 100
  ) t;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_update_category(p_id uuid, p_name_ar text DEFAULT NULL::text, p_icon text DEFAULT NULL::text, p_color text DEFAULT NULL::text, p_image text DEFAULT NULL::text, p_sort_order integer DEFAULT NULL::integer, p_parent_id uuid DEFAULT NULL::uuid, p_clear_parent boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not exists(select 1 from public.categories where id=p_id) then
    return jsonb_build_object('ok',false,'error','الفئة غير موجودة');
  end if;
  update public.categories set
    name_ar = coalesce(p_name_ar, name_ar),
    icon = coalesce(p_icon, icon),
    color = coalesce(p_color, color),
    image = coalesce(p_image, image),
    sort_order = coalesce(p_sort_order, sort_order),
    parent_id = case when p_clear_parent then null when p_parent_id is not null then p_parent_id else parent_id end,
    updated_at = now()
  where id = p_id;
  return jsonb_build_object('ok',true);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.admin_update_merchant_location(p_merchant_id uuid, p_lat numeric, p_lng numeric, p_x numeric, p_y numeric, p_addr text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  if p_lat is null or p_lng is null then
    return jsonb_build_object('ok', false, 'error', 'إحداثيات غير صحيحة');
  end if;
  update public.merchants set
    lat = p_lat,
    lng = p_lng,
    x = coalesce(p_x, x),
    y = coalesce(p_y, y),
    addr = coalesce(nullif(trim(p_addr), ''), addr)
  where id = p_merchant_id
  returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'lat', r.lat, 'lng', r.lng, 'x', r.x, 'y', r.y, 'addr', r.addr);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_update_merchant_location(p_merchant_id uuid, p_lat numeric, p_lng numeric, p_x numeric, p_y numeric, p_addr text DEFAULT NULL::text, p_area text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  if p_lat is null or p_lng is null then
    return jsonb_build_object('ok', false, 'error', 'إحداثيات غير صحيحة');
  end if;
  update public.merchants set
    lat = p_lat,
    lng = p_lng,
    x = coalesce(p_x, x),
    y = coalesce(p_y, y),
    addr = coalesce(nullif(trim(p_addr), ''), addr),
    area = coalesce(nullif(trim(p_area), ''), area)
  where id = p_merchant_id
  returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'lat', r.lat, 'lng', r.lng, 'x', r.x, 'y', r.y, 'addr', r.addr, 'area', r.area);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_update_offer_image(p_offer_id uuid, p_img_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.offers;
begin
  update public.offers set img_url = p_img_url where id = p_offer_id and deleted = false returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'العرض غير موجود'); end if;
  return jsonb_build_object('ok', true, 'id', r.id, 'img_url', r.img_url);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_update_text_settings(p_admin_id uuid, p_settings jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a public.admin_users; ok boolean; k text; v text;
begin
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false);
  if ok then
    for k, v in select * from jsonb_each_text(p_settings) loop
      insert into public.app_text_settings(key, value) values (k, v)
      on conflict (key) do update set value = excluded.value;
    end loop;
  end if;
  return jsonb_build_object('ok', ok, 'error', case when not ok then 'هذا الإجراء مسموح للأدمن الأساسي فقط' else null end);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_verify_pin(p_username text, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.admin_users;
begin
  select * into r from public.admin_users where username = p_username;
  if r is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  return jsonb_build_object('ok', true, 'admin', jsonb_build_object('id', r.id, 'username', r.username, 'is_primary', r.is_primary));
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_warn_merchant(p_merchant_id uuid, p_max_warns integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  update public.merchants set warns = coalesce(warns,0) + 1 where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  if r.warns >= p_max_warns then
    update public.merchants set status = 'excluded' where id = p_merchant_id;
    r.status := 'excluded';
  end if;
  return jsonb_build_object('ok', true, 'warns', r.warns, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.admin_wipe_all_data(p_admin_id uuid, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a public.admin_users; ok boolean; err text;
begin
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false) and a.pin_hash is not null and crypt(p_pin, a.pin_hash) = a.pin_hash;
  if ok then truncate table public.merchants, public.customers cascade; end if;
  err := case when a.id is null then 'جلسة غير صالحة، أعد تسجيل الدخول' when not coalesce(a.is_primary,false) then 'هذا الإجراء مسموح للأدمن الأساسي فقط' when not ok then 'رمز الإدارة غير صحيح' else null end;
  return jsonb_build_object('ok', ok, 'error', err);
end; $function$
;
CREATE OR REPLACE FUNCTION public.create_transaction(p_merchant_id uuid, p_customer_phone text, p_invoice numeric, p_redeem boolean, p_offer_id uuid DEFAULT NULL::uuid, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.merchants; c public.customers; o public.offers;
  rate numeric; cap_pct numeric; tier_max numeric;
  disc numeric := 0; base numeric; vip_cap numeric := 0; is_vip boolean := false;
  reserved_pts numeric; avail_pts numeric; max_redeem numeric;
  cap numeric; rp numeric; rv numeric; net numeric; bonus numeric := 0; earn numeric;
  wallet_json jsonb; wallet_avail numeric; new_tx public.pos_transactions;
begin
  update public.pos_transactions set status = 'EXPIRED'
  where customer_phone = p_customer_phone and status = 'PENDING' and now() - created_at > interval '5 minutes';

  select * into m from public.merchants where id = p_merchant_id;
  if m is null or m.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب المحل غير فعّال'); end if;
  select * into c from public.customers where phone = p_customer_phone;
  if c is null then return jsonb_build_object('ok', false, 'error', 'هذا الرقم غير مسجّل في التطبيق'); end if;
  if c.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب الزبون مجمّد'); end if;
  if p_invoice is null or p_invoice <= 0 then return jsonb_build_object('ok', false, 'error', 'أدخل قيمة الفاتورة'); end if;

  select coalesce(sum(redeem_pts),0) into reserved_pts from public.pos_transactions where customer_phone = p_customer_phone and status='PENDING';
  if reserved_pts > 0 then return jsonb_build_object('ok', false, 'error', 'لدى الزبون عملية قيد التأكيد'); end if;

  select value into rate from public.app_settings where key='rate_pts_per_usd';
  select value into cap_pct from public.app_settings where key='redeem_cap_pct';

  if p_offer_id is not null then
    select * into o from public.offers where id = p_offer_id and merchant_id = p_merchant_id;
    if o is null then return jsonb_build_object('ok', false, 'error', 'العرض غير موجود'); end if;
    if not o.active or now() - o.created_at >= (o.days || ' days')::interval then return jsonb_build_object('ok', false, 'error', 'انتهى هذا العرض'); end if;
    if o.min_amount > 0 and p_invoice < o.min_amount then return jsonb_build_object('ok', false, 'error', format('الحد الأدنى لهذا العرض $%s', o.min_amount)); end if;
    if o.first_time_only and exists (select 1 from public.pos_transactions where merchant_id=p_merchant_id and customer_phone=p_customer_phone and status='CONFIRMED') then
      return jsonb_build_object('ok', false, 'error', 'هذا العرض للزائر الجديد فقط');
    end if;
  end if;

  tier_max := case m.tier when 'large' then 10000 when 'medium' then 2500 else 1000 end;

  disc := case when o.type = 'discount' then round(p_invoice * o.val / 100, 2) else 0 end;
  base := round(p_invoice - disc, 2);

  select cap_points into vip_cap from public.merchant_vips where merchant_id=p_merchant_id and customer_phone=p_customer_phone;
  is_vip := vip_cap is not null and vip_cap > 0;

  avail_pts := greatest(0, c.points);
  max_redeem := floor(avail_pts * cap_pct / 100);

  if is_vip then
    cap := least(max_redeem, least(vip_cap, floor(base * rate)));
  else
    cap := least(max_redeem, floor(base * rate * coalesce(m.redeem_pct,5)/100), tier_max);
  end if;
  rp := case when p_redeem then cap else 0 end;
  rv := rp / rate;
  net := round(base - rv, 2);
  bonus := case when o.type = 'bonus' and o.per > 0 then floor(net / o.per) * o.pts else 0 end;
  earn := floor(net * m.pct / 100 * rate) + bonus;

  wallet_json := public.merchant_wallet(p_merchant_id);
  wallet_avail := (wallet_json->>'avail')::numeric;
  if earn / rate > wallet_avail then return jsonb_build_object('ok', false, 'error', 'INSUFFICIENT'); end if;

  insert into public.pos_transactions(merchant_id, customer_phone, invoice, redeem_pts, redeem_val, net, earn, items, status)
  values (p_merchant_id, p_customer_phone, p_invoice, rp, rv, net, earn, coalesce(p_items,'[]'::jsonb), 'PENDING')
  returning * into new_tx;

  insert into public.customer_notes(customer_phone, type, title, body)
  values (p_customer_phone, 'points', 'عملية بانتظار تأكيدك', m.name || ': $' || p_invoice);

  return jsonb_build_object('ok', true, 'tx_id', new_tx.id, 'invoice', p_invoice, 'disc', disc, 'redeem_pts', rp,
    'redeem_val', rv, 'net', net, 'bonus', bonus, 'earn', earn);
end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_check_phone(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.customers;
begin
  select * into r from public.customers where phone = p_phone;
  if r is null then return jsonb_build_object('exists', false); end if;
  return jsonb_build_object('exists', true, 'status', r.status, 'has_pin', r.pin_hash is not null);
end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_check_welcome_expiry(p_phone text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.customers; lost numeric;
begin
  select * into r from public.customers where phone = p_phone for update;
  if r is null then return; end if;
  if r.welcome_remain > 0 and r.welcome_exp is not null and now() > r.welcome_exp then
    lost := least(r.welcome_remain, r.points);
    update public.customers set points = points - lost, welcome_remain = 0 where phone = p_phone;
    insert into public.customer_notes(customer_phone, type, title, body)
    values (p_phone, 'points',
      case when lost > 0 then format('انتهت صلاحية هدية الترحيب، سُحبت %s نقطة لم تُصرف', lost) else 'انتهت صلاحية هدية الترحيب' end,
      'تبقى معك فقط النقاط التي اكتسبتها من مشترياتك الفعلية.');
  end if;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.customer_create_request(p_merchant_id uuid, p_phone text, p_invoice numeric, p_offer_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.merchants; c public.customers; r public.customer_requests;
begin
  select * into m from public.merchants where id = p_merchant_id;
  if m is null or m.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب المحل غير فعّال'); end if;
  select * into c from public.customers where phone = p_phone;
  if c is null then return jsonb_build_object('ok', false, 'error', 'هذا الرقم غير مسجّل في التطبيق'); end if;
  if c.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب الزبون مجمّد'); end if;
  if p_invoice is null or p_invoice <= 0 then return jsonb_build_object('ok', false, 'error', 'أدخل قيمة الفاتورة'); end if;

  insert into public.customer_requests(merchant_id, customer_phone, invoice, offer_id, status)
  values (p_merchant_id, p_phone, p_invoice, p_offer_id, 'open')
  returning * into r;

  return jsonb_build_object('ok', true, 'id', r.id);
end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_notes_list(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'type', type, 'title', title, 'body', body, 'read', read,
    'at', floor(extract(epoch from created_at)*1000)
  ) order by created_at desc), '[]'::jsonb) into r
  from public.customer_notes where customer_phone = p_phone;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_notes_mark_read(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin update public.customer_notes set read = true where customer_phone = p_phone and read = false;
return jsonb_build_object('ok', true); end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_profile(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.customers;
begin
  perform public.customer_check_welcome_expiry(p_phone);
  select * into r from public.customers where phone = p_phone;
  if r is null then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true, 'customer', jsonb_build_object(
    'phone', r.phone, 'name', r.name, 'last_name', r.last_name, 'photo_url', r.photo_url, 'points', r.points, 'status', r.status,
    'welcome_remain', r.welcome_remain, 'welcome_exp', r.welcome_exp));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.customer_register(p_phone text, p_pin text, p_name text DEFAULT 'زبون جديد'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.customers; nm text;
begin
  nm := coalesce(p_name, 'زبون جديد');
  if p_phone is null or length(p_phone) < 7 then raise exception 'رقم هاتف غير صحيح'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  if exists (select 1 from public.customers where phone = p_phone) then
    raise exception 'هذا الرقم مسجّل مسبقاً';
  end if;
  insert into public.customers(phone, pin_hash, name, status)
  values (p_phone, crypt(p_pin, gen_salt('bf')), nm, 'active')
  returning * into r;
  return jsonb_build_object('phone', r.phone, 'name', r.name, 'points', r.points, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_register(p_phone text, p_pin text, p_name text DEFAULT 'زبون جديد'::text, p_welcome_bonus numeric DEFAULT 0, p_welcome_days integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.customers; nm text; wexp timestamptz;
begin
  nm := coalesce(p_name, 'زبون جديد');
  if p_phone is null or length(p_phone) < 7 then raise exception 'رقم هاتف غير صحيح'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  if exists (select 1 from public.customers where phone = p_phone) then
    raise exception 'هذا الرقم مسجّل مسبقاً';
  end if;
  wexp := case when coalesce(p_welcome_bonus,0) > 0 and coalesce(p_welcome_days,0) > 0
    then now() + (p_welcome_days || ' days')::interval else null end;
  insert into public.customers(phone, pin_hash, name, status, points, welcome_remain, welcome_exp)
  values (p_phone, crypt(p_pin, gen_salt('bf')), nm, 'active', greatest(0, coalesce(p_welcome_bonus,0)),
          greatest(0, coalesce(p_welcome_bonus,0)), wexp)
  returning * into r;
  if p_welcome_bonus > 0 then
    insert into public.customer_notes(customer_phone, type, title, body)
    values (p_phone, 'points', format('هدية الترحيب: %s نقطة', p_welcome_bonus),
      format('صالحة %s أيام، تُسحب تلقائياً إن لم تُصرف قبل ذلك', coalesce(p_welcome_days,0)));
  end if;
  insert into public.customer_notes(customer_phone, type, title, body)
  values (p_phone, 'general', 'مرحباً بك في Tripoli Points', 'ابدأ باكتشاف العروض وجمع النقاط من المحلات القريبة.');
  return jsonb_build_object('phone', r.phone, 'name', r.name, 'points', r.points, 'status', r.status);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.customer_register(p_phone text, p_pin text, p_name text DEFAULT 'زبون جديد'::text, p_welcome_bonus numeric DEFAULT 0, p_welcome_days integer DEFAULT 0, p_terms_version text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.customers; nm text; wexp timestamptz;
begin
  nm := coalesce(p_name, 'زبون جديد');
  if p_phone is null or length(p_phone) < 7 then raise exception 'رقم هاتف غير صحيح'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  if exists (select 1 from public.customers where phone = p_phone) then
    raise exception 'هذا الرقم مسجّل مسبقاً';
  end if;
  wexp := case when coalesce(p_welcome_bonus,0) > 0 and coalesce(p_welcome_days,0) > 0
    then now() + (p_welcome_days || ' days')::interval else null end;
  insert into public.customers(phone, pin_hash, name, status, points, welcome_remain, welcome_exp, terms_version, terms_accepted_at)
  values (p_phone, crypt(p_pin, gen_salt('bf')), nm, 'active', greatest(0, coalesce(p_welcome_bonus,0)),
          greatest(0, coalesce(p_welcome_bonus,0)), wexp, p_terms_version, case when p_terms_version is not null then now() else null end)
  returning * into r;
  if p_welcome_bonus > 0 then
    insert into public.customer_notes(customer_phone, type, title, body)
    values (p_phone, 'points', format('هدية الترحيب: %s نقطة', p_welcome_bonus),
      format('صالحة %s أيام، تُسحب تلقائياً إن لم تُصرف قبل ذلك', coalesce(p_welcome_days,0)));
  end if;
  insert into public.customer_notes(customer_phone, type, title, body)
  values (p_phone, 'general', 'مرحباً بك في Tripoli Points', 'ابدأ باكتشاف العروض وجمع النقاط من المحلات القريبة.');
  return jsonb_build_object('phone', r.phone, 'name', r.name, 'points', r.points, 'status', r.status);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.customer_reset_pin(p_phone text, p_new_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not exists (select 1 from public.customers where phone = p_phone) then
    raise exception 'الحساب غير موجود';
  end if;
  if p_new_pin is null or length(p_new_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  update public.customers set pin_hash = crypt(p_new_pin, gen_salt('bf')) where phone = p_phone;
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_set_pin(p_phone text, p_pin text, p_name text DEFAULT 'زبون جديد'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.customers;
begin
  if p_phone is null or length(p_phone) < 7 then raise exception 'رقم هاتف غير صحيح'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  if exists (select 1 from public.customers where phone = p_phone) then
    raise exception 'هذا الرقم مسجّل مسبقاً';
  end if;
  insert into public.customers(phone, pin_hash, name, status)
  values (p_phone, crypt(p_pin, gen_salt('bf')), coalesce(p_name,'زبون جديد'), 'active')
  returning * into r;
  return jsonb_build_object('phone', r.phone, 'name', r.name, 'points', r.points, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_transactions(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  update public.pos_transactions set status = 'EXPIRED'
  where customer_phone = p_phone and status = 'PENDING' and now() - created_at > interval '5 minutes';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'mid', t.merchant_id, 'mname', m.name, 'invoice', t.invoice,
    'redeemPts', t.redeem_pts, 'redeemVal', t.redeem_val, 'net', t.net, 'earn', t.earn,
    'items', t.items, 'status', t.status, 'at', floor(extract(epoch from t.created_at)*1000)
  ) order by t.created_at desc), '[]'::jsonb) into r
  from public.pos_transactions t join public.merchants m on m.id = t.merchant_id
  where t.customer_phone = p_phone;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.customer_verify_pin(p_phone text, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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
$function$
;
CREATE OR REPLACE FUNCTION public.decide_transaction(p_tx_id uuid, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t public.pos_transactions; m public.merchants; pic record; prev_count int; new_count int;
begin
  select * into t from public.pos_transactions where id = p_tx_id;
  if t is null then return jsonb_build_object('ok', false, 'error', 'العملية غير موجودة'); end if;
  if t.status = 'PENDING' and now() - t.created_at > interval '5 minutes' then
    update public.pos_transactions set status = 'EXPIRED' where id = p_tx_id;
    return jsonb_build_object('ok', false, 'error', 'انتهت مهلة العملية');
  end if;
  if t.status <> 'PENDING' then return jsonb_build_object('ok', false, 'error', 'انتهت مهلة العملية'); end if;
  select * into m from public.merchants where id = t.merchant_id;

  select count(distinct merchant_id) into prev_count from public.pos_transactions where customer_phone = t.customer_phone and status = 'CONFIRMED';

  update public.pos_transactions set status = case when p_confirm then 'CONFIRMED' else 'CANCELLED' end where id = p_tx_id;

  insert into public.merchant_notes(merchant_id, type, title, body) values (t.merchant_id,
    case when p_confirm then 'sale' else 'warn' end,
    case when p_confirm then format('تم تأكيد عملية بقيمة $%s', t.invoice) else 'ألغى الزبون العملية' end,
    (select name from public.customers where phone = t.customer_phone));

  if p_confirm then
    update public.customers set points = points + t.earn - t.redeem_pts where phone = t.customer_phone;
    if t.redeem_pts > 0 then insert into public.customer_notes(customer_phone,type,title,body) values (t.customer_phone,'points', format('تم استخدام %s نقطة', t.redeem_pts), m.name); end if;
    if t.earn > 0 then insert into public.customer_notes(customer_phone,type,title,body) values (t.customer_phone,'points', format('تمت إضافة %s نقطة', t.earn), m.name); end if;

    select count(distinct merchant_id) into new_count from public.pos_transactions where customer_phone = t.customer_phone and status = 'CONFIRMED';
    if new_count > prev_count then
      select * into pic from public.treasure_pics order by display_order, created_at limit 1 offset new_count - 1;
      if pic.id is not null then
        insert into public.customer_unlocks(customer_phone, pic_id) values (t.customer_phone, pic.id) on conflict do nothing;
        insert into public.customer_notes(customer_phone,type,title,body) values (t.customer_phone,'general',
          format('🎉 صورة جديدة من كنوز طرابلس: %s', pic.name), 'افتح «كنوز طرابلس» من صفحة حسابي لمشاهدتها');
      end if;
    end if;
  end if;

  return jsonb_build_object('ok', true, 'status', case when p_confirm then 'CONFIRMED' else 'CANCELLED' end);
end; $function$
;
CREATE OR REPLACE FUNCTION public.get_app_text_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) into r from public.app_text_settings;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.get_categories(p_include_inactive boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'slug', c.slug, 'name_ar', c.name_ar, 'name_en', c.name_en,
      'parent_id', c.parent_id, 'icon', c.icon, 'color', c.color, 'image', c.image,
      'sort_order', c.sort_order, 'is_active', c.is_active
    ) order by c.sort_order, c.name_ar), '[]'::jsonb) into r
  from public.categories c
  where p_include_inactive or c.is_active;
  return r;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.list_active_offers_all()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', o.id, 'mid', o.merchant_id, 'type', o.type, 'badge', o.badge, 'val', o.val,
    'gift_text', o.gift_text, 'pts', o.pts, 'per', o.per, 'img_url', o.img_url,
    'old_price', o.old_price, 'new_price', o.new_price, 'min', o.min_amount,
    'days', o.days, 'first', o.first_time_only, 'active', o.active, 'title', o.title, 'specs', o.specs,
    'at', floor(extract(epoch from o.created_at)*1000)
  ) order by o.created_at desc), '[]'::jsonb) into r
  from public.offers o join public.merchants m on m.id = o.merchant_id
  where o.deleted = false and o.active = true and m.status = 'active'
    and now() - o.created_at < (o.days || ' days')::interval;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.list_merchants()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'cat', cat, 'extra_cats', extra_cats, 'pct', pct, 'tier', tier,
    'redeem_pct', redeem_pct, 'redeem_pct_vip', redeem_pct_vip,
    'addr', addr, 'lat', lat, 'lng', lng, 'x', x, 'y', y, 'area', area,
    'photo_url', photo_url, 'logo_url', logo_url, 'status', status,
    'page_blurb', page_blurb, 'page_enabled', page_enabled
  )), '[]'::jsonb) into r
  from public.merchants where status = 'active';
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_add_offer(p_merchant_id uuid, p_type text, p_title text, p_badge text DEFAULT 'جديد'::text, p_val numeric DEFAULT NULL::numeric, p_gift_text text DEFAULT NULL::text, p_pts numeric DEFAULT NULL::numeric, p_per numeric DEFAULT NULL::numeric, p_old_price numeric DEFAULT NULL::numeric, p_new_price numeric DEFAULT NULL::numeric, p_img_url text DEFAULT NULL::text, p_min_amount numeric DEFAULT 0, p_days integer DEFAULT 30, p_first_time_only boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare new_o public.offers;
begin
  insert into public.offers(merchant_id, type, title, badge, val, gift_text, pts, per,
    old_price, new_price, img_url, min_amount, days, first_time_only, active)
  values (p_merchant_id, p_type, p_title, p_badge, p_val, p_gift_text, p_pts, p_per,
    p_old_price, p_new_price, p_img_url, p_min_amount, p_days, p_first_time_only, true)
  returning * into new_o;
  return jsonb_build_object('ok', true, 'id', new_o.id);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_add_offer(p_merchant_id uuid, p_type text, p_title text, p_badge text DEFAULT 'جديد'::text, p_val numeric DEFAULT NULL::numeric, p_gift_text text DEFAULT NULL::text, p_pts numeric DEFAULT NULL::numeric, p_per numeric DEFAULT NULL::numeric, p_old_price numeric DEFAULT NULL::numeric, p_new_price numeric DEFAULT NULL::numeric, p_img_url text DEFAULT NULL::text, p_min_amount numeric DEFAULT 0, p_days integer DEFAULT 30, p_first_time_only boolean DEFAULT false, p_specs text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare new_o public.offers;
begin
  insert into public.offers(merchant_id, type, title, badge, val, gift_text, pts, per,
    old_price, new_price, img_url, min_amount, days, first_time_only, specs, active)
  values (p_merchant_id, p_type, p_title, p_badge, p_val, p_gift_text, p_pts, p_per,
    p_old_price, p_new_price, p_img_url, p_min_amount, p_days, p_first_time_only, p_specs, true)
  returning * into new_o;
  return jsonb_build_object('ok', true, 'id', new_o.id);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_check_phone(p_phone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  select * into r from public.merchants where phone = p_phone;
  if r is null then return jsonb_build_object('exists', false); end if;
  return jsonb_build_object('exists', true, 'status', r.status, 'has_pin', r.pin_hash is not null);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_close_request(p_request_id uuid, p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.customer_requests;
begin
  update public.customer_requests set status = 'used'
  where id = p_request_id and merchant_id = p_merchant_id and status = 'open'
  returning * into r;
  if r is null then return jsonb_build_object('ok', false); end if;
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_create_topup_order(p_merchant_id uuid, p_amount numeric, p_points numeric, p_pack_label text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.topup_orders; newref text;
begin
  perform public._expire_topup_orders();
  if p_amount is null or p_amount<=0 then return jsonb_build_object('ok',false,'error','قيمة غير صحيحة'); end if;
  select * into o from public.topup_orders
    where merchant_id=p_merchant_id and amount=p_amount and status='PENDING'
    order by created_at desc limit 1;
  if o.id is null then
    newref := 'TP-'||lpad((floor(random()*900000)+100000)::text,6,'0');
    insert into public.topup_orders(merchant_id,amount,points,pack_label,ref)
      values (p_merchant_id,p_amount,p_points,p_pack_label,newref)
      returning * into o;
  end if;
  return jsonb_build_object('ok',true,'id',o.id,'ref',o.ref,'amount',o.amount,'points',o.points,
    'status',o.status,'collect_url',o.whish_collect_url,'at',floor(extract(epoch from o.created_at)*1000));
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_delete_offer(p_offer_id uuid, p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.offers set deleted = true, active = false where id = p_offer_id and merchant_id = p_merchant_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'العرض غير موجود'); end if;
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_gallery_add(p_merchant_id uuid, p_name text, p_price numeric, p_img_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare cnt int; r public.merchant_gallery;
begin
  select count(*) into cnt from public.merchant_gallery where merchant_id = p_merchant_id;
  if cnt >= 6 then return jsonb_build_object('ok', false, 'error', 'وصلت للحد الأقصى (6 صور)'); end if;
  if p_name is null or trim(p_name) = '' then return jsonb_build_object('ok', false, 'error', 'اكتب اسم الغرض'); end if;
  if p_img_url is null or trim(p_img_url) = '' then return jsonb_build_object('ok', false, 'error', 'أضف صورة'); end if;
  insert into public.merchant_gallery(merchant_id, name, price, img_url, display_order)
  values (p_merchant_id, trim(p_name), p_price, p_img_url, cnt)
  returning * into r;
  return jsonb_build_object('ok', true, 'id', r.id);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_gallery_delete(p_item_id uuid, p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from public.merchant_gallery where id = p_item_id and merchant_id = p_merchant_id;
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_gallery_list(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'price', price, 'img', img_url, 'at', floor(extract(epoch from created_at)*1000)
  ) order by display_order, created_at), '[]'::jsonb) into r
  from public.merchant_gallery where merchant_id = p_merchant_id;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_notes_list(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'type', type, 'title', title, 'body', body, 'read', read,
    'at', floor(extract(epoch from created_at)*1000)
  ) order by created_at desc), '[]'::jsonb) into r
  from public.merchant_notes where merchant_id = p_merchant_id;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_notes_mark_read(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin update public.merchant_notes set read = true where merchant_id = p_merchant_id and read = false;
return jsonb_build_object('ok', true); end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_offers(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'mid', merchant_id, 'type', type, 'badge', badge, 'val', val,
    'gift_text', gift_text, 'pts', pts, 'per', per, 'img_url', img_url,
    'old_price', old_price, 'new_price', new_price, 'min', min_amount,
    'days', days, 'first', first_time_only, 'active', active, 'title', title, 'specs', specs,
    'at', floor(extract(epoch from created_at)*1000)
  ) order by created_at desc), '[]'::jsonb) into r
  from public.offers where merchant_id = p_merchant_id and deleted = false;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_register(p_name text, p_phone text, p_pin text, p_cat text, p_pct numeric, p_addr text DEFAULT NULL::text, p_x numeric DEFAULT NULL::numeric, p_y numeric DEFAULT NULL::numeric, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_photo_url text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants;
begin
  if exists (select 1 from public.merchants where phone = p_phone) then raise exception 'هذا الرقم مسجّل مسبقاً'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  insert into public.merchants(name, phone, pin_hash, cat, pct, addr, x, y, lat, lng, photo_url, status, redeem_pct, redeem_pct_vip)
  values (p_name, p_phone, crypt(p_pin, gen_salt('bf')), p_cat, coalesce(p_pct,5), p_addr, p_x, p_y, p_lat, p_lng, p_photo_url, 'pending', 5, 5)
  returning * into r;
  return jsonb_build_object('id', r.id, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_register(p_name text, p_phone text, p_pin text, p_cat text, p_pct numeric, p_addr text DEFAULT NULL::text, p_x numeric DEFAULT NULL::numeric, p_y numeric DEFAULT NULL::numeric, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_photo_url text DEFAULT NULL::text, p_redeem_pct numeric DEFAULT 5)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants;
begin
  if exists (select 1 from public.merchants where phone = p_phone) then raise exception 'هذا الرقم مسجّل مسبقاً'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  insert into public.merchants(name, phone, pin_hash, cat, pct, addr, x, y, lat, lng, photo_url, status, redeem_pct, redeem_pct_vip)
  values (p_name, p_phone, crypt(p_pin, gen_salt('bf')), p_cat, coalesce(p_pct,5), p_addr, p_x, p_y, p_lat, p_lng, p_photo_url, 'pending', coalesce(p_redeem_pct,5), coalesce(p_redeem_pct,5))
  returning * into r;
  return jsonb_build_object('id', r.id, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_register(p_name text, p_phone text, p_pin text, p_cat text, p_pct numeric, p_addr text DEFAULT NULL::text, p_x numeric DEFAULT NULL::numeric, p_y numeric DEFAULT NULL::numeric, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_photo_url text DEFAULT NULL::text, p_redeem_pct numeric DEFAULT 5, p_extra_cats text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants; ec text[];
begin
  if exists (select 1 from public.merchants where phone = p_phone) then raise exception 'هذا الرقم مسجّل مسبقاً'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  select coalesce(array_agg(distinct c), '{}') into ec from unnest(coalesce(p_extra_cats,'{}')) c where c is not null and c <> '' and c <> p_cat;
  if array_length(ec,1) > 2 then raise exception 'يمكن اختيار 3 فئات كحد أقصى'; end if;
  insert into public.merchants(name, phone, pin_hash, cat, extra_cats, pct, addr, x, y, lat, lng, photo_url, status, redeem_pct, redeem_pct_vip)
  values (p_name, p_phone, crypt(p_pin, gen_salt('bf')), p_cat, ec, coalesce(p_pct,5), p_addr, p_x, p_y, p_lat, p_lng, p_photo_url, 'pending', coalesce(p_redeem_pct,5), coalesce(p_redeem_pct,5))
  returning * into r;
  return jsonb_build_object('id', r.id, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_register(p_name text, p_phone text, p_pin text, p_cat text, p_pct numeric, p_addr text DEFAULT NULL::text, p_x numeric DEFAULT NULL::numeric, p_y numeric DEFAULT NULL::numeric, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_photo_url text DEFAULT NULL::text, p_redeem_pct numeric DEFAULT 5, p_extra_cats text[] DEFAULT '{}'::text[], p_terms_version text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants; ec text[];
begin
  if exists (select 1 from public.merchants where phone = p_phone) then raise exception 'هذا الرقم مسجّل مسبقاً'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  select coalesce(array_agg(distinct c), '{}') into ec from unnest(coalesce(p_extra_cats,'{}')) c where c is not null and c <> '' and c <> p_cat;
  if array_length(ec,1) > 2 then raise exception 'يمكن اختيار 3 فئات كحد أقصى'; end if;
  insert into public.merchants(name, phone, pin_hash, cat, extra_cats, pct, addr, x, y, lat, lng, photo_url, status, redeem_pct, redeem_pct_vip, terms_version, terms_accepted_at)
  values (p_name, p_phone, crypt(p_pin, gen_salt('bf')), p_cat, ec, coalesce(p_pct,5), p_addr, p_x, p_y, p_lat, p_lng, p_photo_url, 'pending', coalesce(p_redeem_pct,5), coalesce(p_redeem_pct,5), p_terms_version, case when p_terms_version is not null then now() else null end)
  returning * into r;
  return jsonb_build_object('id', r.id, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_register(p_name text, p_phone text, p_pin text, p_cat text, p_pct numeric, p_addr text DEFAULT NULL::text, p_x numeric DEFAULT NULL::numeric, p_y numeric DEFAULT NULL::numeric, p_lat numeric DEFAULT NULL::numeric, p_lng numeric DEFAULT NULL::numeric, p_photo_url text DEFAULT NULL::text, p_redeem_pct numeric DEFAULT 5, p_extra_cats text[] DEFAULT '{}'::text[], p_terms_version text DEFAULT NULL::text, p_area text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants; ec text[];
begin
  if exists (select 1 from public.merchants where phone = p_phone) then raise exception 'هذا الرقم مسجّل مسبقاً'; end if;
  if p_pin is null or length(p_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  select coalesce(array_agg(distinct c), '{}') into ec from unnest(coalesce(p_extra_cats,'{}')) c where c is not null and c <> '' and c <> p_cat;
  if array_length(ec,1) > 2 then raise exception 'يمكن اختيار 3 فئات كحد أقصى'; end if;
  insert into public.merchants(name, phone, pin_hash, cat, extra_cats, pct, addr, x, y, lat, lng, area, photo_url, status, redeem_pct, redeem_pct_vip, terms_version, terms_accepted_at)
  values (p_name, p_phone, crypt(p_pin, gen_salt('bf')), p_cat, ec, coalesce(p_pct,5), p_addr, p_x, p_y, p_lat, p_lng, nullif(p_area,''), p_photo_url, 'pending', coalesce(p_redeem_pct,5), coalesce(p_redeem_pct,5), p_terms_version, case when p_terms_version is not null then now() else null end)
  returning * into r;
  return jsonb_build_object('id', r.id, 'status', r.status);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_request_info_change(p_merchant_id uuid, p_name text DEFAULT NULL::text, p_addr text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants; pn text; pa text;
begin
  select * into r from public.merchants where id = p_merchant_id;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  pn := nullif(trim(coalesce(p_name,'')), '');
  pa := nullif(trim(coalesce(p_addr,'')), '');
  if pn is not null and pn = r.name then pn := null; end if;
  if pa is not null and pa = coalesce(r.addr,'') then pa := null; end if;
  if pn is null and pa is null then return jsonb_build_object('ok', false, 'error', 'لا يوجد تغيير لإرساله'); end if;
  update public.merchants set
    pending_name = coalesce(pn, pending_name),
    pending_addr = coalesce(pa, pending_addr)
  where id = p_merchant_id;
  insert into public.merchant_notes(merchant_id, type, title, body, severity)
  values (p_merchant_id, 'info', 'تم استلام طلب تعديل معلومات محلك', 'بانتظار موافقة الإدارة عليه.', 'info');
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_request_manual_topup(p_merchant_id uuid, p_amount numeric, p_points numeric, p_pack_label text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.topup_orders; newref text;
begin
  if p_amount is null or p_amount<=0 then return jsonb_build_object('ok',false,'error','قيمة غير صحيحة'); end if;
  newref := 'TP-'||lpad((floor(random()*900000)+100000)::text,6,'0');
  insert into public.topup_orders(merchant_id,amount,points,pack_label,ref,status,method)
    values (p_merchant_id,p_amount,p_points,p_pack_label,newref,'REVIEW','manual')
    returning * into o;
  insert into public.merchant_notes(merchant_id,type,title,body)
    values (p_merchant_id,'wallet', format('طلب شراء بطاقة $%s بانتظار موافقة الإدارة', p_amount), format('مرجع %s',o.ref));
  return jsonb_build_object('ok',true,'id',o.id,'ref',o.ref,'amount',o.amount,'points',o.points,
    'status',o.status,'method',o.method,'at',floor(extract(epoch from o.created_at)*1000));
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_requests(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  update public.customer_requests set status = 'expired'
  where merchant_id = p_merchant_id and status = 'open' and now() - created_at > interval '30 minutes';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', q.id, 'phone', q.customer_phone, 'cname', c.name, 'invoice', q.invoice,
    'offerId', q.offer_id, 'offerTitle', o.title, 'status', q.status,
    'at', floor(extract(epoch from q.created_at)*1000)
  ) order by q.created_at desc), '[]'::jsonb) into r
  from public.customer_requests q
  left join public.customers c on c.phone = q.customer_phone
  left join public.offers o on o.id = q.offer_id
  where q.merchant_id = p_merchant_id and q.status = 'open';
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_reset_pin(p_phone text, p_new_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
begin
  if not exists (select 1 from public.merchants where phone = p_phone) then
    raise exception 'الحساب غير موجود';
  end if;
  if p_new_pin is null or length(p_new_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  update public.merchants set pin_hash = crypt(p_new_pin, gen_salt('bf')) where phone = p_phone;
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_set_logo(p_phone text, p_pin text, p_logo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants; rl_key text := 'merchant:' || p_phone;
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.merchants where phone = p_phone;
  if r is null then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl_reset(rl_key);
  update public.merchants set logo_url = nullif(p_logo_url, '')
  where id = r.id returning * into r;
  return jsonb_build_object('ok', true, 'logo_url', r.logo_url);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_set_offer_active(p_offer_id uuid, p_merchant_id uuid, p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.offers set active = p_active where id = p_offer_id and merchant_id = p_merchant_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'العرض غير موجود'); end if;
  return jsonb_build_object('ok', true);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_set_redeem_pct(p_merchant_id uuid, p_redeem_pct numeric, p_redeem_pct_vip numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  update public.merchants set redeem_pct = p_redeem_pct,
    redeem_pct_vip = case when p_redeem_pct_vip is not null then p_redeem_pct_vip
      when redeem_pct_vip is not null and redeem_pct_vip < p_redeem_pct then p_redeem_pct
      else redeem_pct_vip end
  where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'redeem_pct', r.redeem_pct, 'redeem_pct_vip', r.redeem_pct_vip);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_submit_photo(p_merchant_id uuid, p_photo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  update public.merchants set photo_pending_url = p_photo_url
  where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'photo_pending_url', r.photo_pending_url);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_topup_orders(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  perform public._expire_topup_orders();
  select coalesce(jsonb_agg(t.obj order by t.created_at desc),'[]'::jsonb) into r
  from (
    select created_at, jsonb_build_object(
      'id',id,'amount',amount,'points',points,'pack_label',pack_label,'ref',ref,'status',status,
      'paid_amount',paid_amount,'collect_url',whish_collect_url,'method',method,'collected',collected,'at',floor(extract(epoch from created_at)*1000)
    ) as obj
    from public.topup_orders where merchant_id=p_merchant_id order by created_at desc limit 20
  ) t;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_transactions(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  update public.pos_transactions set status = 'EXPIRED'
  where merchant_id = p_merchant_id and status = 'PENDING' and now() - created_at > interval '5 minutes';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.id, 'phone', t.customer_phone, 'cname', c.name, 'invoice', t.invoice,
    'redeemPts', t.redeem_pts, 'redeemVal', t.redeem_val, 'net', t.net, 'earn', t.earn,
    'items', t.items, 'status', t.status, 'at', floor(extract(epoch from t.created_at)*1000)
  ) order by t.created_at desc), '[]'::jsonb) into r
  from public.pos_transactions t left join public.customers c on c.phone = t.customer_phone
  where t.merchant_id = p_merchant_id;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_update_page(p_merchant_id uuid, p_blurb text DEFAULT NULL::text, p_enabled boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  update public.merchants set page_blurb = nullif(trim(coalesce(p_blurb,'')),''), page_enabled = coalesce(p_enabled,false)
  where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'page_blurb', r.page_blurb, 'page_enabled', r.page_enabled);
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_verify_pin(p_phone text, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants; rl_key text := 'merchant:' || p_phone;
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.merchants where phone = p_phone;
  if r is null then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl_reset(rl_key);
  return jsonb_build_object('ok', true, 'merchant', jsonb_build_object(
    'id', r.id, 'name', r.name, 'phone', r.phone, 'status', r.status, 'cat', r.cat, 'pct', r.pct,
    'tier', r.tier, 'addr', r.addr, 'photo_url', r.photo_url, 'photo_pending_url', r.photo_pending_url,
    'logo_url', r.logo_url,
    'poster_printed', r.poster_printed, 'warns', r.warns,
    'redeem_pct', r.redeem_pct, 'redeem_pct_vip', r.redeem_pct_vip,
    'pending_name', r.pending_name, 'pending_addr', r.pending_addr));
end; $function$
;
CREATE OR REPLACE FUNCTION public.merchant_wallet(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare topped numeric; cred numeric; used numeric; res numeric;
begin
  select coalesce(sum(amount),0) into topped from public.topups where merchant_id = p_merchant_id;
  select coalesce(sum(redeem_val),0) into cred from public.pos_transactions where merchant_id = p_merchant_id and status='CONFIRMED';
  select coalesce(sum(earn)/100.0,0) into used from public.pos_transactions where merchant_id = p_merchant_id and status='CONFIRMED';
  select coalesce(sum(earn)/100.0,0) into res from public.pos_transactions where merchant_id = p_merchant_id and status='PENDING';
  return jsonb_build_object('topped', topped, 'cred', cred, 'used', used, 'reserved', res, 'balance', topped+cred-used, 'avail', topped+cred-used-res);
end; $function$
;
CREATE OR REPLACE FUNCTION public.store_gallery(p_merchant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'price', price, 'img', img_url
  ) order by display_order, created_at), '[]'::jsonb) into r
  from public.merchant_gallery where merchant_id = p_merchant_id;
  return r;
end; $function$
;
CREATE OR REPLACE FUNCTION public.tp_dev_change_pin(p_old text, p_new text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid(); a tp_dev.accounts%rowtype; attempts tp_dev.pin_attempts%rowtype;
begin
if v_uid is null then return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');end if;
select * into a from tp_dev.accounts where user_id=v_uid for update;
if not found then return jsonb_build_object('ok',false,'error','ACCOUNT_REQUIRED');end if;
insert into tp_dev.pin_attempts(user_id) values(v_uid) on conflict do nothing;
select * into attempts from tp_dev.pin_attempts where user_id=v_uid for update;
if attempts.locked_until>now() then return jsonb_build_object('ok',false,'error','TEMPORARILY_LOCKED');end if;
if a.pin_hash is null or extensions.crypt(coalesce(p_old,''),a.pin_hash)<>a.pin_hash then
update tp_dev.pin_attempts set bad_count=case when bad_count>=4 then 0 else bad_count+1 end,locked_until=case when bad_count>=4 then now()+interval '15 minutes' else null end,updated_at=now() where user_id=v_uid;
return jsonb_build_object('ok',false,'error','INVALID_CURRENT_PIN');end if;
if p_new !~ '^[0-9]{4}$' or p_new in ('0000','1111','1234','4321','9999') or p_old=p_new then return jsonb_build_object('ok',false,'error','WEAK_NEW_PIN');end if;
update tp_dev.accounts set pin_hash=extensions.crypt(p_new,extensions.gen_salt('bf')) where user_id=v_uid;
update tp_dev.pin_attempts set bad_count=0,locked_until=null,updated_at=now() where user_id=v_uid;
return jsonb_build_object('ok',true,'notification_required',true);
end $function$
;
CREATE OR REPLACE FUNCTION public.tp_dev_confirm_transaction(p_id uuid, p_confirm boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid(); t tp_dev.demo_transactions%rowtype;
begin
if v_uid is null then return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');end if;
select * into t from tp_dev.demo_transactions where id=p_id for update;
if not found or t.user_id<>v_uid then return jsonb_build_object('ok',false,'error','NOT_FOUND');end if;
if t.status<>'PENDING' then return jsonb_build_object('ok',true,'status',t.status,'already_decided',true);end if;
if now()-t.created_at>interval '15 minutes' then return jsonb_build_object('ok',false,'error','EXPIRED');end if;
update tp_dev.demo_transactions set status=case when p_confirm then 'CONFIRMED' else 'CANCELLED' end where id=p_id;
if p_confirm then insert into tp_dev.demo_balances(user_id,points) values(v_uid,t.points) on conflict(user_id) do update set points=tp_dev.demo_balances.points+excluded.points;end if;
return jsonb_build_object('ok',true,'status',case when p_confirm then 'CONFIRMED' else 'CANCELLED' end,'already_decided',false);
end $function$
;
CREATE OR REPLACE FUNCTION public.tp_dev_create_request(p_merchant_ref text, p_amount numeric, p_key uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid(); existing tp_dev.requests%rowtype; r tp_dev.requests%rowtype;
begin
if v_uid is null or not exists(select 1 from tp_dev.accounts where user_id=v_uid and role='customer') then return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');end if;
if p_key is null or length(trim(coalesce(p_merchant_ref,'')))=0 or p_amount is null or p_amount<=0 or p_amount>1000000 then return jsonb_build_object('ok',false,'error','INVALID_INPUT');end if;
insert into tp_dev.requests(user_id,merchant_ref,idempotency_key,amount) values(v_uid,p_merchant_ref,p_key,p_amount) on conflict(user_id,idempotency_key) do nothing returning * into r;
if r.id is null then select * into existing from tp_dev.requests where user_id=v_uid and idempotency_key=p_key;
if existing.merchant_ref<>p_merchant_ref or existing.amount<>p_amount then return jsonb_build_object('ok',false,'error','KEY_REUSED_DIFFERENT_PAYLOAD');end if; r:=existing;end if;
return jsonb_build_object('ok',true,'id',r.id,'status',r.status);
end $function$
;
CREATE OR REPLACE FUNCTION public.tp_dev_register(p_role text, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid uuid:=auth.uid(); v_email text; v_confirm timestamptz;
begin
if v_uid is null then return jsonb_build_object('ok',false,'error','AUTH_REQUIRED');end if;
select email,email_confirmed_at into v_email,v_confirm from auth.users where id=v_uid;
if v_confirm is null or v_email !~* '^[A-Za-z0-9._%+-]+@gmail\.com$' then return jsonb_build_object('ok',false,'error','VERIFIED_GMAIL_REQUIRED');end if;
if p_role not in ('customer','merchant') or p_pin !~ '^[0-9]{4}$' or p_pin in ('0000','1111','1234','4321','9999') then return jsonb_build_object('ok',false,'error','INVALID_INPUT');end if;
insert into tp_dev.accounts(user_id,role,pin_hash,email) values(v_uid,p_role,extensions.crypt(p_pin,extensions.gen_salt('bf')),lower(v_email)) on conflict(user_id) do nothing;
insert into tp_dev.demo_balances(user_id) values(v_uid) on conflict do nothing;
return jsonb_build_object('ok',true);
end $function$
;
CREATE OR REPLACE FUNCTION public.whish_confirm_payment(p_order_id uuid, p_result text, p_paid_amount numeric DEFAULT NULL::numeric, p_external_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare o public.topup_orders;
begin
  select * into o from public.topup_orders where id=p_order_id;
  if o.id is null then return jsonb_build_object('ok',false,'error','order not found'); end if;
  if o.status in ('PAID','FAILED') then return jsonb_build_object('ok',true,'status',o.status,'noop',true); end if;
  if p_external_id is not null then o.whish_external_id:=p_external_id; end if;
  if p_result='success' then
    if p_paid_amount is not null and p_paid_amount <> o.amount then
      update public.topup_orders set status='REVIEW', paid_amount=p_paid_amount, whish_external_id=coalesce(p_external_id,whish_external_id) where id=p_order_id;
      insert into public.merchant_notes(merchant_id,type,title,body)
        values (o.merchant_id,'warn','مبلغ الدفع لا يطابق الطلب', format('المرجع %s · قيد مراجعة الإدارة',o.ref));
      return jsonb_build_object('ok',true,'status','REVIEW');
    end if;
    insert into public.topups(merchant_id,amount,source,ref) values (o.merchant_id,o.amount,'wish',o.ref);
    insert into public.merchant_notes(merchant_id,type,title,body)
      values (o.merchant_id,'wallet', format('تمت إضافة $%s إلى محفظتك التشغيلية',o.amount), format('مرجع %s · عبر Whish',o.ref));
    update public.topup_orders set status='PAID', paid_at=now(), paid_amount=o.amount, whish_external_id=coalesce(p_external_id,whish_external_id) where id=p_order_id;
    return jsonb_build_object('ok',true,'status','PAID');
  else
    update public.topup_orders set status='FAILED', whish_external_id=coalesce(p_external_id,whish_external_id) where id=p_order_id;
    return jsonb_build_object('ok',true,'status','FAILED');
  end if;
end; $function$
;
CREATE OR REPLACE FUNCTION public.whish_set_collect_url(p_order_id uuid, p_collect_url text, p_external_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.topup_orders set whish_collect_url=p_collect_url, whish_external_id=p_external_id where id=p_order_id;
  return jsonb_build_object('ok',true);
end; $function$
;
alter table only public."user" alter column created_at set default now();
alter table only public."user" alter column email set default ''::text;
alter table only public."user" alter column full_name set default ''::text;
alter table only public."user" alter column id set default gen_random_uuid();
alter table only public."user" alter column phone set default ''::text;
alter table only public."user" alter column points set default '0'::bigint;
alter table only public.admin_users alter column created_at set default now();
alter table only public.admin_users alter column id set default gen_random_uuid();
alter table only public.admin_users alter column is_primary set default false;
alter table only public.auth_rate_limits alter column fail_count set default 0;
alter table only public.auth_rate_limits alter column updated_at set default now();
alter table only public.categories alter column created_at set default now();
alter table only public.categories alter column id set default gen_random_uuid();
alter table only public.categories alter column is_active set default true;
alter table only public.categories alter column sort_order set default 0;
alter table only public.categories alter column updated_at set default now();
alter table only public.customer_notes alter column created_at set default now();
alter table only public.customer_notes alter column id set default gen_random_uuid();
alter table only public.customer_notes alter column read set default false;
alter table only public.customer_requests alter column created_at set default now();
alter table only public.customer_requests alter column id set default gen_random_uuid();
alter table only public.customer_requests alter column status set default 'open'::text;
alter table only public.customer_unlocks alter column id set default gen_random_uuid();
alter table only public.customer_unlocks alter column unlocked_at set default now();
alter table only public.customers alter column created_at set default now();
alter table only public.customers alter column points set default 0;
alter table only public.customers alter column status set default 'active'::text;
alter table only public.customers alter column welcome_remain set default 0;
alter table only public.merchant_gallery alter column created_at set default now();
alter table only public.merchant_gallery alter column display_order set default 0;
alter table only public.merchant_gallery alter column id set default gen_random_uuid();
alter table only public.merchant_notes alter column created_at set default now();
alter table only public.merchant_notes alter column id set default gen_random_uuid();
alter table only public.merchant_notes alter column read set default false;
alter table only public.merchant_notes alter column severity set default 'info'::text;
alter table only public.merchant_vips alter column cap_points set default 0;
alter table only public.merchant_vips alter column created_at set default now();
alter table only public.merchant_vips alter column id set default gen_random_uuid();
alter table only public.merchants alter column created_at set default now();
alter table only public.merchants alter column extra_cats set default '{}'::text[];
alter table only public.merchants alter column id set default gen_random_uuid();
alter table only public.merchants alter column page_enabled set default false;
alter table only public.merchants alter column pct set default 5;
alter table only public.merchants alter column poster_printed set default false;
alter table only public.merchants alter column status set default 'pending'::text;
alter table only public.merchants alter column tier set default 'medium'::text;
alter table only public.merchants alter column warns set default 0;
alter table only public.offers alter column active set default true;
alter table only public.offers alter column created_at set default now();
alter table only public.offers alter column days set default 30;
alter table only public.offers alter column deleted set default false;
alter table only public.offers alter column first_time_only set default false;
alter table only public.offers alter column id set default gen_random_uuid();
alter table only public.offers alter column min_amount set default 0;
alter table only public.pos_transactions alter column created_at set default now();
alter table only public.pos_transactions alter column earn set default 0;
alter table only public.pos_transactions alter column id set default gen_random_uuid();
alter table only public.pos_transactions alter column items set default '[]'::jsonb;
alter table only public.pos_transactions alter column redeem_pts set default 0;
alter table only public.pos_transactions alter column redeem_val set default 0;
alter table only public.pos_transactions alter column status set default 'PENDING'::text;
alter table only public.topup_orders alter column collected set default false;
alter table only public.topup_orders alter column created_at set default now();
alter table only public.topup_orders alter column id set default gen_random_uuid();
alter table only public.topup_orders alter column method set default 'whish'::text;
alter table only public.topup_orders alter column status set default 'PENDING'::text;
alter table only public.topup_requests alter column created_at set default now();
alter table only public.topup_requests alter column id set default gen_random_uuid();
alter table only public.topup_requests alter column status set default 'pending'::text;
alter table only public.topups alter column created_at set default now();
alter table only public.topups alter column id set default gen_random_uuid();
alter table only public.transactions alter column created_at set default now();
alter table only public.transactions alter column id set default gen_random_uuid();
alter table only public.transactions alter column points_earned set default '0'::bigint;
alter table only public.transactions alter column status set default 'confirmed'::text;
alter table only public.treasure_pics alter column created_at set default now();
alter table only public.treasure_pics alter column display_order set default 0;
alter table only public.treasure_pics alter column id set default gen_random_uuid();
alter table only public.wallet_orders alter column created_at set default now();
alter table only public.wallet_orders alter column id set default gen_random_uuid();
alter table only public.wallet_orders alter column status set default 'PENDING'::text;
alter table only tp_dev.accounts alter column created_at set default now();
alter table only tp_dev.demo_balances alter column points set default 0;
alter table only tp_dev.demo_transactions alter column created_at set default now();
alter table only tp_dev.demo_transactions alter column id set default gen_random_uuid();
alter table only tp_dev.demo_transactions alter column status set default 'PENDING'::text;
alter table only tp_dev.pin_attempts alter column bad_count set default 0;
alter table only tp_dev.pin_attempts alter column updated_at set default now();
alter table only tp_dev.requests alter column created_at set default now();
alter table only tp_dev.requests alter column id set default gen_random_uuid();
alter table only tp_dev.requests alter column status set default 'open'::text;
alter table only public."user" add constraint user_pkey PRIMARY KEY (id);
alter table only public.admin_users add constraint admin_users_pkey PRIMARY KEY (id);
alter table only public.admin_users add constraint admin_users_username_key UNIQUE (username);
alter table only public.app_settings add constraint app_settings_pkey PRIMARY KEY (key);
alter table only public.app_text_settings add constraint app_text_settings_pkey PRIMARY KEY (key);
alter table only public.auth_rate_limits add constraint auth_rate_limits_pkey PRIMARY KEY (key);
alter table only public.categories add constraint categories_pkey PRIMARY KEY (id);
alter table only public.categories add constraint categories_slug_key UNIQUE (slug);
alter table only public.customer_notes add constraint customer_notes_pkey PRIMARY KEY (id);
alter table only public.customer_requests add constraint customer_requests_pkey PRIMARY KEY (id);
alter table only public.customer_requests add constraint customer_requests_status_check CHECK ((status = ANY (ARRAY['open'::text, 'used'::text, 'expired'::text, 'cancelled'::text])));
alter table only public.customer_unlocks add constraint customer_unlocks_customer_phone_pic_id_key UNIQUE (customer_phone, pic_id);
alter table only public.customer_unlocks add constraint customer_unlocks_pkey PRIMARY KEY (id);
alter table only public.customers add constraint customers_pkey PRIMARY KEY (phone);
alter table only public.customers add constraint customers_status_check CHECK ((status = ANY (ARRAY['active'::text, 'frozen'::text])));
alter table only public.merchant_gallery add constraint merchant_gallery_pkey PRIMARY KEY (id);
alter table only public.merchant_notes add constraint merchant_notes_pkey PRIMARY KEY (id);
alter table only public.merchant_vips add constraint merchant_vips_merchant_id_customer_phone_key UNIQUE (merchant_id, customer_phone);
alter table only public.merchant_vips add constraint merchant_vips_pkey PRIMARY KEY (id);
alter table only public.merchants add constraint merchants_phone_key UNIQUE (phone);
alter table only public.merchants add constraint merchants_pkey PRIMARY KEY (id);
alter table only public.merchants add constraint merchants_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'frozen'::text, 'excluded'::text, 'rejected'::text])));
alter table only public.merchants add constraint merchants_tier_check CHECK ((tier = ANY (ARRAY['large'::text, 'medium'::text, 'small'::text])));
alter table only public.offers add constraint offers_pkey PRIMARY KEY (id);
alter table only public.offers add constraint offers_type_check CHECK ((type = ANY (ARRAY['discount'::text, 'gift'::text, 'product'::text, 'bonus'::text])));
alter table only public.pos_transactions add constraint pos_transactions_pkey PRIMARY KEY (id);
alter table only public.pos_transactions add constraint pos_transactions_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'CONFIRMED'::text, 'CANCELLED'::text, 'EXPIRED'::text, 'REVIEW'::text])));
alter table only public.topup_orders add constraint topup_orders_pkey PRIMARY KEY (id);
alter table only public.topup_orders add constraint topup_orders_ref_key UNIQUE (ref);
alter table only public.topup_orders add constraint topup_orders_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'PAID'::text, 'EXPIRED'::text, 'REVIEW'::text, 'FAILED'::text])));
alter table only public.topup_requests add constraint topup_requests_pkey PRIMARY KEY (id);
alter table only public.topup_requests add constraint topup_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])));
alter table only public.topups add constraint topups_pkey PRIMARY KEY (id);
alter table only public.transactions add constraint transactions_pkey PRIMARY KEY (id);
alter table only public.treasure_pics add constraint treasure_pics_pkey PRIMARY KEY (id);
alter table only public.wallet_orders add constraint wallet_orders_pkey PRIMARY KEY (id);
alter table only public.wallet_orders add constraint wallet_orders_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'REVIEW'::text, 'PAID'::text])));
alter table only tp_dev.accounts add constraint accounts_pkey PRIMARY KEY (user_id);
alter table only tp_dev.accounts add constraint accounts_role_check CHECK ((role = ANY (ARRAY['customer'::text, 'merchant'::text])));
alter table only tp_dev.demo_balances add constraint demo_balances_pkey PRIMARY KEY (user_id);
alter table only tp_dev.demo_transactions add constraint demo_transactions_pkey PRIMARY KEY (id);
alter table only tp_dev.demo_transactions add constraint demo_transactions_points_check CHECK ((points >= 0));
alter table only tp_dev.demo_transactions add constraint demo_transactions_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'CONFIRMED'::text, 'CANCELLED'::text])));
alter table only tp_dev.pin_attempts add constraint pin_attempts_pkey PRIMARY KEY (user_id);
alter table only tp_dev.requests add constraint requests_amount_check CHECK ((amount > (0)::numeric));
alter table only tp_dev.requests add constraint requests_pkey PRIMARY KEY (id);
alter table only tp_dev.requests add constraint requests_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])));
alter table only tp_dev.requests add constraint requests_user_id_idempotency_key_key UNIQUE (user_id, idempotency_key);
alter table only public.categories add constraint categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES categories(id);
alter table only public.customer_notes add constraint customer_notes_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone) ON DELETE CASCADE;
alter table only public.customer_requests add constraint customer_requests_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone);
alter table only public.customer_requests add constraint customer_requests_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table only public.customer_requests add constraint customer_requests_offer_id_fkey FOREIGN KEY (offer_id) REFERENCES offers(id);
alter table only public.customer_unlocks add constraint customer_unlocks_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone) ON DELETE CASCADE;
alter table only public.customer_unlocks add constraint customer_unlocks_pic_id_fkey FOREIGN KEY (pic_id) REFERENCES treasure_pics(id) ON DELETE CASCADE;
alter table only public.merchant_gallery add constraint merchant_gallery_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table only public.merchant_notes add constraint merchant_notes_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE;
alter table only public.merchant_vips add constraint merchant_vips_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone) ON DELETE CASCADE;
alter table only public.merchant_vips add constraint merchant_vips_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE;
alter table only public.offers add constraint offers_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE;
alter table only public.pos_transactions add constraint pos_transactions_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone);
alter table only public.pos_transactions add constraint pos_transactions_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table only public.topup_orders add constraint topup_orders_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table only public.topup_requests add constraint topup_requests_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table only public.topups add constraint topups_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table only public.transactions add constraint transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES "user"(id);
alter table only public.wallet_orders add constraint wallet_orders_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table only tp_dev.accounts add constraint accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table only tp_dev.demo_balances add constraint demo_balances_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table only tp_dev.demo_transactions add constraint demo_transactions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
alter table only tp_dev.pin_attempts add constraint pin_attempts_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
alter table only tp_dev.requests add constraint requests_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id);
CREATE INDEX categories_parent_idx ON public.categories USING btree (parent_id);
CREATE INDEX topup_orders_mid_idx ON public.topup_orders USING btree (merchant_id);
alter table public."user" enable row level security;
alter table public.admin_users enable row level security;
alter table public.app_settings enable row level security;
alter table public.app_text_settings enable row level security;
alter table public.auth_rate_limits enable row level security;
alter table public.categories enable row level security;
alter table public.customer_notes enable row level security;
alter table public.customer_requests enable row level security;
alter table public.customer_unlocks enable row level security;
alter table public.customers enable row level security;
alter table public.merchant_gallery enable row level security;
alter table public.merchant_notes enable row level security;
alter table public.merchant_vips enable row level security;
alter table public.merchants enable row level security;
alter table public.offers enable row level security;
alter table public.pos_transactions enable row level security;
alter table public.topup_orders enable row level security;
alter table public.topup_requests enable row level security;
alter table public.topups enable row level security;
alter table public.transactions enable row level security;
alter table public.treasure_pics enable row level security;
alter table public.wallet_orders enable row level security;
alter table tp_dev.accounts enable row level security;
alter table tp_dev.demo_balances enable row level security;
alter table tp_dev.demo_transactions enable row level security;
alter table tp_dev.pin_attempts enable row level security;
alter table tp_dev.requests enable row level security;
revoke all on table public."user" from public, anon, authenticated, service_role;
grant DELETE on table public."user" to anon;
grant INSERT on table public."user" to anon;
grant MAINTAIN on table public."user" to anon;
grant REFERENCES on table public."user" to anon;
grant SELECT on table public."user" to anon;
grant TRIGGER on table public."user" to anon;
grant TRUNCATE on table public."user" to anon;
grant UPDATE on table public."user" to anon;
grant DELETE on table public."user" to authenticated;
grant INSERT on table public."user" to authenticated;
grant MAINTAIN on table public."user" to authenticated;
grant REFERENCES on table public."user" to authenticated;
grant SELECT on table public."user" to authenticated;
grant TRIGGER on table public."user" to authenticated;
grant TRUNCATE on table public."user" to authenticated;
grant UPDATE on table public."user" to authenticated;
grant DELETE on table public."user" to service_role;
grant INSERT on table public."user" to service_role;
grant MAINTAIN on table public."user" to service_role;
grant REFERENCES on table public."user" to service_role;
grant SELECT on table public."user" to service_role;
grant TRIGGER on table public."user" to service_role;
grant TRUNCATE on table public."user" to service_role;
grant UPDATE on table public."user" to service_role;
revoke all on table public.admin_users from public, anon, authenticated, service_role;
grant DELETE on table public.admin_users to anon;
grant INSERT on table public.admin_users to anon;
grant MAINTAIN on table public.admin_users to anon;
grant REFERENCES on table public.admin_users to anon;
grant SELECT on table public.admin_users to anon;
grant TRIGGER on table public.admin_users to anon;
grant TRUNCATE on table public.admin_users to anon;
grant UPDATE on table public.admin_users to anon;
grant DELETE on table public.admin_users to authenticated;
grant INSERT on table public.admin_users to authenticated;
grant MAINTAIN on table public.admin_users to authenticated;
grant REFERENCES on table public.admin_users to authenticated;
grant SELECT on table public.admin_users to authenticated;
grant TRIGGER on table public.admin_users to authenticated;
grant TRUNCATE on table public.admin_users to authenticated;
grant UPDATE on table public.admin_users to authenticated;
grant DELETE on table public.admin_users to service_role;
grant INSERT on table public.admin_users to service_role;
grant MAINTAIN on table public.admin_users to service_role;
grant REFERENCES on table public.admin_users to service_role;
grant SELECT on table public.admin_users to service_role;
grant TRIGGER on table public.admin_users to service_role;
grant TRUNCATE on table public.admin_users to service_role;
grant UPDATE on table public.admin_users to service_role;
revoke all on table public.app_settings from public, anon, authenticated, service_role;
grant DELETE on table public.app_settings to anon;
grant INSERT on table public.app_settings to anon;
grant MAINTAIN on table public.app_settings to anon;
grant REFERENCES on table public.app_settings to anon;
grant SELECT on table public.app_settings to anon;
grant TRIGGER on table public.app_settings to anon;
grant TRUNCATE on table public.app_settings to anon;
grant UPDATE on table public.app_settings to anon;
grant DELETE on table public.app_settings to authenticated;
grant INSERT on table public.app_settings to authenticated;
grant MAINTAIN on table public.app_settings to authenticated;
grant REFERENCES on table public.app_settings to authenticated;
grant SELECT on table public.app_settings to authenticated;
grant TRIGGER on table public.app_settings to authenticated;
grant TRUNCATE on table public.app_settings to authenticated;
grant UPDATE on table public.app_settings to authenticated;
grant DELETE on table public.app_settings to service_role;
grant INSERT on table public.app_settings to service_role;
grant MAINTAIN on table public.app_settings to service_role;
grant REFERENCES on table public.app_settings to service_role;
grant SELECT on table public.app_settings to service_role;
grant TRIGGER on table public.app_settings to service_role;
grant TRUNCATE on table public.app_settings to service_role;
grant UPDATE on table public.app_settings to service_role;
revoke all on table public.app_text_settings from public, anon, authenticated, service_role;
grant DELETE on table public.app_text_settings to anon;
grant INSERT on table public.app_text_settings to anon;
grant MAINTAIN on table public.app_text_settings to anon;
grant REFERENCES on table public.app_text_settings to anon;
grant SELECT on table public.app_text_settings to anon;
grant TRIGGER on table public.app_text_settings to anon;
grant TRUNCATE on table public.app_text_settings to anon;
grant UPDATE on table public.app_text_settings to anon;
grant DELETE on table public.app_text_settings to authenticated;
grant INSERT on table public.app_text_settings to authenticated;
grant MAINTAIN on table public.app_text_settings to authenticated;
grant REFERENCES on table public.app_text_settings to authenticated;
grant SELECT on table public.app_text_settings to authenticated;
grant TRIGGER on table public.app_text_settings to authenticated;
grant TRUNCATE on table public.app_text_settings to authenticated;
grant UPDATE on table public.app_text_settings to authenticated;
grant DELETE on table public.app_text_settings to service_role;
grant INSERT on table public.app_text_settings to service_role;
grant MAINTAIN on table public.app_text_settings to service_role;
grant REFERENCES on table public.app_text_settings to service_role;
grant SELECT on table public.app_text_settings to service_role;
grant TRIGGER on table public.app_text_settings to service_role;
grant TRUNCATE on table public.app_text_settings to service_role;
grant UPDATE on table public.app_text_settings to service_role;
revoke all on table public.auth_rate_limits from public, anon, authenticated, service_role;
grant DELETE on table public.auth_rate_limits to anon;
grant INSERT on table public.auth_rate_limits to anon;
grant MAINTAIN on table public.auth_rate_limits to anon;
grant REFERENCES on table public.auth_rate_limits to anon;
grant SELECT on table public.auth_rate_limits to anon;
grant TRIGGER on table public.auth_rate_limits to anon;
grant TRUNCATE on table public.auth_rate_limits to anon;
grant UPDATE on table public.auth_rate_limits to anon;
grant DELETE on table public.auth_rate_limits to authenticated;
grant INSERT on table public.auth_rate_limits to authenticated;
grant MAINTAIN on table public.auth_rate_limits to authenticated;
grant REFERENCES on table public.auth_rate_limits to authenticated;
grant SELECT on table public.auth_rate_limits to authenticated;
grant TRIGGER on table public.auth_rate_limits to authenticated;
grant TRUNCATE on table public.auth_rate_limits to authenticated;
grant UPDATE on table public.auth_rate_limits to authenticated;
grant DELETE on table public.auth_rate_limits to service_role;
grant INSERT on table public.auth_rate_limits to service_role;
grant MAINTAIN on table public.auth_rate_limits to service_role;
grant REFERENCES on table public.auth_rate_limits to service_role;
grant SELECT on table public.auth_rate_limits to service_role;
grant TRIGGER on table public.auth_rate_limits to service_role;
grant TRUNCATE on table public.auth_rate_limits to service_role;
grant UPDATE on table public.auth_rate_limits to service_role;
revoke all on table public.categories from public, anon, authenticated, service_role;
grant DELETE on table public.categories to anon;
grant INSERT on table public.categories to anon;
grant MAINTAIN on table public.categories to anon;
grant REFERENCES on table public.categories to anon;
grant SELECT on table public.categories to anon;
grant TRIGGER on table public.categories to anon;
grant TRUNCATE on table public.categories to anon;
grant UPDATE on table public.categories to anon;
grant DELETE on table public.categories to authenticated;
grant INSERT on table public.categories to authenticated;
grant MAINTAIN on table public.categories to authenticated;
grant REFERENCES on table public.categories to authenticated;
grant SELECT on table public.categories to authenticated;
grant TRIGGER on table public.categories to authenticated;
grant TRUNCATE on table public.categories to authenticated;
grant UPDATE on table public.categories to authenticated;
grant DELETE on table public.categories to service_role;
grant INSERT on table public.categories to service_role;
grant MAINTAIN on table public.categories to service_role;
grant REFERENCES on table public.categories to service_role;
grant SELECT on table public.categories to service_role;
grant TRIGGER on table public.categories to service_role;
grant TRUNCATE on table public.categories to service_role;
grant UPDATE on table public.categories to service_role;
revoke all on table public.customer_notes from public, anon, authenticated, service_role;
grant DELETE on table public.customer_notes to anon;
grant INSERT on table public.customer_notes to anon;
grant MAINTAIN on table public.customer_notes to anon;
grant REFERENCES on table public.customer_notes to anon;
grant SELECT on table public.customer_notes to anon;
grant TRIGGER on table public.customer_notes to anon;
grant TRUNCATE on table public.customer_notes to anon;
grant UPDATE on table public.customer_notes to anon;
grant DELETE on table public.customer_notes to authenticated;
grant INSERT on table public.customer_notes to authenticated;
grant MAINTAIN on table public.customer_notes to authenticated;
grant REFERENCES on table public.customer_notes to authenticated;
grant SELECT on table public.customer_notes to authenticated;
grant TRIGGER on table public.customer_notes to authenticated;
grant TRUNCATE on table public.customer_notes to authenticated;
grant UPDATE on table public.customer_notes to authenticated;
grant DELETE on table public.customer_notes to service_role;
grant INSERT on table public.customer_notes to service_role;
grant MAINTAIN on table public.customer_notes to service_role;
grant REFERENCES on table public.customer_notes to service_role;
grant SELECT on table public.customer_notes to service_role;
grant TRIGGER on table public.customer_notes to service_role;
grant TRUNCATE on table public.customer_notes to service_role;
grant UPDATE on table public.customer_notes to service_role;
revoke all on table public.customer_requests from public, anon, authenticated, service_role;
grant DELETE on table public.customer_requests to anon;
grant INSERT on table public.customer_requests to anon;
grant MAINTAIN on table public.customer_requests to anon;
grant REFERENCES on table public.customer_requests to anon;
grant SELECT on table public.customer_requests to anon;
grant TRIGGER on table public.customer_requests to anon;
grant TRUNCATE on table public.customer_requests to anon;
grant UPDATE on table public.customer_requests to anon;
grant DELETE on table public.customer_requests to authenticated;
grant INSERT on table public.customer_requests to authenticated;
grant MAINTAIN on table public.customer_requests to authenticated;
grant REFERENCES on table public.customer_requests to authenticated;
grant SELECT on table public.customer_requests to authenticated;
grant TRIGGER on table public.customer_requests to authenticated;
grant TRUNCATE on table public.customer_requests to authenticated;
grant UPDATE on table public.customer_requests to authenticated;
grant DELETE on table public.customer_requests to service_role;
grant INSERT on table public.customer_requests to service_role;
grant MAINTAIN on table public.customer_requests to service_role;
grant REFERENCES on table public.customer_requests to service_role;
grant SELECT on table public.customer_requests to service_role;
grant TRIGGER on table public.customer_requests to service_role;
grant TRUNCATE on table public.customer_requests to service_role;
grant UPDATE on table public.customer_requests to service_role;
revoke all on table public.customer_unlocks from public, anon, authenticated, service_role;
grant DELETE on table public.customer_unlocks to anon;
grant INSERT on table public.customer_unlocks to anon;
grant MAINTAIN on table public.customer_unlocks to anon;
grant REFERENCES on table public.customer_unlocks to anon;
grant SELECT on table public.customer_unlocks to anon;
grant TRIGGER on table public.customer_unlocks to anon;
grant TRUNCATE on table public.customer_unlocks to anon;
grant UPDATE on table public.customer_unlocks to anon;
grant DELETE on table public.customer_unlocks to authenticated;
grant INSERT on table public.customer_unlocks to authenticated;
grant MAINTAIN on table public.customer_unlocks to authenticated;
grant REFERENCES on table public.customer_unlocks to authenticated;
grant SELECT on table public.customer_unlocks to authenticated;
grant TRIGGER on table public.customer_unlocks to authenticated;
grant TRUNCATE on table public.customer_unlocks to authenticated;
grant UPDATE on table public.customer_unlocks to authenticated;
grant DELETE on table public.customer_unlocks to service_role;
grant INSERT on table public.customer_unlocks to service_role;
grant MAINTAIN on table public.customer_unlocks to service_role;
grant REFERENCES on table public.customer_unlocks to service_role;
grant SELECT on table public.customer_unlocks to service_role;
grant TRIGGER on table public.customer_unlocks to service_role;
grant TRUNCATE on table public.customer_unlocks to service_role;
grant UPDATE on table public.customer_unlocks to service_role;
revoke all on table public.customers from public, anon, authenticated, service_role;
grant DELETE on table public.customers to anon;
grant INSERT on table public.customers to anon;
grant MAINTAIN on table public.customers to anon;
grant REFERENCES on table public.customers to anon;
grant SELECT on table public.customers to anon;
grant TRIGGER on table public.customers to anon;
grant TRUNCATE on table public.customers to anon;
grant UPDATE on table public.customers to anon;
grant DELETE on table public.customers to authenticated;
grant INSERT on table public.customers to authenticated;
grant MAINTAIN on table public.customers to authenticated;
grant REFERENCES on table public.customers to authenticated;
grant SELECT on table public.customers to authenticated;
grant TRIGGER on table public.customers to authenticated;
grant TRUNCATE on table public.customers to authenticated;
grant UPDATE on table public.customers to authenticated;
grant DELETE on table public.customers to service_role;
grant INSERT on table public.customers to service_role;
grant MAINTAIN on table public.customers to service_role;
grant REFERENCES on table public.customers to service_role;
grant SELECT on table public.customers to service_role;
grant TRIGGER on table public.customers to service_role;
grant TRUNCATE on table public.customers to service_role;
grant UPDATE on table public.customers to service_role;
revoke all on table public.merchant_gallery from public, anon, authenticated, service_role;
grant DELETE on table public.merchant_gallery to anon;
grant INSERT on table public.merchant_gallery to anon;
grant MAINTAIN on table public.merchant_gallery to anon;
grant REFERENCES on table public.merchant_gallery to anon;
grant SELECT on table public.merchant_gallery to anon;
grant TRIGGER on table public.merchant_gallery to anon;
grant TRUNCATE on table public.merchant_gallery to anon;
grant UPDATE on table public.merchant_gallery to anon;
grant DELETE on table public.merchant_gallery to authenticated;
grant INSERT on table public.merchant_gallery to authenticated;
grant MAINTAIN on table public.merchant_gallery to authenticated;
grant REFERENCES on table public.merchant_gallery to authenticated;
grant SELECT on table public.merchant_gallery to authenticated;
grant TRIGGER on table public.merchant_gallery to authenticated;
grant TRUNCATE on table public.merchant_gallery to authenticated;
grant UPDATE on table public.merchant_gallery to authenticated;
grant DELETE on table public.merchant_gallery to service_role;
grant INSERT on table public.merchant_gallery to service_role;
grant MAINTAIN on table public.merchant_gallery to service_role;
grant REFERENCES on table public.merchant_gallery to service_role;
grant SELECT on table public.merchant_gallery to service_role;
grant TRIGGER on table public.merchant_gallery to service_role;
grant TRUNCATE on table public.merchant_gallery to service_role;
grant UPDATE on table public.merchant_gallery to service_role;
revoke all on table public.merchant_notes from public, anon, authenticated, service_role;
grant DELETE on table public.merchant_notes to anon;
grant INSERT on table public.merchant_notes to anon;
grant MAINTAIN on table public.merchant_notes to anon;
grant REFERENCES on table public.merchant_notes to anon;
grant SELECT on table public.merchant_notes to anon;
grant TRIGGER on table public.merchant_notes to anon;
grant TRUNCATE on table public.merchant_notes to anon;
grant UPDATE on table public.merchant_notes to anon;
grant DELETE on table public.merchant_notes to authenticated;
grant INSERT on table public.merchant_notes to authenticated;
grant MAINTAIN on table public.merchant_notes to authenticated;
grant REFERENCES on table public.merchant_notes to authenticated;
grant SELECT on table public.merchant_notes to authenticated;
grant TRIGGER on table public.merchant_notes to authenticated;
grant TRUNCATE on table public.merchant_notes to authenticated;
grant UPDATE on table public.merchant_notes to authenticated;
grant DELETE on table public.merchant_notes to service_role;
grant INSERT on table public.merchant_notes to service_role;
grant MAINTAIN on table public.merchant_notes to service_role;
grant REFERENCES on table public.merchant_notes to service_role;
grant SELECT on table public.merchant_notes to service_role;
grant TRIGGER on table public.merchant_notes to service_role;
grant TRUNCATE on table public.merchant_notes to service_role;
grant UPDATE on table public.merchant_notes to service_role;
revoke all on table public.merchant_vips from public, anon, authenticated, service_role;
grant DELETE on table public.merchant_vips to anon;
grant INSERT on table public.merchant_vips to anon;
grant MAINTAIN on table public.merchant_vips to anon;
grant REFERENCES on table public.merchant_vips to anon;
grant SELECT on table public.merchant_vips to anon;
grant TRIGGER on table public.merchant_vips to anon;
grant TRUNCATE on table public.merchant_vips to anon;
grant UPDATE on table public.merchant_vips to anon;
grant DELETE on table public.merchant_vips to authenticated;
grant INSERT on table public.merchant_vips to authenticated;
grant MAINTAIN on table public.merchant_vips to authenticated;
grant REFERENCES on table public.merchant_vips to authenticated;
grant SELECT on table public.merchant_vips to authenticated;
grant TRIGGER on table public.merchant_vips to authenticated;
grant TRUNCATE on table public.merchant_vips to authenticated;
grant UPDATE on table public.merchant_vips to authenticated;
grant DELETE on table public.merchant_vips to service_role;
grant INSERT on table public.merchant_vips to service_role;
grant MAINTAIN on table public.merchant_vips to service_role;
grant REFERENCES on table public.merchant_vips to service_role;
grant SELECT on table public.merchant_vips to service_role;
grant TRIGGER on table public.merchant_vips to service_role;
grant TRUNCATE on table public.merchant_vips to service_role;
grant UPDATE on table public.merchant_vips to service_role;
revoke all on table public.merchants from public, anon, authenticated, service_role;
grant DELETE on table public.merchants to anon;
grant INSERT on table public.merchants to anon;
grant MAINTAIN on table public.merchants to anon;
grant REFERENCES on table public.merchants to anon;
grant SELECT on table public.merchants to anon;
grant TRIGGER on table public.merchants to anon;
grant TRUNCATE on table public.merchants to anon;
grant UPDATE on table public.merchants to anon;
grant DELETE on table public.merchants to authenticated;
grant INSERT on table public.merchants to authenticated;
grant MAINTAIN on table public.merchants to authenticated;
grant REFERENCES on table public.merchants to authenticated;
grant SELECT on table public.merchants to authenticated;
grant TRIGGER on table public.merchants to authenticated;
grant TRUNCATE on table public.merchants to authenticated;
grant UPDATE on table public.merchants to authenticated;
grant DELETE on table public.merchants to service_role;
grant INSERT on table public.merchants to service_role;
grant MAINTAIN on table public.merchants to service_role;
grant REFERENCES on table public.merchants to service_role;
grant SELECT on table public.merchants to service_role;
grant TRIGGER on table public.merchants to service_role;
grant TRUNCATE on table public.merchants to service_role;
grant UPDATE on table public.merchants to service_role;
revoke all on table public.offers from public, anon, authenticated, service_role;
grant DELETE on table public.offers to anon;
grant INSERT on table public.offers to anon;
grant MAINTAIN on table public.offers to anon;
grant REFERENCES on table public.offers to anon;
grant SELECT on table public.offers to anon;
grant TRIGGER on table public.offers to anon;
grant TRUNCATE on table public.offers to anon;
grant UPDATE on table public.offers to anon;
grant DELETE on table public.offers to authenticated;
grant INSERT on table public.offers to authenticated;
grant MAINTAIN on table public.offers to authenticated;
grant REFERENCES on table public.offers to authenticated;
grant SELECT on table public.offers to authenticated;
grant TRIGGER on table public.offers to authenticated;
grant TRUNCATE on table public.offers to authenticated;
grant UPDATE on table public.offers to authenticated;
grant DELETE on table public.offers to service_role;
grant INSERT on table public.offers to service_role;
grant MAINTAIN on table public.offers to service_role;
grant REFERENCES on table public.offers to service_role;
grant SELECT on table public.offers to service_role;
grant TRIGGER on table public.offers to service_role;
grant TRUNCATE on table public.offers to service_role;
grant UPDATE on table public.offers to service_role;
revoke all on table public.pos_transactions from public, anon, authenticated, service_role;
grant DELETE on table public.pos_transactions to anon;
grant INSERT on table public.pos_transactions to anon;
grant MAINTAIN on table public.pos_transactions to anon;
grant REFERENCES on table public.pos_transactions to anon;
grant SELECT on table public.pos_transactions to anon;
grant TRIGGER on table public.pos_transactions to anon;
grant TRUNCATE on table public.pos_transactions to anon;
grant UPDATE on table public.pos_transactions to anon;
grant DELETE on table public.pos_transactions to authenticated;
grant INSERT on table public.pos_transactions to authenticated;
grant MAINTAIN on table public.pos_transactions to authenticated;
grant REFERENCES on table public.pos_transactions to authenticated;
grant SELECT on table public.pos_transactions to authenticated;
grant TRIGGER on table public.pos_transactions to authenticated;
grant TRUNCATE on table public.pos_transactions to authenticated;
grant UPDATE on table public.pos_transactions to authenticated;
grant DELETE on table public.pos_transactions to service_role;
grant INSERT on table public.pos_transactions to service_role;
grant MAINTAIN on table public.pos_transactions to service_role;
grant REFERENCES on table public.pos_transactions to service_role;
grant SELECT on table public.pos_transactions to service_role;
grant TRIGGER on table public.pos_transactions to service_role;
grant TRUNCATE on table public.pos_transactions to service_role;
grant UPDATE on table public.pos_transactions to service_role;
revoke all on table public.topup_orders from public, anon, authenticated, service_role;
grant DELETE on table public.topup_orders to anon;
grant INSERT on table public.topup_orders to anon;
grant MAINTAIN on table public.topup_orders to anon;
grant REFERENCES on table public.topup_orders to anon;
grant SELECT on table public.topup_orders to anon;
grant TRIGGER on table public.topup_orders to anon;
grant TRUNCATE on table public.topup_orders to anon;
grant UPDATE on table public.topup_orders to anon;
grant DELETE on table public.topup_orders to authenticated;
grant INSERT on table public.topup_orders to authenticated;
grant MAINTAIN on table public.topup_orders to authenticated;
grant REFERENCES on table public.topup_orders to authenticated;
grant SELECT on table public.topup_orders to authenticated;
grant TRIGGER on table public.topup_orders to authenticated;
grant TRUNCATE on table public.topup_orders to authenticated;
grant UPDATE on table public.topup_orders to authenticated;
grant DELETE on table public.topup_orders to service_role;
grant INSERT on table public.topup_orders to service_role;
grant MAINTAIN on table public.topup_orders to service_role;
grant REFERENCES on table public.topup_orders to service_role;
grant SELECT on table public.topup_orders to service_role;
grant TRIGGER on table public.topup_orders to service_role;
grant TRUNCATE on table public.topup_orders to service_role;
grant UPDATE on table public.topup_orders to service_role;
revoke all on table public.topup_requests from public, anon, authenticated, service_role;
grant DELETE on table public.topup_requests to anon;
grant INSERT on table public.topup_requests to anon;
grant MAINTAIN on table public.topup_requests to anon;
grant REFERENCES on table public.topup_requests to anon;
grant SELECT on table public.topup_requests to anon;
grant TRIGGER on table public.topup_requests to anon;
grant TRUNCATE on table public.topup_requests to anon;
grant UPDATE on table public.topup_requests to anon;
grant DELETE on table public.topup_requests to authenticated;
grant INSERT on table public.topup_requests to authenticated;
grant MAINTAIN on table public.topup_requests to authenticated;
grant REFERENCES on table public.topup_requests to authenticated;
grant SELECT on table public.topup_requests to authenticated;
grant TRIGGER on table public.topup_requests to authenticated;
grant TRUNCATE on table public.topup_requests to authenticated;
grant UPDATE on table public.topup_requests to authenticated;
grant DELETE on table public.topup_requests to service_role;
grant INSERT on table public.topup_requests to service_role;
grant MAINTAIN on table public.topup_requests to service_role;
grant REFERENCES on table public.topup_requests to service_role;
grant SELECT on table public.topup_requests to service_role;
grant TRIGGER on table public.topup_requests to service_role;
grant TRUNCATE on table public.topup_requests to service_role;
grant UPDATE on table public.topup_requests to service_role;
revoke all on table public.topups from public, anon, authenticated, service_role;
grant DELETE on table public.topups to anon;
grant INSERT on table public.topups to anon;
grant MAINTAIN on table public.topups to anon;
grant REFERENCES on table public.topups to anon;
grant SELECT on table public.topups to anon;
grant TRIGGER on table public.topups to anon;
grant TRUNCATE on table public.topups to anon;
grant UPDATE on table public.topups to anon;
grant DELETE on table public.topups to authenticated;
grant INSERT on table public.topups to authenticated;
grant MAINTAIN on table public.topups to authenticated;
grant REFERENCES on table public.topups to authenticated;
grant SELECT on table public.topups to authenticated;
grant TRIGGER on table public.topups to authenticated;
grant TRUNCATE on table public.topups to authenticated;
grant UPDATE on table public.topups to authenticated;
grant DELETE on table public.topups to service_role;
grant INSERT on table public.topups to service_role;
grant MAINTAIN on table public.topups to service_role;
grant REFERENCES on table public.topups to service_role;
grant SELECT on table public.topups to service_role;
grant TRIGGER on table public.topups to service_role;
grant TRUNCATE on table public.topups to service_role;
grant UPDATE on table public.topups to service_role;
revoke all on table public.transactions from public, anon, authenticated, service_role;
grant DELETE on table public.transactions to anon;
grant INSERT on table public.transactions to anon;
grant MAINTAIN on table public.transactions to anon;
grant REFERENCES on table public.transactions to anon;
grant SELECT on table public.transactions to anon;
grant TRIGGER on table public.transactions to anon;
grant TRUNCATE on table public.transactions to anon;
grant UPDATE on table public.transactions to anon;
grant DELETE on table public.transactions to authenticated;
grant INSERT on table public.transactions to authenticated;
grant MAINTAIN on table public.transactions to authenticated;
grant REFERENCES on table public.transactions to authenticated;
grant SELECT on table public.transactions to authenticated;
grant TRIGGER on table public.transactions to authenticated;
grant TRUNCATE on table public.transactions to authenticated;
grant UPDATE on table public.transactions to authenticated;
grant DELETE on table public.transactions to service_role;
grant INSERT on table public.transactions to service_role;
grant MAINTAIN on table public.transactions to service_role;
grant REFERENCES on table public.transactions to service_role;
grant SELECT on table public.transactions to service_role;
grant TRIGGER on table public.transactions to service_role;
grant TRUNCATE on table public.transactions to service_role;
grant UPDATE on table public.transactions to service_role;
revoke all on table public.treasure_pics from public, anon, authenticated, service_role;
grant DELETE on table public.treasure_pics to anon;
grant INSERT on table public.treasure_pics to anon;
grant MAINTAIN on table public.treasure_pics to anon;
grant REFERENCES on table public.treasure_pics to anon;
grant SELECT on table public.treasure_pics to anon;
grant TRIGGER on table public.treasure_pics to anon;
grant TRUNCATE on table public.treasure_pics to anon;
grant UPDATE on table public.treasure_pics to anon;
grant DELETE on table public.treasure_pics to authenticated;
grant INSERT on table public.treasure_pics to authenticated;
grant MAINTAIN on table public.treasure_pics to authenticated;
grant REFERENCES on table public.treasure_pics to authenticated;
grant SELECT on table public.treasure_pics to authenticated;
grant TRIGGER on table public.treasure_pics to authenticated;
grant TRUNCATE on table public.treasure_pics to authenticated;
grant UPDATE on table public.treasure_pics to authenticated;
grant DELETE on table public.treasure_pics to service_role;
grant INSERT on table public.treasure_pics to service_role;
grant MAINTAIN on table public.treasure_pics to service_role;
grant REFERENCES on table public.treasure_pics to service_role;
grant SELECT on table public.treasure_pics to service_role;
grant TRIGGER on table public.treasure_pics to service_role;
grant TRUNCATE on table public.treasure_pics to service_role;
grant UPDATE on table public.treasure_pics to service_role;
revoke all on table public.wallet_orders from public, anon, authenticated, service_role;
grant DELETE on table public.wallet_orders to anon;
grant INSERT on table public.wallet_orders to anon;
grant MAINTAIN on table public.wallet_orders to anon;
grant REFERENCES on table public.wallet_orders to anon;
grant SELECT on table public.wallet_orders to anon;
grant TRIGGER on table public.wallet_orders to anon;
grant TRUNCATE on table public.wallet_orders to anon;
grant UPDATE on table public.wallet_orders to anon;
grant DELETE on table public.wallet_orders to authenticated;
grant INSERT on table public.wallet_orders to authenticated;
grant MAINTAIN on table public.wallet_orders to authenticated;
grant REFERENCES on table public.wallet_orders to authenticated;
grant SELECT on table public.wallet_orders to authenticated;
grant TRIGGER on table public.wallet_orders to authenticated;
grant TRUNCATE on table public.wallet_orders to authenticated;
grant UPDATE on table public.wallet_orders to authenticated;
grant DELETE on table public.wallet_orders to service_role;
grant INSERT on table public.wallet_orders to service_role;
grant MAINTAIN on table public.wallet_orders to service_role;
grant REFERENCES on table public.wallet_orders to service_role;
grant SELECT on table public.wallet_orders to service_role;
grant TRIGGER on table public.wallet_orders to service_role;
grant TRUNCATE on table public.wallet_orders to service_role;
grant UPDATE on table public.wallet_orders to service_role;
revoke all on table tp_dev.accounts from public, anon, authenticated, service_role;
revoke all on table tp_dev.demo_balances from public, anon, authenticated, service_role;
revoke all on table tp_dev.demo_transactions from public, anon, authenticated, service_role;
revoke all on table tp_dev.pin_attempts from public, anon, authenticated, service_role;
revoke all on table tp_dev.requests from public, anon, authenticated, service_role;
revoke all on function _expire_topup_orders() from public, anon, authenticated, service_role;
revoke all on function _rl_locked(text) from public, anon, authenticated, service_role;
grant EXECUTE on function _rl_locked(text) to service_role;
revoke all on function _rl_record_fail(text) from public, anon, authenticated, service_role;
grant EXECUTE on function _rl_record_fail(text) to service_role;
revoke all on function _rl_reset(text) from public, anon, authenticated, service_role;
grant EXECUTE on function _rl_reset(text) to service_role;
revoke all on function _test_noop() from public, anon, authenticated, service_role;
revoke all on function active_offers(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function active_offers(uuid) to public;
grant EXECUTE on function active_offers(uuid) to anon;
grant EXECUTE on function active_offers(uuid) to authenticated;
grant EXECUTE on function active_offers(uuid) to service_role;
revoke all on function admin_add_category(text,uuid,text,text,text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_add_category(text,uuid,text,text,text,text) to public;
grant EXECUTE on function admin_add_category(text,uuid,text,text,text,text) to anon;
grant EXECUTE on function admin_add_category(text,uuid,text,text,text,text) to authenticated;
grant EXECUTE on function admin_add_category(text,uuid,text,text,text,text) to service_role;
revoke all on function admin_approve_merchant_photo(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_approve_merchant_photo(uuid) to public;
grant EXECUTE on function admin_approve_merchant_photo(uuid) to anon;
grant EXECUTE on function admin_approve_merchant_photo(uuid) to authenticated;
grant EXECUTE on function admin_approve_merchant_photo(uuid) to service_role;
revoke all on function admin_delete_customer(text,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_delete_customer(text,uuid) to public;
grant EXECUTE on function admin_delete_customer(text,uuid) to anon;
grant EXECUTE on function admin_delete_customer(text,uuid) to authenticated;
grant EXECUTE on function admin_delete_customer(text,uuid) to service_role;
revoke all on function admin_delete_merchant(uuid,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_delete_merchant(uuid,uuid) to public;
grant EXECUTE on function admin_delete_merchant(uuid,uuid) to anon;
grant EXECUTE on function admin_delete_merchant(uuid,uuid) to authenticated;
grant EXECUTE on function admin_delete_merchant(uuid,uuid) to service_role;
revoke all on function admin_delete_offer(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_delete_offer(uuid) to public;
grant EXECUTE on function admin_delete_offer(uuid) to anon;
grant EXECUTE on function admin_delete_offer(uuid) to authenticated;
grant EXECUTE on function admin_delete_offer(uuid) to service_role;
revoke all on function admin_delete_topup_order_only(uuid) from public, anon, authenticated, service_role;
revoke all on function admin_force_delete_customer(text,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_force_delete_customer(text,uuid) to public;
grant EXECUTE on function admin_force_delete_customer(text,uuid) to anon;
grant EXECUTE on function admin_force_delete_customer(text,uuid) to authenticated;
grant EXECUTE on function admin_force_delete_customer(text,uuid) to service_role;
revoke all on function admin_force_delete_merchant(uuid,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_force_delete_merchant(uuid,uuid) to public;
grant EXECUTE on function admin_force_delete_merchant(uuid,uuid) to anon;
grant EXECUTE on function admin_force_delete_merchant(uuid,uuid) to authenticated;
grant EXECUTE on function admin_force_delete_merchant(uuid,uuid) to service_role;
revoke all on function admin_grant_customer_gift(text,numeric,integer) from public, anon, authenticated, service_role;
revoke all on function admin_list_all_offers() from public, anon, authenticated, service_role;
grant EXECUTE on function admin_list_all_offers() to public;
grant EXECUTE on function admin_list_all_offers() to anon;
grant EXECUTE on function admin_list_all_offers() to authenticated;
grant EXECUTE on function admin_list_all_offers() to service_role;
revoke all on function admin_list_customers() from public, anon, authenticated, service_role;
grant EXECUTE on function admin_list_customers() to public;
grant EXECUTE on function admin_list_customers() to anon;
grant EXECUTE on function admin_list_customers() to authenticated;
grant EXECUTE on function admin_list_customers() to service_role;
revoke all on function admin_list_merchants() from public, anon, authenticated, service_role;
grant EXECUTE on function admin_list_merchants() to public;
grant EXECUTE on function admin_list_merchants() to anon;
grant EXECUTE on function admin_list_merchants() to authenticated;
grant EXECUTE on function admin_list_merchants() to service_role;
revoke all on function admin_mark_order_collected(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_mark_order_collected(uuid) to public;
grant EXECUTE on function admin_mark_order_collected(uuid) to anon;
grant EXECUTE on function admin_mark_order_collected(uuid) to authenticated;
grant EXECUTE on function admin_mark_order_collected(uuid) to service_role;
revoke all on function admin_reject_merchant_photo(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_reject_merchant_photo(uuid) to public;
grant EXECUTE on function admin_reject_merchant_photo(uuid) to anon;
grant EXECUTE on function admin_reject_merchant_photo(uuid) to authenticated;
grant EXECUTE on function admin_reject_merchant_photo(uuid) to service_role;
revoke all on function admin_reset_merchant_pin(uuid,text,uuid,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_reset_merchant_pin(uuid,text,uuid,text) to anon;
grant EXECUTE on function admin_reset_merchant_pin(uuid,text,uuid,text) to authenticated;
grant EXECUTE on function admin_reset_merchant_pin(uuid,text,uuid,text) to service_role;
revoke all on function admin_resolve_topup_order(uuid,boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_resolve_topup_order(uuid,boolean) to public;
grant EXECUTE on function admin_resolve_topup_order(uuid,boolean) to anon;
grant EXECUTE on function admin_resolve_topup_order(uuid,boolean) to authenticated;
grant EXECUTE on function admin_resolve_topup_order(uuid,boolean) to service_role;
revoke all on function admin_review_info_change(uuid,boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_review_info_change(uuid,boolean) to public;
grant EXECUTE on function admin_review_info_change(uuid,boolean) to anon;
grant EXECUTE on function admin_review_info_change(uuid,boolean) to authenticated;
grant EXECUTE on function admin_review_info_change(uuid,boolean) to service_role;
revoke all on function admin_set_category_active(uuid,boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_set_category_active(uuid,boolean) to public;
grant EXECUTE on function admin_set_category_active(uuid,boolean) to anon;
grant EXECUTE on function admin_set_category_active(uuid,boolean) to authenticated;
grant EXECUTE on function admin_set_category_active(uuid,boolean) to service_role;
revoke all on function admin_set_customer_status(text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_set_customer_status(text,text) to public;
grant EXECUTE on function admin_set_customer_status(text,text) to anon;
grant EXECUTE on function admin_set_customer_status(text,text) to authenticated;
grant EXECUTE on function admin_set_customer_status(text,text) to service_role;
revoke all on function admin_set_merchant_category(uuid,text,text[]) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_set_merchant_category(uuid,text,text[]) to public;
grant EXECUTE on function admin_set_merchant_category(uuid,text,text[]) to anon;
grant EXECUTE on function admin_set_merchant_category(uuid,text,text[]) to authenticated;
grant EXECUTE on function admin_set_merchant_category(uuid,text,text[]) to service_role;
revoke all on function admin_set_merchant_photo(uuid,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_set_merchant_photo(uuid,text) to public;
grant EXECUTE on function admin_set_merchant_photo(uuid,text) to anon;
grant EXECUTE on function admin_set_merchant_photo(uuid,text) to authenticated;
grant EXECUTE on function admin_set_merchant_photo(uuid,text) to service_role;
revoke all on function admin_set_merchant_status(uuid,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_set_merchant_status(uuid,text) to public;
grant EXECUTE on function admin_set_merchant_status(uuid,text) to anon;
grant EXECUTE on function admin_set_merchant_status(uuid,text) to authenticated;
grant EXECUTE on function admin_set_merchant_status(uuid,text) to service_role;
revoke all on function admin_topup_merchant(uuid,numeric,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_topup_merchant(uuid,numeric,text) to public;
grant EXECUTE on function admin_topup_merchant(uuid,numeric,text) to anon;
grant EXECUTE on function admin_topup_merchant(uuid,numeric,text) to authenticated;
grant EXECUTE on function admin_topup_merchant(uuid,numeric,text) to service_role;
revoke all on function admin_topup_orders() from public, anon, authenticated, service_role;
grant EXECUTE on function admin_topup_orders() to public;
grant EXECUTE on function admin_topup_orders() to anon;
grant EXECUTE on function admin_topup_orders() to authenticated;
grant EXECUTE on function admin_topup_orders() to service_role;
revoke all on function admin_update_category(uuid,text,text,text,text,integer,uuid,boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_update_category(uuid,text,text,text,text,integer,uuid,boolean) to public;
grant EXECUTE on function admin_update_category(uuid,text,text,text,text,integer,uuid,boolean) to anon;
grant EXECUTE on function admin_update_category(uuid,text,text,text,text,integer,uuid,boolean) to authenticated;
grant EXECUTE on function admin_update_category(uuid,text,text,text,text,integer,uuid,boolean) to service_role;
revoke all on function admin_update_merchant_location(uuid,numeric,numeric,numeric,numeric,text) from public, anon, authenticated, service_role;
revoke all on function admin_update_merchant_location(uuid,numeric,numeric,numeric,numeric,text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_update_merchant_location(uuid,numeric,numeric,numeric,numeric,text,text) to public;
grant EXECUTE on function admin_update_merchant_location(uuid,numeric,numeric,numeric,numeric,text,text) to anon;
grant EXECUTE on function admin_update_merchant_location(uuid,numeric,numeric,numeric,numeric,text,text) to authenticated;
grant EXECUTE on function admin_update_merchant_location(uuid,numeric,numeric,numeric,numeric,text,text) to service_role;
revoke all on function admin_update_offer_image(uuid,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_update_offer_image(uuid,text) to public;
grant EXECUTE on function admin_update_offer_image(uuid,text) to anon;
grant EXECUTE on function admin_update_offer_image(uuid,text) to authenticated;
grant EXECUTE on function admin_update_offer_image(uuid,text) to service_role;
revoke all on function admin_update_text_settings(uuid,jsonb) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_update_text_settings(uuid,jsonb) to public;
grant EXECUTE on function admin_update_text_settings(uuid,jsonb) to anon;
grant EXECUTE on function admin_update_text_settings(uuid,jsonb) to authenticated;
grant EXECUTE on function admin_update_text_settings(uuid,jsonb) to service_role;
revoke all on function admin_verify_pin(text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_verify_pin(text,text) to public;
grant EXECUTE on function admin_verify_pin(text,text) to anon;
grant EXECUTE on function admin_verify_pin(text,text) to authenticated;
grant EXECUTE on function admin_verify_pin(text,text) to service_role;
revoke all on function admin_warn_merchant(uuid,integer) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_warn_merchant(uuid,integer) to public;
grant EXECUTE on function admin_warn_merchant(uuid,integer) to anon;
grant EXECUTE on function admin_warn_merchant(uuid,integer) to authenticated;
grant EXECUTE on function admin_warn_merchant(uuid,integer) to service_role;
revoke all on function admin_wipe_all_data(uuid,text) from public, anon, authenticated, service_role;
grant EXECUTE on function admin_wipe_all_data(uuid,text) to public;
grant EXECUTE on function admin_wipe_all_data(uuid,text) to anon;
grant EXECUTE on function admin_wipe_all_data(uuid,text) to authenticated;
grant EXECUTE on function admin_wipe_all_data(uuid,text) to service_role;
revoke all on function create_transaction(uuid,text,numeric,boolean,uuid,jsonb) from public, anon, authenticated, service_role;
grant EXECUTE on function create_transaction(uuid,text,numeric,boolean,uuid,jsonb) to public;
grant EXECUTE on function create_transaction(uuid,text,numeric,boolean,uuid,jsonb) to anon;
grant EXECUTE on function create_transaction(uuid,text,numeric,boolean,uuid,jsonb) to authenticated;
grant EXECUTE on function create_transaction(uuid,text,numeric,boolean,uuid,jsonb) to service_role;
revoke all on function customer_check_phone(text) from public, anon, authenticated, service_role;
grant EXECUTE on function customer_check_phone(text) to public;
grant EXECUTE on function customer_check_phone(text) to anon;
grant EXECUTE on function customer_check_phone(text) to authenticated;
grant EXECUTE on function customer_check_phone(text) to service_role;
revoke all on function customer_check_welcome_expiry(text) from public, anon, authenticated, service_role;
revoke all on function customer_create_request(uuid,text,numeric,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function customer_create_request(uuid,text,numeric,uuid) to public;
grant EXECUTE on function customer_create_request(uuid,text,numeric,uuid) to anon;
grant EXECUTE on function customer_create_request(uuid,text,numeric,uuid) to authenticated;
grant EXECUTE on function customer_create_request(uuid,text,numeric,uuid) to service_role;
revoke all on function customer_notes_list(text) from public, anon, authenticated, service_role;
grant EXECUTE on function customer_notes_list(text) to public;
grant EXECUTE on function customer_notes_list(text) to anon;
grant EXECUTE on function customer_notes_list(text) to authenticated;
grant EXECUTE on function customer_notes_list(text) to service_role;
revoke all on function customer_notes_mark_read(text) from public, anon, authenticated, service_role;
revoke all on function customer_profile(text) from public, anon, authenticated, service_role;
grant EXECUTE on function customer_profile(text) to public;
grant EXECUTE on function customer_profile(text) to anon;
grant EXECUTE on function customer_profile(text) to authenticated;
grant EXECUTE on function customer_profile(text) to service_role;
revoke all on function customer_register(text,text,text) from public, anon, authenticated, service_role;
revoke all on function customer_register(text,text,text,numeric,integer) from public, anon, authenticated, service_role;
revoke all on function customer_register(text,text,text,numeric,integer,text) from public, anon, authenticated, service_role;
grant EXECUTE on function customer_register(text,text,text,numeric,integer,text) to public;
grant EXECUTE on function customer_register(text,text,text,numeric,integer,text) to anon;
grant EXECUTE on function customer_register(text,text,text,numeric,integer,text) to authenticated;
grant EXECUTE on function customer_register(text,text,text,numeric,integer,text) to service_role;
revoke all on function customer_reset_pin(text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function customer_reset_pin(text,text) to public;
grant EXECUTE on function customer_reset_pin(text,text) to anon;
grant EXECUTE on function customer_reset_pin(text,text) to authenticated;
grant EXECUTE on function customer_reset_pin(text,text) to service_role;
revoke all on function customer_set_pin(text,text,text) from public, anon, authenticated, service_role;
revoke all on function customer_transactions(text) from public, anon, authenticated, service_role;
grant EXECUTE on function customer_transactions(text) to public;
grant EXECUTE on function customer_transactions(text) to anon;
grant EXECUTE on function customer_transactions(text) to authenticated;
grant EXECUTE on function customer_transactions(text) to service_role;
revoke all on function customer_verify_pin(text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function customer_verify_pin(text,text) to public;
grant EXECUTE on function customer_verify_pin(text,text) to anon;
grant EXECUTE on function customer_verify_pin(text,text) to authenticated;
grant EXECUTE on function customer_verify_pin(text,text) to service_role;
revoke all on function decide_transaction(uuid,boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function decide_transaction(uuid,boolean) to public;
grant EXECUTE on function decide_transaction(uuid,boolean) to anon;
grant EXECUTE on function decide_transaction(uuid,boolean) to authenticated;
grant EXECUTE on function decide_transaction(uuid,boolean) to service_role;
revoke all on function get_app_text_settings() from public, anon, authenticated, service_role;
grant EXECUTE on function get_app_text_settings() to public;
grant EXECUTE on function get_app_text_settings() to anon;
grant EXECUTE on function get_app_text_settings() to authenticated;
grant EXECUTE on function get_app_text_settings() to service_role;
revoke all on function get_categories(boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function get_categories(boolean) to public;
grant EXECUTE on function get_categories(boolean) to anon;
grant EXECUTE on function get_categories(boolean) to authenticated;
grant EXECUTE on function get_categories(boolean) to service_role;
revoke all on function list_active_offers_all() from public, anon, authenticated, service_role;
grant EXECUTE on function list_active_offers_all() to public;
grant EXECUTE on function list_active_offers_all() to anon;
grant EXECUTE on function list_active_offers_all() to authenticated;
grant EXECUTE on function list_active_offers_all() to service_role;
revoke all on function list_merchants() from public, anon, authenticated, service_role;
grant EXECUTE on function list_merchants() to public;
grant EXECUTE on function list_merchants() to anon;
grant EXECUTE on function list_merchants() to authenticated;
grant EXECUTE on function list_merchants() to service_role;
revoke all on function merchant_add_offer(uuid,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,integer,boolean) from public, anon, authenticated, service_role;
revoke all on function merchant_add_offer(uuid,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,integer,boolean,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_add_offer(uuid,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,integer,boolean,text) to public;
grant EXECUTE on function merchant_add_offer(uuid,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,integer,boolean,text) to anon;
grant EXECUTE on function merchant_add_offer(uuid,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,integer,boolean,text) to authenticated;
grant EXECUTE on function merchant_add_offer(uuid,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,integer,boolean,text) to service_role;
revoke all on function merchant_check_phone(text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_check_phone(text) to public;
grant EXECUTE on function merchant_check_phone(text) to anon;
grant EXECUTE on function merchant_check_phone(text) to authenticated;
grant EXECUTE on function merchant_check_phone(text) to service_role;
revoke all on function merchant_close_request(uuid,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_close_request(uuid,uuid) to public;
grant EXECUTE on function merchant_close_request(uuid,uuid) to anon;
grant EXECUTE on function merchant_close_request(uuid,uuid) to authenticated;
grant EXECUTE on function merchant_close_request(uuid,uuid) to service_role;
revoke all on function merchant_create_topup_order(uuid,numeric,numeric,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_create_topup_order(uuid,numeric,numeric,text) to public;
grant EXECUTE on function merchant_create_topup_order(uuid,numeric,numeric,text) to anon;
grant EXECUTE on function merchant_create_topup_order(uuid,numeric,numeric,text) to authenticated;
grant EXECUTE on function merchant_create_topup_order(uuid,numeric,numeric,text) to service_role;
revoke all on function merchant_delete_offer(uuid,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_delete_offer(uuid,uuid) to public;
grant EXECUTE on function merchant_delete_offer(uuid,uuid) to anon;
grant EXECUTE on function merchant_delete_offer(uuid,uuid) to authenticated;
grant EXECUTE on function merchant_delete_offer(uuid,uuid) to service_role;
revoke all on function merchant_gallery_add(uuid,text,numeric,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_gallery_add(uuid,text,numeric,text) to public;
grant EXECUTE on function merchant_gallery_add(uuid,text,numeric,text) to anon;
grant EXECUTE on function merchant_gallery_add(uuid,text,numeric,text) to authenticated;
grant EXECUTE on function merchant_gallery_add(uuid,text,numeric,text) to service_role;
revoke all on function merchant_gallery_delete(uuid,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_gallery_delete(uuid,uuid) to public;
grant EXECUTE on function merchant_gallery_delete(uuid,uuid) to anon;
grant EXECUTE on function merchant_gallery_delete(uuid,uuid) to authenticated;
grant EXECUTE on function merchant_gallery_delete(uuid,uuid) to service_role;
revoke all on function merchant_gallery_list(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_gallery_list(uuid) to public;
grant EXECUTE on function merchant_gallery_list(uuid) to anon;
grant EXECUTE on function merchant_gallery_list(uuid) to authenticated;
grant EXECUTE on function merchant_gallery_list(uuid) to service_role;
revoke all on function merchant_notes_list(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_notes_list(uuid) to public;
grant EXECUTE on function merchant_notes_list(uuid) to anon;
grant EXECUTE on function merchant_notes_list(uuid) to authenticated;
grant EXECUTE on function merchant_notes_list(uuid) to service_role;
revoke all on function merchant_notes_mark_read(uuid) from public, anon, authenticated, service_role;
revoke all on function merchant_offers(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_offers(uuid) to public;
grant EXECUTE on function merchant_offers(uuid) to anon;
grant EXECUTE on function merchant_offers(uuid) to authenticated;
grant EXECUTE on function merchant_offers(uuid) to service_role;
revoke all on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text) from public, anon, authenticated, service_role;
revoke all on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric) from public, anon, authenticated, service_role;
revoke all on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,text[]) from public, anon, authenticated, service_role;
revoke all on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,text[],text) from public, anon, authenticated, service_role;
revoke all on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,text[],text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,text[],text,text) to public;
grant EXECUTE on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,text[],text,text) to anon;
grant EXECUTE on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,text[],text,text) to authenticated;
grant EXECUTE on function merchant_register(text,text,text,text,numeric,text,numeric,numeric,numeric,numeric,text,numeric,text[],text,text) to service_role;
revoke all on function merchant_request_info_change(uuid,text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_request_info_change(uuid,text,text) to public;
grant EXECUTE on function merchant_request_info_change(uuid,text,text) to anon;
grant EXECUTE on function merchant_request_info_change(uuid,text,text) to authenticated;
grant EXECUTE on function merchant_request_info_change(uuid,text,text) to service_role;
revoke all on function merchant_request_manual_topup(uuid,numeric,numeric,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_request_manual_topup(uuid,numeric,numeric,text) to public;
grant EXECUTE on function merchant_request_manual_topup(uuid,numeric,numeric,text) to anon;
grant EXECUTE on function merchant_request_manual_topup(uuid,numeric,numeric,text) to authenticated;
grant EXECUTE on function merchant_request_manual_topup(uuid,numeric,numeric,text) to service_role;
revoke all on function merchant_requests(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_requests(uuid) to public;
grant EXECUTE on function merchant_requests(uuid) to anon;
grant EXECUTE on function merchant_requests(uuid) to authenticated;
grant EXECUTE on function merchant_requests(uuid) to service_role;
revoke all on function merchant_reset_pin(text,text) from public, anon, authenticated, service_role;
revoke all on function merchant_set_logo(text,text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_set_logo(text,text,text) to anon;
grant EXECUTE on function merchant_set_logo(text,text,text) to authenticated;
grant EXECUTE on function merchant_set_logo(text,text,text) to service_role;
revoke all on function merchant_set_offer_active(uuid,uuid,boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_set_offer_active(uuid,uuid,boolean) to public;
grant EXECUTE on function merchant_set_offer_active(uuid,uuid,boolean) to anon;
grant EXECUTE on function merchant_set_offer_active(uuid,uuid,boolean) to authenticated;
grant EXECUTE on function merchant_set_offer_active(uuid,uuid,boolean) to service_role;
revoke all on function merchant_set_redeem_pct(uuid,numeric,numeric) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_set_redeem_pct(uuid,numeric,numeric) to public;
grant EXECUTE on function merchant_set_redeem_pct(uuid,numeric,numeric) to anon;
grant EXECUTE on function merchant_set_redeem_pct(uuid,numeric,numeric) to authenticated;
grant EXECUTE on function merchant_set_redeem_pct(uuid,numeric,numeric) to service_role;
revoke all on function merchant_submit_photo(uuid,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_submit_photo(uuid,text) to public;
grant EXECUTE on function merchant_submit_photo(uuid,text) to anon;
grant EXECUTE on function merchant_submit_photo(uuid,text) to authenticated;
grant EXECUTE on function merchant_submit_photo(uuid,text) to service_role;
revoke all on function merchant_topup_orders(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_topup_orders(uuid) to public;
grant EXECUTE on function merchant_topup_orders(uuid) to anon;
grant EXECUTE on function merchant_topup_orders(uuid) to authenticated;
grant EXECUTE on function merchant_topup_orders(uuid) to service_role;
revoke all on function merchant_transactions(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_transactions(uuid) to public;
grant EXECUTE on function merchant_transactions(uuid) to anon;
grant EXECUTE on function merchant_transactions(uuid) to authenticated;
grant EXECUTE on function merchant_transactions(uuid) to service_role;
revoke all on function merchant_update_page(uuid,text,boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_update_page(uuid,text,boolean) to public;
grant EXECUTE on function merchant_update_page(uuid,text,boolean) to anon;
grant EXECUTE on function merchant_update_page(uuid,text,boolean) to authenticated;
grant EXECUTE on function merchant_update_page(uuid,text,boolean) to service_role;
revoke all on function merchant_verify_pin(text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_verify_pin(text,text) to public;
grant EXECUTE on function merchant_verify_pin(text,text) to anon;
grant EXECUTE on function merchant_verify_pin(text,text) to authenticated;
grant EXECUTE on function merchant_verify_pin(text,text) to service_role;
revoke all on function merchant_wallet(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function merchant_wallet(uuid) to public;
grant EXECUTE on function merchant_wallet(uuid) to anon;
grant EXECUTE on function merchant_wallet(uuid) to authenticated;
grant EXECUTE on function merchant_wallet(uuid) to service_role;
revoke all on function store_gallery(uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function store_gallery(uuid) to public;
grant EXECUTE on function store_gallery(uuid) to anon;
grant EXECUTE on function store_gallery(uuid) to authenticated;
grant EXECUTE on function store_gallery(uuid) to service_role;
revoke all on function tp_dev_change_pin(text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function tp_dev_change_pin(text,text) to authenticated;
grant EXECUTE on function tp_dev_change_pin(text,text) to service_role;
revoke all on function tp_dev_confirm_transaction(uuid,boolean) from public, anon, authenticated, service_role;
grant EXECUTE on function tp_dev_confirm_transaction(uuid,boolean) to authenticated;
grant EXECUTE on function tp_dev_confirm_transaction(uuid,boolean) to service_role;
revoke all on function tp_dev_create_request(text,numeric,uuid) from public, anon, authenticated, service_role;
grant EXECUTE on function tp_dev_create_request(text,numeric,uuid) to authenticated;
grant EXECUTE on function tp_dev_create_request(text,numeric,uuid) to service_role;
revoke all on function tp_dev_register(text,text) from public, anon, authenticated, service_role;
grant EXECUTE on function tp_dev_register(text,text) to authenticated;
grant EXECUTE on function tp_dev_register(text,text) to service_role;
revoke all on function whish_confirm_payment(uuid,text,numeric,bigint) from public, anon, authenticated, service_role;
revoke all on function whish_set_collect_url(uuid,text,bigint) from public, anon, authenticated, service_role;
grant USAGE on schema public to public;
grant USAGE on schema public to anon;
grant USAGE on schema public to authenticated;
grant USAGE on schema public to service_role;
alter default privileges for role postgres in schema public grant SELECT on sequences to anon;
alter default privileges for role postgres in schema public grant UPDATE on sequences to anon;
alter default privileges for role postgres in schema public grant USAGE on sequences to anon;
alter default privileges for role postgres in schema public grant SELECT on sequences to authenticated;
alter default privileges for role postgres in schema public grant UPDATE on sequences to authenticated;
alter default privileges for role postgres in schema public grant USAGE on sequences to authenticated;
alter default privileges for role postgres in schema public grant SELECT on sequences to service_role;
alter default privileges for role postgres in schema public grant UPDATE on sequences to service_role;
alter default privileges for role postgres in schema public grant USAGE on sequences to service_role;
alter default privileges for role postgres in schema public grant EXECUTE on functions to anon;
alter default privileges for role postgres in schema public grant EXECUTE on functions to authenticated;
alter default privileges for role postgres in schema public grant EXECUTE on functions to service_role;
alter default privileges for role postgres in schema public grant DELETE on tables to anon;
alter default privileges for role postgres in schema public grant INSERT on tables to anon;
alter default privileges for role postgres in schema public grant MAINTAIN on tables to anon;
alter default privileges for role postgres in schema public grant REFERENCES on tables to anon;
alter default privileges for role postgres in schema public grant SELECT on tables to anon;
alter default privileges for role postgres in schema public grant TRIGGER on tables to anon;
alter default privileges for role postgres in schema public grant TRUNCATE on tables to anon;
alter default privileges for role postgres in schema public grant UPDATE on tables to anon;
alter default privileges for role postgres in schema public grant DELETE on tables to authenticated;
alter default privileges for role postgres in schema public grant INSERT on tables to authenticated;
alter default privileges for role postgres in schema public grant MAINTAIN on tables to authenticated;
alter default privileges for role postgres in schema public grant REFERENCES on tables to authenticated;
alter default privileges for role postgres in schema public grant SELECT on tables to authenticated;
alter default privileges for role postgres in schema public grant TRIGGER on tables to authenticated;
alter default privileges for role postgres in schema public grant TRUNCATE on tables to authenticated;
alter default privileges for role postgres in schema public grant UPDATE on tables to authenticated;
alter default privileges for role postgres in schema public grant DELETE on tables to service_role;
alter default privileges for role postgres in schema public grant INSERT on tables to service_role;
alter default privileges for role postgres in schema public grant MAINTAIN on tables to service_role;
alter default privileges for role postgres in schema public grant REFERENCES on tables to service_role;
alter default privileges for role postgres in schema public grant SELECT on tables to service_role;
alter default privileges for role postgres in schema public grant TRIGGER on tables to service_role;
alter default privileges for role postgres in schema public grant TRUNCATE on tables to service_role;
alter default privileges for role postgres in schema public grant UPDATE on tables to service_role;
alter default privileges for role supabase_admin in schema public grant SELECT on sequences to anon;
alter default privileges for role supabase_admin in schema public grant UPDATE on sequences to anon;
alter default privileges for role supabase_admin in schema public grant USAGE on sequences to anon;
alter default privileges for role supabase_admin in schema public grant SELECT on sequences to authenticated;
alter default privileges for role supabase_admin in schema public grant UPDATE on sequences to authenticated;
alter default privileges for role supabase_admin in schema public grant USAGE on sequences to authenticated;
alter default privileges for role supabase_admin in schema public grant SELECT on sequences to service_role;
alter default privileges for role supabase_admin in schema public grant UPDATE on sequences to service_role;
alter default privileges for role supabase_admin in schema public grant USAGE on sequences to service_role;
alter default privileges for role supabase_admin in schema public grant EXECUTE on functions to anon;
alter default privileges for role supabase_admin in schema public grant EXECUTE on functions to authenticated;
alter default privileges for role supabase_admin in schema public grant EXECUTE on functions to service_role;
alter default privileges for role supabase_admin in schema public grant DELETE on tables to anon;
alter default privileges for role supabase_admin in schema public grant INSERT on tables to anon;
alter default privileges for role supabase_admin in schema public grant MAINTAIN on tables to anon;
alter default privileges for role supabase_admin in schema public grant REFERENCES on tables to anon;
alter default privileges for role supabase_admin in schema public grant SELECT on tables to anon;
alter default privileges for role supabase_admin in schema public grant TRIGGER on tables to anon;
alter default privileges for role supabase_admin in schema public grant TRUNCATE on tables to anon;
alter default privileges for role supabase_admin in schema public grant UPDATE on tables to anon;
alter default privileges for role supabase_admin in schema public grant DELETE on tables to authenticated;
alter default privileges for role supabase_admin in schema public grant INSERT on tables to authenticated;
alter default privileges for role supabase_admin in schema public grant MAINTAIN on tables to authenticated;
alter default privileges for role supabase_admin in schema public grant REFERENCES on tables to authenticated;
alter default privileges for role supabase_admin in schema public grant SELECT on tables to authenticated;
alter default privileges for role supabase_admin in schema public grant TRIGGER on tables to authenticated;
alter default privileges for role supabase_admin in schema public grant TRUNCATE on tables to authenticated;
alter default privileges for role supabase_admin in schema public grant UPDATE on tables to authenticated;
alter default privileges for role supabase_admin in schema public grant DELETE on tables to service_role;
alter default privileges for role supabase_admin in schema public grant INSERT on tables to service_role;
alter default privileges for role supabase_admin in schema public grant MAINTAIN on tables to service_role;
alter default privileges for role supabase_admin in schema public grant REFERENCES on tables to service_role;
alter default privileges for role supabase_admin in schema public grant SELECT on tables to service_role;
alter default privileges for role supabase_admin in schema public grant TRIGGER on tables to service_role;
alter default privileges for role supabase_admin in schema public grant TRUNCATE on tables to service_role;
alter default privileges for role supabase_admin in schema public grant UPDATE on tables to service_role;
insert into public.app_settings select * from json_populate_recordset(null::public.app_settings, '[]') on conflict do nothing;
insert into public.app_text_settings select * from json_populate_recordset(null::public.app_text_settings, '[]') on conflict do nothing;
insert into public.categories select * from json_populate_recordset(null::public.categories, '[{"id":"7e570000-0000-4000-8000-000100000001","slug":"stg_food","name_ar":"مطاعم (تجريبي)","name_en":"Restaurants (test)","parent_id":null,"icon":"🍽️","color":"#1d63e0","image":null,"sort_order":1,"is_active":true,"created_at":"2026-11-02T22:41:05.319694+00:00","updated_at":"2026-11-02T22:41:05.319694+00:00"}, 
 {"id":"7e570000-0000-4000-8000-000100000002","slug":"stg_cafe","name_ar":"مقاهي (تجريبي)","name_en":"Cafes (test)","parent_id":null,"icon":"☕","color":"#1d63e0","image":null,"sort_order":2,"is_active":true,"created_at":"2026-11-02T22:41:05.319694+00:00","updated_at":"2026-11-02T22:41:05.319694+00:00"}, 
 {"id":"7e570000-0000-4000-8000-000100000003","slug":"stg_fashion","name_ar":"أزياء (تجريبي)","name_en":"Fashion (test)","parent_id":null,"icon":"👗","color":"#1d63e0","image":null,"sort_order":3,"is_active":true,"created_at":"2026-11-02T22:41:05.319694+00:00","updated_at":"2026-11-02T22:41:05.319694+00:00"}]') on conflict do nothing;
-- end of structure export
commit;
