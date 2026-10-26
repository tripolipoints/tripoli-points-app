-- =====================================================================
-- Tripoli Points — ROLLBACK for tripoli-points-merchant-logo-migration.sql
-- =====================================================================
-- NOT EXECUTED. This file exists so a rollback can be applied in
-- seconds if something goes wrong after approval, without having to
-- improvise reverse-DDL under pressure. It restores every function this
-- migration touches to its EXACT current (pre-migration) production
-- definition, pulled via pg_get_functiondef() immediately before writing
-- this file -- not retyped from memory or from the PR's own history.
--
-- WHAT THIS DOES: restores merchant_verify_pin, list_merchants,
-- admin_list_merchants, and merchant_reset_pin's grants to their exact
-- current production state; drops everything the migration newly adds
-- (merchant_set_logo, admin_reset_merchant_pin, the auth_rate_limits
-- table and its three helper functions, the logo_url column).
--
-- WHAT THIS DOES NOT DO: restore any DATA. If merchants have already
-- saved logos, used admin_reset_merchant_pin, or hit the rate limiter
-- before a rollback is needed, dropping logo_url/auth_rate_limits loses
-- that data permanently. For that reason step 0 (a real backup) below
-- is not optional -- run it, or confirm Supabase's own backups cover
-- this window, before applying the migration at all.
-- =====================================================================

-- Restore merchant_verify_pin to its exact current production shape
-- (no logo_url key, no rate limiting) -- pulled via pg_get_functiondef
-- immediately before writing this file.
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
    'poster_printed', r.poster_printed, 'warns', r.warns,
    'redeem_pct', r.redeem_pct, 'redeem_pct_vip', r.redeem_pct_vip,
    'pending_name', r.pending_name, 'pending_addr', r.pending_addr));
end; $function$;

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
    'photo_url', photo_url, 'status', status,
    'page_blurb', page_blurb, 'page_enabled', page_enabled
  )), '[]'::jsonb) into r
  from public.merchants where status = 'active';
  return r;
end; $function$;

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
    'photo_url', photo_url, 'photo_pending_url', photo_pending_url,
    'status', status, 'poster_printed', poster_printed, 'warns', warns,
    'pending_name', pending_name, 'pending_addr', pending_addr,
    'page_blurb', page_blurb, 'page_enabled', page_enabled,
    'created_at', extract(epoch from created_at) * 1000
  ) order by created_at), '[]'::jsonb) into r
  from public.merchants;
  return r;
end; $function$;

-- Restore merchant_reset_pin's grants to exactly what production has
-- today (anon, authenticated, service_role, PUBLIC all EXECUTE) --
-- NOTE: this re-opens the account-takeover hole this whole PR exists to
-- close. Only use this rollback step if you are reverting the ENTIRE
-- migration, e.g. because of an unrelated production incident, and
-- understand that doing so brings the vulnerability back until the
-- migration (or an equivalent fix) is reapplied.
GRANT EXECUTE ON FUNCTION public.merchant_reset_pin(text, text) TO PUBLIC, anon, authenticated, service_role;

-- Drop everything the migration newly introduced. DATA LOSS WARNING:
-- this discards any logo_url values merchants saved and any
-- auth_rate_limits history, permanently, the moment it runs.
DROP FUNCTION IF EXISTS public.merchant_set_logo(text, text, text);
DROP FUNCTION IF EXISTS public.admin_reset_merchant_pin(uuid, text, uuid, text);
DROP FUNCTION IF EXISTS public._rl_locked(text);
DROP FUNCTION IF EXISTS public._rl_record_fail(text);
DROP FUNCTION IF EXISTS public._rl_reset(text);
DROP TABLE IF EXISTS public.auth_rate_limits;
ALTER TABLE public.merchants DROP COLUMN IF EXISTS logo_url;

-- =====================================================================
-- HOW TO USE THIS
-- =====================================================================
-- Only after the migration has actually been applied and something
-- needs reverting. Review the data-loss warnings above first -- in
-- particular, decide whether re-opening merchant_reset_pin is
-- acceptable for however long until a fix is reapplied, and whether any
-- logo_url / auth_rate_limits data saved since the migration ran is
-- safe to discard (or needs exporting first, e.g. `select id, phone,
-- logo_url from public.merchants where logo_url is not null;`).
-- =====================================================================
