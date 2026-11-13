-- BATCH 3f BACKUP / RESTORE TESTS — LOCAL DISPOSABLE DATABASE ONLY (they run a real wipe inside the transaction).
-- Never run on Staging or Production. Everything ends in ROLLBACK.
begin;
set local client_min_messages = warning;
do $$ begin
  if current_database() !~ '^(b3f|bk)_' then raise exception 'LOCAL ONLY: run on a disposable database named b3f_* / bk_*'; end if;
end $$;
create temp table _t (n serial primary key, name text, ok boolean, detail text) on commit drop;
create temp table _ctx (k text primary key, v text) on commit drop;
create temp table _sum (tname text primary key, n bigint, h text) on commit drop;
create function pg_temp.ok(p_name text, p_cond boolean, p_detail text default null) returns void language sql as $$
  insert into _t(name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail) $$;
create function pg_temp.set(p_k text, p_v text) returns void language sql as $$
  insert into _ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.get(p_k text) returns text language sql as $$ select v from _ctx where k = p_k $$;
create function pg_temp.sums(p_into boolean) returns text language plpgsql as $$
declare t regclass; vn bigint; vh text; bad text;
begin
  foreach t in array public._tp_wipe_scope() loop
    continue when t::text in ('app_sessions','purchase_codes');
    execute format('select count(*), md5(coalesce(string_agg(r::text, chr(10) order by r::text), '''')) from %s r', t) into vn, vh;
    if p_into then insert into _sum values (t::text, vn, vh) on conflict (tname) do update set n = excluded.n, h = excluded.h;
    elsif not exists (select 1 from _sum s where s.tname = t::text and s.n = vn and s.h = vh) then bad := concat_ws(', ', bad, t::text); end if;
  end loop;
  return bad;
end $$;

-- fixtures: a branch with a subscription grant, staff, a confirmed and a pending purchase, customers with ledger
insert into public.customers(phone, pin_hash, name, status, points) values
  ('79998201', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0),
  ('79998202', extensions.crypt('1111', extensions.gen_salt('bf', 4)), 'زبون جديد', 'active', 0);
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
  ('00000000-0000-4000-8000-0000000b3f01', 'فرع النسخ', '79998211', extensions.crypt('2222', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 5, 'active');
insert into public.topups(merchant_id, amount, source) values ('00000000-0000-4000-8000-0000000b3f01', 100, 'test');
insert into public.admin_users(id, username, pin_hash, is_primary) values
  ('00000000-0000-4000-8000-0000000b3fa1', 'tp_test_b3f_a1', extensions.crypt('3333', extensions.gen_salt('bf', 4)), true);
do $$
declare a text; m text; c1 text; c2 text; r jsonb; q jsonb; s jsonb; tx uuid;
begin
  a := public.admin_login('tp_test_b3f_a1', '3333')->>'session'; m := public.merchant_login('79998211', '2222')->>'session';
  c1 := public.customer_login('79998201', '1111')->>'session'; c2 := public.customer_login('79998202', '1111')->>'session';
  perform public.admin_pay_settings_v2(a, '70 000 000', 'test');
  perform public.admin_plan_save_v2(a, 'bk-plan', 'خطة نسخ', 'medium', 20, 2000, 1, true);
  r := public.merchant_payment_request_v2(m, 'subscription', 'bk-plan', 'BK-REF-1', null, 'idem-bk-0001');
  perform public.admin_payment_decide_v2(a, (r->'request'->>'id')::uuid, true, 20, 'BK-REF-1');
  perform public.merchant_staff_save_v2(m, null, 'موظف', '79998221', '5555', array['sell']);
  perform public.admin_points_adjust_v2(a, '79998201', 3000, 'رصيد اختبار');
  perform public.admin_points_adjust_v2(a, '79998202', 1000, 'رصيد اختبار');
  q := public.customer_qr_issue(c1); s := public.merchant_scan_code(m, q->>'qr');
  r := public.merchant_create_tx_v2(m, (s->>'code_id')::uuid, 100, true, null, '[]'::jsonb, 'idem-bk-0002'); tx := (r->'tx'->>'id')::uuid;
  perform public.customer_decide_tx_v2(c1, tx, true, (select detail_hash from public.pos_transactions where id = tx));
  q := public.customer_qr_issue(c2); s := public.merchant_scan_code(m, q->>'qr');
  r := public.merchant_create_tx_v2(m, (s->>'code_id')::uuid, 50, true, null, '[]'::jsonb, 'idem-bk-0003');   -- left pending (holds)
  perform pg_temp.ok('fixtures: ledger, grants, holds, staff, payment, subscription present',
    (select count(*) from public.point_batches) >= 3 and exists (select 1 from public.allowance_holds where status = 'held')
    and exists (select 1 from public.merchant_staff) and exists (select 1 from public.merchant_subscriptions) and exists (select 1 from public.payment_requests where status = 'approved'));
  perform pg_temp.set('a', a);
end $$;

do $$
declare t regclass; names text;
begin
  names := (select string_agg(x::text, ',') from unnest(public._tp_wipe_scope()) x);
  perform pg_temp.ok('coverage: wipe scope includes every batch 3 table emptied by the wipe',
    names ~ 'point_batches' and names ~ 'point_movements' and names ~ 'allowance_grants' and names ~ 'allowance_holds' and names ~ 'allowance_movements'
    and names ~ 'merchant_subscriptions' and names ~ 'payment_requests' and names ~ 'merchant_staff' and names ~ 'pos_transactions', names);
  perform pg_temp.ok('coverage: tables outside the scope are not emptied by the wipe (audit_log, tx_reports, tx_events, plans, packages)',
    not (array['public.audit_log'::regclass, 'public.tx_reports'::regclass, 'public.tx_events'::regclass, 'public.plans'::regclass,
             'public.packages'::regclass] && public._tp_wipe_scope()));
end $$;
select pg_temp.sums(true);

-- 1. a copy without wipe
do $$
declare r jsonb;
begin
  r := public.admin_backup_now_v2(pg_temp.get('a'));
  perform pg_temp.ok('backup now: copy made without wiping, audited', (r->>'ok')::boolean and pg_temp.sums(false) is null
    and exists (select 1 from public.audit_log where action = 'wipe_snapshot' and target_id = r->>'stamp'), r::text);
  perform pg_temp.ok('backup now: a second copy within 10 minutes is refused', public.admin_backup_now_v2(pg_temp.get('a'))->>'error' = 'too_soon');
  perform pg_temp.ok('wipe is still disabled', public._setting('admin_wipe_enabled', 0) = 0
    and public.admin_wipe_all_data_v2(pg_temp.get('a'), '3333', 'امسح كل البيانات')->>'error' = 'wipe_disabled');
end $$;

-- 2. wipe (only inside this rolled-back local test) and restore
do $$
declare r jsonb; x jsonb;
begin
  update public.app_settings set value = 1 where key = 'admin_wipe_enabled';
  r := public.admin_wipe_all_data_v2(pg_temp.get('a'), '3333', 'امسح كل البيانات');
  perform pg_temp.set('w1', r->>'snapshot');
  perform pg_temp.ok('wipe (test only): emptied, copy stamped, switch back to 0', (r->>'ok')::boolean and not exists (select 1 from public.point_batches)
    and not exists (select 1 from public.allowance_grants) and not exists (select 1 from public.customers) and public._setting('admin_wipe_enabled', 0) = 0, r::text);
  x := public._tp_wipe_restore(pg_temp.get('w1'));
  perform pg_temp.ok('restore: every covered table identical to before (rows + checksum)', pg_temp.sums(false) is null, coalesce(pg_temp.sums(false), 'ok'));
  perform pg_temp.ok('restore: ledger reconciled (no opening batches needed), audited',
    exists (select 1 from jsonb_array_elements(x->'tables') e where (e->'reconcile'->>'reconciled')::boolean and (e->'reconcile'->>'opening_batches')::int = 0)
    and exists (select 1 from public.audit_log where action = 'wipe_restore' and target_id = pg_temp.get('w1')), x::text);
  perform pg_temp.ok('restore: balances = ledger for every customer',
    not exists (select 1 from public.customers c where coalesce(c.points,0) <> (select coalesce(sum(remaining),0) from public.point_batches b where b.customer_phone = c.phone)));
  perform pg_temp.ok('restore: no duplicated credits (batches / movements / grants counted once)',
    (select count(*) from public.point_batches) = (select n from _sum where tname = 'point_batches')
    and (select count(*) from public.allowance_movements) = (select n from _sum where tname = 'allowance_movements'));
  perform pg_temp.ok('restore: foreign keys valid (orphans none)',
    not exists (select 1 from public.point_movements m left join public.point_batches b on b.id = m.batch_id where m.batch_id is not null and b.id is null)
    and not exists (select 1 from public.allowance_grants g left join public.merchants mm on mm.id = g.merchant_id where mm.id is null)
    and not exists (select 1 from public.pos_transactions t left join public.customers c on c.phone = t.customer_phone where c.phone is null));
  perform pg_temp.ok('restore: the pending purchase still holds its reservation', exists (select 1 from public.allowance_holds h join public.pos_transactions t on t.id = h.tx_id where h.status = 'held' and t.status = 'PENDING'));
  begin perform public._tp_wipe_restore(pg_temp.get('w1')); perform pg_temp.ok('restore twice refused', false);
  exception when others then perform pg_temp.ok('restore twice refused', sqlerrm like 'TP_RESTORE:%already restored%', sqlerrm); end;
  perform pg_temp.ok('wipe still disabled after restore', public._setting('admin_wipe_enabled', 0) = 0);
end $$;

-- 3. a changed copy is refused and nothing is restored (no partial state)
do $$
declare r jsonb; a text;
begin
  a := public.admin_login('tp_test_b3f_a1', '3333')->>'session';
  update public.app_settings set value = 1 where key = 'admin_wipe_enabled';
  r := public.admin_wipe_all_data_v2(a, '3333', 'امسح كل البيانات'); perform pg_temp.set('w2', r->>'snapshot');
  execute format('update tp_backup.%I set remaining = remaining + 1', pg_temp.get('w2') || '__point_batches');
  begin perform public._tp_wipe_restore(pg_temp.get('w2')); perform pg_temp.ok('tampered copy refused', false);
  exception when others then perform pg_temp.ok('tampered copy refused, nothing restored', sqlerrm like 'TP_RESTORE:%changed after it was made%'
      and not exists (select 1 from public.customers) and not exists (select 1 from public.point_batches), sqlerrm); end;
end $$;

-- 5. an OLD copy (made before batch 3: customers with points, no ledger) restores with opening batches
do $$
declare a text; r jsonb; x jsonb; st text;
begin
  -- rebuild a minimal pre-ledger state from the tampered round: restore is impossible, so start from empty tables
  perform set_config('tp.ledger', '1', true);
  insert into public.customers(phone, pin_hash, name, status, points, welcome_remain, welcome_exp)
  values ('79998231', 'x', 'زبون قديم', 'active', 3500, 3000, now() + interval '5 days');
  delete from public.point_movements where customer_phone = '79998231';
  delete from public.point_batches where customer_phone = '79998231';                 -- simulate «no ledger» in the copy
  perform set_config('tp.ledger', '0', true);
  st := public._tp_wipe_snapshot('test:old-copy', null);
  perform set_config('tp.ledger', '1', true);
  truncate table public.merchants, public.customers cascade;                          -- local test only
  perform set_config('tp.ledger', '0', true);
  x := public._tp_wipe_restore(st);
  perform pg_temp.ok('old copy: customer restored and given opening batches (3000 welcome with its expiry + 500 legacy)',
    (select sum(remaining) from public.point_batches where customer_phone = '79998231') = 3500
    and exists (select 1 from public.point_batches where customer_phone = '79998231' and kind = 'welcome' and remaining = 3000 and expires_at > now() + interval '4 days')
    and exists (select 1 from public.point_batches where customer_phone = '79998231' and kind = 'legacy' and remaining = 500), x::text);
end $$;

-- 4. a copy whose ledger does not add up is refused by the reconcile step, and the whole restore is undone
do $$
declare st text; x jsonb;
begin
  perform set_config('tp.ledger', '1', true);
  update public.point_batches set remaining = remaining - 1 where customer_phone = '79998231' and kind = 'legacy';
  update public.customers set points = points - 1 where phone = '79998231';     -- cached total follows, movements do not
  perform set_config('tp.ledger', '0', true);
  st := public._tp_wipe_snapshot('test:broken-copy', null);
  truncate table public.merchants, public.customers cascade;                    -- local test only
  begin x := public._tp_wipe_restore(st); perform pg_temp.ok('inconsistent copy refused', false, x::text);
  exception when others then perform pg_temp.ok('inconsistent copy: refused by reconcile, nothing restored (no partial state)',
      sqlerrm like 'TP_RESTORE_LEDGER%' and not exists (select 1 from public.customers) and not exists (select 1 from public.point_batches), sqlerrm); end;
end $$;

do $$ begin
  perform pg_temp.ok('final: wipe disabled', public._setting('admin_wipe_enabled', 0) = 0);
  perform pg_temp.ok('final: owner-only backup functions not reachable by anon',
    not has_function_privilege('anon', 'public._tp_wipe_restore(text)', 'execute') and not has_function_privilege('anon', 'public._tp_wipe_snapshot(text,uuid)', 'execute'));
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
