/* Tripoli Points — OFFLINE DEMO SERVER (test builds only, never part of the real app).
 *
 * Replaces the Supabase client in the demo build: every call the app makes is answered here, in the
 * browser, from invented sample data kept in localStorage. Nothing leaves the device: no Supabase,
 * no production data, no real purchases, payments or PIN changes.
 *
 * Demo accounts (PIN 1234 for all):
 *   customer 70 000 001 (450 points) · customer 70 000 002 (1,200 points)
 *   merchant 71 000 001 = «مقهى الميناء» · merchant 71 000 002 = «بصريات التل»
 * Add ?demo-reset=1 to the address to restore the sample data.
 */
(function () {
  'use strict';
  const KEY = 'tp_demo_db_v1', PIN = '1234', EXPIRY = 5 * 60 * 1000, now = () => Date.now();
  const U = n => `d0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
  const IMG = 'assets/img/';
  function seed() {
    const t = now(), D = 86400000;
    const shops = [
      [1, 'مقهى الميناء', 'cafe', 'الميناء', 34.4497, 35.8141, 'pack-20.61f04b66dd.jpg', '71000001', 6],
      [2, 'بصريات التل', 'glasses', 'التل', 34.4359, 35.8390, 'pack-10.13414a9e4b.jpg', '71000002', 5],
      [3, 'حلويات الأمراء', 'chocolate', 'المعرض', 34.4319, 35.8300, 'treasure-p9.f5080fc565.jpg', '71000003', 5],
      [4, 'ساعات عزمي', 'watches', 'عزمي بك', 34.4405, 35.8361, '', '71000004', 4],
      [5, 'عبايات الأمل', 'abayas', 'التل', 34.4367, 35.8397, 'pack-5.a80c7bb1f0.jpg', '71000005', 5],
      [6, 'إلكترونيات النور', 'mobile', 'ساحة النور', 34.4341, 35.8358, 'pack-30.7094ae2e77.jpg', '71000006', 3],
      [7, 'ستائر الفيحاء', 'curtains', 'نقابة الأطباء', 34.4449, 35.8279, 'banner-citadel.8f3103eb8b.jpg', '71000007', 5],
      [8, 'أحذية البولفار', 'shoes_men', 'البولفار', 34.4418, 35.8338, '', '71000008', 5]
    ].map(([n, name, cat, area, lat, lng, photo, phone, pct]) => ({ id: U(n), name, cat, area, lat, lng, phone, pct, tier: 'medium', status: 'active',
      addr: area + '، طرابلس', photo_url: photo ? IMG + photo : '', logo_url: '', redeem_pct: 5, redeem_pct_vip: 10, page_enabled: true,
      page_blurb: 'محل تجريبي في النسخة التجريبية من Tripoli Points.', extra_cats: [], created_at: new Date(t - 40 * D).toISOString() }));
    const off = (n, mid, type, x, ageDays, days) => Object.assign({ id: U(100 + n), mid: U(mid), type, title: '', badge: '', at: t - ageDays * D, days,
      active: true, val: null, gift_text: null, pts: null, per: null, old_price: null, new_price: null, img_url: '', specs: '', min: 0, first: false }, x);
    const offers = [
      off(1, 1, 'gift', { title: 'قهوة عربية مجاناً فوق $15', gift_text: 'قهوة عربية', min: 15, badge: 'حصري' }, 2, 10),
      off(2, 2, 'product', { title: 'نظارات شمسية مستقطبة', old_price: 45, new_price: 32, specs: 'إطار معدني خفيف مع علبة جلدية', img_url: IMG + 'pack-10.13414a9e4b.jpg', badge: 'جديد' }, 5, 30),
      off(3, 3, 'discount', { title: 'خصم 15% على علب الشوكولا', val: 15, min: 20, img_url: IMG + 'treasure-p9.f5080fc565.jpg' }, 3, 7),
      off(4, 4, 'bonus', { title: '50 نقطة إضافية كل $20', pts: 50, per: 20 }, 9, 90),
      off(5, 5, 'discount', { title: 'خصم 20% على تشكيلة الخريف', val: 20, min: 50, img_url: IMG + 'treasure-p3.9a60256500.jpg', badge: 'جديد' }, 2, 14),
      off(6, 6, 'product', { title: 'سماعات لاسلكية', old_price: 30, new_price: 20, specs: 'مع علبة شحن', img_url: IMG + 'pack-15.cd39a25f54.jpg' }, 7, 27),
      off(7, 7, 'discount', { title: 'خصم 10% فوق $100', val: 10, min: 100 }, 6, 20)
    ];
    const cats = [['cafe', 'مقاهي', '☕'], ['glasses', 'نظارات', '👓'], ['chocolate', 'حلويات وشوكولا', '🍫'], ['watches', 'ساعات', '⌚'], ['abayas', 'عبايات', '🧕'],
      ['mobile', 'هواتف وإلكترونيات', '📱'], ['curtains', 'ستائر وديكور', '🪟'], ['shoes_men', 'أحذية رجالية', '👞']]
      .map(([slug, name_ar, icon], i) => ({ id: U(200 + i), slug, name_ar, name_en: slug, icon, color: '#1d63e0', parent_id: null, sort_order: i, is_active: true }));
    const customers = {
      '70000001': { phone: '70000001', name: 'زبون تجريبي', last_name: 'أول', points: 450, status: 'active', photo_url: '', welcome_remain: 0, welcome_exp: null },
      '70000002': { phone: '70000002', name: 'زبونة تجريبية', last_name: 'ثانية', points: 1200, status: 'active', photo_url: '', welcome_remain: 0, welcome_exp: null }
    };
    return { v: 1, shops, offers, cats, customers, pins: { '70000001': PIN, '70000002': PIN, '71000001': PIN, '71000002': PIN, '71000003': PIN },
      tx: [], reqs: [], notes: [], mnotes: [], seq: 1000 };
  }
  function load() {
    try { if (/[?&]demo-reset=1\b/.test(location.search)) localStorage.removeItem(KEY) } catch (e) {}
    try { const d = JSON.parse(localStorage.getItem(KEY) || 'null'); if (d && d.v === 1) return d } catch (e) {}
    return seed();
  }
  let db = load();
  const save = () => { try { localStorage.setItem(KEY, JSON.stringify(db)) } catch (e) {} };
  const id = () => U(++db.seq);
  const shop = mid => db.shops.find(s => s.id === mid);
  const pub = s => { const c = Object.assign({}, s); delete c.phone; return c };
  const txRow = t => ({ id: t.id, mid: t.mid, phone: t.phone, cname: (db.customers[t.phone] || {}).name || 'زبون', invoice: t.invoice, net: t.net,
    redeemVal: t.redeemVal, redeemPts: t.redeemPts, earn: t.earn, items: t.items, status: t.status, at: t.at });
  function expire() { db.tx.forEach(t => { if (t.status === 'PENDING' && now() - t.at > EXPIRY) t.status = 'EXPIRED' }) }
  function note(phone, type, title, body) { db.notes.unshift({ id: id(), phone, type, title, body, at: now() }) }
  const ok = data => ({ data, error: null }), fail = message => ({ data: null, error: { message } });

  const H = {
    list_merchants: () => ok(db.shops.filter(s => s.status === 'active').map(pub)),
    get_categories: () => ok(db.cats),
    get_app_text_settings: () => ok({ welcome_bonus: '0', welcome_days: '0' }),
    list_active_offers_all: () => ok(db.offers.filter(o => o.active)),
    active_offers: a => ok(db.offers.filter(o => o.active && (!a || !a.p_merchant_id || o.mid === a.p_merchant_id))),
    store_gallery: () => ok([]), merchant_gallery_list: () => ok([]),
    customer_check_phone: a => ok({ exists: !!db.customers[a.p_phone] }),
    merchant_check_phone: a => ok({ exists: db.shops.some(s => s.phone === a.p_phone) }),
    customer_verify_pin: a => { const c = db.customers[a.p_phone]; return ok(c && db.pins[a.p_phone] === a.p_pin ? { ok: true, customer: c } : { ok: false, reason: 'bad_pin' }) },
    merchant_verify_pin: a => { const s = db.shops.find(x => x.phone === a.p_phone); return ok(s && (db.pins[a.p_phone] || PIN) === a.p_pin ? { ok: true, merchant: s } : { ok: false, reason: 'bad_pin' }) },
    customer_register: a => { db.customers[a.p_phone] = { phone: a.p_phone, name: a.p_name || 'زبون جديد', last_name: '', points: 100, status: 'active', photo_url: '', welcome_remain: 0, welcome_exp: null };
      db.pins[a.p_phone] = a.p_pin; save(); return ok({ ok: true, points: 100 }) },
    customer_profile: a => { const c = db.customers[a.p_phone]; return ok(c ? { ok: true, customer: c } : { ok: false }) },
    customer_transactions: a => { expire(); return ok(db.tx.filter(t => t.phone === a.p_phone).map(txRow)) },
    customer_notes_list: a => ok(db.notes.filter(n => n.phone === a.p_phone).map(n => ({ id: n.id, type: n.type, title: n.title, body: n.body, at: n.at }))),
    customer_create_request: a => { if (!shop(a.p_merchant_id)) return ok({ ok: false, error: 'المحل غير موجود' });
      db.reqs.push({ id: id(), mid: a.p_merchant_id, phone: a.p_phone, invoice: +a.p_invoice, offerId: a.p_offer_id || null, at: now(), status: 'open' }); save(); return ok({ ok: true }) },
    merchant_requests: a => ok(db.reqs.filter(r => r.mid === a.p_merchant_id && r.status === 'open').map(r => ({ id: r.id, phone: r.phone, invoice: r.invoice, offerId: r.offerId, at: r.at }))),
    merchant_close_request: a => { const r = db.reqs.find(x => x.id === a.p_request_id && x.mid === a.p_merchant_id); if (r) r.status = 'used'; save(); return ok({ ok: !!r }) },
    merchant_transactions: a => { expire(); return ok(db.tx.filter(t => t.mid === a.p_merchant_id).map(txRow)) },
    merchant_wallet: () => ok({ topped: 1000, cred: 0, used: 0, reserved: 0, balance: 100000, avail: 100000 }),
    merchant_offers: a => ok(db.offers.filter(o => o.mid === a.p_merchant_id)),
    merchant_notes_list: a => ok(db.mnotes.filter(n => n.mid === a.p_merchant_id)),
    merchant_topup_orders: () => ok([]),
    create_transaction: a => { const s = shop(a.p_merchant_id), c = db.customers[a.p_customer_phone]; if (!s || !c) return ok({ ok: false, error: 'بيانات غير صحيحة' });
      expire(); if (db.tx.some(t => t.mid === s.id && t.phone === c.phone && t.status === 'PENDING')) return ok({ ok: false, error: 'لدى الزبون عملية قيد التأكيد' });
      const inv = +a.p_invoice, redeemPts = a.p_redeem ? Math.min(Math.floor(c.points * 0.7), Math.round(inv * s.redeem_pct)) : 0, redeemVal = redeemPts / 100;
      const net = +(inv - redeemVal).toFixed(2), earn = Math.round(net * s.pct);
      const t = { id: id(), mid: s.id, phone: c.phone, invoice: inv, net, redeemPts, redeemVal, earn, items: a.p_items || [], status: 'PENDING', at: now() };
      db.tx.push(t); note(c.phone, 'points', 'عملية بانتظار تأكيدك', `${s.name}: فاتورة $${inv.toFixed(2)}`); save(); return ok({ ok: true, tx_id: t.id }) },
    decide_transaction: a => { expire(); const t = db.tx.find(x => x.id === a.p_tx_id); if (!t || t.status !== 'PENDING') return ok({ ok: false, error: 'not pending' });
      t.status = a.p_confirm ? 'CONFIRMED' : 'CANCELLED'; if (a.p_confirm) { const c = db.customers[t.phone]; c.points += t.earn - t.redeemPts;
        note(t.phone, 'points', 'تم تأكيد العملية', `أضيفت ${t.earn} نقطة إلى رصيدك`) } save(); return ok({ ok: true }) }
  };
  function answer(fn, args) {
    const h = H[fn];
    if (!h) return fail('هذه الميزة غير متاحة في النسخة التجريبية');
    try { return h(args || {}) } catch (e) { return fail('خطأ في الخادم التجريبي') }
  }
  // Same call shape as supabase-js: sb.rpc(fn,args) is awaitable and returns {data,error}.
  const later = v => new Promise(r => setTimeout(() => r(v), 120));
  const chain = p => { const o = new Proxy(function () {}, { get: (t, k) => k === 'then' ? p.then.bind(p) : k === 'catch' ? p.catch.bind(p) : k === 'finally' ? p.finally.bind(p) : () => o, apply: () => o }); return o };
  const ch = { on: () => ch, subscribe: () => ch, unsubscribe: () => {} };
  const client = {
    rpc: (fn, args) => chain(later(answer(fn, args))),
    from: () => chain(later(fail('غير متاح في النسخة التجريبية'))),
    functions: { invoke: () => later(fail('الدفع غير متاح في النسخة التجريبية')) },
    storage: { from: () => ({ upload: () => later(fail('رفع الصور غير متاح في النسخة التجريبية')), getPublicUrl: () => ({ data: { publicUrl: '' } }) }) },
    channel: () => ch, removeChannel: () => {},
    auth: new Proxy({}, { get: () => () => Promise.resolve({ data: { session: null, user: null }, error: null }) })
  };
  window.supabase = { createClient: () => client };
  window.TP_DEMO = { reset() { try { localStorage.removeItem(KEY) } catch (e) {} db = seed(); save() }, get db() { return db }, accounts: { customers: ['70000001', '70000002'], merchants: ['71000001', '71000002'], pin: PIN } };
})();
