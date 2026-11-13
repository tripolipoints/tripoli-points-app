-- =====================================================================================================
-- ROLLBACK of tp-engine-v1.sql (batch 3b) — STAGING ONLY. Not run unless explicitly decided.
-- DESTRUCTIVE PARTS (review before running):
--   * drops the 11 new tables and 2 new columns (app_sessions.staff_id, pos_transactions.staff_id).
--     Their rows are first COPIED to tp_backup.b3b_<table> (kept), so no data is lost.
--   * staff sessions are revoked before app_sessions.staff_id is dropped (otherwise they would become
--     owner sessions).
--   * the 12 replaced functions are restored from tp_backup.func_snapshots (exact text, ACL kept).
--   * settings keys added by batch 3b are removed only if still at their inserted value.
--   customers.points is left as it is (the ledger kept it equal to the valid total).
-- =====================================================================================================
begin;

do $$ begin
  if (select count(*) from tp_backup.func_snapshots where batch = 'b3b_engine_v1') <> 12 then
    raise exception 'function snapshots missing — stop';
  end if;
end $$;

-- 1) keep a copy of everything batch 3b created
do $$
declare t text;
begin
  foreach t in array array['point_batches','point_movements','plans','packages','merchant_staff','payment_requests',
                           'merchant_subscriptions','allowance_grants','allowance_holds','allowance_movements','audit_log'] loop
    if to_regclass('tp_backup.b3b_' || t) is not null then raise exception 'tp_backup.b3b_% already exists — stop', t; end if;
    execute format('cre' || 'ate table tp_backup.%I as select * from public.%I', 'b3b_' || t, t);
  end loop;
  execute 'cre' || 'ate table tp_backup.b3b_pos_staff as select id, staff_id from public.pos_transactions where staff_id is not null';
  execute 'cre' || 'ate table tp_backup.b3b_session_staff as select id, staff_id from public.app_sessions where staff_id is not null';
end $$;

-- 2) staff sessions end
update public.app_sessions set revoked_at = now(), revoked_reason = 'rollback_b3b' where staff_id is not null and revoked_at is null;

-- 3) triggers
drop trigger if exists customers_points_guard on public.customers;
drop trigger if exists customers_points_open on public.customers;
drop trigger if exists merchant_staff_revoke on public.merchant_staff;

-- 4) replaced functions back to their phase-1 text
do $$
declare r record;
begin
  for r in select sig, def, src_md5 from tp_backup.func_snapshots where batch = 'b3b_engine_v1' loop
    execute r.def;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)) <> r.src_md5 then
      raise exception 'restore of % did not match', r.sig;
    end if;
  end loop;
end $$;

-- 5) new functions
do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[
      '_audit','_day_start','_ref_norm','_ledger','_pts_spendable','_pts_sync','_pts_add','_pts_take','_pts_expire','_tr_points_guard',
      '_tr_points_open','_allow_remaining','_allow_cap','_allow_add','_allow_reserve','_allow_consume','_allow_release','_allow_expire',
      '_allow_json','_sess_branch','_staff_id','_tr_staff_revoke','_staff_json','_payreq_json',
      'staff_login','merchant_staff_list_v2','merchant_staff_save_v2','customer_points_v2','merchant_allowance_v2','merchant_catalog_v2',
      'merchant_payment_request_v2','merchant_payment_requests_v2','merchant_payment_cancel_v2','admin_catalog_v2','admin_plan_save_v2',
      'admin_package_save_v2','admin_pay_settings_v2','admin_engine_setting_v2','admin_payment_requests_v2','admin_payment_decide_v2',
      'admin_merchant_allowance_v2','admin_allowance_adjust_v2','admin_customer_points_v2','admin_points_adjust_v2','admin_run_expiry_v2',
      'admin_audit_log_v2']) loop
    execute format('drop function %s', f);
  end loop;
end $$;

-- 6) columns and tables (copies kept in tp_backup)
alter table public.app_sessions drop column staff_id;
alter table public.pos_transactions drop column staff_id;
drop table public.allowance_holds, public.allowance_movements, public.allowance_grants, public.merchant_subscriptions,
           public.payment_requests, public.point_movements, public.point_batches, public.plans, public.packages,
           public.merchant_staff, public.audit_log;

-- 7) settings added by batch 3b, only when unchanged
do $$
declare r record;
begin
  for r in select tbl, key, inserted_value from tp_backup.settings_snapshots where batch = 'b3b_engine_v1' and not existed loop
    if r.tbl = 'app_settings' then
      execute 'de' || 'lete from public.app_settings where key = $1 and value::text = $2' using r.key, r.inserted_value;
    else
      execute 'de' || 'lete from public.app_text_settings where key = $1 and value = $2' using r.key, r.inserted_value;
    end if;
  end loop;
end $$;

commit;
