-- =====================================================================================================
-- Tripoli Points — BATCH 3j: staff first-login verification + 6-digit PIN on approved devices, complaint deadlines
-- and escalation (STAGING ONLY)
-- Register 12-Nov-2026:
--   §13  first login with e-mail + password + verification, then a 6-digit PIN on an approved device, with protection
--        against failed attempts and automatic lock; the owner adds / removes staff and ends their sessions; every
--        purchase records the employee; staff never see the customer's full phone or e-mail.
--        Verification today = the OWNER approves the new device from his staff screen. The e-mail code path is built
--        and tested but stays off (email_delivery_enabled = 0) until the e-mail sending configuration is authorised.
--   §11  Admin answers a complaint within 48 h and resolves it within 5 days; late complaints are escalated with an
--        Admin alert; every answer is notified to the reporter.
-- Changes: settings (fill-missing), 9 nullable columns, 2 tables, 1 trigger, 3 functions text-patched (saved in
--   tp_backup.func_snapshots 'b3j'), new functions. The old phone+PIN staff_login is refused while
--   staff_device_required = 1 (approved rule). No drop / delete / truncate. Rollback: R_tp-b3j-staff-complaints-rollback.sql
-- =====================================================================================================
begin;

do $$ begin
  if to_regprocedure('public._shop_state(uuid)') is null then raise exception 'batch 3i required'; end if;
  if exists (select 1 from tp_backup.func_snapshots where batch = 'b3j') then raise exception 'already applied'; end if;
end $$;

do $$
declare r record; cur text;
begin
  for r in select * from (values
    ('staff_login(text,text,text)', '1302cdfe5dc67eaa4d9f7e988734fa0c'),
    ('admin_security_feed_v2(text,integer)', '05ef64d355f4bd4e2ee3faae4a886444'),
    ('admin_run_jobs_v2(text)', '2601b1bf58187a09d97a4c5b40ee4f5f')) v(sig, want) loop
    cur := (select md5(replace(prosrc, chr(13), '')) from pg_proc where oid = to_regprocedure('public.' || r.sig));
    if cur is distinct from r.want then raise exception '% differs (md5 %), stop', r.sig, cur; end if;
    insert into tp_backup.func_snapshots(batch, sig, def, src_md5)
    values ('b3j', r.sig, pg_get_functiondef(to_regprocedure('public.' || r.sig)), (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)));
  end loop;
  for r in select * from (values ('staff_device_required', 1), ('email_delivery_enabled', 0), ('staff_code_ttl_min', 15),
                                 ('complaint_response_hours', 48), ('complaint_resolve_days', 5)) v(k, val) loop
    if not exists (select 1 from public.app_settings where key = r.k) then
      execute 'insert ' || 'into public.app_settings(key, value) values ($1, $2)' using r.k, r.val;
      insert into tp_backup.settings_snapshots(batch, tbl, key, existed, old_value, inserted_value) values ('b3j', 'app_settings', r.k, false, null, r.val::text);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------- §13 staff credentials and devices
alter table public.merchant_staff add column email text, add column password_hash text, add column verified_at timestamptz, add column pin6_hash text;
create unique index merchant_staff_email_uidx on public.merchant_staff(lower(email)) where email is not null;
create table public.staff_devices(
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.merchant_staff(id) on delete cascade,
  device_hash bytea not null,
  label text,
  status text not null default 'pending' check (status in ('pending','approved','revoked')),
  code_hash bytea, code_expires_at timestamptz, code_attempts int not null default 0,   -- e-mail code path (off until authorised)
  created_at timestamptz not null default now(), approved_at timestamptz, approved_by text, last_used_at timestamptz,
  unique (staff_id, device_hash));
alter table public.staff_devices enable row level security;
revoke all on table public.staff_devices from public, anon, authenticated;

create function public._staff_device(p_staff uuid, p_device text) returns public.staff_devices
language sql stable security definer set search_path = public, pg_temp as $$
  select * from public.staff_devices where staff_id = p_staff and device_hash = public._sha('dev:' || coalesce(p_device, ''))
$$;

-- owner: e-mail + temporary password for an employee (a new password ends his devices' approval and his PIN)
create function public.merchant_staff_credentials_v2(p_session text, p_staff_id uuid, p_email text, p_password text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare m public.merchants; st public.merchant_staff;
begin
  m := public._sess_merchant(p_session);
  if p_email is null or p_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(p_email) > 120 then return jsonb_build_object('ok', false, 'error', 'bad_email'); end if;
  if p_password is null or length(p_password) < 8 or length(p_password) > 72 or p_password !~ '[0-9]' or p_password !~ '[A-Za-z]' then
    return jsonb_build_object('ok', false, 'error', 'weak_password', 'message', 'كلمة السر 8 أحرف على الأقل، فيها أحرف وأرقام');
  end if;
  begin
    update public.merchant_staff set email = lower(trim(p_email)), password_hash = extensions.crypt(p_password, extensions.gen_salt('bf')),
           verified_at = null, pin6_hash = null where id = p_staff_id and merchant_id = m.id returning * into st;
  exception when unique_violation then return jsonb_build_object('ok', false, 'error', 'email_taken');
  end;
  if st.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  update public.staff_devices set status = 'revoked' where staff_id = st.id and status <> 'revoked';
  update public.app_sessions set revoked_at = now(), revoked_reason = 'staff_credentials' where staff_id = st.id and revoked_at is null;
  perform public._audit('merchant', m.id::text, 'staff_credentials', 'staff', st.id::text);
  return jsonb_build_object('ok', true);
end $$;

-- employee, step 1 (new device): e-mail + password → the device waits for verification
create function public.staff_first_login_v2(p_email text, p_password text, p_device text, p_label text default null) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare st public.merchant_staff; d public.staff_devices; key text := 'staffpw:' || lower(coalesce(p_email, ''));
begin
  if p_device is null or length(p_device) < 16 or length(p_device) > 128 then return jsonb_build_object('ok', false, 'error', 'bad_device'); end if;
  if not public._login_allowed(key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into st from public.merchant_staff where lower(email) = lower(trim(coalesce(p_email, '')));
  if st.id is null or st.password_hash is null or extensions.crypt(coalesce(p_password, ''), st.password_hash) <> st.password_hash then
    perform public._login_failed(key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_credentials');
  end if;
  if st.status <> 'active' or exists (select 1 from public.merchants where id = st.merchant_id and (status in ('frozen','excluded','rejected') or closed_at is not null)) then
    return jsonb_build_object('ok', false, 'reason', 'frozen');
  end if;
  perform public._rl_reset(key);
  insert into public.staff_devices(staff_id, device_hash, label) values (st.id, public._sha('dev:' || p_device), left(p_label, 60))
  on conflict (staff_id, device_hash) do update set label = coalesce(excluded.label, staff_devices.label)
  returning * into d;
  if d.status = 'revoked' then
    update public.staff_devices set status = 'pending', approved_at = null, approved_by = null where id = d.id returning * into d;
  end if;
  if d.status = 'approved' then
    return jsonb_build_object('ok', true, 'step', case when st.pin6_hash is null then 'set_pin' else 'pin_login' end, 'device_id', d.id);
  end if;
  perform public._ev('staff_device_pending', 'staff', null, st.merchant_id, null, null, jsonb_build_object('staff', st.id, 'device', d.id));
  return jsonb_build_object('ok', true, 'step', 'verify', 'via', case when public._setting('email_delivery_enabled', 0) = 1 then 'email' else 'owner' end,
    'message', case when public._setting('email_delivery_enabled', 0) = 1 then 'أرسلنا رمز تحقق إلى بريدك' else 'اطلب من صاحب المحل الموافقة على هذا الجهاز' end);
end $$;

-- e-mail code (only for the Edge Function, service_role): creates the 6-digit code to put in the e-mail. Off by default.
create function public._staff_code_issue(p_staff uuid, p_device_id uuid) returns jsonb language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare code text := lpad(((('x' || encode(extensions.gen_random_bytes(4), 'hex'))::bit(32)::bigint) % 1000000)::text, 6, '0');
begin
  if public._setting('email_delivery_enabled', 0) <> 1 then return jsonb_build_object('ok', false, 'error', 'email_disabled'); end if;
  update public.staff_devices set code_hash = public._sha('staffcode:' || code), code_expires_at = now() + make_interval(mins => public._setting('staff_code_ttl_min', 15)::int),
         code_attempts = 0 where id = p_device_id and staff_id = p_staff and status = 'pending';
  if not found then return jsonb_build_object('ok', false, 'error', 'not_pending'); end if;
  return jsonb_build_object('ok', true, 'code', code, 'email', (select email from public.merchant_staff where id = p_staff));
end $$;

create function public.staff_verify_code_v2(p_email text, p_password text, p_device text, p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare st public.merchant_staff; d public.staff_devices;
begin
  select * into st from public.merchant_staff where lower(email) = lower(trim(coalesce(p_email, '')));
  if st.id is null or st.password_hash is null or extensions.crypt(coalesce(p_password, ''), st.password_hash) <> st.password_hash then
    perform public._login_failed('staffpw:' || lower(coalesce(p_email, '')));
    return jsonb_build_object('ok', false, 'reason', 'wrong_credentials');
  end if;
  d := public._staff_device(st.id, p_device);
  if d.id is null or d.status <> 'pending' or d.code_hash is null or d.code_expires_at < now() or d.code_attempts >= 5 then
    return jsonb_build_object('ok', false, 'error', 'no_code');
  end if;
  if public._sha('staffcode:' || coalesce(p_code, '')) <> d.code_hash then
    update public.staff_devices set code_attempts = code_attempts + 1 where id = d.id;
    return jsonb_build_object('ok', false, 'error', 'wrong_code');
  end if;
  update public.staff_devices set status = 'approved', approved_at = now(), approved_by = 'email', code_hash = null where id = d.id;
  update public.merchant_staff set verified_at = coalesce(verified_at, now()) where id = st.id;
  perform public._audit('staff', st.id::text, 'staff_device_verified', 'staff_device', d.id::text, jsonb_build_object('via', 'email'));
  return jsonb_build_object('ok', true, 'step', case when st.pin6_hash is null then 'set_pin' else 'pin_login' end);
end $$;

-- owner: pending / approved devices of his staff, approve or revoke
create function public.merchant_staff_devices_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants;
begin
  m := public._sess_merchant(p_session);
  return jsonb_build_object('ok', true, 'devices', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'staff', s.name, 'staff_id', s.id,
     'label', d.label, 'status', d.status, 'created_at', floor(extract(epoch from d.created_at) * 1000),
     'last_used_at', case when d.last_used_at is null then null else floor(extract(epoch from d.last_used_at) * 1000) end) order by d.created_at desc), '[]'::jsonb)
     from public.staff_devices d join public.merchant_staff s on s.id = d.staff_id where s.merchant_id = m.id and d.status <> 'revoked'));
end $$;

create function public.merchant_staff_device_decide_v2(p_session text, p_device_id uuid, p_approve boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare m public.merchants; d public.staff_devices;
begin
  m := public._sess_merchant(p_session);
  update public.staff_devices sd set status = case when p_approve then 'approved' else 'revoked' end,
         approved_at = case when p_approve then now() else null end, approved_by = case when p_approve then 'owner:' || m.id else null end
   where sd.id = p_device_id and exists (select 1 from public.merchant_staff s where s.id = sd.staff_id and s.merchant_id = m.id)
     and (p_approve and sd.status = 'pending' or not p_approve and sd.status <> 'revoked')
  returning * into d;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_approve then update public.merchant_staff set verified_at = coalesce(verified_at, now()) where id = d.staff_id;
  else update public.app_sessions set revoked_at = now(), revoked_reason = 'device_revoked' where staff_id = d.staff_id and revoked_at is null; end if;
  perform public._audit('merchant', m.id::text, case when p_approve then 'staff_device_approved' else 'staff_device_revoked' end, 'staff_device', d.id::text);
  return jsonb_build_object('ok', true);
end $$;

-- employee, step 2 (approved device): choose the 6-digit PIN (needs the password once more)
create function public.staff_set_pin6_v2(p_email text, p_password text, p_device text, p_pin6 text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare st public.merchant_staff; d public.staff_devices;
begin
  if p_pin6 is null or p_pin6 !~ '^\d{6}$' or p_pin6 ~ '^(\d)\1{5}$' or p_pin6 in ('123456','654321') then
    return jsonb_build_object('ok', false, 'error', 'weak_pin', 'message', 'رمز من 6 أرقام غير متكرر وغير متسلسل');
  end if;
  select * into st from public.merchant_staff where lower(email) = lower(trim(coalesce(p_email, '')));
  if st.id is null or st.password_hash is null or extensions.crypt(coalesce(p_password, ''), st.password_hash) <> st.password_hash then
    perform public._login_failed('staffpw:' || lower(coalesce(p_email, '')));
    return jsonb_build_object('ok', false, 'reason', 'wrong_credentials');
  end if;
  d := public._staff_device(st.id, p_device);
  if d.id is null or d.status <> 'approved' then return jsonb_build_object('ok', false, 'error', 'device_not_approved'); end if;
  update public.merchant_staff set pin6_hash = extensions.crypt(p_pin6, extensions.gen_salt('bf')), verified_at = coalesce(verified_at, now()) where id = st.id;
  perform public._audit('staff', st.id::text, 'staff_pin6_set', 'staff', st.id::text);
  return jsonb_build_object('ok', true, 'step', 'pin_login');
end $$;

-- employee, daily: phone + 6-digit PIN, only on an approved device; 5 wrong → 15 minutes lock (shared limiter)
create function public.staff_pin_login_v2(p_phone text, p_pin6 text, p_device text) returns jsonb
language plpgsql security definer set search_path = public, extensions, pg_temp as $$
declare st public.merchant_staff; m public.merchants; d public.staff_devices; s jsonb; key text := 'staff:' || coalesce(p_phone, '');
begin
  if p_phone is null or p_phone !~ '^\d{8}$' then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if not public._login_allowed(key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into st from public.merchant_staff where phone = p_phone;
  d := public._staff_device(st.id, p_device);
  if st.id is null or d.id is null or d.status <> 'approved' then
    perform public._login_failed(key);
    return jsonb_build_object('ok', false, 'reason', 'device_not_approved');
  end if;
  if st.pin6_hash is null or extensions.crypt(coalesce(p_pin6, ''), st.pin6_hash) <> st.pin6_hash then
    perform public._login_failed(key);
    perform public._ev('login_failed', 'staff', null, st.merchant_id, null, null);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  select * into m from public.merchants where id = st.merchant_id;
  if st.status <> 'active' or m.status in ('frozen','excluded','rejected') or m.closed_at is not null then return jsonb_build_object('ok', false, 'reason', 'frozen'); end if;
  perform public._rl_reset(key);
  update public.staff_devices set last_used_at = now() where id = d.id;
  s := public._issue_session('merchant', null, m.id, null, coalesce(d.label, 'staff device'));
  update public.app_sessions set staff_id = st.id where token_hash = public._sha(s->>'session');
  perform public._audit('staff', st.id::text, 'staff_login', 'merchant', m.id::text, jsonb_build_object('device', d.id));
  return jsonb_build_object('ok', true, 'merchant', public._merchant_json(m), 'staff', jsonb_build_object('id', st.id, 'name', st.name, 'perms', st.perms)) || s;
end $$;

-- ---------------------------------------------------------------- §11 complaint deadlines
alter table public.tx_reports add column response_due_at timestamptz, add column resolve_due_at timestamptz,
  add column first_response_at timestamptz, add column last_admin_message text, add column escalated_at timestamptz;
create function public._tr_report_due() returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  new.response_due_at := coalesce(new.response_due_at, new.created_at + make_interval(hours => public._setting('complaint_response_hours', 48)::int));
  new.resolve_due_at := coalesce(new.resolve_due_at, new.created_at + make_interval(days => public._setting('complaint_resolve_days', 5)::int));
  return new;
end $$;
create trigger tx_reports_due before insert on public.tx_reports for each row execute function public._tr_report_due();
update public.tx_reports set response_due_at = created_at + interval '48 hours', resolve_due_at = created_at + interval '5 days'
 where response_due_at is null;                                  -- existing reports (Staging: none)

create function public.admin_report_respond_v2(p_session text, p_report_id uuid, p_message text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r public.tx_reports;
begin
  a := public._sess_admin(p_session, false);
  if p_message is null or length(trim(p_message)) < 3 or length(p_message) > 500 then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  update public.tx_reports set first_response_at = coalesce(first_response_at, now()), last_admin_message = trim(p_message)
   where id = p_report_id and status = 'open' returning * into r;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  if r.reporter_role = 'customer' then
    insert into public.customer_notes(customer_phone, type, title, body) values (r.reporter, 'general', 'رد الإدارة على بلاغك', trim(p_message));
  elsif r.reporter ~ '^[0-9a-f-]{36}$' then
    insert into public.merchant_notes(merchant_id, type, title, body) values (r.reporter::uuid, 'info', 'رد الإدارة على بلاغك', trim(p_message));
  end if;
  perform public._audit('admin', a.id::text, 'report_respond', 'report', r.id::text);
  return jsonb_build_object('ok', true);
end $$;

create function public._escalate_reports() returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0;
begin
  for r in update public.tx_reports set escalated_at = now()
            where status = 'open' and escalated_at is null
              and ((first_response_at is null and response_due_at < now()) or resolve_due_at < now())
           returning id, reporter_role, (first_response_at is null) as no_answer loop
    perform public._ev('alert_report_overdue', null, null, null, null, null, jsonb_build_object('report', r.id, 'stage', case when r.no_answer then 'response_48h' else 'resolve_5d' end));
    perform public._audit('system', null, 'report_escalated', 'report', r.id::text);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------- text patches
do $$
declare r record; d text; n int;
begin
  for r in select * from (values
    ('staff_login(text,text,text)',
     'if p_phone is null or p_phone !~ ''^\d{8}$'' then return jsonb_build_object(''ok'', false, ''reason'', ''not_found''); end if;',
     'if public._setting(''staff_device_required'', 1) = 1 then return jsonb_build_object(''ok'', false, ''reason'', ''device_required'', ''message'', ''سجّل الدخول من جهاز معتمد بالبريد وكلمة السر''); end if; /* B3J */
  if p_phone is null or p_phone !~ ''^\d{8}$'' then return jsonb_build_object(''ok'', false, ''reason'', ''not_found''); end if;'),
    ('admin_security_feed_v2(text,integer)', '''reason'', r.reason, ''note'', r.note, ''status'', r.status)',
     '''reason'', r.reason, ''note'', r.note, ''status'', r.status, ''response_due_at'', floor(extract(epoch from r.response_due_at) * 1000), ''resolve_due_at'', floor(extract(epoch from r.resolve_due_at) * 1000), ''first_response_at'', floor(extract(epoch from r.first_response_at) * 1000), ''escalated'', r.escalated_at is not null, ''answer'', r.last_admin_message) /* B3J */'),
    ('admin_run_jobs_v2(text)', 'y := public._process_account_closures();',
     'y := public._process_account_closures() || jsonb_build_object(''reports_escalated'', public._escalate_reports()); /* B3J */')) v(sig, old, new) loop
    d := (select def from tp_backup.func_snapshots where batch = 'b3j' and sig = r.sig);
    n := (length(d) - length(replace(d, r.old, ''))) / length(r.old);
    if n <> 1 then raise exception 'patch target found % times in %', n, r.sig; end if;
    execute replace(d, r.old, r.new);
  end loop;
end $$;

do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['_staff_device','_tr_report_due','_escalate_reports','_staff_code_issue']) loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  execute 'grant execute on function public._staff_code_issue(uuid,uuid) to service_role';         -- the e-mail Edge Function only, when authorised
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      'merchant_staff_credentials_v2','staff_first_login_v2','staff_verify_code_v2','merchant_staff_devices_v2','merchant_staff_device_decide_v2',
      'staff_set_pin6_v2','staff_pin_login_v2','admin_report_respond_v2']) loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
  if has_function_privilege('anon', 'public._staff_code_issue(uuid,uuid)', 'execute') then raise exception 'self-check: e-mail code issuer open'; end if;
  if public._setting('email_delivery_enabled', 0) <> 0 then raise exception 'self-check: e-mail delivery must stay off'; end if;
end $$;

commit;
