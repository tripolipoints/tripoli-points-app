-- STAGING ONLY (project axzlshimvtskkxknlwoz) — NOT RUN. Run it yourself in the Staging SQL Editor only after approving it.
-- Adds two categories if they are missing: earphones («سماعات أذن») and wedding_dresses («فساتين أعراس»).
-- Checked on 2026-11-09 from your export: Staging has only stg_cafe, stg_fashion, stg_food → both are missing.

-- 1) Check first (read only): the table's columns, and whether the two slugs already exist
select column_name, data_type, is_nullable, column_default
from information_schema.columns where table_schema = 'public' and table_name = 'categories' order by ordinal_position;

select slug, name_ar, parent_id, is_active from public.categories
where slug in ('earphones', 'wedding_dresses', 'stg_earphones', 'stg_wedding_dresses');

-- 2) Add them (safe to run twice: each insert is skipped when the slug already exists).
--    If step 1 shows a column below does not exist (or another column is NOT NULL without a default), adjust before running.
begin;
insert into public.categories (slug, name_ar, icon, color, parent_id, is_active, sort_order)
select 'earphones', 'سماعات أذن', '🎧', '#5b5b66', null, true,
       coalesce((select max(sort_order) from public.categories), 0) + 1
where not exists (select 1 from public.categories where slug = 'earphones');

insert into public.categories (slug, name_ar, icon, color, parent_id, is_active, sort_order)
select 'wedding_dresses', 'فساتين أعراس', '👰', '#b08aa6', null, true,
       coalesce((select max(sort_order) from public.categories), 0) + 1
where not exists (select 1 from public.categories where slug = 'wedding_dresses');

select slug, name_ar, is_active, sort_order from public.categories order by sort_order, slug;
commit;   -- or: rollback;  if the result is not what you expect

-- The map already supports both slugs (and stg_earphones / stg_wedding_dresses). No merchant is changed by this script;
-- a shop shows the new picture only after you choose the category for it from the admin screen.
