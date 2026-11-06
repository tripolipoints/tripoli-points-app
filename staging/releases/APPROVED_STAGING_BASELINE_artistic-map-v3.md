# Approved Staging baseline — Tripoli Points Artistic Map V3

Approved on 6 Nov 2026 as the Staging baseline (Staging only — NOT approved for Production).

| Item | Value |
|---|---|
| Version | `artistic-map-v3` |
| Source commit (app code) | `48ecdaae1958a2b76bfafd3431d2a6d39a0085c1` (branch `integration/artistic-gold-map`) |
| Backup branch | `backup/staging-artistic-map-v3-approved` (this commit adds only this file and the ZIP) |
| Deployment ZIP | `staging/releases/Tripoli_Points_Staging_Artistic_Map_v3.zip` — 23,729,579 bytes |
| ZIP SHA-256 | `af83465434bf4cbc9d29d4847264a1b0bf32aa73a51a2b5d99c117c2aafa2d7a` |
| Build | `staging/build-staging.mjs`, built 2026-11-06T10:27:12Z (see `staging-build.json` inside the ZIP) |
| Supabase (Staging) | `https://axzlshimvtskkxknlwoz.supabase.co`, publishable key `sb_publishable_oVS…xFc5g9` (public key only) |
| Production protection | Staging guard + STAGING badge; CSP `connect-src` limited to the Staging project; no Production reference outside the guard; no `.sql` files |
| Netlify | manual drag-and-drop of the ZIP contents (index.html at the root); `_headers` included; no `_redirects` needed |
| Extra (Staging package only) | `staging-map-diagnostics.js`, active only with `?mapdiag=1`, read-only |

Previous Staging (before the map integration): branch `backup/staging-before-artistic-map-20261106` (`6294e11`).

## Verified on Netlify Staging (by the project owner)
Existing Staging test customer login and PIN · Staging Supabase connection · all six regional gold pins · QR transactions and points.
Still to do before any Production decision: merchant navigation tests.

## Contents of V3 (map integration)
Painted OpenStreetMap tiles (zoom 13–20; sharp citywide to zoom 17), artistic zoom-13 overview centred on Tripoli,
six regional gold pins (5 main areas + عزمي بك) with live counts, gold cluster and miniature shop pins, split-pin +2 zoom,
independent cluster expand/collapse, empty-map close, zoom 19–20 shared-spot list, failed phone lookup never treated as a new number.

## Restore
1. Netlify Staging → Deploys → drag in the extracted contents of the ZIP above (check its SHA-256 first), or
2. rebuild from commit `48ecdaa` with `node staging/build-staging.mjs` (Staging URL + publishable key as environment variables)
   and add `staging-map-diagnostics.js` + its script tag as described in `staging/map-integration/README.md`.
