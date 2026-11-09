# V3.5 (Staging only) — category images in shop pins + progressive enlargement

Base: V3.4.1 step-back (`cfc4713`). No DB change, no Production change.

- `assets/map/cat/<slug>.webp`: 100 images, 128 px, round alpha (from the 102-image manifest; `beautysupplies` and `salons` left out because the source images are unusable — those shops fall back to the parent category image or the current icon).
- Lookup by the shop's primary category slug, then its parent category; aliases `earbuds`/`headphones` → `earphones`, `wedding`/`bridal` → `wedding_dresses`. A shown logo keeps priority.
- All individual shop pins: selected ×1.45 (max 2.6), route ≥ ×1.18 of the selected size (max 3.1), growing from the tip; z-index above neighbours (existing).
- `routeFitView` reserves the enlarged pin's real height/width; `clearRoute` redraws pins so sizes reset immediately.
- Patch + scripts: `map-integration/v3.5/`.

## V3.5 final (2026-11-09)
- 98 images: 77 realistic photos cut from the source boards (picture.rar, `board_tiles.py` + `final_cat_images.py`), 21 kept from the ZIP (no realistic source yet), 4 removed (hospitals, main_health, sportswear_women, sportswear_kids: duplicates / wrong subject → parent image or category icon). Per-slug list: `map-integration/v3.5/final_report.csv`.
- Staging test slugs `stg_*` map to the same images (stg_cafe → cafe, stg_food → food, stg_fashion → fashion).
- Cancelling the route returns the selected pin to its normal size (card stays open); a step back restores the selected stage.
- `staging_add_categories_PREVIEW.sql`: NOT run — adds earphones / wedding_dresses on Staging after approval.
