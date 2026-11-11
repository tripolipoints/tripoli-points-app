#!/usr/bin/env python3
# Turns the CSV downloaded from the Supabase SQL editor (tp-structure-export.sql) into a runnable .sql file.
# usage: python3 structure_csv_to_sql.py export.csv staging_structure.sql
import csv, sys
csv.field_size_limit(10**9)
rows = list(csv.DictReader(open(sys.argv[1], encoding='utf-8', newline='')))
rows.sort(key=lambda r: int(r['n']))
with open(sys.argv[2], 'w', encoding='utf-8') as f:
    f.write('-- generated from the structure export CSV; run on an EMPTY Supabase project (SQL editor or psql)\nbegin;\n')
    for r in rows:
        f.write(r['sql'].rstrip() + '\n')
    f.write('commit;\n')
print(len(rows), 'statements')
