-- =====================================================================================================
-- Tripoli Points — BATCH 3b: points ledger, branch allowance, catalogue, manual payments, staff, audit
-- File: security/batch3b-engine/tp-engine-v1.sql              STAGING ONLY · never Production / main
-- Requires: phase 0, batch 2 (H1, C-1, G-1) and phase 1 (tp-secure-purchase-v1.sql).
-- =====================================================================================================
-- WHAT IT DOES
--  1. Customer points ledger: every grant of points is its own batch with its own expiry
--     (earned = 3 calendar months, welcome gift = its own validity). Spending takes the batch that expires
--     first, across all kinds. customers.points stays as the cached total (kept in sync by the ledger).
--  2. Branch acceptance allowance (each merchants row = one physical branch): grants from subscriptions,
--     packages and admin adjustments, each with its own validity. Per purchase the redeemed points may not
--     exceed 70 % of the remaining valid allowance (all of it when 10 points or fewer remain). Reserved when
--     the purchase is created, consumed on confirmation, given back on cancel / expiry.
--     The legacy 70 % cap on the CUSTOMER balance (redeem_cap_pct) is no longer used by the v2 purchase.
--  3. Admin-editable catalogue: subscription plans and extra packages (price, points, period / validity).
--  4. Manual transfer payments: the merchant requests, pays outside the app, submits the transfer
--     reference; a primary admin re-types the amount and the reference he verified himself and approves.
--     One reference can never be credited twice (unique index + atomic approval).
--  5. Branch staff (employees): own PIN login, bound to one branch, with permissions.
--  6. Purchase rules: max N purchases per customer per branch per Beirut day (2), optional daily eligible
--     purchase amount per merchant tier (0 = off until the 12-Nov register values are entered).
--  7. audit_log for every money / balance / catalogue / staff action.
-- WHAT IT DOES NOT DO
--  * No drop, no delete, no truncate. Existing rows are not changed except: point batches are created for
--    customers that have points (Staging today: none), and app_sessions/pos_transactions get one new
--    nullable column (staff_id).
--  * 12 existing functions are replaced; their exact previous text is saved in tp_backup.func_snapshots
--    first and is restored by R_tp-engine-v1-rollback.sql. Each one is checked against the md5 of the
--    phase-1 text before it is replaced (the migration stops if anything differs).
--  * The old phone-based functions (create_transaction / decide_transaction ...) keep working until the
--    client switch: a trigger mirrors their balance changes into the ledger. Setting engine_strict = 1
--    (after the switch) makes any balance change outside the ledger fail.
-- PROVISIONAL (pending the 12-Nov register, all Admin-editable): legacy_points_valid_months, the daily
--   eligible amounts per tier, rounding (floor), plan / package prices and quantities (none are seeded).
-- =====================================================================================================
begin;

do $$ begin
  if to_regclass('public.app_sessions') is null or to_regprocedure('public._tx_quote(uuid,text,numeric,boolean,uuid)') is null then
    raise exception 'phase 1 (tp-secure-purchase-v1.sql) is required first';
  end if;
  if to_regclass('public.point_batches') is not null then raise exception 'batch 3b already applied (point_batches exists)'; end if;
  if to_regclass('tp_backup.settings_snapshots') is null then raise exception 'tp_backup.settings_snapshots missing (batch 2 settings step)'; end if;
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 0) Backup of every function this file replaces (exact text) + md5 guard
-- ----------------------------------------------------------------------------------------------------
create table if not exists tp_backup.func_snapshots(
  id bigserial primary key, batch text not null, sig text not null, def text not null, src_md5 text not null,
  saved_at timestamptz not null default now(), unique (batch, sig));
revoke all on table tp_backup.func_snapshots from public;
do $$ begin execute 'revoke all on table tp_backup.func_snapshots from anon, authenticated'; exception when undefined_object then null; end $$;

do $$
declare r record; cur text;
begin
  for r in select * from (values
    ('_tx_quote(uuid,text,numeric,boolean,uuid)', '5e13bd0e8388999f5a446a10470605b6'),
    ('merchant_create_tx_v2(text,uuid,numeric,boolean,uuid,jsonb,text)', 'f833efa433668e76f02f651349d7e6d9'),
    ('merchant_cancel_tx(text,uuid)', '449a180f54b76d7e5c3fbd0b0120d332'),
    ('customer_decide_tx_v2(text,uuid,boolean,text)', '72f56b65e38263c4795fb8666849c11c'),
    ('_expire_pending(text,uuid)', 'b8160caf72e071f2997cf371d3615311'),
    ('customer_check_welcome_expiry(text)', '447440451b10564270ddca7c8bdb23a1'),
    ('_sess_merchant(text)', '49cd62ddf212451d3b5380c8e157e3f2'),
    ('merchant_scan_code(text,text)', 'bbb94038f6a47676773548fb9117b711'),
    ('merchant_quote_v2(text,uuid,numeric,boolean,uuid)', '839c6c834023b6e2ac657600a652f7dd'),
    ('merchant_me_v2(text)', '08eb50bc1cd073cd50832caadc4a53f8'),
    ('merchant_transactions_v2(text)', 'd1d349e25a0082351fb7656e6139b4ca'),
    ('report_tx(text,text,uuid,uuid,text)', '53c33a1652d0b27eeadb0c702fc9d556')) v(sig, want) loop
    if to_regprocedure('public.' || r.sig) is null then raise exception 'missing function %', r.sig; end if;
    cur := (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig));
    if cur <> r.want then raise exception 'function % differs from phase 1 (md5 %), stop', r.sig, cur; end if;
    insert into tp_backup.func_snapshots(batch, sig, def, src_md5)
    values ('b3b_engine_v1', r.sig, pg_get_functiondef(to_regprocedure('public.' || r.sig)), cur)
    on conflict (batch, sig) do nothing;
  end loop;
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 1) Settings — only missing keys are added (recorded in tp_backup.settings_snapshots for the rollback)
-- ----------------------------------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select * from (values
    ('points_valid_months', 3),            -- approved: earned points expire after 3 calendar months
    ('legacy_points_valid_months', 3),     -- PROVISIONAL: opening balance of pre-ledger points (no such points on Staging)
    ('tx_per_customer_branch_day', 2),     -- approved: max purchases per customer per branch per Beirut day
    ('allowance_cap_pct', 70),             -- approved: per purchase ≤ 70 % of the remaining valid branch allowance
    ('allowance_small_threshold', 10),     -- approved: ≤ 10 points remaining → all may be used
    ('sub_carryover_months', 1),           -- approved: subscription allowance carries over 1 extra month only
    ('tier_redeem_max_small', 1000),       -- same values as the hard-coded phase-1 tier caps
    ('tier_redeem_max_medium', 2500),
    ('tier_redeem_max_large', 10000),
    ('daily_eligible_usd_small', 0),       -- PROVISIONAL: daily eligible purchase per customer per branch (0 = off)
    ('daily_eligible_usd_medium', 0),
    ('daily_eligible_usd_large', 0),
    ('pay_pending_max', 3),                -- open payment requests per branch
    ('engine_strict', 0)) v(k, val) loop   -- 1 after the client switch: balances change only through the ledger
    if not exists (select 1 from public.app_settings where key = r.k) then
      execute 'insert ' || 'into public.app_settings(key, value) values ($1, $2)' using r.k, r.val;
      insert into tp_backup.settings_snapshots(batch, tbl, key, existed, old_value, inserted_value)
      values ('b3b_engine_v1', 'app_settings', r.k, false, null, r.val::text) on conflict do nothing;
    end if;
  end loop;
  for r in select * from (values ('pay_transfer_number', ''), ('pay_transfer_instructions', '')) v(k, val) loop
    if not exists (select 1 from public.app_text_settings where key = r.k) then
      execute 'insert ' || 'into public.app_text_settings(key, value) values ($1, $2)' using r.k, r.val;
      insert into tp_backup.settings_snapshots(batch, tbl, key, existed, old_value, inserted_value)
      values ('b3b_engine_v1', 'app_text_settings', r.k, false, null, r.val) on conflict do nothing;
    end if;
  end loop;
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 2) Tables
-- ----------------------------------------------------------------------------------------------------
create table public.point_batches(
  id bigserial primary key,
  customer_phone text not null references public.customers(phone) on delete cascade on update cascade,
  kind text not null check (kind in ('welcome','earn','legacy','adjust','mirror','refund')),
  initial numeric not null check (initial > 0),
  remaining numeric not null check (remaining >= 0 and remaining <= initial),
  earned_at timestamptz not null default now(),
  expires_at timestamptz,
  tx_id uuid, merchant_id uuid, note text,
  created_at timestamptz not null default now());
create index point_batches_open_idx on public.point_batches(customer_phone, expires_at) where remaining > 0;

create table public.point_movements(
  id bigserial primary key,
  customer_phone text not null references public.customers(phone) on delete cascade on update cascade,
  batch_id bigint references public.point_batches(id) on delete cascade,
  delta numeric not null,
  reason text not null check (reason in ('welcome','earn','spend','expire','adjust','legacy','mirror','mirror_shortfall','refund')),
  tx_id uuid, actor text, at timestamptz not null default now());
create index point_movements_cust_idx on public.point_movements(customer_phone, at desc);

create table public.plans(
  code text primary key check (code ~ '^[a-z0-9_-]{2,32}$'),
  title text not null check (length(title) between 1 and 80),
  tier text check (tier in ('small','medium','large')),
  price numeric not null check (price >= 0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  allowance_pts numeric not null check (allowance_pts > 0),
  period_months integer not null check (period_months between 1 and 12),
  active boolean not null default false,
  provisional boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid);

create table public.packages(
  code text primary key check (code ~ '^[a-z0-9_-]{2,32}$'),
  title text not null check (length(title) between 1 and 80),
  price numeric not null check (price >= 0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  points numeric not null check (points > 0),
  validity_days integer not null check (validity_days between 1 and 730),
  active boolean not null default false,
  provisional boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid);

create table public.merchant_staff(
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  name text not null check (length(name) between 1 and 60),
  phone text not null unique check (phone ~ '^\d{8}$'),
  pin_hash text not null,
  perms text[] not null default array['sell']::text[]
    check (perms <@ array['sell','cancel','history','wallet','payments']::text[]),
  status text not null default 'active' check (status in ('active','disabled')),
  created_at timestamptz not null default now(), created_by text);

alter table public.app_sessions add column staff_id uuid references public.merchant_staff(id) on delete cascade;
alter table public.pos_transactions add column staff_id uuid;

create table public.payment_requests(
  id uuid primary key default gen_random_uuid(),
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  kind text not null check (kind in ('subscription','renewal','package')),
  item_code text not null,
  item jsonb not null,                             -- price / points / period as they were at request time
  amount numeric not null check (amount >= 0),
  currency text not null default 'USD',
  transfer_ref text not null check (length(transfer_ref) between 4 and 64),
  ref_norm text not null check (ref_norm ~ '^[A-Z0-9]{4,64}$'),
  evidence text check (evidence is null or length(evidence) <= 500),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  idem_key text not null check (idem_key ~ '^[A-Za-z0-9_-]{8,64}$'),
  staff_id uuid,
  created_at timestamptz not null default now(),
  decided_at timestamptz, decided_by uuid, decision_note text,
  grant_id bigint, subscription_id bigint,
  unique (merchant_id, idem_key));
-- one transfer reference can be pending or approved only once (rejected / cancelled ones may be re-submitted)
create unique index payment_requests_ref_once on public.payment_requests(ref_norm) where status in ('pending','approved');
create index payment_requests_status_idx on public.payment_requests(status, created_at);

create table public.merchant_subscriptions(
  id bigserial primary key,
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  plan_code text not null,
  period_start timestamptz not null, period_end timestamptz not null check (period_end > period_start),
  payment_request_id uuid references public.payment_requests(id),
  created_at timestamptz not null default now());
create index merchant_subscriptions_m_idx on public.merchant_subscriptions(merchant_id, period_end desc);

create table public.allowance_grants(
  id bigserial primary key,
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  source text not null check (source in ('subscription','package','adjust')),
  initial numeric not null check (initial > 0),
  remaining numeric not null check (remaining >= 0 and remaining <= initial),
  valid_from timestamptz not null default now(),
  expires_at timestamptz not null,
  plan_code text, package_code text,
  payment_request_id uuid references public.payment_requests(id),
  subscription_id bigint references public.merchant_subscriptions(id),
  granted_by uuid, note text,
  created_at timestamptz not null default now(),
  check (expires_at > valid_from));
create index allowance_grants_open_idx on public.allowance_grants(merchant_id, expires_at) where remaining > 0;

create table public.allowance_holds(
  tx_id uuid not null, grant_id bigint not null references public.allowance_grants(id) on delete cascade,
  pts numeric not null check (pts > 0),
  status text not null default 'held' check (status in ('held','consumed','released','lapsed')),
  created_at timestamptz not null default now(), closed_at timestamptz,
  primary key (tx_id, grant_id));

create table public.allowance_movements(
  id bigserial primary key,
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  grant_id bigint references public.allowance_grants(id) on delete cascade,
  delta numeric not null,               -- change of grant.remaining
  pts numeric not null default 0,       -- points concerned (consume / lapse have delta 0)
  kind text not null check (kind in ('grant','reserve','release','consume','lapse','expire','adjust')),
  tx_id uuid, actor text, at timestamptz not null default now());
create index allowance_movements_m_idx on public.allowance_movements(merchant_id, at desc);

create table public.audit_log(
  id bigserial primary key, at timestamptz not null default now(),
  actor_role text not null, actor_id text, action text not null,
  target_type text, target_id text, detail jsonb not null default '{}'::jsonb, ip text);
create index audit_log_at_idx on public.audit_log(at desc);

do $$
declare t text;
begin
  foreach t in array array['point_batches','point_movements','plans','packages','merchant_staff','payment_requests',
                           'merchant_subscriptions','allowance_grants','allowance_holds','allowance_movements','audit_log'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
  for t in select c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'S'
             and c.relname in ('point_batches_id_seq','point_movements_id_seq','merchant_subscriptions_id_seq','allowance_grants_id_seq',
                               'allowance_movements_id_seq','audit_log_id_seq') loop
    execute format('revoke all on sequence public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 3) Helpers
-- ----------------------------------------------------------------------------------------------------
create function public._audit(p_role text, p_actor text, p_action text, p_ttype text, p_tid text, p_detail jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into public.audit_log(actor_role, actor_id, action, target_type, target_id, detail, ip)
  values (p_role, p_actor, p_action, p_ttype, p_tid, coalesce(p_detail, '{}'::jsonb), public._client_ip())
$$;

create function public._day_start() returns timestamptz language sql stable set search_path = public, pg_temp as $$
  select (date_trunc('day', now() at time zone 'Asia/Beirut') at time zone 'Asia/Beirut')
$$;

create function public._ref_norm(p text) returns text language sql immutable set search_path = public, pg_temp as $$
  select nullif(regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g'), '')
$$;

create function public._ledger(p_on boolean) returns void language sql set search_path = public, pg_temp as $$
  select set_config('tp.ledger', case when p_on then '1' else '0' end, true) where true
$$;

-- ---- customer points ---------------------------------------------------------------------------------
create function public._pts_spendable(p_phone text) returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(remaining), 0) from public.point_batches
   where customer_phone = p_phone and remaining > 0 and (expires_at is null or expires_at > now())
$$;

create function public._pts_sync(p_phone text) returns numeric language plpgsql security definer set search_path = public, pg_temp as $$
declare v numeric; w numeric;
begin
  v := public._pts_spendable(p_phone);
  w := (select coalesce(sum(remaining), 0) from public.point_batches where customer_phone = p_phone and kind = 'welcome'
          and remaining > 0 and (expires_at is null or expires_at > now()));
  perform public._ledger(true);
  update public.customers set points = v, welcome_remain = w
   where phone = p_phone and (points is distinct from v or welcome_remain is distinct from w);
  perform public._ledger(false);
  return v;
end $$;

-- new batch (no sync: the caller syncs)
create function public._pts_add(p_phone text, p_pts numeric, p_kind text, p_expires timestamptz, p_tx uuid, p_mid uuid, p_actor text, p_note text)
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare b bigint;
begin
  if p_pts is null or p_pts <= 0 then return null; end if;
  insert into public.point_batches(customer_phone, kind, initial, remaining, expires_at, tx_id, merchant_id, note)
  values (p_phone, p_kind, p_pts, p_pts, p_expires, p_tx, p_mid, p_note) returning id into b;
  insert into public.point_movements(customer_phone, batch_id, delta, reason, tx_id, actor)
  values (p_phone, b, p_pts, case p_kind when 'earn' then 'earn' when 'welcome' then 'welcome' when 'legacy' then 'legacy'
                                       when 'mirror' then 'mirror' when 'refund' then 'refund' else 'adjust' end, p_tx, p_actor);
  return b;
end $$;

-- spend earliest-expiring first across all kinds; all or nothing; returns false when not enough (no sync)
create function public._pts_take(p_phone text, p_pts numeric, p_reason text, p_tx uuid, p_actor text, p_partial boolean default false)
returns numeric language plpgsql security definer set search_path = public, pg_temp as $$
declare need numeric := p_pts; b record; take numeric;
begin
  if p_pts is null or p_pts <= 0 then return 0; end if;
  perform 1 from public.point_batches where customer_phone = p_phone and remaining > 0 for update;
  if not p_partial and public._pts_spendable(p_phone) < p_pts then return -1; end if;
  for b in select id, remaining from public.point_batches
            where customer_phone = p_phone and remaining > 0 and (expires_at is null or expires_at > now())
            order by expires_at nulls last, id loop
    take := least(b.remaining, need);
    update public.point_batches set remaining = remaining - take where id = b.id;
    insert into public.point_movements(customer_phone, batch_id, delta, reason, tx_id, actor) values (p_phone, b.id, -take, p_reason, p_tx, p_actor);
    need := need - take;
    exit when need <= 0;
  end loop;
  return p_pts - need;
end $$;

-- expire due batches of one customer, sync the cached total
create function public._pts_expire(p_phone text) returns numeric language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; lost numeric := 0; lost_w numeric := 0;
begin
  for b in update public.point_batches pb set remaining = 0
            from (select id, remaining as old_rem from public.point_batches
                   where customer_phone = p_phone and remaining > 0 and expires_at is not null and expires_at <= now() for update) x
           where pb.id = x.id returning pb.id, pb.kind, x.old_rem loop
    insert into public.point_movements(customer_phone, batch_id, delta, reason, actor) values (p_phone, b.id, -b.old_rem, 'expire', 'system');
    lost := lost + b.old_rem;
    if b.kind = 'welcome' then lost_w := lost_w + b.old_rem; end if;
  end loop;
  if lost_w > 0 then
    insert into public.customer_notes(customer_phone, type, title, body)
    values (p_phone, 'points', format('انتهت صلاحية هدية الترحيب، سُحبت %s نقطة لم تُصرف', lost_w), 'تبقى معك فقط النقاط الصالحة.');
  end if;
  if lost - lost_w > 0 then
    insert into public.customer_notes(customer_phone, type, title, body)
    values (p_phone, 'points', format('انتهت صلاحية %s نقطة', lost - lost_w), 'النقاط المكتسبة صالحة 3 أشهر من تاريخ اكتسابها.');
  end if;
  perform public._pts_sync(p_phone);
  return lost;
end $$;

-- ---- guard on customers.points ---------------------------------------------------------------------
-- Ledger functions set tp.ledger = 1. Any other change: strict mode → refused; otherwise mirrored into the
-- ledger (legacy phone-based functions until they are closed).
create function public._tr_points_guard() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare d numeric; got numeric;
begin
  if coalesce(current_setting('tp.ledger', true), '0') = '1' then return new; end if;
  if public._setting('engine_strict', 0) = 1 then
    raise exception 'TP_LEDGER_ONLY: points change only through the ledger' using errcode = 'P0001';
  end if;
  d := coalesce(new.points, 0) - coalesce(old.points, 0);
  if d > 0 then
    perform public._pts_add(new.phone, d, 'mirror',
      now() + make_interval(months => public._setting('points_valid_months', 3)::int), null, null, 'legacy_fn', 'legacy function');
  elsif d < 0 then
    got := public._pts_take(new.phone, -d, 'spend', null, 'legacy_fn', true);
    if got < -d then
      insert into public.point_movements(customer_phone, delta, reason, actor) values (new.phone, -(-d - got), 'mirror_shortfall', 'legacy_fn');
      perform public._ev('ledger_mismatch', null, new.phone, null, null, null, jsonb_build_object('wanted', -d, 'taken', got));
    end if;
  end if;
  return new;
end $$;
create trigger customers_points_guard before update of points on public.customers
  for each row when (old.points is distinct from new.points) execute function public._tr_points_guard();

-- new customers (old register functions write points / welcome_remain directly): open their batches
create function public._tr_points_open() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
declare w numeric; rest numeric;
begin
  if coalesce(new.points, 0) <= 0 then return new; end if;
  w := case when new.welcome_exp is not null then least(greatest(coalesce(new.welcome_remain, 0), 0), new.points) else 0 end;
  rest := new.points - w;
  perform public._pts_add(new.phone, w, 'welcome', new.welcome_exp, null, null, 'register', 'welcome gift');
  perform public._pts_add(new.phone, rest, 'legacy',
    now() + make_interval(months => public._setting('legacy_points_valid_months', 3)::int), null, null, 'register', 'opening balance');
  return new;
end $$;
create trigger customers_points_open after insert on public.customers for each row execute function public._tr_points_open();

-- ---- branch allowance -------------------------------------------------------------------------------
create function public._allow_remaining(p_mid uuid) returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(sum(remaining), 0) from public.allowance_grants
   where merchant_id = p_mid and remaining > 0 and valid_from <= now() and expires_at > now()
$$;

create function public._allow_cap(p_remaining numeric) returns numeric language sql stable set search_path = public, pg_temp as $$
  select case when p_remaining <= 0 then 0
              when p_remaining <= public._setting('allowance_small_threshold', 10) then p_remaining
              else floor(p_remaining * public._setting('allowance_cap_pct', 70) / 100) end
$$;

create function public._allow_add(p_mid uuid, p_pts numeric, p_source text, p_from timestamptz, p_to timestamptz, p_plan text, p_pkg text,
  p_req uuid, p_sub bigint, p_by uuid, p_note text) returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare g bigint;
begin
  insert into public.allowance_grants(merchant_id, source, initial, remaining, valid_from, expires_at, plan_code, package_code,
                                      payment_request_id, subscription_id, granted_by, note)
  values (p_mid, p_source, p_pts, p_pts, p_from, p_to, p_plan, p_pkg, p_req, p_sub, p_by, p_note) returning id into g;
  insert into public.allowance_movements(merchant_id, grant_id, delta, pts, kind, actor) values (p_mid, g, p_pts, p_pts, 'grant', coalesce(p_by::text, 'system'));
  return g;
end $$;

-- reserve p_pts for a purchase, earliest-expiring grant first; false when above the cap under lock
create function public._allow_reserve(p_mid uuid, p_tx uuid, p_pts numeric) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare need numeric := p_pts; g record; take numeric;
begin
  if p_pts is null or p_pts <= 0 then return true; end if;
  perform 1 from public.allowance_grants where merchant_id = p_mid and remaining > 0 for update;
  if p_pts > public._allow_cap(public._allow_remaining(p_mid)) then return false; end if;
  for g in select id, remaining from public.allowance_grants
            where merchant_id = p_mid and remaining > 0 and valid_from <= now() and expires_at > now()
            order by expires_at, id loop
    take := least(g.remaining, need);
    update public.allowance_grants set remaining = remaining - take where id = g.id;
    insert into public.allowance_holds(tx_id, grant_id, pts) values (p_tx, g.id, take);
    insert into public.allowance_movements(merchant_id, grant_id, delta, pts, kind, tx_id, actor) values (p_mid, g.id, -take, take, 'reserve', p_tx, 'purchase');
    need := need - take;
    exit when need <= 0;
  end loop;
  return need <= 0;
end $$;

create function public._allow_consume(p_tx uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare h record;
begin
  for h in update public.allowance_holds set status = 'consumed', closed_at = now() where tx_id = p_tx and status = 'held' returning grant_id, pts loop
    insert into public.allowance_movements(merchant_id, grant_id, delta, pts, kind, tx_id, actor)
    select merchant_id, h.grant_id, 0, h.pts, 'consume', p_tx, 'purchase' from public.allowance_grants where id = h.grant_id;
  end loop;
end $$;

-- give reserved points back to their grant (or let them lapse if the grant has expired meanwhile)
create function public._allow_release(p_tx uuid, p_actor text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare h record; g public.allowance_grants;
begin
  for h in select grant_id, pts from public.allowance_holds where tx_id = p_tx and status = 'held' for update loop
    select * into g from public.allowance_grants where id = h.grant_id for update;
    if g.expires_at > now() then
      update public.allowance_grants set remaining = remaining + h.pts where id = g.id;
      update public.allowance_holds set status = 'released', closed_at = now() where tx_id = p_tx and grant_id = g.id;
      insert into public.allowance_movements(merchant_id, grant_id, delta, pts, kind, tx_id, actor) values (g.merchant_id, g.id, h.pts, h.pts, 'release', p_tx, p_actor);
    else
      update public.allowance_holds set status = 'lapsed', closed_at = now() where tx_id = p_tx and grant_id = g.id;
      insert into public.allowance_movements(merchant_id, grant_id, delta, pts, kind, tx_id, actor) values (g.merchant_id, g.id, 0, h.pts, 'lapse', p_tx, p_actor);
    end if;
  end loop;
end $$;

create function public._allow_expire(p_mid uuid) returns numeric language plpgsql security definer set search_path = public, pg_temp as $$
declare g record; n numeric := 0;
begin
  for g in update public.allowance_grants ag set remaining = 0
            from (select id, remaining as old_rem from public.allowance_grants
                   where (p_mid is null or merchant_id = p_mid) and remaining > 0 and expires_at <= now() for update) x
           where ag.id = x.id returning ag.id, ag.merchant_id, x.old_rem loop
    insert into public.allowance_movements(merchant_id, grant_id, delta, pts, kind, actor) values (g.merchant_id, g.id, -g.old_rem, g.old_rem, 'expire', 'system');
    n := n + g.old_rem;
  end loop;
  return n;
end $$;

create function public._allow_json(p_mid uuid) returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'remaining', public._allow_remaining(p_mid),
    'per_purchase_max', public._allow_cap(public._allow_remaining(p_mid)),
    'held', (select coalesce(sum(h.pts), 0) from public.allowance_holds h join public.allowance_grants g on g.id = h.grant_id
              where g.merchant_id = p_mid and h.status = 'held'),
    'grants', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'source', source, 'initial', initial, 'remaining', remaining,
                 'valid_from', floor(extract(epoch from valid_from) * 1000), 'expires_at', floor(extract(epoch from expires_at) * 1000),
                 'plan', plan_code, 'package', package_code, 'active', valid_from <= now() and expires_at > now()) order by expires_at), '[]'::jsonb)
                from public.allowance_grants where merchant_id = p_mid and (expires_at > now() - interval '60 days')),
    'subscription', (select jsonb_build_object('plan', plan_code, 'period_start', floor(extract(epoch from period_start) * 1000),
                       'period_end', floor(extract(epoch from period_end) * 1000))
                       from public.merchant_subscriptions where merchant_id = p_mid and period_end > now() order by period_start limit 1))
$$;

-- ---- branch sessions (owner or staff with a permission) ---------------------------------------------
create function public._sess_branch(p_session text, p_perm text) returns public.merchants
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; m public.merchants; st public.merchant_staff;
begin
  s := public._sess(p_session, 'merchant');
  select * into m from public.merchants where id = s.merchant_id;
  if m.id is null or m.status in ('frozen','excluded','rejected') then
    raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'account_inactive';
  end if;
  if s.staff_id is not null then
    select * into st from public.merchant_staff where id = s.staff_id;
    if st.id is null or st.status <> 'active' or st.merchant_id <> m.id then
      raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'account_inactive';
    end if;
    if p_perm is null or not (p_perm = any(st.perms)) then
      raise exception 'TP_FORBIDDEN' using errcode = 'P0001', hint = 'staff_permission';
    end if;
  end if;
  perform set_config('tp.staff_id', coalesce(s.staff_id::text, ''), true);
  return m;
end $$;

create function public._staff_id() returns uuid language sql stable set search_path = public, pg_temp as $$
  select nullif(current_setting('tp.staff_id', true), '')::uuid
$$;

-- staff PIN / status change → their sessions end
create function public._tr_staff_revoke() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.pin_hash is distinct from old.pin_hash or new.status is distinct from old.status or new.perms is distinct from old.perms then
    update public.app_sessions set revoked_at = now(), revoked_reason = 'staff_changed' where staff_id = new.id and revoked_at is null;
  end if;
  return new;
end $$;
create trigger merchant_staff_revoke after update on public.merchant_staff for each row execute function public._tr_staff_revoke();

-- ----------------------------------------------------------------------------------------------------
-- 4) Replaced phase-1 functions (previous text saved in tp_backup.func_snapshots)
-- ----------------------------------------------------------------------------------------------------
-- owner-only functions keep calling _sess_merchant: a staff session is refused there
create or replace function public._sess_merchant(p_session text) returns public.merchants
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; m public.merchants;
begin
  s := public._sess(p_session, 'merchant');
  if s.staff_id is not null then raise exception 'TP_FORBIDDEN' using errcode = 'P0001', hint = 'owner_only'; end if;
  select * into m from public.merchants where id = s.merchant_id;
  if m.id is null or m.status in ('frozen','excluded','rejected') then
    raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'account_inactive';
  end if;
  perform set_config('tp.staff_id', '', true);
  return m;
end $$;

-- the old welcome-expiry check now expires ledger batches (same note text, same effect, no double deduction)
create or replace function public.customer_check_welcome_expiry(p_phone text) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not exists (select 1 from public.customers where phone = p_phone) then return; end if;
  perform 1 from public.customers where phone = p_phone for update;
  perform public._pts_expire(p_phone);
end $$;

create or replace function public._tx_quote(p_mid uuid, p_phone text, p_invoice numeric, p_redeem boolean, p_offer_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare m public.merchants; c public.customers; o public.offers;
  rate numeric; tier_max numeric; disc numeric := 0; base numeric; vip_cap numeric; is_vip boolean;
  avail_pts numeric; allow_r numeric; allow_cap numeric; cap numeric; rp numeric; rv numeric; net numeric; bonus numeric := 0; earn numeric;
  wallet_avail numeric; n_today int; lim numeric; used numeric; eligible numeric;
begin
  select * into m from public.merchants where id = p_mid;
  if m.id is null or m.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب المحل غير فعّال'); end if;
  select * into c from public.customers where phone = p_phone;
  if c.phone is null then return jsonb_build_object('ok', false, 'error', 'هذا الحساب غير موجود'); end if;
  if c.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب الزبون مجمّد'); end if;
  if p_invoice is null or p_invoice <= 0 then return jsonb_build_object('ok', false, 'error', 'أدخل قيمة الفاتورة'); end if;
  if p_invoice > public._setting('tx_max_invoice', 100000) then return jsonb_build_object('ok', false, 'error', 'قيمة الفاتورة كبيرة جداً'); end if;
  if round(p_invoice, 2) <> p_invoice then return jsonb_build_object('ok', false, 'error', 'قيمة الفاتورة غير صحيحة'); end if;
  -- approved: max purchases per customer per branch per (Beirut) day, pending ones included
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
  disc := case when o.type = 'discount' then round(p_invoice * o.val / 100, 2) else 0 end;
  base := round(p_invoice - disc, 2);
  select cap_points into vip_cap from public.merchant_vips where merchant_id = p_mid and customer_phone = p_phone;
  is_vip := vip_cap is not null and vip_cap > 0;
  avail_pts := public._pts_spendable(p_phone);                 -- valid ledger batches only (expired gifts / points excluded)
  allow_r := public._allow_remaining(p_mid);
  allow_cap := public._allow_cap(allow_r);                       -- approved branch rule (70 % / ≤ 10 all)
  if is_vip then cap := least(avail_pts, vip_cap, floor(base * rate), allow_cap);
  else cap := least(avail_pts, floor(base * rate * coalesce(m.redeem_pct, 5) / 100), tier_max, allow_cap); end if;
  cap := greatest(0, floor(cap));
  rp := case when p_redeem then cap else 0 end;
  rv := rp / rate;
  net := round(base - rv, 2);
  -- PROVISIONAL: daily eligible purchase amount per customer per branch (0 = no limit)
  lim := public._setting('daily_eligible_usd_' || coalesce(m.tier, 'small'), 0);
  if lim > 0 then
    used := (select coalesce(sum(px.net), 0) from public.pos_transactions px where px.customer_phone = p_phone and px.merchant_id = p_mid
               and status in ('PENDING','CONFIRMED') and created_at >= public._day_start());
    eligible := greatest(0, least(net, lim - used));
  else eligible := net; end if;
  bonus := case when o.type = 'bonus' and o.per > 0 then floor(net / o.per) * o.pts else 0 end;
  earn := floor(eligible * m.pct / 100 * rate) + bonus;          -- PROVISIONAL rounding: floor
  wallet_avail := (public.merchant_wallet(p_mid)->>'avail')::numeric;
  if earn / rate > wallet_avail then return jsonb_build_object('ok', false, 'error', 'INSUFFICIENT'); end if;
  return jsonb_build_object('ok', true, 'invoice', p_invoice, 'disc', disc, 'redeem_pts', rp, 'redeem_val', rv, 'net', net,
    'bonus', bonus, 'earn', earn, 'redeem_max', cap, 'offer_id', p_offer_id, 'eligible', eligible,
    'allowance_cap', allow_cap, 'customer_points', avail_pts, 'today_count', n_today);
end $$;

create or replace function public._expire_pending(p_phone text, p_mid uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare ttl int := public._setting('tx_pending_sec', 300)::int; r record;
begin
  for r in update public.pos_transactions set status = 'EXPIRED'
            where status = 'PENDING' and created_at < now() - make_interval(secs => ttl)
              and (p_phone is null or customer_phone = p_phone) and (p_mid is null or merchant_id = p_mid)
           returning id, customer_phone, merchant_id loop
    perform public._allow_release(r.id, 'expired');
    perform public._ev('tx_expired', null, r.customer_phone, r.merchant_id, null, r.id);
  end loop;
end $$;

create or replace function public.merchant_create_tx_v2(p_session text, p_code_id uuid, p_invoice numeric, p_redeem boolean, p_offer_id uuid default null,
  p_items jsonb default '[]'::jsonb, p_idem_key text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; pc public.purchase_codes; c public.customers; q jsonb; t public.pos_transactions; v_id uuid := gen_random_uuid();
begin
  m := public._sess_branch(p_session, 'sell');
  if p_idem_key is null or p_idem_key !~ '^[A-Za-z0-9_-]{8,64}$' then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into t from public.pos_transactions where merchant_id = m.id and idem_key = p_idem_key;
  if t.id is not null then return jsonb_build_object('ok', true, 'replayed', true, 'tx', public._tx_json(t, 'merchant')); end if;
  if jsonb_typeof(coalesce(p_items, '[]'::jsonb)) <> 'array' or jsonb_array_length(coalesce(p_items, '[]'::jsonb)) > 50 then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  pc := public._claim_for(m, p_code_id, true);
  if pc.id is null then return jsonb_build_object('ok', false, 'error', 'claim_expired', 'message', 'انتهت مهلة هذا المسح. امسح رمز الزبون من جديد'); end if;
  if pc.tx_id is not null then return jsonb_build_object('ok', false, 'error', 'used', 'message', 'هذا الرمز استُعمل من قبل'); end if;
  select * into c from public.customers where phone = pc.customer_phone for update;      -- serialises purchases of one customer
  perform public._expire_pending(c.phone, null);
  perform public._pts_expire(c.phone);
  if exists (select 1 from public.pos_transactions where customer_phone = c.phone and status = 'PENDING') then
    return jsonb_build_object('ok', false, 'error', 'pending', 'message', 'لدى الزبون عملية قيد التأكيد');
  end if;
  q := public._tx_quote(m.id, c.phone, p_invoice, coalesce(p_redeem, false), p_offer_id);
  if not (q->>'ok')::boolean then return q; end if;
  t.id := v_id; t.merchant_id := m.id; t.customer_phone := c.phone; t.invoice := p_invoice;
  t.redeem_pts := (q->>'redeem_pts')::numeric; t.redeem_val := (q->>'redeem_val')::numeric; t.net := (q->>'net')::numeric;
  t.earn := (q->>'earn')::numeric; t.disc := (q->>'disc')::numeric; t.bonus := (q->>'bonus')::numeric; t.offer_id := p_offer_id;
  t.created_at := now();
  -- branch allowance: reserved now (under lock), consumed on confirmation, released on cancel / expiry
  if not public._allow_reserve(m.id, t.id, t.redeem_pts) then
    return jsonb_build_object('ok', false, 'error', 'allowance_changed', 'message', 'تغيّر رصيد قبول الفرع. أعد احتساب العملية');
  end if;
  begin
    insert into public.pos_transactions(id, merchant_id, customer_phone, invoice, redeem_pts, redeem_val, net, earn, items, status,
                                        code_id, idem_key, offer_id, disc, bonus, detail_hash, created_at, staff_id)
    values (t.id, t.merchant_id, t.customer_phone, t.invoice, t.redeem_pts, t.redeem_val, t.net, t.earn, coalesce(p_items, '[]'::jsonb), 'PENDING',
            pc.id, p_idem_key, t.offer_id, t.disc, t.bonus, public._tx_hash(t), t.created_at, public._staff_id())
    returning * into t;
  exception when unique_violation then
    perform public._allow_release(v_id, 'duplicate');
    select * into t from public.pos_transactions where merchant_id = m.id and idem_key = p_idem_key;
    if t.id is not null then return jsonb_build_object('ok', true, 'replayed', true, 'tx', public._tx_json(t, 'merchant')); end if;
    return jsonb_build_object('ok', false, 'error', 'used', 'message', 'هذا الرمز استُعمل من قبل');
  end;
  update public.purchase_codes set tx_id = t.id where id = pc.id;
  insert into public.customer_notes(customer_phone, type, title, body) values (c.phone, 'points', 'عملية بانتظار تأكيدك', m.name || ': $' || t.invoice);
  perform public._ev('tx_created', 'merchant', c.phone, m.id, pc.id, t.id,
    jsonb_build_object('invoice', t.invoice, 'redeem_pts', t.redeem_pts, 'earn', t.earn, 'staff', public._staff_id()));
  return jsonb_build_object('ok', true, 'tx', public._tx_json(t, 'merchant'));
end $$;

create or replace function public.merchant_cancel_tx(p_session text, p_tx_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; t public.pos_transactions;
begin
  m := public._sess_branch(p_session, 'cancel');
  update public.pos_transactions set status = 'CANCELLED', decided_at = now()
   where id = p_tx_id and merchant_id = m.id and status = 'PENDING' returning * into t;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_pending'); end if;
  perform public._allow_release(t.id, 'merchant_cancel');
  insert into public.customer_notes(customer_phone, type, title, body) values (t.customer_phone, 'points', 'ألغى المحل العملية', m.name || ': $' || t.invoice);
  perform public._ev('tx_cancelled_by_merchant', 'merchant', t.customer_phone, m.id, t.code_id, t.id, jsonb_build_object('staff', public._staff_id()));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.customer_decide_tx_v2(p_session text, p_tx_id uuid, p_confirm boolean, p_detail_hash text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers; t public.pos_transactions; m public.merchants; ttl int := public._setting('tx_pending_sec', 300)::int; pic jsonb;
  taken numeric; pts numeric;
begin
  c := public._sess_customer(p_session);
  if p_confirm is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if p_confirm and (p_detail_hash is null or p_detail_hash !~ '^[0-9a-f]{64}$') then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into c from public.customers where phone = c.phone for update;
  -- one atomic, conditional update: two simultaneous approvals cannot both succeed
  update public.pos_transactions set status = case when p_confirm then 'CONFIRMED' else 'CANCELLED' end, decided_at = now()
   where id = p_tx_id and customer_phone = c.phone and status = 'PENDING' and created_at > now() - make_interval(secs => ttl)
     and (not p_confirm or detail_hash = p_detail_hash)
  returning * into t;
  if t.id is null then
    select * into t from public.pos_transactions where id = p_tx_id and customer_phone = c.phone;
    if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found', 'message', 'العملية غير موجودة'); end if;
    if t.status = 'PENDING' and t.created_at <= now() - make_interval(secs => ttl) then
      update public.pos_transactions set status = 'EXPIRED' where id = t.id and status = 'PENDING';
      perform public._allow_release(t.id, 'expired');
      perform public._ev('tx_expired', 'customer', c.phone, t.merchant_id, t.code_id, t.id);
      return jsonb_build_object('ok', false, 'error', 'expired', 'message', 'انتهت مهلة العملية');
    end if;
    if t.status = 'PENDING' then
      perform public._ev('decide_hash_mismatch', 'customer', c.phone, t.merchant_id, t.code_id, t.id);
      return jsonb_build_object('ok', false, 'error', 'details_changed', 'message', 'تفاصيل العملية تغيّرت. راجعها من جديد', 'tx', public._tx_json(t, 'customer'));
    end if;
    return jsonb_build_object('ok', false, 'error', 'already_decided', 'status', t.status, 'message', 'تم البت في هذه العملية من قبل');
  end if;
  select * into m from public.merchants where id = t.merchant_id;
  if p_confirm then
    perform public._pts_expire(c.phone);
    if t.redeem_pts > 0 then
      taken := public._pts_take(c.phone, t.redeem_pts, 'spend', t.id, 'customer');
      if taken < t.redeem_pts then      -- points expired since the purchase was created: nothing is applied
        update public.pos_transactions set status = 'CANCELLED' where id = t.id;
        perform public._allow_release(t.id, 'insufficient_points');
        perform public._ev('tx_insufficient_points', 'customer', c.phone, t.merchant_id, t.code_id, t.id,
          jsonb_build_object('redeem_pts', t.redeem_pts, 'spendable', public._pts_spendable(c.phone)));
        insert into public.merchant_notes(merchant_id, type, title, body) values (t.merchant_id, 'warn', 'أُلغيت العملية: رصيد الزبون الصالح لم يعد يكفي', null);
        return jsonb_build_object('ok', false, 'error', 'insufficient_points', 'message', 'رصيدك الصالح لم يعد يكفي لهذه العملية. اطلب من المحل إعادتها');
      end if;
    end if;
    perform public._pts_add(c.phone, t.earn, 'earn', now() + make_interval(months => public._setting('points_valid_months', 3)::int),
                            t.id, t.merchant_id, 'customer', null);
    perform public._allow_consume(t.id);
    pts := public._pts_sync(c.phone);
    select * into c from public.customers where phone = c.phone;
  else
    perform public._allow_release(t.id, 'customer_reject');
  end if;
  insert into public.merchant_notes(merchant_id, type, title, body) values (t.merchant_id,
    case when p_confirm then 'sale' else 'warn' end,
    case when p_confirm then format('تم تأكيد عملية بقيمة $%s', t.invoice) else 'ألغى الزبون العملية' end,
    case when c.name = 'زبون جديد' then null else c.name end);
  if p_confirm then
    if t.redeem_pts > 0 then insert into public.customer_notes(customer_phone, type, title, body) values (c.phone, 'points', format('تم استخدام %s نقطة', t.redeem_pts), m.name); end if;
    if t.earn > 0 then insert into public.customer_notes(customer_phone, type, title, body) values (c.phone, 'points', format('تمت إضافة %s نقطة', t.earn), m.name); end if;
    pic := public._unlock_treasure(t);
    perform public._ev('tx_confirmed', 'customer', c.phone, t.merchant_id, t.code_id, t.id, jsonb_build_object('invoice', t.invoice, 'treasure', pic is not null));
    perform public._alerts_after_confirm(t);
  else
    perform public._ev('tx_rejected', 'customer', c.phone, t.merchant_id, t.code_id, t.id);
  end if;
  return jsonb_build_object('ok', true, 'status', t.status, 'points', c.points, 'unlocked', pic);
end $$;

-- text patches: the branch functions accept staff sessions with the right permission
do $$
declare r record; d text; n int;
begin
  for r in select * from (values
      ('merchant_scan_code(text,text)', 'm := public._sess_merchant(p_session);', 'm := public._sess_branch(p_session, ''sell'');'),
      ('merchant_quote_v2(text,uuid,numeric,boolean,uuid)', 'm := public._sess_merchant(p_session);', 'm := public._sess_branch(p_session, ''sell'');'),
      ('merchant_me_v2(text)', 'm := public._sess_merchant(p_session);', 'm := public._sess_branch(p_session, ''sell'');'),
      ('merchant_transactions_v2(text)', 'm := public._sess_merchant(p_session);', 'm := public._sess_branch(p_session, ''history'');'),
      ('report_tx(text,text,uuid,uuid,text)', 'perform public._sess_merchant(p_session);', 'perform public._sess_branch(p_session, ''sell'');')) v(sig, old, new) loop
    d := (select def from tp_backup.func_snapshots where batch = 'b3b_engine_v1' and sig = r.sig);
    n := (length(d) - length(replace(d, r.old, ''))) / length(r.old);
    if n <> 1 then raise exception 'patch target found % times in %', n, r.sig; end if;
    execute replace(d, r.old, r.new || ' /* B3B */');
  end loop;
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 5) Staff (employees)
-- ----------------------------------------------------------------------------------------------------
create function public.staff_login(p_phone text, p_pin text, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare st public.merchant_staff; m public.merchants; s jsonb;
begin
  if p_phone is null or p_phone !~ '^\d{8}$' then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if not public._login_allowed('staff:' || p_phone) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into st from public.merchant_staff where phone = p_phone;
  if st.id is null or extensions.crypt(coalesce(p_pin, ''), st.pin_hash) <> st.pin_hash then
    perform public._login_failed('staff:' || p_phone);
    perform public._ev('login_failed', 'staff', null, st.merchant_id, null, null);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  select * into m from public.merchants where id = st.merchant_id;
  if st.status <> 'active' or m.status in ('frozen','excluded','rejected') then return jsonb_build_object('ok', false, 'reason', 'frozen'); end if;
  perform public._rl_reset('staff:' || p_phone);
  s := public._issue_session('merchant', null, m.id, null, p_device);
  update public.app_sessions set staff_id = st.id where token_hash = public._sha(s->>'session');
  perform public._audit('staff', st.id::text, 'staff_login', 'merchant', m.id::text);
  return jsonb_build_object('ok', true, 'merchant', public._merchant_json(m),
    'staff', jsonb_build_object('id', st.id, 'name', st.name, 'perms', st.perms)) || s;
end $$;

create function public._staff_json(st public.merchant_staff) returns jsonb language sql stable set search_path = public, pg_temp as $$
  select jsonb_build_object('id', st.id, 'name', st.name, 'phone', st.phone, 'perms', st.perms, 'status', st.status,
    'created_at', floor(extract(epoch from st.created_at) * 1000))
$$;

create function public.merchant_staff_list_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return jsonb_build_object('ok', true, 'staff', (select coalesce(jsonb_agg(public._staff_json(s) order by s.created_at), '[]'::jsonb)
                                                    from public.merchant_staff s where s.merchant_id = m.id));
end $$;

-- create (p_id null, PIN required) or update (name / perms / active / new PIN) — owner only
create function public.merchant_staff_save_v2(p_session text, p_id uuid, p_name text, p_phone text, p_pin text, p_perms text[], p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.merchants; st public.merchant_staff;
begin
  m := public._sess_merchant(p_session);
  if p_name is null or length(trim(p_name)) not between 1 and 60 then return jsonb_build_object('ok', false, 'error', 'bad_name'); end if;
  if p_perms is null or not (p_perms <@ array['sell','cancel','history','wallet','payments']::text[]) then return jsonb_build_object('ok', false, 'error', 'bad_perms'); end if;
  if p_pin is not null and p_pin !~ '^\d{4,6}$' then return jsonb_build_object('ok', false, 'error', 'bad_pin'); end if;
  if p_id is null then
    if p_phone is null or p_phone !~ '^\d{8}$' then return jsonb_build_object('ok', false, 'error', 'bad_phone'); end if;
    if p_pin is null then return jsonb_build_object('ok', false, 'error', 'bad_pin'); end if;
    if (select count(*) from public.merchant_staff where merchant_id = m.id) >= 20 then return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
    begin
      insert into public.merchant_staff(merchant_id, name, phone, pin_hash, perms, status, created_by)
      values (m.id, trim(p_name), p_phone, extensions.crypt(p_pin, extensions.gen_salt('bf')), p_perms,
              case when coalesce(p_active, true) then 'active' else 'disabled' end, m.id::text) returning * into st;
    exception when unique_violation then return jsonb_build_object('ok', false, 'error', 'phone_taken');
    end;
  else
    update public.merchant_staff set name = trim(p_name), perms = p_perms,
           status = case when coalesce(p_active, true) then 'active' else 'disabled' end,
           pin_hash = case when p_pin is null then pin_hash else extensions.crypt(p_pin, extensions.gen_salt('bf')) end
     where id = p_id and merchant_id = m.id returning * into st;
    if st.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  perform public._audit('merchant', m.id::text, case when p_id is null then 'staff_create' else 'staff_update' end, 'staff', st.id::text,
    jsonb_build_object('perms', st.perms, 'status', st.status, 'pin_changed', p_pin is not null));
  return jsonb_build_object('ok', true, 'staff', public._staff_json(st));
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 6) Customer
-- ----------------------------------------------------------------------------------------------------
create function public.customer_points_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers;
begin
  c := public._sess_customer(p_session);
  perform 1 from public.customers where phone = c.phone for update;
  perform public._pts_expire(c.phone);
  return jsonb_build_object('ok', true, 'points', public._pts_spendable(c.phone),
    'batches', (select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'initial', initial, 'remaining', remaining,
                  'earned_at', floor(extract(epoch from earned_at) * 1000),
                  'expires_at', case when expires_at is null then null else floor(extract(epoch from expires_at) * 1000) end,
                  'shop', (select name from public.merchants where id = b.merchant_id)) order by expires_at nulls last, id), '[]'::jsonb)
                from public.point_batches b where customer_phone = c.phone and remaining > 0),
    'next_expiry', (select jsonb_build_object('points', sum(remaining), 'at', floor(extract(epoch from min(expires_at)) * 1000))
                      from public.point_batches where customer_phone = c.phone and remaining > 0
                       and expires_at = (select min(expires_at) from public.point_batches where customer_phone = c.phone and remaining > 0 and expires_at > now())),
    'movements', (select coalesce(jsonb_agg(jsonb_build_object('delta', delta, 'reason', reason, 'at', floor(extract(epoch from at) * 1000)) order by at desc, id desc), '[]'::jsonb)
                  from (select * from public.point_movements where customer_phone = c.phone order by at desc, id desc limit 100) x));
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 7) Merchant: allowance, catalogue, payment requests
-- ----------------------------------------------------------------------------------------------------
create function public.merchant_allowance_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_branch(p_session, 'wallet');
  perform public._expire_pending(null, m.id);
  perform public._allow_expire(m.id);
  return jsonb_build_object('ok', true) || public._allow_json(m.id);
end $$;

create function public.merchant_catalog_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_branch(p_session, 'payments');
  return jsonb_build_object('ok', true,
    'transfer_number', (select value from public.app_text_settings where key = 'pay_transfer_number'),
    'transfer_instructions', (select value from public.app_text_settings where key = 'pay_transfer_instructions'),
    'plans', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'title', title, 'tier', tier, 'price', price, 'currency', currency,
               'allowance_pts', allowance_pts, 'period_months', period_months, 'provisional', provisional) order by price), '[]'::jsonb)
              from public.plans where active and (tier is null or tier = m.tier)),
    'packages', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'title', title, 'price', price, 'currency', currency,
               'points', points, 'validity_days', validity_days, 'provisional', provisional) order by price), '[]'::jsonb)
              from public.packages where active),
    'subscription', public._allow_json(m.id)->'subscription');
end $$;

create function public._payreq_json(r public.payment_requests, p_admin boolean) returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('id', r.id, 'kind', r.kind, 'item_code', r.item_code, 'item', r.item, 'amount', r.amount, 'currency', r.currency,
    'transfer_ref', r.transfer_ref, 'evidence', r.evidence, 'status', r.status, 'decision_note', r.decision_note,
    'created_at', floor(extract(epoch from r.created_at) * 1000),
    'decided_at', case when r.decided_at is null then null else floor(extract(epoch from r.decided_at) * 1000) end)
  || case when p_admin then jsonb_build_object('merchant_id', r.merchant_id, 'merchant', (select jsonb_build_object('name', name, 'phone', phone, 'tier', tier)
                                    from public.merchants where id = r.merchant_id), 'decided_by', r.decided_by,
                                    'ref_used_before', (select count(*) from public.payment_requests x where x.ref_norm = r.ref_norm and x.id <> r.id))
     else '{}'::jsonb end
$$;

create function public.merchant_payment_request_v2(p_session text, p_kind text, p_item_code text, p_transfer_ref text,
  p_evidence text default null, p_idem_key text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; pl public.plans; pk public.packages; r public.payment_requests; item jsonb; amt numeric; cur text; rn text;
begin
  m := public._sess_branch(p_session, 'payments');
  if p_idem_key is null or p_idem_key !~ '^[A-Za-z0-9_-]{8,64}$' then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into r from public.payment_requests where merchant_id = m.id and idem_key = p_idem_key;
  if r.id is not null then return jsonb_build_object('ok', true, 'replayed', true, 'request', public._payreq_json(r, false)); end if;
  if coalesce(trim((select value from public.app_text_settings where key = 'pay_transfer_number')), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'payments_closed', 'message', 'الدفع غير متاح حالياً');
  end if;
  if p_kind not in ('subscription','renewal','package') then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  rn := public._ref_norm(p_transfer_ref);
  if rn is null or length(rn) < 4 or length(rn) > 64 or length(p_transfer_ref) > 64 then
    return jsonb_build_object('ok', false, 'error', 'bad_ref', 'message', 'أدخل رقم مرجع التحويل كما يظهر في الإيصال');
  end if;
  if p_evidence is not null and length(p_evidence) > 500 then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if p_kind in ('subscription','renewal') then
    select * into pl from public.plans where code = p_item_code and active;
    if pl.code is null or (pl.tier is not null and pl.tier <> m.tier) then return jsonb_build_object('ok', false, 'error', 'item_unavailable'); end if;
    item := jsonb_build_object('title', pl.title, 'price', pl.price, 'currency', pl.currency, 'allowance_pts', pl.allowance_pts,
              'period_months', pl.period_months, 'provisional', pl.provisional);
    amt := pl.price; cur := pl.currency;
  else
    select * into pk from public.packages where code = p_item_code and active;
    if pk.code is null then return jsonb_build_object('ok', false, 'error', 'item_unavailable'); end if;
    item := jsonb_build_object('title', pk.title, 'price', pk.price, 'currency', pk.currency, 'points', pk.points,
              'validity_days', pk.validity_days, 'provisional', pk.provisional);
    amt := pk.price; cur := pk.currency;
  end if;
  if (select count(*) from public.payment_requests where merchant_id = m.id and status = 'pending') >= public._setting('pay_pending_max', 3) then
    return jsonb_build_object('ok', false, 'error', 'too_many_pending', 'message', 'لديك طلبات قيد المراجعة');
  end if;
  begin
    insert into public.payment_requests(merchant_id, kind, item_code, item, amount, currency, transfer_ref, ref_norm, evidence, idem_key, staff_id)
    values (m.id, p_kind, p_item_code, item, amt, cur, trim(p_transfer_ref), rn, nullif(trim(p_evidence), ''), p_idem_key, public._staff_id())
    returning * into r;
  exception when unique_violation then
    select * into r from public.payment_requests where merchant_id = m.id and idem_key = p_idem_key;
    if r.id is not null then return jsonb_build_object('ok', true, 'replayed', true, 'request', public._payreq_json(r, false)); end if;
    perform public._audit('merchant', m.id::text, 'payment_duplicate_ref', 'payment_ref', rn);
    return jsonb_build_object('ok', false, 'error', 'duplicate_ref', 'message', 'رقم المرجع هذا مستعمل في طلب آخر');
  end;
  perform public._audit(case when public._staff_id() is null then 'merchant' else 'staff' end, coalesce(public._staff_id(), m.id)::text,
    'payment_request', 'payment_request', r.id::text, jsonb_build_object('kind', r.kind, 'item', r.item_code, 'amount', r.amount));
  return jsonb_build_object('ok', true, 'request', public._payreq_json(r, false));
end $$;

create function public.merchant_payment_requests_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_branch(p_session, 'payments');
  return jsonb_build_object('ok', true, 'requests', (select coalesce(jsonb_agg(public._payreq_json(r, false) order by r.created_at desc), '[]'::jsonb)
                                                       from (select * from public.payment_requests where merchant_id = m.id order by created_at desc limit 100) r));
end $$;

create function public.merchant_payment_cancel_v2(p_session text, p_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; r public.payment_requests;
begin
  m := public._sess_branch(p_session, 'payments');
  update public.payment_requests set status = 'cancelled', decided_at = now() where id = p_id and merchant_id = m.id and status = 'pending' returning * into r;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_pending'); end if;
  perform public._audit('merchant', m.id::text, 'payment_cancel', 'payment_request', r.id::text);
  return jsonb_build_object('ok', true);
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 8) Admin
-- ----------------------------------------------------------------------------------------------------
create function public.admin_catalog_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
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
       'tier_redeem_max_medium','tier_redeem_max_large','daily_eligible_usd_small','daily_eligible_usd_medium','daily_eligible_usd_large',
       'pay_pending_max','engine_strict','rate_pts_per_usd')));
end $$;

create function public.admin_plan_save_v2(p_session text, p_code text, p_title text, p_tier text, p_price numeric, p_allowance_pts numeric,
  p_period_months integer, p_active boolean, p_provisional boolean default true, p_currency text default 'USD') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; old jsonb; p public.plans;
begin
  a := public._sess_admin(p_session, true);
  if p_code is null or p_code !~ '^[a-z0-9_-]{2,32}$' or p_title is null or length(trim(p_title)) not between 1 and 80
     or (p_tier is not null and p_tier not in ('small','medium','large')) or p_price is null or p_price < 0 or p_price > 100000
     or p_allowance_pts is null or p_allowance_pts <= 0 or p_allowance_pts > 100000000 or p_period_months is null or p_period_months not between 1 and 12
     or coalesce(p_currency, 'USD') !~ '^[A-Z]{3}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  old := (select to_jsonb(x) from public.plans x where code = p_code);
  insert into public.plans as t(code, title, tier, price, currency, allowance_pts, period_months, active, provisional, updated_at, updated_by)
  values (p_code, trim(p_title), p_tier, p_price, coalesce(p_currency, 'USD'), p_allowance_pts, p_period_months, coalesce(p_active, false),
          coalesce(p_provisional, true), now(), a.id)
  on conflict (code) do update set title = excluded.title, tier = excluded.tier, price = excluded.price, currency = excluded.currency,
     allowance_pts = excluded.allowance_pts, period_months = excluded.period_months, active = excluded.active,
     provisional = excluded.provisional, updated_at = now(), updated_by = a.id
  returning * into p;
  perform public._audit('admin', a.id::text, 'plan_save', 'plan', p.code, jsonb_build_object('before', old, 'after', to_jsonb(p)));
  return jsonb_build_object('ok', true, 'plan', to_jsonb(p));
end $$;

create function public.admin_package_save_v2(p_session text, p_code text, p_title text, p_price numeric, p_points numeric,
  p_validity_days integer, p_active boolean, p_provisional boolean default true, p_currency text default 'USD') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; old jsonb; p public.packages;
begin
  a := public._sess_admin(p_session, true);
  if p_code is null or p_code !~ '^[a-z0-9_-]{2,32}$' or p_title is null or length(trim(p_title)) not between 1 and 80
     or p_price is null or p_price < 0 or p_price > 100000 or p_points is null or p_points <= 0 or p_points > 100000000
     or p_validity_days is null or p_validity_days not between 1 and 730 or coalesce(p_currency, 'USD') !~ '^[A-Z]{3}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  old := (select to_jsonb(x) from public.packages x where code = p_code);
  insert into public.packages as t(code, title, price, currency, points, validity_days, active, provisional, updated_at, updated_by)
  values (p_code, trim(p_title), p_price, coalesce(p_currency, 'USD'), p_points, p_validity_days, coalesce(p_active, false), coalesce(p_provisional, true), now(), a.id)
  on conflict (code) do update set title = excluded.title, price = excluded.price, currency = excluded.currency, points = excluded.points,
     validity_days = excluded.validity_days, active = excluded.active, provisional = excluded.provisional, updated_at = now(), updated_by = a.id
  returning * into p;
  perform public._audit('admin', a.id::text, 'package_save', 'package', p.code, jsonb_build_object('before', old, 'after', to_jsonb(p)));
  return jsonb_build_object('ok', true, 'package', to_jsonb(p));
end $$;

create function public.admin_pay_settings_v2(p_session text, p_transfer_number text, p_instructions text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; old jsonb;
begin
  a := public._sess_admin(p_session, true);
  if p_transfer_number is null or length(p_transfer_number) > 64 or p_instructions is null or length(p_instructions) > 1000 then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  old := (select jsonb_object_agg(key, value) from public.app_text_settings where key in ('pay_transfer_number','pay_transfer_instructions'));
  insert into public.app_text_settings(key, value) values ('pay_transfer_number', trim(p_transfer_number)), ('pay_transfer_instructions', trim(p_instructions))
  on conflict (key) do update set value = excluded.value;
  perform public._audit('admin', a.id::text, 'pay_settings', 'settings', 'pay', jsonb_build_object('before', old,
    'after', jsonb_build_object('pay_transfer_number', trim(p_transfer_number), 'pay_transfer_instructions', trim(p_instructions))));
  return jsonb_build_object('ok', true);
end $$;

-- engine settings (bounded); the generic admin_set_setting_v2 does not know these keys
create function public.admin_engine_setting_v2(p_session text, p_key text, p_value numeric) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; lo numeric; hi numeric; old numeric;
begin
  a := public._sess_admin(p_session, true);
  select x.lo, x.hi into lo, hi from (values ('points_valid_months', 1, 24), ('legacy_points_valid_months', 1, 24), ('tx_per_customer_branch_day', 1, 20),
    ('allowance_cap_pct', 1, 100), ('allowance_small_threshold', 0, 1000), ('sub_carryover_months', 0, 6),
    ('tier_redeem_max_small', 0, 1000000), ('tier_redeem_max_medium', 0, 1000000), ('tier_redeem_max_large', 0, 1000000),
    ('daily_eligible_usd_small', 0, 100000), ('daily_eligible_usd_medium', 0, 100000), ('daily_eligible_usd_large', 0, 100000),
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

create function public.admin_payment_requests_v2(p_session text, p_status text default 'pending') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  return jsonb_build_object('ok', true, 'requests', (select coalesce(jsonb_agg(public._payreq_json(r, true) order by r.created_at), '[]'::jsonb)
    from (select * from public.payment_requests where p_status is null or status = p_status order by created_at desc limit 300) r));
end $$;

-- the admin re-types the amount and the reference he verified himself; one atomic approval per request
create function public.admin_payment_decide_v2(p_session text, p_id uuid, p_approve boolean, p_verified_amount numeric default null,
  p_verified_ref text default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r public.payment_requests; sub_start timestamptz; sub_end timestamptz; sid bigint; gid bigint; m public.merchants;
begin
  a := public._sess_admin(p_session, true);
  if p_approve is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into r from public.payment_requests where id = p_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'pending' then return jsonb_build_object('ok', false, 'error', 'already_decided', 'status', r.status); end if;
  select * into m from public.merchants where id = r.merchant_id;
  if not p_approve then
    if p_note is null or length(trim(p_note)) < 3 then return jsonb_build_object('ok', false, 'error', 'note_required'); end if;
    update public.payment_requests set status = 'rejected', decided_at = now(), decided_by = a.id, decision_note = left(trim(p_note), 500)
     where id = r.id returning * into r;
    insert into public.merchant_notes(merchant_id, type, title, body, severity) values (r.merchant_id, 'warn', 'رُفض طلب الدفع', r.decision_note, 'warn');
    perform public._audit('admin', a.id::text, 'payment_reject', 'payment_request', r.id::text, jsonb_build_object('note', r.decision_note));
    return jsonb_build_object('ok', true, 'status', r.status);
  end if;
  if p_verified_amount is null or p_verified_amount <> r.amount then
    perform public._audit('admin', a.id::text, 'payment_amount_mismatch', 'payment_request', r.id::text, jsonb_build_object('typed', p_verified_amount));
    return jsonb_build_object('ok', false, 'error', 'amount_mismatch', 'message', 'المبلغ المُتحقَّق منه لا يطابق الطلب');
  end if;
  if public._ref_norm(p_verified_ref) is distinct from r.ref_norm then
    perform public._audit('admin', a.id::text, 'payment_ref_mismatch', 'payment_request', r.id::text);
    return jsonb_build_object('ok', false, 'error', 'ref_mismatch', 'message', 'رقم المرجع المُتحقَّق منه لا يطابق الطلب');
  end if;
  if exists (select 1 from public.payment_requests where ref_norm = r.ref_norm and status = 'approved' and id <> r.id) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_ref');
  end if;
  if m.id is null or m.status in ('frozen','excluded','rejected') then return jsonb_build_object('ok', false, 'error', 'merchant_inactive'); end if;
  if r.kind in ('subscription','renewal') then
    perform 1 from public.merchants where id = r.merchant_id for update;      -- serialises periods of one branch
    sub_start := greatest(now(), coalesce((select max(period_end) from public.merchant_subscriptions where merchant_id = r.merchant_id), now()));
    sub_end := sub_start + make_interval(months => (r.item->>'period_months')::int);
    insert into public.merchant_subscriptions(merchant_id, plan_code, period_start, period_end, payment_request_id)
    values (r.merchant_id, r.item_code, sub_start, sub_end, r.id) returning id into sid;
    gid := public._allow_add(r.merchant_id, (r.item->>'allowance_pts')::numeric, 'subscription', sub_start,
             sub_end + make_interval(months => public._setting('sub_carryover_months', 1)::int), r.item_code, null, r.id, sid, a.id, null);
  else
    gid := public._allow_add(r.merchant_id, (r.item->>'points')::numeric, 'package', now(),
             now() + make_interval(days => (r.item->>'validity_days')::int), null, r.item_code, r.id, null, a.id, null);
  end if;
  update public.payment_requests set status = 'approved', decided_at = now(), decided_by = a.id, decision_note = nullif(left(trim(coalesce(p_note, '')), 500), ''),
         grant_id = gid, subscription_id = sid where id = r.id returning * into r;
  insert into public.merchant_notes(merchant_id, type, title, body, severity)
  values (r.merchant_id, 'info', 'تم اعتماد الدفع', format('%s — رصيد قبول %s نقطة', r.item->>'title', coalesce(r.item->>'allowance_pts', r.item->>'points')), 'info');
  perform public._audit('admin', a.id::text, 'payment_approve', 'payment_request', r.id::text,
    jsonb_build_object('merchant', r.merchant_id, 'amount', r.amount, 'grant', gid, 'subscription', sid, 'kind', r.kind, 'item', r.item_code));
  return jsonb_build_object('ok', true, 'status', r.status, 'grant_id', gid, 'subscription_id', sid);
end $$;

create function public.admin_merchant_allowance_v2(p_session text, p_merchant_id uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  if not exists (select 1 from public.merchants where id = p_merchant_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true) || public._allow_json(p_merchant_id) || jsonb_build_object(
    'movements', (select coalesce(jsonb_agg(jsonb_build_object('grant', grant_id, 'delta', delta, 'pts', pts, 'kind', kind, 'tx', tx_id, 'actor', actor,
                    'at', floor(extract(epoch from at) * 1000)) order by at desc, id desc), '[]'::jsonb)
                  from (select * from public.allowance_movements where merchant_id = p_merchant_id order by at desc, id desc limit 200) x),
    'staff', (select coalesce(jsonb_agg(public._staff_json(s)), '[]'::jsonb) from public.merchant_staff s where s.merchant_id = p_merchant_id));
end $$;

-- manual correction of a branch allowance (+ new grant / − earliest-expiring first), reason required
create function public.admin_allowance_adjust_v2(p_session text, p_merchant_id uuid, p_points numeric, p_valid_days integer, p_note text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; need numeric; g record; take numeric; gid bigint;
begin
  a := public._sess_admin(p_session, true);
  if p_points is null or p_points = 0 or p_points <> round(p_points) or abs(p_points) > 10000000 or p_note is null or length(trim(p_note)) < 3 then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  if not exists (select 1 from public.merchants where id = p_merchant_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_points > 0 then
    if p_valid_days is null or p_valid_days not between 1 and 730 then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
    gid := public._allow_add(p_merchant_id, p_points, 'adjust', now(), now() + make_interval(days => p_valid_days), null, null, null, null, a.id, left(trim(p_note), 300));
  else
    perform 1 from public.allowance_grants where merchant_id = p_merchant_id and remaining > 0 for update;
    if public._allow_remaining(p_merchant_id) < -p_points then return jsonb_build_object('ok', false, 'error', 'insufficient'); end if;
    need := -p_points;
    for g in select id, remaining from public.allowance_grants where merchant_id = p_merchant_id and remaining > 0 and valid_from <= now() and expires_at > now()
              order by expires_at, id loop
      take := least(g.remaining, need);
      update public.allowance_grants set remaining = remaining - take where id = g.id;
      insert into public.allowance_movements(merchant_id, grant_id, delta, pts, kind, actor) values (p_merchant_id, g.id, -take, take, 'adjust', a.id::text);
      need := need - take; exit when need <= 0;
    end loop;
  end if;
  perform public._audit('admin', a.id::text, 'allowance_adjust', 'merchant', p_merchant_id::text,
    jsonb_build_object('points', p_points, 'valid_days', p_valid_days, 'note', left(trim(p_note), 300), 'grant', gid));
  return jsonb_build_object('ok', true, 'remaining', public._allow_remaining(p_merchant_id));
end $$;

create function public.admin_customer_points_v2(p_session text, p_phone text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  if not exists (select 1 from public.customers where phone = p_phone) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'spendable', public._pts_spendable(p_phone),
    'cached', (select points from public.customers where phone = p_phone),
    'batches', (select coalesce(jsonb_agg(to_jsonb(b) order by b.expires_at nulls last, b.id), '[]'::jsonb) from public.point_batches b where customer_phone = p_phone),
    'movements', (select coalesce(jsonb_agg(to_jsonb(x) order by x.at desc, x.id desc), '[]'::jsonb)
                  from (select * from public.point_movements where customer_phone = p_phone order by at desc, id desc limit 200) x));
end $$;

-- manual correction of customer points (+ new 'adjust' batch with the normal validity / − earliest-expiring first)
create function public.admin_points_adjust_v2(p_session text, p_phone text, p_points numeric, p_note text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; got numeric;
begin
  a := public._sess_admin(p_session, true);
  if p_points is null or p_points = 0 or p_points <> round(p_points) or abs(p_points) > 1000000 or p_note is null or length(trim(p_note)) < 3 then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  perform 1 from public.customers where phone = p_phone for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform public._pts_expire(p_phone);
  if p_points > 0 then
    perform public._pts_add(p_phone, p_points, 'adjust', now() + make_interval(months => public._setting('points_valid_months', 3)::int),
                            null, null, a.id::text, left(trim(p_note), 300));
  else
    got := public._pts_take(p_phone, -p_points, 'adjust', null, a.id::text);
    if got < 0 then return jsonb_build_object('ok', false, 'error', 'insufficient'); end if;
  end if;
  perform public._audit('admin', a.id::text, 'points_adjust', 'customer', p_phone, jsonb_build_object('points', p_points, 'note', left(trim(p_note), 300)));
  return jsonb_build_object('ok', true, 'points', public._pts_sync(p_phone));
end $$;

create function public.admin_run_expiry_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r record; pts numeric := 0; n int := 0; al numeric;
begin
  a := public._sess_admin(p_session, false);
  perform public._expire_pending(null, null);
  for r in select distinct customer_phone from public.point_batches where remaining > 0 and expires_at <= now() loop
    perform 1 from public.customers where phone = r.customer_phone for update;
    pts := pts + public._pts_expire(r.customer_phone); n := n + 1;
  end loop;
  al := public._allow_expire(null);
  perform public._audit('admin', a.id::text, 'run_expiry', null, null, jsonb_build_object('customers', n, 'points', pts, 'allowance', al));
  return jsonb_build_object('ok', true, 'customers', n, 'points_expired', pts, 'allowance_expired', al);
end $$;

create function public.admin_audit_log_v2(p_session text, p_limit integer default 200) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  return jsonb_build_object('ok', true, 'log', (select coalesce(jsonb_agg(jsonb_build_object('at', floor(extract(epoch from at) * 1000), 'role', actor_role,
     'actor', actor_id, 'action', action, 'target_type', target_type, 'target', target_id, 'detail', detail) order by at desc, id desc), '[]'::jsonb)
     from (select * from public.audit_log order by at desc, id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) x));
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 9) Opening balances: one batch per customer that already has points (Staging today: none)
-- ----------------------------------------------------------------------------------------------------
do $$
declare c record; w numeric;
begin
  for c in select phone, points, welcome_remain, welcome_exp from public.customers where coalesce(points, 0) > 0 loop
    w := case when c.welcome_exp is not null then least(greatest(coalesce(c.welcome_remain, 0), 0), c.points) else 0 end;
    perform public._pts_add(c.phone, w, 'welcome', c.welcome_exp, null, null, 'migration', 'welcome gift (opening)');
    perform public._pts_add(c.phone, c.points - w, 'legacy',
      now() + make_interval(months => public._setting('legacy_points_valid_months', 3)::int), null, null, 'migration', 'opening balance');
  end loop;
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 10) Privileges: helpers unreachable, API functions for anon/authenticated only
-- ----------------------------------------------------------------------------------------------------
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      '_audit','_day_start','_ref_norm','_ledger','_pts_spendable','_pts_sync','_pts_add','_pts_take','_pts_expire','_tr_points_guard',
      '_tr_points_open','_allow_remaining','_allow_cap','_allow_add','_allow_reserve','_allow_consume','_allow_release','_allow_expire',
      '_allow_json','_sess_branch','_staff_id','_tr_staff_revoke','_staff_json','_payreq_json',
      '_sess_merchant','_tx_quote','_expire_pending']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'staff_login','merchant_staff_list_v2','merchant_staff_save_v2','customer_points_v2','merchant_allowance_v2','merchant_catalog_v2',
      'merchant_payment_request_v2','merchant_payment_requests_v2','merchant_payment_cancel_v2','admin_catalog_v2','admin_plan_save_v2',
      'admin_package_save_v2','admin_pay_settings_v2','admin_engine_setting_v2','admin_payment_requests_v2','admin_payment_decide_v2',
      'admin_merchant_allowance_v2','admin_allowance_adjust_v2','admin_customer_points_v2','admin_points_adjust_v2','admin_run_expiry_v2',
      'admin_audit_log_v2']) loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end $$;

-- self-check
do $$
declare n int;
begin
  n := (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like '\_%' and p.proname in
         ('_pts_take','_allow_reserve','_sess_branch','_tx_quote') and has_function_privilege('anon', p.oid, 'execute'));
  if n > 0 then raise exception 'self-check: % internal helpers reachable by anon', n; end if;
  if (select count(*) from public.customers where coalesce(points, 0) <> public._pts_spendable(phone) and coalesce(points,0) > 0) > 0 then
    raise exception 'self-check: ledger total differs from customers.points';
  end if;
end $$;

commit;
