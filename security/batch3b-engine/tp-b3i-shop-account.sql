-- =====================================================================================================
-- Tripoli Points — BATCH 3i: subscription grace, opening hours, closures, account deletion, marketing consent (STAGING)
-- Register 12-Nov-2026:
--   §05  10-day grace after a subscription ends when there is no valid card balance; then the shop page and pin are
--        hidden (data kept) until eligibility returns. Behind the switch sub_enforce (0 on Staging: no test shop has a
--        subscription yet, turning it on would hide all of them).
--   §14  weekly hours + exceptions, set by the owner; new points purchases stop while the branch is officially closed
--        (checking an earlier purchase stays possible); a long temporary closure keeps the pin and page with
--        «مغلق مؤقتاً»; subscription periods continue (no automatic extension); customers can report wrong hours.
--   §15  permanent closure on the owner's request after Admin review of balances, complaints and purchases: page, pin,
--        ads and new points purchases stop; all records and customers' points stay; no automatic transfer.
--   Annex account deletion: request from «حسابي» after identity check (PIN), 7 days to cancel; then the account is
--        disabled and stops earning / using points, batches kept 3 months from the disable date; reactivation within
--        3 months restores only points still valid at their original dates; after that the remaining points are
--        cancelled with a recorded movement and unnecessary personal data is removed (legal records kept).
--   Annex privacy: marketing consent separate, optional, changeable, with its time; never a condition to register.
-- Changes: settings (fill-missing), 7 nullable columns, 2 tables, 4 functions text-patched (saved in
--   tp_backup.func_snapshots 'b3i'), new functions. No drop / truncate. The only DELETE is inside merchant_hours_set_v2
--   (an owner replacing his own weekly schedule rows, WHERE merchant_id = his branch). Rollback: R_tp-b3i-shop-account-rollback.sql
-- =====================================================================================================
begin;

do $$ begin
  if to_regprocedure('public._pts_remind(text)') is null then raise exception 'batch 3h required'; end if;
  if exists (select 1 from tp_backup.func_snapshots where batch = 'b3i') then raise exception 'already applied'; end if;
end $$;

do $$
declare r record; cur text;
begin
  for r in select * from (values
    ('list_merchants()', '4e12b38d99a67cc639dfcc7b0470a772'),
    ('_tx_quote2(uuid,text,numeric,boolean,uuid,numeric)', '2ce4a861cd17a22b79bf2c1463d73093'),
    ('admin_engine_setting_v2(text,text,numeric)', '9f44a2d8621079ed74978b92fad7db8e'),
    ('admin_catalog_v2(text)', '3b248c4e741e2bd2a623ecb51b95f7c2')) v(sig, want) loop
    cur := (select md5(replace(prosrc, chr(13), '')) from pg_proc where oid = to_regprocedure('public.' || r.sig));
    if cur is distinct from r.want then raise exception '% differs (md5 %), stop', r.sig, cur; end if;
    insert into tp_backup.func_snapshots(batch, sig, def, src_md5)
    values ('b3i', r.sig, pg_get_functiondef(to_regprocedure('public.' || r.sig)), (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)));
  end loop;
  for r in select * from (values ('sub_grace_days', 10), ('sub_enforce', 0), ('account_cancel_days', 7), ('account_keep_months', 3)) v(k, val) loop
    if not exists (select 1 from public.app_settings where key = r.k) then
      execute 'insert ' || 'into public.app_settings(key, value) values ($1, $2)' using r.k, r.val;
      insert into tp_backup.settings_snapshots(batch, tbl, key, existed, old_value, inserted_value) values ('b3i', 'app_settings', r.k, false, null, r.val::text);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------- columns + tables
alter table public.merchants add column closure_requested_at timestamptz, add column closed_at timestamptz;
alter table public.customers add column deletion_requested_at timestamptz, add column deactivated_at timestamptz, add column data_removed_at timestamptz,
  add column marketing_consent boolean not null default false, add column marketing_consent_at timestamptz;

create table public.merchant_hours(
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  dow smallint not null check (dow between 0 and 6),                -- 0 = Sunday (Beirut local day)
  opens time not null, closes time not null,                        -- closes < opens = past midnight
  primary key (merchant_id, dow, opens));
create table public.merchant_closures(
  id bigserial primary key,
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  starts_at timestamptz not null, ends_at timestamptz,               -- null = until the owner reopens
  reason text, created_by text, created_at timestamptz not null default now(), ended_at timestamptz,
  check (ends_at is null or ends_at > starts_at));
create index merchant_closures_m_idx on public.merchant_closures(merchant_id, starts_at);
do $$ begin
  execute 'alter table public.merchant_hours enable row level security';
  execute 'alter table public.merchant_closures enable row level security';
  execute 'revoke all on table public.merchant_hours from public, anon, authenticated';
  execute 'revoke all on table public.merchant_closures from public, anon, authenticated';
  execute 'revoke all on sequence public.merchant_closures_id_seq from public, anon, authenticated';
end $$;

-- ---------------------------------------------------------------- shop state
-- §05 listed = switch off, or a subscription period not ended more than <grace> days ago, or a valid card balance
create function public._merchant_listed(p_mid uuid) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select public._setting('sub_enforce', 0) <> 1
      or exists (select 1 from public.merchant_subscriptions s where s.merchant_id = p_mid and s.period_start <= now()
                   and s.period_end + make_interval(days => public._setting('sub_grace_days', 10)::int) > now())
      or exists (select 1 from public.allowance_grants g where g.merchant_id = p_mid and g.source = 'package' and g.remaining > 0
                   and g.valid_from <= now() and g.expires_at > now())
$$;

-- §14 'open' | 'closed_hours' | 'closed_temp' | 'closed_final' | 'hidden'  (no hours entered = open)
create function public._shop_state(p_mid uuid) returns text language plpgsql stable security definer set search_path = public, pg_temp as $$
declare m public.merchants; lt timestamp := now() at time zone 'Asia/Beirut'; d int; t time; prev int;
begin
  select * into m from public.merchants where id = p_mid;
  if m.closed_at is not null then return 'closed_final'; end if;
  if not public._merchant_listed(p_mid) then return 'hidden'; end if;
  if exists (select 1 from public.merchant_closures c where c.merchant_id = p_mid and c.ended_at is null and c.starts_at <= now()
               and (c.ends_at is null or c.ends_at > now())) then return 'closed_temp'; end if;
  if not exists (select 1 from public.merchant_hours h where h.merchant_id = p_mid) then return 'open'; end if;
  d := extract(dow from lt)::int; t := lt::time; prev := (d + 6) % 7;
  if exists (select 1 from public.merchant_hours h where h.merchant_id = p_mid and (
       (h.dow = d and h.opens <= h.closes and t >= h.opens and t < h.closes)
    or (h.dow = d and h.opens > h.closes and t >= h.opens)
    or (h.dow = prev and h.opens > h.closes and t < h.closes))) then return 'open'; end if;
  return 'closed_hours';
end $$;

-- ---------------------------------------------------------------- §14 owner: hours and temporary closures
create function public.merchant_hours_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_branch(p_session, 'sell');
  return jsonb_build_object('ok', true, 'state', public._shop_state(m.id),
    'hours', (select coalesce(jsonb_agg(jsonb_build_object('dow', dow, 'opens', to_char(opens, 'HH24:MI'), 'closes', to_char(closes, 'HH24:MI')) order by dow, opens), '[]'::jsonb)
              from public.merchant_hours where merchant_id = m.id),
    'closures', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'starts_at', floor(extract(epoch from starts_at) * 1000),
                  'ends_at', case when ends_at is null then null else floor(extract(epoch from ends_at) * 1000) end, 'reason', reason) order by starts_at), '[]'::jsonb)
                 from public.merchant_closures where merchant_id = m.id and ended_at is null and (ends_at is null or ends_at > now())));
end $$;

-- p_hours: [{"dow":0..6,"opens":"09:00","closes":"22:00"}, …]; replaces the weekly schedule (owner only)
create function public.merchant_hours_set_v2(p_session text, p_hours jsonb) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; h jsonb;
begin
  m := public._sess_merchant(p_session);
  if jsonb_typeof(p_hours) <> 'array' or jsonb_array_length(p_hours) > 28 then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  for h in select x from jsonb_array_elements(p_hours) x loop
    if (h->>'dow') !~ '^[0-6]$' or (h->>'opens') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or (h->>'closes') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
       or h->>'opens' = h->>'closes' then
      return jsonb_build_object('ok', false, 'error', 'bad_hours', 'message', 'أوقات غير صحيحة');
    end if;
  end loop;
  delete from public.merchant_hours where merchant_id = m.id;     -- replaces the owner's own weekly schedule rows (function body, one branch)
  insert into public.merchant_hours(merchant_id, dow, opens, closes)
  select m.id, (x->>'dow')::smallint, (x->>'opens')::time, (x->>'closes')::time from jsonb_array_elements(p_hours) x on conflict do nothing;
  perform public._audit('merchant', m.id::text, 'hours_set', 'merchant', m.id::text, jsonb_build_object('rows', jsonb_array_length(p_hours)));
  return jsonb_build_object('ok', true, 'state', public._shop_state(m.id));
end $$;

create function public.merchant_closure_start_v2(p_session text, p_from timestamptz, p_until timestamptz, p_reason text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; id bigint;
begin
  m := public._sess_merchant(p_session);
  if coalesce(p_from, now()) < now() - interval '1 minute' or (p_until is not null and p_until <= coalesce(p_from, now())) or length(coalesce(p_reason, '')) > 200 then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  insert into public.merchant_closures(merchant_id, starts_at, ends_at, reason, created_by) values (m.id, coalesce(p_from, now()), p_until, nullif(trim(p_reason), ''), m.id::text)
  returning merchant_closures.id into id;
  perform public._audit('merchant', m.id::text, 'closure_start', 'merchant', m.id::text, jsonb_build_object('closure', id, 'until', p_until));
  return jsonb_build_object('ok', true, 'id', id, 'state', public._shop_state(m.id));
end $$;

create function public.merchant_closure_end_v2(p_session text, p_id bigint) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; n int;
begin
  m := public._sess_merchant(p_session);
  update public.merchant_closures set ended_at = now() where id = p_id and merchant_id = m.id and ended_at is null;
  get diagnostics n = row_count;
  if n = 0 then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform public._audit('merchant', m.id::text, 'closure_end', 'merchant', m.id::text, jsonb_build_object('closure', p_id));
  return jsonb_build_object('ok', true, 'state', public._shop_state(m.id));
end $$;

-- public (any visitor): the shop's current state and hours for its page
create function public.shop_hours_public(p_mid uuid) returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('state', public._shop_state(p_mid),
    'hours', (select coalesce(jsonb_agg(jsonb_build_object('dow', dow, 'opens', to_char(opens, 'HH24:MI'), 'closes', to_char(closes, 'HH24:MI')) order by dow, opens), '[]'::jsonb)
              from public.merchant_hours where merchant_id = p_mid))
   where exists (select 1 from public.merchants where id = p_mid and status = 'active')
$$;

-- a customer reports wrong location / hours (Admin feed; repeated reports visible)
create function public.report_shop_info_v2(p_session text, p_mid uuid, p_note text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers;
begin
  c := public._sess_customer(p_session);
  if not exists (select 1 from public.merchants where id = p_mid) or length(coalesce(p_note, '')) > 300 then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if not public._rl2_hit('shopinfo:' || c.phone, public._setting('report_per_day', 5)::int, 86400, 0) then return jsonb_build_object('ok', false, 'error', 'rate_limited'); end if;
  perform public._ev('alert_shop_info', 'customer', c.phone, p_mid, null, null, jsonb_build_object('note', left(p_note, 300),
    'count_30d', (select count(*) + 1 from public.tx_events where event = 'alert_shop_info' and merchant_id = p_mid and at > now() - interval '30 days')));
  return jsonb_build_object('ok', true);
end $$;

-- §05 shop: its subscription / grace status
create function public.merchant_sub_status_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; pe timestamptz;
begin
  m := public._sess_branch(p_session, 'wallet');
  pe := (select max(period_end) from public.merchant_subscriptions where merchant_id = m.id and period_start <= now());
  return jsonb_build_object('ok', true, 'enforced', public._setting('sub_enforce', 0) = 1, 'listed', public._merchant_listed(m.id),
    'period_end', case when pe is null then null else floor(extract(epoch from pe) * 1000) end,
    'grace_until', case when pe is null then null else floor(extract(epoch from pe + make_interval(days => public._setting('sub_grace_days', 10)::int)) * 1000) end,
    'card_balance', (select coalesce(sum(remaining), 0) from public.allowance_grants where merchant_id = m.id and source = 'package' and expires_at > now()),
    'state', public._shop_state(m.id));
end $$;

-- ---------------------------------------------------------------- §15 permanent closure
create function public.merchant_close_shop_request_v2(p_session text, p_pin text) returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  if m.pin_hash is null or extensions.crypt(coalesce(p_pin, ''), m.pin_hash) <> m.pin_hash then return jsonb_build_object('ok', false, 'error', 'wrong_pin'); end if;
  update public.merchants set closure_requested_at = now() where id = m.id and closed_at is null;
  perform public._ev('alert_closure_request', 'merchant', null, m.id, null, null);
  perform public._audit('merchant', m.id::text, 'closure_request', 'merchant', m.id::text);
  return jsonb_build_object('ok', true, 'message', 'أُرسل طلب الإغلاق النهائي إلى الإدارة للمراجعة');
end $$;

create function public.admin_closure_review_v2(p_session text, p_merchant_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; m public.merchants;
begin
  a := public._sess_admin(p_session, false);
  select * into m from public.merchants where id = p_merchant_id;
  if m.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'requested_at', m.closure_requested_at, 'closed_at', m.closed_at,
    'pending_purchases', (select count(*) from public.pos_transactions where merchant_id = m.id and status = 'PENDING'),
    'open_reports', (select count(*) from public.tx_reports r join public.pos_transactions t on t.id = r.tx_id where t.merchant_id = m.id and r.status = 'open'),
    'pending_payments', (select count(*) from public.payment_requests where merchant_id = m.id and status = 'pending'),
    'allowance_remaining', public._allow_remaining(m.id),
    'customers_with_points_from_shop', (select count(distinct customer_phone) from public.point_batches where merchant_id = m.id and remaining > 0),
    'confirmed_purchases', (select count(*) from public.pos_transactions where merchant_id = m.id and status = 'CONFIRMED'));
end $$;

create function public.admin_close_shop_v2(p_session text, p_merchant_id uuid, p_approve boolean, p_note text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; m public.merchants;
begin
  a := public._sess_admin(p_session, true);
  select * into m from public.merchants where id = p_merchant_id for update;
  if m.id is null or m.closure_requested_at is null or m.closed_at is not null then return jsonb_build_object('ok', false, 'error', 'no_request'); end if;
  if p_note is null or length(trim(p_note)) < 3 then return jsonb_build_object('ok', false, 'error', 'note_required'); end if;
  if not p_approve then
    update public.merchants set closure_requested_at = null where id = m.id;
    insert into public.merchant_notes(merchant_id, type, title, body) values (m.id, 'info', 'لم يُعتمد طلب الإغلاق النهائي', left(trim(p_note), 300));
    perform public._audit('admin', a.id::text, 'closure_reject', 'merchant', m.id::text, jsonb_build_object('note', left(trim(p_note), 300)));
    return jsonb_build_object('ok', true, 'closed', false);
  end if;
  if exists (select 1 from public.pos_transactions where merchant_id = m.id and status = 'PENDING') then
    return jsonb_build_object('ok', false, 'error', 'pending_purchases', 'message', 'توجد عمليات قيد التأكيد');
  end if;
  update public.merchants set closed_at = now(), status = 'frozen' where id = m.id;          -- page, pin and new purchases stop; sessions end (trigger)
  update public.merchant_staff set status = 'disabled' where merchant_id = m.id and status = 'active';
  update public.payment_requests set status = 'cancelled', decided_at = now(), decided_by = a.id, decision_note = 'إغلاق نهائي' where merchant_id = m.id and status = 'pending';
  insert into public.merchant_notes(merchant_id, type, title, body) values (m.id, 'info', 'تم الإغلاق النهائي للفرع', left(trim(p_note), 300));
  perform public._audit('admin', a.id::text, 'closure_approve', 'merchant', m.id::text, jsonb_build_object('note', left(trim(p_note), 300),
    'allowance_left', public._allow_remaining(m.id)));
  return jsonb_build_object('ok', true, 'closed', true);
end $$;

-- ---------------------------------------------------------------- account deletion + marketing consent
create function public.customer_privacy_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers;
begin
  c := public._sess_customer(p_session);
  return jsonb_build_object('ok', true, 'marketing_consent', c.marketing_consent,
    'marketing_consent_at', case when c.marketing_consent_at is null then null else floor(extract(epoch from c.marketing_consent_at) * 1000) end,
    'terms_version', c.terms_version, 'terms_accepted_at', case when c.terms_accepted_at is null then null else floor(extract(epoch from c.terms_accepted_at) * 1000) end,
    'deletion_requested_at', case when c.deletion_requested_at is null then null else floor(extract(epoch from c.deletion_requested_at) * 1000) end,
    'deletion_effective_at', case when c.deletion_requested_at is null then null
       else floor(extract(epoch from c.deletion_requested_at + make_interval(days => public._setting('account_cancel_days', 7)::int)) * 1000) end);
end $$;

create function public.customer_set_marketing_v2(p_session text, p_consent boolean) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers;
begin
  c := public._sess_customer(p_session);
  if p_consent is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  update public.customers set marketing_consent = p_consent, marketing_consent_at = now() where phone = c.phone;
  perform public._audit('customer', c.phone, case when p_consent then 'marketing_on' else 'marketing_off' end, 'customer', c.phone);
  return jsonb_build_object('ok', true, 'marketing_consent', p_consent);
end $$;

create function public.customer_delete_request_v2(p_session text, p_pin text) returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.customers; d int := public._setting('account_cancel_days', 7)::int;
begin
  c := public._sess_customer(p_session);
  if c.pin_hash is null or extensions.crypt(coalesce(p_pin, ''), c.pin_hash) <> c.pin_hash then
    perform public._login_failed('customer:' || c.phone);
    return jsonb_build_object('ok', false, 'error', 'wrong_pin');
  end if;
  if c.deletion_requested_at is null then update public.customers set deletion_requested_at = now() where phone = c.phone; end if;
  insert into public.customer_notes(customer_phone, type, title, body) values (c.phone, 'general', 'طلب حذف الحساب',
    format('سيُعطَّل حسابك بعد %s أيام. يمكنك التراجع قبل ذلك من «حسابي». نقاطك تبقى محفوظة 3 أشهر بعد التعطيل.', d));
  perform public._audit('customer', c.phone, 'delete_request', 'customer', c.phone);
  return jsonb_build_object('ok', true, 'effective_in_days', d,
    'points', public._pts_spendable(c.phone));
end $$;

create function public.customer_delete_cancel_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers;
begin
  c := public._sess_customer(p_session);
  if c.deletion_requested_at is null then return jsonb_build_object('ok', false, 'error', 'no_request'); end if;
  update public.customers set deletion_requested_at = null where phone = c.phone;
  insert into public.customer_notes(customer_phone, type, title, body) values (c.phone, 'general', 'أُلغي طلب حذف الحساب', null);
  perform public._audit('customer', c.phone, 'delete_cancel', 'customer', c.phone);
  return jsonb_build_object('ok', true);
end $$;

-- the deletion timeline (run by the Admin job)
create function public._process_account_closures() returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c record; b record; dis int := 0; rem int := 0;
  d int := public._setting('account_cancel_days', 7)::int; k int := public._setting('account_keep_months', 3)::int;
begin
  for c in select phone from public.customers where deletion_requested_at is not null and deactivated_at is null
            and deletion_requested_at <= now() - make_interval(days => d) for update loop
    perform public._expire_pending(c.phone, null);
    update public.customers set status = 'frozen', deactivated_at = now() where phone = c.phone;          -- sessions end (trigger)
    update public.merchant_vips set status = 'cancelled', updated_at = now() where customer_phone = c.phone and status = 'active';
    perform public._audit('system', null, 'account_disabled', 'customer', c.phone);
    dis := dis + 1;
  end loop;
  for c in select phone from public.customers where deactivated_at is not null and data_removed_at is null
            and deactivated_at <= now() - make_interval(months => k) for update loop
    for b in update public.point_batches pb set remaining = 0 from (select id, remaining as r0 from public.point_batches
              where customer_phone = c.phone and remaining > 0 for update) x where pb.id = x.id returning pb.id, x.r0 loop
      insert into public.point_movements(customer_phone, batch_id, delta, reason, actor) values (c.phone, b.id, -b.r0, 'expire', 'account_closed');
    end loop;
    perform public._pts_sync(c.phone);
    update public.customers set name = 'حساب محذوف', last_name = null, photo_url = null, photo_hash = null, pin_hash = null,
           marketing_consent = false, data_removed_at = now() where phone = c.phone;
    perform public._audit('system', null, 'account_closed', 'customer', c.phone);
    rem := rem + 1;
  end loop;
  return jsonb_build_object('disabled', dis, 'closed', rem);
end $$;

create function public.admin_customer_reactivate_v2(p_session text, p_phone text, p_note text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; c public.customers;
begin
  a := public._sess_admin(p_session, true);
  select * into c from public.customers where phone = p_phone for update;
  if c.phone is null or c.deactivated_at is null then return jsonb_build_object('ok', false, 'error', 'not_disabled'); end if;
  if c.data_removed_at is not null then return jsonb_build_object('ok', false, 'error', 'closed', 'message', 'انتهت مهلة الأشهر الثلاثة وأُغلق الحساب'); end if;
  if p_note is null or length(trim(p_note)) < 3 then return jsonb_build_object('ok', false, 'error', 'note_required'); end if;
  update public.customers set status = 'active', deactivated_at = null, deletion_requested_at = null where phone = c.phone;
  perform public._pts_expire(c.phone);                                    -- only points still valid at their original dates remain
  perform public._audit('admin', a.id::text, 'account_reactivated', 'customer', c.phone, jsonb_build_object('note', left(trim(p_note), 300)));
  return jsonb_build_object('ok', true, 'points', public._pts_spendable(c.phone));
end $$;

-- one job for the timeline items (expiry + reminders + deletions); the Admin runs it, or a scheduler later
create function public.admin_run_jobs_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; x jsonb; y jsonb;
begin
  a := public._sess_admin(p_session, false);
  x := public.admin_run_expiry_v2(p_session);
  y := public._process_account_closures();
  perform public._audit('admin', a.id::text, 'run_jobs', null, null, jsonb_build_object('expiry', x, 'accounts', y));
  return jsonb_build_object('ok', true, 'expiry', x, 'accounts', y);
end $$;

-- ---------------------------------------------------------------- text patches
do $$
declare r record; d text; n int;
begin
  for r in select * from (values
    ('list_merchants()', 'from public.merchants where status = ''active'';',
     'from public.merchants where status = ''active'' and public._merchant_listed(id); /* B3I */'),
    ('list_merchants()', '''page_blurb'', page_blurb, ''page_enabled'', page_enabled',
     '''page_blurb'', page_blurb, ''page_enabled'', page_enabled, ''open_state'', public._shop_state(id) /* B3I */'),
    ('_tx_quote2(uuid,text,numeric,boolean,uuid,numeric)', 'n_today := (select count(*) from public.pos_transactions where customer_phone = p_phone and merchant_id = p_mid',
     'if public._shop_state(p_mid) <> ''open'' then return jsonb_build_object(''ok'', false, ''error'', ''shop_closed'', ''state'', public._shop_state(p_mid), ''message'', ''الفرع مغلق حالياً: لا عمليات نقاط جديدة''); end if; /* B3I */
  n_today := (select count(*) from public.pos_transactions where customer_phone = p_phone and merchant_id = p_mid'),
    ('admin_engine_setting_v2(text,text,numeric)', '(''pay_pending_max'', 1, 20), (''engine_strict'', 0, 1)',
     '(''pay_pending_max'', 1, 20), (''engine_strict'', 0, 1), (''sub_grace_days'', 0, 60), (''sub_enforce'', 0, 1) /* B3I */'),
    ('admin_catalog_v2(text)', '''pay_pending_max'',''engine_strict'',''rate_pts_per_usd''',
     '''pay_pending_max'',''engine_strict'',''rate_pts_per_usd'',''sub_grace_days'',''sub_enforce'' /* B3I */')) v(sig, old, new) loop
    d := coalesce((select current_setting('tp.b3i_' || md5(r.sig), true)), '');
    if d = '' then d := (select def from tp_backup.func_snapshots where batch = 'b3i' and sig = r.sig); end if;
    n := (length(d) - length(replace(d, r.old, ''))) / length(r.old);
    if n <> 1 then raise exception 'patch target found % times in %', n, r.sig; end if;
    perform set_config('tp.b3i_' || md5(r.sig), replace(d, r.old, r.new), true);
  end loop;
  for r in select distinct sig from tp_backup.func_snapshots where batch = 'b3i' loop
    execute current_setting('tp.b3i_' || md5(r.sig));
  end loop;
end $$;

do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      '_merchant_listed','_shop_state','_process_account_closures']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'merchant_hours_v2','merchant_hours_set_v2','merchant_closure_start_v2','merchant_closure_end_v2','shop_hours_public','report_shop_info_v2',
      'merchant_sub_status_v2','merchant_close_shop_request_v2','admin_closure_review_v2','admin_close_shop_v2','customer_privacy_v2',
      'customer_set_marketing_v2','customer_delete_request_v2','customer_delete_cancel_v2','admin_customer_reactivate_v2','admin_run_jobs_v2']) loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
  if not has_function_privilege('anon', 'public.list_merchants()', 'execute') then raise exception 'self-check: list_merchants lost its grant'; end if;
  if public._setting('sub_enforce', 0) <> 0 then raise exception 'self-check: sub_enforce must stay 0 on Staging'; end if;
  if (select count(*) from jsonb_array_elements(public.list_merchants())) <> (select count(*) from public.merchants where status = 'active') then
    raise exception 'self-check: a shop disappeared from the directory';
  end if;
end $$;

commit;
