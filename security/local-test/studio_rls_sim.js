// Simulates the Supabase SQL editor "RLS enabled" option as far as it can be seen from Studio's code
// (apps/studio/lib/sql-event-parser.ts): every table that its "table created" detectors find in the query text
// (CREATE TABLE [IF NOT EXISTS], TEMP/UNLOGGED, CREATE TABLE … AS SELECT, SELECT … INTO) gets an added
// "alter table <name> enable row level security". Patterns re-written from the description of that file.
// usage: node studio_rls_sim.js file.sql   → prints the detections, then writes the SQL that would be sent to stdout.
const fs = require('fs');
const ID = '(?:"(?:[^"]|"")+"|`(?:[^`]|``)+`|[\\w]+)';
const T = `(?<schema>(?:"[^"]+"|[\\w]+)\\.)?(?<table>${ID})`;
const pats = [
  new RegExp(`CREATE\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?${T}`, 'ig'),
  new RegExp(`CREATE\\s+(?:TEMP|TEMPORARY)\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?${T}`, 'ig'),
  new RegExp(`CREATE\\s+UNLOGGED\\s+TABLE\\s+(?:IF\\s+NOT\\s+EXISTS\\s+)?${T}`, 'ig'),
  new RegExp(`SELECT\\s+.*?\\s+INTO\\s+${T}`, 'igs'),
];
const s = fs.readFileSync(process.argv[2], 'utf8'); const found = new Set();
for (const re of pats) { let m; while ((m = re.exec(s))) found.add((m.groups.schema || '') + m.groups.table); }
console.error('tables the editor would think are created:', [...found]);
process.stdout.write(s + [...found].map(t => `\nalter table ${t} enable row level security;`).join('') + '\n');
