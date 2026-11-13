// H1 end-to-end test: the REAL app (main V3.7.4 index.html, unmodified) driven in Chromium against a LOCAL database,
// every server call executed as the public role `anon` (what the browser key does). Run once on the Production-like
// replica WITHOUT H1 and once WITH H1; compare. Usage: node e2e.js <db> <label> <appDir> <outDir>
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const { rpc, psql } = require('./gateway');
const [, , DB, LABEL, APP, OUT] = process.argv;
fs.mkdirSync(OUT, { recursive: true });
const STUB = `window.supabase={createClient:function(u,k){return{rpc:function(fn,a){return fetch(u+'/rest/v1/rpc/'+fn,{method:'POST',headers:{apikey:k,'content-type':'application/json'},body:JSON.stringify(a||{})}).then(function(r){return r.text().then(function(t){var j=null;try{j=JSON.parse(t)}catch(e){};return r.ok?{data:j,error:null}:{data:null,error:j||{message:t}}})}).catch(function(e){return{data:null,error:{message:String(e)}}})},functions:{invoke:function(){return Promise.resolve({data:null,error:{message:'edge functions not available in this test'}})}}}}};`;
const sql1 = q => psql(DB, q + '\n').stdout.trim();
const CPH = '71000222', MPH = '76000111', MID = '11111111-1111-4111-8111-111111111111', OID = '22222222-2222-4222-8222-222222222222';

function serve(root, port) {
  return new Promise(r => http.createServer((q, res) => {
    let p = decodeURIComponent(q.url.split('?')[0]); if (p.endsWith('/')) p += 'index.html';
    const f = path.join(root, p);
    if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html; charset=utf-8' : f.endsWith('.webp') ? 'image/webp' : 'application/octet-stream' });
    fs.createReadStream(f).pipe(res);
  }).listen(port, () => r()));
}

(async () => {
  const port = 8400 + Math.floor(Math.random() * 90);
  await serve(APP, port);
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'ar' });
  const page = await ctx.newPage();
  const calls = [];
  await page.route('**/*', async route => {
    const u = route.request().url();
    if (/cdn\.jsdelivr\.net\/npm\/@supabase/.test(u)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: STUB });
    if (/fonts\.|arcgisonline|staticimgly|osrm|openstreetmap|wa\.me/.test(u)) return route.fulfill({ status: 200, body: '' });
    if (/supabase\.co\/storage\//.test(u)) return route.fulfill({ status: 404, body: '' });
    const m = u.match(/supabase\.co\/rest\/v1\/rpc\/([a-z_0-9]+)/);
    if (m) {
      const args = JSON.parse(route.request().postData() || '{}');
      const r = rpc(DB, m[1], args);
      calls.push({ fn: m[1], status: r.status, err: r.status === 200 ? null : r.body.message });
      return route.fulfill({ status: r.status, contentType: 'application/json', body: typeof r.body === 'string' ? r.body : JSON.stringify(r.body) });
    }
    return route.continue();
  });
  const results = [];
  const check = (name, ok, detail) => { results.push({ name, ok: !!ok, detail: detail || '' }); };
  const wait = ms => page.waitForTimeout(ms);
  const toasts = async () => page.evaluate(() => window.__t || []);
  const pin = async code => { for (const d of code) await page.click(`.pad button:has-text("${d}")`); await wait(900); };
  const shot = async n => page.screenshot({ path: path.join(OUT, `${LABEL}-${n}.png`) });
  const since = i => calls.slice(i).map(c => c.fn + (c.status === 200 ? '' : '!' + c.status));

  await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'load' }); await wait(2500);
  await page.evaluate(() => { window.__t = []; const o = window.toast; window.toast = function (m) { window.__t.push(String(m)); return o.apply(this, arguments) } });

  // ---- 1. customer PIN setup (new registration through the real screens) ----
  let c0 = calls.length;
  await page.evaluate(() => { S.screen = 'login'; render() }); await wait(300);
  await page.fill('#ph', CPH); await page.click('button:has-text("متابعة")'); await wait(1500);
  check('register: new number reaches «create PIN»', await page.evaluate(() => S.screen === 'pin' && S.pinMode === 'set'));
  await pin('1357'); await pin('1357');
  check('register: PIN confirmed, welcome screen', await page.evaluate(() => S.screen === 'welcome'));
  await page.evaluate(() => pickType('c')); await wait(400);
  await page.evaluate(() => { S.termsAgree = true; return agreeCustomerTerms() }); await wait(2500);
  check('register: customer account created, in app', await page.evaluate(() => S.mode === 'customer' && S.screen === 'app'));
  check('register: PIN stored hashed and correct in DB', sql1(`select (pin_hash = extensions.crypt('1357', pin_hash))::text from public.customers where phone='${CPH}'`) === 'true');
  check('register: welcome gift recorded', sql1(`select welcome_remain::int::text from public.customers where phone='${CPH}'`) === '3000', sql1(`select points||'/'||welcome_remain from public.customers where phone='${CPH}'`));
  results.push({ name: 'register: server calls', ok: true, detail: since(c0).join(' ') });
  await shot('1-registered');

  // ---- 2. customer login with PIN, wrong PIN, forgot PIN ----
  await page.evaluate(() => logout()); await wait(300);
  await page.evaluate(() => { S.screen = 'login'; render() }); await page.fill('#ph', CPH); await page.click('button:has-text("متابعة")'); await wait(1500);
  check('login: existing customer asked for PIN', await page.evaluate(() => S.screen === 'pin' && S.pinMode === 'enter'));
  await pin('0000');
  check('login: wrong PIN refused', (await toasts()).some(t => t.includes('غير صحيح')));
  c0 = calls.length;
  await page.click('button:has-text("نسيت رمز الحماية")'); await wait(500);
  check('forgot PIN: support screen shown', await page.evaluate(() => S.screen === 'mforgotpin'));
  check('forgot PIN: no server call (no self-reset by phone)', calls.length === c0, since(c0).join(' '));
  await shot('2-forgot-pin');
  await page.evaluate(() => go('pin')); await wait(300);
  await pin('1357'); await wait(1500);
  check('login: correct PIN opens the app', await page.evaluate(() => S.mode === 'customer' && S.screen === 'app'));

  // ---- 3. merchant login, purchase, customer confirmation ----
  await page.evaluate(() => logout()); await wait(300);
  await page.evaluate(() => { S.screen = 'login'; render() }); await page.fill('#ph', MPH); await page.click('button:has-text("متابعة")'); await wait(1500);
  await pin('1111'); await wait(2000);
  check('merchant: PIN login', await page.evaluate(id => S.merchantId === id && S.mode === 'merchant', MID));
  const err = await page.evaluate(([mid, p]) => createTx(mid, p, 20, false, [], null), [MID, CPH]); await wait(800);
  check('merchant: create purchase for the customer', err === null, String(err));
  const txid = sql1(`select id from public.pos_transactions where customer_phone='${CPH}' and status='PENDING'`);
  // merchant asks the admin for a manual top-up (the approved manual-transfer request)
  await page.evaluate(() => { S.buySel = 10; return startManualOrder() }); await wait(1500);
  check('merchant: manual transfer request submitted', sql1(`select count(*) from public.topup_orders where merchant_id='${MID}' and status='REVIEW'`) === '2');
  await page.evaluate(() => logout()); await wait(300);
  await page.evaluate(() => { S.screen = 'login'; render() }); await page.fill('#ph', CPH); await page.click('button:has-text("متابعة")'); await wait(1200);
  await pin('1357'); await wait(2000);
  await page.evaluate(id => decide(id, true), txid); await wait(1500);
  check('customer: confirms the purchase', sql1(`select status from public.pos_transactions where id='${txid}'`) === 'CONFIRMED');
  check('customer: points credited once (3000 gift + 100 earned)', sql1(`select points from public.customers where phone='${CPH}'`) === '3100', sql1(`select points||' pts'  from public.customers where phone='${CPH}'`));
  await shot('3-customer-after-purchase');

  // ---- 4. admin: login, order list, approve / top up attempts from the app ----
  await page.evaluate(() => logout()); await wait(300);
  await page.evaluate(() => { S.screen = 'adminlogin'; render() }); await wait(300);
  await page.fill('#au', 'h1admin'); await page.fill('#ac', '2468'); await page.click('button:has-text("دخول")'); await wait(2500);
  check('admin: PIN login', await page.evaluate(() => S.mode === 'admin'));
  check('admin: top-up order list loads', await page.evaluate(() => Array.isArray(S.orders) && S.orders.length >= 2), await page.evaluate(() => (S.orders || []).length + ' orders'));
  c0 = calls.length; const t0 = (await toasts()).length;
  await page.evaluate(id => adminResolve(id, true), OID); await wait(1500);
  const st = sql1(`select status from public.topup_orders where id='${OID}'`);
  results.push({ name: 'admin app: «approve» button on a REVIEW order', ok: true, detail: `order status now ${st}; calls: ${since(c0).join(' ')}; toast: ${(await toasts()).slice(t0).join(' | ')}` });
  c0 = calls.length;
  const bal0 = sql1(`select coalesce(sum(amount),0) from public.topups where merchant_id='${MID}'`);
  await page.evaluate(id => topup(id, 5), MID); await wait(1200);
  const bal1 = sql1(`select coalesce(sum(amount),0) from public.topups where merchant_id='${MID}'`);
  results.push({ name: 'admin app: direct «top up» button', ok: true, detail: `top-ups ${bal0} -> ${bal1}; calls: ${since(c0).join(' ')}` });
  await page.evaluate(() => { S.tab = 'ao'; render() }); await wait(800); await shot('4-admin');

  // ---- 5. what an attacker with only the public key can do, straight from the browser console ----
  const attack = async (fn, args) => page.evaluate(([f, a]) => sb.rpc(f, a).then(r => r.error ? (r.error.code === '42501' ? 'refused: 42501 permission denied' : 'REACHED the function (business error: ' + (r.error.message || '') + ')') : 'EXECUTED'), [fn, args]);
  const atk = {
    'approve someone\'s top-up order': await attack('admin_resolve_topup_order', { p_order_id: OID, p_approve: true }),
    'credit a wallet': await attack('admin_topup_merchant', { p_merchant_id: MID, p_amount: 1000, p_source: 'x' }),
    'reset another customer\'s PIN': await attack('customer_reset_pin', { p_phone: CPH, p_new_pin: '9999' }),
    'set another customer\'s PIN': await attack('customer_set_pin', { p_phone: CPH, p_pin: '9999', p_name: 'x' }),
    'grant gift points': await attack('admin_grant_customer_gift', { p_phone: CPH, p_amount: 100000, p_days: 30 }),
    'mark an order paid (Whish confirm)': await attack('whish_confirm_payment', { p_order_id: OID, p_result: 'success', p_paid_amount: null, p_external_id: null }),
    'mark an order collected': await attack('admin_mark_order_collected', { p_order_id: OID }),
    'delete an order record': await attack('admin_delete_topup_order_only', { p_order_id: OID }),
  };
  for (const [k, v] of Object.entries(atk)) results.push({ name: 'public key: ' + k, ok: v.startsWith('refused'), detail: v });
  check('PIN still the customer\'s own after attacks', sql1(`select (pin_hash = extensions.crypt('1357', pin_hash))::text from public.customers where phone='${CPH}'`) === 'true');

  // ---- 6. the restricted admin procedure (owner, SQL editor) still works ----
  const oid2 = sql1(`select id from public.topup_orders where merchant_id='${MID}' and status='REVIEW' and id <> '${OID}' limit 1`);
  const own = psql(DB, `select public.admin_resolve_topup_order('${oid2}', true)::text;\n`);
  results.push({ name: 'owner (SQL editor): approve verified order', ok: own.status === 0, detail: (own.stdout || own.stderr).trim().slice(0, 160) });

  await browser.close();
  const pass = results.filter(r => r.ok).length;
  fs.writeFileSync(path.join(OUT, `${LABEL}.json`), JSON.stringify({ label: LABEL, db: DB, pass, total: results.length, results, calls }, null, 1));
  console.log(`${LABEL}: ${pass}/${results.length}`);
  results.forEach(r => console.log((r.ok ? ' ok  ' : ' FAIL') + ' ' + r.name + (r.detail ? '  — ' + r.detail : '')));
  process.exit(0);
})();
