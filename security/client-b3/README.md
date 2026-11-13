# Batch 3 client — kept here because deployment branches are frozen

Netlify is disabled by the owner's decision (13 Nov 22:33). Client work after `staging-netlify` @ `4ff9ace` is **not pushed** to
`staging-netlify` or `staging/b3-client`. It lives here instead:

- `b3-client.js` — the full client module (inlined before `</body>` of `index.html` between `<!-- B3-CLIENT -->` markers).
- `000N-*.patch` — the commits on top of `staging-netlify` @ `4ff9ace` (local branch `wip/b3-client-3e`, commits up to `1128704`).
  Apply with `git am` on a branch made from `4ff9ace` when the owner authorises it.

Added in 3e: report a purchase (customer, from the pay-code sheet and the pending-purchase card), report a scanned code
(shop: "the person is not the account owner"), Admin «البلاغات والتنبيهات» (reports + monitoring alerts, resolve with a note
that is sent to the reporter).

Added in 3g: customer chooses the points to use on the purchase code (§03), owner «زبائن VIP» (§16), lower % request handled
as pending, customer «نقاطي» shows VIP caps, Admin «طلبات نسبة الاستبدال», «النسخ الاحتياطية», and the new rule settings.
E2E (real app, local copy with all migrations up to 3g): 59/59.

Added in 3h–3j (local branch commit `7fa4524`): Admin «إرجاع عملية», «تعويض (7 أيام)», «رد» on reports with deadlines, «تشغيل
المهام الدورية», customer reactivation, permanent-closure decision; owner «الدوام والإغلاق», staff e-mail/password and device
approvals; staff login = e-mail + password on a new device → owner approval → 6-digit PIN (device id kept in this browser's
localStorage); customer «الخصوصية وحذف الحساب». E2E (real app, local copy with all migrations through 3j + e-mail prep): 70/70.
