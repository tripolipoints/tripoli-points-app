#!/bin/bash
# Local run of phase 0 (PostgreSQL 16, roles anon/authenticated/service_role). Never points at Supabase.
# usage: run_phase0.sh <replica builder> ; prints one line per step.
set -u; B=$1; SEC=$(cd "$(dirname "$0")/.." && pwd); ROOT=$(dirname "$SEC")
P="psql -h /var/tmp -p 55432 -U postgres -X -q"
oct() { $P -d $1 -f $ROOT/tripoli-points-merchant-logo-security-tests.sql 2>&1 | grep -v "^psql.*NOTICE" | grep -vF '$2a$' | md5sum | cut -c1-12; }
p0t() { $P -d $1 -f $SEC/tp-security-phase0-tests.sql 2>&1 | tail -3 | head -1 | tr -s ' '; }
fail() { echo "FAIL: $*"; exit 1; }

# October tests change data (no rollback), so each side runs on a fresh copy
$B oc >/dev/null 2>&1 || fail build; $P -d oc -f $SEC/local-test/oct_fixtures.sql >/dev/null 2>&1; o1=$(oct oc)
$B oc >/dev/null 2>&1; $P -d oc -f $SEC/local-test/oct_fixtures.sql >/dev/null 2>&1
$P -d oc -v ON_ERROR_STOP=1 -f $SEC/tp-security-phase0-urgent.sql >/dev/null 2>&1 || fail "phase 0 on oc"; o2=$(oct oc)
[ "$o1" = "$o2" ] && echo "October tests: identical output without and with phase 0 ($o1)" || fail "October output changed"
$B r0 >/dev/null 2>&1 || fail build
$P -d r0 -v ON_ERROR_STOP=1 -f $SEC/tp-security-phase0-urgent.sql 2>&1 | grep -o "self-check: .*" || fail "phase 0 did not apply"
echo "phase 0 tests (passed|failed|total):$(p0t r0)"
$P -d r0 -v ON_ERROR_STOP=1 -f $SEC/tp-security-phase0-urgent.sql >/dev/null 2>&1 && echo "phase 0 re-run: idempotent, OK"

lock() { $P -d r0 -c "set role anon; select public.customer_verify_pin('$1','0000') from generate_series(1,5)" >/dev/null; }
locks() { $P -d r0 -Atc "select count(*) from auth_rate_limits where locked_until > now()"; }
$P -d r0 -c "insert into customers(phone,pin_hash,name,status) values ('70990001',extensions.crypt('1234',extensions.gen_salt('bf',4)),'r','active'),('70990002',extensions.crypt('1234',extensions.gen_salt('bf',4)),'r','active')" >/dev/null
lock 70990001; lock 70990002; echo "R1 two accounts locked: $(locks)"
sed "s/v_keys text\[\] := '{}';/v_keys text[] := array['customer:70990001'];/" $SEC/tp-security-phase0-urgent-rollback.sql > /tmp/rb_one.sql
$P -d r0 -v ON_ERROR_STOP=1 -f /tmp/rb_one.sql >/dev/null 2>&1 || fail "targeted unlock"
[ "$($P -d r0 -Atc "set role anon; select public.customer_verify_pin('70990001','1234')->>'ok'")" = "true" ] && [ "$(locks)" = 1 ] \
  && echo "R2 targeted unlock: 70990001 logs in, 70990002 still locked" || fail R2
$P -d r0 -v ON_ERROR_STOP=1 -f $SEC/tp-security-phase0-urgent-rollback.sql >/dev/null 2>&1 && [ "$(locks)" = 0 ] && echo "R3 unlock all: 0 locks left" || fail R3
for f in customer_verify_pin admin_verify_pin admin_wipe_all_data; do
  $P -d r0 -Atc "select prosrc like '%_rl_locked%' from pg_proc where proname='$f'" | grep -q t || fail "$f lost its limit"; done
echo "R4 after rollback: customer/admin/wipe still limited; wipe still closed: $($P -d r0 -Atc "select not has_function_privilege('anon','admin_wipe_all_data(uuid,text)','EXECUTE')")"
lock 70990002; $P -d r0 -c "grant execute on function admin_wipe_all_data(uuid,text) to anon" >/dev/null
out=$($P -d r0 -v ON_ERROR_STOP=1 -f $SEC/tp-security-phase0-urgent-rollback.sql 2>&1)
echo "$out" | grep -q "STOP" && [ "$(locks)" = 1 ] && echo "R5 a protection missing: rollback stops, nothing changed (lock kept) — $(echo "$out" | grep -o 'STOP[^.]*' | head -1)" || fail R5
$P -d r0 -c "revoke execute on function admin_wipe_all_data(uuid,text) from anon" >/dev/null
echo "phase 0 tests after the rollback runs:$(p0t r0)"
grep -v "^\s*--" $SEC/tp-security-phase0-urgent-rollback.sql | grep -ciE "create( or replace)? function|grant " | sed 's/^/R6 function definitions or grants in the rollback file: /'
$B r1 >/dev/null 2>&1; out=$($P -d r1 -v ON_ERROR_STOP=1 -f $SEC/tp-security-phase0-urgent-rollback.sql 2>&1)
echo "$out" | grep -q "not applied" && echo "R7 rollback on a database without phase 0: refuses, nothing changed" || fail R7
