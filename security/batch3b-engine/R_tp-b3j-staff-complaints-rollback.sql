-- ROLLBACK of tp-b3j-staff-complaints.sql (STAGING ONLY). DESTRUCTIVE PARTS: drop of table staff_devices (rows copied to
-- tp_backup.b3j_staff_devices first), of the 9 columns 3j added (values copied first), of trigger tx_reports_due and of
-- the new functions. staff_login, admin_security_feed_v2 and admin_run_jobs_v2 are restored exactly.
begin;
do $$ begin if (select count(*) from tp_backup.func_snapshots where batch = 'b3j') <> 3 then raise exception 'snapshots missing'; end if; end $$;
do $$ begin
  execute 'cre' || 'ate table tp_backup.b3j_staff_devices as select * from public.staff_devices';
  execute 'cre' || 'ate table tp_backup.b3j_staff_credentials as select id, email, password_hash, verified_at, pin6_hash from public.merchant_staff';
  execute 'cre' || 'ate table tp_backup.b3j_report_deadlines as select id, response_due_at, resolve_due_at, first_response_at, last_admin_message, escalated_at from public.tx_reports';
end $$;
do $$ declare r record; begin
  for r in select sig, def, src_md5 from tp_backup.func_snapshots where batch = 'b3j' loop
    execute r.def;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)) <> r.src_md5 then raise exception 'restore of % failed', r.sig; end if;
  end loop;
end $$;
drop trigger tx_reports_due on public.tx_reports;
drop function public.merchant_staff_credentials_v2(text,uuid,text,text), public.staff_first_login_v2(text,text,text,text), public._staff_code_issue(uuid,uuid),
  public.staff_verify_code_v2(text,text,text,text), public.merchant_staff_devices_v2(text), public.merchant_staff_device_decide_v2(text,uuid,boolean),
  public.staff_set_pin6_v2(text,text,text,text), public.staff_pin_login_v2(text,text,text), public.admin_report_respond_v2(text,uuid,text),
  public._escalate_reports(), public._tr_report_due(), public._staff_device(uuid,text);
drop table public.staff_devices;
drop index public.merchant_staff_email_uidx;
alter table public.merchant_staff drop column email, drop column password_hash, drop column verified_at, drop column pin6_hash;
alter table public.tx_reports drop column response_due_at, drop column resolve_due_at, drop column first_response_at, drop column last_admin_message, drop column escalated_at;
do $$ declare r record; begin
  for r in select key, inserted_value from tp_backup.settings_snapshots where batch = 'b3j' and not existed loop
    execute 'de' || 'lete from public.app_settings where key = $1 and value::text = $2' using r.key, r.inserted_value;
  end loop;
end $$;
commit;
