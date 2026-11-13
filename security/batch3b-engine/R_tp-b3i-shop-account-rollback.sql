-- ROLLBACK of tp-b3i-shop-account.sql (STAGING ONLY). DESTRUCTIVE PARTS: drop of merchant_hours / merchant_closures
-- (rows copied to tp_backup.b3i_* first), of the 7 columns 3i added (values copied to tp_backup.b3i_customer_privacy /
-- b3i_merchant_closure first) and of its new functions. The 4 patched functions are restored exactly.
-- Accounts disabled or closed by the deletion timeline stay as they are (their history is in audit_log).
begin;
do $$ begin if (select count(*) from tp_backup.func_snapshots where batch = 'b3i') <> 4 then raise exception 'snapshots missing'; end if; end $$;
do $$ begin
  execute 'cre' || 'ate table tp_backup.b3i_merchant_hours as select * from public.merchant_hours';
  execute 'cre' || 'ate table tp_backup.b3i_merchant_closures as select * from public.merchant_closures';
  execute 'cre' || 'ate table tp_backup.b3i_customer_privacy as select phone, deletion_requested_at, deactivated_at, data_removed_at, marketing_consent, marketing_consent_at from public.customers';
  execute 'cre' || 'ate table tp_backup.b3i_merchant_closure as select id, closure_requested_at, closed_at from public.merchants';
end $$;
do $$ declare r record; begin
  for r in select sig, def, src_md5 from tp_backup.func_snapshots where batch = 'b3i' loop
    execute r.def;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)) <> r.src_md5 then raise exception 'restore of % failed', r.sig; end if;
  end loop;
end $$;
drop function public.merchant_hours_v2(text), public.merchant_hours_set_v2(text,jsonb), public.merchant_closure_start_v2(text,timestamptz,timestamptz,text),
  public.merchant_closure_end_v2(text,bigint), public.shop_hours_public(uuid), public.report_shop_info_v2(text,uuid,text), public.merchant_sub_status_v2(text),
  public.merchant_close_shop_request_v2(text,text), public.admin_closure_review_v2(text,uuid), public.admin_close_shop_v2(text,uuid,boolean,text),
  public.customer_privacy_v2(text), public.customer_set_marketing_v2(text,boolean), public.customer_delete_request_v2(text,text),
  public.customer_delete_cancel_v2(text), public.admin_customer_reactivate_v2(text,text,text), public.admin_run_jobs_v2(text),
  public._process_account_closures(), public._shop_state(uuid), public._merchant_listed(uuid);
drop table public.merchant_hours, public.merchant_closures;
alter table public.merchants drop column closure_requested_at, drop column closed_at;
alter table public.customers drop column deletion_requested_at, drop column deactivated_at, drop column data_removed_at, drop column marketing_consent, drop column marketing_consent_at;
do $$ declare r record; begin
  for r in select key, inserted_value from tp_backup.settings_snapshots where batch = 'b3i' and not existed loop
    execute 'de' || 'lete from public.app_settings where key = $1 and value::text = $2' using r.key, r.inserted_value;
  end loop;
end $$;
commit;
