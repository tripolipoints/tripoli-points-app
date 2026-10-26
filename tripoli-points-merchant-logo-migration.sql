-- =====================================================================
-- Tripoli Points — Merchant Logo Persistence Migration
-- =====================================================================
-- Purpose: persist merchant logo uploads to Supabase so they survive a
-- page refresh, logout, and re-login, consistent with how the app
-- already persists the merchant's storefront photo (photo_url).
--
-- Scope: adds exactly one column and one new RPC, and extends three
-- existing read-only RPCs to also return the new column. No existing
-- column, table, RPC behavior, or RLS policy is removed or altered
-- beyond adding the new field to their output.
--
-- No Supabase Storage bucket is introduced. This project has never
-- used Supabase Storage (storage.buckets has 0 rows) — every existing
-- image (storefront photo, gallery photos, customer/offer photos) is
-- stored as a base64 data: URI directly in a text column, written via
-- a SECURITY DEFINER RPC. This migration follows that exact, already-
-- proven pattern for consistency, instead of introducing a new,
-- unprecedented Storage-based path. If you'd prefer Supabase Storage
-- for logos specifically (e.g. to reduce row size), that is a larger,
-- separate change — happy to prepare it if you'd like to go that route
-- instead; let me know before this migration is run.
--
-- IMPORTANT: Review this file, then run it yourself in the Supabase
-- SQL editor (or via `supabase db` CLI against this project). Nothing
-- in this file has been executed. See "HOW TO RUN THIS" at the bottom.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) New column: public.merchants.logo_url
-- ---------------------------------------------------------------------
-- Nullable text column, same shape as the existing photo_url column.
-- Holds either NULL/empty (no custom logo — client shows the Tripoli
-- Points fallback mark) or a base64 data: URI of the merchant's logo.
ALTER TABLE public.merchants
  ADD COLUMN IF NOT EXISTS logo_url text;


-- ---------------------------------------------------------------------
-- 2) New RPC: public.merchant_set_logo(p_merchant_id, p_logo_url)
-- ---------------------------------------------------------------------
-- Mirrors the existing merchant_submit_photo function exactly in shape
-- and security model (SECURITY DEFINER, scoped to the one merchant row
-- the caller names). Used for BOTH saving a new logo and removing one:
-- call with p_logo_url = NULL (or '') to remove, matching how the
-- client already treats an empty m.logo as "no custom logo".
--
-- Security model: identical to every other merchant_* write RPC in
-- this app (merchant_submit_photo, merchant_gallery_add, etc.) — the
-- merchant authenticates once at login via merchant_verify_pin, and
-- every write RPC afterward trusts the client-held merchant id for
-- that session, the same boundary the rest of the app already uses.
-- This migration does not introduce a new per-action PIN re-check,
-- because no other merchant action in the app re-prompts for the PIN
-- either — adding one only for the logo would be a new, inconsistent
-- pattern. If you specifically want a PIN re-confirmation step before
-- saving/removing a logo (as the V31 preview appeared to prompt for),
-- that is a UX/security decision that would need a new RPC parameter
-- (e.g. p_pin) checked against pin_hash before the update — let me
-- know if you want that added, and I'll prepare it as a deliberate,
-- explained change rather than guessing at it here.
CREATE OR REPLACE FUNCTION public.merchant_set_logo(p_merchant_id uuid, p_logo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r public.merchants;
begin
  update public.merchants set logo_url = nullif(p_logo_url, '')
  where id = p_merchant_id returning * into r;
  if r is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  return jsonb_build_object('ok', true, 'logo_url', r.logo_url);
end; $function$;


-- ---------------------------------------------------------------------
-- 3) Extend existing read RPCs to also return logo_url
-- ---------------------------------------------------------------------
-- Each function below is reproduced in full and is otherwise byte-for-
-- byte identical to the version currently deployed (confirmed via
-- pg_get_functiondef before writing this file) — the only change in
-- each is the addition of a 'logo_url' key to its returned JSON.

-- 3a) merchant_verify_pin — used at merchant login; this is what lets
-- a merchant's own logo survive logout + re-login.
CREATE OR REPLACE FUNCTION public.merchant_verify_pin(p_phone text, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants;
begin
  select * into r from public.merchants where phone = p_phone;
  if r is null then return jsonb_build_object('ok', false, 'reason', 'not_found'); end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  return jsonb_build_object('ok', true, 'merchant', jsonb_build_object(
    'id', r.id, 'name', r.name, 'phone', r.phone, 'status', r.status, 'cat', r.cat, 'pct', r.pct,
    'tier', r.tier, 'addr', r.addr, 'photo_url', r.photo_url, 'photo_pending_url', r.photo_pending_url,
    'logo_url', r.logo_url,
    'poster_printed', r.poster_printed, 'warns', r.warns,
    'redeem_pct', r.redeem_pct, 'redeem_pct_vip', r.redeem_pct_vip,
    'pending_name', r.pending_name, 'pending_addr', r.pending_addr));
end; $function$;

-- 3b) list_merchants — used for the customer-facing directory/map/store
-- pages, so a merchant's saved logo shows consistently to customers too.
CREATE OR REPLACE FUNCTION public.list_merchants()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'cat', cat, 'extra_cats', extra_cats, 'pct', pct, 'tier', tier,
    'redeem_pct', redeem_pct, 'redeem_pct_vip', redeem_pct_vip,
    'addr', addr, 'lat', lat, 'lng', lng, 'x', x, 'y', y, 'area', area,
    'photo_url', photo_url, 'logo_url', logo_url, 'status', status,
    'page_blurb', page_blurb, 'page_enabled', page_enabled
  )), '[]'::jsonb) into r
  from public.merchants where status = 'active';
  return r;
end; $function$;

-- 3c) admin_list_merchants — used on the admin side, so admins see the
-- same logo the merchant and customers see (no new admin override
-- added here, per the request's scope — admins can already see the
-- stored value, just not edit it from this migration).
CREATE OR REPLACE FUNCTION public.admin_list_merchants()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'name', name, 'phone', phone, 'cat', cat, 'extra_cats', extra_cats, 'pct', pct, 'tier', tier,
    'redeem_pct', redeem_pct, 'redeem_pct_vip', redeem_pct_vip,
    'addr', addr, 'lat', lat, 'lng', lng, 'x', x, 'y', y,
    'photo_url', photo_url, 'photo_pending_url', photo_pending_url, 'logo_url', logo_url,
    'status', status, 'poster_printed', poster_printed, 'warns', warns,
    'pending_name', pending_name, 'pending_addr', pending_addr,
    'page_blurb', page_blurb, 'page_enabled', page_enabled,
    'created_at', extract(epoch from created_at) * 1000
  ) order by created_at), '[]'::jsonb) into r
  from public.merchants;
  return r;
end; $function$;


-- =====================================================================
-- HOW TO RUN THIS
-- =====================================================================
-- 1. Read through the whole file above — nothing here has been run yet.
-- 2. In the Supabase dashboard for this project (lqbhfkowqaqlgcrdybvv),
--    open SQL Editor → New query, paste this entire file, and run it.
--    (Or, if you use the Supabase CLI locally: `supabase db execute
--    --file tripoli-points-merchant-logo-migration.sql` against this
--    project, or add it as a numbered migration via `supabase
--    migration new` and `supabase db push`.)
-- 3. This is additive only (new column, new function, three functions
--    replaced with an identical body plus one new JSON key) — it does
--    not drop or rename anything, and existing rows simply get
--    logo_url = NULL until a merchant uploads a logo.
-- 4. After running it, the matching app code in this PR (branch
--    feature/merchant-logo-persistence) will start saving/reading
--    logo_url through merchant_set_logo. Nothing in the app calls
--    merchant_set_logo until this migration has been applied, so it
--    is safe to merge this migration first and the code PR second
--    (or the reverse — the RPC call will just fail gracefully with
--    the existing "تعذّر حفظ الشعار على الخادم" toast until the
--    migration is applied).
-- =====================================================================
