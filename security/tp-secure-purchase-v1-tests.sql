-- =====================================================================================================
-- Tripoli Points — PHASE 1 TESTS (run on STAGING after tp-secure-purchase-v1.sql)
-- Everything runs inside one transaction that ends with ROLLBACK: test accounts, codes, purchases, events and
-- setting changes all disappear. The last statement prints one row per check (ok = true / false) and a summary.
-- Test phone numbers: 70999901-70999913 (must not exist). Test admin usernames start with tp_test_.
-- =====================================================================================================
begin;
set local client_min_messages = warning;

create temp table _t (n serial primary key, name text, ok boolean, detail text) on commit drop;
create temp table _ctx (k text primary key, v text) on commit drop;

create function pg_temp.ok(p_name text, p_cond boolean, p_detail text default null) returns void language sql as $$
  insert into _t(name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail) $$;
create function pg_temp.j(p_sql text) returns jsonb language plpgsql as $$
declare r jsonb; begin execute p_sql into r; return r; end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'NO_ERROR'; exception when others then return sqlerrm; end $$;
create function pg_temp.set(p_k text, p_v text) returns void language sql as $$
  insert into _ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.get(p_k text) returns text language sql as $$ select v from _ctx where k = p_k $$;

do $$ begin
  if exists (select 1 from public.customers where phone like '709999__') or exists (select 1 from public.merchants where phone like '709999__') then
    raise exception 'test phone numbers 709999xx already exist — tests stopped';
  end if;
end $$;

-- ---------------------------------------------------------------- fixtures
insert into public.customers(phone, pin_hash, name, status, points) values
  ('70999901', extensions.crypt('1234', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 1000),
  ('70999902', extensions.crypt('1234', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0),
  ('70999903', extensions.crypt('1234', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0),
  ('70999911', extensions.crypt('1234', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0);   -- same phone as merchant M1
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
  ('00000000-0000-4000-8000-000000000011', 'محل اختبار 1', '70999911', extensions.crypt('4321', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 5, 'active'),
  ('00000000-0000-4000-8000-000000000012', 'محل اختبار 2', '70999912', extensions.crypt('4321', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 5, 'active'),
  ('00000000-0000-4000-8000-000000000013', 'محل اختبار 3', '70999913', extensions.crypt('4321', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 5, 'pending');
insert into public.topups(merchant_id, amount, source) values
  ('00000000-0000-4000-8000-000000000011', 500, 'test'), ('00000000-0000-4000-8000-000000000012', 500, 'test');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000000a1', 'tp_test_admin1', extensions.crypt('9999', extensions.gen_salt('bf', 4)), true),
  ('00000000-0000-4000-8000-0000000000a2', 'tp_test_admin2', extensions.crypt('9999', extensions.gen_salt('bf', 4)), false);

-- batch 3b adds the approved limit of 2 purchases per customer per branch per day (tested in
-- batch3b-engine/tp-engine-v1-tests.sql). These phase-1 checks make more purchases in one shop, so the limit is
-- raised for this rolled-back run only. No effect before batch 3b (the key does not exist then).
update public.app_settings set value = 20 where key = 'tx_per_customer_branch_day';
-- batch 3g adds the approved daily eligible-purchase caps (tested in batch3b-engine/tp-b3g-rules-tests.sql). Check 48 compares the
-- quote with the old create_transaction price rules on large invoices, so the caps are switched off for this rolled-back run only.
update public.app_settings set value = 0 where key in ('daily_eligible_pts_small','daily_eligible_pts_medium','daily_eligible_pts_large');

-- ---------------------------------------------------------------- 1. sessions
do $$
declare r jsonb; tok text; i int;
begin
  for i in 1..5 loop r := public.customer_login('70999903', '0000'); end loop;
  r := public.customer_login('70999903', '1234');
  perform pg_temp.ok('login: 5 wrong PINs lock the account even with the right PIN', r->>'reason' = 'locked', r::text);
  perform public._rl_reset('customer:70999903');

  r := public.customer_login('70999901', '1234', 'test-phone');
  tok := r->>'session'; perform pg_temp.set('c1', tok);
  perform pg_temp.ok('login: correct PIN returns a session', (r->>'ok')::boolean and tok like 'tps1_%' and length(tok) >= 40, left(r::text, 120));
  perform pg_temp.ok('session: only the SHA-256 of the token is stored',
    exists (select 1 from public.app_sessions where token_hash = public._sha(tok))
    and not exists (select 1 from public.app_sessions s where s.device = tok or s.ip = tok or encode(s.token_hash, 'escape') = tok));
  perform pg_temp.set('c2', public.customer_login('70999902', '1234')->>'session');
  perform pg_temp.set('c3', public.customer_login('70999903', '1234')->>'session');
  perform pg_temp.set('m1', public.merchant_login('70999911', '4321')->>'session');
  perform pg_temp.set('m2', public.merchant_login('70999912', '4321')->>'session');
  r := public.merchant_login('70999911', '0000');
  perform pg_temp.ok('merchant login: wrong PIN refused', r->>'reason' = 'wrong_pin');
  perform pg_temp.set('a1', public.admin_login('tp_test_admin1', '9999')->>'session');
  perform pg_temp.set('a2', public.admin_login('tp_test_admin2', '9999')->>'session');
  perform pg_temp.ok('admin login works', pg_temp.get('a1') like 'tps1_%' and pg_temp.get('a2') like 'tps1_%');

  perform pg_temp.ok('session: a customer token is refused by merchant functions',
    pg_temp.err(format('select public.merchant_offers_v2(%L)', pg_temp.get('c1'))) = 'TP_SESSION_EXPIRED');
  perform pg_temp.ok('session: a made-up token is refused',
    pg_temp.err(format('select public.customer_profile_v2(%L)', 'tps1_' || repeat('A', 43))) = 'TP_SESSION_EXPIRED');
  perform pg_temp.ok('session: a merchant token is refused by admin functions',
    pg_temp.err(format('select public.admin_list_customers_v2(%L)', pg_temp.get('m1'))) = 'TP_SESSION_EXPIRED');

  tok := public.customer_login('70999902', '1234')->>'session';
  perform public.session_logout(tok);
  perform pg_temp.ok('logout: the token stops working', pg_temp.err(format('select public.customer_profile_v2(%L)', tok)) = 'TP_SESSION_EXPIRED');

  tok := public.customer_login('70999902', '1234')->>'session';
  perform pg_temp.ok('logout everywhere: other devices are signed out', (public.session_logout_all(tok)->>'revoked')::int >= 2
    and pg_temp.err(format('select public.customer_profile_v2(%L)', pg_temp.get('c2'))) = 'TP_SESSION_EXPIRED');
  perform pg_temp.set('c2', public.customer_login('70999902', '1234')->>'session');

  tok := public.customer_login('70999903', '1234')->>'session';
  update public.customers set pin_hash = extensions.crypt('5678', extensions.gen_salt('bf', 4)) where phone = '70999903';
  perform pg_temp.ok('PIN change revokes every session of the account', pg_temp.err(format('select public.customer_profile_v2(%L)', tok)) = 'TP_SESSION_EXPIRED');
  update public.customers set pin_hash = extensions.crypt('1234', extensions.gen_salt('bf', 4)) where phone = '70999903';

  tok := public.customer_login('70999903', '1234')->>'session';
  update public.customers set status = 'frozen' where phone = '70999903';
  perform pg_temp.ok('a frozen account loses its sessions', pg_temp.err(format('select public.customer_qr_issue(%L)', tok)) = 'TP_SESSION_EXPIRED');
  update public.customers set status = 'active' where phone = '70999903';
  perform pg_temp.set('c3', public.customer_login('70999903', '1234')->>'session');

  update public.app_sessions set expires_at = now() - interval '1 second' where token_hash = public._sha(pg_temp.get('c3'));
  perform pg_temp.ok('an expired session is refused', pg_temp.err(format('select public.customer_profile_v2(%L)', pg_temp.get('c3'))) = 'TP_SESSION_EXPIRED');
  perform pg_temp.set('c3', public.customer_login('70999903', '1234')->>'session');
end $$;

-- ---------------------------------------------------------------- 2. purchase QR
do $$
declare q1 jsonb; q2 jsonb; s jsonb; r jsonb;
begin
  q1 := public.customer_qr_issue(pg_temp.get('c1'));
  perform pg_temp.ok('QR: issued with a 300 s lifetime and an 8-digit backup code',
    (q1->>'ok')::boolean and q1->>'qr' like 'TPPAY1.%' and q1->>'short' ~ '^\d{8}$' and (q1->>'ttl')::int = 300, left(q1::text, 160));
  perform pg_temp.ok('QR: no phone number or name inside the code', position('70999901' in q1->>'qr') = 0 and q1->>'qr' ~ '^TPPAY1\.[A-Za-z0-9_-]+$');
  q2 := public.customer_qr_issue(pg_temp.get('c1'));
  r := public.merchant_scan_code(pg_temp.get('m1'), q1->>'qr');
  perform pg_temp.ok('QR: an older code is invalid as soon as a new one is shown', r->>'error' = 'superseded', r::text);

  update public.purchase_codes set expires_at = now() - interval '1 second' where id = (q2->>'code_id')::uuid;
  r := public.merchant_scan_code(pg_temp.get('m1'), q2->>'qr');
  perform pg_temp.ok('QR: an expired code is refused with a clear message', r->>'error' = 'expired' and r->>'message' like 'انتهت صلاحية%', r::text);

  q1 := public.customer_qr_issue(pg_temp.get('c1')); perform pg_temp.set('q1', q1::text);
  s := public.merchant_scan_code(pg_temp.get('m1'), q1->>'qr');
  perform pg_temp.ok('scan: a valid code is claimed by the shop', (s->>'ok')::boolean and s->>'code_id' = q1->>'code_id', left(s::text, 200));
  perform pg_temp.ok('scan: the merchant gets no phone number', position('70999901' in s::text) = 0 and not (s->'customer' ? 'phone'));
  r := public.merchant_scan_code(pg_temp.get('m2'), q1->>'qr');
  perform pg_temp.ok('scan: a second shop cannot use a claimed code', r->>'error' = 'used', r::text);
  r := public.merchant_scan_code(pg_temp.get('m1'), q1->>'qr');
  perform pg_temp.ok('scan: the same shop scanning again gets its own open claim back', (r->>'ok')::boolean and r->>'code_id' = q1->>'code_id');
  r := public.customer_qr_status(pg_temp.get('c1'), (q1->>'code_id')::uuid);
  perform pg_temp.ok('customer sees the code was scanned and by which shop', r->>'state' = 'claimed' and r->>'shop' = 'محل اختبار 1', r::text);
  r := public.customer_qr_status(pg_temp.get('c2'), (q1->>'code_id')::uuid);
  perform pg_temp.ok('another customer cannot read this code', r->>'error' = 'not_found');

  r := public.merchant_scan_code(pg_temp.get('m1'), 'hello');
  perform pg_temp.ok('scan: garbage text is refused', r->>'error' = 'invalid');

  q2 := public.customer_qr_issue(pg_temp.get('c2'));
  r := public.merchant_scan_code(pg_temp.get('m2'), substr(q2->>'short', 1, 4) || '-' || substr(q2->>'short', 5, 4));
  perform pg_temp.ok('typed 8-digit code works (with a dash)', (r->>'ok')::boolean and r->>'code_id' = q2->>'code_id', r::text);
  perform pg_temp.set('q2', q2::text);
end $$;

do $$
declare r jsonb; i int; good text; q jsonb;
begin
  q := public.customer_qr_issue(pg_temp.get('c3')); good := q->>'short';
  for i in 1..5 loop r := public.merchant_scan_code(pg_temp.get('m2'), lpad(((good::bigint + i * 7919) % 100000000)::text, 8, '0')); end loop;
  r := public.merchant_scan_code(pg_temp.get('m2'), good);
  perform pg_temp.ok('typed codes: 5 wrong attempts lock typing for the shop, even the right code', r->>'error' = 'locked', r::text);
  r := public.merchant_scan_code(pg_temp.get('m2'), q->>'qr');
  perform pg_temp.ok('typed-code lock does not block camera scans', (r->>'ok')::boolean, r::text);
  perform public._rl2_reset('scanman:00000000-0000-4000-8000-000000000012');
end $$;

do $$
declare r jsonb; ppl jsonb; q jsonb;
begin
  q := public.customer_qr_issue(pg_temp.get('c2'));
  update public.customers set status = 'active' where phone = '70999911';
  perform pg_temp.set('c11', public.customer_login('70999911', '1234')->>'session');
  q := public.customer_qr_issue(pg_temp.get('c11'));
  r := public.merchant_scan_code(pg_temp.get('m1'), q->>'qr');
  perform pg_temp.ok('a shop cannot charge its own phone number', r->>'error' = 'own_account', r::text);
end $$;

-- ---------------------------------------------------------------- 3. purchase and approval
do $$
declare q jsonb; c jsonb; t jsonb; r jsonb; p0 bigint; p1 bigint; h text; idem text := 'idem-test-0001';
begin
  q := pg_temp.get('q1')::jsonb;
  r := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 20, false, null, '[]', null);
  perform pg_temp.ok('create: refused without an idempotency key', r->>'error' = 'bad_request');
  r := public.merchant_quote_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 20, false, null);
  perform pg_temp.ok('quote before creating', (r->>'ok')::boolean and (r->>'earn')::numeric = 100, r::text);
  c := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 20, false, null, '[]', idem);
  perform pg_temp.ok('create: purchase linked to the scanned code', (c->>'ok')::boolean and c->'tx'->>'status' = 'PENDING', left(c::text, 200));
  perform pg_temp.set('tx1', c->'tx'->>'id');
  r := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 20, false, null, '[]', idem);
  perform pg_temp.ok('create: the same key twice returns the same purchase', (r->>'replayed')::boolean and r->'tx'->>'id' = c->'tx'->>'id');
  perform pg_temp.ok('create: still one row in the table', (select count(*) from public.pos_transactions where code_id = (q->>'code_id')::uuid) = 1);
  r := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 25, false, null, '[]', 'idem-test-0002');
  perform pg_temp.ok('create: a code linked to a purchase cannot be used again', r->>'error' = 'used', r::text);
  r := public.merchant_create_tx_v2(pg_temp.get('m2'), (q->>'code_id')::uuid, 20, false, null, '[]', 'idem-test-0003');
  perform pg_temp.ok('create: another shop cannot use this claim', r->>'error' = 'claim_expired', r::text);
  perform pg_temp.ok('create: the old phone-number function is not needed (no phone argument exists)',
    not exists (select 1 from pg_proc where proname = 'merchant_create_tx_v2' and pg_get_function_arguments(oid) like '%phone%'));

  r := public.customer_qr_status(pg_temp.get('c1'), (q->>'code_id')::uuid);
  h := r->'tx'->>'detailHash';
  perform pg_temp.ok('customer receives the details to approve', r->>'state' = 'tx' and h ~ '^[0-9a-f]{64}$' and (r->'tx'->>'invoice')::numeric = 20, left(r::text, 200));

  r := public.customer_decide_tx_v2(pg_temp.get('c2'), (c->'tx'->>'id')::uuid, true, h);
  perform pg_temp.ok('approve: another customer cannot approve it', r->>'error' = 'not_found', r::text);
  r := public.customer_decide_tx_v2(pg_temp.get('c1'), (c->'tx'->>'id')::uuid, true, repeat('0', 64));
  perform pg_temp.ok('approve: refused when the details are not the ones shown', r->>'error' = 'details_changed', left(r::text, 120));
  r := public.customer_decide_tx_v2(pg_temp.get('c1'), (c->'tx'->>'id')::uuid, true, null);
  perform pg_temp.ok('approve: refused without the details fingerprint', r->>'error' = 'bad_request');

  select points into p0 from public.customers where phone = '70999901';
  r := public.customer_decide_tx_v2(pg_temp.get('c1'), (c->'tx'->>'id')::uuid, true, h);
  select points into p1 from public.customers where phone = '70999901';
  perform pg_temp.ok('approve: points added once', (r->>'ok')::boolean and r->>'status' = 'CONFIRMED' and p1 = p0 + 100, format('%s → %s %s', p0, p1, r));
  r := public.customer_decide_tx_v2(pg_temp.get('c1'), (c->'tx'->>'id')::uuid, true, h);
  perform pg_temp.ok('approve: a second approval changes nothing', r->>'error' = 'already_decided' and (select points from public.customers where phone = '70999901') = p1);
  r := public.customer_decide_tx_v2(pg_temp.get('c1'), (c->'tx'->>'id')::uuid, false, null);
  perform pg_temp.ok('approve: cannot cancel after confirming', r->>'error' = 'already_decided');
end $$;

do $$
declare q jsonb; s jsonb; c jsonb; r jsonb; h text; p0 bigint;
begin
  -- a purchase not approved within 300 s expires, without points
  q := public.customer_qr_issue(pg_temp.get('c2'));
  s := public.merchant_scan_code(pg_temp.get('m2'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m2'), (q->>'code_id')::uuid, 30, false, null, '[]', 'idem-exp-0001');
  h := (public.customer_qr_status(pg_temp.get('c2'), (q->>'code_id')::uuid))->'tx'->>'detailHash';
  update public.pos_transactions set created_at = now() - interval '301 seconds' where id = (c->'tx'->>'id')::uuid;
  select points into p0 from public.customers where phone = '70999902';
  r := public.customer_decide_tx_v2(pg_temp.get('c2'), (c->'tx'->>'id')::uuid, true, h);
  perform pg_temp.ok('expiry: approval after 300 s is refused, no points', r->>'error' = 'expired'
    and (select status from public.pos_transactions where id = (c->'tx'->>'id')::uuid) = 'EXPIRED'
    and (select points from public.customers where phone = '70999902') = p0, r::text);

  -- one pending purchase per customer
  q := public.customer_qr_issue(pg_temp.get('c2'));
  s := public.merchant_scan_code(pg_temp.get('m2'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m2'), (q->>'code_id')::uuid, 30, false, null, '[]', 'idem-pend-0001');
  perform pg_temp.set('tx_pending_c2', c->'tx'->>'id');
  q := public.customer_qr_issue(pg_temp.get('c2'));
  s := public.merchant_scan_code(pg_temp.get('m1'), q->>'qr');
  r := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 30, false, null, '[]', 'idem-pend-0002');
  perform pg_temp.ok('only one pending purchase per customer', r->>'error' = 'pending', r::text);

  -- a purchase made just before the code rotates stays valid
  r := public.merchant_cancel_tx(pg_temp.get('m2'), pg_temp.get('tx_pending_c2')::uuid);
  perform pg_temp.ok('the shop can cancel its own pending purchase', (r->>'ok')::boolean);
  q := public.customer_qr_issue(pg_temp.get('c2'));
  update public.purchase_codes set issued_at = now() - interval '290 seconds', expires_at = now() + interval '10 seconds' where id = (q->>'code_id')::uuid;
  s := public.merchant_scan_code(pg_temp.get('m1'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 18, false, null, '[]', 'idem-rot-0001');
  update public.purchase_codes set expires_at = now() - interval '1 second' where id = (q->>'code_id')::uuid;
  perform public.customer_qr_issue(pg_temp.get('c2'));
  h := (public.customer_qr_status(pg_temp.get('c2'), (q->>'code_id')::uuid))->'tx'->>'detailHash';
  r := public.customer_decide_tx_v2(pg_temp.get('c2'), (c->'tx'->>'id')::uuid, true, h);
  perform pg_temp.ok('a purchase created at second 290 survives the QR change', (r->>'ok')::boolean, r::text);
end $$;

-- ---------------------------------------------------------------- 4. same results as today's price rules
do $$
declare q jsonb; t jsonb; o jsonb; inv numeric; red boolean; bad int := 0; det text := '';
begin
  foreach inv in array array[7.5, 15, 33.33, 120, 999.99] loop
    foreach red in array array[false, true] loop
      q := public._tx_quote('00000000-0000-4000-8000-000000000012', '70999903', inv, red, null);
      begin
        o := public.create_transaction('00000000-0000-4000-8000-000000000012', '70999903', inv, red, null, '[]');
        if (o->>'redeem_pts')::numeric is distinct from (q->>'redeem_pts')::numeric or (o->>'net')::numeric is distinct from (q->>'net')::numeric
           or (o->>'earn')::numeric is distinct from (q->>'earn')::numeric or (o->>'disc')::numeric is distinct from (q->>'disc')::numeric then
          bad := bad + 1; det := det || format(' %s/%s', inv, red);
        end if;
        raise exception 'undo';
      exception when raise_exception then null;
      end;
    end loop;
  end loop;
  perform pg_temp.ok('price rules: new quote equals create_transaction for 10 cases', bad = 0, det);
end $$;

-- ---------------------------------------------------------------- 5. Treasures and profile
do $$
declare r jsonb; q jsonb; c jsonb; h text; tok text := pg_temp.get('c3'); i int;
  big text := 'data:image/jpeg;base64,' || repeat('A', 260000);
  small text := 'data:image/jpeg;base64,' || repeat('QUJD', 2000);
begin
  -- a purchase before the profile is complete: points yes, treasure no
  q := public.customer_qr_issue(tok); perform public.merchant_scan_code(pg_temp.get('m1'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 40, false, null, '[]', 'idem-tr-0001');
  h := (public.customer_qr_status(tok, (q->>'code_id')::uuid))->'tx'->>'detailHash';
  r := public.customer_decide_tx_v2(tok, (c->'tx'->>'id')::uuid, true, h);
  perform pg_temp.ok('treasures: $40 before the profile is complete gives no picture', (r->>'ok')::boolean and r->'unlocked' = 'null'::jsonb, r::text);

  r := public.customer_update_profile(tok, 'سارة', null, null);
  perform pg_temp.ok('profile: name only does not start the treasures', (r->>'treasures_started')::boolean = false);
  r := public.customer_update_profile(tok, 'Sara1', null, null);
  perform pg_temp.ok('profile: digits in the name are refused', (r->>'ok')::boolean = false);
  r := public.customer_update_profile(tok, null, null, big);
  perform pg_temp.ok('profile: a photo over 150 KB is refused', r->>'error' = 'حجم الصورة كبير');
  r := public.customer_update_profile(tok, null, null, '<script>');
  perform pg_temp.ok('profile: anything that is not an image is refused', (r->>'ok')::boolean = false);
  r := public.customer_update_profile(tok, null, 'خالد', small);
  perform pg_temp.ok('profile: name + family name + photo starts the treasures', (r->>'treasures_started')::boolean and (r->>'profile_complete')::boolean, r::text);
  r := public.customer_update_profile(tok, '', '', '');
  perform pg_temp.ok('profile: empty values never erase saved data',
    (select name = 'سارة' and last_name = 'خالد' and photo_url = small from public.customers where phone = '70999903'));
  r := public.customer_profile_v2(tok, null);
  perform pg_temp.ok('profile: saved on the server and returned after login', r->'customer'->>'name' = 'سارة' and r->'customer'->>'photo_url' = small);
  r := public.customer_profile_v2(tok, r->'customer'->>'photo_hash');
  perform pg_temp.ok('profile: the photo is not re-sent when the app already has it', r->'customer'->'photo_url' = 'null'::jsonb);
  r := public.customer_profile_v2(public.customer_login('70999903', '1234', 'second-phone')->>'session', null);
  perform pg_temp.ok('profile: a second phone sees the same profile (no new registration)', (r->'customer'->>'profile_complete')::boolean);

  -- after the profile: 14.99 no, 15 yes, same shop again no, another shop yes
  q := public.customer_qr_issue(tok); perform public.merchant_scan_code(pg_temp.get('m2'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m2'), (q->>'code_id')::uuid, 14.99, false, null, '[]', 'idem-tr-0002');
  r := public.customer_decide_tx_v2(tok, (c->'tx'->>'id')::uuid, true, (public.customer_qr_status(tok, (q->>'code_id')::uuid))->'tx'->>'detailHash');
  perform pg_temp.ok('treasures: $14.99 gives no picture', r->'unlocked' = 'null'::jsonb);
  q := public.customer_qr_issue(tok); perform public.merchant_scan_code(pg_temp.get('m2'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m2'), (q->>'code_id')::uuid, 15, false, null, '[]', 'idem-tr-0003');
  r := public.customer_decide_tx_v2(tok, (c->'tx'->>'id')::uuid, true, (public.customer_qr_status(tok, (q->>'code_id')::uuid))->'tx'->>'detailHash');
  perform pg_temp.ok('treasures: $15 at the same shop unlocks the first picture', (r->'unlocked'->>'seq')::int = 1 and r->'unlocked'->>'slug' = 'p1', r::text);
  q := public.customer_qr_issue(tok); perform public.merchant_scan_code(pg_temp.get('m2'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m2'), (q->>'code_id')::uuid, 50, false, null, '[]', 'idem-tr-0004');
  r := public.customer_decide_tx_v2(tok, (c->'tx'->>'id')::uuid, true, (public.customer_qr_status(tok, (q->>'code_id')::uuid))->'tx'->>'detailHash');
  perform pg_temp.ok('treasures: one picture per shop per cycle', r->'unlocked' = 'null'::jsonb);
  q := public.customer_qr_issue(tok); perform public.merchant_scan_code(pg_temp.get('m1'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 20, false, null, '[]', 'idem-tr-0005');
  r := public.customer_decide_tx_v2(tok, (c->'tx'->>'id')::uuid, true, (public.customer_qr_status(tok, (q->>'code_id')::uuid))->'tx'->>'detailHash');
  perform pg_temp.ok('treasures: a second shop unlocks the second picture (order kept)', (r->'unlocked'->>'seq')::int = 2 and r->'unlocked'->>'slug' = 'p2', r::text);

  -- adding landmarks later does not change progress
  r := public.admin_treasure_upsert_v2(pg_temp.get('a2'), null, 'معلم اختبار', null, null, 5, true);
  r := public.customer_treasures_v2(tok);
  perform pg_temp.ok('treasures: a new landmark leaves discovered pictures unchanged',
    jsonb_array_length(r->'unlocked') = 2 and r->'unlocked'->0->>'slug' = 'p1' and r->'unlocked'->1->>'slug' = 'p2' and (r->>'total')::int = (select count(*) from public.treasure_pics where active), left(r::text, 200));
  perform pg_temp.ok('treasures: the list is not limited to 11', (select count(*) from public.treasure_pics where active) >= 12);
  perform pg_temp.ok('treasures: the old decide_transaction can no longer write pictures',
    pg_temp.err($q$insert into public.customer_unlocks(customer_phone, pic_id) select '70999903', id from public.treasure_pics where slug = 'p5'$q$) = 'NO_ERROR'
    and not exists (select 1 from public.customer_unlocks where customer_phone = '70999903' and merchant_id is null));
  update public.app_settings set value = 20 where key = 'treasure_min_invoice';
  perform pg_temp.ok('treasures: the $15 limit is a setting', public._setting('treasure_min_invoice', 15) = 20);
  update public.app_settings set value = 15 where key = 'treasure_min_invoice';
end $$;

-- ---------------------------------------------------------------- 6. merchant view and photo privacy
do $$
declare r jsonb;
begin
  r := public.merchant_transactions_v2(pg_temp.get('m1'));
  perform pg_temp.ok('merchant history shows no customer phone numbers', jsonb_array_length(r) > 0 and r::text !~ '7099990[1-3]', left(r::text, 200));
  perform pg_temp.ok('merchant history shows no customer photos', position('data:image' in r::text) = 0);
  r := public.merchant_offers_v2(pg_temp.get('m1'));
  perform pg_temp.ok('merchant functions use the session shop, not an id from the browser',
    case when r ? 'args' then r->'args'->>0 = '00000000-0000-4000-8000-000000000011'           -- replica stub
         else jsonb_typeof(r) = 'array' and not exists (select 1 from jsonb_array_elements(r) e
                where coalesce(e->>'mid', e->>'merchant_id', '00000000-0000-4000-8000-000000000011') <> '00000000-0000-4000-8000-000000000011') end, left(r::text, 200));
  r := public.merchant_delete_offer_v2(pg_temp.get('m2'), '00000000-0000-4000-8000-0000000000ff');
  perform pg_temp.ok('merchant arguments keep their order',
    case when r ? 'args' then r->'args'->>0 = '00000000-0000-4000-8000-0000000000ff' and r->'args'->>1 = '00000000-0000-4000-8000-000000000012'
         else coalesce((r->>'ok')::boolean, false) = false end, r::text);   -- real function: an offer of another shop is refused
end $$;

-- ---------------------------------------------------------------- 7. reports, admin, limits, monitoring
do $$
declare q jsonb; c jsonb; r jsonb; i int;
begin
  q := public.customer_qr_issue(pg_temp.get('c2')); perform public.merchant_scan_code(pg_temp.get('m1'), q->>'qr');
  c := public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 60, false, null, '[]', 'idem-rep-0001');
  r := public.report_tx(pg_temp.get('c2'), 'not_my_purchase', (c->'tx'->>'id')::uuid);
  perform pg_temp.ok('report: a customer report cancels the waiting purchase', (r->>'ok')::boolean
    and (select status from public.pos_transactions where id = (c->'tx'->>'id')::uuid) = 'CANCELLED');
  q := public.customer_qr_issue(pg_temp.get('c2')); perform public.merchant_scan_code(pg_temp.get('m1'), q->>'qr');
  r := public.report_tx(pg_temp.get('m1'), 'not_account_owner', null, (q->>'code_id')::uuid);
  perform pg_temp.ok('report: a merchant report releases the scanned code', (r->>'ok')::boolean
    and (public.merchant_create_tx_v2(pg_temp.get('m1'), (q->>'code_id')::uuid, 10, false, null, '[]', 'idem-rep-0002'))->>'error' in ('claim_expired', 'used'));
  r := public.report_tx(pg_temp.get('m2'), 'other', (c->'tx'->>'id')::uuid);
  perform pg_temp.ok('report: a shop cannot report another shop''s purchase', r->>'error' = 'not_found');
end $$;

do $$ declare r text; begin
  r := pg_temp.err(format('select public.admin_topup_merchant_v2(%L, %L, 10)', pg_temp.get('a2'), '00000000-0000-4000-8000-000000000011'));
  perform pg_temp.ok('admin: money actions need the primary admin', r = 'TP_FORBIDDEN', r);
end $$;

do $$
declare r jsonb; q jsonb; c jsonb; i int;
begin
  r := public.admin_topup_merchant_v2(pg_temp.get('a1'), '00000000-0000-4000-8000-000000000011', 10);
  perform pg_temp.ok('admin: the primary admin can top up', r->>'stub' = 'admin_topup_merchant' or (r->>'ok')::boolean, r::text);
  r := public.admin_delete_customer_v2(pg_temp.get('a1'), '70999999');
  perform pg_temp.ok('admin: the session admin id is passed, not one from the browser', r ? 'ok' or r->'args'->>1 = '00000000-0000-4000-8000-0000000000a1', r::text);
  perform pg_temp.ok('admin: actions are logged', exists (select 1 from public.tx_events where event = 'admin_action' and detail->>'fn' = 'admin_topup_merchant'));
  r := public.admin_set_setting_v2(pg_temp.get('a1'), 'qr_ttl_sec', 5);
  perform pg_temp.ok('settings: values outside the safe range are refused', (r->>'ok')::boolean = false, r::text);
  r := public.admin_set_setting_v2(pg_temp.get('a1'), 'alert_same_shop_per_day', 3);
  perform pg_temp.ok('settings: limits can be changed without a migration', (r->>'ok')::boolean);

  for i in 1..3 loop
    q := public.customer_qr_issue(pg_temp.get('c1')); perform public.merchant_scan_code(pg_temp.get('m2'), q->>'qr');
    c := public.merchant_create_tx_v2(pg_temp.get('m2'), (q->>'code_id')::uuid, 5, false, null, '[]', 'idem-alert-000' || i);
    perform public.customer_decide_tx_v2(pg_temp.get('c1'), (c->'tx'->>'id')::uuid, true, (public.customer_qr_status(pg_temp.get('c1'), (q->>'code_id')::uuid))->'tx'->>'detailHash');
  end loop;
  perform pg_temp.ok('monitoring: repeated purchases at one shop raise an alert, without blocking',
    exists (select 1 from public.tx_events where event = 'alert_same_shop' and customer_phone = '70999901')
    and (select count(*) from public.pos_transactions where customer_phone = '70999901' and merchant_id = '00000000-0000-4000-8000-000000000012' and status = 'CONFIRMED') = 3);
  r := public.admin_security_feed_v2(pg_temp.get('a2'));
  perform pg_temp.ok('monitoring: alerts and reports reach the admin feed', jsonb_array_length(r->'events') > 0 and jsonb_array_length(r->'reports') >= 2);
  perform pg_temp.ok('log: every step of a purchase is recorded',
    (select count(distinct event) from public.tx_events where event in ('qr_issued','scanned','scan_failed','tx_created','tx_confirmed','tx_expired','reported')) = 7);
end $$;

-- (registration and its server-side welcome gift: tp-auth-email-v1-tests.sql)

-- ---------------------------------------------------------------- 9. privileges as the public API role
grant all on _t, _ctx to anon; grant usage on sequence _t_n_seq to anon;
set local role anon;
do $$
declare r text;
begin
  r := pg_temp.err('select count(*) from public.app_sessions');
  insert into _t(name, ok, detail) values ('anon cannot read the sessions table', r like 'permission denied%', r);
  r := pg_temp.err('select count(*) from public.purchase_codes');
  insert into _t(name, ok, detail) values ('anon cannot read purchase codes', r like 'permission denied%', r);
  r := pg_temp.err('select count(*) from public.tx_events');
  insert into _t(name, ok, detail) values ('anon cannot read the event log', r like 'permission denied%', r);
  r := pg_temp.err($q$select public._issue_session('customer', '70999901', null, null, null)$q$);
  insert into _t(name, ok, detail) values ('anon cannot call internal helpers (_issue_session)', r like 'permission denied%', r);
  r := pg_temp.err($q$select public._unlock_treasure(null::public.pos_transactions)$q$);
  insert into _t(name, ok, detail) values ('anon cannot call internal helpers (_unlock_treasure)', r like 'permission denied%', r);
  r := pg_temp.err($q$select public.customer_login('70999901', '1234')$q$);
  insert into _t(name, ok, detail) values ('anon can call the login API', r = 'NO_ERROR', r);
  r := pg_temp.err($q$select public.treasure_list()$q$);
  insert into _t(name, ok, detail) values ('anon can read the public landmark list', r = 'NO_ERROR', r);
end $$;
reset role;

-- ---------------------------------------------------------------- wipe from the app (admin_wipe_all_data_v2) and restore
create temp table _wsnap on commit drop as select 1 as k, null::text as tname, 0::bigint as n, null::text as h where false;
do $$ declare t regclass; vn bigint; vh text; begin
  foreach t in array public._tp_wipe_scope() loop
    execute format('select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from %s r', t) into vn, vh;
    insert into _wsnap values (1, t::text, vn, vh);
  end loop;
end $$;
do $$ declare r jsonb; e text; nc bigint := (select count(*) from public.customers); begin
  e := pg_temp.err(format('select public.admin_wipe_all_data_v2(%L, %L, %L)', pg_temp.get('a2'), '9999', 'امسح كل البيانات'));
  perform pg_temp.ok('wipe v2: a non-primary admin session is refused', e = 'TP_FORBIDDEN', e);
  e := pg_temp.err(format('select public.admin_wipe_all_data_v2(%L, %L, %L)', 'tps1_not_a_session', '9999', 'امسح كل البيانات'));
  perform pg_temp.ok('wipe v2: no session, no wipe', e = 'TP_SESSION_EXPIRED', e);
  r := public.admin_wipe_all_data_v2(pg_temp.get('a1'), '9999', 'امسح كل البيانات');
  perform pg_temp.ok('wipe v2: off by default (switch admin_wipe_enabled = 0)', r->>'error' = 'wipe_disabled', r::text);
  r := public.admin_set_setting_v2(pg_temp.get('a1'), 'admin_wipe_enabled', 1);
  perform pg_temp.ok('wipe v2: an admin session cannot turn the switch on', r->>'error' = 'unknown_key', r::text);
  update public.app_settings set value = 1 where key = 'admin_wipe_enabled';     -- the owner, SQL editor
  r := public.admin_wipe_all_data_v2(pg_temp.get('a1'), '9999', 'نعم');
  perform pg_temp.ok('wipe v2: the exact confirmation phrase is required', r->>'error' = 'confirm', r::text);
  r := public.admin_wipe_all_data_v2(pg_temp.get('a1'), '0000', 'امسح كل البيانات');
  perform pg_temp.ok('wipe v2: a wrong PIN is refused', not (r->>'ok')::boolean and r->>'error' = 'رمز الإدارة غير صحيح', r::text);
  perform pg_temp.ok('wipe v2: nothing deleted by the refused attempts', (select count(*) from public.customers) = nc);
  r := public.admin_wipe_all_data_v2(pg_temp.get('a1'), '9999', ' امسح كل البيانات ');
  perform pg_temp.ok('wipe v2: primary session + switch + phrase + PIN → wiped, with a copy stamp', (r->>'ok')::boolean and r->>'snapshot' like 'w2%', r::text);
  perform pg_temp.ok('wipe v2: merchants and customers are empty', not exists (select 1 from public.customers) and not exists (select 1 from public.merchants));
  perform pg_temp.ok('wipe v2: the switch turned itself off', public._setting('admin_wipe_enabled', 0) = 0);
  perform pg_temp.ok('wipe v2: logged with the copy stamp (the log is kept)', exists (select 1 from public.tx_events
    where event = 'admin_action' and detail->>'fn' = 'admin_wipe_all_data_v2' and detail->>'snapshot' = r->>'snapshot'));
  perform pg_temp.set('wstamp', r->>'snapshot');
end $$;
do $$ declare r jsonb; e text; t text; vn bigint; vh text; bad text; begin
  perform pg_temp.set('a1', public.admin_login('tp_test_admin1', '9999')->>'session');     -- the admin logs in again
  r := public.admin_wipe_all_data_v2(pg_temp.get('a1'), '9999', 'امسح كل البيانات');
  perform pg_temp.ok('wipe v2: a second wipe needs the owner to turn the switch on again', r->>'error' = 'wipe_disabled', r::text);
  r := public._tp_wipe_restore(pg_temp.get('wstamp'));
  for t in select w.tname from _wsnap w where w.tname <> 'app_sessions' loop   -- sessions: last_seen_at moves on use; checked below
    execute format('select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from public.%I r', t) into vn, vh;
    if not exists (select 1 from _wsnap w where w.tname = t and w.n = vn and w.h = vh) then bad := concat_ws(', ', bad, t); end if;
  end loop;
  perform pg_temp.ok('restore: every table back with the same rows and checksum (sessions included)', (r->>'ok')::boolean and bad is null, coalesce(bad, r::text));
  perform pg_temp.ok('restore: customers log in again', (public.customer_login('70999902', '1234')->>'ok')::boolean);
  e := pg_temp.err(format('select public.customer_qr_issue(%L)', pg_temp.get('c2')));
  perform pg_temp.ok('restore: sessions from before the wipe work again', e = 'NO_ERROR' or e not like 'TP_SESSION%', e);
end $$;

-- ---------------------------------------------------------------- result
select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
