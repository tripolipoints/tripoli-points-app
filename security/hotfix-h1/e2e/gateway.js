// Minimal local stand-in for Supabase's REST RPC endpoint (PostgREST), for end-to-end tests of the real app.
// Every call runs as role anon (exactly what the public API key does), against a LOCAL PostgreSQL replica only.
const { spawnSync } = require('child_process');
const PSQL = ['-h', '/var/tmp', '-p', '55432', '-U', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=1'];
const lit = v => v === null || v === undefined ? 'NULL' : '$tpq$' + (typeof v === 'object' ? JSON.stringify(v) : String(v)) + '$tpq$';
const voidCache = {};
function psql(db, sql) { return spawnSync('psql', [...PSQL, '-d', db], { input: sql, encoding: 'utf8' }); }
function rpc(db, fn, args) {
  if (!/^[a-z_0-9]+$/.test(fn)) return { status: 404, body: { message: 'bad function', code: 'PGRST202' } };
  if (!(db + fn in voidCache)) voidCache[db + fn] = psql(db, `select bool_or(prorettype='void'::regtype) from pg_proc where proname='${fn}' and pronamespace='public'::regnamespace;`).stdout.trim() === 't';
  const named = Object.entries(args || {}).map(([k, v]) => `${k} => ${lit(v)}`).join(', ');
  const call = `public.${fn}(${named})`;
  const sql = `set role anon;\n` + (voidCache[db + fn] ? `select ${call};\nselect 'null';\n` : `select coalesce(to_jsonb(${call})::text, 'null');\n`);
  const r = psql(db, sql);
  if (r.status !== 0) {
    const m = (r.stderr.match(/ERROR:\s+(.*)/) || [, r.stderr])[1].trim();
    const denied = /permission denied/.test(m);
    return { status: denied ? 401 : 400, body: { message: m, code: denied ? '42501' : 'P0001', details: null, hint: null } };
  }
  const out = r.stdout.trim().split('\n').pop();
  return { status: 200, body: out };
}
module.exports = { rpc, psql };
