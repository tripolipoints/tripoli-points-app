# Production release — Tripoli Points Artistic Map V3.1 (prepared 6 Nov 2026, NOT deployed)

V3.1 = V3 (map) + the approved Staging UI improvements listed below. Supersedes the V3 package (`f7d50d8e…`).

| Item | Value |
|---|---|
| Release version | `production-artistic-map-v3.1` |
| Base (current Production) | GitHub main `a6c4e79529a65ec4d70711f78c81b499a8c86c99` |
| Approved map source | Staging V3 `48ecdaae1958a2b76bfafd3431d2a6d39a0085c1` (`backup/staging-artistic-map-v3-approved`) |
| Release branch | `release/production-artistic-map-v3` (not merged into main) |
| Production ZIP | `Tripoli_Points_Production_Artistic_Map_v3.1.zip` — 23,721,635 bytes, 6,390 files |
| ZIP SHA-256 | `a8885e3a1eb9851e1a53666cc36fac1903e07d2a40c707cbb0c1a698683a408a` |
| Production backup | branch `backup/production-before-artistic-map-20261106` → `production-backups/Tripoli_Points_Production_before_artistic_map_a6c4e79.zip` (SHA-256 `d1885e6d…d278a`) |
| Supabase | Production project, SB_URL/SB_KEY lines identical to main (not contacted during preparation) |

## Approved Staging UI improvements added in V3.1 (from Staging baseline `6294e11`, display only)
1. Home: «Scan» (navy) and «Tripoli» (gold) as two equal pills in their own row below the banner (no overlap with the image or the bell);
   «Tripoli» resets the map to the Tripoli view (same action as the former «طرابلس» chip on the map, which moves to this row).
2. Brand font for those pills: Poppins Bold, Latin letters only (`assets/fonts/poppins-bold-latin.e3c2d4743b.woff`, OFL licence file included).
3. Map buttons (zoom, full screen, round chips): soft drop shadow, hairline ring, pressed state.
4. «+» zoom drawn as a centred SVG.
5. The six area tiles and «بحث وفئات» above the map: raised shadow and pressed state.
6. iOS: a passive touchstart listener so :active pressed states show (no effect on gestures).

## Approved Staging change NOT included (needs a separate decision)
`custKnown` / `custName` (14 code blocks): changes how the merchant's device checks a customer on the transaction screen (relies on
create_transaction on the server instead of the device's local customer list). It is QR-transaction logic, not UI, so it was left out
as instructed; the merchant transaction code in V3.1 is identical to current Production.
Not included either: netlify.toml (Staging build only), .gitignore, staging/ folder, Staging guard/badge, diagnostics, test data.

## Map changes (the same change blocks as Staging V3, verified identical — the same 27 change blocks as Staging V3, verified identical)
- `index.html`: painted map tiles (static), zoom 13–20, artistic zoom-13 overview centred on Tripoli, six regional gold pins with
  live counts, gold cluster + miniature shop pins, split-pin +2 zoom, independent expand/collapse, empty-map close, zoom 19–20
  shared-spot list, brown/gold name labels; and the V3 login safeguard (a failed phone lookup shows "try again" instead of
  opening registration). Adds a Google Fonts stylesheet link for the Amiri font (free; same provider the app already uses).
- `assets/map/`: 6,341 tiles (© OpenStreetMap contributors, ODbL), artwork, 8 pin images.
- `map-integration/`: the script and sources used to generate the change (not part of the site package).
Not included: Staging guard/badge, diagnostics, test panel, dummy shops, staging/ folder, .sql files.
No database, RLS, authentication-function or data change.

## Checks done (locally, all outside network blocked)
No reference to the Staging project; Production URL/key unchanged; every asset and indexed tile present; map suite
(6 pins, split 6/5, +2 zoom, independent expand/collapse, empty-map close, mini pins, selection, route) passed; regional pins
inside the map with a small concentrated shop set; login: existing → PIN, new → registration, failed lookup → stays with retry.

## Deploy (manual, by the owner)
Netlify → Production site → Deploys → drag in the extracted ZIP contents (index.html at the root). Then hard-refresh on iPhone.

## Rollback
Netlify → Deploys → "Publish deploy" on the previous Production deploy, or drag in the backup ZIP above. No database step needed.
Note: /assets/* are cached for a year (_headers); a future map update must use new file paths.
