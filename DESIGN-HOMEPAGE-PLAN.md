# Tripoli Points — Premium Mobile Homepage Design Plan

Status: design proposal awaiting code implementation and on-device verification. This branch intentionally does NOT change application behavior or the production main branch.

## Scope
Visual refinement of the customer's first / map homepage. Preserve existing functionality: Tripoli hero image/logo, search, live point balance, neighborhood filtering and "المزيد", interactive map, clusters, pins, route control, promotional card, and six-tab bottom navigation.

## Target look (based on approved visual direction)
- Keep blue/gold Tripoli Points brand, tower image, and Arabic RTL layout.
- Compact the hero enough to expose more map on small phones; preserve readable wordmark and notification action.
- Keep search visually integrated with the hero; minimum tap height 44px.
- Make points card prominent with balanced two-column layout, large balance, readable caption, tasteful navy gradient; NO hard-coded value (must read existing state).
- Neighborhood tiles: uniform heights, crisp icons, smaller shadow, active state, single intentional horizontal-scrolling row; do not change filtering.
- Map remains the main focal point with rounded outer container, unchanged live tiles, markers/clustering, user-location and satellite controls. Do NOT replace live map with a screenshot.
- Promo card: single navy rounded surface with no visible gray outer wrapper; respect current dynamic promotional content.
- Navigation: six equal-width actions, `min-width: 0`, readable short labels, prevent clipping of "حسابي" and long "كنوز طرابلس". Fixed/sticky behavior should be inspected against viewport and browser toolbar.

## Mobile correctness criteria
1. No accidental horizontal page scroll; district strip may scroll within its own element.
2. Bottom navigation visibly fits on 320/375/390/430px screens, including iOS Safari and browser toolbar expanded/collapsed.
3. No doubled gray/blue background behind promotional card.
4. Touch interactions, map drag/pinch, and vertical scroll remain functional.
5. Respect RTL, safe-area inset, dynamic viewport. Fix actual overflow source; avoid blanket `overflow-x:hidden` unless justified.
6. Font size on focusable inputs >= 16px on iOS to prevent involuntary zoom.
7. Do not change points, redemptions, authentication, Supabase RPC, server rules, database, or back-end behavior.

## Integration and safety
- Latest known base main commit when plan created: `a2f34b311cfff76cbdfd09bcbec49c9f22b72a1d` (Claude's iOS auto-zoom fix).
- Avoid simultaneous changes to `index.html` without rebasing/refreshing from main.
- Deploy feature-branch preview (or isolated Netlify preview) before merging.
- Check screenshot at actual iPhone size with Safari toolbars visible.
- Record before/after and smoke-test map, districts, search, points, tabs, routes and promotional actions.

## Implementation blocker / next step
The repository currently contains a single oversized `index.html` (~2.6 MB). This connector cannot return its complete file content for safe editing. The file must be made available to the editor through a supported local upload / workspace or split into smaller maintained modules before code modifications. No HTML/CSS has been modified by this planning commit.
