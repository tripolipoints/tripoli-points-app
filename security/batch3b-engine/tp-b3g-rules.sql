-- =====================================================================================================
-- Tripoli Points — BATCH 3g: approved business rules from the 12-Nov-2026 register (STAGING ONLY)
--   §03  tier limits: small 1,000 pts / 20 % of the invoice, medium 2,500 / 50 %, large 10,000 / 100 %.
--        A shop may choose a LOWER % only with Admin approval (request → Admin review). The customer decides how many
--        points to use (optional amount on the purchase code); acceptance is mandatory within the limits.
--   §04  earning 1 %–10 % of the net paid; daily eligible purchases per customer per branch: small 10,000,
--        medium 25,000, large 50,000 reference points (= 100 / 250 / 500 at 100 pts per unit), set from the tier;
--        above the cap the purchase goes through but earns only on what is left; offer bonus counted inside the cap.
--        Same customer + branch + invoice value on two consecutive days → Admin alert only (never blocks).
--   §16  VIP: owner-only, chosen among customers with a completed points purchase at the branch; Admin sets the
--        maximum count per tier (no value is invented: until the Admin sets it, no NEW VIP can be added; existing
--        ones keep working); the VIP cap replaces the normal cap as a DAILY total at the branch, still inside the
--        % limit, the 70 % branch allowance and the customer balance; raise = immediate, lower = from the next day,
--        cancel = immediate, with notifications and a permanent change log; the customer sees his VIP caps.
-- Unresolved (kept provisional, not decided here): reward rounding (floor), legacy points validity.
-- Changes: 5 settings added (fill-missing only, recorded), 6 nullable / defaulted columns added, 1 new table,
--   7 functions replaced or text-patched (previous text saved in tp_backup.func_snapshots batch 'b3g_rules'),
--   new API functions. No drop / delete / truncate; no balance is changed.
-- Rollback: R_tp-b3g-rules-rollback.sql
-- =====================================================================================================
begin;

do $$ begin
  if to_regclass('public.point_batches') is null then raise exception 'batch 3b required'; end if;
  if exists (select 1 from tp_backup.func_snapshots where batch = 'b3g_rules') then raise exception 'already applied'; end if;
end $$;

-- ---------------------------------------------------------------- 0. backup of every function touched
do $$
declare r record; cur text;
begin
  for r in select * from (values
    ('_tx_quote(uuid,text,numeric,boolean,uuid)', '1ae511b5e7cdad152450665642a003f1'),
    ('merchant_quote_v2(text,uuid,numeric,boolean,uuid)', '570e4c832d626c4f643398f4a7e0ee6b'),
    ('merchant_create_tx_v2(text,uuid,numeric,boolean,uuid,jsonb,text)', '8d8a4d283211e7b74293b6adf0508d86'),
    ('customer_decide_tx_v2(text,uuid,boolean,text)', 'd0260de7344224f164107b5dcbf6b2ee'),
    ('merchant_set_redeem_pct_v2(text,numeric,numeric)', 'b99ddf2dc2ab6b89b18edd321eae801e'),
    ('admin_engine_setting_v2(text,text,numeric)', '1235861dd54307c904c70872aa2f07ab'),
    ('admin_catalog_v2(text)', 'd6e8e79d75f174487f9183aadb641a75')) v(sig, want) loop
    cur := (select md5(replace(prosrc, chr(13), '')) from pg_proc where oid = to_regprocedure('public.' || r.sig));
    if cur is distinct from r.want then raise exception '% differs (md5 %), stop', r.sig, cur; end if;
    insert into tp_backup.func_snapshots(batch, sig, def, src_md5)
    values ('b3g_rules', r.sig, pg_get_functiondef(to_regprocedure('public.' || r.sig)),
            (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)));
  end loop;
end $$;

-- ---------------------------------------------------------------- 1. settings (approved values, fill-missing only)
do $$
declare r record;
begin
  for r in select * from (values
    ('tier_redeem_pct_small', 20), ('tier_redeem_pct_medium', 50), ('tier_redeem_pct_large', 100),          -- §03
    ('daily_eligible_pts_small', 10000), ('daily_eligible_pts_medium', 25000), ('daily_eligible_pts_large', 50000), -- §04
    ('earn_pct_min', 1), ('earn_pct_max', 10)) v(k, val) loop                                                  -- §04
    if not exists (select 1 from public.app_settings where key = r.k) then
      execute 'insert ' || 'into public.app_settings(key, value) values ($1, $2)' using r.k, r.val;
      insert into tp_backup.settings_snapshots(batch, tbl, key, existed, old_value, inserted_value)
      values ('b3g_rules', 'app_settings', r.k, false, null, r.val::text) on conflict do nothing;
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------- 2. columns + VIP log
alter table public.merchants add column pending_redeem_pct numeric, add column pending_redeem_pct_vip numeric, add column pending_redeem_at timestamptz;
alter table public.purchase_codes add column redeem_want numeric check (redeem_want is null or redeem_want >= 0);
alter table public.merchant_vips add column status text not null default 'active' check (status in ('active','cancelled')),
  add column next_cap numeric check (next_cap is null or next_cap > 0), add column next_from date, add column updated_at timestamptz;

create table public.merchant_vip_log(
  id bigserial primary key,
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  customer_phone text not null references public.customers(phone) on delete cascade on update cascade,
  action text not null check (action in ('add','raise','lower','cancel','reactivate')),
  old_cap numeric, new_cap numeric, effective_from date not null,
  actor text, at timestamptz not null default now());
alter table public.merchant_vip_log enable row level security;
revoke all on table public.merchant_vip_log from public, anon, authenticated;
revoke all on sequence public.merchant_vip_log_id_seq from public, anon, authenticated;

-- ---------------------------------------------------------------- 3. helpers
create function public._beirut_today() returns date language sql stable set search_path = public, pg_temp as $$
  select (now() at time zone 'Asia/Beirut')::date
$$;
create function public._tier_pct(p_tier text) returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select public._setting('tier_redeem_pct_' || coalesce(p_tier, 'small'), case p_tier when 'large' then 100 when 'medium' then 50 else 20 end)
$$;
-- current VIP cap of a customer at a branch (lowering waits for the next Beirut day)
create function public._vip_cap(p_mid uuid, p_phone text) returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select case when v.next_from is not null and v.next_from <= public._beirut_today() then v.next_cap else v.cap_points end
    from public.merchant_vips v where v.merchant_id = p_mid and v.customer_phone = p_phone and v.status = 'active' and v.cap_points > 0
$$;

-- ---------------------------------------------------------------- 4. the quote with the approved rules
create function public._tx_quote2(p_mid uuid, p_phone text, p_invoice numeric, p_redeem boolean, p_offer_id uuid, p_want numeric)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare m public.merchants; c public.customers; o public.offers;
  rate numeric; tier_max numeric; tier_pct numeric; pct numeric; disc numeric := 0; base numeric; vip numeric; vip_left numeric := null;
  avail_pts numeric; allow_cap numeric; cap numeric; rp numeric; rv numeric; net numeric; bonus numeric := 0; earn numeric;
  wallet_avail numeric; n_today int; lim numeric; used numeric; eligible numeric; earn_pct numeric;
begin
  select * into m from public.merchants where id = p_mid;
  if m.id is null or m.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب المحل غير فعّال'); end if;
  select * into c from public.customers where phone = p_phone;
  if c.phone is null then return jsonb_build_object('ok', false, 'error', 'هذا الحساب غير موجود'); end if;
  if c.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب الزبون مجمّد'); end if;
  if p_invoice is null or p_invoice <= 0 then return jsonb_build_object('ok', false, 'error', 'أدخل قيمة الفاتورة'); end if;
  if p_invoice > public._setting('tx_max_invoice', 100000) then return jsonb_build_object('ok', false, 'error', 'قيمة الفاتورة كبيرة جداً'); end if;
  if round(p_invoice, 2) <> p_invoice then return jsonb_build_object('ok', false, 'error', 'قيمة الفاتورة غير صحيحة'); end if;
  earn_pct := coalesce(m.pct, 0);
  if earn_pct < public._setting('earn_pct_min', 1) or earn_pct > public._setting('earn_pct_max', 10) then        -- §04
    return jsonb_build_object('ok', false, 'error', 'earn_pct_invalid', 'message', 'نسبة مكافآت المحل خارج المجال المعتمد. تواصل مع الإدارة');
  end if;
  n_today := (select count(*) from public.pos_transactions where customer_phone = p_phone and merchant_id = p_mid
                and status in ('PENDING','CONFIRMED') and created_at >= public._day_start());
  if n_today >= public._setting('tx_per_customer_branch_day', 2) then
    return jsonb_build_object('ok', false, 'error', 'daily_limit', 'message', 'وصل الزبون إلى الحد اليومي للعمليات في هذا الفرع');
  end if;
  rate := public._setting('rate_pts_per_usd', 100);
  if p_offer_id is not null then
    select * into o from public.offers where id = p_offer_id and merchant_id = p_mid;
    if o.id is null then return jsonb_build_object('ok', false, 'error', 'العرض غير موجود'); end if;
    if not o.active or coalesce(o.deleted, false) or now() - o.created_at >= (o.days || ' days')::interval then return jsonb_build_object('ok', false, 'error', 'انتهى هذا العرض'); end if;
    if o.min_amount > 0 and p_invoice < o.min_amount then return jsonb_build_object('ok', false, 'error', format('الحد الأدنى لهذا العرض $%s', o.min_amount)); end if;
    if o.first_time_only and exists (select 1 from public.pos_transactions where merchant_id = p_mid and customer_phone = p_phone and status = 'CONFIRMED') then
      return jsonb_build_object('ok', false, 'error', 'هذا العرض للزائر الجديد فقط');
    end if;
  end if;
  tier_max := public._setting('tier_redeem_max_' || coalesce(m.tier, 'small'), case m.tier when 'large' then 10000 when 'medium' then 2500 else 1000 end);
  tier_pct := public._tier_pct(m.tier);                                                                         -- §03
  disc := case when o.type = 'discount' then round(p_invoice * o.val / 100, 2) else 0 end;                      -- §08: discount first
  base := round(p_invoice - disc, 2);
  avail_pts := public._pts_spendable(p_phone);
  allow_cap := public._allow_cap(public._allow_remaining(p_mid));
  vip := public._vip_cap(p_mid, p_phone);
  if vip is not null then                                                                                       -- §16 VIP-3
    used := (select coalesce(sum(redeem_pts), 0) from public.pos_transactions where customer_phone = p_phone and merchant_id = p_mid
               and status in ('PENDING','CONFIRMED') and created_at >= public._day_start());
    vip_left := greatest(0, vip - used);
    pct := least(coalesce(m.redeem_pct_vip, m.redeem_pct, tier_pct), tier_pct);
    cap := least(avail_pts, vip_left, floor(base * rate * pct / 100), allow_cap);
  else
    pct := least(coalesce(m.redeem_pct, tier_pct), tier_pct);
    cap := least(avail_pts, floor(base * rate * pct / 100), tier_max, allow_cap);
  end if;
  cap := greatest(0, floor(cap));
  -- §03: the customer decides the amount (on his purchase code); acceptance is mandatory within the limits
  rp := case when p_want is not null then least(cap, floor(p_want)) when p_redeem then cap else 0 end;
  rv := rp / rate;
  net := round(base - rv, 2);
  -- §04: daily eligible purchases per customer per branch, from the tier (reference points / rate)
  lim := public._setting('daily_eligible_pts_' || coalesce(m.tier, 'small'), 0) / rate;
  if lim > 0 then
    used := (select coalesce(sum(px.net), 0) from public.pos_transactions px where px.customer_phone = p_phone and px.merchant_id = p_mid
               and px.status in ('PENDING','CONFIRMED') and px.created_at >= public._day_start());
    eligible := greatest(0, least(net, lim - used));
  else eligible := net; end if;
  bonus := case when o.type = 'bonus' and o.per > 0 then floor(eligible / o.per) * o.pts else 0 end;
  earn := floor(eligible * earn_pct / 100 * rate) + bonus;                                                     -- PROVISIONAL rounding: floor
  wallet_avail := (public.merchant_wallet(p_mid)->>'avail')::numeric;
  if earn / rate > wallet_avail then return jsonb_build_object('ok', false, 'error', 'INSUFFICIENT'); end if;
  return jsonb_build_object('ok', true, 'invoice', p_invoice, 'disc', disc, 'redeem_pts', rp, 'redeem_val', rv, 'net', net,
    'bonus', bonus, 'earn', earn, 'redeem_max', cap, 'offer_id', p_offer_id, 'eligible', eligible, 'eligible_cap', lim,
    'allowance_cap', allow_cap, 'customer_points', avail_pts, 'today_count', n_today, 'pct', pct, 'vip', vip is not null,
    'vip_left', vip_left, 'customer_chose', p_want is not null, 'rounding', 'floor (provisional)');
end $$;

create or replace function public._tx_quote(p_mid uuid, p_phone text, p_invoice numeric, p_redeem boolean, p_offer_id uuid) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select public._tx_quote2(p_mid, p_phone, p_invoice, p_redeem, p_offer_id, null)
$$;

-- ---------------------------------------------------------------- 5. repeat-value alert (§04, never blocks)
create function public._alert_repeat_value(t public.pos_transactions) returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if exists (select 1 from public.pos_transactions p where p.customer_phone = t.customer_phone and p.merchant_id = t.merchant_id
               and p.status = 'CONFIRMED' and p.id <> t.id and p.invoice = t.invoice
               and (p.created_at at time zone 'Asia/Beirut')::date = (t.created_at at time zone 'Asia/Beirut')::date - 1) then
    perform public._ev('alert_repeat_value', null, t.customer_phone, t.merchant_id, null, t.id, jsonb_build_object('invoice', t.invoice));
  end if;
end $$;

-- ---------------------------------------------------------------- 6. text patches (one line each)
do $$
declare r record; d text; n int;
begin
  for r in select * from (values
    ('merchant_quote_v2(text,uuid,numeric,boolean,uuid)',
     'return public._tx_quote(m.id, pc.customer_phone, p_invoice, coalesce(p_redeem, false), p_offer_id);',
     'return public._tx_quote2(m.id, pc.customer_phone, p_invoice, coalesce(p_redeem, false), p_offer_id, pc.redeem_want); /* B3G */'),
    ('merchant_create_tx_v2(text,uuid,numeric,boolean,uuid,jsonb,text)',
     'q := public._tx_quote(m.id, c.phone, p_invoice, coalesce(p_redeem, false), p_offer_id);',
     'q := public._tx_quote2(m.id, c.phone, p_invoice, coalesce(p_redeem, false), p_offer_id, pc.redeem_want); /* B3G */'),
    ('customer_decide_tx_v2(text,uuid,boolean,text)',
     'perform public._alerts_after_confirm(t);',
     'perform public._alerts_after_confirm(t); perform public._alert_repeat_value(t); /* B3G */')) v(sig, old, new) loop
    d := (select def from tp_backup.func_snapshots where batch = 'b3g_rules' and sig = r.sig);
    n := (length(d) - length(replace(d, r.old, ''))) / length(r.old);
    if n <> 1 then raise exception 'patch target found % times in %', n, r.sig; end if;
    execute replace(d, r.old, r.new);
  end loop;
end $$;

-- ---------------------------------------------------------------- 7. customer: amount of points to use on this code (§03)
create function public.customer_qr_set_redeem(p_session text, p_code_id uuid, p_points numeric) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers; pc public.purchase_codes;
begin
  c := public._sess_customer(p_session);
  if p_points is not null and (p_points < 0 or p_points <> floor(p_points) or p_points > 10000000) then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  update public.purchase_codes set redeem_want = p_points
   where id = p_code_id and customer_phone = c.phone and tx_id is null and superseded_at is null and expires_at > now() - interval '1 minute'
  returning * into pc;
  if pc.id is null then return jsonb_build_object('ok', false, 'error', 'not_found', 'message', 'الرمز لم يعد صالحاً'); end if;
  return jsonb_build_object('ok', true, 'redeem_want', pc.redeem_want, 'spendable', public._pts_spendable(c.phone));
end $$;

-- ---------------------------------------------------------------- 8. shop % below the tier needs Admin approval (§03)
create or replace function public.merchant_set_redeem_pct_v2(p_session text, p_redeem_pct numeric, p_redeem_pct_vip numeric default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; tp numeric; vip numeric;
begin
  m := public._sess_merchant(p_session);
  tp := public._tier_pct(m.tier);
  if p_redeem_pct is null or p_redeem_pct <= 0 or p_redeem_pct > tp or p_redeem_pct <> round(p_redeem_pct, 2)
     or (p_redeem_pct_vip is not null and (p_redeem_pct_vip <= 0 or p_redeem_pct_vip > tp)) then
    return jsonb_build_object('ok', false, 'error', 'bad_pct', 'message', format('النسبة بين 1%% و %s%% لفئة محلك', tp));
  end if;
  vip := coalesce(p_redeem_pct_vip, greatest(p_redeem_pct, coalesce(m.redeem_pct_vip, p_redeem_pct)));
  if p_redeem_pct >= tp and vip >= tp then                        -- the tier's own % : no approval needed
    update public.merchants set redeem_pct = tp, redeem_pct_vip = tp, pending_redeem_pct = null, pending_redeem_pct_vip = null, pending_redeem_at = null
     where id = m.id returning * into m;
    perform public._audit('merchant', m.id::text, 'redeem_pct_tier', 'merchant', m.id::text, jsonb_build_object('pct', tp));
    return jsonb_build_object('ok', true, 'redeem_pct', m.redeem_pct, 'redeem_pct_vip', m.redeem_pct_vip, 'pending', false);
  end if;
  update public.merchants set pending_redeem_pct = p_redeem_pct, pending_redeem_pct_vip = vip, pending_redeem_at = now() where id = m.id;
  perform public._audit('merchant', m.id::text, 'redeem_pct_request', 'merchant', m.id::text, jsonb_build_object('pct', p_redeem_pct, 'vip', vip, 'tier_pct', tp));
  return jsonb_build_object('ok', true, 'pending', true, 'redeem_pct', m.redeem_pct, 'redeem_pct_vip', m.redeem_pct_vip,
    'message', 'أُرسل طلب النسبة الأقل إلى الإدارة للموافقة');
end $$;

create function public.admin_redeem_pct_requests_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  return jsonb_build_object('ok', true, 'requests', (select coalesce(jsonb_agg(jsonb_build_object('merchant_id', id, 'name', name, 'tier', tier,
     'tier_pct', public._tier_pct(tier), 'current', redeem_pct, 'current_vip', redeem_pct_vip, 'requested', pending_redeem_pct,
     'requested_vip', pending_redeem_pct_vip, 'at', floor(extract(epoch from pending_redeem_at) * 1000)) order by pending_redeem_at), '[]'::jsonb)
     from public.merchants where pending_redeem_pct is not null));
end $$;

create function public.admin_review_redeem_pct_v2(p_session text, p_merchant_id uuid, p_approve boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; m public.merchants;
begin
  a := public._sess_admin(p_session, true);
  select * into m from public.merchants where id = p_merchant_id and pending_redeem_pct is not null for update;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_approve then
    update public.merchants set redeem_pct = least(pending_redeem_pct, public._tier_pct(tier)), redeem_pct_vip = least(pending_redeem_pct_vip, public._tier_pct(tier)),
           pending_redeem_pct = null, pending_redeem_pct_vip = null, pending_redeem_at = null where id = m.id returning * into m;
  else
    update public.merchants set pending_redeem_pct = null, pending_redeem_pct_vip = null, pending_redeem_at = null where id = m.id;
  end if;
  insert into public.merchant_notes(merchant_id, type, title, body) values (m.id, 'info',
    case when p_approve then 'وافقت الإدارة على نسبة الاستبدال الجديدة' else 'لم توافق الإدارة على نسبة الاستبدال المطلوبة' end, null);
  perform public._audit('admin', a.id::text, case when p_approve then 'redeem_pct_approve' else 'redeem_pct_reject' end, 'merchant', m.id::text,
    jsonb_build_object('pct', m.redeem_pct, 'vip', m.redeem_pct_vip));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- 9. VIP (§16) — owner only
create function public.merchant_vip_candidates_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return jsonb_build_object('ok', true, 'customers', (select coalesce(jsonb_agg(x order by x->>'last' desc), '[]'::jsonb) from (
    select jsonb_build_object('ref', (array_agg(t.id order by t.created_at desc))[1], 'cref', '••' || right(t.customer_phone, 2),
      'name', max(case when c.name = 'زبون جديد' then null else c.name end), 'purchases', count(*),
      'last', floor(extract(epoch from max(t.created_at)) * 1000),
      'vip_cap', (select public._vip_cap(m.id, t.customer_phone))) x
      from public.pos_transactions t join public.customers c on c.phone = t.customer_phone
     where t.merchant_id = m.id and t.status = 'CONFIRMED' group by t.customer_phone order by max(t.created_at) desc limit 200) q));
end $$;

create function public.merchant_vip_list_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; lim numeric;
begin
  m := public._sess_merchant(p_session);
  lim := (select value from public.app_settings where key = 'vip_max_' || coalesce(m.tier, 'small'));
  return jsonb_build_object('ok', true, 'limit', lim, 'count', (select count(*) from public.merchant_vips where merchant_id = m.id and status = 'active'),
    'vips', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'cref', '••' || right(v.customer_phone, 2),
       'name', case when c.name = 'زبون جديد' then null else c.name end, 'cap', public._vip_cap(m.id, v.customer_phone), 'cap_set', v.cap_points,
       'next_cap', v.next_cap, 'next_from', v.next_from) order by v.created_at), '[]'::jsonb)
       from public.merchant_vips v join public.customers c on c.phone = v.customer_phone where v.merchant_id = m.id and v.status = 'active'));
end $$;

-- add / change a VIP: p_ref is a confirmed purchase of that customer at this branch (the owner never types a phone)
create function public.merchant_vip_set_v2(p_session text, p_ref uuid, p_cap numeric) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; ph text; v public.merchant_vips; lim numeric; n int; cur numeric; tomorrow date := public._beirut_today() + 1;
begin
  m := public._sess_merchant(p_session);
  if p_cap is null or p_cap <= 0 or p_cap <> floor(p_cap) or p_cap > 10000000 then return jsonb_build_object('ok', false, 'error', 'bad_cap'); end if;
  ph := (select customer_phone from public.pos_transactions where id = p_ref and merchant_id = m.id and status = 'CONFIRMED');
  if ph is null then return jsonb_build_object('ok', false, 'error', 'not_eligible', 'message', 'VIP فقط لزبائن أتمّوا عملية نقاط في فرعك'); end if;
  select * into v from public.merchant_vips where merchant_id = m.id and customer_phone = ph for update;
  if v.id is null or v.status <> 'active' then
    lim := (select value from public.app_settings where key = 'vip_max_' || coalesce(m.tier, 'small'));
    if lim is null then return jsonb_build_object('ok', false, 'error', 'vip_limit_not_set', 'message', 'لم تحدد الإدارة بعد عدد VIP المسموح لفئة محلك'); end if;
    n := (select count(*) from public.merchant_vips where merchant_id = m.id and status = 'active');
    if n >= lim then return jsonb_build_object('ok', false, 'error', 'vip_limit', 'message', format('وصلت إلى الحد الأقصى لعدد VIP (%s)', lim)); end if;
    if v.id is null then
      insert into public.merchant_vips(merchant_id, customer_phone, cap_points, status, updated_at) values (m.id, ph, p_cap, 'active', now()) returning * into v;
    else
      update public.merchant_vips set cap_points = p_cap, status = 'active', next_cap = null, next_from = null, updated_at = now() where id = v.id returning * into v;
    end if;
    insert into public.merchant_vip_log(merchant_id, customer_phone, action, old_cap, new_cap, effective_from, actor)
    values (m.id, ph, case when v.created_at < now() - interval '1 second' then 'reactivate' else 'add' end, null, p_cap, public._beirut_today(), m.id::text);
    insert into public.customer_notes(customer_phone, type, title, body) values (ph, 'general', '👑 أصبحت VIP في ' || m.name, format('حد استبدال يومي حتى %s نقطة في هذا الفرع', p_cap));
    perform public._audit('merchant', m.id::text, 'vip_add', 'vip', v.id::text, jsonb_build_object('cap', p_cap));
    return jsonb_build_object('ok', true, 'cap', p_cap, 'effective', 'now');
  end if;
  cur := public._vip_cap(m.id, ph);
  if p_cap >= cur then                                      -- raise: immediate (and drops any pending lowering)
    update public.merchant_vips set cap_points = p_cap, next_cap = null, next_from = null, updated_at = now() where id = v.id;
    insert into public.merchant_vip_log(merchant_id, customer_phone, action, old_cap, new_cap, effective_from, actor)
    values (m.id, ph, 'raise', cur, p_cap, public._beirut_today(), m.id::text);
    perform public._audit('merchant', m.id::text, 'vip_raise', 'vip', v.id::text, jsonb_build_object('from', cur, 'to', p_cap));
    return jsonb_build_object('ok', true, 'cap', p_cap, 'effective', 'now');
  end if;
  -- lower: from the next Beirut day, without notification (§16 VIP-4)
  update public.merchant_vips set cap_points = cur, next_cap = p_cap, next_from = tomorrow, updated_at = now() where id = v.id;
  insert into public.merchant_vip_log(merchant_id, customer_phone, action, old_cap, new_cap, effective_from, actor)
  values (m.id, ph, 'lower', cur, p_cap, tomorrow, m.id::text);
  perform public._audit('merchant', m.id::text, 'vip_lower', 'vip', v.id::text, jsonb_build_object('from', cur, 'to', p_cap, 'from_day', tomorrow));
  return jsonb_build_object('ok', true, 'cap', cur, 'next_cap', p_cap, 'effective', tomorrow);
end $$;

create function public.merchant_vip_cancel_v2(p_session text, p_vip_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; v public.merchant_vips;
begin
  m := public._sess_merchant(p_session);
  update public.merchant_vips set status = 'cancelled', next_cap = null, next_from = null, updated_at = now()
   where id = p_vip_id and merchant_id = m.id and status = 'active' returning * into v;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into public.merchant_vip_log(merchant_id, customer_phone, action, old_cap, new_cap, effective_from, actor)
  values (m.id, v.customer_phone, 'cancel', v.cap_points, null, public._beirut_today(), m.id::text);
  insert into public.customer_notes(customer_phone, type, title, body) values (v.customer_phone, 'general', 'انتهت عضوية VIP في ' || m.name, 'نقاطك وعملياتك محفوظة كما هي.');
  perform public._audit('merchant', m.id::text, 'vip_cancel', 'vip', v.id::text);
  return jsonb_build_object('ok', true);
end $$;

create function public.customer_vips_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers;
begin
  c := public._sess_customer(p_session);
  return jsonb_build_object('ok', true, 'vips', (select coalesce(jsonb_agg(jsonb_build_object('shop', mm.name, 'mid', mm.id,
     'cap', public._vip_cap(v.merchant_id, v.customer_phone), 'next_cap', v.next_cap, 'next_from', v.next_from,
     'used_today', (select coalesce(sum(redeem_pts), 0) from public.pos_transactions t where t.customer_phone = c.phone and t.merchant_id = v.merchant_id
                     and t.status in ('PENDING','CONFIRMED') and t.created_at >= public._day_start()))), '[]'::jsonb)
     from public.merchant_vips v join public.merchants mm on mm.id = v.merchant_id where v.customer_phone = c.phone and v.status = 'active'));
end $$;

-- ---------------------------------------------------------------- 10. Admin settings: the new keys
create or replace function public.admin_engine_setting_v2(p_session text, p_key text, p_value numeric) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; lo numeric; hi numeric; old numeric;
begin
  a := public._sess_admin(p_session, true);
  select x.lo, x.hi into lo, hi from (values ('points_valid_months', 1, 24), ('legacy_points_valid_months', 1, 24), ('tx_per_customer_branch_day', 1, 20),
    ('allowance_cap_pct', 1, 100), ('allowance_small_threshold', 0, 1000), ('sub_carryover_months', 0, 6),
    ('tier_redeem_max_small', 0, 1000000), ('tier_redeem_max_medium', 0, 1000000), ('tier_redeem_max_large', 0, 1000000),
    ('tier_redeem_pct_small', 1, 100), ('tier_redeem_pct_medium', 1, 100), ('tier_redeem_pct_large', 1, 100),
    ('daily_eligible_pts_small', 0, 10000000), ('daily_eligible_pts_medium', 0, 10000000), ('daily_eligible_pts_large', 0, 10000000),
    ('earn_pct_min', 0, 100), ('earn_pct_max', 0, 100),
    ('vip_max_small', 0, 10000), ('vip_max_medium', 0, 10000), ('vip_max_large', 0, 10000),
    ('pay_pending_max', 1, 20), ('engine_strict', 0, 1)) as x(k, lo, hi) where x.k = p_key;
  if lo is null then return jsonb_build_object('ok', false, 'error', 'unknown_key'); end if;
  if p_value is null or p_value < lo or p_value > hi or p_value <> round(p_value) then
    return jsonb_build_object('ok', false, 'error', format('القيمة يجب أن تكون عدداً صحيحاً بين %s و %s', lo, hi));
  end if;
  old := (select value from public.app_settings where key = p_key);
  insert into public.app_settings(key, value) values (p_key, p_value) on conflict (key) do update set value = excluded.value;
  perform public._audit('admin', a.id::text, 'engine_setting', 'setting', p_key, jsonb_build_object('before', old, 'after', p_value));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_catalog_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  return jsonb_build_object('ok', true,
    'transfer_number', (select value from public.app_text_settings where key = 'pay_transfer_number'),
    'transfer_instructions', (select value from public.app_text_settings where key = 'pay_transfer_instructions'),
    'plans', (select coalesce(jsonb_agg(to_jsonb(p) order by p.code), '[]'::jsonb) from public.plans p),
    'packages', (select coalesce(jsonb_agg(to_jsonb(p) order by p.code), '[]'::jsonb) from public.packages p),
    'settings', (select jsonb_object_agg(key, value) from public.app_settings where key in ('points_valid_months','legacy_points_valid_months',
       'tx_per_customer_branch_day','allowance_cap_pct','allowance_small_threshold','sub_carryover_months','tier_redeem_max_small',
       'tier_redeem_max_medium','tier_redeem_max_large','tier_redeem_pct_small','tier_redeem_pct_medium','tier_redeem_pct_large',
       'daily_eligible_pts_small','daily_eligible_pts_medium','daily_eligible_pts_large','earn_pct_min','earn_pct_max',
       'vip_max_small','vip_max_medium','vip_max_large','pay_pending_max','engine_strict','rate_pts_per_usd')));
end $$;

-- ---------------------------------------------------------------- 11. privileges + self-check
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      '_beirut_today','_tier_pct','_vip_cap','_tx_quote2','_tx_quote','_alert_repeat_value']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'customer_qr_set_redeem','admin_redeem_pct_requests_v2','admin_review_redeem_pct_v2','merchant_vip_candidates_v2','merchant_vip_list_v2',
      'merchant_vip_set_v2','merchant_vip_cancel_v2','customer_vips_v2']) loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
  if has_function_privilege('anon', 'public._tx_quote2(uuid,text,numeric,boolean,uuid,numeric)', 'execute') then raise exception 'self-check: _tx_quote2 open'; end if;
  if not has_function_privilege('anon', 'public.merchant_set_redeem_pct_v2(text,numeric,numeric)', 'execute') then raise exception 'self-check: grant lost'; end if;
  if (select value from public.app_text_settings where key = 'welcome_bonus') is distinct from '3000'
     or (select value from public.app_text_settings where key = 'welcome_days') is distinct from '7' then raise exception 'self-check: gift settings changed'; end if;
end $$;

commit;
