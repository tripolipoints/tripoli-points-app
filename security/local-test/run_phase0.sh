#!/bin/bash
# Phase 0 v1.3 — local end-to-end run (PostgreSQL 16 on /var/tmp:55432). NEVER points at Supabase.
# usage: local-test/run_phase0.sh        prints one PASS/FAIL line per check and a summary.
set -u
T=$(cd "$(dirname "$0")" && pwd); SEC=$(dirname "$T"); ROOT=$(dirname "$SEC")
B=$T/build_replica.sh
P="psql -h /var/tmp -p 55432 -U postgres -X -q"
PASS=0; FAIL=0
ok()   { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "PASS  $1"; else FAIL=$((FAIL+1)); echo "FAIL  $1 ${3:-}"; fi; }
q()    { $P -d "$1" -Atc "$2" 2>&1; }
apply(){ $P -d "$1" -v ON_ERROR_STOP=1 -f "$2" 2>&1; }
p0t()  { $P -d "$1" -f $SEC/tp-security-phase0-tests.sql 2>&1 | tail -3 | head -1 | tr -s ' '; }
state(){ # everything that matters, as text: privileges of every API key, function bodies, lock rows, data counts
  q "$1" "select string_agg(x, E'\n' order by x) from (
     select 'F '||r||' '||p.oid::regprocedure||' '||has_function_privilege(r,p.oid,'EXECUTE') x from pg_proc p, unnest(array['anon','authenticated','service_role']) r where p.pronamespace='public'::regnamespace
     union all select 'S '||p.oid::regprocedure||' '||md5(prosrc) from pg_proc p where p.pronamespace='public'::regnamespace
     union all select 'T '||r||' '||c.relname||' '||has_table_privilege(r,c.oid,'SELECT,INSERT,UPDATE,DELETE') from pg_class c, unnest(array['anon','authenticated','service_role']) r where c.relnamespace='public'::regnamespace and c.relkind='r'
     union all select 'L '||key||' '||fail_count||' '||coalesce(locked_until::text,'-') from auth_rate_limits
     union all select 'D customers '||count(*) from customers union all select 'D merchants '||count(*) from merchants) z" | md5sum | cut -c1-12; }
octo() { $P -d "$1" -f $ROOT/tripoli-points-merchant-logo-security-tests.sql 2>&1 | grep -v "^psql.*NOTICE" | grep -vF '$2a$' | md5sum | cut -c1-12; }
lock() { q "$1" "set role anon; select public.customer_verify_pin('$2','0000') from generate_series(1,5)" >/dev/null; }
locked(){ q "$1" "select count(*) from auth_rate_limits where locked_until > now()"; }
mkcust(){ q "$1" "insert into customers(phone,pin_hash,name,status) values ('$2',extensions.crypt('1234',extensions.gen_salt('bf',4)),'r','active')" >/dev/null; }
echo "== 1. October tests unchanged by phase 0"
$B oc >/dev/null 2>&1; $P -d oc -f $T/oct_fixtures.sql >/dev/null 2>&1; o1=$(octo oc)
$B oc >/dev/null 2>&1; $P -d oc -f $T/oct_fixtures.sql >/dev/null 2>&1; apply oc $SEC/tp-security-phase0-urgent.sql >/dev/null; o2=$(octo oc)
ok "October security tests: identical output without and with phase 0 ($o1)" $([ "$o1" = "$o2" ]; echo $?)

echo "== 2. starting states (Production today; Staging variants)"
for S in prod stg_svc stg_closed; do
  $B s_$S >/dev/null 2>&1
  case $S in
    stg_svc)    q s_$S "revoke execute on function whish_confirm_payment(uuid,text,numeric,bigint), whish_set_collect_url(uuid,text,bigint), admin_grant_customer_gift(text,numeric,integer) from public, anon, authenticated;
                         grant execute on function whish_confirm_payment(uuid,text,numeric,bigint), whish_set_collect_url(uuid,text,bigint), admin_grant_customer_gift(text,numeric,integer) to service_role" >/dev/null;;
    stg_closed) q s_$S "revoke execute on function whish_confirm_payment(uuid,text,numeric,bigint), whish_set_collect_url(uuid,text,bigint), admin_grant_customer_gift(text,numeric,integer) from public, anon, authenticated, service_role" >/dev/null;;
  esac
  before=$(q s_$S "select string_agg(r||':'||has_function_privilege(r,f::regprocedure,'EXECUTE'), ' ' order by f, r) from unnest(array['whish_confirm_payment(uuid,text,numeric,bigint)','whish_set_collect_url(uuid,text,bigint)','admin_grant_customer_gift(text,numeric,integer)']) f, unnest(array['anon','authenticated','service_role']) r")
  out=$(apply s_$S $SEC/tp-security-phase0-urgent.sql); rc=$?
  ok "$S: phase 0 applies; self-check + no-gain guard pass" $([ $rc = 0 ] && echo "$out" | grep -q "no API key gained"; echo $?) "$(echo "$out" | grep -E 'ERROR|STOP' | head -2)"
  after=$(q s_$S "select string_agg(r||':'||has_function_privilege(r,f::regprocedure,'EXECUTE'), ' ' order by f, r) from unnest(array['whish_confirm_payment(uuid,text,numeric,bigint)','whish_set_collect_url(uuid,text,bigint)','admin_grant_customer_gift(text,numeric,integer)']) f, unnest(array['anon','authenticated','service_role']) r")
  svc_b=$(echo "$before" | tr ' ' '\n' | grep service_role); svc_a=$(echo "$after" | tr ' ' '\n' | grep service_role)
  ok "$S: Whish + gift: service_role keeps exactly what it had ($(echo $svc_a | tr '\n' ' '))" $([ "$svc_b" = "$svc_a" ]; echo $?)
  ok "$S: Whish + gift closed to anon/authenticated" $(echo "$after" | tr ' ' '\n' | grep -E '^(anon|authenticated):t' -q; [ $? = 1 ]; echo $?)
  r=$(p0t s_$S); ok "$S: behavioural tests: $r" $(echo "$r" | grep -q "| 0 |"; echo $?)
  s1=$(state s_$S); apply s_$S $SEC/tp-security-phase0-urgent.sql >/dev/null; s2=$(state s_$S)
  ok "$S: re-running phase 0 changes nothing (idempotent)" $([ "$s1" = "$s2" ]; echo $?)
done

echo "== 3. pre-flight stops before changing anything"
$B pf >/dev/null 2>&1
q pf "create or replace function public.customer_verify_pin(p_phone text, p_pin text) returns jsonb language plpgsql security definer set search_path to 'public','extensions' as \$\$ begin return jsonb_build_object('ok', false, 'reason', 'staging_variant'); end \$\$" >/dev/null
s1=$(state pf); out=$(apply pf $SEC/tp-security-phase0-urgent.sql); s2=$(state pf)
ok "a different customer_verify_pin: STOP with its fingerprint, nothing changed" $(echo "$out" | grep -q "differs from the reviewed version" && [ "$s1" = "$s2" ]; echo $?)
$B pf >/dev/null 2>&1; q pf "drop function public._rl_reset(text)" >/dev/null
s1=$(state pf); out=$(apply pf $SEC/tp-security-phase0-urgent.sql); s2=$(state pf)
ok "October fixes missing: STOP, nothing changed" $(echo "$out" | grep -q "October 2026 fixes are missing" && [ "$s1" = "$s2" ]; echo $?)
$B pf >/dev/null 2>&1; s1=$(state pf)
inj() { sed "0,/^-- ---------------------------------------------------------------- final guard/s//$1\n&/" $SEC/tp-security-phase0-urgent.sql | $P -d pf -v ON_ERROR_STOP=1 2>&1; }
out=$(inj "grant execute on function public.customer_reset_pin(text,text) to anon;"); s2=$(state pf)
ok "final guard: customer_reset_pin re-opened late in the file is caught, nothing changed" $(echo "$out" | grep -q "protection missing at the end" && [ "$s1" = "$s2" ]; echo $?)
out=$(inj "grant execute on function public._phase0_selfcheck() to anon;"); s2=$(state pf)
ok "final guard: an access anon never had (new owner-only function) is caught, nothing changed" $(echo "$out" | grep -q "would give access" && [ "$s1" = "$s2" ]; echo $?)
out=$(inj "revoke execute on function public.whish_confirm_payment(uuid,text,numeric,bigint) from service_role;"); s2=$(state pf)
ok "final guard: Whish access removed from service_role is caught, nothing changed" $(echo "$out" | grep -q "would lose access" && [ "$s1" = "$s2" ]; echo $?)

echo "== 4. safe rollback (default changes nothing; named accounts only)"
D=s_prod; mkcust $D 70990001; mkcust $D 70990002; mkcust $D 70990003; lock $D 70990001; lock $D 70990002; lock $D 70990003
s1=$(state $D); out=$(apply $D $SEC/tp-security-phase0-urgent-rollback.sql); s2=$(state $D)
ok "default run: 3 locks stay, no privilege/function/data change" $([ "$s1" = "$s2" ] && [ "$(locked $D)" = 3 ] && echo "$out" | grep -q "no lock released (default)"; echo $?)
ok "default run: nothing logged as released" $([ "$(q $D 'select count(*) from tp_backup.lock_releases')" = 0 ]; echo $?)
rb() { sed "s/  v_keys   text\[\] := '{}';/  v_keys   text[] := $1;/; s/  v_reason text   := '';/  v_reason text   := '$2';/" $SEC/tp-security-phase0-urgent-rollback.sql; }
s1=$(state $D); out=$(rb "array['customer:70990001']" "" | $P -d $D -v ON_ERROR_STOP=1 2>&1); s2=$(state $D)
ok "a key without a reason: refused, nothing changed" $(echo "$out" | grep -q "write the reason" && [ "$s1" = "$s2" ]; echo $?)
for bad in "customer:%" "customer:" "*" "customer:7099000_" "customer:70990001' or '1'='1"; do
  s1=$(state $D); out=$(rb "array['${bad//\'/\'\'}']" "support ticket 1" | $P -d $D -v ON_ERROR_STOP=1 2>&1); s2=$(state $D)
  ok "pattern/wildcard key \"$bad\": refused, nothing changed" $(echo "$out" | grep -q "not an exact account key" && [ "$s1" = "$s2" ]; echo $?)
done
out=$(rb "array['customer:70990001']" "customer called, identity checked" | $P -d $D -v ON_ERROR_STOP=1 2>&1)
ok "named key: only 70990001 released (2 locks stay)" $([ "$(q $D "set role anon; select public.customer_verify_pin('70990001','1234')->>'ok'")" = true ] && [ "$(locked $D)" = 2 ]; echo $?)
ok "named key: release logged with reason and the old record" $([ "$(q $D "select count(*) from tp_backup.lock_releases where key='customer:70990001' and reason like 'customer called%' and (record->>'fail_count')::int >= 5")" = 1 ]; echo $?)
lock $D 70990001
ok "after the rollback the PIN limit still works: 5 wrong PINs lock 70990001 again" $([ "$(q $D "set role anon; select public.customer_verify_pin('70990001','1234')->>'reason'")" = locked ]; echo $?)
for f in customer_verify_pin admin_verify_pin admin_wipe_all_data; do
  ok "after the rollback $f still has its limit" $(q $D "select prosrc like '%_rl_locked%' and prosrc like '%tp-phase0%' from pg_proc where proname='$f'" | grep -q t; echo $?); done
ok "after the rollback: customer_reset_pin, whish_confirm_payment, wipe still closed to anon + authenticated" $([ "$(q $D "select bool_or(has_function_privilege(r,f::regprocedure,'EXECUTE')) from unnest(array['customer_reset_pin(text,text)','whish_confirm_payment(uuid,text,numeric,bigint)','admin_wipe_all_data(uuid,text)']) f, unnest(array['anon','authenticated']) r")" = f ]; echo $?)
q $D "grant execute on function admin_wipe_all_data(uuid,text) to anon" >/dev/null; lb=$(locked $D)
out=$(rb "array['customer:70990002']" "should be undone" | $P -d $D -v ON_ERROR_STOP=1 2>&1)
ok "a protection missing: rollback STOPS and its unlock is undone ($lb locks stay)" $(echo "$out" | grep -q "STOP" && [ "$(locked $D)" = "$lb" ] && [ "$(q $D "select count(*) from tp_backup.lock_releases where reason='should be undone'")" = 0 ]; echo $?)
q $D "revoke execute on function admin_wipe_all_data(uuid,text) from anon" >/dev/null
n=$(grep -v '^\s*--' $SEC/tp-security-phase0-urgent-rollback.sql | grep -ciE 'create( or replace)? function|grant |delete from public.auth_rate_limits;|truncate')
ok "rollback file: no function definition, no GRANT, no unconditional delete" $([ "$n" = 0 ]; echo $?)
$B nop0 >/dev/null 2>&1; s1=$(state nop0); out=$(apply nop0 $SEC/tp-security-phase0-urgent-rollback.sql); s2=$(state nop0)
ok "rollback on a database without phase 0: refuses, nothing changed" $(echo "$out" | grep -q "not applied" && [ "$s1" = "$s2" ]; echo $?)
r=$(p0t $D); ok "behavioural tests after all rollback runs: $r" $(echo "$r" | grep -q "| 0 |"; echo $?)

echo "== 5. DANGEROUS unlock-all (separate file, typed confirmation)"
s1=$(state $D); out=$(apply $D $SEC/tp-security-DANGEROUS-unlock-all-pin-locks.sql); s2=$(state $D)
ok "as shipped: REFUSED, nothing changed" $(echo "$out" | grep -q "REFUSED" && [ "$s1" = "$s2" ]; echo $?)
ua() { sed "s/  v_confirm text := '';/  v_confirm text := '$1';/; s/  v_reason  text := '';/  v_reason  text := '$2';/" $SEC/tp-security-DANGEROUS-unlock-all-pin-locks.sql; }
s1=$(state $D); out=$(ua "RELEASE ALL PIN LOCKS 2000-01-01" "app bug sent wrong PINs" | $P -d $D -v ON_ERROR_STOP=1 2>&1); s2=$(state $D)
ok "wrong date in the phrase: REFUSED, nothing changed" $(echo "$out" | grep -q "REFUSED" && [ "$s1" = "$s2" ]; echo $?)
today=$(q $D "select to_char(now() at time zone 'UTC','YYYY-MM-DD')"); nrec=$(q $D "select count(*) from auth_rate_limits")
out=$(ua "RELEASE ALL PIN LOCKS $today" "app bug sent wrong PINs, fixed" | $P -d $D -v ON_ERROR_STOP=1 2>&1)
ok "exact phrase + reason: every record released ($nrec), each logged, protections re-checked" $([ "$(q $D 'select count(*) from auth_rate_limits')" = 0 ] && [ "$(q $D "select count(*) from tp_backup.lock_releases where reason like 'ALL:%'")" = "$nrec" ]; echo $?)
n=$(grep -v '^\s*--' $SEC/tp-security-DANGEROUS-reopen-phase0.sql | grep -c '[^[:space:]]')
ok "DANGEROUS reopen file: every statement commented out" $([ "$n" = 0 ]; echo $?)

echo "== 6. full stack: phase 1 + e-mail on top, their rollbacks keep phase 0"
F=fs; $B $F >/dev/null 2>&1; apply $F $SEC/tp-security-phase0-urgent.sql >/dev/null
pg_dump -h /var/tmp -p 55432 -U postgres -s $F | grep -v restrict > /tmp/fs_p0.sql
apply $F $SEC/tp-secure-purchase-v1.sql >/dev/null; r=$($P -d $F -f $SEC/tp-secure-purchase-v1-tests.sql 2>&1 | tail -3 | head -1 | tr -s ' ')
ok "phase 1 tests: $r" $(echo "$r" | grep -q "| 0 |"; echo $?)
pg_dump -h /var/tmp -p 55432 -U postgres -s $F | grep -v restrict > /tmp/fs_p1.sql
apply $F $SEC/tp-auth-email-v1.sql >/dev/null; r=$($P -d $F -f $SEC/tp-auth-email-v1-tests.sql 2>&1 | tail -3 | head -1 | tr -s ' ')
ok "e-mail tests: $r" $(echo "$r" | grep -q "| 0 |"; echo $?)
r=$(p0t $F); ok "phase 0 tests with phase 1 + e-mail: $r" $(echo "$r" | grep -q "| 0 |"; echo $?)
apply $F $SEC/tp-auth-email-v1-rollback.sql >/dev/null; pg_dump -h /var/tmp -p 55432 -U postgres -s $F | grep -v restrict > /tmp/fs_p1b.sql
ok "e-mail rollback: schema identical to after phase 1" $(diff -q /tmp/fs_p1.sql /tmp/fs_p1b.sql >/dev/null; echo $?)
apply $F $SEC/tp-secure-purchase-v1-rollback.sql >/dev/null; pg_dump -h /var/tmp -p 55432 -U postgres -s $F | grep -v restrict > /tmp/fs_p0b.sql
ok "phase 1 rollback: schema identical to after phase 0 (phase 0 protections intact)" $(diff -q /tmp/fs_p0.sql /tmp/fs_p0b.sql >/dev/null; echo $?)
r=$(p0t $F); ok "phase 0 tests after both rollbacks: $r" $(echo "$r" | grep -q "| 0 |"; echo $?)

echo "== summary: $PASS passed, $FAIL failed"
[ $FAIL = 0 ]
