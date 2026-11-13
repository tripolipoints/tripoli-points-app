-- =====================================================================================================
-- Tripoli Points — DATA FINGERPRINT · 2026-11-11 · READ ONLY (one SELECT: nothing is written, no function called)
-- Run it BEFORE phase 0 and again AFTER all post-checks, Download CSV both times, and compare: every row must be
-- identical. It proves that no customer, merchant, wallet, top-up, transaction or point changed.
--   · one row per table of the app (schema public): row count + checksum of the whole content;
--   · totals: customer points, top-ups, top-up orders by status, POS transactions.
-- If the app is used on Staging between the two runs (logins, purchases), the tables touched by that use will
-- differ: run both fingerprints in a quiet window (no one using Staging), ideally a few minutes apart.
-- auth_rate_limits (PIN lock records) is listed separately: it changes with every login attempt by design.
-- =====================================================================================================
with t as (
  select c.oid::regclass as tbl, c.relname
    from pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p')
)
select 1 as part, relname as item,
       (xpath('/row/n/text()', query_to_xml(format('select count(*) as n from %s', tbl), false, true, '')))[1]::text as row_count,
       (xpath('/row/h/text()', query_to_xml(format(
          'select md5(coalesce(string_agg(md5(tp_fp_row::text), '''' order by md5(tp_fp_row::text)), '''')) as h from %s tp_fp_row', tbl), false, true, '')))[1]::text as checksum
  from t where relname <> 'auth_rate_limits'
union all
select 2, 'customers: total points',
       (xpath('/row/n/text()', query_to_xml('select coalesce(sum(points), 0) as n from public.customers', false, true, '')))[1]::text, null
union all
select 2, 'customers: total welcome points remaining',
       (xpath('/row/n/text()', query_to_xml('select coalesce(sum(welcome_remain), 0) as n from public.customers', false, true, '')))[1]::text, null
  where to_regclass('public.customers') is not null
union all
select 2, 'topups: count / total amount',
       (xpath('/row/n/text()', query_to_xml('select count(*) || '' / '' || coalesce(sum(amount), 0) as n from public.topups', false, true, '')))[1]::text, null
  where to_regclass('public.topups') is not null
union all
select 2, 'topup_orders by status: count / amount / points',
       (xpath('/row/n/text()', query_to_xml('select coalesce(string_agg(s, ''; '' order by s), ''none'') as n from (select status || '': '' || count(*) || '' / '' || coalesce(sum(amount), 0) || '' / '' || coalesce(sum(points), 0) as s from public.topup_orders group by status) z', false, true, '')))[1]::text, null
  where to_regclass('public.topup_orders') is not null
union all
select 2, 'pos_transactions: count',
       (xpath('/row/n/text()', query_to_xml('select count(*) as n from public.pos_transactions', false, true, '')))[1]::text, null
  where to_regclass('public.pos_transactions') is not null
union all
select 3, 'auth_rate_limits (changes with logins, by design): records / locked now',
       (xpath('/row/n/text()', query_to_xml('select count(*) || '' / '' || count(*) filter (where locked_until > now()) as n from public.auth_rate_limits', false, true, '')))[1]::text, null
union all
-- phase 0 compares wipe copies with the alias "r": a table column named r would weaken that comparison
select 3, 'public tables with a column named "r" (should be none)',
       coalesce((select string_agg(table_name, ', ') from information_schema.columns where table_schema = 'public' and column_name = 'r'), 'none'), null
order by 1, 2;
