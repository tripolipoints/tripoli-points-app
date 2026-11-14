-- =====================================================================================================================
-- Tripoli Points — Batch 3-C database-level integration test (Staging-safe, NON-DESTRUCTIVE)
-- ONE statement (a DO block). Every app call is made as role `anon` (exactly what the public key can do), with real
-- server sessions. Fixtures (synthetic phones 799970xx, admins tp_it_*) exist only inside this statement.
-- The block ALWAYS ends with RAISE EXCEPTION 'TP_IT_RESULT ...', so PostgreSQL rolls back everything it did:
-- accounts, sessions, ledger rows, lock records, audit rows. Only sequence counters may advance (harmless gaps).
-- Verification reads (balances, table rows) are done as the session user between calls, never through the app path.
-- Preflight before running: security/client-b3/integration/preflight.sh <this file>  (must print PREFLIGHT OK)
-- Result line format: P = passed, F = failed, I = observation (no approved expectation; reported, not judged).
-- =====================================================================================================================
do $tp_it$
declare
  t jsonb := '[]';                      -- [name, verdict, detail]
  r jsonb; s jsonb; q jsonb; x jsonb;
  e text; v text;
  a1 text; a2 text; c1 text; c2 text; m1 text; m2 text; st text; stf text;
  a1_id uuid := '00000000-0000-4000-8000-0000000b3ca1'; a2_id uuid := '00000000-0000-4000-8000-0000000b3ca2';
  m1_id uuid := '00000000-0000-4000-8000-0000000b3c01'; m2_id uuid := '00000000-0000-4000-8000-0000000b3c02';
  m3_id uuid := '00000000-0000-4000-8000-0000000b3c03';
  code uuid; tx uuid; tx2 uuid; dh text; dev text := 'tp-it-device-AAAA-0001'; dev2 text := 'tp-it-device-BBBB-0002';
  b0 numeric; b1 numeric; b2 numeric; n int; i int; logo0 text;
begin
  -- ------------------------------------------------------------------ guards
  if current_setting('server_version_num')::int < 140000 then raise exception 'TP_IT_ABORT old server'; end if;
  if exists (select 1 from public.customers where phone like '799970__') or exists (select 1 from public.merchants where phone like '799970__')
     or exists (select 1 from public.merchant_staff where phone like '799970__') or exists (select 1 from public.admin_users where username like 'tp\_it\_%') then
    raise exception 'TP_IT_ABORT synthetic range already in use';
  end if;
  if public._setting('engine_strict', -1) <> 1 or public._setting('sub_enforce', -1) <> 0 or public._setting('email_delivery_enabled', -1) <> 0 then
    raise exception 'TP_IT_ABORT flags not as expected (engine_strict=1, sub_enforce=0, email_delivery_enabled=0)';
  end if;

  -- ------------------------------------------------------------------ fixtures (session user; rolled back)
  insert into public.admin_users(id, username, pin_hash, is_primary) values
    (a1_id, 'tp_it_a1', extensions.crypt('7391', extensions.gen_salt('bf', 4)), true),
    (a2_id, 'tp_it_a2', extensions.crypt('7392', extensions.gen_salt('bf', 4)), false);
  insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
    (m1_id, 'محل اختبار 1', '79997011', extensions.crypt('4826', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 50, 'active'),
    (m2_id, 'محل اختبار 2', '79997012', extensions.crypt('4827', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 50, 'active'),
    (m3_id, 'محل اختبار 3', '79997013', extensions.crypt('4828', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 50, 'active');
  -- legacy top-up wallet funds the reward points (same fixture as the approved engine tests; see open decision §02)
  insert into public.topups(merchant_id, amount, source) values (m1_id, 100, 'test');

  -- =================================================================== ADMIN (as anon)
  set local role anon;
  r := public.admin_login(p_username => 'tp_it_a1', p_pin => '0000', p_device => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('A01 admin_login wrong PIN refused', case when coalesce((r->>'ok')::boolean, false) then 'F' else 'P' end, left(r::text, 120)));
  r := public.admin_login(p_username => 'tp_it_a1', p_pin => '7391', p_device => 'tp-it'); a1 := r->>'session';
  t := t || jsonb_build_array(jsonb_build_array('A02 admin_login right PIN gives a server session + admin {id,is_primary}',
       case when a1 is not null and (r->'admin'->>'is_primary')::boolean and (r->'admin'->>'id')::uuid = a1_id then 'P' else 'F' end, null));
  r := public.admin_login(p_username => 'tp_it_a2', p_pin => '7392', p_device => 'tp-it'); a2 := r->>'session';
  t := t || jsonb_build_array(jsonb_build_array('A03 non-primary admin login', case when a2 is not null then 'P' else 'F' end, null));
  begin x := to_jsonb(public.admin_list_customers_v2(a1)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('A04 admin_list_customers_v2 with admin session', case when e = 'NO_ERROR' then 'P' else 'F' end, e));
  r := public.admin_allowance_adjust_v2(a1, m1_id, 5000, 30, 'tp-it allowance');
  t := t || jsonb_build_array(jsonb_build_array('A05 admin grants branch acceptance allowance (ledger)', case when coalesce((r->>'ok')::boolean, false) then 'P' else 'F' end, left(r::text, 160)));

  -- =================================================================== CUSTOMER (as anon)
  r := public.customer_register('79997001', '8642', 'زبون اختبار 1', 0, 0, null);
  t := t || jsonb_build_array(jsonb_build_array('C01 customer_register (public path)', case when r ? 'phone' or coalesce((r->>'ok')::boolean, false) then 'P' else 'F' end, left(r::text, 120)));
  r := public.customer_register('79997002', '8643', 'زبون اختبار 2', 0, 0, null);
  r := public.customer_login(p_phone => '79997001', p_pin => '1111', p_device => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('C02 customer_login wrong PIN refused', case when coalesce((r->>'ok')::boolean, false) then 'F' else 'P' end, left(r::text, 120)));
  c1 := public.customer_login(p_phone => '79997001', p_pin => '8642', p_device => 'tp-it')->>'session';
  c2 := public.customer_login(p_phone => '79997002', p_pin => '8643', p_device => 'tp-it')->>'session';
  t := t || jsonb_build_array(jsonb_build_array('C03 customer_login right PIN gives session', case when c1 is not null and c2 is not null then 'P' else 'F' end, null));
  begin x := to_jsonb(public.customer_points_v2(c1)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('C04 customer_points_v2 with own session', case when e = 'NO_ERROR' then 'P' else 'F' end, e));
  reset role; select points into b0 from public.customers where phone = '79997001'; set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('C05 starting balance from the welcome gift (admin setting)', case when b0 > 0 then 'P' else 'F' end, b0::text));

  -- =================================================================== MERCHANT (as anon)
  r := public.merchant_login(p_phone => '79997011', p_pin => '0000', p_device => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('M01 merchant_login wrong PIN refused', case when coalesce((r->>'ok')::boolean, false) then 'F' else 'P' end, left(r::text, 120)));
  m1 := public.merchant_login(p_phone => '79997011', p_pin => '4826', p_device => 'tp-it')->>'session';
  m2 := public.merchant_login(p_phone => '79997012', p_pin => '4827', p_device => 'tp-it')->>'session';
  t := t || jsonb_build_array(jsonb_build_array('M02 merchant_login right PIN gives session', case when m1 is not null and m2 is not null then 'P' else 'F' end, null));

  -- purchase: customer shows code → chooses points → merchant scans, quotes, creates → customer confirms with hash
  q := public.customer_qr_issue(c1); code := (q->>'code_id')::uuid;
  t := t || jsonb_build_array(jsonb_build_array('C06 customer_qr_issue gives a one-time code', case when code is not null and q->>'qr' is not null then 'P' else 'F' end, null));
  r := public.customer_qr_set_redeem(c1, code, 500);
  t := t || jsonb_build_array(jsonb_build_array('C07 customer chooses 500 points on the code', case when coalesce((r->>'ok')::boolean, true) and r->>'error' is null then 'P' else 'F' end, left(r::text, 120)));
  begin r := public.customer_qr_set_redeem(c2, code, 900); e := coalesce(r->>'error', r->>'reason', 'NO_ERROR'); exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S01 another customer cannot change the redeem on my code', case when e <> 'NO_ERROR' then 'P' else 'F' end, e));
  s := public.merchant_scan_code(m1, q->>'qr');
  t := t || jsonb_build_array(jsonb_build_array('M03 merchant_scan_code accepts the code', case when coalesce((s->>'ok')::boolean, false) then 'P' else 'F' end, left(s::text, 120)));
  r := public.merchant_scan_code(m2, q->>'qr');
  t := t || jsonb_build_array(jsonb_build_array('S02 a second shop cannot claim the same code', case when coalesce((r->>'ok')::boolean, false) then 'F' else 'P' end, left(r::text, 120)));
  begin x := to_jsonb(public.merchant_quote_v2(p_session => m1, p_code_id => code, p_invoice => 20, p_redeem => true, p_offer_id => null)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('M04 merchant_quote_v2', case when e = 'NO_ERROR' then 'P' else 'F' end, e));
  r := public.merchant_create_tx_v2(m1, code, 20, true, null, '[]'::jsonb, 'tp-it-idem-1'); tx := (r->'tx'->>'id')::uuid;
  t := t || jsonb_build_array(jsonb_build_array('M05 merchant_create_tx_v2 → pending tx with the customer''s 500 points',
       case when tx is not null and (r->'tx'->>'redeemPts')::numeric = 500 then 'P' else 'F' end, left(r::text, 160)));
  r := public.merchant_create_tx_v2(m1, code, 20, true, null, '[]'::jsonb, 'tp-it-idem-1');
  t := t || jsonb_build_array(jsonb_build_array('M06 same idempotency key does not create a second tx', case when (r->'tx'->>'id')::uuid is not distinct from tx or coalesce((r->>'replayed')::boolean, false) or r->>'error' is not null then 'P' else 'F' end, left(r::text, 120)));
  reset role; select count(*) into n from public.pos_transactions where id = tx or (merchant_id = m1_id and created_at > now() - interval '1 hour'); set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('M07 exactly one tx row exists for this purchase', case when n = 1 then 'P' else 'F' end, n::text));
  reset role; select coalesce(sum(pts), 0) into b1 from public.allowance_holds where tx_id = tx and status = 'held'; set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('M08 branch allowance holds the redeemed points while pending', case when b1 = 500 then 'P' else 'F' end, b1::text));
  begin r := public.merchant_cancel_tx(m2, tx); e := coalesce(r->>'error', r->>'reason', case when coalesce((r->>'ok')::boolean, false) then 'NO_ERROR' else r::text end); exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S03 another shop cannot cancel this tx', case when e <> 'NO_ERROR' then 'P' else 'F' end, left(e, 120)));
  x := to_jsonb(public.customer_transactions_v2(c1));
  select el->>'detailHash' into dh from jsonb_array_elements(case when jsonb_typeof(x) = 'array' then x else '[]' end) el where (el->>'id')::uuid = tx;
  t := t || jsonb_build_array(jsonb_build_array('C08 customer sees the pending tx with its detail hash', case when dh is not null then 'P' else 'F' end, null));
  x := to_jsonb(public.merchant_transactions_v2(m1));
  t := t || jsonb_build_array(jsonb_build_array('S04 merchant tx list does not expose the customer phone', case when position('79997001' in x::text) = 0 then 'P' else 'F' end, null));
  begin r := public.customer_decide_tx_v2(c2, tx, true, dh); e := coalesce(r->>'error', r->>'reason', case when coalesce((r->>'ok')::boolean, false) then 'NO_ERROR' else r::text end); exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S05 another customer cannot confirm my tx', case when e <> 'NO_ERROR' then 'P' else 'F' end, left(e, 120)));
  begin r := public.customer_decide_tx_v2(c1, tx, true, md5('tampered')); e := coalesce(r->>'error', r->>'reason', case when coalesce((r->>'ok')::boolean, false) then 'NO_ERROR' else r::text end); exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S06 confirm with a tampered detail hash refused', case when e <> 'NO_ERROR' then 'P' else 'F' end, left(e, 120)));
  r := public.customer_decide_tx_v2(c1, tx, true, dh);
  t := t || jsonb_build_array(jsonb_build_array('C09 customer confirms with the right hash', case when coalesce((r->>'ok')::boolean, false) then 'P' else 'F' end, left(r::text, 120)));
  r := public.customer_decide_tx_v2(c1, tx, true, dh);
  t := t || jsonb_build_array(jsonb_build_array('S07 second confirm does not apply twice', case when coalesce((r->>'ok')::boolean, false) and not coalesce((r->>'replayed')::boolean, false) then 'I' else 'P' end, left(r::text, 120)));
  reset role; select points into b1 from public.customers where phone = '79997001';
  select count(*) into n from public.allowance_holds where tx_id = tx and status = 'held'; set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('C10 balance: −500 redeemed (+ reward per engine rules)', case when b1 < b0 and b1 >= b0 - 500 then 'P' else 'F' end, b0::text || ' → ' || b1::text));
  t := t || jsonb_build_array(jsonb_build_array('M09 allowance hold settled after confirm', case when n = 0 then 'P' else 'F' end, n::text));

  -- =================================================================== EMPLOYEE (as anon)
  r := public.merchant_staff_save_v2(p_session => m1, p_id => null, p_name => 'موظف اختبار', p_phone => '79997021', p_pin => '5555', p_perms => array['sell'], p_active => true);
  stf := r->'staff'->>'id';
  t := t || jsonb_build_array(jsonb_build_array('E01 owner creates employee (sell only)', case when stf is not null then 'P' else 'F' end, left(r::text, 120)));
  begin r := public.merchant_staff_save_v2(p_session => m2, p_id => stf::uuid, p_name => 'x', p_phone => '79997021', p_pin => '5555', p_perms => array['sell','payments'], p_active => true);
        e := coalesce(r->>'error', r->>'reason', case when coalesce((r->>'ok')::boolean, false) then 'NO_ERROR' else r::text end); exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S08 another shop cannot edit this employee', case when e <> 'NO_ERROR' then 'P' else 'F' end, left(e, 120)));
  r := public.staff_login(p_phone => '79997021', p_pin => '5555', p_device => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('E02 old phone+PIN staff login refused', case when r->>'reason' = 'device_required' then 'P' else 'F' end, left(r::text, 120)));
  r := public.merchant_staff_credentials_v2(p_session => m1, p_staff_id => stf::uuid, p_email => 'tp-it-staff@test.example', p_password => 'Passw0rdTpIt9');
  r := public.staff_first_login_v2(p_email => 'tp-it-staff@test.example', p_password => 'Passw0rdTpIt9', p_device => dev, p_label => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('E03 first login on new device → owner verification', case when r->>'step' = 'verify' then 'P' else 'F' end, left(r::text, 120)));
  x := public.merchant_staff_devices_v2(m1);
  begin r := public.merchant_staff_device_decide_v2(p_session => m2, p_device_id => (x->'devices'->0->>'id')::uuid, p_approve => true);
        e := coalesce(r->>'error', r->>'reason', case when coalesce((r->>'ok')::boolean, false) then 'NO_ERROR' else r::text end); exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S09 another shop cannot approve this device', case when e <> 'NO_ERROR' then 'P' else 'F' end, left(e, 120)));
  perform public.merchant_staff_device_decide_v2(p_session => m1, p_device_id => (x->'devices'->0->>'id')::uuid, p_approve => true);
  r := public.staff_set_pin6_v2(p_email => 'tp-it-staff@test.example', p_password => 'Passw0rdTpIt9', p_device => dev, p_pin6 => '482915');
  st := public.staff_pin_login_v2(p_phone => '79997021', p_pin6 => '482915', p_device => dev)->>'session';
  t := t || jsonb_build_array(jsonb_build_array('E04 6-digit PIN login on the approved device', case when st is not null then 'P' else 'F' end, null));
  r := public.staff_pin_login_v2(p_phone => '79997021', p_pin6 => '482915', p_device => dev2);
  t := t || jsonb_build_array(jsonb_build_array('E05 same PIN on an unapproved device refused', case when st is not null and r->>'session' is null then 'P' else 'F' end, left(r::text, 120)));
  begin x := to_jsonb(public.merchant_me_v2(st)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('E06 employee session can reach selling (merchant_me_v2)', case when e = 'NO_ERROR' then 'P' else 'F' end, e));
  begin x := to_jsonb(public.merchant_staff_list_v2(st)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('E07 employee cannot manage staff', case when e like 'TP_%' then 'P' else 'F' end, e));
  begin x := to_jsonb(public.merchant_payment_requests_v2(st)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('E08 employee without «payments» cannot see payment requests', case when e like 'TP_%' then 'P' else 'F' end, e));
  begin x := to_jsonb(public.admin_list_customers_v2(st)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('E09 employee session refused on admin functions', case when e like 'TP_%' then 'P' else 'F' end, e));
  -- employee sells within the same branch (second purchase, no redeem)
  q := public.customer_qr_issue(c2); s := public.merchant_scan_code(st, q->>'qr');
  r := public.merchant_create_tx_v2(st, (s->>'code_id')::uuid, 10, false, null, '[]'::jsonb, 'tp-it-idem-2'); tx2 := (r->'tx'->>'id')::uuid;
  t := t || jsonb_build_array(jsonb_build_array('E10 employee creates a sale for the branch', case when tx2 is not null then 'P' else 'F' end, left(r::text, 120)));
  reset role; select count(*) into n from public.pos_transactions where id = tx2 and merchant_id = m1_id; set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('E11 the sale belongs to the employee''s branch', case when n = 1 then 'P' else 'F' end, n::text));

  -- =================================================================== ADMIN actions on the purchase
  begin x := to_jsonb(public.admin_list_customers_v2(c1)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S10 customer session refused on admin functions', case when e like 'TP_%' then 'P' else 'F' end, e));
  begin x := to_jsonb(public.admin_list_customers_v2(m1)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S11 merchant session refused on admin functions', case when e like 'TP_%' then 'P' else 'F' end, e));
  begin r := public.admin_points_adjust_v2(c1, '79997001', 100000, 'tp-it'); e := coalesce(r->>'error', 'NO_ERROR'); exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S12 customer cannot credit own points via admin function', case when e <> 'NO_ERROR' then 'P' else 'F' end, e));
  begin r := public.admin_points_adjust_v2(a2, '79997001', 1000, 'tp-it'); v := coalesce(r->>'error', r->>'reason', case when coalesce((r->>'ok')::boolean, false) then 'allowed' else r::text end); exception when others then v := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('A06 non-primary admin manual points adjustment (observation)', 'I', left(v, 120)));
  r := public.admin_tx_refund_v2(a1, tx, 1, 'tp-it', true, false);
  t := t || jsonb_build_array(jsonb_build_array('A07 refund needs both parties'' agreement', case when r->>'error' = 'agreement_required' then 'P' else 'F' end, left(r::text, 120)));
  reset role; select points into b1 from public.customers where phone = '79997001'; set local role anon;
  r := public.admin_tx_refund_v2(a1, tx, 0.5, 'tp-it', true, true);
  reset role; select points into b2 from public.customers where phone = '79997001'; set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('A08 50% refund reverses points proportionally (separate correction entries)', case when coalesce((r->>'ok')::boolean, false) and b2 <> b1 then 'P' else 'F' end, b1::text || ' → ' || b2::text || ' ' || left(r::text, 100)));
  reset role; select count(*) into n from public.pos_transactions where id = tx; set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('A09 the original tx is kept (not deleted)', case when n = 1 then 'P' else 'F' end, n::text));
  begin x := to_jsonb(public.admin_audit_log_v2(p_session => a1, p_limit => 50)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('A10 audit log readable by admin and records this run''s admin actions', case when e = 'NO_ERROR' and x::text ~* 'refund|allowance' then 'P' else 'F' end, left(e, 80)));

  -- =================================================================== SESSIONS
  begin x := to_jsonb(public.customer_points_v2('forged-' || md5(random()::text))); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S13 forged session token refused', case when e like 'TP_SESSION%' then 'P' else 'F' end, e));
  begin x := to_jsonb(public.customer_points_v2(null)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S14 missing session refused', case when e like 'TP_%' then 'P' else 'F' end, e));
  begin x := to_jsonb(public.customer_points_v2(m1)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S15 merchant session refused on customer functions', case when e like 'TP_%' then 'P' else 'F' end, e));
  perform public.session_logout(c2);
  begin x := to_jsonb(public.customer_points_v2(c2)); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S16 session dead after logout', case when e like 'TP_SESSION%' then 'P' else 'F' end, e));

  -- =================================================================== DIRECT DATA ACCESS (bypassing the app)
  begin update public.customers set points = points + 100000 where phone = '79997001'; get diagnostics n = row_count; e := 'rows=' || n; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S17 public key cannot update balances directly', case when e = 'rows=0' or e like '%permission denied%' then 'P' else 'F' end, e));
  begin select count(*) into n from public.customers; e := 'rows=' || n; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S18 public key cannot read the customers table', case when e = 'rows=0' or e like '%permission denied%' then 'P' else 'F' end, e));
  begin insert into public.point_batches(customer_phone, kind, initial, remaining, expires_at) values ('79997001', 'earn', 100000, 100000, now() + interval '90 days'); e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S19 public key cannot write ledger rows', case when e ~* 'permission denied|row-level security' then 'P' else 'F' end, left(e, 100)));
  reset role;
  begin update public.customers set points = points + 100000 where phone = '79997001'; e := 'NO_ERROR'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('S20 engine_strict: balance cannot change outside the ledger even for privileged SQL', case when e <> 'NO_ERROR' then 'P' else 'F' end, left(e, 100)));
  select string_agg(p.oid::regprocedure::text, ', ') into v from pg_proc p where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'EXECUTE')
     and p.proname in ('customer_set_pin','customer_reset_pin','decide_transaction','create_transaction','admin_list_customers','admin_list_merchants','admin_grant_customer_gift',
                       'admin_topup_merchant','merchant_wallet','customer_create_request','admin_wipe_all_data','admin_set_customer_status','customer_profile');
  t := t || jsonb_build_array(jsonb_build_array('S21 legacy phone/id functions closed to the public key', case when v is null then 'P' else 'F' end, v));
  set local role anon;

  -- =================================================================== merchant_set_logo (phone + PIN, kept open by design)
  reset role; select logo_url into logo0 from public.merchants where id = m1_id; set local role anon;
  r := public.merchant_set_logo('79997012', '9999', 'https://example.test/x.png');
  t := t || jsonb_build_array(jsonb_build_array('L01 merchant_set_logo wrong PIN refused', case when r->>'reason' = 'wrong_pin' then 'P' else 'F' end, left(r::text, 80)));
  r := public.merchant_set_logo('79997012', '4827', 'https://example.test/m2.png');
  reset role; select count(*) into n from public.merchants where id = m2_id and logo_url = 'https://example.test/m2.png';
  select count(*) into i from public.merchants where id = m1_id and logo_url is not distinct from logo0; set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('L02 right PIN changes only that shop''s logo', case when n = 1 and i = 1 then 'P' else 'F' end, n || '/' || i));
  for i in 1..5 loop perform public.merchant_set_logo('79997013', '0000', 'https://example.test/y.png'); end loop;
  r := public.merchant_set_logo('79997013', '4828', 'https://example.test/m3.png');
  t := t || jsonb_build_array(jsonb_build_array('L03 5 wrong PINs lock merchant_set_logo (even with the right PIN)', case when r->>'reason' = 'locked' then 'P' else 'F' end, left(r::text, 80)));
  r := public.merchant_login(p_phone => '79997013', p_pin => '4828', p_device => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('L04 does the set_logo lock also block merchant_login? (observation)', 'I', case when r->>'session' is null then 'yes, login blocked: ' || left(coalesce(r->>'reason', r->>'error', ''), 40) else 'NO — separate counters' end));
  reset role; perform public._rl_reset('merchant:79997013'); set local role anon;
  for i in 1..5 loop perform public.merchant_login(p_phone => '79997013', p_pin => '0000', p_device => 'tp-it'); end loop;
  r := public.merchant_set_logo('79997013', '4828', 'https://example.test/m3.png');
  t := t || jsonb_build_array(jsonb_build_array('L05 does a merchant_login lock also block merchant_set_logo? (observation)', 'I', case when coalesce(r->>'reason', '') = 'locked' then 'yes, blocked' else 'NO — set_logo still accepts the PIN: ' || left(r::text, 40) end));
  r := public.merchant_set_logo('79997012', '4827', 'javascript:alert(1)');
  reset role; select logo_url into v from public.merchants where id = m2_id; set local role anon;
  t := t || jsonb_build_array(jsonb_build_array('L06 non-http(s) logo URL rejected server-side (observation)', 'I', case when v = 'javascript:alert(1)' then 'NO — stored as given' else 'rejected' end));

  -- =================================================================== admin_reset_merchant_pin (admin id + admin PIN, kept open by design)
  r := public.admin_reset_merchant_pin(a2_id, '7392', m2_id, '6153');
  t := t || jsonb_build_array(jsonb_build_array('R01 non-primary admin cannot reset a merchant PIN', case when coalesce((r->>'ok')::boolean, false) then 'F' else 'P' end, left(r::text, 100)));
  r := public.admin_reset_merchant_pin(a1_id, '0000', m2_id, '6153');
  t := t || jsonb_build_array(jsonb_build_array('R02 wrong admin PIN refused', case when coalesce((r->>'ok')::boolean, false) then 'F' else 'P' end, left(r::text, 100)));
  r := public.admin_reset_merchant_pin(gen_random_uuid(), '7391', m2_id, '6153');
  t := t || jsonb_build_array(jsonb_build_array('R03 unknown admin id refused', case when coalesce((r->>'ok')::boolean, false) then 'F' else 'P' end, left(r::text, 100)));
  r := public.admin_reset_merchant_pin(a1_id, '7391', m2_id, '6153');
  t := t || jsonb_build_array(jsonb_build_array('R04 primary admin with right PIN resets the (synthetic) merchant PIN', case when coalesce((r->>'ok')::boolean, false) then 'P' else 'F' end, left(r::text, 100)));
  r := public.merchant_login(p_phone => '79997012', p_pin => '4827', p_device => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('R05 old merchant PIN no longer works', case when r->>'session' is null then 'P' else 'F' end, null));
  r := public.merchant_login(p_phone => '79997012', p_pin => '6153', p_device => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('R06 new merchant PIN works', case when r->>'session' is not null then 'P' else 'F' end, null));
  begin x := to_jsonb(public.merchant_me_v2(m2)); e := 'still valid'; exception when others then e := sqlerrm; end;
  t := t || jsonb_build_array(jsonb_build_array('R07 sessions opened with the old PIN end after the reset (observation)', 'I', left(e, 80)));
  r := public.admin_reset_merchant_pin(a1_id, '7391', m2_id, '1111');
  t := t || jsonb_build_array(jsonb_build_array('R08 trivial new PIN (1111) refused (observation)', 'I', case when coalesce((r->>'ok')::boolean, false) then 'NO — accepted' else 'refused' end));
  for i in 1..5 loop perform public.admin_reset_merchant_pin(a1_id, '0000', m2_id, '6154'); end loop;
  r := public.admin_reset_merchant_pin(a1_id, '7391', m2_id, '6154');
  t := t || jsonb_build_array(jsonb_build_array('R09 5 wrong admin PINs lock the reset (even with the right PIN)', case when r->>'reason' = 'locked' then 'P' else 'F' end, left(r::text, 80)));
  r := public.admin_login(p_username => 'tp_it_a1', p_pin => '7391', p_device => 'tp-it');
  t := t || jsonb_build_array(jsonb_build_array('R10 does that lock also block the admin''s login? (observation)', 'I', case when r->>'session' is null then 'yes: ' || left(coalesce(r->>'reason', r->>'error', ''), 40) else 'NO — login still works' end));
  reset role;

  raise exception 'TP_IT_RESULT %', t::text;
end
$tp_it$;
