Local test harness (PostgreSQL 16 + pgcrypto, roles anon / authenticated / service_role). Never points at Supabase.
- replica_base.sql — Production schema from a read-only dump (2026-11-11) plus the functions the phases call, verbatim.
- replica_stubs.sql — the other old functions with their exact signatures; they echo their arguments.
- oct_prereq.sql, phase0_prereq.sql — Production's pre-October / pre-phase-0 bodies of the functions those files replace.
- oct_fixtures.sql — the two merchants / two admins the October tests expect.
- build_replica.sh <db> — builds a copy equal to Production today (October applied).
- pgup.sh — starts the local PostgreSQL 16 (port 55432, socket /var/tmp).
- run_phase0.sh — phase 0 v1.3 end to end (50 checks): October tests identical, three starting states (Production,
  Staging with Whish/gift closed keeping or not keeping service_role), pre-flight and final guards, safe rollback
  (default no change, named keys only, wildcards refused), DANGEROUS unlock-all refusals, full stack with phase 1 + e-mail.
- gen.py — generates the *_v2 wrappers, the landmark seed and the grants of tp-secure-purchase-v1.sql.
Full order used for the report: build_replica → phase 0 → phase 0 tests (70) → phase 1 → phase 1 tests (104) →
phase 0 tests again → e-mail → e-mail tests (48) → phase 1 + phase 0 tests again → e-mail rollback (schema identical
to after phase 1) → phase 1 rollback (schema identical to after phase 0) → phase 0 tests again.
