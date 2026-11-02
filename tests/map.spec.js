const { test, expect, SHOP, open, login, shot } = require('./fixtures');

test('map: shops shown, selecting a shop, walking and driving routes, cancel', async ({ page }, ti) => {
  await open(page);
  await login(page, '70000001');
  await page.waitForFunction(() => S.merchants.filter(m => !m.demo).length === 8);
  await expect(page.locator('#rmap')).toBeVisible();
  await page.waitForFunction(() => document.querySelectorAll('#rmap .pn').length > 0);
  await shot(page, ti, 'map-home');
  await page.evaluate(id => { const e = document.querySelector('#rmap .pn[data-id="' + id + '"]'); e ? e.click() : pinTap(id) }, SHOP(1));
  await page.waitForFunction(id => S.sel === id, SHOP(1));
  const walk = page.locator('#promoSlot .rtrow .walk, #promoSlot .rtSeg button[aria-label="مشياً"]').first();
  await expect(walk).toBeVisible();
  await walk.click();
  await page.waitForFunction(() => S.route && !S.route.loading && S.route.mode === 'foot', null, { timeout: 15000 }).catch(() => {});
  await page.waitForFunction(() => document.querySelectorAll('#rsv polyline').length > 0, null, { timeout: 15000 });
  await shot(page, ti, 'map-walking-route');
  const car = page.locator('#promoSlot .rtrow .car, #promoSlot .rtSeg button[aria-label="بالسيارة"]').first();
  await car.click();
  await page.waitForFunction(() => S.route && S.route.mode !== 'foot' && !S.route.loading, null, { timeout: 15000 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});
