-- Tripoli Points — HOTFIX H1 ROLLBACK v1.1 (emergency only). Restores, for each of the 10 functions, EXACTLY the
-- privileges recorded by H1 before it changed anything (tp_backup.acl_snapshots, batch 'H1'): every grant H1 removed
-- comes back, and nothing that was not there before is added. Verifies the result entry by entry.
-- WARNING: this REOPENS the holes that were open before H1. Tell the developer first.
begin;
do $rb$
declare s record; g record; n int := 0; cur text; want text;
begin
  if to_regclass('tp_backup.acl_snapshots') is null then raise exception 'ROLLBACK STOP: no H1 snapshot found (H1 was never applied here)'; end if;
  for s in execute 'select sig, acl, owner_name from tp_backup.acl_snapshots where batch = ''H1'' order by id' loop
    if to_regprocedure('public.' || s.sig) is null then raise exception 'ROLLBACK STOP: % missing', s.sig; end if;
    -- remove every current grant except the owner's
    for g in select distinct case when a.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end as who
             from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
             where p.oid = to_regprocedure('public.' || s.sig) and a.grantee <> p.proowner loop
      execute format('revoke execute on function public.%s from %s', s.sig, g.who);
    end loop;
    -- put back exactly what was recorded (NULL = the default: owner + PUBLIC)
    for g in select case when a.grantee = 0 then 'public' else quote_ident(pg_get_userbyid(a.grantee)) end as who
             from aclexplode(coalesce(s.acl, acldefault('f', (select proowner from pg_proc where oid = to_regprocedure('public.' || s.sig))))) a
             where pg_get_userbyid(a.grantee) is distinct from s.owner_name and a.privilege_type = 'EXECUTE' loop
      execute format('grant execute on function public.%s to %s', s.sig, g.who);
    end loop;
    -- verify: same (grantee, privilege) set as recorded
    want := (select string_agg(a.grantee::text || ':' || a.privilege_type, ',' order by a.grantee::text)
             from aclexplode(coalesce(s.acl, acldefault('f', (select proowner from pg_proc where oid = to_regprocedure('public.' || s.sig))))) a);
    cur := (select string_agg(a.grantee::text || ':' || a.privilege_type, ',' order by a.grantee::text)
            from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where p.oid = to_regprocedure('public.' || s.sig));
    if cur is distinct from want then raise exception 'ROLLBACK STOP: % now % but recorded %', s.sig, cur, want; end if;
    n := n + 1;
  end loop;
  if n <> 10 then raise exception 'ROLLBACK STOP: % snapshot rows, expected 10', n; end if;
  raise notice 'H1 rolled back exactly: % function(s) restored to their recorded privileges (vulnerable again where they were open)', n;
end $rb$;
commit;
