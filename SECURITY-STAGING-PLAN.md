# Tripoli Points — security staging (preparation only)

This branch is **NOT ready to deploy**: `index.html` still targets production Supabase. Do not use it for live tests.

## Before staging
- Provision a separate database, after cost approval; seed only synthetic records.
- Configure separate staging URL and publishable key, with an obvious STAGING banner.
- No code merge, live deploy, production SQL or customer emails without explicit approval.

## Confirmed by read-only production catalog/function review
- Legacy destructive admin overloads were absent, old merchant PIN reset inaccessible to anon; inspected tables had RLS enabled.
- Several anon-callable SECURITY DEFINER functions lack caller verification: customer_reset_pin, decide_transaction, customer_create_request, admin_topup_merchant, admin_grant_customer_gift, admin_list_customers and admin_set_merchant_status.
- Customer and merchant transaction listing accepts a supplied phone/merchant identifier without verifying caller ownership.
- No transaction/request business idempotency indexes were found.

## Implementation order in isolated staging
1. Authenticated, server-verified customer/merchant/admin identities; verified email registration and safe PIN recovery; migrate existing accounts without losing points.
2. Server-side authorization on every RPC and privacy-sensitive read.
3. Lock/atomic guarded transaction status transition plus one-time ledger updates; server-enforced expiry; request idempotency keys.
4. Restrict admin mutation RPCs and record change audit logs.
5. Tests: QR outside/inside app; customer and merchant flows; two-device confirmation race; retries; cross-account access denial; account email recovery; balances; expiry.
6. Backups, review and separate approval before any production rollout.

Staging database not created; Supabase branch quoted US$0.01344/hour, needs separate cost approval.
