# Batch 3-C — browser E2E against Staging: preparation and plan (NOT executed)

Status: prepared only. Nothing has run in a browser against Staging. This needs your explicit approval, because
browser calls go over HTTP and **each call commits on its own**. Unlike the database-level test, nothing rolls back.

## Why `e2e-b3.js` cannot point at Staging as it is

`e2e-b3.js` (349 lines) + `gateway-b3.js` were written for a disposable local copy:
- `gateway-b3.js` answers every `/rest/v1/rpc/*` call with local `psql` as role anon. Nothing reaches Supabase.
- `seed-b3.sql` inserts a merchant, a top-up, an **admin with a known PIN** and a customer directly into tables.
- 58 `sql1()` calls use superuser `psql`. Most only read (verification), but several **write or change shared state**:
  - line 180 moves gift expiry dates;
  - the admin steps checked at lines 91–99, 277 and 297–299 change plans, the transfer number, the VIP count and the
    redeem % through the admin screens (Staging-wide settings that other testers see);
  - line 303 takes a backup into `tp_backup`;
  - some `sql1()` calls fetch ids (tx, payment request, staff) that the next steps depend on.

## Minimum changes (proposed, not made)

1. **Gateway switch** `TP_TARGET=local|staging` (default `local`). In `staging` mode, do not intercept
   `/rest/v1/rpc/*`. Let the stub's `fetch` reach the real endpoint, with the URL and publishable key read from environment
   variables (never written to a file). Refuse to start unless the host is `axzlshimvtskkxknlwoz.supabase.co`, and never
   with a service key.
2. **No `seed-b3.sql` in staging mode.** Create the customer and the shop through the real registration screens (synthetic
   `79998xxx` phones not used on Staging). The admin steps use an **existing Staging admin, typed by you at run time**
   (environment variable or a prompt). The script never stores it.
3. **Replace the id-fetching `sql1()` calls** with the data the app already returns (`customer_transactions_v2`,
   `merchant_payment_requests_v2`, `merchant_staff_list_v2`, `report_tx`).
4. **Read-only verification afterwards.** In staging mode, `sql1()` writes each verification query to
   `result/staging-verify.sql` instead of running it. After the run, I check them through the database tools, read-only.
5. **Skip the steps that change shared state** (expiry time travel, plans/transfer number/VIP count/redeem %, backup) in
   staging mode, with a printed "SKIPPED (shared state)". They stay covered by the local run (70/70) and the database test.
6. **Cleanup plan:** a backup without wipe before the run (`admin_backup_now_v2`, existing feature). After the run, either
   keep the synthetic accounts, tagged by phone range, or remove them with `admin_force_delete_*_v2` (destructive on the
   synthetic accounts only, so that needs its own yes from you).

These changes touch only `security/batch3b-engine/e2e/e2e-b3.js` and `gateway-b3.js`. The app (`index.html`, `b3-client.js`)
is not changed.

## Where it can run

Not in this workspace: no browser binaries, no network route to Staging, and installs are off. It needs a machine with
Node, Playwright + Chromium and internet access: yours, or a later session with network installs enabled.

## Test plan (4 roles, staging mode)

| # | Role | Flow | Persists on Staging |
|---|---|---|---|
| 1 | Customer | register (welcome gift from the admin setting) → home → «رمز الشراء» → choose points → privacy screen | new synthetic customer, gift batch |
| 2 | Merchant | register → admin activates → login → transfer request (reference `TP-E2E-…`) | new synthetic shop, payment request |
| 3 | Admin (your account) | approve the shop → approve the payment with re-typed amount/reference → reports screen → refund | allowance grant, audit rows |
| 4 | Merchant + customer | scan → quote → create → the customer confirms on their page → receipt on both sides | 1–2 transactions, ledger rows |
| 5 | Employee | owner adds employee (sell) → email/password → device approval → 6-digit PIN → sale | staff + device rows |
| 6 | Attacks from the browser console | other customer's tx, cross-role tokens, tampered hash, direct table access | none (all refused) |
| 7 | Logout everywhere | session ends | session rows |

Prerequisite from the database test: the new shop needs an **old-wallet top-up** to sell (open decision §02), or
the run stops at «INSUFFICIENT».

Not included without separate approval: wipe/restore, settings changes, real e-mail, `sub_enforce`, Netlify (the app is
served locally from `security/client-b3/`, not deployed).
