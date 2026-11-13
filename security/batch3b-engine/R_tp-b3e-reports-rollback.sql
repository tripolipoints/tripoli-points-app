-- ROLLBACK of tp-b3e-reports.sql (STAGING ONLY): restores the two functions' previous text exactly and removes the
-- helper it added. DESTRUCTIVE PART: `drop function public._report_notify(uuid)` — a helper created by 3e, no data.
begin;
do $$
declare r record;
begin
  if (select count(*) from tp_backup.func_snapshots where batch = 'b3e_reports') <> 2 then raise exception 'snapshots missing'; end if;
  for r in select sig, def, src_md5 from tp_backup.func_snapshots where batch = 'b3e_reports' loop
    execute r.def;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)) <> r.src_md5 then raise exception 'restore of % failed', r.sig; end if;
  end loop;
end $$;
drop function public._report_notify(uuid);
commit;
