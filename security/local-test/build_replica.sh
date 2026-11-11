#!/bin/bash
# build_replica.sh <db> : local copy equivalent to Production today (October applied, nothing of phases 0/1/email)
set -e; DB=$1; T=$(cd "$(dirname "$0")" && pwd); ROOT=$(cd "$T/../.." && pwd)
P="psql -h /var/tmp -p 55432 -U postgres -v ON_ERROR_STOP=1 -q"
$P -d postgres -c "drop database if exists $DB" -c "create database $DB" >/dev/null
for f in replica_base.sql replica_stubs.sql oct_prereq.sql phase0_prereq.sql; do $P -d $DB -f $T/$f >/dev/null; done
PGOPTIONS='-c search_path=public,extensions' $P -d $DB -f $ROOT/tripoli-points-merchant-logo-migration.sql >/dev/null
