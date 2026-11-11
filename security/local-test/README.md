Local test harness (PostgreSQL 16 + pgcrypto, roles anon / authenticated / service_role). Never points at Supabase.
- replica_base.sql — Production schema from a read-only dump (2026-11-11) plus the functions the phases call, verbatim.
- replica_stubs.sql — the other old functions with their exact signatures; they echo their arguments.
- oct_prereq.sql, phase0_prereq.sql — Production's pre-October / pre-phase-0 bodies of the functions those files replace.
- oct_fixtures.sql — the two merchants / two admins the October tests expect.
- build_replica.sh <db> — builds a copy equal to Production today (October applied).
- run_phase0.sh build_replica.sh — phase 0 end to end: October tests identical without/with phase 0, self-check,
  behavioural tests, re-run, and the safe rollback (targeted unlock, unlock all, protections kept, stops when a
  protection is missing, refuses on a database without phase 0, no function/grant in the file).
- gen.py — generates the *_v2 wrappers, the landmark seed and the grants of tp-secure-purchase-v1.sql.
Full order used for the report: build_replica → phase 0 → phase 0 tests (55) → phase 1 → phase 1 tests (104) →
phase 0 tests again → e-mail → e-mail tests (48) → phase 1 + phase 0 tests again → e-mail rollback (schema identical
to after phase 1) → phase 1 rollback (schema identical to after phase 0) → phase 0 tests again.
