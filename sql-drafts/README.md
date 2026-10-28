# SQL drafts — NOT EXECUTED

Everything in this folder is a **postponed draft kept for future review only**.
None of these statements has been run against any Supabase project, and the app
does not call any function defined here.

- `NOT-EXECUTED_POSTPONED_tripoli-points-map-light-rpc.sql` — proposed read-only
  `list_merchants_map()` and `merchant_media(uuid[])` (performance Stage 2 / "A").
- `NOT-EXECUTED_POSTPONED_tripoli-points-map-light-rpc-rollback.sql` — matching rollback.

Status (2026-10-28): postponed. Image management will be handled by a future
admin-controlled media approval system (merchant logos, storefront images,
product photos, offer images). Database permissions, merchant IDs, column types
and security will be reviewed separately before production launch.
