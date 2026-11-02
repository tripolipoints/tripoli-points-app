const { test, expect, SHOP, open, login, shot } = require('./fixtures');

test.describe('Customer', () => {
  test('login, home, balance, offers page', async ({ page }, ti) => {
    await open(page);
    await login(page, '70000001');
    await expect(page.locator('.hero2')).toBeVisible();
    await expect(page.locator('.bal2')).toContainText('450');
    await expect(page.locator('#tpDemoBadge')).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await shot(page, ti, 'customer-home');
    await page.evaluate(() => navClick('offers'));
    await expect(page.locator('.o2c').first()).toBeVisible();
    expect(await page.locator('.o2c').count()).toBe(7);
    await shot(page, ti, 'customer-offers');
  });

  test('purchase request: «متابعة» disabled until a valid amount, one request, sent screen', async ({ page }, ti) => {
    await open(page);
    await login(page, '70000001');
    await page.evaluate(id => openCalc(id), SHOP(1));
    const go = page.locator('#ccGo');
    await expect(go).toBeDisabled();
    const amount = page.locator('#app input[inputmode="decimal"]');
    await amount.fill('0'); await expect(go).toBeDisabled();
    await amount.fill('18.5'); await expect(go).toBeEnabled();
    await shot(page, ti, 'calculator-ready');
    await amount.fill(''); await expect(go).toBeDisabled();
    await amount.fill('18.5');
    await go.click();
    await expect(page.locator('#app')).toContainText('وصل طلبك');
    const n = await page.evaluate(() => TP_DEMO.db.reqs.length);
    expect(n).toBe(1);
    await shot(page, ti, 'request-sent');
  });

  test('forgotten PIN leads to support, never to a new-PIN form', async ({ page }, ti) => {
    await open(page);
    await page.evaluate(() => { S.screen = 'login'; render() });
    await page.fill('#ph', '70000001');
    await page.evaluate(() => phoneNext());
    await page.waitForFunction(() => S.screen === 'pin');
    await page.getByText('نسيت رمز الحماية؟').click();
    await expect(page.locator('#app')).toContainText('لحماية حسابك ونقاطك');
    await expect(page.locator('a[href*="wa.me"]')).toBeVisible();
    expect(await page.evaluate(() => S.pinMode)).toBe('enter');
    await shot(page, ti, 'forgot-pin-customer');
  });
});
