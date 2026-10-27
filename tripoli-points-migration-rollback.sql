-- =====================================================================
-- Tripoli Points — FUNCTIONAL ROLLBACK for
-- tripoli-points-merchant-logo-migration.sql
-- =====================================================================
-- NOT EXECUTED. Revised after review: the first draft of this file
-- restored merchant_reset_pin's EXECUTE grants (including PUBLIC and
-- anon) as part of a routine rollback -- meaning rolling back the logo
-- feature for an unrelated reason (a bug, a performance issue, anything
-- not security-related) would have silently reopened the
-- account-takeover hole this whole PR exists to close. That's fixed:
-- this file now rolls back ONLY the logo/rate-limiting FEATURE and
-- leaves every security fix in place. It does not touch
-- merchant_reset_pin's privileges at all, in either direction -- running
-- this file cannot change whether that function is callable.
--
-- If you ever need to go further and literally restore the OLD,
-- insecure merchant_reset_pin privileges too -- which we recommend
-- against, and which should never be needed for an ordinary functional
-- rollback -- that is a SEPARATE, explicit, heavily-guarded action in
-- its own file: tripoli-points-DANGEROUS-reopen-legacy-functions.sql.
-- Never run that file as part of "rolling back the logo feature"; see
-- its own header for when (if ever) it's the right call.
--
-- WHAT THIS DOES: restores merchant_verify_pin, list_merchants, and
-- admin_list_merchants to their exact current (pre-migration) production
-- definitions (pulled via pg_get_functiondef() immediately before
-- writing this file -- not retyped from memory); drops everything the
-- migration newly adds for the logo/rate-limiting feature
-- (merchant_set_logo, admin_reset_merchant_pin, the auth_rate_limits
-- table and its three helper functions, the logo_url column).
--
-- WHAT THIS DELIBERATELY DOES NOT DO: touch merchant_reset_pin's
-- privileges. Before AND after this rollback runs, merchant_reset_pin
-- stays revoked from PUBLIC/anon/authenticated/service_role -- the
-- account-takeover fix survives a logo-feature rollback. A verification
-- query at the end confirms this explicitly, so running this file tells
-- you immediately if that's somehow not the case.
--
-- WHAT THIS DOES NOT DO: restore any DATA. If merchants have already
-- saved logos, used admin_reset_merchant_pin, or hit the rate limiter
-- before a rollback is needed, dropping logo_url/auth_rate_limits loses
-- that data permanently. For that reason, confirm a real backup/restore
-- point (Supabase dashboard -> Database -> Backups) before applying the
-- migration at all -- not optional.
-- =====================================================================

-- Restore merchant_verify_pin to its exact current production shape
-- (no logo_url key, no rate limiting).
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

-- Drop everything the migration newly introduced FOR THE LOGO/RATE-
-- LIMITING FEATURE ONLY. DATA LOSS WARNING: this discards any logo_url
-- values merchants saved and any auth_rate_limits history, permanently,
-- the moment it runs. It does NOT touch merchant_reset_pin.
DROP FUNCTION IF EXISTS public.merchant_set_logo(text, text, text);
DROP FUNCTION IF EXISTS public.admin_reset_merchant_pin(uuid, text, uuid, text);
DROP FUNCTION IF EXISTS public._rl_locked(text);
DROP FUNCTION IF EXISTS public._rl_record_fail(text);
DROP FUNCTION IF EXISTS public._rl_reset(text);
DROP TABLE IF EXISTS public.auth_rate_limits;
ALTER TABLE public.merchants DROP COLUMN IF EXISTS logo_url;

-- SAFETY CHECK: confirms the account-takeover fix is still in place
-- after this rollback. If this returns anything other than all-false,
-- STOP and investigate before telling anyone the rollback is "done" --
-- it means something outside this file re-granted access.
select
  has_function_privilege('anon', 'public.merchant_reset_pin(text,text)', 'EXECUTE') as anon_can_reset_pin_should_be_false,
  has_function_privilege('authenticated', 'public.merchant_reset_pin(text,text)', 'EXECUTE') as authenticated_can_reset_pin_should_be_false,
  has_function_privilege('public', 'public.merchant_reset_pin(text,text)', 'EXECUTE') as public_can_reset_pin_should_be_false;

-- =====================================================================
-- HOW TO USE THIS
-- =====================================================================
-- Only after the migration has actually been applied and the LOGO
-- FEATURE specifically needs reverting -- a bug, a performance problem,
-- anything unrelated to the security fixes. Review the data-loss
-- warning above first, and export logo_url / auth_rate_limits data
-- first if it needs to survive the rollback, e.g.:
--   select id, phone, logo_url from public.merchants where logo_url is not null;
-- Run the safety-check SELECT at the end (it runs automatically as the
-- last statement) and confirm all three columns read false before
-- considering the rollback complete.
-- =====================================================================
