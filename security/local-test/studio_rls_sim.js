// Simulates the Supabase SQL editor "RLS enabled" behaviour assumed here: it looks for CREATE TABLE in the text with
// Studio's own detector pattern (apps/studio/lib/sql-event-parser.ts) and adds "alter table <name> enable row level
// security" for each table found. Prints the SQL that would be sent.
const fs = require('fs');
const re = /CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?<schema>(?:"[^"]+"|[\w]+)\.)?(?<table>(?:"(?:[^"]|"")+"|`(?:[^`]|``)+`|[\w]+))/ig;
const s = fs.readFileSync(process.argv[2], 'utf8'); let m, extra = '';
while ((m = re.exec(s))) extra += `\nalter table ${(m.groups.schema || '')}${m.groups.table} enable row level security;`;
process.stdout.write(s + extra + '\n');
