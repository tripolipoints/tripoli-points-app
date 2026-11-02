const { test, expect, SHOP, open, login, shot } = require('./fixtures');

test('merchant: grouped request → send purchase → customer confirms once', async ({ page }, ti) => {
  await open(page);
  // the customer sends the same request twice (the case seen in the real test)
  await page.evaluate(id => { for (let i = 0; i < 2; i++) TP_DEMO.db.reqs.push({ id: 'd0000000-0000-4000-8000-00000000090' + i, mid: id, phone: '70000002', invoice: 10, offerId: null, at: Date.now() - i * 60000, status: 'open' }) }, SHOP(1));
  // As in the real two-device test, the customer has used this device before (see the known-limitation test below)
  await login(page, '70000002');
  await page.evaluate(() => logout());
  await login(page, '71000001');
  await expect(page.locator('#app')).toContainText('مقهى الميناء');
  await expect(page.getByRole('button', { name: 'ابدأ العملية' })).toHaveCount(1);
  await expect(page.locator('#app')).toContainText('أُرسل مرتين');
  await shot(page, ti, 'merchant-requests');
  await page.getByRole('button', { name: 'ابدأ العملية' }).click();
  await page.evaluate(() => mfNext());
  const send = page.locator('#app button.btn.blue', { hasText: 'تأكيد العملية' });
  await send.click();
  await page.waitForFunction(() => S.tab === 'mops' && S.mopf === 'PENDING');
  await shot(page, ti, 'merchant-pending-list');
  const db = await page.evaluate(() => ({ tx: TP_DEMO.db.tx.length, open: TP_DEMO.db.reqs.filter(r => r.status === 'open').length }));
  expect(db).toEqual({ tx: 1, open: 0 });
  // the customer confirms; points move once even with repeated taps
  await page.evaluate(() => logout());
  await login(page, '70000002');
  await page.evaluate(() => openNotes());
  const ok = page.locator('#notePend .btn.ok');
  await expect(ok).toBeVisible();
  await shot(page, ti, 'customer-pending');
  await page.evaluate(() => { const b = document.querySelector('#notePend .btn.ok'); b.click(); b.click() });
  await page.waitForFunction(() => TP_DEMO.db.tx[0].status === 'CONFIRMED');
  expect(await page.evaluate(() => TP_DEMO.db.customers['70000002'].points)).toBe(1200 + 60);
});

test('merchant: QR poster and forgotten PIN', async ({ page }, ti) => {
  await open(page);
  await login(page, '71000002');
  await page.evaluate(() => { S.tab = 'macc'; S.sub = 'qr'; render() });
  await expect(page.locator('#app svg').first()).toBeVisible();
  await shot(page, ti, 'merchant-qr-poster');
  await page.evaluate(() => logout());
  await page.evaluate(() => { S.screen = 'login'; render() });
  await page.fill('#ph', '71000002');
  await page.evaluate(() => phoneNext());
  await page.waitForFunction(() => S.screen === 'pin');
  await page.getByText('نسيت رمز الحماية؟').click();
  await expect(page.locator('#app')).toContainText('حساب محلك');
});

// KNOWN LIMITATION (existing behaviour since the first version, not changed here): the merchant's new-purchase form only accepts
// customers whose details this browser already holds; the app has no server lookup for a customer's phone. On a fresh device
// the merchant sees «هذا الرقم غير مسجّل في التطبيق» even for a registered customer. Recorded so it can be decided separately.
test('known limitation: merchant on a fresh device cannot start a purchase for a registered customer', async ({ page }) => {
  test.info().annotations.push({ type: 'known limitation', description: 'merchant form checks customers held in the browser only' });
  await open(page);
  await page.evaluate(id => TP_DEMO.db.reqs.push({ id: 'd0000000-0000-4000-8000-000000000950', mid: id, phone: '70000002', invoice: 10, offerId: null, at: Date.now(), status: 'open' }), SHOP(1));
  await login(page, '71000001');
  await page.getByRole('button', { name: 'ابدأ العملية' }).click();
  await page.evaluate(() => { window.__t = []; const t = window.toast; window.toast = function (m) { __t.push(m); return t.apply(this, arguments) }; mfNext() });
  expect(await page.evaluate(() => ({ step: S.mf.step, toast: __t[0] }))).toEqual({ step: 1, toast: 'هذا الرقم غير مسجّل في التطبيق' });
});
