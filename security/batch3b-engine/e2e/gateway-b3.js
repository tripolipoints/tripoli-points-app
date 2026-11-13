// Like hotfix-h1/e2e/gateway.js (every call as role anon on a LOCAL database), plus PostgREST's handling of array
// arguments: a JSON array sent for a text[] parameter becomes a Postgres array (jsonb parameters stay JSON).
const { spawnSync } = require('child_process');
const PSQL = ['-h', '/var/tmp', '-p', '55432', '-U', 'postgres', '-At', '-q', '-v', 'ON_ERROR_STOP=1'];
const q = v => '$tpq$' + String(v) + '$tpq$';
const meta = {};
function psql(db, sql) { return spawnSync('psql', [...PSQL, '-d', db], { input: sql, encoding: 'utf8' }); }
function info(db, fn) {
  if (meta[db + fn]) return meta[db + fn];
  const out = psql(db, `select bool_or(prorettype='void'::regtype)::text || '|' || coalesce(string_agg(distinct a.n || ':' || format_type(a.t, null), ','), '') from pg_proc p left join lateral unnest(p.proargnames, p.proargtypes::oid[]) a(n, t) on true where p.proname='${fn}' and p.pronamespace='public'::regnamespace;`).stdout.trim();
  const [v, a] = out.split('|'); const types = {}; (a || '').split(',').filter(Boolean).forEach(x => { const [n, t] = x.split(':'); types[n] = t });
  return meta[db + fn] = { isVoid: v === 'true', types };
}
function lit(v, t) {
  if (v === null || v === undefined) return 'NULL';
  if (Array.isArray(v) && t && t.endsWith('[]')) return `ARRAY[${v.map(x => x === null ? 'NULL' : q(x)).join(',')}]::${t}`;
  return q(typeof v === 'object' ? JSON.stringify(v) : v);
}
function rpc(db, fn, args) {
  if (!/^[a-z_0-9]+$/.test(fn)) return { status: 404, body: { message: 'bad function', code: 'PGRST202' } };
  const m = info(db, fn);
  const named = Object.entries(args || {}).map(([k, v]) => `${k} => ${lit(v, m.types[k])}`).join(', ');
  const call = `public.${fn}(${named})`;
  const sql = `set role anon;\n` + (m.isVoid ? `select ${call};\nselect 'null';\n` : `select coalesce(to_jsonb(${call})::text, 'null');\n`);
  const r = psql(db, sql);
  if (r.status !== 0) {
    const msg = (r.stderr.match(/ERROR:\s+(.*)/) || [, r.stderr])[1].trim();
    const denied = /permission denied/.test(msg);
    return { status: denied ? 401 : 400, body: { message: msg, code: denied ? '42501' : 'P0001', details: null, hint: null } };
  }
  return { status: 200, body: r.stdout.trim().split('\n').pop() };
}
module.exports = { rpc, psql };
