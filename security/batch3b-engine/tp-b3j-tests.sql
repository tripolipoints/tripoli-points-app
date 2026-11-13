-- BATCH 3j TESTS (Staging-safe): one transaction ending in ROLLBACK; synthetic phones 799986xx. No wipe / truncate.
-- email_delivery_enabled is switched on ONLY inside this rolled-back run, to test the code path without sending anything.
begin;
set local client_min_messages = warning;
create temp table _t (n serial primary key, name text, ok boolean, detail text) on commit drop;
create temp table _ctx (k text primary key, v text) on commit drop;
create function pg_temp.ok(p_name text, p_cond boolean, p_detail text default null) returns void language sql as $$
  insert into _t(name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail) $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'NO_ERROR'; exception when others then return sqlerrm; end $$;
create function pg_temp.set(p_k text, p_v text) returns void language sql as $$
  insert into _ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.get(p_k text) returns text language sql as $$ select v from _ctx where k = p_k $$;
do $$ begin
  if exists (select 1 from public.merchants where phone like '799986__') or exists (select 1 from public.merchant_staff where phone like '799986__') then raise exception 'test phones exist'; end if;
end $$;
insert into public.customers(phone, pin_hash, name, status, points) values ('79998601', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0);
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
  ('00000000-0000-4000-8000-0000000b3601', 'فرع الموظفين', '79998611', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 50, 'active');
insert into public.topups(merchant_id, amount, source) values ('00000000-0000-4000-8000-0000000b3601', 100, 'test');
insert into public.admin_users(id, username, pin_hash, is_primary) values ('00000000-0000-4000-8000-0000000b36a1', 'tp_test_b3j_a1', extensions.crypt('3333', extensions.gen_salt('bf', 4)), true);
do $$ declare r jsonb; begin
  perform pg_temp.set('c1', public.customer_login('79998601', '1111')->>'session');
  perform pg_temp.set('m1', public.merchant_login('79998611', '2222')->>'session');
  perform pg_temp.set('a1', public.admin_login('tp_test_b3j_a1', '3333')->>'session');
  r := public.merchant_staff_save_v2(pg_temp.get('m1'), null, 'موظفة', '79998621', '5555', array['sell']);
  perform pg_temp.set('st', r->'staff'->>'id');
end $$;

-- §13 staff verification + 6-digit PIN on approved devices
do $$ declare r jsonb; dev text := 'device-AAAA-1111-test-01'; dev2 text := 'device-BBBB-2222-test-02'; tok text; i int; begin
  r := public.staff_login('79998621', '5555');
  perform pg_temp.ok('§13 the old phone+PIN staff login is refused (device required)', r->>'reason' = 'device_required', r::text);
  perform pg_temp.ok('§13 weak password refused', public.merchant_staff_credentials_v2(pg_temp.get('m1'), pg_temp.get('st')::uuid, 'emp@test.example', 'abc')->>'error' = 'weak_password');
  r := public.merchant_staff_credentials_v2(pg_temp.get('m1'), pg_temp.get('st')::uuid, 'Emp@Test.example', 'Passw0rdTest');
  perform pg_temp.ok('§13 owner sets e-mail + password (stored hashed)', (r->>'ok')::boolean
    and (select password_hash like '$2%' and email = 'emp@test.example' from public.merchant_staff where id = pg_temp.get('st')::uuid), r::text);
  perform pg_temp.ok('§13 wrong password refused', public.staff_first_login_v2('emp@test.example', 'nope', dev)->>'reason' = 'wrong_credentials');
  r := public.staff_first_login_v2('emp@test.example', 'Passw0rdTest', dev, 'هاتف الصندوق');
  perform pg_temp.ok('§13 first login on a new device → verification by the owner (e-mail off)', r->>'step' = 'verify' and r->>'via' = 'owner', r::text);
  perform pg_temp.ok('§13 no PIN before the device is approved', public.staff_set_pin6_v2('emp@test.example', 'Passw0rdTest', dev, '482915')->>'error' = 'device_not_approved');
  r := public.merchant_staff_devices_v2(pg_temp.get('m1'));
  perform pg_temp.ok('§13 the owner sees the pending device', r->'devices'->0->>'status' = 'pending', r::text);
  perform public.merchant_staff_device_decide_v2(pg_temp.get('m1'), (r->'devices'->0->>'id')::uuid, true);
  perform pg_temp.ok('§13 weak PINs refused (repeated / sequential / not 6 digits)', public.staff_set_pin6_v2('emp@test.example', 'Passw0rdTest', dev, '111111')->>'error' = 'weak_pin'
    and public.staff_set_pin6_v2('emp@test.example', 'Passw0rdTest', dev, '123456')->>'error' = 'weak_pin' and public.staff_set_pin6_v2('emp@test.example', 'Passw0rdTest', dev, '4829')->>'error' = 'weak_pin');
  r := public.staff_set_pin6_v2('emp@test.example', 'Passw0rdTest', dev, '482915');
  perform pg_temp.ok('§13 6-digit PIN set on the approved device', (r->>'ok')::boolean, r::text);
  r := public.staff_pin_login_v2('79998621', '482915', dev); tok := r->>'session';
  perform pg_temp.ok('§13 daily login: phone + 6-digit PIN on the approved device → branch session (staff)', (r->>'ok')::boolean
    and (select staff_id = pg_temp.get('st')::uuid from public.app_sessions where token_hash = public._sha(tok)), r::text);
  perform pg_temp.ok('§13 staff session can sell, cannot manage staff', (public.merchant_me_v2(tok)->>'ok')::boolean and pg_temp.err(format('select public.merchant_staff_list_v2(%L)', tok)) like 'TP_FORBIDDEN%');
  perform pg_temp.ok('§13 same PIN on an unknown device refused', public.staff_pin_login_v2('79998621', '482915', dev2)->>'reason' = 'device_not_approved');
  for i in 1..5 loop perform public.staff_pin_login_v2('79998621', '000000', dev); end loop;
  perform pg_temp.ok('§13 5 wrong PINs lock the login (even with the right PIN)', public.staff_pin_login_v2('79998621', '482915', dev)->>'reason' = 'locked');
  perform public._rl_reset('staff:79998621');
  r := public.merchant_staff_devices_v2(pg_temp.get('m1'));
  perform public.merchant_staff_device_decide_v2(pg_temp.get('m1'), (r->'devices'->0->>'id')::uuid, false);
  perform pg_temp.ok('§13 owner revokes the device: sessions end, login refused', pg_temp.err(format('select public.merchant_me_v2(%L)', tok)) like 'TP_SESSION%'
    and public.staff_pin_login_v2('79998621', '482915', dev)->>'reason' = 'device_not_approved');
  -- e-mail code path (built, off by default) — switched on only here, nothing is sent
  perform pg_temp.ok('§13 e-mail code cannot be issued while delivery is off', (public._staff_code_issue(pg_temp.get('st')::uuid, gen_random_uuid())->>'error') = 'email_disabled');
  update public.app_settings set value = 1 where key = 'email_delivery_enabled';
  r := public.staff_first_login_v2('emp@test.example', 'Passw0rdTest', dev2, 'جهاز ثانٍ');
  perform pg_temp.ok('§13 with delivery on: verification via e-mail', r->>'via' = 'email', r::text);
  r := public._staff_code_issue(pg_temp.get('st')::uuid, (select id from public.staff_devices where staff_id = pg_temp.get('st')::uuid and label = 'جهاز ثانٍ'));
  perform pg_temp.ok('§13 wrong e-mail code refused', public.staff_verify_code_v2('emp@test.example', 'Passw0rdTest', dev2, '000000')->>'error' = 'wrong_code');
  perform pg_temp.ok('§13 right e-mail code approves the device', (public.staff_verify_code_v2('emp@test.example', 'Passw0rdTest', dev2, r->>'code')->>'ok')::boolean
    and (public.staff_pin_login_v2('79998621', '482915', dev2)->>'ok')::boolean);
  update public.app_settings set value = 0 where key = 'email_delivery_enabled';
  perform pg_temp.ok('§13 the e-mail code issuer is not reachable by anon', not has_function_privilege('anon', 'public._staff_code_issue(uuid,uuid)', 'execute'));
end $$;

-- §11 complaint deadlines
do $$ declare q jsonb; s jsonb; r jsonb; tx uuid; rep uuid; f jsonb; begin
  perform public._allow_add('00000000-0000-4000-8000-0000000b3601', 1000, 'adjust', now(), now() + interval '30 days', null, null, null, null, null, 'test');
  q := public.customer_qr_issue(pg_temp.get('c1')); s := public.merchant_scan_code(pg_temp.get('m1'), q->>'qr');
  r := public.merchant_create_tx_v2(pg_temp.get('m1'), (s->>'code_id')::uuid, 10, false, null, '[]'::jsonb, 'idem-b3j-0001'); tx := (r->'tx'->>'id')::uuid;
  perform public.report_tx(pg_temp.get('c1'), 'wrong_amount', tx, null, 'القيمة خطأ');
  rep := (select id from public.tx_reports where tx_id = tx);
  perform pg_temp.ok('§11 deadlines set: answer within 48 h, resolve within 5 days', (select response_due_at = created_at + interval '48 hours' and resolve_due_at = created_at + interval '5 days' from public.tx_reports where id = rep));
  r := public.admin_report_respond_v2(pg_temp.get('a1'), rep, 'نراجع العملية مع المحل');
  perform pg_temp.ok('§11 Admin answer recorded and sent to the customer', (r->>'ok')::boolean and (select first_response_at is not null from public.tx_reports where id = rep)
    and exists (select 1 from public.customer_notes where customer_phone = '79998601' and title = 'رد الإدارة على بلاغك'));
  perform pg_temp.ok('§11 not escalated while on time', public._escalate_reports() = 0);
  update public.tx_reports set resolve_due_at = now() - interval '1 hour' where id = rep;
  perform pg_temp.set('esc', public._escalate_reports()::text);
  perform pg_temp.ok('§11 past 5 days unresolved → escalated with an Admin alert', pg_temp.get('esc') = '1'
    and exists (select 1 from public.tx_events where event = 'alert_report_overdue' and detail->>'report' = rep::text));
  perform pg_temp.ok('§11 escalated once only', public._escalate_reports() = 0);
  f := public.admin_security_feed_v2(pg_temp.get('a1'), 50);
  perform pg_temp.ok('§11 Admin feed shows deadlines, answer and escalation', exists (select 1 from jsonb_array_elements(f->'reports') x where (x->>'id')::uuid = rep
    and (x->>'escalated')::boolean and x->>'answer' = 'نراجع العملية مع المحل' and x ? 'resolve_due_at'));
  perform pg_temp.ok('§11 Admin job includes escalation', (public.admin_run_jobs_v2(pg_temp.get('a1'))->'accounts') ? 'reports_escalated');
  perform pg_temp.ok('gift settings untouched; e-mail delivery off', (select value from public.app_text_settings where key = 'welcome_bonus') = '3000'
    and (select value from public.app_text_settings where key = 'welcome_days') = '7' and public._setting('email_delivery_enabled', 0) = 0);
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
