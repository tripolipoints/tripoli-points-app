-- Local replica of the Tripoli Points public schema (from a read-only dump of Production, 2026-11-11), for testing only.
do $$ begin if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls; end if; end $$;
create schema extensions; create extension pgcrypto schema extensions;
grant usage on schema public, extensions to anon, authenticated, service_role;
-- Supabase default: new functions/tables in public are granted to the API roles
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
create table public.admin_users (id uuid default gen_random_uuid() not null, username text not null, pin_hash text not null, is_primary boolean default false, created_at timestamp with time zone default now());
create table public.app_settings (key text not null, value numeric not null);
create table public.app_text_settings (key text not null, value text);
create table public.auth_rate_limits (key text not null, fail_count integer default 0 not null, locked_until timestamp with time zone, updated_at timestamp with time zone default now() not null);
create table public.categories (id uuid default gen_random_uuid() not null, slug text not null, name_ar text not null, name_en text, parent_id uuid, icon text, color text, image text, sort_order integer default 0 not null, is_active boolean default true not null, created_at timestamp with time zone default now() not null, updated_at timestamp with time zone default now() not null);
create table public.customer_notes (id uuid default gen_random_uuid() not null, customer_phone text, type text, title text, body text, read boolean default false, created_at timestamp with time zone default now());
create table public.customer_requests (id uuid default gen_random_uuid() not null, merchant_id uuid, customer_phone text, invoice numeric not null, offer_id uuid, status text default 'open'::text not null, created_at timestamp with time zone default now() not null);
create table public.customer_unlocks (id uuid default gen_random_uuid() not null, customer_phone text, pic_id uuid, unlocked_at timestamp with time zone default now());
create table public.customers (phone text not null, pin_hash text, name text, last_name text, photo_url text, points bigint default 0, status text default 'active'::text, src text, created_at timestamp with time zone default now(), welcome_remain numeric default 0 not null, welcome_exp timestamp with time zone, terms_version text, terms_accepted_at timestamp with time zone);
create table public.merchant_gallery (id uuid default gen_random_uuid() not null, merchant_id uuid not null, name text not null, price numeric, img_url text not null, display_order integer default 0 not null, created_at timestamp with time zone default now() not null);
create table public.merchant_notes (id uuid default gen_random_uuid() not null, merchant_id uuid, type text, title text, body text, cta text, severity text default 'info'::text, read boolean default false, created_at timestamp with time zone default now());
create table public.merchant_vips (id uuid default gen_random_uuid() not null, merchant_id uuid, customer_phone text, created_at timestamp with time zone default now(), cap_points numeric default 0);
create table public.merchants (id uuid default gen_random_uuid() not null, name text not null, owner text, phone text not null, pin_hash text, cat text, pct numeric default 5, tier text default 'medium'::text, redeem_pct numeric, redeem_pct_vip numeric, x numeric, y numeric, lat numeric, lng numeric, addr text, photo_url text, photo_pending_url text, status text default 'pending'::text, poster_printed boolean default false, warns integer default 0, created_at timestamp with time zone default now(), pending_name text, pending_addr text, extra_cats text[] default '{}'::text[] not null, terms_version text, terms_accepted_at timestamp with time zone, page_blurb text, page_enabled boolean default false not null, area text, logo_url text);
create table public.offers (id uuid default gen_random_uuid() not null, merchant_id uuid, type text not null, badge text, val numeric, gift_text text, pts numeric, per numeric, img_url text, old_price numeric, new_price numeric, min_amount numeric default 0, days integer default 30, first_time_only boolean default false, active boolean default true, created_at timestamp with time zone default now(), deleted boolean default false, title text, specs text);
create table public.pos_transactions (id uuid default gen_random_uuid() not null, merchant_id uuid, customer_phone text, invoice numeric not null, redeem_pts bigint default 0, redeem_val numeric default 0, net numeric, earn bigint default 0, items jsonb default '[]'::jsonb, status text default 'PENDING'::text, created_at timestamp with time zone default now());
create table public.topup_orders (id uuid default gen_random_uuid() not null, merchant_id uuid not null, amount numeric not null, points numeric not null, pack_label text, ref text not null, status text default 'PENDING'::text not null, paid_amount numeric, whish_external_id bigint, whish_collect_url text, created_at timestamp with time zone default now() not null, paid_at timestamp with time zone, method text default 'whish'::text not null, collected boolean default false not null);
create table public.topups (id uuid default gen_random_uuid() not null, merchant_id uuid, amount numeric not null, source text, ref text, created_at timestamp with time zone default now());
create table public.treasure_pics (id uuid default gen_random_uuid() not null, name text not null, note text, img_url text, display_order integer default 0, created_at timestamp with time zone default now());
alter table admin_users add constraint admin_users_pkey PRIMARY KEY (id);
alter table admin_users add constraint admin_users_username_key UNIQUE (username);
alter table app_settings add constraint app_settings_pkey PRIMARY KEY (key);
alter table app_text_settings add constraint app_text_settings_pkey PRIMARY KEY (key);
alter table auth_rate_limits add constraint auth_rate_limits_pkey PRIMARY KEY (key);
alter table categories add constraint categories_pkey PRIMARY KEY (id);
alter table customer_notes add constraint customer_notes_pkey PRIMARY KEY (id);
alter table customer_requests add constraint customer_requests_pkey PRIMARY KEY (id);
alter table customer_unlocks add constraint customer_unlocks_customer_phone_pic_id_key UNIQUE (customer_phone, pic_id);
alter table customer_unlocks add constraint customer_unlocks_pkey PRIMARY KEY (id);
alter table customers add constraint customers_pkey PRIMARY KEY (phone);
alter table customers add constraint customers_status_check CHECK ((status = ANY (ARRAY['active'::text, 'frozen'::text])));
alter table merchant_gallery add constraint merchant_gallery_pkey PRIMARY KEY (id);
alter table merchant_notes add constraint merchant_notes_pkey PRIMARY KEY (id);
alter table merchant_vips add constraint merchant_vips_merchant_id_customer_phone_key UNIQUE (merchant_id, customer_phone);
alter table merchant_vips add constraint merchant_vips_pkey PRIMARY KEY (id);
alter table merchants add constraint merchants_phone_key UNIQUE (phone);
alter table merchants add constraint merchants_pkey PRIMARY KEY (id);
alter table merchants add constraint merchants_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'frozen'::text, 'excluded'::text, 'rejected'::text])));
alter table merchants add constraint merchants_tier_check CHECK ((tier = ANY (ARRAY['large'::text, 'medium'::text, 'small'::text])));
alter table offers add constraint offers_pkey PRIMARY KEY (id);
alter table offers add constraint offers_type_check CHECK ((type = ANY (ARRAY['discount'::text, 'gift'::text, 'product'::text, 'bonus'::text])));
alter table pos_transactions add constraint pos_transactions_pkey PRIMARY KEY (id);
alter table pos_transactions add constraint pos_transactions_status_check CHECK ((status = ANY (ARRAY['PENDING'::text, 'CONFIRMED'::text, 'CANCELLED'::text, 'EXPIRED'::text, 'REVIEW'::text])));
alter table topup_orders add constraint topup_orders_pkey PRIMARY KEY (id);
alter table topups add constraint topups_pkey PRIMARY KEY (id);
alter table treasure_pics add constraint treasure_pics_pkey PRIMARY KEY (id);
alter table customer_notes add constraint customer_notes_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone) ON DELETE CASCADE;
alter table customer_requests add constraint customer_requests_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone);
alter table customer_requests add constraint customer_requests_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table customer_unlocks add constraint customer_unlocks_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone) ON DELETE CASCADE;
alter table customer_unlocks add constraint customer_unlocks_pic_id_fkey FOREIGN KEY (pic_id) REFERENCES treasure_pics(id) ON DELETE CASCADE;
alter table merchant_gallery add constraint merchant_gallery_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table merchant_notes add constraint merchant_notes_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE;
alter table merchant_vips add constraint merchant_vips_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone) ON DELETE CASCADE;
alter table merchant_vips add constraint merchant_vips_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE;
alter table offers add constraint offers_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id) ON DELETE CASCADE;
alter table pos_transactions add constraint pos_transactions_customer_phone_fkey FOREIGN KEY (customer_phone) REFERENCES customers(phone);
alter table pos_transactions add constraint pos_transactions_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table topup_orders add constraint topup_orders_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
alter table topups add constraint topups_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchants(id);
do $$ declare t text; begin for t in select tablename from pg_tables where schemaname='public' loop execute format('alter table public.%I enable row level security', t); end loop; end $$;
insert into app_settings values ('redeem_cap_pct',70),('rate_pts_per_usd',100);

-- Production functions the new code calls or replaces (copied verbatim from the read-only dump)
CREATE OR REPLACE FUNCTION public._rl_locked(p_key text) RETURNS boolean LANGUAGE sql STABLE SET search_path TO 'public' AS $function$
  select exists(select 1 from public.auth_rate_limits where key = p_key and locked_until is not null and locked_until > now());
$function$;
CREATE OR REPLACE FUNCTION public._rl_record_fail(p_key text) RETURNS void LANGUAGE plpgsql SET search_path TO 'public' AS $function$
declare n integer;
begin
  insert into public.auth_rate_limits(key, fail_count, updated_at) values (p_key, 1, now())
  on conflict (key) do update set
    fail_count = case when public.auth_rate_limits.locked_until is not null and public.auth_rate_limits.locked_until > now()
      then public.auth_rate_limits.fail_count else public.auth_rate_limits.fail_count + 1 end,
    updated_at = now()
  returning fail_count into n;
  if n >= 5 then update public.auth_rate_limits set locked_until = now() + interval '15 minutes' where key = p_key; end if;
end; $function$;
CREATE OR REPLACE FUNCTION public._rl_reset(p_key text) RETURNS void LANGUAGE sql SET search_path TO 'public' AS $function$
  delete from public.auth_rate_limits where key = p_key;
$function$;
revoke execute on function public._rl_locked(text), public._rl_record_fail(text), public._rl_reset(text) from public, anon, authenticated;
CREATE OR REPLACE FUNCTION public.merchant_wallet(p_merchant_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare topped numeric; cred numeric; used numeric; res numeric;
begin
  select coalesce(sum(amount),0) into topped from public.topups where merchant_id = p_merchant_id;
  select coalesce(sum(redeem_val),0) into cred from public.pos_transactions where merchant_id = p_merchant_id and status='CONFIRMED';
  select coalesce(sum(earn)/100.0,0) into used from public.pos_transactions where merchant_id = p_merchant_id and status='CONFIRMED';
  select coalesce(sum(earn)/100.0,0) into res from public.pos_transactions where merchant_id = p_merchant_id and status='PENDING';
  return jsonb_build_object('topped', topped, 'cred', cred, 'used', used, 'reserved', res, 'balance', topped+cred-used, 'avail', topped+cred-used-res);
end; $function$;
CREATE OR REPLACE FUNCTION public.customer_check_welcome_expiry(p_phone text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare r public.customers; lost numeric;
begin
  select * into r from public.customers where phone = p_phone for update;
  if r is null then return; end if;
  if r.welcome_remain > 0 and r.welcome_exp is not null and now() > r.welcome_exp then
    lost := least(r.welcome_remain, r.points);
    update public.customers set points = points - lost, welcome_remain = 0 where phone = p_phone;
    insert into public.customer_notes(customer_phone, type, title, body) values (p_phone, 'points',
      case when lost > 0 then format('انتهت صلاحية هدية الترحيب، سُحبت %s نقطة لم تُصرف', lost) else 'انتهت صلاحية هدية الترحيب' end,
      'تبقى معك فقط النقاط التي اكتسبتها من مشترياتك الفعلية.');
  end if;
end; $function$;
CREATE OR REPLACE FUNCTION public.create_transaction(p_merchant_id uuid, p_customer_phone text, p_invoice numeric, p_redeem boolean, p_offer_id uuid DEFAULT NULL::uuid, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
  if is_vip then cap := least(max_redeem, least(vip_cap, floor(base * rate)));
  else cap := least(max_redeem, floor(base * rate * coalesce(m.redeem_pct,5)/100), tier_max); end if;
  rp := case when p_redeem then cap else 0 end;
  rv := rp / rate;
  net := round(base - rv, 2);
  bonus := case when o.type = 'bonus' and o.per > 0 then floor(net / o.per) * o.pts else 0 end;
  earn := floor(net * m.pct / 100 * rate) + bonus;
  wallet_json := public.merchant_wallet(p_merchant_id);
  wallet_avail := (wallet_json->>'avail')::numeric;
  if earn / rate > wallet_avail then return jsonb_build_object('ok', false, 'error', 'INSUFFICIENT'); end if;
  insert into public.pos_transactions(merchant_id, customer_phone, invoice, redeem_pts, redeem_val, net, earn, items, status)
  values (p_merchant_id, p_customer_phone, p_invoice, rp, rv, net, earn, coalesce(p_items,'[]'::jsonb), 'PENDING') returning * into new_tx;
  insert into public.customer_notes(customer_phone, type, title, body) values (p_customer_phone, 'points', 'عملية بانتظار تأكيدك', m.name || ': $' || p_invoice);
  return jsonb_build_object('ok', true, 'tx_id', new_tx.id, 'invoice', p_invoice, 'disc', disc, 'redeem_pts', rp, 'redeem_val', rv, 'net', net, 'bonus', bonus, 'earn', earn);
end; $function$;
CREATE OR REPLACE FUNCTION public.decide_transaction(p_tx_id uuid, p_confirm boolean) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
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
end; $function$;
CREATE OR REPLACE FUNCTION public.merchant_set_redeem_pct(p_merchant_id uuid, p_redeem_pct numeric, p_redeem_pct_vip numeric DEFAULT NULL::numeric) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare r public.merchants;
begin
  update public.merchants set redeem_pct = p_redeem_pct,
    redeem_pct_vip = case when p_redeem_pct_vip is not null then p_redeem_pct_vip when redeem_pct_vip is not null and redeem_pct_vip < p_redeem_pct then p_redeem_pct else redeem_pct_vip end
  where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'redeem_pct', r.redeem_pct, 'redeem_pct_vip', r.redeem_pct_vip);
end; $function$;
CREATE OR REPLACE FUNCTION public.admin_delete_customer(p_phone text, p_admin_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare a public.admin_users; cnt int; ok boolean;
begin
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary,false);
  if ok then delete from public.customers where phone = p_phone; get diagnostics cnt = row_count; end if;
  return jsonb_build_object('ok', coalesce(ok and cnt>0, false), 'error', case when not ok then 'هذا الإجراء مسموح للأدمن الأساسي فقط' else null end);
exception when foreign_key_violation then
  return jsonb_build_object('ok', false, 'error', 'لا يمكن حذف هذا الزبون لوجود عمليات مسجّلة عليه. جمّده بدلاً من الحذف.');
end; $function$;
