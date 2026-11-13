// Batch 0 parity test: main V3.7.4 (as is) vs dist-staging (built from sync/staging-v3.7.4), offline.
// Supabase is mocked at the network layer with synthetic data; nothing reaches any real project.
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const [,, MAIN_DIR, STG_DIR, OUT] = process.argv;
fs.mkdirSync(OUT, { recursive: true });

function serve(root, port, csp) {
  const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.webp': 'image/webp', '.png': 'image/png', '.jpg': 'image/jpeg', '.svg': 'image/svg+xml' };
  return new Promise(r => {
    const s = http.createServer((q, res) => {
      let p = decodeURIComponent(q.url.split('?')[0]); if (p.endsWith('/')) p += 'index.html';
      const f = path.join(root, p);
      if (!f.startsWith(root) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('nf'); }
      const h = { 'content-type': types[path.extname(f)] || 'application/octet-stream' };
      if (csp && p.endsWith('.html')) h['content-security-policy'] = csp;
      res.writeHead(200, h); fs.createReadStream(f).pipe(res);
    }).listen(port, () => r(s));
  });
}
const cspFrom = (dir) => { const t = fs.readFileSync(path.join(dir, '_headers'), 'utf8'); const m = t.match(/Content-Security-Policy:\s*(.+)/); return m && m[1].trim(); };

const STUB = `window.supabase={createClient:function(u,k){return{rpc:function(fn,a){return fetch(u+'/rest/v1/rpc/'+fn,{method:'POST',headers:{apikey:k,'content-type':'application/json'},body:JSON.stringify(a||{})}).then(function(r){return r.json()}).then(function(d){return{data:d,error:null}}).catch(function(e){return{data:null,error:{message:String(e)}}})},functions:{invoke:function(){return Promise.resolve({data:null,error:{message:'stub'}})}}}}};`;
const cats = ['cafe', 'food', 'fashion', 'bakery', 'beauty', 'sweets', 'pharmacy', 'phones'];
const pts = [[34.4365, 35.8350], [34.4372, 35.8361], [34.4352, 35.8338], [34.4490, 35.8190], [34.4505, 35.8178], [34.4400, 35.8361], [34.4320, 35.8450], [34.4420, 35.8300], [34.4440, 35.8420], [34.4380, 35.8280]];
const merchants = pts.map((p, i) => ({ id: '00000000-0000-4000-8000-00000000000' + i, name: 'محل تجربة ' + (i + 1), cat: cats[i % cats.length], extra_cats: [], pct: 5, tier: 'small', redeem_pct: 5, redeem_pct_vip: 5, addr: 'طرابلس', lat: p[0], lng: p[1], x: null, y: null, area: '', photo_url: '', logo_url: '', status: 'active', page_blurb: '', page_enabled: true }));
const offers = [{ id: 'aaaaaaaa-0000-4000-8000-000000000001', mid: merchants[0].id, type: 'discount', badge: 'جديد', val: 10, title: 'خصم تجربة', active: true, days: 30, created_at: new Date().toISOString() }];
function mock(fn) {
  if (fn === 'list_merchants') return merchants;
  if (fn === 'list_active_offers_all') return offers;
  if (fn === 'get_categories') return [];
  if (fn === 'get_app_text_settings') return {};
  return null;
}

(async () => {
  const sM = await serve(MAIN_DIR, 8101, null), sS = await serve(STG_DIR, 8102, cspFrom(STG_DIR));
  const browser = await chromium.launch();
  const report = {};
  for (const [name, url] of [['main', 'http://127.0.0.1:8101/'], ['staging', 'http://127.0.0.1:8102/']]) {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, locale: 'ar' });
    const page = await ctx.newPage();
    const r = { requests: [], prodRequests: [], supabaseHosts: {}, manifest: [], img404: [], consoleErrors: [], cspViolations: 0 };
    await page.route('**/*', route => {
      const u = route.request().url();
      if (/cdn\.jsdelivr\.net\/npm\/@supabase/.test(u)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: STUB });
      if (/fonts\.(googleapis|gstatic)\.com|server\.arcgisonline\.com|staticimgly|osrm|openstreetmap/.test(u)) return route.fulfill({ status: 200, contentType: 'text/css', body: '' });
      const m = u.match(/^https:\/\/([a-z0-9]+)\.supabase\.co\/(.*)$/);
      if (m) {
        r.supabaseHosts[m[1]] = (r.supabaseHosts[m[1]] || 0) + 1;
        if (m[2].includes('map-assets')) return route.fulfill({ status: 404, body: 'nf' });
        const fn = (m[2].match(/rest\/v1\/rpc\/([a-z_0-9]+)/) || [])[1];
        return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(mock(fn)) });
      }
      return route.continue();
    });
    page.on('request', q => { const u = q.url(); r.requests.push(u); if (u.includes('lqbhfkowqaqlgcrdybvv')) r.prodRequests.push(u); if (u.includes('manifest.json')) r.manifest.push(u); });
    page.on('response', s => { if (s.status() === 404 && /\.(webp|png|jpg|svg)(\?|$)/.test(s.url())) r.img404.push(s.url()); if (s.url().includes('manifest.json')) r.manifestStatus = s.status(); });
    page.on('console', c => { if (c.type() === 'error') r.consoleErrors.push(c.text().slice(0, 160)); });
    await page.goto(url, { waitUntil: 'load' });
    await page.waitForTimeout(5000);
    r.cspViolations = await page.evaluate(() => (window.__TP_STAGING && window.__TP_STAGING.blocked) || 0);
    r.stagingGuard = await page.evaluate(() => window.__TP_STAGING ? { db: window.__TP_STAGING.db, blocked: window.__TP_STAGING.blocked, log: window.__TP_STAGING.log } : null);
    r.title = await page.title();
    r.mapRemote = await page.evaluate(() => typeof TP_MAP_REMOTE !== 'undefined' ? TP_MAP_REMOTE : null);
    r.mapOn = await page.evaluate(() => typeof TP_MAP_ON !== 'undefined' ? TP_MAP_ON : 'undef');
    r.merchantsLoaded = await page.evaluate(() => (typeof S !== 'undefined' && S.merchants) ? S.merchants.length : -1);
    const shot = async (tag) => {
      await page.evaluate(() => { const b = document.getElementById('tpStagingBadge'); if (b) b.style.display = 'none'; });
      await page.screenshot({ path: path.join(OUT, `${name}-${tag}.png`) });
    };
    await shot('splash');
    // signed-in synthetic customer (state only; every server call is mocked)
    await page.evaluate(() => { S.phone = '96170000000'; S.customers[S.phone] = { name: 'تجربة', last: 'اختبار', photo: '', points: 5000, status: 'active', src: 'direct', welcome: null }; S.mode = 'customer'; S.tab = 'home'; S.screen = 'app'; render() });
    await page.waitForTimeout(2500); await shot('home');
    // open the shops map (same action as the home "المتاجر القريبة" button)
    await page.evaluate(() => { try { S.sub = null; S.offMode = 'cat'; S.tab = 'offers'; S.offView = 'map'; S.q = ''; render() } catch (e) { } });
    await page.waitForTimeout(4000);
    r.mapImgs = await page.evaluate(() => [...document.querySelectorAll('img')].map(i => i.getAttribute('src') || '').filter(s => s.includes('assets/map')).reduce((a, s) => { const k = s.split('/').slice(0, 3).join('/'); a[k] = (a[k] || 0) + 1; return a }, {}));
    r.mapImgsBroken = await page.evaluate(() => [...document.querySelectorAll('img')].filter(i => (i.getAttribute('src') || '').includes('assets/map') && i.complete && i.naturalWidth === 0).map(i => i.getAttribute('src')));
    r.bgTiles = await page.evaluate(() => [...document.querySelectorAll('*')].filter(e => (e.style && e.style.backgroundImage || '').includes('assets/map')).length);
    r.pinEls = await page.evaluate(() => { const L = document.getElementById('tpBig') || document; return { catImgs: L.querySelectorAll('.tpCatImg').length, imgsInMap: L.querySelectorAll('img').length, mapSrcs: [...L.querySelectorAll('img')].map(i => i.getAttribute('src')).filter(Boolean).slice(0, 12) } });
    await shot('map');
    const pin = await page.$('img[src*="assets/map/pins/r3"]'); if (pin) { await pin.click(); await page.waitForTimeout(2500); }
    r.zoomed = await page.evaluate(() => { const L = document.getElementById('tpBig') || document; return { catImgs: L.querySelectorAll('.tpCatImg').length, catSrcs: [...L.querySelectorAll('img')].map(i => i.getAttribute('src')).filter(x => x && x.includes('/cat/')).slice(0, 8), broken: [...L.querySelectorAll('img')].filter(i => i.complete && i.naturalWidth === 0).length } });
    await shot('zoom');
    await page.evaluate(() => { try { openStore(S.merchants[0].id) } catch (e) { } }); await page.waitForTimeout(2500); await shot('store');
    await page.evaluate(() => { try { S.sub = 'collect'; render() } catch (e) { } }); await page.waitForTimeout(2500); await shot('treasures');
    r.finalImg404 = r.img404.length;
    report[name] = r;
    await ctx.close();
  }
  await browser.close(); sM.close(); sS.close();
  for (const k of Object.keys(report)) { report[k].requestCount = report[k].requests.length; delete report[k].requests; }
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(report, null, 1));
  console.log(JSON.stringify(report, null, 1));
})();
