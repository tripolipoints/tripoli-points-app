# Tripoli Points: Staging site on Netlify

This branch (`staging-netlify`) is GitHub `main` plus this folder, `netlify.toml` and `.gitignore`. `index.html`
is not edited: the build writes a separate copy to `dist-staging/` that talks only to the Staging Supabase project
`axzlshimvtskkxknlwoz`. `main`, the live site and Production Supabase are never touched.

## How the build keeps Production out

| Layer | What it does |
| --- | --- |
| Build checks | Stops unless `TP_STAGING_SITE=yes`, the URL is exactly `https://axzlshimvtskkxknlwoz.supabase.co` and the key is a public key of that project. Production URL or key, a `service_role` JWT or an `sb_secret_` key stop the build. |
| Output scan | Stops if any published file contains the Production reference (except where it is named to be blocked) or the Production key, or if a `.sql` file would be published. |
| Browser rule (CSP) | `connect-src` allows only Staging Supabase and the routing and image tools the app needs: the browser refuses any request to Production. |
| In-page guard + badge | Blocks requests to any other Supabase project, counts requests to Staging, and shows `STAGING · DB n` (purple). Red with `BLOCKED n` means stop testing. Tap it for details. |
| Check page | `/staging-check.html`: five checks that must all read PASS before QR or transaction tests. |

## One-time setup (about 10 minutes)

1. **Live site, first:** in the live site's Netlify settings, open *Site configuration → Build & deploy →
   Continuous deployment → Branches and deploy contexts*. Production branch must be `main`, and *Branch deploys*
   should be "Deploy only the production branch". Change nothing else. If it is set to "All", a build of this
   branch on the live site stops at once (no `TP_STAGING_SITE`) and publishes nothing, but set it to production only anyway.
2. **New site:** *Add new site → Import an existing project → GitHub → tripolipoints/tripoli-points-app*.
   - Branch to deploy: `staging-netlify` (not `main`).
   - Build command and publish directory come from `netlify.toml`; leave them blank.
   - Site name: for example `tripoli-points-staging` (address `https://tripoli-points-staging.netlify.app`).
3. **Environment variables**, before the first deploy (*Add environment variables* during import, or later
   under *Site configuration → Environment variables*), scope: Builds:
   - `TP_STAGING_SITE` = `yes`
   - `STAGING_SUPABASE_URL` = `https://axzlshimvtskkxknlwoz.supabase.co`
   - `STAGING_SUPABASE_KEY` = the Staging project's public **anon** (or **publishable**) key, from Supabase →
     Staging project → *Project Settings → API Keys*. Never the `service_role` or secret key.
4. **Deploy contexts of the new site:** *Branch deploys* = production branch only, *Deploy Previews* = none.
5. Deploy. The build log must end with `STAGING build OK`. Any `STAGING BUILD STOPPED` line explains what to fix.

## Verify before any QR or transaction test

1. On the iPhone and on the merchant computer, open `https://<staging-site>/staging-check.html`.
   All five rows must read **PASS**.
2. Open the app (`https://<staging-site>/`). The title starts with `[STAGING]`, and a purple `STAGING · DB n`
   badge appears top left. Browse shops: `n` grows; the badge must never turn red.
3. On the computer (Chrome or Safari), open the developer tools, then *Network*, filter `supabase`, and reload.
   Every request must go to `axzlshimvtskkxknlwoz.supabase.co`.
4. Only then use the dummy accounts. The Staging database has no data until the synthetic seed is applied.

## Keeping Staging up to date

Merge `main` into `staging-netlify`. Only the Staging site rebuilds. If `index.html` ever stops defining
`SB_URL` / `SB_KEY` exactly once, the build stops and says so: update `staging/build-staging.mjs`.

## Known, intended limits on Staging

- No edge functions and no `pg_net` on Staging: Whish payments cannot start; payment-confirmation functions are
  closed to the public key. Top-up flows stop with an error. That is expected.
- 21 function signatures the app never calls have no public access on Staging (Wave 1 rehearsal).
- Google Maps is not configured (empty key in `main`); the map uses the built-in tile map, as in production.
