# Map V3.6.1 on main (2026-11-10)

Approved on Netlify Staging and merged into `main`. It contains Production V3.3 (the artistic map deployed on 2026-11-06) plus these map changes:

- **V3.4.1, step-back navigation.** A tap on the empty map and «−» each go back one map step. The shop button now reads «توجّه للمتجر».
- **V3.5, shop pins.**
  - Each individual shop pin shows its category image (102 images in `assets/map/cat/<slug>.webp`).
  - A shop's own logo replaces the category image.
  - Pins enlarge in two steps: when the shop is selected and when the route starts. They return to normal size when the route is cancelled, when going back, or when another shop is chosen.
  - While a route is shown, the other pins are hidden and the enlarged pin stays fully on screen.
- **V3.6, regional pins.** The six regional pins show the area photos in the «أبي سمراء» style: photo medallion, beige name ribbon, and Tajawal ExtraBold text.
- **V3.6.1, regional view.**
  - The «التل» pin is raised above the «طرابلس» label. Only its art anchor moved.
  - Pinch zoom on the regional view keeps the six pins, which grow with the zoom. Tapping a pin enters the stages.
  - The «−» and «✕» marks are centred in their buttons.

## Changes made for main only

These differ from the Staging build:

- The Staging-only slug prefixes (`stg_`, `test_`, `demo_`) are no longer recognised.
- The six regional pin files have content-hashed names (`assets/map/pins/rN.<sha256-10>.webp`). `_headers` caches `/assets/*` for one year as immutable, so reusing the old names would leave phones that opened V3.3 with the old pin art.
- The map images can be read from Supabase Storage. The app uses the public bucket `map-assets`, folder `v3.6.1/`:
  - The switch turns on only when `v3.6.1/manifest.json` is published there with `"version":"v3.6.1"`.
  - Until then, the app uses its own local files exactly as before.
  - Any single Storage image that fails falls back to its local file.
  - No table or policy is used.
- Staging files left out of main: the Staging SQL preview, the test scripts, the position dumps, the QA screenshots, and the Staging notes.

No change to coordinates, area data, registration, QR, transactions, points, Treasures of Tripoli, or the database.

## Rollback

- The previous main is kept as branch `backup/main-before-map-v3.6.1-20261110` (`a6c4e79`).
- To revert in git, run `git revert -m 1 <merge commit>`, or reset main to the backup branch.
- To roll back the site, redeploy the previous Netlify deploy (Deploys → the earlier deploy → "Publish deploy").
