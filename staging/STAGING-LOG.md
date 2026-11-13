# Staging log (staging-netlify)

Every Staging batch, data reset and test account change is recorded here. Production and main are never touched.

| Date | Batch | Commit / file | What changed on Staging | Rollback |
|---|---|---|---|---|
| 2026-11-13 | 1 — environment sync | this commit | Site code = main V3.7.4 (a54a85c) + Staging build files; build step 2b serves map images from local files (no Production Storage). No database change. | Netlify: publish the previous deploy. Git: revert this merge; backup branch `backup/staging-netlify-48ecdaa-20261113` = previous head 48ecdaa. |

## Test accounts

No account was reset or created by Batch 1.
