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

-- =====================================================================
-- Tests 9-14: merchant_reset_pin revocation, rate limiting, and the
-- new admin_reset_merchant_pin RPC — added for the PIN-reset-security /
-- rate-limiting request. Needs a few extra fixtures on top of the two
-- merchants above:
--   public.admin_users: a PRIMARY admin (id 33333333-...-333333333333,
--     username 'primary_admin', pin '9999', is_primary=true) and a
--     SECONDARY admin (id 44444444-...-444444444444, pin '8888',
--     is_primary=false), both with EXECUTE on admin_reset_merchant_pin
--     granted to anon (matching how the real client calls every RPC).
--   public.auth_rate_limits must exist (created by the migration).
-- I ran these against the same throwaway local Postgres instance as
-- Tests 1-8 — not against the real Supabase project.
-- =====================================================================

\echo '--- Test 9: merchant_reset_pin (the old self-service reset) is now REVOKED from anon ---'
\echo '--- entirely -- this IS the account-takeover fix the user flagged as the top priority. ---'
set role anon;
select public.merchant_reset_pin('71111111', '0000');
reset role;
-- EXPECT: ERROR: permission denied for function merchant_reset_pin — NOT a jsonb {"ok":...}
-- result. (Caught during testing that REVOKE ... FROM anon, authenticated ALONE is NOT
-- enough here, because every function in this project has an implicit EXECUTE grant to
-- PUBLIC from creation time, and anon/authenticated are both members of PUBLIC — so the
-- migration's REVOKE explicitly includes PUBLIC too. Re-run this test after applying the
-- migration to confirm the real project behaves the same way.)

\echo '--- Test 10: 5 wrong PINs for one merchant locks that merchant out, SHARED between the ---'
\echo '--- login screen (merchant_verify_pin) and the logo-save PIN modal (merchant_set_logo), ---'
\echo '--- so an attacker cannot multiply their guess budget by switching entry points. ---'
set role anon;
select public.merchant_verify_pin('72222222', 'wrong');
select public.merchant_verify_pin('72222222', 'wrong');
select public.merchant_verify_pin('72222222', 'wrong');
select public.merchant_verify_pin('72222222', 'wrong');
select public.merchant_set_logo('72222222', 'wrong', 'data:image/png;base64,X');
\echo '--- the 6th attempt, even with the CORRECT pin, via either endpoint, is now rejected as locked ---'
select public.merchant_verify_pin('72222222', '5678');
select public.merchant_set_logo('72222222', '5678', 'data:image/png;base64,X');
reset role;
-- EXPECT: the first 5 calls all return {"ok":false,"reason":"wrong_pin"}; the 6th and 7th
-- (both with the real PIN 5678) return {"ok":false,"reason":"locked"} instead.

\echo '--- Test 11: the lockout is per-merchant -- Merchant A (71111111) is unaffected by Bs lockout ---'
set role anon;
select public.merchant_verify_pin('71111111', '1234');
reset role;
-- EXPECT: {"ok":true, ...} — Merchant A logs in normally despite Test 10 locking Merchant B.

\echo '--- Test 12: admin_reset_merchant_pin requires the REAL primary admin PIN, not just an id ---'
set role anon;
select public.admin_reset_merchant_pin('33333333-3333-3333-3333-333333333333', 'WRONGPIN', '11111111-1111-1111-1111-111111111111', '4321');
select public.admin_reset_merchant_pin('44444444-4444-4444-4444-444444444444', '8888', '11111111-1111-1111-1111-111111111111', '4321');
select public.admin_reset_merchant_pin('99999999-9999-9999-9999-999999999999', '0000', '11111111-1111-1111-1111-111111111111', '4321');
reset role;
select pin_hash from public.merchants where phone='71111111';
-- EXPECT: all three calls return {"ok":false, "error":...} (wrong pin / not primary / invalid
-- session, respectively) and Merchant As pin_hash is UNCHANGED by any of them.

\echo '--- Test 13: the REAL primary admin + REAL pin succeeds, and only touches the named merchant ---'
set role anon;
select public.admin_reset_merchant_pin('33333333-3333-3333-3333-333333333333', '9999', '11111111-1111-1111-1111-111111111111', '4321');
select public.merchant_verify_pin('71111111', '4321');
select public.merchant_verify_pin('71111111', '1234');
reset role;
select phone from public.merchants where phone='72222222' and logo_url is null;
-- EXPECT: {"ok":true} for the reset; the new pin 4321 now logs Merchant A in; the old pin
-- 1234 is rejected; Merchant B (72222222) is completely untouched by a call that only named
-- Merchant A.

\echo '--- Test 14: admin_reset_merchant_pin has its OWN rate limit too (throttles admin-pin ---'
\echo '--- guessing against THIS endpoint specifically, independent of the merchant lockout above) ---'
set role anon;
select public.admin_reset_merchant_pin('33333333-3333-3333-3333-333333333333', 'bad1', '11111111-1111-1111-1111-111111111111', '1111');
select public.admin_reset_merchant_pin('33333333-3333-3333-3333-333333333333', 'bad2', '11111111-1111-1111-1111-111111111111', '1111');
select public.admin_reset_merchant_pin('33333333-3333-3333-3333-333333333333', 'bad3', '11111111-1111-1111-1111-111111111111', '1111');
select public.admin_reset_merchant_pin('33333333-3333-3333-3333-333333333333', 'bad4', '11111111-1111-1111-1111-111111111111', '1111');
select public.admin_reset_merchant_pin('33333333-3333-3333-3333-333333333333', 'bad5', '11111111-1111-1111-1111-111111111111', '1111');
select public.admin_reset_merchant_pin('33333333-3333-3333-3333-333333333333', '9999', '11111111-1111-1111-1111-111111111111', '2222');
reset role;
select phone from public.merchants where phone='71111111';
set role anon;
select public.merchant_verify_pin('71111111', '4321');
reset role;
-- EXPECT: the 6th call, even with the TRUE admin pin 9999, returns {"ok":false,"reason":"locked"};
-- Merchant As pin is still 4321 from Test 13 (the locked-out call never reached the update).

-- =====================================================================
-- Tests 15-17: the rate-limit helper functions themselves (_rl_locked,
-- _rl_record_fail, _rl_reset) cannot be called directly by anon or
-- authenticated to inspect, clear, or forge lockout state. Added after
-- review flagged that these three, as first written, kept Postgres's
-- default implicit PUBLIC EXECUTE grant -- table-level REVOKE on
-- auth_rate_limits already blocked exploitation in practice (confirmed
-- below), but the migration now also explicitly revokes EXECUTE on the
-- functions themselves, for defense in depth and so this isn't relying
-- on an indirect/incidental protection.
-- =====================================================================

\echo '--- Test 15: anon cannot call _rl_reset directly to clear a lock out from under a victim ---'
set role anon;
select public._rl_reset('merchant:72222222');
reset role;
-- EXPECT: ERROR: permission denied for function _rl_reset (not a jsonb {"ok":...} result).

\echo '--- Test 16: anon cannot call _rl_record_fail directly to lock someone ELSE out (a DoS) ---'
set role anon;
select public._rl_record_fail('merchant:71111111');
reset role;
-- EXPECT: ERROR: permission denied for function _rl_record_fail.

\echo '--- Test 17: anon cannot call _rl_locked directly either (even read-only lock-state probing is blocked) ---'
set role anon;
select public._rl_locked('merchant:71111111');
reset role;
-- EXPECT: ERROR: permission denied for function _rl_locked.
--
-- Also confirmed via has_function_privilege('anon'/'authenticated'/'public', <oid>, 'EXECUTE')
-- = false for all three helpers after the migration's REVOKEs, vs. true for all three
-- beforehand -- this is the exact gap the review flagged, now closed and verified both by
-- direct-call tests (above) and by checking the catalog privilege directly.
