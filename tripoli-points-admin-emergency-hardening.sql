-- =====================================================================
-- Tripoli Points — EMERGENCY HARDENING (proposal only, NOT executed)
-- =====================================================================
-- This is a SEPARATE, OPTIONAL-BUT-URGENT proposal, split out from the
-- merchant-logo-persistence migration on purpose: it touches admin RPCs
-- that are outside that PR's scope, and the user asked to "report
-- findings and proposed implementation separately before changing
-- production" — this file is exactly that proposal, not an action.
-- NOTHING IN THIS FILE HAS BEEN RUN. It is not referenced by, and does
-- not depend on, the merchant-logo-persistence migration or PR #3.
--
-- WHAT THIS FIXES
-- ----------------
-- Several of the most destructive admin_* RPCs exist as TWO overloads
-- in the live database: an old, fully insecure version with no
-- authorization check at all, and a newer version that DOES check the
-- caller is a primary admin (some also re-verify the admin's own PIN).
-- The app's client code (index.html) only ever calls the newer,
-- checked overload — but Postgres does not "replace" a function when a
-- new overload with a different argument list is added; both versions
-- stay live side by side. Because every one of these functions is
-- granted EXECUTE to the `anon` role (the role the public anon/
-- publishable key uses), anyone who has that key — which is public, by
-- design, embedded in the client — can simply call the OLD overload
-- directly (bypassing the UI, the newer checked overload, and the
-- client entirely) and it will carry out the destructive action with
-- ZERO authorization. This completely undermines the newer, "fixed"
-- versions: having a secure overload next to an insecure one with the
-- same effect is equivalent to having no check at all.
--
-- Confirmed via has_function_privilege('anon', <oid>, 'EXECUTE') = true
-- for every function this script drops, as of this review.
--
-- Also included: several leftover debug/test admin functions
-- (admin_delete_merchant_test2/6/7, admin_force_delete_merchant_test2/6)
-- that serve no product purpose, are not called anywhere in index.html,
-- are also EXECUTE-granted to anon, and in two cases (_test2, _test6)
-- only perform a PARTIAL delete (e.g. deleting rows from topup_orders
-- but not the merchant itself) — i.e. they are not even "safe no-ops",
-- they are half-finished destructive actions left reachable in
-- production. These should simply not exist any more.
--
-- WHAT THIS DOES NOT TOUCH
-- ------------------------
-- The NEWER overload of each function below (the one the client
-- actually calls, e.g. admin_delete_merchant(p_merchant_id, p_admin_id))
-- is left completely untouched by this file. This script only removes
-- the old/insecure/leftover versions sitting next to them. It also does
-- not change admin_verify_pin, admin_set_merchant_status, or the other
-- admin_* functions that take no admin credential at all and have no
-- newer, checked counterpart yet — those need a design decision (new
-- checked versions written, old ones retired) rather than a drop, and
-- are listed in the full report as a separate, larger follow-up, not
-- bundled into this emergency-cleanup script.
--
-- HOW TO VERIFY BEFORE RUNNING
-- -----------------------------
-- For each DROP below, you can first confirm anon still has EXECUTE on
-- the OLD overload (proving the vulnerability is live) by running, e.g.:
--   select has_function_privilege('anon', 'public.admin_delete_merchant(uuid)', 'EXECUTE');
-- -> true means this is exploitable right now; dropping it removes that.
--
-- DEPENDENCY CHECK (done before finalizing this file, re-confirmed on
-- the current schema, nothing executed beyond read-only catalog
-- queries):
--   1. Re-pulled the exact current signature + oid + anon-EXECUTE state
--      of every function this file drops (pg_get_function_identity_
--      arguments + has_function_privilege) -- all match what's below.
--   2. pg_depend: zero catalog-level dependents (no view, default,
--      index, or constraint references any of these oids).
--   3. pg_trigger: zero triggers use any of these as a trigger function.
--   4. Searched every OTHER function's body (pg_proc.prosrc) in this
--      schema for a call to any of these by name -- zero matches. Only
--      the live client (index.html) calls the checked overloads, and
--      only ever with named parameters (p_admin_id, and p_pin for the
--      wipe function) -- PostgREST's named-parameter overload
--      resolution means those calls can only ever match the newer,
--      checked overload, never the one being dropped here, regardless
--      of which overloads exist. Dropping the old ones changes no
--      client-visible behavior.
-- Re-run these same checks yourself against the live schema right
-- before applying this file, in case anything has changed since this
-- review.
--
-- =====================================================================

-- 1) admin_delete_merchant(uuid) — the OLD overload, zero checks at all.
--    (NOT admin_delete_merchant(uuid, uuid), which stays — that's the
--    one the client calls, and it is left untouched.)
DROP FUNCTION IF EXISTS public.admin_delete_merchant(uuid);

-- 2) admin_force_delete_merchant(uuid) — if a zero-arg-admin-check
--    overload exists; the client-called admin_force_delete_merchant
--    (uuid, uuid) stays. (Review confirmed only the checked 2-arg
--    overload currently exists for this one — this line is a no-op
--    IF FOUND safety net in case that changes before this runs.)
DROP FUNCTION IF EXISTS public.admin_force_delete_merchant(uuid);

-- 3) admin_delete_customer(text) — the OLD overload, zero checks.
--    admin_delete_customer(text, uuid) is the checked one and stays.
DROP FUNCTION IF EXISTS public.admin_delete_customer(text);

-- 4) admin_wipe_all_data() — the OLD zero-argument overload that
--    unconditionally truncates merchants + customers with NO check of
--    any kind. admin_wipe_all_data(p_admin_id uuid, p_pin text), which
--    re-verifies the caller is a primary admin AND knows that admin's
--    own PIN, is the one the client calls and stays untouched.
--    This is the single most dangerous function in this list: as it
--    stands today, ANY holder of the public anon key can wipe every
--    merchant and customer in production with one call and no PIN.
DROP FUNCTION IF EXISTS public.admin_wipe_all_data();

-- 5)-9) Leftover debug/test functions. Not referenced anywhere in
--    index.html, not part of any documented feature, EXECUTE-granted to
--    anon, and (for the two "test2"/"test6" force-delete variants) only
--    partially implemented destructive actions.
DROP FUNCTION IF EXISTS public.admin_delete_merchant_test2(uuid);
DROP FUNCTION IF EXISTS public.admin_delete_merchant_test6(uuid);
DROP FUNCTION IF EXISTS public.admin_delete_merchant_test7(uuid);
DROP FUNCTION IF EXISTS public.admin_force_delete_merchant_test2(uuid, uuid);
DROP FUNCTION IF EXISTS public.admin_force_delete_merchant_test6(uuid, uuid);

-- =====================================================================
-- HOW TO RUN THIS (once you've approved it — nothing above has run)
-- =====================================================================
-- 1. This is independent of PR #3 / the logo-persistence migration —
--    it can be run before, after, or in the same sitting as that one,
--    whenever you're ready, since it only removes already-superseded
--    old overloads and dead test code that the live client never calls.
-- 2. Recommended: run the two verification SELECTs shown above (or your
--    own) against production first, with nothing else, to see the
--    "true" result confirming the old overloads are presently
--    anon-callable — then run this file.
-- 3. After running, re-check the app (merchant delete/force-delete,
--    customer delete, admin "wipe all data") from the admin panel as a
--    primary admin to confirm those actions still work exactly as
--    before — they should, since only the OLD, never-called-by-the-
--    client overloads are removed.
-- 4. BACKUP FIRST: same as the logo-persistence migration — confirm a
--    recent backup/restore point exists (Supabase dashboard -> Database
--    -> Backups) before running this against production. This file's
--    DROPs are schema-only (no table data is touched), so the risk
--    window is narrow, but confirm anyway before any production change.
-- =====================================================================


-- =====================================================================
-- ROLLBACK — intentionally NOT included in this file
-- =====================================================================
-- Revised after review: an earlier draft of this file kept commented-
-- out CREATE OR REPLACE statements here that would recreate the old,
-- insecure overloads this file drops. Even commented out, keeping a
-- "just uncomment to undo" block inside the hardening file itself
-- blurs the line between "routine rollback" and "deliberately reopen a
-- fixed vulnerability" -- the two must never look like the same kind of
-- action.
--
-- If those old overloads ever genuinely need to come back (see the
-- "when, if ever" note below -- essentially never), the exact
-- statements to do that live in a SEPARATE, clearly-named file:
-- tripoli-points-DANGEROUS-reopen-legacy-functions.sql. It is not
-- referenced by, run by, or bundled with this file or with
-- tripoli-points-migration-rollback.sql in any way.
-- =====================================================================
