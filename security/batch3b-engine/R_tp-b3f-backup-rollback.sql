-- ROLLBACK of tp-b3f-backup.sql (STAGING ONLY): restores _tp_wipe_restore and _tp_wipe_snapshot exactly and removes
-- the functions 3f added. DESTRUCTIVE PART: `drop function` of the four functions created by 3f (no data).
-- Copies (tp_backup.w*) and their records are kept.
begin;
do $$
declare r record;
begin
  if (select count(*) from tp_backup.func_snapshots where batch = 'b3f_backup') <> 2 then raise exception 'snapshots missing'; end if;
  for r in select sig, def, src_md5 from tp_backup.func_snapshots where batch = 'b3f_backup' loop
    execute r.def;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)) <> r.src_md5 then raise exception 'restore of % failed', r.sig; end if;
  end loop;
end $$;
drop function public.admin_backup_now_v2(text);
drop function public.admin_backup_list_v2(text);
drop function public._tp_restore_reconcile(text);
commit;
