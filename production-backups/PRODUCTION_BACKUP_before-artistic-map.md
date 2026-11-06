# Production backup — before the Artistic Map V3 release (6 Nov 2026)

| Item | Value |
|---|---|
| Production code (GitHub main) | `a6c4e79529a65ec4d70711f78c81b499a8c86c99` (Merge pull request #7, 2 Nov 2026) |
| Backup branch | `backup/production-before-artistic-map-20261106` (this commit adds only this file and the ZIP) |
| Site package | `production-backups/Tripoli_Points_Production_before_artistic_map_a6c4e79.zip` — index.html, _headers, assets/ exactly as on main — 1,763,619 bytes |
| ZIP SHA-256 | `d1885e6d328e8fadae168f3700405215f20589e75c0c3099096407b6708d278a` |
| Supabase | the Production project already referenced in main's index.html (unchanged; not contacted) |

Note: this is the code on GitHub main. If the live Netlify site was uploaded from a different build, also download that
deploy in Netlify (Deploys → the published deploy → "Download") and keep it with this backup.

## Rollback
Netlify → Production site → Deploys → either "Publish deploy" on the previous deploy, or drag in the extracted contents of this ZIP.
No database step is needed: the map release does not change the database.
