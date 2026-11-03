#!/usr/bin/env node
// Tripoli Points: STAGING build for Netlify.                                   Version 2, 3 Nov 2026
// v2: badge reports the QR button's state on the device; staging-only hero/QR style safeguard for iPhone Safari.
//
// Builds dist-staging/ from this branch's index.html (= GitHub main) for the STAGING Supabase project only.
// No dependencies (Node 18+). It never edits index.html in place; main and the live site are untouched.
//
// Required Netlify environment variables (STAGING site only):
//   TP_STAGING_SITE=yes                 refuses to build anywhere else (e.g. a branch deploy of the live site)
//   STAGING_SUPABASE_URL=https://axzlshimvtskkxknlwoz.supabase.co
//   STAGING_SUPABASE_KEY=<Staging anon JWT or sb_publishable_ key>   (the PUBLIC key; never a secret key)
//
// What the build does, and stops on failure:
//   1. checks the URL is exactly the Staging project, and the key is a public key (an anon JWT must name
//      project axzlshimvtskkxknlwoz; service_role JWTs and sb_secret_ keys are refused);
//   2. replaces the single SB_URL / SB_KEY definition and the Supabase preconnect (each must occur exactly once);
//   3. injects a network guard first in <head>: any request to another Supabase project or naming the
//      Production project is blocked in the page, counted and shown in a STAGING badge;
//   4. writes _headers with a Content-Security-Policy whose connect-src allows only Staging Supabase and the
//      map routing / image tools the app needs, so the browser itself refuses any Production database request;
//   5. copies only the site files (index.html, assets/), never the repository's .sql files;
//   6. scans every output file: the Production project reference and the Production key must not appear.
import { readFileSync, writeFileSync, mkdirSync, cpSync, rmSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'dist-staging');
const STAGING_REF = 'axzlshimvtskkxknlwoz';
const STAGING_URL = `https://${STAGING_REF}.supabase.co`;
const PROD_REF = 'lqbhfkowqaqlgcrdybvv';

const fail = (msg) => { console.error(`\nSTAGING BUILD STOPPED: ${msg}\nNothing was published.\n`); process.exit(1); };
const env = (k) => (process.env[k] || '').trim();

// ---------- 1. configuration checks ----------
if (env('TP_STAGING_SITE') !== 'yes') fail('TP_STAGING_SITE=yes is not set. This branch only builds on the Staging Netlify site.');
const url = env('STAGING_SUPABASE_URL').replace(/\/+$/, '');
const key = env('STAGING_SUPABASE_KEY');
if (url !== STAGING_URL) fail(`STAGING_SUPABASE_URL must be exactly ${STAGING_URL}.`);
if (!key) fail('STAGING_SUPABASE_KEY is empty.');
if (key.includes(PROD_REF)) fail('the key names the Production project.');
if (/^sb_secret_/i.test(key)) fail('a secret key (sb_secret_) was given. Use the public anon / publishable key.');
let keyKind;
if (/^sb_publishable_[A-Za-z0-9_-]{10,}$/.test(key)) {
  keyKind = 'publishable key (project checked at run time by the STAGING badge)';
} else if (/^eyJ[\w-]+\.[\w-]+\.[\w-]+$/.test(key)) {
  let p;
  try { p = JSON.parse(Buffer.from(key.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'), 'base64').toString('utf8')); }
  catch { fail('the key looks like a JWT but cannot be read.'); }
  if (p.role !== 'anon') fail(`the JWT role is "${p.role}", not "anon". Never use the service_role key in a browser build.`);
  if (p.ref !== STAGING_REF) fail(`the anon key belongs to project "${p.ref}", not Staging (${STAGING_REF}).`);
  keyKind = 'anon JWT for project ' + p.ref;
} else fail('STAGING_SUPABASE_KEY is neither an anon JWT nor an sb_publishable_ key.');

// ---------- 2. rewrite the one Supabase definition ----------
let html = readFileSync(join(ROOT, 'index.html'), 'utf8');
const urlRe = /const SB_URL='https:\/\/[a-z0-9]+\.supabase\.co';/g;
const keyRe = /const SB_KEY='([^']+)';/g;
const pre = /<link rel="preconnect" href="https:\/\/[a-z0-9]+\.supabase\.co" crossorigin>/g;
const count = (re) => (html.match(re) || []).length;
if (count(urlRe) !== 1) fail(`expected exactly one SB_URL definition in index.html, found ${count(urlRe)}. index.html changed: update this script.`);
if (count(keyRe) !== 1) fail(`expected exactly one SB_KEY definition in index.html, found ${count(keyRe)}.`);
const prodKey = [...html.matchAll(keyRe)][0][1];
html = html.replace(urlRe, `const SB_URL='${STAGING_URL}';`)
           .replace(keyRe, `const SB_KEY='${key}';`)
           .replace(pre, `<link rel="preconnect" href="${STAGING_URL}" crossorigin>`);

// ---------- 3. network guard + STAGING badge (first script in <head>) ----------
const commit = env('COMMIT_REF').slice(0, 7) || 'local';
const builtAt = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
const guard = `<meta name="robots" content="noindex,nofollow">
<style id="tpStagingQrFix">/* STAGING ONLY: keep the hero QR pill above the banner on iPhone Safari */
.hero2{isolation:isolate;-webkit-mask-image:-webkit-radial-gradient(white,black)}
.hero2 .qrsHero{z-index:3;-webkit-transform:translateZ(0);transform:translateZ(0)}
@supports not (aspect-ratio:1/1){.hero2{height:42vw!important;min-height:122px}}
</style>
<script>/* Tripoli Points STAGING network guard (build ${commit}, ${builtAt}) */
(function(){var OK='${STAGING_REF}.supabase.co',BAD='${PROD_REF}',st={db:0,blocked:0,log:[],ref:'${STAGING_REF}',commit:'${commit}',built:'${builtAt}'};
window.__TP_STAGING=st;
function host(u){try{return new URL(String(u),location.href).host}catch(e){return''}}
function allowed(u){var s=String(u),h=host(s);if(s.indexOf(BAD)>=0)return false;if(/(^|\\.)supabase\\.(co|in|net)$/.test(h)&&h!==OK)return false;if(h===OK)st.db++;return true}
function note(u,how){st.blocked++;st.log.push(how+' '+String(u).slice(0,90));draw()}
var f=window.fetch;window.fetch=function(i,o){var u=i&&i.url?i.url:i;if(!allowed(u)){note(u,'fetch');return Promise.reject(new TypeError('Blocked by STAGING guard'))}var p=f.apply(this,arguments);draw();return p};
var xo=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){if(!allowed(u)){note(u,'xhr');throw new TypeError('Blocked by STAGING guard')}draw();return xo.apply(this,arguments)};
if(window.WebSocket){var W=window.WebSocket;window.WebSocket=function(u,p){if(!allowed(u)){note(u,'ws');throw new TypeError('Blocked by STAGING guard')}return p===undefined?new W(u):new W(u,p)};window.WebSocket.prototype=W.prototype}
if(navigator.sendBeacon){var b=navigator.sendBeacon.bind(navigator);navigator.sendBeacon=function(u,d){if(!allowed(u)){note(u,'beacon');return false}return b(u,d)}}
document.addEventListener('securitypolicyviolation',function(e){note(e.blockedURI,'csp')});
function qrInfo(){var ua=navigator.userAgent,ios=(ua.match(/OS (\\d+[_\\d]*) like Mac/)||[])[1],sv=(ua.match(/Version\\/([\\d.]+)/)||[])[1];
var dev='Device: '+(ios?'iOS '+ios.replace(/_/g,'.'):'not iOS')+(sv?', Safari '+sv:'')+', viewport '+innerWidth+'x'+innerHeight;
var scr='';try{scr=', screen '+S.screen+'/'+S.mode+'/'+S.tab+(S.sub?'/'+S.sub:'')}catch(e){}
var b=document.querySelector('.qrsHero'),h=document.querySelector('.hero2');
if(!b)return 'QR button: NOT in page'+scr+(h?' (banner present)':' (no home banner on this screen)')+'\\nPR #7 scanner code in build: '+(typeof qrsOpen==='function'?'yes':'NO')+'\\n'+dev;
var r=b.getBoundingClientRect(),cs=getComputedStyle(b),t=document.elementFromPoint(r.left+r.width/2,r.top+r.height/2),hr=h?h.getBoundingClientRect():null;
return 'QR button: in page'+scr+'\\n display '+cs.display+', visibility '+cs.visibility+', opacity '+cs.opacity+'\\n box '+[r.left,r.top,r.width,r.height].map(Math.round).join(',')+(hr?' in banner '+[hr.width,hr.height].map(Math.round).join('x'):'')+'\\n on top: '+(t&&(t===b||b.contains(t))?'yes':'NO ('+(t?(t.className||t.tagName):'none')+')')+'\\n'+dev}
var el;function draw(){if(!el){if(!document.body)return;el=document.createElement('div');el.id='tpStagingBadge';
el.style.cssText='position:fixed;z-index:2147483647;left:6px;top:calc(env(safe-area-inset-top,0px) + 4px);padding:2px 7px;border-radius:9px;font:600 10px/1.5 -apple-system,system-ui,sans-serif;color:#fff;direction:ltr;opacity:.92;cursor:pointer;pointer-events:auto';
el.onclick=function(){alert('STAGING build\\nSupabase: '+OK+'\\nCommit: '+st.commit+'\\nBuilt: '+st.built+'\\nRequests to Staging DB: '+st.db+'\\nBlocked: '+st.blocked+'\\n\\n'+qrInfo()+(st.log.length?'\\n\\n'+st.log.slice(-8).join('\\n'):''))};
document.body.appendChild(el)}
el.style.background=st.blocked?'#c62828':'#6a1b9a';el.textContent='STAGING \\u00b7 DB '+st.db+(st.blocked?' \\u00b7 BLOCKED '+st.blocked:'')}
document.addEventListener('DOMContentLoaded',function(){draw();document.title='[STAGING] '+document.title});setInterval(draw,2000)})();
</script>`;
if (!/<head>/.test(html)) fail('no <head> tag found in index.html.');
html = html.replace('<head>', '<head>\n' + guard);

// ---------- 4/5. output: only site files ----------
rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
writeFileSync(join(OUT, 'index.html'), html);
cpSync(join(ROOT, 'assets'), join(OUT, 'assets'), { recursive: true });
cpSync(join(ROOT, 'staging', 'staging-check.html'), join(OUT, 'staging-check.html'));
const connect = ["'self'", STAGING_URL, `wss://${STAGING_REF}.supabase.co`, 'https://cdn.jsdelivr.net', 'https://staticimgly.com',
  'https://router.project-osrm.org', 'https://routing.openstreetmap.de', 'data:', 'blob:'].join(' ');
const baseHeaders = existsSync(join(ROOT, '_headers')) ? readFileSync(join(ROOT, '_headers'), 'utf8') : '';
writeFileSync(join(OUT, '_headers'), baseHeaders.trimEnd() + `

# ---- STAGING only (added by staging/build-staging.mjs) ----
/*
  Content-Security-Policy: connect-src ${connect}
  X-Robots-Tag: noindex, nofollow
  Referrer-Policy: strict-origin-when-cross-origin
`);
writeFileSync(join(OUT, 'staging-build.json'), JSON.stringify({ environment: 'staging', supabase: STAGING_URL, keyKind,
  commit: env('COMMIT_REF') || 'local', branch: env('BRANCH') || 'local', built: builtAt }, null, 2) + '\n');

// ---------- 6. scan everything that will be published ----------
const walk = (d) => readdirSync(d).flatMap((n) => { const p = join(d, n); return statSync(p).isDirectory() ? walk(p) : [p]; });
for (const file of walk(OUT)) {
  const buf = readFileSync(file);
  const text = buf.toString('latin1');
  const rel = file.slice(OUT.length + 1);
  // The Production reference may appear only where it is named in order to be blocked: the guard in index.html
  // and the negative test in staging-check.html.
  if (text.includes(PROD_REF) && !(rel === 'index.html' && onlyInGuard(text)) && rel !== 'staging-check.html')
    fail(`${rel} contains the Production project reference.`);
  if (prodKey.length > 20 && text.includes(prodKey)) fail(`${rel} contains the Production key.`);
  if (/\.sql$/i.test(rel)) fail(`${rel}: SQL files must never be published.`);
}
function onlyInGuard(t) {   // the guard itself names the Production reference in order to block it
  const g = t.indexOf('/* Tripoli Points STAGING network guard'), e = t.indexOf('</script>', g);
  return g >= 0 && t.split(PROD_REF).length === 2 && t.indexOf(PROD_REF) > g && t.indexOf(PROD_REF) < e;
}
console.log(`STAGING build OK -> dist-staging/ (Supabase ${STAGING_URL}, ${keyKind}, commit ${commit}).`);
console.log('Checked: no Production reference outside the guard, no Production key, no .sql files.');
