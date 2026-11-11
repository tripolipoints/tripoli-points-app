Local test harness used to check the phase 1 files before review (PostgreSQL 16 + pgcrypto, roles anon/authenticated/service_role).
- replica_base.sql — Production schema from a read-only dump (2026-11-11) plus the functions phase 1 calls, copied verbatim.
- replica_stubs.sql — the other old functions with their exact signatures; they echo their arguments so the *_v2 wrappers can be checked.
- gen.py — generates the pass-through *_v2 wrappers, the landmark seed and the grants of tp-secure-purchase-v1.sql.
Order: replica_base → replica_stubs → tp-secure-purchase-v1 → tp-secure-purchase-v1-tests (91/91) → rollback → schema identical.
