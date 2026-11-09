# V3.5 (Staging only) — category images in shop pins + progressive enlargement

Base: V3.4.1 step-back (`cfc4713`). No DB change, no Production change.

- `assets/map/cat/<slug>.webp`: 100 images, 128 px, round alpha (from the 102-image manifest; `beautysupplies` and `salons` left out because the source images are unusable — those shops fall back to the parent category image or the current icon).
- Lookup by the shop's primary category slug, then its parent category; aliases `earbuds`/`headphones` → `earphones`, `wedding`/`bridal` → `wedding_dresses`. A shown logo keeps priority.
- All individual shop pins: selected ×1.45 (max 2.6), route ≥ ×1.18 of the selected size (max 3.1), growing from the tip; z-index above neighbours (existing).
- `routeFitView` reserves the enlarged pin's real height/width; `clearRoute` redraws pins so sizes reset immediately.
- Patch + scripts: `map-integration/v3.5/`.
