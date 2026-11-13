-- Tripoli Points — C-1 tests (synthetic rows, single transaction, ROLLBACK at the end; local/Staging only).
begin;
do $t$
declare pass int := 0; fail int := 0; msg text := ''; mid uuid := gen_random_uuid(); r jsonb; tx uuid; ok boolean; v text;
begin
  insert into public.merchants(id, name, phone, status, pct, tier, redeem_pct) values (mid, 'C1 shop', '76111222', 'active', 5, 'small', 5);
  insert into public.topups(merchant_id, amount, source) values (mid, 100, 'test');
  insert into public.app_settings(key, value) values ('rate_pts_per_usd', 100), ('redeem_cap_pct', 70) on conflict (key) do nothing;
  -- A: gift expired, nothing else (the 8 Production customers)        B: gift still valid
  -- C: 3200 = 3000 expired gift + 200 earned                           D: 669 earned, no gift (customer c2)
  insert into public.customers(phone, name, status, points, welcome_remain, welcome_exp) values
    ('79990001','A','active',3000,3000, now() - interval '1 day'),
    ('79990002','B','active',3000,3000, now() + interval '3 days'),
    ('79990003','C','active',3200,3000, now() - interval '1 day'),
    ('79990004','D','active', 669,   0, now() - interval '20 days');
  -- invoice 100 dollars at a small shop: invoice limit 5% = 500 pts, tier 1000, legacy customer cap 70% of spendable
  for v in select unnest(array['79990001:0','79990002:500','79990003:140','79990004:468']) loop
    r := public.create_transaction(mid, split_part(v,':',1), 100, true, null, '[]'::jsonb);
    if (r->>'redeem_pts')::numeric = split_part(v,':',2)::numeric then pass := pass + 1;
    else fail := fail + 1; msg := msg || format(' [%s expected %s got %s]', split_part(v,':',1), split_part(v,':',2), r->>'redeem_pts'); end if;
    update public.pos_transactions set status = 'CANCELLED' where customer_phone = split_part(v,':',1) and status = 'PENDING';
  end loop;
  -- balances untouched by C-1 itself
  if (select string_agg(points::text, ',' order by phone) from public.customers where phone like '7999000_') = '3000,3000,3200,669'
     and (select string_agg(welcome_remain::text, ',' order by phone) from public.customers where phone like '7999000_') = '3000,3000,3000,0'
  then pass := pass + 1; else fail := fail + 1; msg := msg || ' [a balance or gift changed]'; end if;
  -- gift expires inside the 5-minute confirmation window -> confirmation refused, nothing changes
  r := public.create_transaction(mid, '79990002', 100, true, null, '[]'::jsonb); tx := (r->>'tx_id')::uuid;
  update public.customers set welcome_exp = now() - interval '1 second' where phone = '79990002';
  begin r := public.decide_transaction(tx, true); fail := fail + 1; msg := msg || ' [expired gift spent at confirmation]';
  exception when others then
    if sqlerrm like 'TP_C1%' then pass := pass + 1; else fail := fail + 1; msg := msg || ' [unexpected error ' || sqlerrm || ']'; end if; end;
  if (select status from public.pos_transactions where id = tx) = 'PENDING' and (select points from public.customers where phone = '79990002') = 3000
  then pass := pass + 1; else fail := fail + 1; msg := msg || ' [refused confirmation changed data]'; end if;
  update public.pos_transactions set status = 'CANCELLED' where id = tx;
  -- normal purchase without redemption still confirms and credits once
  r := public.create_transaction(mid, '79990001', 20, false, null, '[]'::jsonb); tx := (r->>'tx_id')::uuid;
  r := public.decide_transaction(tx, true);
  if (r->>'ok')::boolean and (select points from public.customers where phone = '79990001') = 3100 then pass := pass + 1;
  else fail := fail + 1; msg := msg || ' [earning-only purchase broken: ' || coalesce(r::text,'') || ']'; end if;
  -- a valid-gift redemption still confirms
  update public.customers set welcome_exp = now() + interval '3 days' where phone = '79990002';
  r := public.create_transaction(mid, '79990002', 100, true, null, '[]'::jsonb); tx := (r->>'tx_id')::uuid;
  r := public.decide_transaction(tx, true);
  if (r->>'ok')::boolean and (select points from public.customers where phone = '79990002') = 3000 - 500 + (select earn from public.pos_transactions where id = tx)
  then pass := pass + 1; else fail := fail + 1; msg := msg || ' [valid gift redemption broken]'; end if;
  raise exception 'C1_TESTS passed=% failed=% %', pass, fail, msg using errcode = 'P0001';
end $t$;
rollback;
