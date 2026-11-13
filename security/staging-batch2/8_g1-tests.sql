-- Tripoli Points — G-1 tests (synthetic rows in one transaction, ROLLBACK at the end). Staging / local only.
begin;
do $t$
declare pass int := 0; fail int := 0; msg text := ''; r jsonb; b_old text; d_old text;
begin
  b_old := (select value from public.app_text_settings where key = 'welcome_bonus');
  d_old := (select value from public.app_text_settings where key = 'welcome_days');
  update public.app_text_settings set value = '3000' where key = 'welcome_bonus';
  update public.app_text_settings set value = '7' where key = 'welcome_days';
  execute 'insert ' || 'into public.app_text_settings(key, value) values (''welcome_bonus'', ''3000''), (''welcome_days'', ''7'') on conflict (key) do nothing';
  -- 1. the browser asks for a huge gift and a long validity: the server gives the Admin setting
  r := public.customer_register('79990071', '1234', 'g1', 1000000000, 999, 'v1');
  if (select points = 3000 and welcome_remain = 3000 and welcome_exp between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour'
      from public.customers where phone = '79990071') then pass := pass + 1; else fail := fail + 1; msg := msg || ' [browser value trusted]'; end if;
  -- 2. the gift note states the server amount and validity
  if exists (select 1 from public.customer_notes where customer_phone = '79990071' and title like '%3000%' and body like '%7%') then pass := pass + 1;
  else fail := fail + 1; msg := msg || ' [gift note missing]'; end if;
  -- 3. the same phone cannot register again (no second gift), and nothing changes
  begin r := public.customer_register('79990071', '1234', 'g1', 3000, 7, 'v1'); fail := fail + 1; msg := msg || ' [second registration accepted]';
  exception when others then pass := pass + 1; end;
  if (select count(*) from public.customer_notes where customer_phone = '79990071' and title like 'هدية الترحيب%') = 1
     and (select points from public.customers where phone = '79990071') = 3000 then pass := pass + 1; else fail := fail + 1; msg := msg || ' [duplicate gift]'; end if;
  -- 4. the Admin changes the gift: only NEW accounts get the new value; existing gifts keep their original amount and validity
  update public.app_text_settings set value = '5000' where key = 'welcome_bonus';
  update public.app_text_settings set value = '14' where key = 'welcome_days';
  r := public.customer_register('79990072', '1234', 'g2', 0, 0, 'v1');
  if (select points from public.customers where phone = '79990072') = 5000 and (select welcome_exp > now() + interval '13 days' from public.customers where phone = '79990072')
     and (select points = 3000 and welcome_exp < now() + interval '8 days' from public.customers where phone = '79990071') then pass := pass + 1;
  else fail := fail + 1; msg := msg || ' [settings change not applied to new / changed existing]'; end if;
  -- 5. gift switched off by the Admin (0): no gift, no gift note
  update public.app_text_settings set value = '0' where key = 'welcome_bonus';
  r := public.customer_register('79990073', '1234', 'g3', 3000, 7, 'v1');
  if (select points from public.customers where phone = '79990073') = 0 and not exists (select 1 from public.customer_notes where customer_phone = '79990073' and title like 'هدية الترحيب%')
  then pass := pass + 1; else fail := fail + 1; msg := msg || ' [gift given while switched off]'; end if;
  -- 6. setting missing or not a number: no gift (never the browser value)
  update public.app_text_settings set value = 'not-a-number' where key = 'welcome_bonus';   -- invalid setting (no DELETE)
  r := public.customer_register('79990074', '1234', 'g4', 3000, 7, 'v1');
  if (select points from public.customers where phone = '79990074') = 0 then pass := pass + 1; else fail := fail + 1; msg := msg || ' [invalid setting fell back to browser]'; end if;
  -- 7. the public key may still register (the app's normal path)
  update public.app_text_settings set value = '3000' where key = 'welcome_bonus';
  set local role anon; r := public.customer_register('79990075', '1234', 'g5', 99999, 99, 'v1'); reset role;
  if (select points from public.customers where phone = '79990075') = 3000 then pass := pass + 1; else fail := fail + 1; msg := msg || ' [anon registration path]'; end if;
  raise exception 'G1_TESTS passed=% failed=% %', pass, fail, msg using errcode = 'P0001';
end $t$;
rollback;
