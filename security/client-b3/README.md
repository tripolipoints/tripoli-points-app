# Batch 3 client — kept here because deployment branches are frozen

Netlify is disabled by the owner's decision (13 Nov 22:33). Client work after `staging-netlify` @ `4ff9ace` is **not pushed** to
`staging-netlify` or `staging/b3-client`. It lives here instead:

- `b3-client.js` — the full client module (inlined before `</body>` of `index.html` between `<!-- B3-CLIENT -->` markers).
- `0001-*.patch` — the commit on top of `staging-netlify` @ `4ff9ace` (local branch `wip/b3-client-3e`, commit `9c33c5d`).
  Apply with `git am` on a branch made from `4ff9ace` when the owner authorises it.

Added in 3e: report a purchase (customer, from the pay-code sheet and the pending-purchase card), report a scanned code
(shop: "the person is not the account owner"), Admin «البلاغات والتنبيهات» (reports + monitoring alerts, resolve with a note
that is sent to the reporter).
