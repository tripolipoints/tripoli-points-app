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
--
-- SECURITY: merchant_set_logo (section 2 below) was revised after
-- review to resolve the merchant from a verified (phone, PIN) pair
-- server-side, instead of trusting a client-supplied merchant id —
-- see the comment on that function for the full explanation, and
-- tripoli-points-merchant-logo-security-tests.sql (same folder) for
-- negative tests proving one merchant cannot touch another's logo and
-- an unauthenticated/wrong-PIN caller cannot touch anyone's logo.
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
-- 2) New RPC: public.merchant_set_logo(p_phone, p_pin, p_logo_url)
-- ---------------------------------------------------------------------
-- REVISED after security review. The first draft of this function took
-- a client-supplied p_merchant_id and updated that row directly — the
-- same pattern every other merchant_* write RPC in this app already
-- uses (merchant_submit_photo, merchant_gallery_add, merchant_reset_pin,
-- etc.), none of which verify the caller owns the id they pass in. That
-- was flagged as a real vulnerability for this new function and is
-- fixed here: merchant_set_logo no longer accepts a merchant id from
-- the client at all. Instead it takes the SAME (p_phone, p_pin) pair
-- used at login, verifies them itself with the same crypt()/pin_hash
-- check merchant_verify_pin already uses, resolves the merchant row
-- from that verified phone, and only ever updates that row. There is
-- no code path in this function that can act on any merchant other
-- than the one whose PIN was just correctly supplied — a merchant id
-- is never read from the request at all, so it cannot be spoofed.
--
-- Used for both saving a new logo and removing one: call with
-- p_logo_url = NULL (or '') to remove.
--
-- On any failure (unknown phone, wrong PIN, or no pin set) this
-- returns the SAME generic {ok:false, reason:'wrong_pin'} regardless
-- of which case it was, so a caller cannot use this function to probe
-- which phone numbers are registered merchants.
--
-- IMPORTANT — this is a narrow, scoped fix for this one new function.
-- It does NOT fix the same missing-ownership-check pattern that exists
-- today in merchant_submit_photo, merchant_gallery_add,
-- merchant_reset_pin, and other existing merchant_* RPCs — those were
-- out of scope for this request and are flagged separately in the PR
-- description and the accompanying report, not silently changed here.
CREATE OR REPLACE FUNCTION public.merchant_set_logo(p_phone text, p_pin text, p_logo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants;
begin
  select * into r from public.merchants where phone = p_phone;
  if r is null then return jsonb_build_object('ok', false, 'reason', 'wrong_pin'); end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  update public.merchants set logo_url = nullif(p_logo_url, '')
  where id = r.id returning * into r;
  return jsonb_build_object('ok', true, 'logo_url', r.logo_url);
end; $function$;

-- Explicit, minimal EXECUTE grants — matching exactly what every other
-- merchant_* RPC in this project already has (anon, authenticated,
-- service_role; see the security review in the PR for the query used
-- to confirm this), and revoking the PUBLIC grant Postgres adds to a
-- function by default, so this isn't reachable any more broadly than
-- the rest of the app's RPCs.
REVOKE ALL ON FUNCTION public.merchant_set_logo(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merchant_set_logo(text, text, text) TO anon, authenticated, service_role;


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


-- ---------------------------------------------------------------------
-- 4) Brute-force protection: public.auth_rate_limits + helper functions
-- ---------------------------------------------------------------------
-- NEW infrastructure added in this pass, requested separately (rate
-- limiting / brute-force protection for PIN verification and logo
-- updates). Nothing in the app called anything resembling this before —
-- there was no lockout mechanism of any kind for PIN attempts.
--
-- One shared table, keyed by a short text key (e.g. 'merchant:<phone>'
-- or 'admin:<admin id>'), counting consecutive failures and recording a
-- lockout expiry. Not exposed to anon/authenticated at all — it is only
-- ever touched from inside other SECURITY DEFINER functions (which run
-- as the functions' owner, so no explicit grant is needed for THEM to
-- read/write it; a function's owner always has implicit rights on their
-- own objects even under REVOKE ALL FROM PUBLIC). There is no code path
-- that lets a client read or write this table directly.
CREATE TABLE IF NOT EXISTS public.auth_rate_limits (
  key          text primary key,
  fail_count   integer not null default 0,
  locked_until timestamptz,
  updated_at   timestamptz not null default now()
);
REVOKE ALL ON TABLE public.auth_rate_limits FROM PUBLIC;

-- SECURITY NOTE (added after review): _rl_locked / _rl_record_fail /
-- _rl_reset below are plain functions (SECURITY INVOKER, Postgres's
-- default — none of the three declare SECURITY DEFINER), so calling
-- one directly runs it as the CALLER's own role, not as the function
-- owner. Today that means a direct anon call still fails, because it
-- hits the REVOKE on auth_rate_limits above before touching any row —
-- verified empirically: `set role anon; select
-- public._rl_reset('merchant:72222222');` raises `permission denied
-- for table auth_rate_limits`, and the same for _rl_record_fail and
-- _rl_locked (see tripoli-points-merchant-logo-security-tests.sql,
-- Tests 15-17). But relying ONLY on that indirect, table-level denial
-- is fragile: every one of these three functions still carries
-- Postgres's default PUBLIC EXECUTE grant today (confirmed via
-- has_function_privilege), so if anything ever grants anon/
-- authenticated any privilege on auth_rate_limits in the future — even
-- for an unrelated reason — these three become directly callable again
-- with no function-level check of their own. The REVOKEs below close
-- that off explicitly, as defense in depth, matching the pattern this
-- project already needed once for merchant_reset_pin: never rely on an
-- indirect/implicit denial when an explicit REVOKE is just as cheap.
-- (REVOKEs placed right after each CREATE below, same as everywhere
-- else in this file — a REVOKE ON FUNCTION must follow its CREATE.)

-- Returns true while a key is currently locked out.
CREATE OR REPLACE FUNCTION public._rl_locked(p_key text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1 from public.auth_rate_limits
    where key = p_key and locked_until is not null and locked_until > now()
  );
$function$;
REVOKE ALL ON FUNCTION public._rl_locked(text) FROM PUBLIC;

-- Records one failed attempt for a key; after 5 consecutive failures,
-- locks that key out for 15 minutes. A failure recorded while already
-- locked does not extend the lock further (so a flood of retries during
-- a lockout doesn't itself become a denial-of-service against the
-- legitimate owner re-trying after the window passes).
CREATE OR REPLACE FUNCTION public._rl_record_fail(p_key text)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  insert into public.auth_rate_limits(key, fail_count, updated_at)
    values (p_key, 1, now())
  on conflict (key) do update set
    fail_count = case
      when public.auth_rate_limits.locked_until is not null and public.auth_rate_limits.locked_until > now()
        then public.auth_rate_limits.fail_count
      else public.auth_rate_limits.fail_count + 1
    end,
    updated_at = now()
  returning fail_count into n;
  if n >= 5 then
    update public.auth_rate_limits set locked_until = now() + interval '15 minutes' where key = p_key;
  end if;
end; $function$;
REVOKE ALL ON FUNCTION public._rl_record_fail(text) FROM PUBLIC;

-- Clears a key's failure count/lock entirely, called on any successful
-- verification so a legitimate login right after a few mistypes doesn't
-- carry a stale count toward a future lockout.
CREATE OR REPLACE FUNCTION public._rl_reset(p_key text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public'
AS $function$
  delete from public.auth_rate_limits where key = p_key;
$function$;
REVOKE ALL ON FUNCTION public._rl_reset(text) FROM PUBLIC;


-- ---------------------------------------------------------------------
-- 5) merchant_verify_pin and merchant_set_logo: wired to rate limiting
-- ---------------------------------------------------------------------
-- Both share the SAME lockout key, 'merchant:<phone>' — a merchant's
-- login attempts and their logo-save PIN attempts count toward the same
-- budget. This is deliberate: without it, an attacker could use the
-- login screen for 4 guesses, then switch to the logo-save PIN modal
-- for 4 more, and so on, multiplying their guess budget by however many
-- PIN-gated entry points exist. A shared key closes that.
--
-- Behavior otherwise unchanged from the versions above (section 2 and
-- the original migration), with one addition: a locked-out key returns
-- {"ok": false, "reason": "locked"} immediately, without even checking
-- the submitted PIN, so a lockout cannot be distinguished-bypassed by a
-- correct guess made during the lockout window.
CREATE OR REPLACE FUNCTION public.merchant_verify_pin(p_phone text, p_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants; rl_key text := 'merchant:' || p_phone;
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.merchants where phone = p_phone;
  if r is null then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'not_found');
  end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl_reset(rl_key);
  return jsonb_build_object('ok', true, 'merchant', jsonb_build_object(
    'id', r.id, 'name', r.name, 'phone', r.phone, 'status', r.status, 'cat', r.cat, 'pct', r.pct,
    'tier', r.tier, 'addr', r.addr, 'photo_url', r.photo_url, 'photo_pending_url', r.photo_pending_url,
    'logo_url', r.logo_url,
    'poster_printed', r.poster_printed, 'warns', r.warns,
    'redeem_pct', r.redeem_pct, 'redeem_pct_vip', r.redeem_pct_vip,
    'pending_name', r.pending_name, 'pending_addr', r.pending_addr));
end; $function$;

CREATE OR REPLACE FUNCTION public.merchant_set_logo(p_phone text, p_pin text, p_logo_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants; rl_key text := 'merchant:' || p_phone;
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.merchants where phone = p_phone;
  if r is null then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl_reset(rl_key);
  update public.merchants set logo_url = nullif(p_logo_url, '')
  where id = r.id returning * into r;
  return jsonb_build_object('ok', true, 'logo_url', r.logo_url);
end; $function$;

REVOKE ALL ON FUNCTION public.merchant_set_logo(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.merchant_set_logo(text, text, text) TO anon, authenticated, service_role;


-- ---------------------------------------------------------------------
-- 6) New RPC: public.admin_reset_merchant_pin(p_admin_id, p_pin, p_merchant_id, p_new_pin)
-- ---------------------------------------------------------------------
-- Replaces merchant self-service PIN reset (public.merchant_reset_pin,
-- revoked from anon/authenticated in section 7 below) with an admin-
-- mediated flow: the PRIMARY admin, after verifying the merchant's
-- identity by some out-of-band means (e.g. support chat + the merchant
-- recognizing their own registered shop name/address), sets a new PIN
-- for that merchant from the admin panel.
--
-- Mirrors the one existing admin function that already re-verifies the
-- caller's own admin credentials per call (admin_wipe_all_data(p_admin_id,
-- p_pin)) rather than just trusting a caller-supplied admin id: this
-- function independently re-checks that p_admin_id resolves to an
-- admin_users row, that row has is_primary = true, AND crypt(p_pin, ...)
-- matches that row's own pin_hash — so calling this still requires
-- knowing a real primary admin's PIN, not just their id (ids are not
-- secret — they are already sent client → server on every admin action
-- today, e.g. S.adminInfo.id).
--
-- Rate-limited on its own key ('admin:<admin id>'), so repeated wrong
-- admin-PIN guesses against this endpoint lock out the same way merchant
-- PIN guesses do. On success, also clears any lockout the merchant's OLD
-- pin may have accumulated, so they can log in immediately with the new
-- one instead of being told to wait out a stale lock.
CREATE OR REPLACE FUNCTION public.admin_reset_merchant_pin(p_admin_id uuid, p_pin text, p_merchant_id uuid, p_new_pin text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a public.admin_users; ok boolean; err text; rl_key text := 'admin:' || p_admin_id::text; mphone text;
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  if p_new_pin is null or length(p_new_pin) <> 4 then
    return jsonb_build_object('ok', false, 'error', 'رمز الحماية يجب أن يكون 4 أرقام');
  end if;
  select * into a from public.admin_users where id = p_admin_id;
  ok := a.id is not null and coalesce(a.is_primary, false) and a.pin_hash is not null and crypt(p_pin, a.pin_hash) = a.pin_hash;
  if not ok then
    perform public._rl_record_fail(rl_key);
    err := case
      when a.id is null then 'جلسة غير صالحة، أعد تسجيل الدخول'
      when not coalesce(a.is_primary, false) then 'هذا الإجراء مسموح للأدمن الأساسي فقط'
      else 'رمز الإدارة غير صحيح'
    end;
    return jsonb_build_object('ok', false, 'error', err);
  end if;
  perform public._rl_reset(rl_key);
  select phone into mphone from public.merchants where id = p_merchant_id;
  if mphone is null then return jsonb_build_object('ok', false, 'error', 'المحل غير موجود'); end if;
  update public.merchants set pin_hash = crypt(p_new_pin, gen_salt('bf')) where id = p_merchant_id;
  perform public._rl_reset('merchant:' || mphone);
  return jsonb_build_object('ok', true);
end; $function$;

REVOKE ALL ON FUNCTION public.admin_reset_merchant_pin(uuid, text, uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reset_merchant_pin(uuid, text, uuid, text) TO anon, authenticated, service_role;


-- ---------------------------------------------------------------------
-- 7) Close the merchant_reset_pin account-takeover hole
-- ---------------------------------------------------------------------
-- public.merchant_reset_pin(p_phone, p_new_pin) resets a merchant's PIN
-- given ONLY their phone number — zero verification of any kind. Any
-- caller with the public anon key can take over any merchant account
-- today by calling this directly (the client's own "forgot PIN" screen
-- happened to call it too, which is how this was found).
--
-- We REVOKE EXECUTE rather than DROP the function, so no stored
-- procedure disappears out from under anything that might reference it
-- by name, and so this one-line change is trivially reversible if ever
-- needed — but after this runs, neither anon nor authenticated can call
-- it at all, which is the only privilege level the client ever uses.
--
-- IMPORTANT: like every other function in this project (confirmed via
-- has_function_privilege), merchant_reset_pin's EXECUTE was never
-- explicitly revoked from the implicit PUBLIC grant Postgres gives a
-- function by default — and anon/authenticated are both members of
-- PUBLIC, so a `REVOKE ... FROM anon, authenticated` ALONE does
-- nothing: PUBLIC membership still lets them call it. This exact gap
-- was caught by testing (see tripoli-points-merchant-logo-security-
-- tests.sql, Test A) before this file was finalized — the REVOKE below
-- includes PUBLIC for that reason.
--
-- The matching client-side change (this PR) stops calling it entirely
-- for merchants and instead points them to admin_reset_merchant_pin via
-- support. customer_reset_pin is UNCHANGED/out of scope — see the
-- separate report for why, and for the recommendation to decide on it
-- next.
--
-- ALSO REVOKED FROM service_role (added after review): confirmed via
-- has_function_privilege that production's service_role currently has
-- EXECUTE on this function too -- purely as a side effect of the same
-- PUBLIC grant, not an explicit grant of its own. Nothing in this
-- project (client, the two existing edge functions, or any other
-- function) calls merchant_reset_pin via service_role today, so
-- revoking it here is a deliberate least-privilege choice, not an
-- accident: if the team ever wants a service_role-only manual-reset
-- tool, that is a separate, explicit GRANT to add later with its own
-- justification, not something to leave standing as an unused side
-- effect of a blanket PUBLIC grant. If you'd rather service_role kept
-- this, say so and I'll adjust before this runs.
REVOKE EXECUTE ON FUNCTION public.merchant_reset_pin(text, text) FROM PUBLIC, anon, authenticated, service_role;


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
-- 3. This is additive only (one new table, five new/changed functions
--    rewired for rate limiting, three functions replaced with an
--    identical body plus one new JSON key, and one REVOKE closing the
--    merchant_reset_pin hole) — it does not drop or rename anything
--    merchants or customers already have, and existing rows simply get
--    logo_url = NULL until a merchant uploads a logo. If an EARLIER
--    draft of merchant_set_logo(uuid, text) was ever applied to this
--    project, this migration's CREATE OR REPLACE will NOT remove that
--    old, insecure 2-argument version automatically (Postgres treats
--    different argument lists as different functions) — run
--    `DROP FUNCTION IF EXISTS public.merchant_set_logo(uuid, text);`
--    first if so. If you haven't run any earlier version of this
--    migration, there is nothing to drop and you can ignore this.
-- 4. Recommended before running this against production: run it
--    against a disposable copy first (a local Postgres, or a Supabase
--    branch) and run tripoli-points-merchant-logo-security-tests.sql
--    there to see the negative-security assertions pass with your own
--    eyes. I ran that exact script (plus new tests for sections 4-7)
--    against an isolated, throwaway local Postgres instance (not this
--    Supabase project) while preparing this PR — see the PR description
--    / report for the output — but running it yourself against this
--    schema is cheap and removes any doubt before touching production.
-- 5. After running it, the matching app code in this PR (branch
--    feature/merchant-logo-persistence) will start saving/reading
--    logo_url through merchant_set_logo (prompting for the merchant's
--    PIN before every save/remove), will stop offering merchant
--    self-service PIN reset (pointing to support instead), and will
--    show a new "reset merchant PIN" action in the admin merchant-
--    review panel for primary admins. Run this SQL BEFORE deploying
--    that app code: the REVOKE on merchant_reset_pin and the new
--    admin_reset_merchant_pin RPC need to exist first, or a merchant
--    who hits "forgot PIN" mid-rollout would see the new client screen
--    with no working recovery path yet on the server. Running the SQL
--    first and the code second is safe either way — nothing in the SQL
--    depends on the new client code being present.
-- 6. IMPORTANT, SEPARATE DECISION: this file does NOT include the
--    "emergency hardening" cleanup (dropping old insecure admin-RPC
--    overloads and leftover test functions) — that is proposed as its
--    own file, tripoli-points-admin-emergency-hardening.sql, flagged
--    separately because it touches admin_delete_merchant,
--    admin_wipe_all_data and others that are NOT part of this PR's
--    scope. See the full report for why it's split out and what it
--    contains; nothing in it has been run either.
-- 7. BACKUP, FIRST: before running this file (or the hardening file)
--    against production, take a fresh backup. Confirm in the Supabase
--    dashboard (Database -> Backups) what your project's plan provides
--    (point-in-time recovery or daily backups) and that a recent-enough
--    restore point will exist, or trigger a manual backup there if the
--    plan supports it; I cannot trigger a project backup from here —
--    only you can, via the dashboard. As an extra, cheap safety net
--    that doesn't depend on the dashboard, export the handful of rows
--    this migration can't un-delete data for:
--      select id, phone, logo_url from public.merchants where logo_url is not null;
--    (save the output -- there should be none yet, since merchant_set_logo
--    doesn't exist until this migration runs, but re-run it right before
--    any LATER rollback, once merchants have started saving logos.)
-- 8. ROLLBACK: tripoli-points-migration-rollback.sql (same folder)
--    restores every function this file touches to its exact current
--    production definition (captured via pg_get_functiondef immediately
--    before writing it) and drops what this file newly adds. Dry-run
--    executed cleanly against the same throwaway Postgres instance used
--    for the security tests. Read its data-loss warnings before using
--    it -- in particular, it re-opens merchant_reset_pin and discards
--    any logo_url/auth_rate_limits data saved since this migration ran.
-- 9. RECOMMENDED EXECUTION ORDER (per your approval): 1) review and
--    apply tripoli-points-admin-emergency-hardening.sql, 2) review and
--    apply this file, 3) merge PR #3 and deploy/test the client code.
--    Nothing here depends technically on that exact order (the two SQL
--    files touch disjoint sets of functions), but doing hardening first
--    closes the more severe, already-live admin holes before touching
--    anything else, and keeps step 3 as a deliberate, separate action
--    you take only once both SQL files are confirmed applied correctly.
-- =====================================================================
