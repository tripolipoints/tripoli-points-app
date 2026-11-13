-- =====================================================================================================
-- Tripoli Points — BATCH 3f: backup / restore coverage for the batch 3 data (STAGING ONLY)
-- Findings (inspection of the real schema):
--   * The wipe copy is not a fixed list: _tp_wipe_scope() follows every foreign key that points at merchants /
--     customers, so the batch 3 tables that the wipe empties (point_batches, point_movements, allowance_grants,
--     allowance_holds, allowance_movements, merchant_subscriptions, payment_requests, merchant_staff, plus
--     pos_transactions, purchase_codes, app_sessions …) are already copied, parent-first, and put back with their
--     checksums verified. Tables without such a key (audit_log, tx_events, tx_reports, plans, packages, settings)
--     are not emptied by the wipe, so nothing of theirs is lost.
--   * Real gaps fixed here:
--       1. No ledger check after a restore: a restored state is now reconciled before it is accepted
--          (cached points = ledger total for every customer; every batch = sum of its own movements;
--          every allowance grant = sum of its own movements; held reservations only on pending purchases).
--          Any difference raises, and the whole restore is undone (one transaction).
--       2. Copies made BEFORE batch 3 (no ledger tables in them) restore customers with points but no batches.
--          They now get opening batches (welcome part with its own expiry, the rest as a legacy batch), exactly
--          like the batch 3b migration — so older copies stay usable.
--       3. Neither the copy nor the restore was written to audit_log. Both are now.
--       4. A copy could only be made by wiping. admin_backup_now_v2 makes a copy WITHOUT any wipe
--          (primary admin, audited), and admin_backup_list_v2 lists the copies.
--   * admin_wipe_all_data stays disabled (admin_wipe_enabled = 0 is checked, never changed here).
-- Changes: two phase-0 functions are text-patched (one line each, md5-guarded, previous text saved in
--   tp_backup.func_snapshots batch 'b3f_backup'); four new functions. No table, row or privilege of existing data
--   is changed. No drop / delete / truncate. Rollback: R_tp-b3f-backup-rollback.sql
-- =====================================================================================================
begin;

do $$ begin
  if public._setting('admin_wipe_enabled', 0) <> 0 then raise exception 'admin_wipe_enabled is not 0 — stop'; end if;
  if to_regclass('public.point_batches') is null then raise exception 'batch 3b required'; end if;
  if exists (select 1 from tp_backup.func_snapshots where batch = 'b3f_backup') then raise exception 'already applied'; end if;
end $$;

-- reconcile a restored state (owner only; called by _tp_wipe_restore inside its transaction)
create function public._tp_restore_reconcile(p_stamp text) returns jsonb
language plpgsql set search_path = public, pg_temp as $$
declare c record; w numeric; opened int := 0; bad text;
begin
  perform set_config('tp.ledger', '1', true);
  -- 1. copies made before batch 3: customers with points but no ledger get opening batches
  for c in select phone, points, welcome_remain, welcome_exp from public.customers x
            where coalesce(points, 0) > 0 and not exists (select 1 from public.point_batches b where b.customer_phone = x.phone) loop
    w := case when c.welcome_exp is not null then least(greatest(coalesce(c.welcome_remain, 0), 0), c.points) else 0 end;
    perform public._pts_add(c.phone, w, 'welcome', c.welcome_exp, null, null, 'restore', 'welcome gift (opening after restore)');
    perform public._pts_add(c.phone, c.points - w, 'legacy',
      now() + make_interval(months => public._setting('legacy_points_valid_months', 3)::int), null, null, 'restore', 'opening balance after restore');
    opened := opened + 1;
  end loop;
  perform set_config('tp.ledger', '0', true);
  -- 2. cached points = ledger total (expired-but-not-yet-processed batches included, as at copy time)
  bad := (select string_agg(x.phone, ', ') from public.customers x
           where coalesce(x.points, 0) <> coalesce((select sum(remaining) from public.point_batches b where b.customer_phone = x.phone), 0)
             and exists (select 1 from public.point_batches b where b.customer_phone = x.phone));
  if bad is not null then raise exception 'TP_RESTORE_LEDGER: cached points differ from the ledger for % — nothing restored', bad; end if;
  -- 3. every point batch = the sum of its own movements
  bad := (select string_agg(b.id::text, ', ') from public.point_batches b
           where b.remaining <> coalesce((select sum(m.delta) from public.point_movements m where m.batch_id = b.id), 0));
  if bad is not null then raise exception 'TP_RESTORE_LEDGER: point batches without matching movements: % — nothing restored', bad; end if;
  -- 4. every allowance grant = the sum of its own movements
  bad := (select string_agg(g.id::text, ', ') from public.allowance_grants g
           where g.remaining <> coalesce((select sum(m.delta) from public.allowance_movements m where m.grant_id = g.id), 0));
  if bad is not null then raise exception 'TP_RESTORE_ALLOWANCE: grants without matching movements: % — nothing restored', bad; end if;
  -- 5. held reservations only on purchases still pending
  bad := (select string_agg(distinct h.tx_id::text, ', ') from public.allowance_holds h
           left join public.pos_transactions t on t.id = h.tx_id where h.status = 'held' and coalesce(t.status, '') <> 'PENDING');
  if bad is not null then raise exception 'TP_RESTORE_ALLOWANCE: reservations held for purchases that are not pending: % — nothing restored', bad; end if;
  insert into public.audit_log(actor_role, actor_id, action, target_type, target_id, detail)
  values ('owner', current_user, 'wipe_restore', 'backup', p_stamp, jsonb_build_object('opening_batches', opened));
  return jsonb_build_object('reconciled', true, 'opening_batches', opened);
end $$;
revoke all on function public._tp_restore_reconcile(text) from public, anon, authenticated;

-- text patches (one line each)
do $$
declare r record; cur text; d text; n int;
begin
  for r in select * from (values
    ('_tp_wipe_restore(text)', '03c61ee2dad13aea7c5b6a1557fa89cd',
     'update tp_backup.wipe_runs set restored_at = now(), restored_by = current_user where stamp = p_stamp;',
     'out := out || jsonb_build_object(''reconcile'', public._tp_restore_reconcile(p_stamp)); /* B3F */ update tp_backup.wipe_runs set restored_at = now(), restored_by = current_user where stamp = p_stamp;'),
    ('_tp_wipe_snapshot(text,uuid)', 'c411adff1cb30edfe12063d72cb8a099',
     'return stamp;',
     'insert into public.audit_log(actor_role, actor_id, action, target_type, target_id, detail) values (''admin'', coalesce(p_admin::text, p_by), ''wipe_snapshot'', ''backup'', stamp, jsonb_build_object(''tables'', jsonb_array_length(info), ''by'', p_by)); /* B3F */ return stamp;')
  ) v(sig, want, old, new) loop
    -- Staging's phase-0 text was saved from the SQL editor with Windows line ends: compare without them
    cur := (select md5(replace(prosrc, chr(13), '')) from pg_proc where oid = to_regprocedure('public.' || r.sig));
    if cur is distinct from r.want then raise exception '% differs (md5 %), stop', r.sig, cur; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.sig));
    insert into tp_backup.func_snapshots(batch, sig, def, src_md5)
    values ('b3f_backup', r.sig, d, (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)));
    n := (length(d) - length(replace(d, r.old, ''))) / length(r.old);
    if n <> 1 then raise exception 'patch target found % times in %', n, r.sig; end if;
    execute replace(d, r.old, r.new);
  end loop;
end $$;

-- a copy WITHOUT wiping (primary admin, audited)
create function public.admin_backup_now_v2(p_session text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; v_stamp text;
begin
  a := public._sess_admin(p_session, true);
  if exists (select 1 from tp_backup.wipe_runs where made_at > now() - interval '10 minutes' and made_by like 'backup:%') then
    return jsonb_build_object('ok', false, 'error', 'too_soon', 'message', 'أُخذت نسخة احتياطية قبل أقل من 10 دقائق');
  end if;
  v_stamp := public._tp_wipe_snapshot('backup:' || a.username, a.id);
  return jsonb_build_object('ok', true, 'stamp', v_stamp,
    'tables', (select jsonb_array_length(w.tables) from tp_backup.wipe_runs w where w.stamp = v_stamp));
end $$;

create function public.admin_backup_list_v2(p_session text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, true);
  return jsonb_build_object('ok', true, 'wipe_enabled', public._setting('admin_wipe_enabled', 0) = 1,
    'copies', (select coalesce(jsonb_agg(jsonb_build_object('stamp', stamp, 'at', floor(extract(epoch from made_at) * 1000), 'by', made_by,
                 'tables', jsonb_array_length(tables), 'rows', (select sum((x->>'rows')::bigint) from jsonb_array_elements(tables) x),
                 'restored_at', case when restored_at is null then null else floor(extract(epoch from restored_at) * 1000) end,
                 'has_ledger', exists (select 1 from jsonb_array_elements(tables) x where x->>'t' in ('point_batches','public.point_batches')))
               order by made_at desc), '[]'::jsonb) from (select * from tp_backup.wipe_runs order by made_at desc limit 50) w));
end $$;

do $$
begin
  execute 'revoke all on function public.admin_backup_now_v2(text) from public';
  execute 'revoke all on function public.admin_backup_list_v2(text) from public';
  execute 'grant execute on function public.admin_backup_now_v2(text) to anon, authenticated';
  execute 'grant execute on function public.admin_backup_list_v2(text) to anon, authenticated';
  if has_function_privilege('anon', 'public._tp_wipe_restore(text)', 'execute') or has_function_privilege('anon', 'public._tp_restore_reconcile(text)', 'execute')
     or has_function_privilege('anon', 'public._tp_wipe_snapshot(text,uuid)', 'execute') then
    raise exception 'self-check: an owner-only backup function is reachable by anon';
  end if;
  if public._setting('admin_wipe_enabled', 0) <> 0 then raise exception 'self-check: wipe enabled'; end if;
end $$;

commit;
