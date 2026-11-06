# Production release — Tripoli Points Artistic Map V3 (prepared 6 Nov 2026, NOT deployed)

| Item | Value |
|---|---|
| Release version | `production-artistic-map-v3` |
| Base (current Production) | GitHub main `a6c4e79529a65ec4d70711f78c81b499a8c86c99` |
| Approved map source | Staging V3 `48ecdaae1958a2b76bfafd3431d2a6d39a0085c1` (`backup/staging-artistic-map-v3-approved`) |
| Release branch | `release/production-artistic-map-v3` (not merged into main) |
| Production ZIP | `Tripoli_Points_Production_Artistic_Map_v3.zip` — 23,715,782 bytes |
| ZIP SHA-256 | `f7d50d8e36a8130cecfa1289c7030dc44fd4b3b17ad6e20c3296429da24b1a30` |
| Production backup | branch `backup/production-before-artistic-map-20261106` → `production-backups/Tripoli_Points_Production_before_artistic_map_a6c4e79.zip` (SHA-256 `d1885e6d…d278a`) |
| Supabase | Production project, SB_URL/SB_KEY lines identical to main (not contacted during preparation) |

## What changed (map only — the same 27 change blocks as Staging V3, verified identical)
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
