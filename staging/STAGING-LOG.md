# Staging log (staging-netlify)

Every Staging batch, data reset and test account change is recorded here. Production and main are never touched.

| Date | Batch | Commit / file | What changed on Staging | Rollback |
|---|---|---|---|---|
| 2026-11-13 | 1 — environment sync | this commit | Site code = main V3.7.4 (a54a85c) + Staging build files; build step 2b serves map images from local files (no Production Storage). No database change. | Netlify: publish the previous deploy. Git: revert this merge; backup branch `backup/staging-netlify-48ecdaa-20261113` = previous head 48ecdaa. |

## Test accounts

No account was reset or created by Batch 1.
| 2026-11-13 21:35 | 2 v1.1 — security foundations (database) | `feature/secure-purchase-sql` security/staging-batch2 | Settings added because missing (rate 100, legacy cap 70, welcome gift 3000 / 7 days = the Admin «هدية الترحيب» values); H1 (10 functions closed to the public key, exact ACL snapshot in tp_backup.acl_snapshots); C-1 (expired gift not spendable, rechecked at confirmation); G-1 (gift from the Admin setting, not the browser). Tests on Staging: H1 34/34, C-1 9/9, G-1 8/8 (all inside transactions rolled back); Phase 0 self-check 0 failures; customers / transactions / merchants / top-ups / notes fingerprints identical before and after. No data deleted. | R4_h1-rollback (exact ACL), R5_c1-rollback, R5b_g1-rollback, R3_settings-rollback (only keys the batch added). |
