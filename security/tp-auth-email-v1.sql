-- =====================================================================================================
-- Tripoli Points — EMAIL VERIFICATION AND PIN RECOVERY (STAGING, after tp-secure-purchase-v1.sql)
-- File: tp-auth-email-v1.sql                            Prepared 2026-11-11 · NOT EXECUTED ANYWHERE
-- =====================================================================================================
-- One account system: phone + PIN login and the sessions of phase 1. The e-mail is a verified attribute of the
-- customer / merchant account, used to finish registration and to recover a PIN. No Supabase Auth users.
--
--   Registration   app → Edge Function auth-email {register_start} → _email_register_start (this file) → e-mail
--                  with a 6-digit code + a link → app: register_confirm (code, or link on any device)
--                  → the account is created only now (customer_register / merchant_register reused) → session.
--   Old accounts   signed in (session) → auth-email {email_add_start} → code → email_add_confirm. Same row: points,
--                  purchases, notes and treasures do not move.
--   Forgot PIN     auth-email {pin_reset_start, phone} → code/link to the VERIFIED e-mail only → pin_reset_confirm
--                  (new PIN) → every old session ends (phase-1 trigger) → new session. The old PIN is never shown:
--                  it is stored only as a bcrypt hash and cannot be recovered by anyone.
--
-- Codes and links: 6 digits + a 32-byte link, both stored as SHA-256 only; registration / add 30 min, PIN reset 15 min;
-- used once (atomic update); 5 wrong codes kill the code; a new request replaces the previous one; 60 s between e-mails;
-- per-hour limits per phone, e-mail and IP. All limits are settings.
-- The raw code and link exist only inside the _email_*_start functions, which only service_role (the Edge Function)
-- can call; they are returned to it once to put in the e-mail.
-- =====================================================================================================
begin;

do $$ begin
  if to_regclass('public.app_sessions') is null then raise exception 'run tp-secure-purchase-v1.sql first'; end if;
  if to_regclass('public.email_tokens') is not null then raise exception 'already applied'; end if;
end $$;

insert into public.app_settings(key, value) values
  ('email_code_ttl_min', 30), ('email_reset_ttl_min', 15), ('email_code_attempts', 5), ('email_resend_sec', 60),
  ('email_per_hour_per_address', 5), ('email_per_hour_per_phone', 5), ('email_per_hour_per_ip', 20),
  ('email_pending_hours', 24)
on conflict (key) do nothing;

-- ---------------------------------------------------------------- tables and columns
alter table public.customers add column email text, add column email_verified_at timestamptz;
alter table public.merchants add column email text, add column email_verified_at timestamptz;
create unique index customers_email_verified_uidx on public.customers (lower(email)) where email_verified_at is not null;
create unique index merchants_email_verified_uidx on public.merchants (lower(email)) where email_verified_at is not null;

create table public.pending_registrations (
  id uuid primary key default gen_random_uuid(),
  role text not null check (role in ('customer','merchant')),
  phone text not null,
  pin_hash text not null,                        -- bcrypt of the chosen PIN; the PIN itself is never stored
  email text not null,
  data jsonb not null default '{}'::jsonb,       -- merchant registration fields (name, category, location …)
  terms_version text,
  ip text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  completed_at timestamptz,
  superseded_at timestamptz
);
create index pending_registrations_phone_idx on public.pending_registrations(role, phone) where completed_at is null and superseded_at is null;

create table public.email_tokens (
  id uuid primary key default gen_random_uuid(),
  purpose text not null check (purpose in ('register','add_email','reset_pin')),
  role text not null check (role in ('customer','merchant')),
  pending_id uuid references public.pending_registrations(id) on delete cascade,
  customer_phone text references public.customers(phone) on delete cascade,
  merchant_id uuid references public.merchants(id) on delete cascade,
  email text not null,
  link_hash bytea not null unique,
  code_hash bytea not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz,
  superseded_at timestamptz,
  attempts integer not null default 0,
  send_status text not null default 'pending' check (send_status in ('pending','sent','failed')),
  provider_id text,
  ip text
);
create index email_tokens_subject_idx on public.email_tokens(purpose, role, customer_phone, merchant_id, pending_id) where used_at is null and superseded_at is null;

do $$ declare t text; begin
  foreach t in array array['pending_registrations','email_tokens'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------- helpers (internal)
create function public._email_norm(p text) returns text language sql immutable set search_path = public, pg_temp as $$
  select nullif(lower(trim(p)), '')
$$;
create function public._email_valid(p text) returns boolean language sql immutable set search_path = public, pg_temp as $$
  select p is not null and length(p) <= 254 and p ~ '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$'
$$;
create function public._email_mask(p text) returns text language sql immutable set search_path = public, pg_temp as $$
  select case when p is null then null else left(split_part(p, '@', 1), 1) || repeat('•', greatest(2, least(6, length(split_part(p, '@', 1)) - 1)))
         || '@' || split_part(p, '@', 2) end
$$;

-- issues a code + link for one subject; the previous open token of the same subject is replaced
create function public._email_issue(p_purpose text, p_role text, p_pending uuid, p_phone text, p_mid uuid, p_email text, p_ttl_min int)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare tid uuid := gen_random_uuid(); link text; code text; last_at timestamptz;
begin
  select max(created_at) into last_at from public.email_tokens
   where purpose = p_purpose and role = p_role and email = p_email
     and pending_id is not distinct from p_pending and customer_phone is not distinct from p_phone and merchant_id is not distinct from p_mid;
  if last_at > now() - make_interval(secs => public._setting('email_resend_sec', 60)::int) then
    return jsonb_build_object('ok', false, 'error', 'too_soon', 'retry_in', ceil(extract(epoch from last_at + make_interval(secs => public._setting('email_resend_sec', 60)::int) - now())),
      'message', 'انتظر قليلاً قبل طلب رسالة جديدة');
  end if;
  if not public._rl2_hit('mail:addr:' || p_email, public._setting('email_per_hour_per_address', 5)::int, 3600, 0) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'message', 'طلبات كثيرة لهذا البريد. حاول بعد ساعة');
  end if;
  update public.email_tokens set superseded_at = now()
   where purpose = p_purpose and role = p_role and used_at is null and superseded_at is null
     and pending_id is not distinct from p_pending and customer_phone is not distinct from p_phone and merchant_id is not distinct from p_mid;
  link := public._b64url(extensions.gen_random_bytes(32));
  code := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
  insert into public.email_tokens(id, purpose, role, pending_id, customer_phone, merchant_id, email, link_hash, code_hash, expires_at, ip)
  values (tid, p_purpose, p_role, p_pending, p_phone, p_mid, p_email, public._sha('link:' || link), public._sha('code:' || tid || ':' || code),
          now() + make_interval(mins => p_ttl_min), public._client_ip());
  perform public._ev('email_' || p_purpose || '_sent', p_role, p_phone, p_mid, null, null, jsonb_build_object('token', tid));
  return jsonb_build_object('ok', true, 'token_id', tid, 'link_token', link, 'code', code, 'email', p_email,
    'masked', public._email_mask(p_email), 'ttl_min', p_ttl_min, 'purpose', p_purpose, 'role', p_role);
end $$;

-- consumes a token: by link alone, or by code + subject. One use; wrong codes counted; returns the token row or null.
create function public._email_consume(p_purpose text, p_link text, p_code text, p_role text, p_pending uuid, p_phone text, p_mid uuid)
returns public.email_tokens language plpgsql security definer set search_path = public, pg_temp as $$
declare t public.email_tokens; maxa int := public._setting('email_code_attempts', 5)::int;
begin
  if p_link is not null and length(p_link) between 20 and 100 then
    update public.email_tokens set used_at = now()
     where link_hash = public._sha('link:' || p_link) and purpose = p_purpose and used_at is null and superseded_at is null
       and expires_at > now() and attempts < maxa
    returning * into t;
    return t;
  end if;
  if p_code is null or p_code !~ '^\d{6}$' then return null; end if;
  select * into t from public.email_tokens
   where purpose = p_purpose and role = p_role and used_at is null and superseded_at is null
     and pending_id is not distinct from p_pending and customer_phone is not distinct from p_phone and merchant_id is not distinct from p_mid
   order by created_at desc limit 1 for update;
  if t.id is null or t.expires_at <= now() or t.attempts >= maxa then return null; end if;
  if t.code_hash <> public._sha('code:' || t.id || ':' || p_code) then
    update public.email_tokens set attempts = attempts + 1 where id = t.id;
    return null;
  end if;
  update public.email_tokens set used_at = now() where id = t.id and used_at is null returning * into t;
  return t;
end $$;

-- ---------------------------------------------------------------- start functions (service_role only: the Edge Function)
create function public._email_register_start(p_role text, p_phone text, p_pin text, p_email text, p_terms_version text default null,
  p_data jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare em text := public._email_norm(p_email); pr public.pending_registrations; ip text := coalesce(public._client_ip(), 'noip');
begin
  if p_role not in ('customer','merchant') then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if p_phone is null or p_phone !~ '^\d{7,8}$' then return jsonb_build_object('ok', false, 'error', 'phone', 'message', 'رقم الهاتف غير صحيح'); end if;
  if p_pin is null or p_pin !~ '^\d{4}$' then return jsonb_build_object('ok', false, 'error', 'pin', 'message', 'رمز الحماية يجب أن يكون 4 أرقام'); end if;
  if not public._email_valid(em) then return jsonb_build_object('ok', false, 'error', 'email', 'message', 'البريد الإلكتروني غير صحيح'); end if;
  if not public._rl2_hit('mail:ip:' || ip, public._setting('email_per_hour_per_ip', 20)::int, 3600, 0)
     or not public._rl2_hit('mail:phone:' || p_role || ':' || p_phone, public._setting('email_per_hour_per_phone', 5)::int, 3600, 0) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'message', 'طلبات كثيرة. حاول بعد ساعة');
  end if;
  if (p_role = 'customer' and exists (select 1 from public.customers where phone = p_phone))
     or (p_role = 'merchant' and exists (select 1 from public.merchants where phone = p_phone)) then
    return jsonb_build_object('ok', false, 'error', 'phone_taken', 'message', 'هذا الرقم مسجّل. سجّل الدخول، أو استرجع رمزك من «نسيت رمز الحماية»');
  end if;
  if (p_role = 'customer' and exists (select 1 from public.customers where lower(email) = em and email_verified_at is not null))
     or (p_role = 'merchant' and exists (select 1 from public.merchants where lower(email) = em and email_verified_at is not null)) then
    return jsonb_build_object('ok', false, 'error', 'email_taken', 'message', 'هذا البريد مستعمل لحساب آخر');
  end if;
  if p_role = 'merchant' and (coalesce(trim(p_data->>'name'), '') = '' or coalesce(p_data->>'cat', '') = '') then
    return jsonb_build_object('ok', false, 'error', 'bad_request', 'message', 'أكمل معلومات المحل');
  end if;
  -- 60 s between e-mails for the same number, checked before anything changes (a refused request leaves the
  -- registration in progress untouched)
  if exists (select 1 from public.email_tokens t join public.pending_registrations p on p.id = t.pending_id
              where p.role = p_role and p.phone = p_phone and t.created_at > now() - make_interval(secs => public._setting('email_resend_sec', 60)::int)) then
    return jsonb_build_object('ok', false, 'error', 'too_soon', 'message', 'انتظر قليلاً قبل طلب رسالة جديدة');
  end if;
  update public.pending_registrations set superseded_at = now()
   where role = p_role and phone = p_phone and completed_at is null and superseded_at is null;
  insert into public.pending_registrations(role, phone, pin_hash, email, data, terms_version, ip, expires_at)
  values (p_role, p_phone, extensions.crypt(p_pin, extensions.gen_salt('bf')), em, coalesce(p_data, '{}'::jsonb), p_terms_version, ip,
          now() + make_interval(hours => public._setting('email_pending_hours', 24)::int))
  returning * into pr;
  return public._email_issue('register', p_role, pr.id, null, null, em, public._setting('email_code_ttl_min', 30)::int)
         || jsonb_build_object('pending_id', pr.id);
end $$;

-- resend for a registration in progress (same pending row, new code + link, old ones stop working)
create function public._email_register_resend(p_pending_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare pr public.pending_registrations;
begin
  select * into pr from public.pending_registrations where id = p_pending_id and completed_at is null and superseded_at is null and expires_at > now();
  if pr.id is null then return jsonb_build_object('ok', false, 'error', 'expired', 'message', 'انتهت مهلة التسجيل. ابدأ من جديد'); end if;
  return public._email_issue('register', pr.role, pr.id, null, null, pr.email, public._setting('email_code_ttl_min', 30)::int)
         || jsonb_build_object('pending_id', pr.id);
end $$;

-- add (or change) the e-mail of a signed-in account. Changing a verified e-mail needs the PIN again.
create function public._email_add_start(p_session text, p_email text, p_pin text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare s public.app_sessions; em text := public._email_norm(p_email); c public.customers; m public.merchants; cur text; ph text; ok_pin boolean;
begin
  select * into s from public.app_sessions where token_hash = public._sha(coalesce(p_session, ''));
  if s.role = 'customer' then c := public._sess_customer(p_session); cur := case when c.email_verified_at is not null then c.email end; ph := c.pin_hash;
  elsif s.role = 'merchant' then m := public._sess_merchant(p_session); cur := case when m.email_verified_at is not null then m.email end; ph := m.pin_hash;
  else raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required'; end if;
  if not public._email_valid(em) then return jsonb_build_object('ok', false, 'error', 'email', 'message', 'البريد الإلكتروني غير صحيح'); end if;
  if cur is not null and lower(cur) = em then return jsonb_build_object('ok', false, 'error', 'same', 'message', 'هذا هو بريدك الموثّق حالياً'); end if;
  if cur is not null then   -- changing a verified e-mail: the PIN, with the October lock
    if public._rl_locked(s.role || ':' || coalesce(c.phone, m.phone)) then return jsonb_build_object('ok', false, 'error', 'locked', 'message', 'عدد محاولات خاطئة كبير، حاول بعد 15 دقيقة'); end if;
    ok_pin := p_pin is not null and extensions.crypt(p_pin, ph) = ph;
    if not ok_pin then perform public._rl_record_fail(s.role || ':' || coalesce(c.phone, m.phone)); return jsonb_build_object('ok', false, 'error', 'wrong_pin', 'message', 'رمز الحماية غير صحيح'); end if;
  end if;
  if (s.role = 'customer' and exists (select 1 from public.customers where lower(email) = em and email_verified_at is not null and phone <> c.phone))
     or (s.role = 'merchant' and exists (select 1 from public.merchants where lower(email) = em and email_verified_at is not null and id <> m.id)) then
    return jsonb_build_object('ok', false, 'error', 'email_taken', 'message', 'هذا البريد مستعمل لحساب آخر');
  end if;
  if not public._rl2_hit('mail:phone:' || s.role || ':' || coalesce(c.phone, m.phone), public._setting('email_per_hour_per_phone', 5)::int, 3600, 0) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'message', 'طلبات كثيرة. حاول بعد ساعة');
  end if;
  return public._email_issue('add_email', s.role, null, c.phone, m.id, em, public._setting('email_code_ttl_min', 30)::int)
         || jsonb_build_object('previous', public._email_mask(cur));
end $$;

-- forgotten PIN: only to an e-mail already verified on that account. Same answer shape whether or not one exists.
create function public._email_reset_start(p_role text, p_phone text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare em text; c public.customers; m public.merchants; ip text := coalesce(public._client_ip(), 'noip');
begin
  if p_role not in ('customer','merchant') or p_phone is null or p_phone !~ '^\d{7,8}$' then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if not public._rl2_hit('mail:ip:' || ip, public._setting('email_per_hour_per_ip', 20)::int, 3600, 0)
     or not public._rl2_hit('mail:reset:' || p_role || ':' || p_phone, 3, 3600, 0) then
    return jsonb_build_object('ok', false, 'error', 'rate_limited', 'message', 'طلبات كثيرة. حاول بعد ساعة');
  end if;
  if p_role = 'customer' then select * into c from public.customers where phone = p_phone; em := case when c.email_verified_at is not null then c.email end;
  else select * into m from public.merchants where phone = p_phone; em := case when m.email_verified_at is not null then m.email end; end if;
  if em is null then
    perform public._ev('email_reset_no_email', p_role, case when p_role = 'customer' then p_phone end, m.id, null, null);
    return jsonb_build_object('ok', false, 'error', 'no_verified_email',
      'message', 'لا يوجد بريد موثّق لهذا الحساب. تواصل مع الدعم لاسترجاع رمزك');
  end if;
  return public._email_issue('reset_pin', p_role, null, c.phone, m.id, em, public._setting('email_reset_ttl_min', 15)::int);
end $$;

-- the Edge Function reports the provider's answer; a failed send leaves the code unusable
create function public._email_mark_sent(p_token_id uuid, p_ok boolean, p_provider_id text default null) returns void
language sql security definer set search_path = public, pg_temp as $$
  update public.email_tokens set send_status = case when p_ok then 'sent' else 'failed' end, provider_id = left(p_provider_id, 120),
         superseded_at = case when p_ok then superseded_at else now() end
   where id = p_token_id
$$;

-- ---------------------------------------------------------------- confirm functions (the app, public key)
create function public.register_confirm(p_pending_id uuid default null, p_code text default null, p_link text default null, p_device text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare t public.email_tokens; pr public.pending_registrations; wb numeric; wd int; mid uuid; c public.customers; m public.merchants; d jsonb; tmp text;
begin
  if p_link is null and p_pending_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if p_pending_id is not null and public._rl2_locked('mailcode:' || p_pending_id) then
    return jsonb_build_object('ok', false, 'error', 'locked', 'message', 'محاولات خاطئة كثيرة. اطلب رمزاً جديداً');
  end if;
  select * into pr from public.pending_registrations where id = p_pending_id;
  t := public._email_consume('register', p_link, p_code, pr.role, p_pending_id, null, null);
  if t.id is null then
    if p_pending_id is not null then perform public._rl2_hit('mailcode:' || p_pending_id, 10, 1800, 1800); end if;
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'message', 'الرمز غير صحيح أو انتهت صلاحيته');
  end if;
  select * into pr from public.pending_registrations where id = t.pending_id for update;
  if pr.id is null or pr.completed_at is not null or pr.superseded_at is not null or pr.expires_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'expired', 'message', 'انتهت مهلة التسجيل. ابدأ من جديد');
  end if;
  -- the number or the e-mail may have been taken since the code was sent
  if (pr.role = 'customer' and exists (select 1 from public.customers where phone = pr.phone))
     or (pr.role = 'merchant' and exists (select 1 from public.merchants where phone = pr.phone)) then
    return jsonb_build_object('ok', false, 'error', 'phone_taken', 'message', 'هذا الرقم سُجّل للتو. سجّل الدخول');
  end if;
  if (pr.role = 'customer' and exists (select 1 from public.customers where lower(email) = pr.email and email_verified_at is not null))
     or (pr.role = 'merchant' and exists (select 1 from public.merchants where lower(email) = pr.email and email_verified_at is not null)) then
    return jsonb_build_object('ok', false, 'error', 'email_taken', 'message', 'هذا البريد مستعمل لحساب آخر');
  end if;
  tmp := lpad(((('x' || encode(extensions.gen_random_bytes(2), 'hex'))::bit(16)::int) % 10000)::text, 4, '0');  -- replaced by the real hash below
  if pr.role = 'customer' then
    begin wb := nullif(trim((select value from public.app_text_settings where key = 'welcome_bonus')), '')::numeric; exception when others then wb := 0; end;
    begin wd := nullif(trim((select value from public.app_text_settings where key = 'welcome_days')), '')::numeric::int; exception when others then wd := 0; end;
    perform public.customer_register(pr.phone, tmp, 'زبون جديد', greatest(0, least(coalesce(wb, 0), 100000)), greatest(0, coalesce(wd, 0)), pr.terms_version);
    update public.customers set pin_hash = pr.pin_hash, email = pr.email, email_verified_at = now() where phone = pr.phone returning * into c;
  else
    d := pr.data;
    perform public.merchant_register(d->>'name', pr.phone, tmp, d->>'cat', (d->>'pct')::numeric, d->>'addr', (d->>'x')::numeric, (d->>'y')::numeric,
      (d->>'lat')::numeric, (d->>'lng')::numeric, d->>'photo_url', coalesce((d->>'redeem_pct')::numeric, 5),
      coalesce(array(select jsonb_array_elements_text(coalesce(d->'extra_cats', '[]'::jsonb))), '{}'::text[]), pr.terms_version, d->>'area');
    update public.merchants set pin_hash = pr.pin_hash, email = pr.email, email_verified_at = now() where phone = pr.phone returning * into m;
  end if;
  update public.pending_registrations set completed_at = now() where id = pr.id;
  perform public._ev('registered', pr.role, c.phone, m.id, null, null, jsonb_build_object('email_verified', true));
  if pr.role = 'customer' then
    return jsonb_build_object('ok', true, 'role', 'customer', 'customer', public._customer_json(c, true))
           || public._issue_session('customer', c.phone, null, null, p_device);
  end if;
  return jsonb_build_object('ok', true, 'role', 'merchant', 'merchant', public._merchant_json(m))
         || public._issue_session('merchant', null, m.id, null, p_device);
exception when raise_exception then
  return jsonb_build_object('ok', false, 'error', 'register_failed', 'message', sqlerrm);
end $$;

create function public.email_add_confirm(p_session text, p_code text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; c public.customers; m public.merchants; t public.email_tokens; who text;
begin
  select * into s from public.app_sessions where token_hash = public._sha(coalesce(p_session, ''));
  if s.role = 'customer' then c := public._sess_customer(p_session); who := c.phone;
  elsif s.role = 'merchant' then m := public._sess_merchant(p_session); who := m.id::text;
  else raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required'; end if;
  if public._rl2_locked('mailcode:add:' || who) then return jsonb_build_object('ok', false, 'error', 'locked', 'message', 'محاولات خاطئة كثيرة. اطلب رمزاً جديداً'); end if;
  t := public._email_consume('add_email', null, p_code, s.role, null, c.phone, m.id);
  if t.id is null then
    perform public._rl2_hit('mailcode:add:' || who, 10, 1800, 1800);
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'message', 'الرمز غير صحيح أو انتهت صلاحيته');
  end if;
  begin
    if s.role = 'customer' then update public.customers set email = t.email, email_verified_at = now() where phone = c.phone;
    else update public.merchants set email = t.email, email_verified_at = now() where id = m.id; end if;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'email_taken', 'message', 'هذا البريد مستعمل لحساب آخر');
  end;
  perform public._ev('email_verified', s.role, c.phone, m.id, null, null);
  return jsonb_build_object('ok', true, 'email', public._email_mask(t.email));
end $$;

-- link variant for adding an e-mail (opened from the mail app on the same phone or another device: no session needed,
-- the link itself proves access to the mailbox and is bound to the account that asked for it)
create function public.email_link_confirm(p_link text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare t public.email_tokens;
begin
  t := public._email_consume('add_email', p_link, null, null, null, null, null);
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'invalid_code', 'message', 'الرابط غير صالح أو انتهت صلاحيته'); end if;
  begin
    if t.role = 'customer' then update public.customers set email = t.email, email_verified_at = now() where phone = t.customer_phone;
    else update public.merchants set email = t.email, email_verified_at = now() where id = t.merchant_id; end if;
  exception when unique_violation then
    return jsonb_build_object('ok', false, 'error', 'email_taken', 'message', 'هذا البريد مستعمل لحساب آخر');
  end;
  perform public._ev('email_verified', t.role, t.customer_phone, t.merchant_id, null, null, jsonb_build_object('via', 'link'));
  return jsonb_build_object('ok', true, 'email', public._email_mask(t.email));
end $$;

create function public.pin_reset_confirm(p_new_pin text, p_role text default null, p_phone text default null, p_code text default null,
  p_link text default null, p_device text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare t public.email_tokens; c public.customers; m public.merchants; k text;
begin
  if p_new_pin is null or p_new_pin !~ '^\d{4}$' then return jsonb_build_object('ok', false, 'error', 'pin', 'message', 'رمز الحماية يجب أن يكون 4 أرقام'); end if;
  if p_link is null then
    if p_role not in ('customer','merchant') or p_phone is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
    if p_role = 'customer' then select * into c from public.customers where phone = p_phone; else select * into m from public.merchants where phone = p_phone; end if;
    k := 'mailcode:reset:' || p_role || ':' || p_phone;
    if public._rl2_locked(k) then return jsonb_build_object('ok', false, 'error', 'locked', 'message', 'محاولات خاطئة كثيرة. اطلب رمزاً جديداً'); end if;
  end if;
  t := public._email_consume('reset_pin', p_link, p_code, p_role, null, c.phone, m.id);
  if t.id is null then
    if k is not null then perform public._rl2_hit(k, 10, 1800, 1800); end if;
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'message', 'الرمز غير صحيح أو انتهت صلاحيته');
  end if;
  -- the new PIN replaces the hash; the phase-1 trigger ends every existing session of this account
  if t.role = 'customer' then
    update public.customers set pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf')) where phone = t.customer_phone returning * into c;
    perform public._rl_reset('customer:' || c.phone); perform public._rl2_reset('login:customer:' || c.phone);
    insert into public.customer_notes(customer_phone, type, title, body) values (c.phone, 'account', 'تم تغيير رمز الحماية', 'عبر بريدك الموثّق. إن لم تكن أنت، تواصل مع الدعم فوراً');
  else
    update public.merchants set pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf')) where id = t.merchant_id returning * into m;
    perform public._rl_reset('merchant:' || m.phone); perform public._rl2_reset('login:merchant:' || m.phone);
    insert into public.merchant_notes(merchant_id, type, title, body, severity) values (m.id, 'info', 'تم تغيير رمز الحماية', 'عبر بريدك الموثّق. إن لم تكن أنت، تواصل مع الدعم فوراً', 'warn');
  end if;
  perform public._ev('pin_reset_by_email', t.role, c.phone, m.id, null, null);
  if t.role = 'customer' then
    return jsonb_build_object('ok', true, 'role', 'customer', 'customer', public._customer_json(c, true)) || public._issue_session('customer', c.phone, null, null, p_device);
  end if;
  if m.status in ('frozen','excluded','rejected') then return jsonb_build_object('ok', true, 'role', 'merchant', 'merchant', public._merchant_json(m), 'session', null); end if;
  return jsonb_build_object('ok', true, 'role', 'merchant', 'merchant', public._merchant_json(m)) || public._issue_session('merchant', null, m.id, null, p_device);
end $$;

-- what the app shows in «حسابي»: masked e-mail and whether it is verified
create function public.email_status(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; c public.customers; m public.merchants;
begin
  select * into s from public.app_sessions where token_hash = public._sha(coalesce(p_session, ''));
  if s.role = 'customer' then c := public._sess_customer(p_session);
    return jsonb_build_object('ok', true, 'email', public._email_mask(c.email), 'verified', c.email_verified_at is not null);
  elsif s.role = 'merchant' then m := public._sess_merchant(p_session);
    return jsonb_build_object('ok', true, 'email', public._email_mask(m.email), 'verified', m.email_verified_at is not null);
  end if;
  raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required';
end $$;

-- ---------------------------------------------------------------- privileges
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
      ('_email_norm','_email_valid','_email_mask','_email_issue','_email_consume','_email_register_start','_email_register_resend',
       '_email_add_start','_email_reset_start','_email_mark_sent','register_confirm','email_add_confirm','email_link_confirm','pin_reset_confirm','email_status') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  -- the Edge Function (service_role) starts flows and reports sends; the app confirms
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
      ('_email_register_start','_email_register_resend','_email_add_start','_email_reset_start','_email_mark_sent') loop
    execute format('grant execute on function %s to service_role', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
      ('register_confirm','email_add_confirm','email_link_confirm','pin_reset_confirm','email_status') loop
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end $$;

commit;
