#!/usr/bin/env bash
# Automated preflight for the Batch 3-C integration SQL. Refuses anything that could persist or touch the wrong place.
# Usage: preflight.sh <file.sql>   → prints PREFLIGHT OK or the reasons it refused, exit code 0/1.
set -u
f="$1"; fail=0
note(){ echo "REFUSED: $1"; fail=1; }
body=$(sed -E 's/--.*$//' "$f")                                  # ignore comments
# 1. exactly one top-level DO block, and it must end by raising (→ full rollback)
[ "$(grep -cE '^do \$tp_it\$' "$f")" = 1 ] || note "must be exactly one DO \$tp_it\$ block"
grep -qE "raise exception 'TP_IT_RESULT" <<<"$body" || note "missing final RAISE EXCEPTION 'TP_IT_RESULT'"
tail -n 5 "$f" | grep -qE "raise exception 'TP_IT_RESULT|^end|^\\\$tp_it\\\$;" || note "the final RAISE must be the last statement"
# 2. no transaction control, DDL or bulk destruction
grep -qiE '\b(commit|rollback|savepoint|truncate|drop|alter|grant|revoke|vacuum|copy|create (table|function|schema|role|extension))\b' <<<"$body" && note "transaction control / DDL / COPY found"
grep -qiE '\bdelete\s+from\b' <<<"$body" && note "DELETE found"
grep -qiE 'public\.[a-z_0-9]*(wipe|restore|dangerous|backup_now)[a-z_0-9]*\s*\(' <<<"$body" && note "wipe / restore / backup / dangerous call found"
# 3. no outbound or server-file access
grep -qiE 'http_(get|post)|net\.http|dblink|pg_read_file|pg_ls_dir|lo_import|program' <<<"$body" && note "outbound/server-file access found"
# 4. protected flags must not be written
grep -qiE "(engine_setting|set_setting|app_settings).*(engine_strict|sub_enforce|email_delivery_enabled)" <<<"$body" && note "attempt to change a protected flag"
grep -qiE "update\s+public\.app_settings" <<<"$body" && note "direct settings update"
# 5. only synthetic identities; no production project reference
grep -oE "'7[0-9]{7}'" <<<"$body" | grep -vqE "'799970[0-9]{2}'" && note "phone outside the synthetic 799970xx range"
grep -qiE 'supabase\.co' <<<"$body" && note "hard-coded project URL"
# 6. guards present
grep -q "TP_IT_ABORT synthetic range already in use" <<<"$body" || note "missing synthetic-range guard"
grep -q "TP_IT_ABORT flags not as expected" <<<"$body" || note "missing flag guard"
[ $fail = 0 ] && echo "PREFLIGHT OK ($(wc -l <"$f") lines, md5 $(md5sum "$f" | cut -c1-12))"
exit $fail
