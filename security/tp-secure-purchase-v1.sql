-- =====================================================================================================
-- Tripoli Points — Secure purchase QR, sessions and Treasures profile — PHASE 1 MIGRATION (STAGING ONLY)
-- File: tp-secure-purchase-v1.sql                       Prepared 2026-11-11 · NOT EXECUTED ANYWHERE
-- =====================================================================================================
-- WHAT IT DOES (additive — the current app keeps working unchanged after it runs):
--   1. Server-side sessions for customers, merchants and admins (random token, only its SHA-256 stored).
--   2. A one-time purchase QR per customer that rotates every 300 s, claimed atomically by a merchant.
--   3. Purchases created from a claimed code only, confirmed once by the customer with the exact details.
--   4. Treasures computed on the server: invoice ≥ setting, after the profile is complete, one per shop per cycle.
--   5. Profile (name, family name, photo) saved permanently; the photo is only returned to its owner,
--      to a merchant holding a valid claim, and to admins.
--   6. Session versions (*_v2) of every function the app calls, so the old phone/merchant-id functions can be
--      closed in phase 3 without losing any feature.
--   7. Event log, suspicious-activity reports, monitoring alerts, editable limits in app_settings.
-- WHAT IT DOES NOT DO: it does not drop, revoke or change any existing function, and it does not touch
--   existing points, transactions, notes, merchants or customers. Closing the old functions is phase 3 (separate file).
-- One existing object changes: the unique key of customer_unlocks becomes (customer_phone, cycle, pic_id)
--   (the table is empty in Production today); the rollback file restores the original key.
-- RUN: Staging SQL editor, whole file at once (it is one transaction). Then run tp-secure-purchase-v1-tests.sql.
-- =====================================================================================================
begin;

do $$ begin
  if current_database() is null then raise exception 'no database'; end if;
  if to_regclass('public.pos_transactions') is null or to_regclass('public.customers') is null
     or to_regclass('public.treasure_pics') is null or to_regclass('public.customer_unlocks') is null then
    raise exception 'Tripoli Points schema not found — wrong project?';
  end if;
  if to_regclass('public.app_sessions') is not null then raise exception 'phase 1 already applied (app_sessions exists)'; end if;
end $$;

create extension if not exists pgcrypto with schema extensions;

-- ----------------------------------------------------------------------------------------------------
-- 1) Settings (numeric, editable later with admin_set_setting_v2; existing keys are never overwritten)
-- ----------------------------------------------------------------------------------------------------
insert into public.app_settings(key, value) values
  ('qr_ttl_sec', 300),                 -- purchase QR lifetime
  ('qr_claim_ttl_sec', 600),           -- after a scan, time the merchant has to create the purchase
  ('qr_issue_per_hour', 30),           -- codes a customer may generate per hour
  ('scan_fail_limit', 10),             -- invalid QR scans per merchant per window before a lock
  ('manual_code_fail_limit', 5),       -- invalid typed 8-digit codes per merchant per window before a lock
  ('scan_fail_window_min', 15),
  ('scan_lock_min', 15),
  ('login_fail_limit', 5),             -- wrong PINs per account per window
  ('login_ip_fail_limit', 30),         -- wrong PINs per IP per window (all accounts)
  ('login_window_min', 15),
  ('login_lock_min', 15),
  ('session_days', 30),                -- customer / merchant session, extended on use
  ('session_max_days', 180),           -- absolute session age
  ('admin_session_hours', 12),
  ('tx_pending_sec', 300),             -- time the customer has to approve a purchase (same as today)
  ('tx_max_invoice', 100000),
  ('treasure_min_invoice', 15),
  ('profile_photo_max_kb', 150),
  ('report_per_day', 5),
  ('alert_same_shop_per_day', 6),      -- monitoring only: confirmed purchases by one customer in one shop per day
  ('alert_merchant_per_hour', 40),     -- monitoring only: confirmed purchases per shop per hour
  ('alert_customer_shops_per_hour', 4) -- monitoring only: different shops per customer per hour
on conflict (key) do nothing;

-- ----------------------------------------------------------------------------------------------------
-- 2) New tables (RLS on, no policy, no grants → reachable only through the functions below)
-- ----------------------------------------------------------------------------------------------------
create table public.app_sessions (
  id uuid primary key default gen_random_uuid(),
  token_hash bytea not null unique,
  role text not null check (role in ('customer','merchant','admin')),
  customer_phone text references public.customers(phone) on delete cascade,
  merchant_id uuid references public.merchants(id) on delete cascade,
  admin_id uuid references public.admin_users(id) on delete cascade,
  device text,
  ip text,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_reason text,
  check ((role = 'customer' and customer_phone is not null and merchant_id is null and admin_id is null)
      or (role = 'merchant' and merchant_id is not null and customer_phone is null and admin_id is null)
      or (role = 'admin' and admin_id is not null and customer_phone is null and merchant_id is null))
);
create index app_sessions_customer_idx on public.app_sessions(customer_phone) where revoked_at is null;
create index app_sessions_merchant_idx on public.app_sessions(merchant_id) where revoked_at is null;
create index app_sessions_admin_idx on public.app_sessions(admin_id) where revoked_at is null;

create table public.purchase_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash bytea not null unique,
  short_hash bytea not null,
  customer_phone text not null references public.customers(phone) on delete cascade,
  session_id uuid references public.app_sessions(id) on delete set null,
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  superseded_at timestamptz,
  claimed_at timestamptz,
  claimed_by uuid references public.merchants(id) on delete set null,
  tx_id uuid
);
create index purchase_codes_customer_idx on public.purchase_codes(customer_phone, issued_at desc);
create index purchase_codes_short_live_idx on public.purchase_codes(short_hash) where claimed_at is null and superseded_at is null;

create table public.tx_events (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  event text not null,
  actor_role text,
  customer_phone text,
  merchant_id uuid,
  code_id uuid,
  tx_id uuid,
  ip text,
  detail jsonb not null default '{}'::jsonb
);
create index tx_events_at_idx on public.tx_events(at desc);
create index tx_events_event_idx on public.tx_events(event, at desc);
create index tx_events_tx_idx on public.tx_events(tx_id);

create table public.tx_reports (
  id uuid primary key default gen_random_uuid(),
  tx_id uuid,
  code_id uuid,
  reporter_role text not null check (reporter_role in ('customer','merchant')),
  reporter text not null,
  reason text not null check (reason in ('not_my_purchase','wrong_amount','not_account_owner','other')),
  note text check (note is null or length(note) <= 500),
  status text not null default 'open' check (status in ('open','reviewed','dismissed')),
  admin_note text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.admin_users(id) on delete set null
);
create index tx_reports_open_idx on public.tx_reports(created_at desc) where status = 'open';

create table public.rate_counters (
  key text primary key,
  window_start timestamptz not null default now(),
  hits integer not null default 0,
  locked_until timestamptz
);

-- columns on existing tables (nullable / defaulted: no existing row changes meaning)
alter table public.pos_transactions
  add column code_id uuid,
  add column idem_key text,
  add column offer_id uuid,
  add column disc numeric,
  add column bonus numeric,
  add column detail_hash text,
  add column decided_at timestamptz;
create unique index pos_transactions_code_uidx on public.pos_transactions(code_id) where code_id is not null;
create unique index pos_transactions_idem_uidx on public.pos_transactions(merchant_id, idem_key) where idem_key is not null;
create index pos_transactions_customer_idx on public.pos_transactions(customer_phone, status, created_at desc);
create index pos_transactions_merchant_idx on public.pos_transactions(merchant_id, status, created_at desc);

alter table public.customers
  add column profile_completed_at timestamptz,
  add column treasure_cycle integer not null default 1,
  add column photo_hash text;

alter table public.treasure_pics
  add column slug text unique,
  add column active boolean not null default true;

alter table public.customer_unlocks
  add column merchant_id uuid references public.merchants(id) on delete set null,
  add column tx_id uuid,
  add column cycle integer not null default 1,
  add column seq integer;
alter table public.customer_unlocks drop constraint customer_unlocks_customer_phone_pic_id_key;
alter table public.customer_unlocks add constraint customer_unlocks_phone_cycle_pic_key unique (customer_phone, cycle, pic_id);
create unique index customer_unlocks_phone_cycle_shop_uidx on public.customer_unlocks(customer_phone, cycle, merchant_id) where merchant_id is not null;

do $$ declare t text; begin
  foreach t in array array['app_sessions','purchase_codes','tx_events','tx_reports','rate_counters'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 3) Triggers
-- ----------------------------------------------------------------------------------------------------
-- Treasures are unlocked only by the new server logic (rows carry merchant_id). The old decide_transaction would start
-- inserting rows by "count of shops" as soon as treasure_pics is filled; those inserts are skipped silently.
create function public._tr_unlocks_skip_legacy() returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.merchant_id is null then return null; end if;
  return new;
end $$;
create trigger customer_unlocks_skip_legacy before insert on public.customer_unlocks
  for each row execute function public._tr_unlocks_skip_legacy();

-- A changed PIN, a frozen account or a deleted admin ends every session of that account.
create function public._tr_revoke_sessions() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if tg_table_name = 'customers' then
    if new.pin_hash is distinct from old.pin_hash or (new.status is distinct from old.status and new.status <> 'active') then
      update public.app_sessions set revoked_at = now(), revoked_reason = case when new.pin_hash is distinct from old.pin_hash then 'pin_changed' else 'account_frozen' end
       where customer_phone = new.phone and revoked_at is null;
    end if;
  elsif tg_table_name = 'merchants' then
    if new.pin_hash is distinct from old.pin_hash or (new.status is distinct from old.status and new.status in ('frozen','excluded','rejected')) then
      update public.app_sessions set revoked_at = now(), revoked_reason = case when new.pin_hash is distinct from old.pin_hash then 'pin_changed' else 'account_'||new.status end
       where merchant_id = new.id and revoked_at is null;
    end if;
  elsif tg_table_name = 'admin_users' then
    if new.pin_hash is distinct from old.pin_hash or new.is_primary is distinct from old.is_primary then
      update public.app_sessions set revoked_at = now(), revoked_reason = 'admin_changed' where admin_id = new.id and revoked_at is null;
    end if;
  end if;
  return new;
end $$;
create trigger customers_revoke_sessions after update of pin_hash, status on public.customers for each row execute function public._tr_revoke_sessions();
create trigger merchants_revoke_sessions after update of pin_hash, status on public.merchants for each row execute function public._tr_revoke_sessions();
create trigger admin_users_revoke_sessions after update of pin_hash, is_primary on public.admin_users for each row execute function public._tr_revoke_sessions();

-- ----------------------------------------------------------------------------------------------------
-- 4) Internal helpers (never callable from the API)
-- ----------------------------------------------------------------------------------------------------
create function public._setting(p_key text, p_default numeric) returns numeric language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select value from public.app_settings where key = p_key), p_default)
$$;

create function public._client_ip() returns text language plpgsql stable set search_path = public, pg_temp as $$
declare h jsonb; v text;
begin
  begin h := nullif(current_setting('request.headers', true), '')::jsonb; exception when others then h := null; end;
  v := coalesce(h->>'cf-connecting-ip', split_part(coalesce(h->>'x-forwarded-for',''), ',', 1));
  return nullif(trim(v), '');
end $$;

create function public._ev(p_event text, p_role text, p_phone text, p_mid uuid, p_code uuid, p_tx uuid, p_detail jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public, pg_temp as $$
  insert into public.tx_events(event, actor_role, customer_phone, merchant_id, code_id, tx_id, ip, detail)
  values (p_event, p_role, p_phone, p_mid, p_code, p_tx, public._client_ip(), coalesce(p_detail, '{}'::jsonb))
$$;

-- fixed-window limiter: true = locked now
create function public._rl2_locked(p_key text) returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists(select 1 from public.rate_counters where key = p_key and locked_until > now())
$$;
-- record one hit; when hits reach p_limit inside the window, lock for p_lock_sec (0 = no lock, just refuse). Returns true if still allowed.
create function public._rl2_hit(p_key text, p_limit integer, p_window_sec integer, p_lock_sec integer) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.rate_counters;
begin
  insert into public.rate_counters as rc(key, window_start, hits) values (p_key, now(), 1)
  on conflict (key) do update set
    hits = case when rc.window_start < now() - make_interval(secs => p_window_sec) then 1 else rc.hits + 1 end,
    window_start = case when rc.window_start < now() - make_interval(secs => p_window_sec) then now() else rc.window_start end
  returning * into r;
  if r.hits >= p_limit and p_lock_sec > 0 then
    update public.rate_counters set locked_until = now() + make_interval(secs => p_lock_sec) where key = p_key;
  end if;
  return r.hits <= p_limit;
end $$;
create function public._rl2_reset(p_key text) returns void language sql security definer set search_path = public, pg_temp as $$
  delete from public.rate_counters where key = p_key
$$;

create function public._b64url(p bytea) returns text language sql immutable set search_path = public, pg_temp as $$
  select translate(rtrim(encode(p, 'base64'), '='), E'+/\n', '-_')
$$;
create function public._sha(p text) returns bytea language sql immutable set search_path = public, extensions, pg_temp as $$
  select extensions.digest(convert_to(p, 'UTF8'), 'sha256')
$$;

create function public._sess(p_session text, p_role text) returns public.app_sessions
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; d numeric; mx numeric;
begin
  if p_session is null or length(p_session) < 20 or length(p_session) > 200 then
    raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required';
  end if;
  select * into s from public.app_sessions where token_hash = public._sha(p_session);
  if s.id is null or s.revoked_at is not null or s.expires_at <= now() or s.role <> p_role then
    raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required';
  end if;
  if s.role <> 'admin' and s.last_seen_at < now() - interval '1 hour' then   -- sliding expiry, written at most once an hour
    d := public._setting('session_days', 30); mx := public._setting('session_max_days', 180);
    update public.app_sessions set last_seen_at = now(),
      expires_at = least(now() + make_interval(days => d::int), created_at + make_interval(days => mx::int))
     where id = s.id returning * into s;
  end if;
  return s;
end $$;

create function public._sess_customer(p_session text) returns public.customers
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; c public.customers;
begin
  s := public._sess(p_session, 'customer');
  select * into c from public.customers where phone = s.customer_phone;
  if c.phone is null or coalesce(c.status,'active') <> 'active' then
    raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'account_inactive';
  end if;
  return c;
end $$;

create function public._sess_merchant(p_session text) returns public.merchants
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; m public.merchants;
begin
  s := public._sess(p_session, 'merchant');
  select * into m from public.merchants where id = s.merchant_id;
  if m.id is null or m.status in ('frozen','excluded','rejected') then
    raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'account_inactive';
  end if;
  return m;
end $$;

create function public._sess_admin(p_session text, p_primary boolean) returns public.admin_users
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; a public.admin_users;
begin
  s := public._sess(p_session, 'admin');
  select * into a from public.admin_users where id = s.admin_id;
  if a.id is null then raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required'; end if;
  if p_primary and not coalesce(a.is_primary, false) then
    raise exception 'TP_FORBIDDEN' using errcode = 'P0001', hint = 'primary_admin_only';
  end if;
  return a;
end $$;

create function public._issue_session(p_role text, p_phone text, p_mid uuid, p_admin uuid, p_device text)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare tok text; exp timestamptz;
begin
  tok := 'tps1_' || public._b64url(extensions.gen_random_bytes(32));
  exp := case when p_role = 'admin' then now() + make_interval(hours => public._setting('admin_session_hours', 12)::int)
              else now() + make_interval(days => public._setting('session_days', 30)::int) end;
  insert into public.app_sessions(token_hash, role, customer_phone, merchant_id, admin_id, device, ip, expires_at)
  values (public._sha(tok), p_role, p_phone, p_mid, p_admin, left(p_device, 120), public._client_ip(), exp);
  return jsonb_build_object('session', tok, 'expires_at', floor(extract(epoch from exp) * 1000));
end $$;

-- login guard shared by the three login functions: true = allowed to try
create function public._login_allowed(p_key text) returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
declare ip text := public._client_ip();
begin
  if public._rl2_locked('login:' || p_key) then return false; end if;
  if ip is not null and public._rl2_locked('loginip:' || ip) then return false; end if;
  return true;
end $$;
create function public._login_failed(p_key text) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare ip text := public._client_ip(); w int := (public._setting('login_window_min', 15) * 60)::int; l int := (public._setting('login_lock_min', 15) * 60)::int;
begin
  perform public._rl2_hit('login:' || p_key, public._setting('login_fail_limit', 5)::int, w, l);
  if ip is not null then perform public._rl2_hit('loginip:' || ip, public._setting('login_ip_fail_limit', 30)::int, w, l); end if;
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 5) Sessions API
-- ----------------------------------------------------------------------------------------------------
create function public._customer_json(c public.customers, p_with_photo boolean) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('phone', c.phone, 'name', c.name, 'last_name', c.last_name,
    'photo_url', case when p_with_photo then c.photo_url else null end, 'photo_hash', c.photo_hash,
    'points', c.points, 'status', c.status, 'welcome_remain', c.welcome_remain, 'welcome_exp', c.welcome_exp,
    'profile_completed_at', case when c.profile_completed_at is null then null else floor(extract(epoch from c.profile_completed_at) * 1000) end,
    'profile_complete', (coalesce(nullif(trim(c.name), ''), 'زبون جديد') <> 'زبون جديد' and nullif(trim(c.last_name), '') is not null and nullif(c.photo_url, '') is not null),
    'treasure_cycle', c.treasure_cycle)
$$;

create function public._merchant_json(r public.merchants) returns jsonb
language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('id', r.id, 'name', r.name, 'phone', r.phone, 'status', r.status, 'cat', r.cat, 'pct', r.pct,
    'tier', r.tier, 'addr', r.addr, 'photo_url', r.photo_url, 'photo_pending_url', r.photo_pending_url, 'logo_url', r.logo_url,
    'poster_printed', r.poster_printed, 'warns', r.warns, 'redeem_pct', r.redeem_pct, 'redeem_pct_vip', r.redeem_pct_vip,
    'pending_name', r.pending_name, 'pending_addr', r.pending_addr)
$$;

create function public.customer_login(p_phone text, p_pin text, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.customers; s jsonb;
begin
  if p_phone is null or p_phone !~ '^\d{7,8}$' then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if not public._login_allowed('customer:' || p_phone) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into c from public.customers where phone = p_phone;
  if c.phone is null then perform public._login_failed('customer:' || p_phone); return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if c.pin_hash is null or extensions.crypt(coalesce(p_pin,''), c.pin_hash) <> c.pin_hash then
    perform public._login_failed('customer:' || p_phone);
    perform public._ev('login_failed', 'customer', p_phone, null, null, null);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  if coalesce(c.status,'active') <> 'active' then return jsonb_build_object('ok', false, 'reason', 'frozen'); end if;
  perform public._rl2_reset('login:customer:' || p_phone);
  perform public.customer_check_welcome_expiry(p_phone);
  select * into c from public.customers where phone = p_phone;
  s := public._issue_session('customer', p_phone, null, null, p_device);
  return jsonb_build_object('ok', true, 'customer', public._customer_json(c, true)) || s;
end $$;

create function public.merchant_login(p_phone text, p_pin text, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r public.merchants; s jsonb;
begin
  if p_phone is null or p_phone !~ '^\d{7,8}$' then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if not public._login_allowed('merchant:' || p_phone) or public._rl_locked('merchant:' || p_phone) then
    return jsonb_build_object('ok', false, 'reason', 'locked');
  end if;
  select * into r from public.merchants where phone = p_phone;
  if r.id is null then perform public._login_failed('merchant:' || p_phone); return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.pin_hash is null or extensions.crypt(coalesce(p_pin,''), r.pin_hash) <> r.pin_hash then
    perform public._login_failed('merchant:' || p_phone);
    perform public._ev('login_failed', 'merchant', null, r.id, null, null);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  if r.status in ('frozen','excluded','rejected') then
    return jsonb_build_object('ok', true, 'merchant', public._merchant_json(r), 'session', null);   -- same as today: the app shows the status screen
  end if;
  perform public._rl2_reset('login:merchant:' || p_phone);
  s := public._issue_session('merchant', null, r.id, null, p_device);
  return jsonb_build_object('ok', true, 'merchant', public._merchant_json(r)) || s;
end $$;

create function public.admin_login(p_username text, p_pin text, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare a public.admin_users; s jsonb;
begin
  if p_username is null or length(p_username) > 64 then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if not public._login_allowed('admin:' || lower(p_username)) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into a from public.admin_users where username = p_username;
  if a.id is null or a.pin_hash is null or extensions.crypt(coalesce(p_pin,''), a.pin_hash) <> a.pin_hash then
    perform public._login_failed('admin:' || lower(p_username));
    perform public._ev('login_failed', 'admin', null, null, null, null, jsonb_build_object('username', left(p_username, 64)));
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl2_reset('login:admin:' || lower(p_username));
  s := public._issue_session('admin', null, null, a.id, p_device);
  perform public._ev('admin_login', 'admin', null, null, null, null, jsonb_build_object('admin', a.id));
  return jsonb_build_object('ok', true, 'admin', jsonb_build_object('id', a.id, 'username', a.username, 'is_primary', a.is_primary)) || s;
end $$;

-- registration returns a session directly. The welcome gift is read from the server settings (app_text_settings
-- welcome_bonus / welcome_days), never from the browser: the current customer_register trusts the amount it is sent.
create function public.customer_register_v2(p_phone text, p_pin text, p_terms_version text default null, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.customers; wb numeric; wd integer;
begin
  if p_phone is null or p_phone !~ '^\d{7,8}$' then return jsonb_build_object('ok', false, 'error', 'رقم الهاتف غير صحيح'); end if;
  if p_pin is null or p_pin !~ '^\d{4}$' then return jsonb_build_object('ok', false, 'error', 'رمز الحماية يجب أن يكون 4 أرقام'); end if;
  if not public._rl2_hit('register:' || coalesce(public._client_ip(), 'noip'), 20, 3600, 0) then
    return jsonb_build_object('ok', false, 'error', 'محاولات كثيرة، حاول لاحقاً');
  end if;
  begin wb := nullif(trim((select value from public.app_text_settings where key = 'welcome_bonus')), '')::numeric; exception when others then wb := 0; end;
  begin wd := nullif(trim((select value from public.app_text_settings where key = 'welcome_days')), '')::numeric::int; exception when others then wd := 0; end;
  begin
    perform public.customer_register(p_phone, p_pin, 'زبون جديد', greatest(0, least(coalesce(wb, 0), 100000)), greatest(0, coalesce(wd, 0)), p_terms_version);
  exception when raise_exception then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
  end;
  select * into c from public.customers where phone = p_phone;
  return jsonb_build_object('ok', true, 'customer', public._customer_json(c, true)) || public._issue_session('customer', p_phone, null, null, p_device);
end $$;

create function public.merchant_register_v2(p_name text, p_phone text, p_pin text, p_cat text, p_pct numeric, p_addr text, p_x numeric, p_y numeric,
  p_lat numeric, p_lng numeric, p_photo_url text, p_redeem_pct numeric, p_extra_cats text[], p_terms_version text, p_area text, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare r jsonb; m public.merchants;
begin
  if p_phone is null or p_phone !~ '^\d{7,8}$' then return jsonb_build_object('ok', false, 'error', 'رقم الهاتف غير صحيح'); end if;
  if not public._rl2_hit('register:' || coalesce(public._client_ip(), 'noip'), 20, 3600, 0) then
    return jsonb_build_object('ok', false, 'error', 'محاولات كثيرة، حاول لاحقاً');
  end if;
  begin
    r := public.merchant_register(p_name, p_phone, p_pin, p_cat, p_pct, p_addr, p_x, p_y, p_lat, p_lng, p_photo_url, p_redeem_pct, p_extra_cats, p_terms_version, p_area);
  exception when raise_exception then
    return jsonb_build_object('ok', false, 'error', sqlerrm);
  end;
  select * into m from public.merchants where phone = p_phone;
  return jsonb_build_object('ok', true, 'id', m.id, 'status', m.status, 'merchant', public._merchant_json(m))
         || public._issue_session('merchant', null, m.id, null, p_device);
end $$;

create function public.session_logout(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  update public.app_sessions set revoked_at = now(), revoked_reason = 'logout'
   where token_hash = public._sha(coalesce(p_session, '')) and revoked_at is null;
  return jsonb_build_object('ok', true);
end $$;

create function public._sess_any(p_session text) returns public.app_sessions language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions;
begin
  select * into s from public.app_sessions where token_hash = public._sha(coalesce(p_session, ''));
  if s.id is null then raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required'; end if;
  return public._sess(p_session, s.role);
end $$;

create function public.session_logout_all(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; n int;
begin
  s := public._sess_any(p_session);
  update public.app_sessions set revoked_at = now(), revoked_reason = 'logout_all'
   where revoked_at is null and role = s.role
     and customer_phone is not distinct from s.customer_phone and merchant_id is not distinct from s.merchant_id and admin_id is not distinct from s.admin_id;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'revoked', n);
end $$;

create function public.session_list(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; r jsonb;
begin
  s := public._sess_any(p_session);
  select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'device', x.device, 'current', x.id = s.id,
      'created_at', floor(extract(epoch from x.created_at) * 1000), 'last_seen_at', floor(extract(epoch from x.last_seen_at) * 1000))
      order by x.last_seen_at desc), '[]'::jsonb) into r
    from public.app_sessions x
   where x.revoked_at is null and x.expires_at > now() and x.role = s.role
     and x.customer_phone is not distinct from s.customer_phone and x.merchant_id is not distinct from s.merchant_id and x.admin_id is not distinct from s.admin_id;
  return r;
end $$;

create function public.session_revoke(p_session text, p_session_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; n int;
begin
  s := public._sess_any(p_session);
  update public.app_sessions set revoked_at = now(), revoked_reason = 'revoked_by_owner'
   where id = p_session_id and revoked_at is null and role = s.role
     and customer_phone is not distinct from s.customer_phone and merchant_id is not distinct from s.merchant_id and admin_id is not distinct from s.admin_id;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', n = 1);
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 6) Profile and Treasures
-- ----------------------------------------------------------------------------------------------------
create function public.customer_profile_v2(p_session text, p_photo_hash text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers;
begin
  c := public._sess_customer(p_session);
  perform public.customer_check_welcome_expiry(c.phone);
  select * into c from public.customers where phone = c.phone;
  -- the photo travels only when the app does not already hold this exact version
  return jsonb_build_object('ok', true, 'customer', public._customer_json(c, p_photo_hash is null or p_photo_hash is distinct from c.photo_hash));
end $$;

create function public.customer_update_profile(p_session text, p_name text default null, p_last text default null, p_photo text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.customers; nm text := nullif(trim(p_name), ''); ln text := nullif(trim(p_last), ''); ph text := nullif(p_photo, '');
  letters constant text := '^[A-Za-zء-غـ-ٰٟ-ۓ ]{2,30}$'; maxlen int; complete boolean; started boolean := false;
begin
  c := public._sess_customer(p_session);
  if nm is not null and (nm !~ letters or nm = 'زبون جديد') then return jsonb_build_object('ok', false, 'error', 'الاسم يجب أن يحتوي على أحرف فقط'); end if;
  if ln is not null and ln !~ letters then return jsonb_build_object('ok', false, 'error', 'اسم العائلة يجب أن يحتوي على أحرف فقط'); end if;
  if ph is not null then
    maxlen := ceil(public._setting('profile_photo_max_kb', 150) * 1024 * 4 / 3)::int + 32;
    if ph !~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/]+={0,2}$' then return jsonb_build_object('ok', false, 'error', 'صيغة الصورة غير مدعومة'); end if;
    if length(ph) > maxlen then return jsonb_build_object('ok', false, 'error', 'حجم الصورة كبير'); end if;
  end if;
  -- empty values never erase saved data
  update public.customers set
      name = coalesce(nm, name), last_name = coalesce(ln, last_name),
      photo_url = coalesce(ph, photo_url),
      photo_hash = case when ph is not null then encode(extensions.digest(ph, 'sha256'), 'hex') else photo_hash end
   where phone = c.phone returning * into c;
  complete := coalesce(nullif(trim(c.name), ''), 'زبون جديد') <> 'زبون جديد' and nullif(trim(c.last_name), '') is not null and nullif(c.photo_url, '') is not null;
  if complete and c.profile_completed_at is null then
    update public.customers set profile_completed_at = now() where phone = c.phone returning * into c;
    started := true;
    perform public._ev('profile_completed', 'customer', c.phone, null, null, null);
  end if;
  return jsonb_build_object('ok', true, 'profile_complete', complete, 'treasures_started', started, 'customer', public._customer_json(c, false));
end $$;

create function public.treasure_list() returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'slug', slug, 'name', name, 'note', note, 'img', img_url, 'order', display_order)
         order by display_order, created_at), '[]'::jsonb)
    from public.treasure_pics where active
$$;

create function public.customer_treasures_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers; r jsonb;
begin
  c := public._sess_customer(p_session);
  select coalesce(jsonb_agg(jsonb_build_object('pic_id', u.pic_id, 'slug', p.slug, 'name', p.name, 'img', p.img_url, 'seq', u.seq,
           'shop', m.name, 'at', floor(extract(epoch from u.unlocked_at) * 1000)) order by u.seq, u.unlocked_at), '[]'::jsonb) into r
    from public.customer_unlocks u join public.treasure_pics p on p.id = u.pic_id left join public.merchants m on m.id = u.merchant_id
   where u.customer_phone = c.phone and u.cycle = c.treasure_cycle and u.merchant_id is not null;
  return jsonb_build_object('ok', true, 'cycle', c.treasure_cycle, 'min_invoice', public._setting('treasure_min_invoice', 15),
    'started_at', case when c.profile_completed_at is null then null else floor(extract(epoch from c.profile_completed_at) * 1000) end,
    'unlocked', r, 'total', (select count(*) from public.treasure_pics where active));
end $$;

-- returns the unlocked picture or null; called inside the confirmation
create function public._unlock_treasure(t public.pos_transactions) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers; pic public.treasure_pics; n int;
begin
  select * into c from public.customers where phone = t.customer_phone;
  if c.profile_completed_at is null or t.created_at < c.profile_completed_at then return null; end if;
  if t.invoice < public._setting('treasure_min_invoice', 15) then return null; end if;
  if exists (select 1 from public.customer_unlocks where customer_phone = c.phone and cycle = c.treasure_cycle and merchant_id = t.merchant_id) then return null; end if;
  select * into pic from public.treasure_pics p
   where p.active and not exists (select 1 from public.customer_unlocks u where u.customer_phone = c.phone and u.cycle = c.treasure_cycle and u.pic_id = p.id)
   order by p.display_order, p.created_at limit 1;
  if pic.id is null then return null; end if;
  select count(*) + 1 into n from public.customer_unlocks where customer_phone = c.phone and cycle = c.treasure_cycle and merchant_id is not null;
  insert into public.customer_unlocks(customer_phone, pic_id, merchant_id, tx_id, cycle, seq)
  values (c.phone, pic.id, t.merchant_id, t.id, c.treasure_cycle, n)
  on conflict do nothing;
  if not found then return null; end if;
  insert into public.customer_notes(customer_phone, type, title, body)
  values (c.phone, 'general', format('🎉 صورة جديدة من كنوز طرابلس: %s', pic.name), 'افتح «كنوز طرابلس» لمشاهدتها');
  perform public._ev('treasure_unlocked', 'customer', c.phone, t.merchant_id, null, t.id, jsonb_build_object('pic', pic.id, 'seq', n));
  return jsonb_build_object('pic_id', pic.id, 'slug', pic.slug, 'name', pic.name, 'img', pic.img_url, 'seq', n);
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 7) Purchase QR
-- ----------------------------------------------------------------------------------------------------
-- price calculation: the same rules as create_transaction, without writing anything
create function public._tx_quote(p_mid uuid, p_phone text, p_invoice numeric, p_redeem boolean, p_offer_id uuid) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare m public.merchants; c public.customers; o public.offers;
  rate numeric; cap_pct numeric; tier_max numeric; disc numeric := 0; base numeric; vip_cap numeric; is_vip boolean;
  avail_pts numeric; max_redeem numeric; cap numeric; rp numeric; rv numeric; net numeric; bonus numeric := 0; earn numeric; wallet_avail numeric;
begin
  select * into m from public.merchants where id = p_mid;
  if m.id is null or m.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب المحل غير فعّال'); end if;
  select * into c from public.customers where phone = p_phone;
  if c.phone is null then return jsonb_build_object('ok', false, 'error', 'هذا الحساب غير موجود'); end if;
  if c.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'حساب الزبون مجمّد'); end if;
  if p_invoice is null or p_invoice <= 0 then return jsonb_build_object('ok', false, 'error', 'أدخل قيمة الفاتورة'); end if;
  if p_invoice > public._setting('tx_max_invoice', 100000) then return jsonb_build_object('ok', false, 'error', 'قيمة الفاتورة كبيرة جداً'); end if;
  if round(p_invoice, 2) <> p_invoice then return jsonb_build_object('ok', false, 'error', 'قيمة الفاتورة غير صحيحة'); end if;
  select value into rate from public.app_settings where key = 'rate_pts_per_usd';
  select value into cap_pct from public.app_settings where key = 'redeem_cap_pct';
  if p_offer_id is not null then
    select * into o from public.offers where id = p_offer_id and merchant_id = p_mid;
    if o.id is null then return jsonb_build_object('ok', false, 'error', 'العرض غير موجود'); end if;
    if not o.active or coalesce(o.deleted, false) or now() - o.created_at >= (o.days || ' days')::interval then return jsonb_build_object('ok', false, 'error', 'انتهى هذا العرض'); end if;
    if o.min_amount > 0 and p_invoice < o.min_amount then return jsonb_build_object('ok', false, 'error', format('الحد الأدنى لهذا العرض $%s', o.min_amount)); end if;
    if o.first_time_only and exists (select 1 from public.pos_transactions where merchant_id = p_mid and customer_phone = p_phone and status = 'CONFIRMED') then
      return jsonb_build_object('ok', false, 'error', 'هذا العرض للزائر الجديد فقط');
    end if;
  end if;
  tier_max := case m.tier when 'large' then 10000 when 'medium' then 2500 else 1000 end;
  disc := case when o.type = 'discount' then round(p_invoice * o.val / 100, 2) else 0 end;
  base := round(p_invoice - disc, 2);
  select cap_points into vip_cap from public.merchant_vips where merchant_id = p_mid and customer_phone = p_phone;
  is_vip := vip_cap is not null and vip_cap > 0;
  avail_pts := greatest(0, c.points);
  max_redeem := floor(avail_pts * cap_pct / 100);
  if is_vip then cap := least(max_redeem, least(vip_cap, floor(base * rate)));
  else cap := least(max_redeem, floor(base * rate * coalesce(m.redeem_pct, 5) / 100), tier_max); end if;
  rp := case when p_redeem then cap else 0 end;
  rv := rp / rate;
  net := round(base - rv, 2);
  bonus := case when o.type = 'bonus' and o.per > 0 then floor(net / o.per) * o.pts else 0 end;
  earn := floor(net * m.pct / 100 * rate) + bonus;
  wallet_avail := (public.merchant_wallet(p_mid)->>'avail')::numeric;
  if earn / rate > wallet_avail then return jsonb_build_object('ok', false, 'error', 'INSUFFICIENT'); end if;
  return jsonb_build_object('ok', true, 'invoice', p_invoice, 'disc', disc, 'redeem_pts', rp, 'redeem_val', rv, 'net', net,
    'bonus', bonus, 'earn', earn, 'redeem_max', cap, 'offer_id', p_offer_id);
end $$;

create function public._tx_hash(t public.pos_transactions) returns text language sql immutable set search_path = public, extensions, pg_temp as $$
  select encode(extensions.digest(convert_to(concat_ws('|', 'tx1', t.id, t.merchant_id, t.customer_phone, t.invoice, coalesce(t.disc,0),
         t.redeem_pts, t.redeem_val, t.net, t.earn, coalesce(t.bonus,0), coalesce(t.offer_id::text,'')), 'UTF8'), 'sha256'), 'hex')
$$;

create function public._tx_json(t public.pos_transactions, p_for text) returns jsonb language sql stable security definer set search_path = public, pg_temp as $$
  select jsonb_build_object('id', t.id, 'mid', t.merchant_id, 'mname', (select name from public.merchants where id = t.merchant_id),
    'invoice', t.invoice, 'disc', coalesce(t.disc,0), 'redeemPts', t.redeem_pts, 'redeemVal', t.redeem_val, 'net', t.net, 'earn', t.earn,
    'bonus', coalesce(t.bonus,0), 'offerId', t.offer_id, 'items', t.items, 'status', t.status,
    'at', floor(extract(epoch from t.created_at) * 1000),
    'expiresAt', case when t.status = 'PENDING' then floor(extract(epoch from t.created_at + make_interval(secs => public._setting('tx_pending_sec', 300)::int)) * 1000) end,
    'detailHash', case when p_for = 'customer' and t.status = 'PENDING' then t.detail_hash end,
    'secure', t.code_id is not null)
$$;

create function public._expire_pending(p_phone text, p_mid uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare ttl int := public._setting('tx_pending_sec', 300)::int; r record;
begin
  for r in update public.pos_transactions set status = 'EXPIRED'
            where status = 'PENDING' and created_at < now() - make_interval(secs => ttl)
              and (p_phone is null or customer_phone = p_phone) and (p_mid is null or merchant_id = p_mid)
           returning id, customer_phone, merchant_id loop
    perform public._ev('tx_expired', null, r.customer_phone, r.merchant_id, null, r.id);
  end loop;
end $$;

create function public.customer_qr_issue(p_session text) returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare c public.customers; s public.app_sessions; tok text; short text; sh bytea; ttl int; pc public.purchase_codes; tries int := 0;
begin
  c := public._sess_customer(p_session);
  s := public._sess(p_session, 'customer');
  if not public._rl2_hit('qr_issue:' || c.phone, public._setting('qr_issue_per_hour', 30)::int, 3600, 0) then
    perform public._ev('qr_issue_limited', 'customer', c.phone, null, null, null);
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'message', 'طلبت رموزاً كثيرة. حاول بعد قليل');
  end if;
  update public.purchase_codes set superseded_at = now()
   where customer_phone = c.phone and claimed_at is null and superseded_at is null;
  ttl := public._setting('qr_ttl_sec', 300)::int;
  tok := public._b64url(extensions.gen_random_bytes(16));
  loop
    short := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 100000000)::text, 8, '0');
    sh := public._sha('short:' || short);
    exit when not exists (select 1 from public.purchase_codes where short_hash = sh and claimed_at is null and superseded_at is null and expires_at > now());
    tries := tries + 1; if tries > 5 then raise exception 'could not allocate a short code'; end if;
  end loop;
  insert into public.purchase_codes(code_hash, short_hash, customer_phone, session_id, expires_at)
  values (public._sha('qr:' || tok), sh, c.phone, s.id, now() + make_interval(secs => ttl)) returning * into pc;
  perform public._ev('qr_issued', 'customer', c.phone, null, pc.id, null);
  return jsonb_build_object('ok', true, 'code_id', pc.id, 'qr', 'TPPAY1.' || tok, 'short', short, 'ttl', ttl,
    'expires_at', floor(extract(epoch from pc.expires_at) * 1000), 'server_now', floor(extract(epoch from now()) * 1000));
end $$;

create function public.customer_qr_status(p_session text, p_code_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers; pc public.purchase_codes; t public.pos_transactions; st text; claim_ttl int := public._setting('qr_claim_ttl_sec', 600)::int;
begin
  c := public._sess_customer(p_session);
  perform public._expire_pending(c.phone, null);
  select * into pc from public.purchase_codes where id = p_code_id and customer_phone = c.phone;
  if pc.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if pc.tx_id is not null then
    select * into t from public.pos_transactions where id = pc.tx_id;
    st := case when t.status = 'PENDING' then 'tx' else 'used' end;
  elsif pc.claimed_at is not null then
    st := case when pc.superseded_at is null and pc.claimed_at > now() - make_interval(secs => claim_ttl) then 'claimed' else 'expired' end;
  elsif pc.superseded_at is not null then st := 'superseded';
  elsif pc.expires_at <= now() then st := 'expired';
  else st := 'live'; end if;
  return jsonb_build_object('ok', true, 'state', st,
    'expires_in', greatest(0, floor(extract(epoch from pc.expires_at - now())))::int,
    'shop', case when pc.claimed_by is not null then (select name from public.merchants where id = pc.claimed_by) end,
    'tx', case when t.id is not null then public._tx_json(t, 'customer') end,
    'server_now', floor(extract(epoch from now()) * 1000));
end $$;

create function public.merchant_scan_code(p_session text, p_code text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; raw text := trim(coalesce(p_code, '')); kind text; h bytea; pc public.purchase_codes; c public.customers;
  lockkey text; lim int; win int := (public._setting('scan_fail_window_min', 15) * 60)::int; lck int := (public._setting('scan_lock_min', 15) * 60)::int;
  why text; claim_ttl int := public._setting('qr_claim_ttl_sec', 600)::int;
begin
  m := public._sess_merchant(p_session);
  if m.status <> 'active' then return jsonb_build_object('ok', false, 'error', 'inactive', 'message', 'حساب المحل غير فعّال'); end if;
  if raw ~ '^TPPAY1\.[A-Za-z0-9_-]{16,64}$' then
    kind := 'qr'; h := public._sha('qr:' || substr(raw, 8)); lockkey := 'scan:' || m.id; lim := public._setting('scan_fail_limit', 10)::int;
  elsif regexp_replace(raw, '[\s-]', '', 'g') ~ '^\d{8}$' then
    kind := 'short'; h := public._sha('short:' || regexp_replace(raw, '[\s-]', '', 'g')); lockkey := 'scanman:' || m.id; lim := public._setting('manual_code_fail_limit', 5)::int;
  else
    kind := 'invalid'; lockkey := 'scan:' || m.id; lim := public._setting('scan_fail_limit', 10)::int;
  end if;
  if public._rl2_locked(lockkey) then
    return jsonb_build_object('ok', false, 'error', 'locked', 'message', 'محاولات خاطئة كثيرة. انتظر قليلاً ثم أعد المحاولة');
  end if;
  if kind <> 'invalid' then
    if kind = 'qr' then
      update public.purchase_codes set claimed_at = now(), claimed_by = m.id
       where code_hash = h and claimed_at is null and superseded_at is null and expires_at > now() returning * into pc;
    else
      update public.purchase_codes set claimed_at = now(), claimed_by = m.id
       where id = (select id from public.purchase_codes where short_hash = h and claimed_at is null and superseded_at is null and expires_at > now()
                    order by issued_at desc limit 1 for update skip locked)
         and claimed_at is null returning * into pc;
    end if;
    if pc.id is null then   -- the same shop scanning again its own open claim gets it back
      select * into pc from public.purchase_codes
       where (case when kind = 'qr' then code_hash = h else short_hash = h end)
         and claimed_by = m.id and tx_id is null and superseded_at is null and claimed_at > now() - make_interval(secs => claim_ttl)
       order by claimed_at desc limit 1;
    end if;
  end if;
  if pc.id is null then
    if kind = 'invalid' then why := 'invalid';
    else
      select case when x.tx_id is not null or x.claimed_at is not null then 'used' when x.superseded_at is not null then 'superseded'
                  when x.expires_at <= now() then 'expired' else 'invalid' end into why
        from public.purchase_codes x where (case when kind = 'qr' then x.code_hash = h else x.short_hash = h end)
        order by x.issued_at desc limit 1;
      why := coalesce(why, 'invalid');
    end if;
    perform public._rl2_hit(lockkey, lim, win, lck);
    perform public._ev('scan_failed', 'merchant', null, m.id, null, null, jsonb_build_object('kind', kind, 'why', why));
    return jsonb_build_object('ok', false, 'error', why, 'message', case why
      when 'expired' then 'انتهت صلاحية هذا الرمز. اطلب من الزبون إظهار الرمز الحالي'
      when 'superseded' then 'هذا رمز قديم. اطلب من الزبون إظهار الرمز الحالي'
      when 'used' then 'هذا الرمز استُعمل من قبل'
      else 'رمز غير صالح' end);
  end if;
  select * into c from public.customers where phone = pc.customer_phone;
  if c.phone = m.phone then
    update public.purchase_codes set superseded_at = now() where id = pc.id;
    return jsonb_build_object('ok', false, 'error', 'own_account', 'message', 'لا يمكن تسجيل عملية على رقم المحل نفسه');
  end if;
  if coalesce(c.status, 'active') <> 'active' then return jsonb_build_object('ok', false, 'error', 'frozen', 'message', 'حساب الزبون مجمّد'); end if;
  perform public._ev('scanned', 'merchant', c.phone, m.id, pc.id, null, jsonb_build_object('kind', kind, 'age_sec', floor(extract(epoch from now() - pc.issued_at))));
  -- only what the merchant needs to check the person: first name and photo. No phone number, no family name, no balance.
  return jsonb_build_object('ok', true, 'code_id', pc.id,
    'customer', jsonb_build_object('first_name', case when c.name = 'زبون جديد' then null else c.name end, 'photo', nullif(c.photo_url, '')),
    'claim_expires_at', floor(extract(epoch from pc.claimed_at + make_interval(secs => claim_ttl)) * 1000));
end $$;

create function public._claim_for(m public.merchants, p_code_id uuid, p_lock boolean) returns public.purchase_codes
language plpgsql security definer set search_path = public, pg_temp as $$
declare pc public.purchase_codes;
begin
  if p_lock then select * into pc from public.purchase_codes where id = p_code_id for update;
  else select * into pc from public.purchase_codes where id = p_code_id; end if;
  if pc.id is null or pc.claimed_by is distinct from m.id or pc.superseded_at is not null
     or pc.claimed_at < now() - make_interval(secs => public._setting('qr_claim_ttl_sec', 600)::int) then
    return null;
  end if;
  return pc;
end $$;

create function public.merchant_quote_v2(p_session text, p_code_id uuid, p_invoice numeric, p_redeem boolean default true, p_offer_id uuid default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; pc public.purchase_codes;
begin
  m := public._sess_merchant(p_session);
  pc := public._claim_for(m, p_code_id, false);
  if pc.id is null or pc.tx_id is not null then return jsonb_build_object('ok', false, 'error', 'claim_expired', 'message', 'انتهت مهلة هذا المسح. امسح رمز الزبون من جديد'); end if;
  return public._tx_quote(m.id, pc.customer_phone, p_invoice, coalesce(p_redeem, false), p_offer_id);
end $$;

create function public.merchant_create_tx_v2(p_session text, p_code_id uuid, p_invoice numeric, p_redeem boolean, p_offer_id uuid default null,
  p_items jsonb default '[]'::jsonb, p_idem_key text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; pc public.purchase_codes; c public.customers; q jsonb; t public.pos_transactions; v_id uuid := gen_random_uuid();
begin
  m := public._sess_merchant(p_session);
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
  if exists (select 1 from public.pos_transactions where customer_phone = c.phone and status = 'PENDING') then
    return jsonb_build_object('ok', false, 'error', 'pending', 'message', 'لدى الزبون عملية قيد التأكيد');
  end if;
  q := public._tx_quote(m.id, c.phone, p_invoice, coalesce(p_redeem, false), p_offer_id);
  if not (q->>'ok')::boolean then return q; end if;
  t.id := v_id; t.merchant_id := m.id; t.customer_phone := c.phone; t.invoice := p_invoice;
  t.redeem_pts := (q->>'redeem_pts')::numeric; t.redeem_val := (q->>'redeem_val')::numeric; t.net := (q->>'net')::numeric;
  t.earn := (q->>'earn')::numeric; t.disc := (q->>'disc')::numeric; t.bonus := (q->>'bonus')::numeric; t.offer_id := p_offer_id;
  t.created_at := now();
  begin
    insert into public.pos_transactions(id, merchant_id, customer_phone, invoice, redeem_pts, redeem_val, net, earn, items, status,
                                        code_id, idem_key, offer_id, disc, bonus, detail_hash, created_at)
    values (t.id, t.merchant_id, t.customer_phone, t.invoice, t.redeem_pts, t.redeem_val, t.net, t.earn, coalesce(p_items, '[]'::jsonb), 'PENDING',
            pc.id, p_idem_key, t.offer_id, t.disc, t.bonus, public._tx_hash(t), t.created_at)
    returning * into t;
  exception when unique_violation then
    select * into t from public.pos_transactions where merchant_id = m.id and idem_key = p_idem_key;
    if t.id is not null then return jsonb_build_object('ok', true, 'replayed', true, 'tx', public._tx_json(t, 'merchant')); end if;
    return jsonb_build_object('ok', false, 'error', 'used', 'message', 'هذا الرمز استُعمل من قبل');
  end;
  update public.purchase_codes set tx_id = t.id where id = pc.id;
  insert into public.customer_notes(customer_phone, type, title, body) values (c.phone, 'points', 'عملية بانتظار تأكيدك', m.name || ': $' || t.invoice);
  perform public._ev('tx_created', 'merchant', c.phone, m.id, pc.id, t.id, jsonb_build_object('invoice', t.invoice, 'redeem_pts', t.redeem_pts, 'earn', t.earn));
  return jsonb_build_object('ok', true, 'tx', public._tx_json(t, 'merchant'));
end $$;

create function public.merchant_cancel_tx(p_session text, p_tx_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; t public.pos_transactions;
begin
  m := public._sess_merchant(p_session);
  update public.pos_transactions set status = 'CANCELLED', decided_at = now()
   where id = p_tx_id and merchant_id = m.id and status = 'PENDING' returning * into t;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_pending'); end if;
  insert into public.customer_notes(customer_phone, type, title, body) values (t.customer_phone, 'points', 'ألغى المحل العملية', m.name || ': $' || t.invoice);
  perform public._ev('tx_cancelled_by_merchant', 'merchant', t.customer_phone, m.id, t.code_id, t.id);
  return jsonb_build_object('ok', true);
end $$;

create function public._alerts_after_confirm(t public.pos_transactions) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare n int;
begin
  select count(*) into n from public.pos_transactions where customer_phone = t.customer_phone and merchant_id = t.merchant_id
     and status = 'CONFIRMED' and created_at >= date_trunc('day', now());
  if n >= public._setting('alert_same_shop_per_day', 6) and not exists (select 1 from public.tx_events where event = 'alert_same_shop'
       and customer_phone = t.customer_phone and merchant_id = t.merchant_id and at >= date_trunc('day', now())) then
    perform public._ev('alert_same_shop', null, t.customer_phone, t.merchant_id, null, t.id, jsonb_build_object('count_today', n));
  end if;
  select count(*) into n from public.pos_transactions where merchant_id = t.merchant_id and status = 'CONFIRMED' and created_at >= now() - interval '1 hour';
  if n >= public._setting('alert_merchant_per_hour', 40) and not exists (select 1 from public.tx_events where event = 'alert_merchant_rate'
       and merchant_id = t.merchant_id and at >= now() - interval '1 hour') then
    perform public._ev('alert_merchant_rate', null, null, t.merchant_id, null, t.id, jsonb_build_object('count_hour', n));
  end if;
  select count(distinct merchant_id) into n from public.pos_transactions where customer_phone = t.customer_phone and status = 'CONFIRMED' and created_at >= now() - interval '1 hour';
  if n >= public._setting('alert_customer_shops_per_hour', 4) and not exists (select 1 from public.tx_events where event = 'alert_customer_shops'
       and customer_phone = t.customer_phone and at >= now() - interval '1 hour') then
    perform public._ev('alert_customer_shops', null, t.customer_phone, null, null, t.id, jsonb_build_object('shops_hour', n));
  end if;
end $$;

create function public.customer_decide_tx_v2(p_session text, p_tx_id uuid, p_confirm boolean, p_detail_hash text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers; t public.pos_transactions; m public.merchants; ttl int := public._setting('tx_pending_sec', 300)::int; pic jsonb;
begin
  c := public._sess_customer(p_session);
  if p_confirm is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if p_confirm and (p_detail_hash is null or p_detail_hash !~ '^[0-9a-f]{64}$') then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
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
  insert into public.merchant_notes(merchant_id, type, title, body) values (t.merchant_id,
    case when p_confirm then 'sale' else 'warn' end,
    case when p_confirm then format('تم تأكيد عملية بقيمة $%s', t.invoice) else 'ألغى الزبون العملية' end,
    case when c.name = 'زبون جديد' then null else c.name end);
  if p_confirm then
    update public.customers set points = points + t.earn - t.redeem_pts where phone = c.phone returning * into c;
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

create function public.customer_transactions_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers; r jsonb;
begin
  c := public._sess_customer(p_session);
  perform public._expire_pending(c.phone, null);
  select coalesce(jsonb_agg(public._tx_json(t, 'customer') order by t.created_at desc), '[]'::jsonb) into r
    from (select * from public.pos_transactions where customer_phone = c.phone order by created_at desc limit 300) t;
  return r;
end $$;

create function public.customer_notes_list_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers; r jsonb;
begin
  c := public._sess_customer(p_session);
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'type', type, 'title', title, 'body', body, 'read', read,
         'at', floor(extract(epoch from created_at) * 1000)) order by created_at desc), '[]'::jsonb) into r
    from (select * from public.customer_notes where customer_phone = c.phone order by created_at desc limit 200) n;
  return r;
end $$;

create function public.customer_notes_mark_read_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare c public.customers;
begin
  c := public._sess_customer(p_session);
  update public.customer_notes set read = true where customer_phone = c.phone and read = false;
  return jsonb_build_object('ok', true);
end $$;

create function public.report_tx(p_session text, p_reason text, p_tx_id uuid default null, p_code_id uuid default null, p_note text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; t public.pos_transactions; pc public.purchase_codes; who text; rep public.tx_reports;
begin
  select * into s from public.app_sessions where token_hash = public._sha(coalesce(p_session, ''));
  if s.role is null or s.role = 'admin' then raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required'; end if;
  if s.role = 'customer' then perform public._sess_customer(p_session); who := s.customer_phone;
  else perform public._sess_merchant(p_session); who := s.merchant_id::text; end if;
  if p_reason not in ('not_my_purchase','wrong_amount','not_account_owner','other') or (p_tx_id is null and p_code_id is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_request');
  end if;
  if p_tx_id is not null then
    select * into t from public.pos_transactions where id = p_tx_id
       and ((s.role = 'customer' and customer_phone = s.customer_phone) or (s.role = 'merchant' and merchant_id = s.merchant_id));
    if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  else
    select * into pc from public.purchase_codes where id = p_code_id
       and ((s.role = 'customer' and customer_phone = s.customer_phone) or (s.role = 'merchant' and claimed_by = s.merchant_id));
    if pc.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  if not public._rl2_hit('report:' || s.role || ':' || who, public._setting('report_per_day', 5)::int, 86400, 0) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'message', 'تم استلام بلاغاتك. ستراجعها الإدارة');
  end if;
  insert into public.tx_reports(tx_id, code_id, reporter_role, reporter, reason, note)
  values (t.id, coalesce(pc.id, t.code_id), s.role, who, p_reason, left(p_note, 500)) returning * into rep;
  -- a report on a purchase that is still waiting cancels it; a merchant reporting a claim releases the code
  if t.id is not null and t.status = 'PENDING' then
    update public.pos_transactions set status = 'CANCELLED', decided_at = now() where id = t.id and status = 'PENDING';
    insert into public.merchant_notes(merchant_id, type, title, body) values (t.merchant_id, 'warn', 'أُلغيت عملية بعد بلاغ', format('$%s', t.invoice));
  end if;
  if pc.id is not null and pc.tx_id is null then update public.purchase_codes set superseded_at = now() where id = pc.id; end if;
  perform public._ev('reported', s.role, coalesce(t.customer_phone, pc.customer_phone), coalesce(t.merchant_id, pc.claimed_by), coalesce(pc.id, t.code_id), t.id,
                     jsonb_build_object('reason', p_reason, 'report', rep.id));
  return jsonb_build_object('ok', true, 'report_id', rep.id);
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 8) Merchant functions with a session (same behaviour as today's functions, merchant taken from the session)
-- ----------------------------------------------------------------------------------------------------
create function public.merchant_me_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin m := public._sess_merchant(p_session); return jsonb_build_object('ok', true, 'merchant', public._merchant_json(m)); end $$;

create function public.merchant_transactions_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; r jsonb;
begin
  m := public._sess_merchant(p_session);
  perform public._expire_pending(null, m.id);
  -- no phone number: a masked reference and the first name only
  select coalesce(jsonb_agg(public._tx_json(t, 'merchant') || jsonb_build_object('cref', '••' || right(t.customer_phone, 2),
           'cname', case when c.name = 'زبون جديد' then null else c.name end) order by t.created_at desc), '[]'::jsonb) into r
    from (select * from public.pos_transactions where merchant_id = m.id order by created_at desc limit 500) t
    left join public.customers c on c.phone = t.customer_phone;
  return r;
end $$;

create function public.merchant_set_logo_v2(p_session text, p_logo_url text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  update public.merchants set logo_url = nullif(p_logo_url, '') where id = m.id returning * into m;
  return jsonb_build_object('ok', true, 'logo_url', m.logo_url);
end $$;
-- ----------------------------------------------------------------------------------------------------
-- 8b) Merchant pass-through functions: the merchant is the session's, never an id sent by the browser
-- ----------------------------------------------------------------------------------------------------
create function public.merchant_add_offer_v2(p_session text, p_type text, p_title text, p_badge text default 'جديد', p_val numeric default null, p_gift_text text default null, p_pts numeric default null, p_per numeric default null, p_old_price numeric default null, p_new_price numeric default null, p_img_url text default null, p_min_amount numeric default 0, p_days integer default 30, p_first_time_only boolean default false, p_specs text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_add_offer(m.id, p_type, p_title, p_badge, p_val, p_gift_text, p_pts, p_per, p_old_price, p_new_price, p_img_url, p_min_amount, p_days, p_first_time_only, p_specs);
end $$;
create function public.merchant_create_topup_order_v2(p_session text, p_amount numeric, p_points numeric, p_pack_label text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_create_topup_order(m.id, p_amount, p_points, p_pack_label);
end $$;
create function public.merchant_delete_offer_v2(p_session text, p_offer_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_delete_offer(p_offer_id, m.id);
end $$;
create function public.merchant_gallery_add_v2(p_session text, p_name text, p_price numeric, p_img_url text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_gallery_add(m.id, p_name, p_price, p_img_url);
end $$;
create function public.merchant_gallery_delete_v2(p_session text, p_item_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_gallery_delete(p_item_id, m.id);
end $$;
create function public.merchant_notes_list_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_notes_list(m.id);
end $$;
create function public.merchant_notes_mark_read_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_notes_mark_read(m.id);
end $$;
create function public.merchant_offers_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_offers(m.id);
end $$;
create function public.merchant_request_info_change_v2(p_session text, p_name text default null, p_addr text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_request_info_change(m.id, p_name, p_addr);
end $$;
create function public.merchant_request_manual_topup_v2(p_session text, p_amount numeric, p_points numeric, p_pack_label text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_request_manual_topup(m.id, p_amount, p_points, p_pack_label);
end $$;
create function public.merchant_set_offer_active_v2(p_session text, p_offer_id uuid, p_active boolean) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_set_offer_active(p_offer_id, m.id, p_active);
end $$;
create function public.merchant_set_redeem_pct_v2(p_session text, p_redeem_pct numeric, p_redeem_pct_vip numeric default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_set_redeem_pct(m.id, p_redeem_pct, p_redeem_pct_vip);
end $$;
create function public.merchant_submit_photo_v2(p_session text, p_photo_url text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_submit_photo(m.id, p_photo_url);
end $$;
create function public.merchant_topup_orders_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_topup_orders(m.id);
end $$;
create function public.merchant_update_page_v2(p_session text, p_blurb text default null, p_enabled boolean default false) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_update_page(m.id, p_blurb, p_enabled);
end $$;
create function public.merchant_wallet_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return public.merchant_wallet(m.id);
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 9) Admin functions with a session. «P» = primary admin only. Every change is written to tx_events.
-- ----------------------------------------------------------------------------------------------------
create function public.admin_add_category_v2(p_session text, p_name_ar text, p_parent_id uuid, p_icon text default '▦', p_color text default '#6b7a99', p_image text default null, p_slug text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_add_category(p_name_ar, p_parent_id, p_icon, p_color, p_image, p_slug);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_add_category', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_approve_merchant_photo_v2(p_session text, p_merchant_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_approve_merchant_photo(p_merchant_id);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_approve_merchant_photo', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_delete_customer_v2(p_session text, p_phone text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_delete_customer(p_phone, a.id);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_delete_customer', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_delete_merchant_v2(p_session text, p_merchant_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_delete_merchant(p_merchant_id, a.id);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_delete_merchant', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_delete_offer_v2(p_session text, p_offer_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_delete_offer(p_offer_id);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_delete_offer', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_force_delete_customer_v2(p_session text, p_phone text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_force_delete_customer(p_phone, a.id);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_force_delete_customer', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_force_delete_merchant_v2(p_session text, p_merchant_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_force_delete_merchant(p_merchant_id, a.id);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_force_delete_merchant', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_list_all_offers_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_list_all_offers();
  return r;
end $$;
create function public.admin_list_customers_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_list_customers();
  return r;
end $$;
create function public.admin_list_merchants_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_list_merchants();
  return r;
end $$;
create function public.admin_mark_order_collected_v2(p_session text, p_order_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_mark_order_collected(p_order_id);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_mark_order_collected', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_reject_merchant_photo_v2(p_session text, p_merchant_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_reject_merchant_photo(p_merchant_id);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_reject_merchant_photo', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_reset_merchant_pin_v2(p_session text, p_pin text, p_merchant_id uuid, p_new_pin text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_reset_merchant_pin(a.id, p_pin, p_merchant_id, p_new_pin);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_reset_merchant_pin', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_resolve_topup_order_v2(p_session text, p_order_id uuid, p_approve boolean) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_resolve_topup_order(p_order_id, p_approve);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_resolve_topup_order', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_review_info_change_v2(p_session text, p_merchant_id uuid, p_approve boolean) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_review_info_change(p_merchant_id, p_approve);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_review_info_change', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_set_category_active_v2(p_session text, p_id uuid, p_active boolean) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_set_category_active(p_id, p_active);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_set_category_active', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_set_customer_status_v2(p_session text, p_phone text, p_status text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_set_customer_status(p_phone, p_status);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_set_customer_status', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_set_merchant_category_v2(p_session text, p_merchant_id uuid, p_cat text, p_extra_cats text[] default '{}'::text[]) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_set_merchant_category(p_merchant_id, p_cat, p_extra_cats);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_set_merchant_category', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_set_merchant_photo_v2(p_session text, p_merchant_id uuid, p_photo_url text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_set_merchant_photo(p_merchant_id, p_photo_url);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_set_merchant_photo', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_set_merchant_status_v2(p_session text, p_merchant_id uuid, p_status text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_set_merchant_status(p_merchant_id, p_status);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_set_merchant_status', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_topup_merchant_v2(p_session text, p_merchant_id uuid, p_amount numeric, p_source text default 'admin') returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_topup_merchant(p_merchant_id, p_amount, p_source);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_topup_merchant', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_topup_orders_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_topup_orders();
  return r;
end $$;
create function public.admin_update_category_v2(p_session text, p_id uuid, p_name_ar text default null, p_icon text default null, p_color text default null, p_image text default null, p_sort_order integer default null, p_parent_id uuid default null, p_clear_parent boolean default false) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_update_category(p_id, p_name_ar, p_icon, p_color, p_image, p_sort_order, p_parent_id, p_clear_parent);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_update_category', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_update_merchant_location_v2(p_session text, p_merchant_id uuid, p_lat numeric, p_lng numeric, p_x numeric, p_y numeric, p_addr text default null, p_area text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_update_merchant_location(p_merchant_id, p_lat, p_lng, p_x, p_y, p_addr, p_area);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_update_merchant_location', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_update_offer_image_v2(p_session text, p_offer_id uuid, p_img_url text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_update_offer_image(p_offer_id, p_img_url);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_update_offer_image', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_update_text_settings_v2(p_session text, p_settings jsonb) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_update_text_settings(a.id, p_settings);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_update_text_settings', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_warn_merchant_v2(p_session text, p_merchant_id uuid, p_max_warns integer default 3) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, false);
  r := public.admin_warn_merchant(p_merchant_id, p_max_warns);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_warn_merchant', 'admin', a.id, 'result', r));
  return r;
end $$;
create function public.admin_wipe_all_data_v2(p_session text, p_pin text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  r := public.admin_wipe_all_data(a.id, p_pin);
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_wipe_all_data', 'admin', a.id, 'result', r));
  return r;
end $$;

create function public.admin_security_feed_v2(p_session text, p_limit integer default 200) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; ev jsonb; rp jsonb;
begin
  a := public._sess_admin(p_session, false);
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', floor(extract(epoch from e.at) * 1000), 'event', e.event, 'role', e.actor_role,
           'phone', e.customer_phone, 'mid', e.merchant_id, 'mname', m.name, 'tx', e.tx_id, 'detail', e.detail) order by e.at desc), '[]'::jsonb) into ev
    from (select * from public.tx_events
           where event like 'alert_%' or event in ('reported','scan_failed','decide_hash_mismatch','qr_issue_limited','login_failed','admin_action')
           order by at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) e
    left join public.merchants m on m.id = e.merchant_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'at', floor(extract(epoch from r.created_at) * 1000), 'tx', r.tx_id, 'code', r.code_id,
           'role', r.reporter_role, 'reporter', r.reporter, 'reason', r.reason, 'note', r.note, 'status', r.status) order by r.created_at desc), '[]'::jsonb) into rp
    from (select * from public.tx_reports order by created_at desc limit 300) r;
  return jsonb_build_object('ok', true, 'events', ev, 'reports', rp);
end $$;

create function public.admin_resolve_report_v2(p_session text, p_report_id uuid, p_status text, p_note text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  if p_status not in ('reviewed','dismissed') then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  update public.tx_reports set status = p_status, admin_note = left(p_note, 500), resolved_at = now(), resolved_by = a.id where id = p_report_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_resolve_report_v2', 'admin', a.id, 'report', p_report_id, 'status', p_status));
  return jsonb_build_object('ok', true);
end $$;

-- limits are editable without a migration; only the keys of this phase, inside sane ranges
create function public.admin_settings_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  return (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.app_settings);
end $$;

create function public.admin_set_setting_v2(p_session text, p_key text, p_value numeric) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; lo numeric; hi numeric;
begin
  a := public._sess_admin(p_session, true);
  select x.lo, x.hi into lo, hi from (values
    ('qr_ttl_sec', 60, 900), ('qr_claim_ttl_sec', 60, 1800), ('qr_issue_per_hour', 5, 200), ('scan_fail_limit', 3, 100), ('manual_code_fail_limit', 3, 20),
    ('scan_fail_window_min', 1, 120), ('scan_lock_min', 1, 240), ('login_fail_limit', 3, 20), ('login_ip_fail_limit', 10, 500), ('login_window_min', 1, 120),
    ('login_lock_min', 1, 240), ('session_days', 1, 90), ('session_max_days', 7, 365), ('admin_session_hours', 1, 72), ('tx_pending_sec', 60, 1800),
    ('tx_max_invoice', 10, 1000000), ('treasure_min_invoice', 0, 10000), ('profile_photo_max_kb', 30, 400), ('report_per_day', 1, 50),
    ('alert_same_shop_per_day', 2, 100), ('alert_merchant_per_hour', 5, 1000), ('alert_customer_shops_per_hour', 2, 50)) as x(k, lo, hi)
   where x.k = p_key;
  if lo is null then return jsonb_build_object('ok', false, 'error', 'unknown_key'); end if;
  if p_value is null or p_value < lo or p_value > hi then return jsonb_build_object('ok', false, 'error', format('القيمة يجب أن تكون بين %s و %s', lo, hi)); end if;
  insert into public.app_settings(key, value) values (p_key, p_value) on conflict (key) do update set value = excluded.value;
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_set_setting_v2', 'admin', a.id, 'key', p_key, 'value', p_value));
  return jsonb_build_object('ok', true);
end $$;

create function public.admin_treasure_list_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'slug', p.slug, 'name', p.name, 'note', p.note, 'img', p.img_url, 'order', p.display_order,
          'active', p.active, 'unlocked_by', (select count(*) from public.customer_unlocks u where u.pic_id = p.id and u.merchant_id is not null)) order by p.display_order, p.created_at), '[]'::jsonb)
          from public.treasure_pics p);
end $$;

-- add or edit a landmark. Progress already made never changes: an unlock stores its picture, and a new landmark only
-- becomes the next one to discover. Pictures are hidden (active = false), never deleted, so collections stay intact.
create function public.admin_treasure_upsert_v2(p_session text, p_id uuid, p_name text, p_note text default null, p_img_url text default null,
  p_display_order integer default null, p_active boolean default true) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r public.treasure_pics;
begin
  a := public._sess_admin(p_session, false);
  if p_name is null or length(trim(p_name)) = 0 or length(p_name) > 80 then return jsonb_build_object('ok', false, 'error', 'اكتب اسم المعلم'); end if;
  if p_id is null then
    insert into public.treasure_pics(name, note, img_url, display_order, active, slug)
    values (trim(p_name), p_note, p_img_url, coalesce(p_display_order, (select coalesce(max(display_order), 0) + 10 from public.treasure_pics)), coalesce(p_active, true),
            't' || substr(md5(gen_random_uuid()::text), 1, 8))
    returning * into r;
  else
    update public.treasure_pics set name = trim(p_name), note = p_note, img_url = coalesce(p_img_url, img_url),
      display_order = coalesce(p_display_order, display_order), active = coalesce(p_active, active)
     where id = p_id returning * into r;
    if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_treasure_upsert_v2', 'admin', a.id, 'pic', r.id));
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;

-- ----------------------------------------------------------------------------------------------------
-- 10) Treasures list (the 11 landmarks of the app today, same order). Adding more later: admin_treasure_upsert_v2.
-- ----------------------------------------------------------------------------------------------------
-- rows that were already in the table (none in Production today) are kept but hidden, so the official order starts at p1;
-- an admin can show them again with admin_treasure_upsert_v2.
do $$ declare n int; begin update public.treasure_pics set active = false where slug is null; get diagnostics n = row_count;
  if n > 0 then raise notice 'treasure_pics: % existing row(s) hidden (active = false)', n; end if; end $$;
insert into public.treasure_pics(slug, name, note, img_url, display_order) values
  ('p1', 'قلعة طرابلس (سان جيل)', 'أقدم قلعة في المدينة، تطل على طرابلس منذ القرن الثاني عشر', 'assets/img/treasure-p1.447155039f.jpg', 10),
  ('p2', 'الميناء القديم', 'الحي البحري العريق بمينائه وأسواقه السمكية', 'assets/img/treasure-p2.a8375548ca.jpg', 20),
  ('p3', 'الأسواق الداخلية', 'الأسواق المسقوفة القديمة بعمارتها المملوكية ومحالها التقليدية', 'assets/img/treasure-p3.9a60256500.jpg', 30),
  ('p4', 'خان الصابون', 'خان أثري يعكس صناعة الصابون العريقة في طرابلس', 'assets/img/treasure-p4.e3a1068b66.jpg', 40),
  ('p5', 'جامع طينال', 'أحد أجمل المساجد المملوكية في المدينة', 'assets/img/treasure-p5.a0ca4ca1e1.jpg', 50),
  ('p6', 'ساعة التل', 'الساعة العثمانية الشهيرة في ساحة التل', 'assets/img/treasure-p6.188c9cea02.jpg', 60),
  ('p7', 'جزر النخيل', 'محمية طبيعية بحرية قبالة سواحل طرابلس', 'assets/img/treasure-p7.915ba280b1.jpg', 70),
  ('p8', 'خان الخياطين', 'خان مملوكي أثري وسط الأسواق القديمة', 'assets/img/treasure-p8.dec427a394.jpg', 80),
  ('p9', 'قلعة طرابلس من الداخل', 'باحات وأسوار القلعة الداخلية كما تبدو للزائر', 'assets/img/treasure-p9.f5080fc565.jpg', 90),
  ('p10', 'المولوية', 'تكية المولوية الأثرية، معلم ثقافي وديني في قلب المدينة', 'assets/img/treasure-p10.a4e1a591ed.jpg', 100),
  ('p11', 'معرض طرابلس الدولي', 'معرض رشيد كرامي، تحفة معمارية لأوسكار نيماير', 'assets/img/treasure-p11.ea2afec8be.jpg', 110)
on conflict (slug) do nothing;

-- ----------------------------------------------------------------------------------------------------
-- 11) Privileges. Supabase grants EXECUTE on new functions to anon by default: everything is revoked first,
--     then only the API functions (no leading underscore) are granted. Internal helpers stay unreachable.
-- ----------------------------------------------------------------------------------------------------
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['_alerts_after_confirm', '_b64url', '_claim_for', '_client_ip', '_customer_json', '_ev', '_expire_pending', '_issue_session', '_login_allowed', '_login_failed', '_merchant_json', '_rl2_hit', '_rl2_locked', '_rl2_reset', '_sess', '_sess_admin', '_sess_any', '_sess_customer', '_sess_merchant', '_setting', '_sha', '_tr_revoke_sessions', '_tr_unlocks_skip_legacy', '_tx_hash', '_tx_json', '_tx_quote', '_unlock_treasure', 'admin_add_category_v2', 'admin_approve_merchant_photo_v2', 'admin_delete_customer_v2', 'admin_delete_merchant_v2', 'admin_delete_offer_v2', 'admin_force_delete_customer_v2', 'admin_force_delete_merchant_v2', 'admin_list_all_offers_v2', 'admin_list_customers_v2', 'admin_list_merchants_v2', 'admin_login', 'admin_mark_order_collected_v2', 'admin_reject_merchant_photo_v2', 'admin_reset_merchant_pin_v2', 'admin_resolve_report_v2', 'admin_resolve_topup_order_v2', 'admin_review_info_change_v2', 'admin_security_feed_v2', 'admin_set_category_active_v2', 'admin_set_customer_status_v2', 'admin_set_merchant_category_v2', 'admin_set_merchant_photo_v2', 'admin_set_merchant_status_v2', 'admin_set_setting_v2', 'admin_settings_v2', 'admin_topup_merchant_v2', 'admin_topup_orders_v2', 'admin_treasure_list_v2', 'admin_treasure_upsert_v2', 'admin_update_category_v2', 'admin_update_merchant_location_v2', 'admin_update_offer_image_v2', 'admin_update_text_settings_v2', 'admin_warn_merchant_v2', 'admin_wipe_all_data_v2', 'customer_decide_tx_v2', 'customer_login', 'customer_notes_list_v2', 'customer_notes_mark_read_v2', 'customer_profile_v2', 'customer_qr_issue', 'customer_qr_status', 'customer_register_v2', 'customer_transactions_v2', 'customer_treasures_v2', 'customer_update_profile', 'merchant_add_offer_v2', 'merchant_cancel_tx', 'merchant_create_topup_order_v2', 'merchant_create_tx_v2', 'merchant_delete_offer_v2', 'merchant_gallery_add_v2', 'merchant_gallery_delete_v2', 'merchant_login', 'merchant_me_v2', 'merchant_notes_list_v2', 'merchant_notes_mark_read_v2', 'merchant_offers_v2', 'merchant_quote_v2', 'merchant_register_v2', 'merchant_request_info_change_v2', 'merchant_request_manual_topup_v2', 'merchant_scan_code', 'merchant_set_logo_v2', 'merchant_set_offer_active_v2', 'merchant_set_redeem_pct_v2', 'merchant_submit_photo_v2', 'merchant_topup_orders_v2', 'merchant_transactions_v2', 'merchant_update_page_v2', 'merchant_wallet_v2', 'report_tx', 'session_list', 'session_logout', 'session_logout_all', 'session_revoke', 'treasure_list']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['admin_add_category_v2', 'admin_approve_merchant_photo_v2', 'admin_delete_customer_v2', 'admin_delete_merchant_v2', 'admin_delete_offer_v2', 'admin_force_delete_customer_v2', 'admin_force_delete_merchant_v2', 'admin_list_all_offers_v2', 'admin_list_customers_v2', 'admin_list_merchants_v2', 'admin_login', 'admin_mark_order_collected_v2', 'admin_reject_merchant_photo_v2', 'admin_reset_merchant_pin_v2', 'admin_resolve_report_v2', 'admin_resolve_topup_order_v2', 'admin_review_info_change_v2', 'admin_security_feed_v2', 'admin_set_category_active_v2', 'admin_set_customer_status_v2', 'admin_set_merchant_category_v2', 'admin_set_merchant_photo_v2', 'admin_set_merchant_status_v2', 'admin_set_setting_v2', 'admin_settings_v2', 'admin_topup_merchant_v2', 'admin_topup_orders_v2', 'admin_treasure_list_v2', 'admin_treasure_upsert_v2', 'admin_update_category_v2', 'admin_update_merchant_location_v2', 'admin_update_offer_image_v2', 'admin_update_text_settings_v2', 'admin_warn_merchant_v2', 'admin_wipe_all_data_v2', 'customer_decide_tx_v2', 'customer_login', 'customer_notes_list_v2', 'customer_notes_mark_read_v2', 'customer_profile_v2', 'customer_qr_issue', 'customer_qr_status', 'customer_register_v2', 'customer_transactions_v2', 'customer_treasures_v2', 'customer_update_profile', 'merchant_add_offer_v2', 'merchant_cancel_tx', 'merchant_create_topup_order_v2', 'merchant_create_tx_v2', 'merchant_delete_offer_v2', 'merchant_gallery_add_v2', 'merchant_gallery_delete_v2', 'merchant_login', 'merchant_me_v2', 'merchant_notes_list_v2', 'merchant_notes_mark_read_v2', 'merchant_offers_v2', 'merchant_quote_v2', 'merchant_register_v2', 'merchant_request_info_change_v2', 'merchant_request_manual_topup_v2', 'merchant_scan_code', 'merchant_set_logo_v2', 'merchant_set_offer_active_v2', 'merchant_set_redeem_pct_v2', 'merchant_submit_photo_v2', 'merchant_topup_orders_v2', 'merchant_transactions_v2', 'merchant_update_page_v2', 'merchant_wallet_v2', 'report_tx', 'session_list', 'session_logout', 'session_logout_all', 'session_revoke', 'treasure_list']) loop
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end $$;

commit;
