-- #####################################################################
-- ##  NOT EXECUTED — POSTPONED (decision 2026-10-28)                  ##
-- ##  Kept for future review only. Do NOT run against any database.   ##
-- ##  Image management will be redesigned as part of a dedicated      ##
-- ##  admin-controlled media approval system; database permissions,  ##
-- ##  merchant IDs, column types and security will be reviewed        ##
-- ##  separately before production launch.                           ##
-- #####################################################################
-- =====================================================================
-- Tripoli Points — Stage 2 (A): lightweight map directory + on-demand media
-- STATUS: POSTPONED DRAFT — NOT EXECUTED. Do not run.
-- Rollback: NOT-EXECUTED_POSTPONED_tripoli-points-map-light-rpc-rollback.sql
--
-- Both functions are READ-ONLY (STABLE, SELECT only) and return a strict
-- subset of what public.list_merchants() already returns publicly today.
-- They do not modify any table, row, policy or existing function.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) list_merchants_map()
--    Everything the map, clusters, search, Shop/area browsing and merchant
--    cards need — WITHOUT the embedded photo/logo images (≈340 bytes per
--    merchant instead of up to ~150 KB). has_photo / has_logo tell the app
--    which merchants have media to fetch later.
--    Same row filter as list_merchants(): status = 'active' only.
-- ---------------------------------------------------------------------
create or replace function public.list_merchants_map()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',             m.id,
           'name',           m.name,
           'cat',            m.cat,
           'extra_cats',     m.extra_cats,
           'pct',            m.pct,
           'tier',           m.tier,
           'redeem_pct',     m.redeem_pct,
           'redeem_pct_vip', m.redeem_pct_vip,
           'addr',           m.addr,
           'lat',            m.lat,
           'lng',            m.lng,
           'x',              m.x,
           'y',              m.y,
           'area',           m.area,
           'status',         m.status,
           'page_blurb',     m.page_blurb,
           'page_enabled',   m.page_enabled,
           'has_photo',      coalesce(m.photo_url, '') <> '',
           'has_logo',       coalesce(m.logo_url,  '') <> ''
         ) order by m.id), '[]'::jsonb)
  from public.merchants m
  where m.status = 'active';
$$;

comment on function public.list_merchants_map() is
  'Read-only public map directory: active merchants only, no images, no contact/PIN/admin fields. Subset of list_merchants().';

revoke all on function public.list_merchants_map() from public;
grant execute on function public.list_merchants_map() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 2) merchant_media(p_ids uuid[])
--    Approved public storefront photo and logo for up to 50 requested
--    merchants per call (the array is truncated server-side). Only active
--    merchants; merchants without any media are omitted. The pending
--    (unapproved) photo column is never read.
-- ---------------------------------------------------------------------
create or replace function public.merchant_media(p_ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',        m.id,
           'photo_url', nullif(m.photo_url, ''),
           'logo_url',  nullif(m.logo_url,  '')
         )), '[]'::jsonb)
  from public.merchants m
  where m.status = 'active'
    and m.id = any (coalesce(p_ids[1:50], '{}'::uuid[]))
    and (coalesce(m.photo_url, '') <> '' or coalesce(m.logo_url, '') <> '');
$$;

comment on function public.merchant_media(uuid[]) is
  'Read-only public media for active merchants (approved photo_url, logo_url), max 50 ids per call. Subset of list_merchants().';

revoke all on function public.merchant_media(uuid[]) from public;
grant execute on function public.merchant_media(uuid[]) to anon, authenticated;
