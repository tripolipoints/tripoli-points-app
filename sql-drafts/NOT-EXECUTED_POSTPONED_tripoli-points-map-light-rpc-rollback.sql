-- #####################################################################
-- ##  NOT EXECUTED — POSTPONED (decision 2026-10-28)                  ##
-- ##  Kept for future review only. Do NOT run against any database.   ##
-- ##  Image management will be redesigned as part of a dedicated      ##
-- ##  admin-controlled media approval system; database permissions,  ##
-- ##  merchant IDs, column types and security will be reviewed        ##
-- ##  separately before production launch.                           ##
-- #####################################################################
-- =====================================================================
-- Tripoli Points — Stage 2 (A) ROLLBACK
-- STATUS: POSTPONED DRAFT — NOT EXECUTED. Do not run.
-- Removes only the two read-only functions added by
-- NOT-EXECUTED_POSTPONED_tripoli-points-map-light-rpc.sql. No table, row, policy or existing
-- function (including list_merchants) is touched.
-- (The app does not use these functions; list_merchants() remains the only
-- directory source.)
-- =====================================================================
drop function if exists public.merchant_media(uuid[]);
drop function if exists public.list_merchants_map();
