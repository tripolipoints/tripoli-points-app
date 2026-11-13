# Batch 0: syncing Staging with main V3.7.4 (code only). Test report, 2026-11-13

**Status.** Code is prepared on the separate branch `sync/staging-v3.7.4`. Nothing has been merged or deployed. `staging-netlify`, `main`, Production and the databases are unchanged.

## Commits on `sync/staging-v3.7.4`

| Commit | Contents |
|---|---|
| `6104115` | Merge of `main` a54a85c with `staging-netlify` 48ecdaa (`-s ours`). The result is main's tree, plus the 12 Staging-only files exactly as they are on 48ecdaa (`batch0-staging-files-check.txt`: 12/12 SAME). |
| `ce10399` | The only code change: step 2b in `staging/build-staging.mjs`, plus `staging/README.md`. See `batch0-build-fix.diff` (55 lines). |

- **Commit messages:** both contain `[skip netlify]`, so Netlify does not build them.
- **Ancestors:** `staging-netlify` (48ecdaa) and `main` (a54a85c) are both ancestors of `ce10399`. A pull request into `staging-netlify` therefore merges with no conflicts and no force push.

## Tests

| # | Test | Result |
|---|---|---|
| 1 | `index.html` and `assets/` compared with main | Identical (`git diff` is empty) |
| 2 | The 12 Staging files compared with 48ecdaa | 12/12 identical |
| 3 | Build without `TP_STAGING_SITE` | Stops |
| 4 | Build with the Production URL | Stops |
| 5 | Build with an `sb_secret_` key | Stops |
| 6 | Build with `TP_MAP_REMOTE` defined twice | Stops |
| 7 | Old build script (48ecdaa) run on main | Stops: "contains the Production project reference". This is the reason for the fix. |
| 8 | New build with a test public key | `STAGING build OK` |
| 9 | Production reference in `dist-staging` | Only inside the guard, and in the negative test of `staging-check.html` |
| 10 | `dist-staging/assets` compared with `assets` | Identical |
| 11 | Browser run with the CSP header, Supabase mocked by synthetic data | 0 requests to Production (main as-is made 6). Every database request went to Staging. Guard: blocked 0. 0 images returned 404. |
| 12 | Pixel comparison, main as-is vs the Staging build (390×844): home, shops map, regional-pin zoom, shop page, Tripoli Treasures | Identical: 0 differing pixels in all 5 |
| 13 | The 102 category images and the 6 regional pins, local files vs Production Storage `map-assets/v3.6.1` (read-only `eTag` comparison) | Category images: 102/102 identical. Pins r1, r3, r4: identical. Pins r0, r2, r5: differ. On Production they are served from the app's local files (`TP_MAP_LOCAL_ONLY`), so Staging shows exactly what Production users see. |

## Not tested here

- A real build on Netlify, and the real Staging key.
- Real data from the Staging database.
- Category images on the shop pins with a real merchant (in this test the synthetic shops did not appear at zoom). Their files were compared directly in test 13.

## Backup

- **Tag not created on GitHub:** pushing the tag `backup-staging-netlify-48ecdaa` was refused by this session's permissions (HTTP 403). It exists only locally.
- **48ecdaa is still preserved:** the commit is a parent of `6104115`, so it is not lost, and `staging-netlify` has not moved.
- **Before merging:** create the backup from the GitHub web interface (tag or branch on 48ecdaa), or give the session permission to push tags. Also record the current Netlify deploy ID.

## Files

| File | Contents |
|---|---|
| `batch0-build-fix.diff` | The code change |
| `batch0-staging-files-check.txt` | Comparison of the Staging files |
| `batch0-sync-vs-main.stat` | Diff statistics against main |
| `parity-test.js` | The browser test harness |
| `parity-report.json` | Browser test results |
| `screens/` | Screenshots of the Staging build |
