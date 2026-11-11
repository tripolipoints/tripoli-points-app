-- =====================================================================================================
-- Tripoli Points — STRUCTURE EXPORT (no test data) · 2026-11-11 · READ ONLY: one SELECT, nothing is written.
-- Run on STAGING in the SQL editor → Download CSV. The CSV holds, one statement per row (column "sql", in order),
-- everything needed to rebuild the app's database structure on an empty Supabase project:
--   extensions · types · sequences · tables (columns, identity, defaults) · functions (full code, SECURITY DEFINER,
--   search_path) · constraints · indexes · views · triggers · RLS on/off · RLS policies · privileges of anon /
--   authenticated / service_role / PUBLIC on every schema, table, sequence and function, default privileges · Realtime publication tables ·
--   Storage buckets (settings only) and Storage policies · scheduled jobs (pg_cron) if any ·
--   configuration rows only: app_settings, app_text_settings, categories.
-- NOT included (by design): customers, merchants, wallets, top-ups, transactions, points, admin accounts and every
-- other data row (test data, accepted to lose); PIN hashes; passwords or keys of any kind.
-- NOT in the database, so not in this file (save from the Dashboard): Edge Function code and secrets, Auth settings,
-- API settings (exposed schemas), Storage files, project settings.
-- Schemas exported: public plus any custom schema of the project (Supabase-managed schemas are left out).
-- =====================================================================================================
with recursive
sch as (
  select n.oid, n.nspname from pg_namespace n
   where n.nspname not like 'pg\_%' and n.nspname not in ('information_schema', 'auth', 'storage', 'realtime', '_realtime',
         'graphql', 'graphql_public', 'extensions', 'vault', 'supabase_functions', 'supabase_migrations', 'net', 'cron',
         'pgsodium', 'pgsodium_masks', 'pgbouncer', '_analytics', 'pgmq', 'pgtle', 'topology', 'tiger', 'tiger_data')
),
rel as (select c.oid, c.relname, c.relkind, n.nspname, format('%I.%I', n.nspname, c.relname) as q
          from pg_class c join sch n on n.oid = c.relnamespace),
ext_owned as (select objid from pg_depend where deptype = 'e'),
cfg(t) as (values ('public.app_settings'), ('public.app_text_settings'), ('public.categories')),
acl_stmt as (   -- privileges, exactly: everything revoked from the API roles, then what exists re-granted
  select o.ord, o.q, o.kind, o.acl from (
    select 900 as ord, r.q, 'table' as kind, coalesce(c.relacl, acldefault('r', c.relowner)) as acl from rel r join pg_class c on c.oid = r.oid where r.relkind in ('r','p','v','m','f')
    union all select 901, r.q, 'sequence', coalesce(c.relacl, acldefault('s', c.relowner)) from rel r join pg_class c on c.oid = r.oid where r.relkind = 'S'
    union all select 902, p.oid::regprocedure::text, 'function', coalesce(p.proacl, acldefault('f', p.proowner)) from pg_proc p join sch n on n.oid = p.pronamespace
       where p.oid not in (select objid from ext_owned)
  ) o
),
stmts(ord, sub, sql) as (
  select 0, '0', '-- Tripoli Points structure export · ' || current_database() || ' · ' || to_char(now() at time zone 'UTC', 'YYYY-MM-DD HH24:MI') || ' UTC · no data rows except configuration'
  union all select 1, '1', 'set check_function_bodies = false;'
  union all
  select 10, e.extname, format('create extension if not exists %I with schema %I;', e.extname, n.nspname)
    from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname <> 'plpgsql'
  union all
  select 20, s.nspname, format('create schema if not exists %I;', s.nspname) from sch s where s.nspname <> 'public'
  union all   -- enum types
  select 30, t.typname, format('create type %I.%I as enum (%s);', n.nspname, t.typname,
         (select string_agg(quote_literal(e.enumlabel), ', ' order by e.enumsortorder) from pg_enum e where e.enumtypid = t.oid))
    from pg_type t join sch n on n.oid = t.typnamespace where t.typtype = 'e' and t.oid not in (select objid from ext_owned)
  union all   -- sequences that are not identity sequences
  select 40, r.q, format('create sequence if not exists %s as %s increment %s minvalue %s maxvalue %s start %s%s;', r.q,
         format_type(s.seqtypid, null), s.seqincrement, s.seqmin, s.seqmax, s.seqstart, case when s.seqcycle then ' cycle' else '' end)
    from rel r join pg_sequence s on s.seqrelid = r.oid
   where r.relkind = 'S' and not exists (select 1 from pg_depend d where d.objid = r.oid and d.deptype = 'i')
  union all   -- tables: columns, types, not null, identity, generated (plain defaults come later, after functions)
  select 50, r.q, format('create table if not exists %s (%s)%s;', r.q,
         coalesce((select string_agg(format('%I %s%s%s%s', a.attname, format_type(a.atttypid, a.atttypmod),
                    case when a.attcollation <> 0 and a.attcollation <> (select typcollation from pg_type where oid = a.atttypid)
                         then ' collate ' || (select format('%I.%I', cn.nspname, co.collname) from pg_collation co join pg_namespace cn on cn.oid = co.collnamespace where co.oid = a.attcollation) else '' end,
                    case a.attidentity when 'a' then ' generated always as identity' when 'd' then ' generated by default as identity' else '' end
                    || case when a.attgenerated = 's' then ' generated always as (' || pg_get_expr(ad.adbin, ad.adrelid) || ') stored' else '' end,
                    case when a.attnotnull then ' not null' else '' end), ', ' order by a.attnum)
                   from pg_attribute a left join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
                  where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped), ''),
         case when r.relkind = 'p' then ' partition by ' || pg_get_partkeydef(r.oid) else '' end)
    from rel r where r.relkind in ('r', 'p') and r.oid not in (select objid from ext_owned)
  union all   -- sequence ownership (serial columns)
  select 55, r.q, format('alter sequence %s owned by %s.%I;', r.q, (select q from rel where oid = d.refobjid), a.attname)
    from rel r join pg_depend d on d.objid = r.oid and d.deptype = 'a' and d.classid = 'pg_class'::regclass
    join pg_attribute a on a.attrelid = d.refobjid and a.attnum = d.refobjsubid
   where r.relkind = 'S'
  union all   -- functions and procedures, full definition
  select 60, p.oid::regprocedure::text, pg_get_functiondef(p.oid) || ';'
    from pg_proc p join sch n on n.oid = p.pronamespace
   where p.prokind in ('f', 'p', 'w') and p.oid not in (select objid from ext_owned)
  union all   -- column defaults
  select 70, r.q || '.' || a.attname, format('alter table only %s alter column %I set default %s;', r.q, a.attname, pg_get_expr(ad.adbin, ad.adrelid))
    from rel r join pg_attribute a on a.attrelid = r.oid join pg_attrdef ad on ad.adrelid = a.attrelid and ad.adnum = a.attnum
   where r.relkind in ('r', 'p') and a.attgenerated = '' and a.attidentity = '' and not a.attisdropped
  union all   -- constraints: primary keys / unique / check / exclusion first, foreign keys after
  select case when k.contype = 'f' then 81 else 80 end, r.q || '.' || k.conname,
         format('alter table only %s add constraint %I %s;', r.q, k.conname, pg_get_constraintdef(k.oid))
    from pg_constraint k join rel r on r.oid = k.conrelid where k.contype in ('p', 'u', 'c', 'f', 'x') and k.conislocal
  union all   -- indexes that do not belong to a constraint
  select 90, i.indexrelid::regclass::text, pg_get_indexdef(i.indexrelid) || ';'
    from pg_index i join rel r on r.oid = i.indrelid
   where not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid and k.contype in ('p', 'u', 'x'))
  union all   -- views and materialized views
  select 100, r.q, case r.relkind when 'v' then format('create or replace view %s as %s', r.q, pg_get_viewdef(r.oid))
                                  else format('create materialized view if not exists %s as %s', r.q, pg_get_viewdef(r.oid)) end
    from rel r where r.relkind in ('v', 'm')
  union all   -- triggers (also database webhooks, which are triggers)
  select 110, r.q || '.' || t.tgname, pg_get_triggerdef(t.oid) || ';'
    from pg_trigger t join rel r on r.oid = t.tgrelid where not t.tgisinternal
  union all   -- row level security switches
  select 120, r.q, format('alter table %s %s row level security;', r.q, case when c.relrowsecurity then 'enable' else 'disable' end)
           || case when c.relforcerowsecurity then format(' alter table %s force row level security;', r.q) else '' end
    from rel r join pg_class c on c.oid = r.oid where r.relkind in ('r', 'p')
  union all   -- RLS policies of the app tables and of storage.objects
  select 130, pol.schemaname || '.' || pol.tablename || '.' || pol.policyname,
         format('create policy %I on %I.%I as %s for %s to %s%s%s;', pol.policyname, pol.schemaname, pol.tablename, lower(pol.permissive), lower(pol.cmd),
                (select string_agg(case when x = 'public' then 'public' else quote_ident(x) end, ', ') from unnest(pol.roles) x),
                case when pol.qual is not null then ' using (' || pol.qual || ')' else '' end,
                case when pol.with_check is not null then ' with check (' || pol.with_check || ')' else '' end)
    from pg_policies pol where pol.schemaname in (select nspname from sch) or (pol.schemaname = 'storage' and pol.tablename = 'objects')
  union all   -- privileges: revoke from the API roles, then re-grant exactly what exists today
  select a.ord, a.q || ' 0', format('revoke all on %s %s from public, anon, authenticated, service_role;', a.kind, a.q)
    from acl_stmt a
  union all
  select a.ord, a.q || ' 1' || g.grantee || g.privilege_type,
         format('grant %s on %s %s to %s;', g.privilege_type, a.kind, a.q, case when g.grantee = '-' then 'public' else quote_ident(g.grantee) end)
    from acl_stmt a
    cross join lateral (
      select case when x.grantee = 0 then '-' else pg_get_userbyid(x.grantee)::text end as grantee, x.privilege_type
        from aclexplode(case when cardinality(a.acl) > 0 then a.acl end) x
       where x.grantee = 0 or pg_get_userbyid(x.grantee) in ('anon', 'authenticated', 'service_role')
    ) g
  union all   -- schema privileges of the API roles
  select 940, s.nspname || ' ' || g.grantee || g.privilege_type,
         format('grant %s on schema %I to %s;', g.privilege_type, s.nspname, case when g.grantee = '-' then 'public' else quote_ident(g.grantee) end)
    from sch s join pg_namespace n on n.oid = s.oid
    cross join lateral (select case when x.grantee = 0 then '-' else pg_get_userbyid(x.grantee)::text end as grantee, x.privilege_type
                          from aclexplode(n.nspacl) x where x.grantee = 0 or pg_get_userbyid(x.grantee) in ('anon', 'authenticated', 'service_role')) g
  union all   -- default privileges (what new tables / functions / sequences get automatically)
  select 941, pg_get_userbyid(d.defaclrole) || ' ' || coalesce(n.nspname, '') || ' ' || d.defaclobjtype::text || ' ' || g.grantee || g.privilege_type,
         format('alter default privileges for role %I%s grant %s on %s to %s;', pg_get_userbyid(d.defaclrole),
                case when n.nspname is null then '' else format(' in schema %I', n.nspname) end, g.privilege_type,
                case d.defaclobjtype when 'r' then 'tables' when 'f' then 'functions' when 'S' then 'sequences' when 'T' then 'types' else 'schemas' end,
                case when g.grantee = '-' then 'public' else quote_ident(g.grantee) end)
    from pg_default_acl d left join pg_namespace n on n.oid = d.defaclnamespace
    cross join lateral (select case when x.grantee = 0 then '-' else pg_get_userbyid(x.grantee)::text end as grantee, x.privilege_type
                          from aclexplode(d.defaclacl) x where x.grantee = 0 or pg_get_userbyid(x.grantee) in ('anon', 'authenticated', 'service_role')) g
   where (d.defaclnamespace = 0 or d.defaclnamespace in (select oid from sch))
     and pg_get_userbyid(d.defaclrole) in ('postgres', 'supabase_admin')
  union all   -- Realtime: which app tables are published
  select 950, pt.schemaname || '.' || pt.tablename,
         format('alter publication supabase_realtime add table %I.%I;', pt.schemaname, pt.tablename)
    from pg_publication_tables pt where pt.pubname = 'supabase_realtime' and pt.schemaname in (select nspname from sch)
  union all   -- Storage buckets: settings only (no files)
  select 960, b.id, format('insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values (%L, %L, %s, %s, %L) on conflict (id) do nothing;',
         b.id, b.name, b.public::text, coalesce(b.file_size_limit::text, 'null'), b.allowed_mime_types)
    from storage.buckets b
  union all   -- configuration rows only (no customer / merchant / wallet / transaction data)
  select 970, c.t, format('insert into %s select * from json_populate_recordset(null::%s, %L) on conflict do nothing;', c.t, c.t,
         (xpath('/row/j/text()', query_to_xml(format('select coalesce(json_agg(x), ''[]'') as j from %s x', c.t), false, true, '')))[1]::text)
    from cfg c where to_regclass(c.t) is not null
  union all   -- scheduled jobs, if pg_cron is used
  select 980, 'cron', coalesce((xpath('/row/j/text()', query_to_xml(
           'select string_agg(format(''select cron.schedule(%L, %L, %L);'', jobname, schedule, command), chr(10)) as j from cron.job', false, true, '')))[1]::text,
           '-- no pg_cron jobs')
   where to_regclass('cron.job') is not null
  union all
  select 999, 'end', '-- end of structure export'
)
select row_number() over (order by ord, sub) as n, sql from stmts order by ord, sub;
