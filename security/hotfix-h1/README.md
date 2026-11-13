# Hotfix H1: closing the money and account functions to the public key

**Status:** Prepared and tested locally only. It has not been applied to Staging or Production. Each environment needs its own approval.

## Files

| File | Purpose | Kind |
|---|---|---|
| `tp-hotfix-h1.sql` | The hotfix | Single transaction; guards stop it on any mismatch |
| `tp-hotfix-h1-check.sql` | Status check | Read-only |
| `tp-hotfix-h1-tests.sql` | Behavioural tests | Synthetic rows, ends in ROLLBACK; for local or Staging only |
| `tp-hotfix-h1-rollback.sql` | Emergency rollback | Reopens the holes |

## Local test (PostgreSQL 16 replica, 2026-11-13)

**Replica setup**
- Built from the Staging structure.
- The privileges on the 10 functions were set to match Production exactly.
- The 10 function bodies in the replica have the same normalised md5 as Production, read today.

**Results**

| Step | Result |
|---|---|
| Tests before H1 (current Production state) | `passed=8 failed=26`. `anon` and `authenticated` reach every one of the 10 functions. |
| Apply H1 | `10 function(s) closed`. The guard confirms the public key is closed and that the owner and `service_role` keep access. |
| Tests after H1 | `passed=34 failed=0` |
| Privilege diff after H1 | Only the 10 target entries changed |
| Apply H1 a second time | Same result (idempotent) |
| Rollback | All 10 functions are back to the original 5 grants each (compared as sets). The check reports them open again. |
| H1, then the Phase 0 v1.3.1 file | Phase 0 still applies cleanly (70/70 self-check). H1 tests still pass 34/34. |

**What the 34 passing tests cover**
- `anon` and `authenticated` are refused on all 10 functions (20 checks).
- Refused calls leave no change in balances, orders or top-ups.
- `service_role` keeps `whish_set_collect_url` but loses `whish_confirm_payment`, and the REVIEW order is untouched.
- Customer login and profile still work, and the existing welcome-expiry rule still runs internally.
- The merchant can still send a manual top-up request and read their wallet.
- The admin order list still loads.
- The owner, from the SQL editor, can still approve an order, top up a wallet, mark an order collected, and reset a PIN.
