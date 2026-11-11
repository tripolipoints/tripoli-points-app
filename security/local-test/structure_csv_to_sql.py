#!/usr/bin/env python3
# Turns the CSV downloaded from the Supabase SQL editor (tp-structure-export.sql v3) into a runnable .sql file
# and checks it is complete: number of statements and md5 must match row 0 of the export.
# usage: python3 structure_csv_to_sql.py export.csv staging_structure.sql
import csv, sys, hashlib, re
csv.field_size_limit(10**9)
rows = list(csv.DictReader(open(sys.argv[1], encoding='utf-8-sig', newline='')))
head = next(r for r in rows if int(r['part']) == 0)['info']
parts = sorted((r for r in rows if int(r['part']) > 0), key=lambda r: int(r['part']))
body = '\n'.join(r['sql'] for r in parts)
want = dict(x.split('=', 1) for x in head.split())
print('export header:', head)
got_md5 = hashlib.md5(body.encode('utf-8')).hexdigest()
n_rows = len(parts)
last = max(int(r['info'].split()[-1].split('-')[1]) for r in parts)
ok = got_md5 == want['md5'] and n_rows == int(want['rows']) and last == int(want['statements'])
print(f"rows {n_rows}/{want['rows']}  statements {last}/{want['statements']}  md5 {'OK' if got_md5 == want['md5'] else 'MISMATCH'}")
if not ok: sys.exit('INCOMPLETE OR CHANGED DOWNLOAD — do not use')
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write('-- generated from the structure export CSV; run on an EMPTY Supabase project\nbegin;\n' + body + '\ncommit;\n')
