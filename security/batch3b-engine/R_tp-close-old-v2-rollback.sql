-- ROLLBACK of tp-close-old-v2.sql (STAGING ONLY): restores the exact saved privileges of every function it closed
-- and the previous engine_strict value. No data is touched. Not run unless explicitly decided.
begin;
do $$
declare r record; g record; cur aclitem[];
begin
  if not exists (select 1 from tp_backup.acl_snapshots where batch = 'b3_close_old') then raise exception 'no snapshot'; end if;
  for r in select sig, acl, owner_name from tp_backup.acl_snapshots where batch = 'b3_close_old' loop
    if to_regprocedure(r.sig) is null then continue; end if;
    if r.acl is null then
      execute format('grant execute on function %s to public', r.sig);     -- NULL acl = default privileges (PUBLIC execute)
    else
      for g in select a.grantee, a.privilege_type from aclexplode(r.acl) a where a.privilege_type = 'EXECUTE' loop
        execute format('grant execute on function %s to %s', r.sig, case when g.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(g.grantee)) end);
      end loop;
    end if;
  end loop;
  -- verify: every saved EXECUTE grant is back
  for r in select sig, acl from tp_backup.acl_snapshots where batch = 'b3_close_old' and acl is not null loop
    if exists (select 1 from aclexplode(r.acl) a where a.privilege_type = 'EXECUTE' and a.grantee <> 0
                 and not has_function_privilege(a.grantee, to_regprocedure(r.sig), 'execute')) then
      raise exception 'restore failed for %', r.sig;
    end if;
  end loop;
end $$;
update public.app_settings s set value = x.old_value::numeric
  from tp_backup.settings_snapshots x where x.batch = 'b3_close_old' and x.tbl = 'app_settings' and x.key = s.key and s.key = 'engine_strict';
commit;
