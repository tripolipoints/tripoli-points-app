-- Tripoli Points — HOTFIX H1 behavioural tests. Creates synthetic rows inside ONE transaction and ROLLS BACK at the end:
-- nothing persists. For local replicas and Staging only (never Production: it would briefly lock tables).
-- Result: the final notice  H1_TESTS passed=N failed=M  (and a list of failures).
begin;
do $t$
declare
  pass int := 0; fail int := 0; msg text := '';
  mid uuid := gen_random_uuid(); oid1 uuid; r jsonb; ok boolean;
  ph text := '96100000123';
  procedure_calls text[][] := array[
    ['admin_topup_merchant',          format('select public.admin_topup_merchant(%L::uuid, 5, %L)', mid, 'test')],
    ['admin_resolve_topup_order',     'select public.admin_resolve_topup_order(gen_random_uuid(), true)'],
    ['admin_mark_order_collected',    'select public.admin_mark_order_collected(gen_random_uuid())'],
    ['admin_delete_topup_order_only', 'select public.admin_delete_topup_order_only(gen_random_uuid())'],
    ['whish_confirm_payment',         'select public.whish_confirm_payment(gen_random_uuid(), ''failed'', null, null)'],
    ['whish_set_collect_url',         'select public.whish_set_collect_url(gen_random_uuid(), ''https://x'', null)'],
    ['customer_reset_pin',            format('select public.customer_reset_pin(%L, %L)', ph, '9999')],
    ['customer_set_pin',              format('select public.customer_set_pin(%L, %L, %L)', ph, '9999', 'x')],
    ['admin_grant_customer_gift',     format('select public.admin_grant_customer_gift(%L, 100000, 7)', ph)],
    ['customer_check_welcome_expiry', format('select public.customer_check_welcome_expiry(%L)', ph)]];
  i int; rl text;
begin
  -- synthetic fixtures
  insert into public.merchants(id, name, phone, status, pct, tier, redeem_pct) values (mid, 'H1 test shop', '96170000999', 'active', 5, 'small', 5);
  insert into public.customers(phone, pin_hash, name, status, points, welcome_remain, welcome_exp)
    values (ph, extensions.crypt('1234', extensions.gen_salt('bf')), 'H1 test', 'active', 3000, 3000, now() - interval '1 day');
  insert into public.topup_orders(merchant_id, amount, points, ref, status, method) values (mid, 5, 500, 'TP-H1TEST', 'REVIEW', 'manual') returning id into oid1;

  -- 1. the public key (anon) and signed-in users (authenticated) are refused on all 10
  foreach rl in array array['anon','authenticated'] loop
    for i in 1 .. array_length(procedure_calls, 1) loop
      begin
        execute format('set local role %I', rl);
        execute procedure_calls[i][2];
        reset role;
        fail := fail + 1; msg := msg || format(' [%s could call %s]', rl, procedure_calls[i][1]);
      exception when insufficient_privilege then
        reset role; pass := pass + 1;
      when others then   -- the call reached the function body: the public key can execute it
        reset role; fail := fail + 1; msg := msg || format(' [%s reached %s]', rl, procedure_calls[i][1]);
      end;
    end loop;
  end loop;

  -- 2. nothing changed by those attempts
  if (select points from public.customers where phone = ph) = 3000 and (select status from public.topup_orders where id = oid1) = 'REVIEW'
     and not exists (select 1 from public.topups where merchant_id = mid)
  then pass := pass + 1; else fail := fail + 1; msg := msg || ' [refused calls changed data]'; end if;

  -- 3. service_role (Whish edge functions): set_collect_url still allowed; confirm_payment closed (callback block)
  if not has_function_privilege('service_role', 'public.whish_set_collect_url(uuid,text,bigint)', 'execute') then
    pass := pass + 1;   -- Staging: Phase 0 already closed the Whish functions to service_role (H1 checks it removes nothing more)
  else
    begin set local role service_role; perform public.whish_set_collect_url(gen_random_uuid(), 'https://x', null); reset role; pass := pass + 1;
    exception when others then reset role; fail := fail + 1; msg := msg || ' [service_role lost whish_set_collect_url: ' || sqlerrm || ']'; end;
  end if;
  begin set local role service_role; perform public.whish_confirm_payment(oid1, 'failed', null, null); reset role;
    fail := fail + 1; msg := msg || ' [service_role can still flip orders via whish_confirm_payment]';
  exception when insufficient_privilege then reset role; pass := pass + 1; end;
  if (select status from public.topup_orders where id = oid1) = 'REVIEW' then pass := pass + 1; else fail := fail + 1; msg := msg || ' [REVIEW order changed]'; end if;

  -- 4. legitimate customer workflow through the public key still works
  set local role anon;
  r := public.customer_verify_pin(ph, '1234');           -- login; internally runs the welcome-expiry rule as owner
  reset role;
  if r is not null then pass := pass + 1; else fail := fail + 1; msg := msg || ' [customer login broken]'; end if;
  if (select welcome_remain from public.customers where phone = ph) = 0 then pass := pass + 1;      -- existing rule still runs internally
  else fail := fail + 1; msg := msg || ' [internal welcome-expiry call broken]'; end if;
  set local role anon; r := public.customer_profile(ph); reset role;
  if r is not null then pass := pass + 1; else fail := fail + 1; msg := msg || ' [customer_profile broken]'; end if;

  -- 5. legitimate merchant workflow through the public key still works
  set local role anon; r := public.merchant_request_manual_topup(mid, 5, 500, null); reset role;
  if coalesce((r->>'ok')::boolean, r is not null) then pass := pass + 1; else fail := fail + 1; msg := msg || ' [merchant manual top-up request broken: ' || r::text || ']'; end if;
  set local role anon; r := public.merchant_wallet(mid); reset role;
  if r ? 'balance' then pass := pass + 1; else fail := fail + 1; msg := msg || ' [merchant_wallet broken]'; end if;

  -- 6. admin: order list still readable through the public key (admin screen keeps working)
  set local role anon; r := public.admin_topup_orders(); reset role;
  if r is not null then pass := pass + 1; else fail := fail + 1; msg := msg || ' [admin order list broken]'; end if;

  -- 7. secure temporary alternative: the owner (SQL editor) can still do every admin money operation
  r := public.admin_resolve_topup_order(oid1, true);
  if (r->>'ok')::boolean and (select status from public.topup_orders where id = oid1) = 'PAID' then pass := pass + 1;
  else fail := fail + 1; msg := msg || ' [owner cannot approve a REVIEW order: ' || r::text || ']'; end if;
  r := public.admin_topup_merchant(mid, 5, 'admin');
  if (r->>'ok')::boolean then pass := pass + 1; else fail := fail + 1; msg := msg || ' [owner cannot top up]'; end if;
  r := public.admin_mark_order_collected(oid1);
  if (r->>'ok')::boolean then pass := pass + 1; else fail := fail + 1; msg := msg || ' [owner cannot mark collected]'; end if;
  perform public.customer_reset_pin(ph, '4321');
  if (select pin_hash = extensions.crypt('4321', pin_hash) from public.customers where phone = ph) then pass := pass + 1;
  else fail := fail + 1; msg := msg || ' [owner cannot reset a PIN]'; end if;

  raise exception 'H1_TESTS passed=% failed=% %', pass, fail, msg using errcode = 'P0001';
end $t$;
rollback;
