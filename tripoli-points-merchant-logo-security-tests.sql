-- =====================================================================
-- Negative security tests for public.merchant_set_logo
-- =====================================================================
-- These prove, against a real Postgres engine, that:
--   1. A merchant with the correct PIN can only ever update their OWN
--      logo_url — there is no way to target another merchant's row.
--   2. An unauthenticated / wrong-PIN caller cannot change ANY
--      merchant's logo, including their own if they don't know the PIN.
--   3. The function runs as the low-privilege `anon` role (the role
--      this app's client actually uses via its publishable key), not
--      as a superuser, matching how the real client calls it.
--
-- I ran this exact script against an isolated, throwaway local
-- Postgres instance seeded with a copy of the merchants table shape
-- and two test merchants — NOT against the real Supabase project. See
-- the PR description / report for the full console output. Re-run it
-- yourself (in the Supabase SQL editor against a branch, or anywhere
-- else) for independent verification before approving the migration.
--
-- Note on structure: every merchant_set_logo(...) call below runs
-- "set role anon" first, matching exactly how the real client calls
-- it (through the anon key, not as a superuser). The verification
-- SELECTs that follow each call run as the normal (admin) role,
-- because in production you'd check real state as an admin/via the
-- dashboard, not through the app's own restricted role — the anon
-- role correctly cannot SELECT the merchants table directly at all
-- (no RLS policies grant it that), which is itself a good sign.
--
-- Fixtures expected (see tripoli-points-merchant-logo-migration.sql's
-- companion setup script, or substitute your own two merchants+PINs):
--   Merchant A: phone '71111111', PIN '1234', id 11111111-...-111111111111
--   Merchant B: phone '72222222', PIN '5678', id 22222222-...-222222222222
-- =====================================================================

\echo '--- Baseline: both merchants start with no logo ---'
select id, phone, logo_url from public.merchants order by phone;

\echo '--- Test 1: Merchant A saves their OWN logo with the CORRECT pin -> should succeed ---'
set role anon;
select public.merchant_set_logo('71111111', '1234', 'data:image/png;base64,AAA_MERCHANT_A_LOGO');
reset role;
select id, phone, logo_url from public.merchants where phone = '71111111';
-- EXPECT: {"ok": true, "logo_url": "data:image/png;base64,AAA_MERCHANT_A_LOGO"}, row updated.

\echo '--- Test 2 (the attack from the review): there is no merchant-id parameter at all any more, ---'
\echo '--- so a caller authenticated as Merchant A structurally cannot name Merchant B as the target. ---'
\echo '--- Call again with Merchant As own credentials and confirm Merchant B is still untouched. ---'
set role anon;
select public.merchant_set_logo('71111111', '1234', 'data:image/png;base64,ATTACK_ATTEMPT');
reset role;
select id, phone, logo_url from public.merchants where phone = '72222222';
-- EXPECT: Merchant B (72222222) logo_url is still NULL — untouched by any call authenticated as A.

\echo '--- Test 3: caller claims to be Merchant B but supplies Merchant As PIN -> should fail, B untouched ---'
set role anon;
select public.merchant_set_logo('72222222', '1234', 'data:image/png;base64,SHOULD_NOT_APPEAR');
reset role;
select id, phone, logo_url from public.merchants where phone = '72222222';
-- EXPECT: {"ok": false, "reason": "wrong_pin"}, Merchant Bs logo_url still NULL.

\echo '--- Test 4: unauthenticated caller, a phone number that does not exist -> should fail, no leak ---'
set role anon;
select public.merchant_set_logo('70000000', '0000', 'data:image/png;base64,SHOULD_NOT_APPEAR');
reset role;
select count(*) as total_merchants from public.merchants;
-- EXPECT: {"ok": false, "reason": "wrong_pin"} — the SAME generic reason as an existing phone
-- with a wrong PIN, so a caller cannot tell "not a merchant" from "wrong PIN". Count unchanged.

\echo '--- Test 5: empty/blank pin -> should fail ---'
set role anon;
select public.merchant_set_logo('72222222', '', 'data:image/png;base64,SHOULD_NOT_APPEAR');
reset role;
select id, phone, logo_url from public.merchants where phone = '72222222';
-- EXPECT: {"ok": false, "reason": "wrong_pin"}, Merchant B still untouched.

\echo '--- Test 6: Merchant B saves their OWN logo with their OWN correct pin -> should succeed ---'
set role anon;
select public.merchant_set_logo('72222222', '5678', 'data:image/png;base64,BBB_MERCHANT_B_LOGO');
reset role;
select id, phone, logo_url from public.merchants where phone = '72222222';
-- EXPECT: {"ok": true, ...}, Merchant Bs logo_url is now BBB_MERCHANT_B_LOGO.

\echo '--- Test 7: removing a logo (p_logo_url = NULL) with the correct pin -> clears only that row ---'
set role anon;
select public.merchant_set_logo('71111111', '1234', null);
reset role;
select id, phone, logo_url from public.merchants order by phone;
-- EXPECT: Merchant A (71111111) logo_url is now NULL (client shows the Tripoli Points
-- fallback), Merchant B (72222222) still has BBB_MERCHANT_B_LOGO, untouched by As removal.

\echo '--- Test 8 (comparison only, demonstrates the vulnerability that was fixed): a function kept ---'
\echo '--- under a different name in this throwaway database only, taking a raw merchant id with no ---'
\echo '--- identity check (the shape the FIRST draft of merchant_set_logo had), DOES let anyone ---'
\echo '--- overwrite any merchant logo just by knowing their uuid. Not part of the migration. ---'
set role anon;
select public.merchant_set_logo_OLD_INSECURE('22222222-2222-2222-2222-222222222222', 'data:image/png;base64,TOTALLY_UNAUTHORIZED_OVERWRITE');
reset role;
select id, phone, logo_url from public.merchants where phone = '72222222';
-- EXPECT (showing the OLD bug, for contrast only): this SUCCEEDS and overwrites Merchant Bs
-- logo with zero authorization — exactly what the shipped merchant_set_logo cannot do, since
-- it never accepts a merchant id from the caller at all.
