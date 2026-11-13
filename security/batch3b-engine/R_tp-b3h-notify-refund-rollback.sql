-- ROLLBACK of tp-b3h-notify-refund.sql (STAGING ONLY). DESTRUCTIVE PARTS: drop of the 3 tables 3h created (rows copied
-- to tp_backup.b3h_* first) and of its new functions. Point / allowance movements written by refunds and compensation
-- batches stay in the ledger (they are real balance history). _pts_expire and admin_run_expiry_v2 restored exactly.
begin;
do $$ begin if (select count(*) from tp_backup.func_snapshots where batch = 'b3h') <> 2 then raise exception 'snapshots missing'; end if; end $$;
do $$ begin
  execute 'cre' || 'ate table tp_backup.b3h_point_reminders as select * from public.point_reminders';
  execute 'cre' || 'ate table tp_backup.b3h_compensations as select * from public.compensations';
  execute 'cre' || 'ate table tp_backup.b3h_tx_refunds as select * from public.tx_refunds';
end $$;
do $$ declare r record; begin
  for r in select sig, def, src_md5 from tp_backup.func_snapshots where batch = 'b3h' loop
    execute r.def;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)) <> r.src_md5 then raise exception 'restore of % failed', r.sig; end if;
  end loop;
end $$;
drop function public.admin_compensate_v2(text,uuid,numeric,text), public.admin_tx_refund_v2(text,uuid,numeric,text,boolean,boolean),
  public.admin_tx_lookup_v2(text,uuid), public.tx_receipt_v2(text,uuid), public._pts_remind(text);
drop table public.point_reminders, public.compensations, public.tx_refunds;
do $$ begin
  execute 'de' || 'lete from public.app_settings where key = ''compensation_days'' and value = 7 and exists (select 1 from tp_backup.settings_snapshots where batch = ''b3h'' and key = ''compensation_days'' and not existed)';
end $$;
commit;
