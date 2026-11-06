# Production release — Tripoli Points V3.3 (prepared 6 Nov 2026, NOT deployed)

V3.3 = current Production (main `a6c4e79`) + the complete approved Staging V3 experience + the V3.2 map-control refinements.
Supersedes the V3 (`f7d50d8e…`), V3.1 (`a8885e3a…`) and V3.2 (`4797e63a…`) packages — do not upload those.

| Item | Value |
|---|---|
| Release version | `production-v3.3` |
| Package | `Tripoli_Points_Production_Artistic_Map_v3.3.zip` — 23,723,091 bytes, index.html at the root |
| SHA-256 | `6a0b5cf9d4526737cc4c5332e832dcc3567a35c28ed4364a026a7f6531a5a49b` |
| Release branch | `release/production-artistic-map-v3` (not merged into main) |
| Base (current Production) | GitHub main `a6c4e79529a65ec4d70711f78c81b499a8c86c99` |
| Approved source | Staging V3 `48ecdaae1958a2b76bfafd3431d2a6d39a0085c1` (`backup/staging-artistic-map-v3-approved`) |
| Production backup | `backup/production-before-artistic-map-20261106` → `production-backups/Tripoli_Points_Production_before_artistic_map_a6c4e79.zip` (SHA-256 `d1885e6d…d278a`) |

## Relation to the approved Staging version (verified by line diff)
V3.3 `index.html` = approved Staging V3 source (48ecdaa) **plus only** the V3.2 map-control refinements
(one CSS block; one «Tripoli» button on the full-screen map). Everything else is line-for-line identical to Staging V3.

## Changes V3.2 → V3.3
- The 14 approved `custKnown` / `custName` blocks from Staging (`aed74d6`, «merchant no longer rejects real customers missing
  from the local cache»), copied exactly: on a real shop's device an unknown number is no longer refused locally;
  `create_transaction` on the server validates existence, status and balance. A known frozen account is still refused locally;
  the request's customer name is shown (display only); the redemption preview never invents a balance and the toast after sending
  shows the server's points used and cash due. Duplicate protection, request lifecycle, customer confirmation, PIN: unchanged.

## Everything in V3.3
Artistic map (tiles 13–20, zoom-13 artwork centred on Tripoli), six regional gold pins with live counts, gold cluster and
miniature shop pins, split +2 zoom, independent expand/collapse, empty-map close, zoom 19–20 shared-spot list, selection and
name labels, routes, Google Maps; Scan/Tripoli row (Poppins Latin lettering), raised area tiles, map-control shadows,
aligned +/−/full-screen/X (34 px), gold «Tripoli» control on the full-screen map; login safeguard (failed lookup ≠ new number);
merchant customer-validation fix (custKnown). Arabic typography unchanged (Tajawal; Poppins only for Latin letters).

## Supabase compatibility
- Same Production project: `SB_URL` / `SB_KEY` lines identical to main. No reference to the Staging project.
- Database calls: the same 68 RPC/function names as main — none added, none removed; `create_transaction` arguments identical.
- No database, RPC, Edge Function, auth or RLS change is required by V3.3.
- One pre-deploy check (read-only, by the owner): the custKnown fix relies on Production `create_transaction` refusing an unknown
  or frozen customer (Staging's does; the fix was tested there). Confirm in the Production SQL editor with
  `select pg_get_functiondef('public.create_transaction'::regproc);` — it must check that the customer exists and is active.

## Local regression (outside network blocked, test responses in place of the database)
Map suite (6 pins, 6/5 split, 16→18, expand/collapse, empty-map close, mini pins, selection, route): pass, no errors.
Login: existing → PIN; new → registration; failed lookup → stays with «try again».
Merchant transaction, customer not in the device list: V3.2 refused locally («غير مسجّل»); V3.3 sends to the server and shows
the server's answer (accepted, or «الزبون غير موجود»). Known frozen customer: still refused locally. Controls: 34×34, aligned.
Not testable here: the real Production database, a real QR transaction and points — check after upload.

## Deploy (manual, by the owner)
1. Netlify → Production site → Deploys → download the currently published deploy (extra backup).
2. Drag in the extracted contents of the V3.3 ZIP (check the SHA-256 first).
3. On iPhone: hard-refresh; check login with a real account, the six pins and real counts, one QR transaction on a real shop
   device with a real customer number, points.

## Rollback
Netlify → Deploys → «Publish deploy» on the previous deploy, or drag in the backup ZIP above. No database step.
Note: /assets/* are cached for a year; a future map update must use new file paths.
