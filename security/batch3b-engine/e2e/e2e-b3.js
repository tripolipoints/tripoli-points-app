// Batch 3 end-to-end test: the REAL app (staging/b3-client branch index.html) in Chromium, every server call executed
// as role anon against a LOCAL copy of the Staging schema with batch 2 + 3a + 3b. Four browser pages act as customer,
// shop owner, employee and admin at the same time. Usage: node e2e-b3.js <db> <appDir> <outDir>
// Test accounts are synthetic (7999xxxx); no real account, PIN or password is used.
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const { rpc, psql } = require('./gateway-b3');
const [, , DB, APP, OUT] = process.argv;
fs.mkdirSync(OUT, { recursive: true });
const STUB = `window.supabase={createClient:function(u,k){return{rpc:function(fn,a){return fetch(u+'/rest/v1/rpc/'+fn,{method:'POST',headers:{apikey:k,'content-type':'application/json'},body:JSON.stringify(a||{})}).then(function(r){return r.text().then(function(t){var j=null;try{j=JSON.parse(t)}catch(e){};return r.ok?{data:j,error:null}:{data:null,error:j||{message:t}}})}).catch(function(e){return{data:null,error:{message:String(e)}}})},functions:{invoke:function(){return Promise.resolve({data:null,error:{message:'n/a'}})}}}}};`;
const sql1 = q => psql(DB, q + '\n').stdout.trim();
const C1 = '79990222', C2 = '79990333', MPH = '79990111', MID = '11111111-1111-4111-8111-1111111b3b11', STAFF = '79990444';

function serve(root, port) {
  return new Promise(r => http.createServer((q, res) => {
    let p = decodeURIComponent(q.url.split('?')[0]); if (p.endsWith('/')) p += 'index.html';
    const f = path.join(root, p);
    if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
    res.writeHead(200, { 'content-type': f.endsWith('.html') ? 'text/html; charset=utf-8' : f.endsWith('.js') ? 'text/javascript' : f.endsWith('.webp') ? 'image/webp' : 'application/octet-stream' });
    fs.createReadStream(f).pipe(res);
  }).listen(port, () => r()));
}

(async () => {
  const port = 8500 + Math.floor(Math.random() * 90);
  await serve(APP, port);
  const browser = await chromium.launch();
  const calls = [], errors = [], results = [];
  const check = (name, ok, detail) => { results.push({ name, ok: !!ok, detail: detail === undefined ? '' : String(detail).slice(0, 300) }); };
  async function newPage(label) {
    const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'ar' });
    const page = await ctx.newPage();
    page.on('pageerror', e => errors.push(label + ': ' + e.message));
    await page.route('**/*', async route => {
      const u = route.request().url();
      if (/cdn\.jsdelivr\.net\/npm\/@supabase/.test(u)) return route.fulfill({ status: 200, contentType: 'text/javascript', body: STUB });
      if (/fonts\.|arcgisonline|staticimgly|osrm|openstreetmap|wa\.me/.test(u)) return route.fulfill({ status: 200, body: '' });
      if (/supabase\.co\/storage\//.test(u)) return route.fulfill({ status: 404, body: '' });
      const m = u.match(/supabase\.co\/rest\/v1\/rpc\/([a-z_0-9]+)/);
      if (m) {
        const args = JSON.parse(route.request().postData() || '{}');
        const r = rpc(DB, m[1], args);
        calls.push({ who: label, fn: m[1], status: r.status, err: r.status === 200 ? null : r.body.message });
        return route.fulfill({ status: r.status, contentType: 'application/json', body: typeof r.body === 'string' ? r.body : JSON.stringify(r.body) });
      }
      return route.continue();
    });
    await page.goto(`http://127.0.0.1:${port}/`, { waitUntil: 'load' }); await page.waitForTimeout(2000);
    await page.evaluate(() => { window.__t = []; const o = window.toast; window.toast = function (m) { window.__t.push(String(m)); return o.apply(this, arguments) } });
    page.toasts = async () => page.evaluate(() => window.__t || []);
    page.lastToast = async () => page.evaluate(() => (window.__t || []).slice(-1)[0] || '');
    page.pin = async code => { for (const d of code) await page.click(`.pad button:has-text("${d}")`); await page.waitForTimeout(700); };
    page.login = async (ph, code) => {
      await page.evaluate(() => { S.screen = 'login'; render() }); await page.waitForTimeout(200);
      await page.fill('#ph', ph); await page.click('button:has-text("متابعة")'); await page.waitForTimeout(1200);
      await page.pin(code); await page.waitForTimeout(1500);
    };
    return page;
  }
  const shot = async (page, n) => page.screenshot({ path: path.join(OUT, `b3-${n}.png`) });
  const W = ms => new Promise(r => setTimeout(r, ms));

  // ---- 1. customer registration and login ----
  const pc = await newPage('customer');
  await pc.evaluate(() => { S.screen = 'login'; render() }); await W(200);
  await pc.fill('#ph', C1); await pc.click('button:has-text("متابعة")'); await W(1200);
  await pc.pin('1357'); await pc.pin('1357');
  await pc.evaluate(() => pickType('c')); await W(300);
  await pc.evaluate(() => { S.termsAgree = true; return agreeCustomerTerms() }); await W(2500);
  check('register: customer created and in the app with a server session', await pc.evaluate(() => S.mode === 'customer' && S.screen === 'app' && S.sess && S.sess.role === 'customer'));
  check('register: welcome gift = Admin setting, as its own ledger batch (7 days)',
    sql1(`select kind||':'||remaining||':'||(expires_at > now() + interval '6 days 23 hours')::text from public.point_batches where customer_phone='${C1}'`) === 'welcome:3000:true',
    sql1(`select string_agg(kind||':'||remaining, ',') from public.point_batches where customer_phone='${C1}'`));
  check('session token is not stored in the browser', await pc.evaluate(() => { try { return !Object.keys(localStorage).some(k => (localStorage.getItem(k) || '').includes('tps1_')) } catch (e) { return true } }));
  await pc.evaluate(() => logout()); await W(300);
  await pc.login(C1, '0000');
  check('login: wrong PIN refused', (await pc.toasts()).some(t => t.includes('غير صحيح')));
  await pc.evaluate(() => go('pin')); await W(200); await pc.pin('1357'); await W(1500);
  check('login: correct PIN → app + session', await pc.evaluate(() => S.mode === 'customer' && S.sess && S.sess.role === 'customer'));
  check('customer home keeps Scan / Tripoli row and adds «رمز الشراء»', await pc.evaluate(() => !!document.querySelector('.qrsRowHome') && !!document.getElementById('payBtn')));
  await shot(pc, '1-customer-home');

  // ---- 2. admin: login, gift screen unchanged, transfer settings, plan ----
  const pa = await newPage('admin');
  await pa.evaluate(() => { S.screen = 'adminlogin'; render() }); await W(200);
  await pa.fill('#au', 'b3admin'); await pa.fill('#ac', '2468'); await pa.click('button:has-text("دخول")'); await W(2500);
  check('admin: login with server session', await pa.evaluate(() => S.mode === 'admin' && S.sess && S.sess.role === 'admin'));
  await pa.evaluate(() => { S.sub = 'settingsWelcome'; render() }); await W(500);
  await pa.click('button:has-text("حفظ الإعدادات")'); await W(1200);
  check('admin gift screen saves through the session (values unchanged: 3000 / 7)',
    sql1(`select string_agg(key||'='||value, ',' order by key) from public.app_text_settings where key in ('welcome_bonus','welcome_days')`) === 'welcome_bonus=3000,welcome_days=7'
    && calls.some(c => c.fn === 'admin_update_text_settings_v2' && c.status === 200), (await pa.toasts()).slice(-1)[0]);
  await pa.evaluate(() => aCatOpen()); await W(1200);
  await pa.fill('#ptn', '70 000 000'); await pa.fill('#pti', 'حوّل المبلغ إلى الرقم ثم أرسل المرجع'); await pa.evaluate(() => aPaySave()); await W(1200);
  await pa.evaluate(() => aPlanForm(null)); await W(300);
  await pa.fill('#bf-code', 'basic-m'); await pa.fill('#bf-title', 'اشتراك شهري تجريبي'); await pa.selectOption('#bf-tier', 'medium');
  await pa.fill('#bf-price', '20'); await pa.fill('#bf-pts', '2000'); await pa.fill('#bf-months', '1'); await pa.check('#bf-active'); await pa.click('#bfSave'); await W(1500);
  check('admin: transfer number and a (provisional) plan saved', sql1(`select price||'/'||allowance_pts||'/'||active||'/'||provisional from public.plans where code='basic-m'`) === '20/2000/true/true'
    && sql1(`select value from public.app_text_settings where key='pay_transfer_number'`) === '70 000 000');
  await shot(pa, '2-admin-catalogue');

  // ---- 3. shop: subscription request ----
  const pm = await newPage('merchant');
  await pm.login(MPH, '1111'); await W(1000);
  await pm.evaluate(() => { S.mPhotoNag = false; render() });   // the app's own «add a shop photo» reminder (synthetic shop has no photo)
  check('shop: login with server session', await pm.evaluate(id => S.mode === 'merchant' && S.merchantId === id && S.sess && S.sess.role === 'merchant', MID));
  await pm.evaluate(() => mPlanOpen()); await W(1500);
  check('shop: sees transfer number and the plan for its tier', await pm.evaluate(() => S.b3 && S.b3.cat && S.b3.cat.transfer_number === '70 000 000' && S.b3.cat.plans.length === 1));
  await pm.evaluate(() => { const p = S.b3.cat.plans[0]; S.b3.sel = { k: 'subscription', code: p.code, price: p.price, cur: p.currency, t: p.title }; render() }); await W(300);
  await pm.fill('#b3ref', 'OMT-778899'); await pm.evaluate(() => mPayReq()); await W(1500);
  check('shop: transfer request pending', sql1(`select status||'/'||amount from public.payment_requests where merchant_id='${MID}'`) === 'pending/20');
  await pm.evaluate(() => { const p = S.b3.cat.plans[0]; S.b3.sel = { k: 'subscription', code: p.code, price: p.price, cur: p.currency, t: p.title }; render() }); await W(300);
  await pm.fill('#b3ref', 'omt 778899'); await pm.evaluate(() => mPayReq()); await W(1200);
  check('shop: the same transfer reference cannot be sent twice', (await pm.lastToast()).includes('مستعمل') && sql1(`select count(*) from public.payment_requests where merchant_id='${MID}'`) === '1', await pm.lastToast());
  await shot(pm, '3-shop-plan');

  // ---- 4. admin approves after re-typing amount + reference ----
  await pa.evaluate(() => aPayOpen('pending')); await W(1200);
  const prid = sql1(`select id from public.payment_requests where merchant_id='${MID}'`);
  await pa.fill(`#va-${prid}`, '25'); await pa.fill(`#vr-${prid}`, 'OMT778899'); await pa.evaluate(id => aPayDecide(id, true), prid); await W(1200);
  check('admin: wrong amount → refused, nothing granted', (await pa.lastToast()).includes('لا يطابق') && sql1(`select count(*) from public.allowance_grants where merchant_id='${MID}'`) === '0', await pa.lastToast());
  await pa.fill(`#va-${prid}`, '20'); await pa.fill(`#vr-${prid}`, 'omt-778899'); await pa.evaluate(id => aPayDecide(id, true), prid); await W(1500);
  check('admin: approval → branch allowance 2000 (subscription + 1 month carry-over)',
    sql1(`select g.initial||'/'||(g.expires_at = s.period_end + interval '1 month')::text from public.allowance_grants g join public.merchant_subscriptions s on s.id = g.subscription_id where g.merchant_id='${MID}'`) === '2000/true');
  const again = await pa.evaluate(id => tpS('admin_payment_decide_v2', { p_id: id, p_approve: true, p_verified_amount: 20, p_verified_ref: 'OMT778899', p_note: null }), prid); await W(300);
  check('admin: the approved request leaves the pending list; approving again is refused', again && again.error === 'already_decided' && !(await pa.evaluate(id => !!document.getElementById('va-' + id), prid)), JSON.stringify(again));
  check('admin: a second approval grants nothing', sql1(`select count(*) from public.allowance_grants where merchant_id='${MID}'`) === '1');
  await shot(pa, '4-admin-payments');

  // ---- 5. purchase with the customer's single-use code ----
  await pc.evaluate(() => payOpen()); await W(1500);
  const short = await pc.evaluate(() => { const el = [...document.querySelectorAll('#paySheet .ltr')].find(e => /^\d{4}-\d{4}$/.test(e.textContent.trim())); return el ? el.textContent.trim() : null });
  check('customer: pay code shown (QR + 8-digit fallback, 5 minutes)', !!short && await pc.evaluate(() => !!document.querySelector('#paySheet svg')), short);
  await shot(pc, '5-pay-code');
  await pm.evaluate(() => { S.tab = 'mhome'; S.sub = 'new'; mfReset(); render() }); await W(400);
  check('shop: purchase form asks for the customer code (no phone field)', await pm.evaluate(() => !!document.getElementById('mfcode') && !document.getElementById('mp')));
  await pm.fill('#mfcode', short); await pm.click('button:has-text("تحقق")'); await W(1200);
  check('shop: code verified', await pm.evaluate(() => !!(S.mf.claim && S.mf.claim.id)));
  await pm.evaluate(() => { S.mf.items = [{ n: 'وجبة', p: '20', q: 1 }]; S.mf.redeem = true; return mfNext() }); await W(1500);
  const q = await pm.evaluate(() => S.mf.quote);
  check('shop: server quote — redeem = min(customer 3000, 5% of invoice = 100, tier 2500, branch 70% of 2000 = 1400) = 100; earn 95',
    q && q.ok && q.redeem_pts === 100 && q.earn === 95, JSON.stringify(q));
  await shot(pm, '6-shop-quote');
  await pm.evaluate(() => mfSend()); await W(1500);
  const tx1 = sql1(`select id from public.pos_transactions where customer_phone='${C1}' and status='PENDING'`);
  check('shop: purchase created (pending), 100 reserved on the branch', !!tx1 && sql1(`select sum(pts) from public.allowance_holds where tx_id='${tx1}' and status='held'`) === '100');
  await pm.evaluate(() => mfSend()); await W(800);
  check('shop: pressing send again does not create a second purchase', sql1(`select count(*) from public.pos_transactions where customer_phone='${C1}'`) === '1');
  await W(3500);
  check('customer: the exact details appear for approval', await pc.evaluate(() => !!document.querySelector('#paySheet button.ok')));
  await shot(pc, '7-customer-approve');
  await pc.click('#paySheet button.ok'); await W(1800);
  check('customer: approval → CONFIRMED, points 3000 − 100 + 95 = 2995 (gift spent first, it expires first)',
    sql1(`select status from public.pos_transactions where id='${tx1}'`) === 'CONFIRMED' && sql1(`select points from public.customers where phone='${C1}'`) === '2995'
    && sql1(`select remaining from public.point_batches where customer_phone='${C1}' and kind='welcome'`) === '2900', sql1(`select points from public.customers where phone='${C1}'`));
  check('branch allowance: 1900 left, reservation consumed', sql1(`select sum(remaining) from public.allowance_grants where merchant_id='${MID}'`) === '1900'
    && sql1(`select status from public.allowance_holds where tx_id='${tx1}'`) === 'consumed');
  await pc.evaluate(() => payClose());
  // second purchase (no points), then the daily limit
  const buy = async (redeem, inv) => {
    await pc.evaluate(() => payOpen()); await W(1200);
    const s = await pc.evaluate(() => { const el = [...document.querySelectorAll('#paySheet .ltr')].find(e => /^\d{4}-\d{4}$/.test(e.textContent.trim())); return el ? el.textContent.trim() : null });
    await pm.evaluate(() => { S.sub = 'new'; mfReset(); render() }); await W(300);
    await pm.fill('#mfcode', s); await pm.click('button:has-text("تحقق")'); await W(1000);
    await pm.evaluate(([r, i]) => { S.mf.items = [{ n: 'قهوة', p: String(i), q: 1 }]; S.mf.redeem = r; return mfNext() }, [redeem, inv]); await W(1200);
    return pm.evaluate(() => S.mf.quote);
  };
  let q2 = await buy(false, 10);
  await pm.evaluate(() => mfSend()); await W(3500);
  await pc.click('#paySheet button.ok'); await W(1500); await pc.evaluate(() => payClose());
  check('second purchase of the day confirmed', sql1(`select count(*) from public.pos_transactions where customer_phone='${C1}' and status='CONFIRMED'`) === '2', JSON.stringify(q2));
  const q3 = await buy(false, 10);
  check('third purchase in the same branch the same day → refused by the server', q3 && q3.ok === false && q3.error === 'daily_limit', JSON.stringify(q3));
  await pc.evaluate(() => payClose());
  await pc.evaluate(() => custPointsOpen()); await W(1000);
  check('customer «نقاطي»: batches with expiry dates', await pc.evaluate(() => !!document.getElementById('ptsModal') && document.getElementById('ptsModal').textContent.includes('حتى')));
  await shot(pc, '8-points'); await pc.evaluate(() => { const m = document.getElementById('ptsModal'); if (m) m.remove() });

  // ---- 6. expired gift ----
  sql1(`update public.point_batches set expires_at = now() - interval '1 minute' where customer_phone='${C1}' and kind='welcome'`);
  await pc.evaluate(() => logout()); await W(300); await pc.login(C1, '1357');
  check('expired gift: removed at login, only earned points remain (95 + 50)', sql1(`select points from public.customers where phone='${C1}'`) === '145',
    sql1(`select points from public.customers where phone='${C1}'`));

  // ---- 7. staff ----
  await pm.evaluate(() => { S.sub = null; S.tab = 'macc'; render(); return mStaffOpen() }); await W(1200);
  await pm.fill('#sfn', 'موظف الصندوق'); await pm.fill('#sfp', STAFF); await pm.fill('#sfc', '8642'); await pm.evaluate(() => mStaffAdd()); await W(1200);
  check('owner adds an employee (sell only)', sql1(`select perms::text from public.merchant_staff where phone='${STAFF}'`) === '{sell}');
  const ps = await newPage('staff');
  await ps.evaluate(() => { S.screen = 'login'; render() }); await W(200);
  await ps.click('button:has-text("دخول موظف")'); await W(300); await ps.fill('#stp', STAFF); await ps.fill('#stc', '8642'); await ps.evaluate(() => staffLogin()); await W(2000);
  check('employee logs in to his branch', await ps.evaluate(id => S.mode === 'merchant' && S.merchantId === id && S.sess.staff && S.sess.staff.name === 'موظف الصندوق', MID));
  const pc2 = await newPage('customer2'); await pc2.login(C2, '2468');
  await pc2.evaluate(() => payOpen()); await W(1200);
  const s2 = await pc2.evaluate(() => { const el = [...document.querySelectorAll('#paySheet .ltr')].find(e => /^\d{4}-\d{4}$/.test(e.textContent.trim())); return el ? el.textContent.trim() : null });
  await ps.evaluate(() => { S.mPhotoNag = false; S.sub = 'new'; mfReset(); render() }); await W(300);
  if (!(await ps.$('#mfcode'))) console.log('DEBUG staff', await ps.evaluate(() => JSON.stringify({ mode: S.mode, screen: S.screen, sub: S.sub, sess: !!S.sess, mid: S.merchantId, t: (window.__t||[]).slice(-3), html: document.body.innerText.slice(0, 300) })));
  await ps.fill('#mfcode', s2); await ps.click('button:has-text("تحقق")'); await W(1000);
  await ps.evaluate(() => { S.mf.items = [{ n: 'عصير', p: '12', q: 1 }]; S.mf.redeem = true; return mfNext() }); await W(1200);
  await ps.evaluate(() => mfSend()); await W(3500);
  await pc2.click('#paySheet button.ok'); await W(1500);
  check('employee sale confirmed by the customer and recorded with the employee', sql1(`select t.status||'/'||(t.staff_id = s.id)::text from public.pos_transactions t join public.merchant_staff s on s.phone='${STAFF}' where t.customer_phone='${C2}'`) === 'CONFIRMED/true');
  const staffBlocked = await ps.evaluate(() => tpS('merchant_staff_list_v2', {}, true).then(r => r === null));
  check('employee cannot open owner functions (staff list)', staffBlocked);
  await shot(ps, '9-staff');

  // ---- 7b. complaints: the customer reports a purchase he did not make; the admin reviews it ----
  await pc2.evaluate(() => payClose()); await pc2.evaluate(() => payOpen()); await W(1200);
  const s3 = await pc2.evaluate(() => { const el = [...document.querySelectorAll('#paySheet .ltr')].find(e => /^\d{4}-\d{4}$/.test(e.textContent.trim())); return el ? el.textContent.trim() : null });
  await pm.evaluate(() => { S.sub = 'new'; mfReset(); render() }); await W(300);
  await pm.fill('#mfcode', s3); await pm.click('button:has-text("تحقق")'); await W(1000);
  await pm.evaluate(() => { S.mf.items = [{ n: 'صنف', p: '30', q: 1 }]; S.mf.redeem = true; return mfNext() }); await W(1200);
  await pm.evaluate(() => mfSend()); await W(3500);
  const tx4 = sql1(`select id from public.pos_transactions where customer_phone='${C2}' and status='PENDING'`);
  const held4 = sql1(`select coalesce(sum(pts),0) from public.allowance_holds where tx_id='${tx4}' and status='held'`);
  await pc2.click('#paySheet button:has-text("أبلغ")'); await W(400); await pc2.click('#rrGo'); await W(1500);
  check('customer reports a pending purchase: it is cancelled and the branch reservation returned',
    !!tx4 && held4 !== '0' && sql1(`select status from public.pos_transactions where id='${tx4}'`) === 'CANCELLED' && sql1(`select status from public.allowance_holds where tx_id='${tx4}' limit 1`) === 'released',
    `held ${held4}`);
  pa.once('dialog', d => d.accept('تمت مراجعة العملية مع المحل'));
  await pa.evaluate(() => aRepOpen()); await W(1200);
  check('admin sees the open report', await pa.evaluate(() => S.b3a.feed && S.b3a.feed.reports.some(r => r.status === 'open')));
  await shot(pa, '10-admin-reports');
  await pa.click('button:has-text("تمت المراجعة")'); await W(1500);
  check('admin resolves it; the customer receives a notification', sql1(`select count(*) from public.customer_notes where customer_phone='${C2}' and title like 'راجعت الإدارة بلاغك%'`) === '1');

  // ---- 8. attacks with the public key from a browser console ----
  const atk = async (page, fn, args) => page.evaluate(([f, a]) => sb.rpc(f, a).then(r => r.error ? 'refused: ' + (r.error.message || '').slice(0, 60) : 'EXECUTED ' + JSON.stringify(r.data).slice(0, 80)), [fn, args]);
  const cTok = await pc.evaluate(() => S.sess.token), mTok = await pm.evaluate(() => S.sess.token);
  const A = {
    'v2 admin call without a session': await atk(pc, 'admin_list_customers_v2', { p_session: 'x' }),
    'customer session approving a payment': await atk(pc, 'admin_payment_decide_v2', { p_session: cTok, p_id: prid, p_approve: true, p_verified_amount: 20, p_verified_ref: 'OMT778899' }),
    'shop session adding points to a customer': await atk(pm, 'admin_points_adjust_v2', { p_session: mTok, p_phone: C1, p_points: 100000, p_note: 'xxxx' }),
    'internal ledger helper': await atk(pc, '_pts_add', { p_phone: C1, p_pts: 100000, p_kind: 'adjust', p_expires: null, p_tx: null, p_mid: null, p_actor: 'x', p_note: 'x' }),
    'internal allowance helper': await atk(pm, '_allow_add', { p_mid: MID, p_pts: 100000, p_source: 'adjust', p_from: null, p_to: null, p_plan: null, p_pkg: null, p_req: null, p_sub: null, p_by: null, p_note: 'x' }),
    'confirm someone else\'s purchase with another customer session': await atk(pc, 'customer_decide_tx_v2', { p_session: cTok, p_tx_id: sql1(`select id from public.pos_transactions where customer_phone='${C2}'`), p_confirm: true, p_detail_hash: '0'.repeat(64) }),
  };
  for (const [k, v] of Object.entries(A)) check('blocked: ' + k, v.startsWith('refused') || /"ok": ?false/.test(v) || /not_found/.test(v), v);
  check('balances unchanged by the attacks', sql1(`select points from public.customers where phone='${C1}'`) === '145' && sql1(`select sum(remaining) from public.allowance_grants where merchant_id='${MID}'`) === '1840',
    sql1(`select points from public.customers where phone='${C1}'`) + ' / ' + sql1(`select sum(remaining) from public.allowance_grants where merchant_id='${MID}'`));
  const legacy = await atk(pc, 'admin_list_customers', {}), legacy2 = await atk(pc, 'create_transaction', { p_merchant_id: MID, p_customer_phone: C1, p_invoice: 5, p_redeem: true, p_offer_id: null, p_items: [] });
  check('old functions closed: admin_list_customers and create_transaction refused to the public key', legacy.startsWith('refused') && legacy2.startsWith('refused'), legacy + ' | ' + legacy2);

  // ---- 8b. every existing screen still loads with sessions (no failed server call, no script error) ----
  const c0 = calls.length;
  for (const t of ['ao', 'am', 'ac', 'ap', 'aa', 'at']) { await pa.evaluate(x => { S.sub = null; S.tab = x; render() }, t); await W(500) }
  for (const sub of ['approvals', 'qrqueue', 'orders', 'settings', 'settingsWelcome', 'settingsSpending', 'settingsCats', 'settingsOffers']) { await pa.evaluate(x => { S.sub = x; render() }, sub); await W(400) }
  await pa.evaluate(() => { S.sub = null; S.tab = 'ao'; render(); return Promise.all([syncAdminMerchants(), syncAdminOrders(), syncAdminCustomers()]) }); await W(800);
  for (const t of ['mhome', 'mops', 'moff', 'macc']) { await pm.evaluate(x => { S.sub = null; S.tab = x; render() }, t); await W(500) }
  for (const sub of ['wallet', 'buy', 'notes', 'gallery', 'mypageEdit', 'qr', 'info']) { await pm.evaluate(x => { S.sub = x; render() }, sub); await W(500) }
  await pm.evaluate(() => { S.sub = null; return syncMerchantData(S.merchantId) }); await W(800);
  for (const t of ['home', 'shop', 'offers', 'collect', 'pts', 'me']) { await pc.evaluate(x => { S.sub = null; S.tab = x; render() }, t); await W(500) }
  await pc.evaluate(() => syncCustomerData(S.phone)); await W(800);
  const failed = calls.slice(c0).filter(c => c.status !== 200);
  check('screen sweep (admin 6 tabs + 8 pages, shop 4 tabs + 7 pages, customer tabs): every server call succeeds', failed.length === 0, failed.map(c => c.who + ':' + c.fn + ' ' + (c.err || '').slice(0, 40)).join(' | '));
  check('screen sweep: the calls went to session functions (no old account function used)', !calls.slice(c0).some(c => /^(admin_(?!.*_v2$)|merchant_(wallet|offers|transactions|notes_list|topup_orders|requests)$|customer_(profile|transactions|notes_list)$)/.test(c.fn)),
    [...new Set(calls.slice(c0).map(c => c.fn))].join(' '));

  // ---- 8c. register 12-Nov (3g): customer-chosen points, VIP, lower % with Admin approval, backups ----
  await pa.evaluate(() => aEngOpen()); await W(1200);
  await pa.fill('#en-vip_max_medium', '2'); await pa.evaluate(() => aEngSave('vip_max_medium')); await W(1000);
  check('3g admin sets the VIP count for medium shops', sql1(`select value from public.app_settings where key='vip_max_medium'`) === '2');
  await pm.evaluate(() => mVipOpen()); await W(1500);
  check('3g VIP candidates hide phone numbers', await pm.evaluate(c => !document.body.innerText.includes(c), C1));
  pm.once('dialog', d => d.accept('500'));
  await pm.click('button:has-text("اجعله VIP")'); await W(1500);
  check('3g owner makes a customer VIP (500/day), customer notified', sql1(`select count(*) from public.merchant_vips where merchant_id='${MID}' and status='active' and cap_points=500`) === '1'
    && sql1(`select count(*) from public.customer_notes where title like '👑%'`) === '1');
  await shot(pm, '11-vip');
  await pc2.evaluate(() => { payClose(); return payOpen() }); await W(1200);
  await pc2.fill('#payWantIn', '20'); await pc2.evaluate(() => payWant()); await W(1000);
  const s4 = await pc2.evaluate(() => { const el = [...document.querySelectorAll('#paySheet .ltr')].find(e => /^\d{4}-\d{4}$/.test(e.textContent.trim())); return el ? el.textContent.trim() : null });
  await pm.evaluate(() => { S.sub = 'new'; mfReset(); render() }); await W(300);
  await pm.fill('#mfcode', s4); await pm.click('button:has-text("تحقق")'); await W(1000);
  await pm.evaluate(() => { S.mf.items = [{ n: 'صنف', p: '30', q: 1 }]; S.mf.redeem = false; return mfNext() }); await W(1200);
  const q5 = await pm.evaluate(() => S.mf.quote);
  check('3g the customer chose 20 points: applied although the shop left points off (acceptance mandatory)', q5 && q5.redeem_pts === 20 && q5.customer_chose === true, JSON.stringify(q5));
  await shot(pc2, '12-customer-amount');
  await pm.evaluate(() => mfSend()); await W(3500); await pc2.click('#paySheet button.ok'); await W(1500);
  check('3g purchase with the chosen amount confirmed', sql1(`select count(*) from public.pos_transactions where customer_phone='${C2}' and status='CONFIRMED' and redeem_pts=20`) === '1');
  const pr = await pm.evaluate(() => sbRpc('merchant_set_redeem_pct', { p_merchant_id: S.merchantId, p_redeem_pct: 3, p_redeem_pct_vip: 3 }));
  check('3g a lower % is only a request until the Admin approves', pr && pr.ok === false && sql1(`select pending_redeem_pct||'/'||redeem_pct from public.merchants where id='${MID}'`) === '3/5', JSON.stringify(pr));
  await pa.evaluate(() => aPctOpen()); await W(1200); await pa.click('button:has-text("موافقة")'); await W(1200);
  check('3g Admin approves: 3 % applies', sql1(`select redeem_pct from public.merchants where id='${MID}'`) === '3');
  await pa.evaluate(() => aBakOpen()); await W(1200);
  check('3g Admin backups screen: wipe shown disabled', await pa.evaluate(() => S.b3a.bak && S.b3a.bak.wipe_enabled === false));
  await pa.evaluate(() => aBakNow()); await W(2000);
  check('3g backup without wipe from the Admin screen (audited, data untouched)', sql1(`select count(*) from tp_backup.wipe_runs where made_by='backup:b3admin'`) === '1'
    && sql1(`select count(*) from public.audit_log where action='wipe_snapshot'`) === '1' && sql1(`select value from public.app_settings where key='admin_wipe_enabled'`) === '0');
  await shot(pa, '13-admin-backups');

  // ---- 9. consistency + no script errors ----
  check('ledger = cached points for every customer', sql1(`select count(*) from public.customers where coalesce(points,0) <> public._pts_spendable(phone)`) === '0');
  check('audit log has the payment, plan and staff actions', sql1(`select count(distinct action) from public.audit_log where action in ('payment_request','payment_approve','plan_save','pay_settings','staff_create','payment_amount_mismatch')`) === '6');
  check('no JavaScript errors in any page', errors.length === 0, errors.join(' | '));

  await browser.close();
  const pass = results.filter(r => r.ok).length;
  fs.writeFileSync(path.join(OUT, 'e2e-b3.json'), JSON.stringify({ db: DB, pass, total: results.length, results, calls: calls.map(c => ({ who: c.who, fn: c.fn, status: c.status, err: c.err })) }, null, 1));
  console.log(`B3 E2E: ${pass}/${results.length}`);
  results.forEach(r => console.log((r.ok ? ' ok  ' : ' FAIL') + ' ' + r.name + (r.detail && !r.ok ? '  — ' + r.detail : '')));
  process.exit(0);
})();
