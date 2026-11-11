#!/bin/bash
# structure_roundtrip.sh <db> : export the structure of <db> (as the SQL editor would, CSV), rebuild it on an empty
# database with the Supabase basics (extensions/storage schemas, realtime publication) and compare. Local only.
T=$(cd "$(dirname "$0")" && pwd); SEC=$(dirname "$T"); SRC=$1; P="psql -h /var/tmp -p 55432 -U postgres -X -q"
$P -d $SRC --csv -f $SEC/tp-structure-export.sql > /tmp/$SRC.csv && python3 $T/structure_csv_to_sql.py /tmp/$SRC.csv /tmp/${SRC}_structure.sql
$P -d postgres -c "drop database if exists ${SRC}_r" -c "create database ${SRC}_r" >/dev/null 2>&1
$P -d ${SRC}_r -c "create schema extensions; create schema storage; create table storage.buckets(id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]); create table storage.objects(id uuid); alter table storage.objects enable row level security; create publication supabase_realtime;" >/dev/null 2>&1
$P -d ${SRC}_r -v ON_ERROR_STOP=1 -f /tmp/${SRC}_structure.sql 2>&1 | grep -v "WARNING\|HINT" | head -5
for d in $SRC ${SRC}_r; do pg_dump -h /var/tmp -p 55432 -U postgres -s -N storage -N extensions $d | grep -v '^\\restrict\|^\\unrestrict\|^GRANT\|^REVOKE' > /tmp/dump_$d.sql; done
echo "structure diff (grant order ignored, test publication excluded): $(diff /tmp/dump_$SRC.sql /tmp/dump_${SRC}_r.sql | grep -c '^[<>]') lines"
