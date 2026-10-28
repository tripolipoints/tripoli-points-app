-- =====================================================================
-- Tripoli Points — Stage 2 (A) ROLLBACK
-- STATUS: DRAFT FOR REVIEW — NOT EXECUTED.
-- Removes only the two read-only functions added by
-- tripoli-points-map-light-rpc.sql. No table, row, policy or existing
-- function (including list_merchants) is touched.
-- The app falls back to list_merchants() automatically when
-- list_merchants_map() is unavailable, so this is safe to run at any time.
-- =====================================================================
drop function if exists public.merchant_media(uuid[]);
drop function if exists public.list_merchants_map();
