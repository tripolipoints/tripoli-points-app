# Automated tests (offline demo)

These tests run on GitHub Actions against an **offline demo build** of the app. They never reach Supabase:

- `demo/build_demo.py` copies the app and swaps the database client for `demo/demo-server.js`, which answers every
  call from invented sample data in the browser. The build stops if any production reference is left.
- `tests/fixtures.js` blocks every request that is not to the local demo server and fails a test if anything tries to
  reach Supabase. Map tiles are blocked; the routing service gets a fixed test answer.
- The app's own `index.html` is not changed by any of this.

What is tested (Chromium at 320, 375, 390 and 430 px, and WebKit as an iPhone 13):

| Area | Tests |
| --- | --- |
| Customer | login, home, balance, offers page; «متابعة» disabled until a valid amount; one request and the sent screen; forgotten PIN → support |
| Merchant | duplicate requests shown once; sending a purchase returns to the pending list; the customer confirms and points move once; QR poster; forgotten PIN → support; known limitation (see below) |
| QR | poster link before login opens the shop after login; «امسح QR» opens from the home picture; decoder loaded from the app's own files; pasted link; camera reads a printed poster (Chromium test camera); the poster sheet |
| Map | shops shown, selecting a shop, walking and driving routes |

**Known limitation recorded by a test (existing behaviour, not changed):** the merchant's new-purchase form only accepts
customers whose details the merchant's browser already holds, so on a fresh device a registered customer is refused with
«هذا الرقم غير مسجّل في التطبيق».

How to run: push to `test/playwright-offline-demo`, or open **Actions → Playwright (offline demo) → Run workflow**.
Results: the run's summary page lists every test; the artifacts hold the HTML report, the screenshots and
`tripoli-points-offline-demo.zip` for testing on an iPhone (see `TESTING-ON-IPHONE.txt` inside it).
