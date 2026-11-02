// Shared helpers. The network guard is the safety net: only the local demo server may be reached.
// Map tiles and the routing service are outside the demo, so tiles are blocked and routes get a fixed test answer.
const base = require('@playwright/test');
const PROD = 'lqbhfkowqaqlgcrdybvv';
const test = base.test.extend({
  page: async ({ page }, use, testInfo) => {
    const blocked = [];
    await page.route('**/*', route => {
      const u = route.request().url();
      if (u.includes(PROD) || u.includes('supabase.co')) { blocked.push(u); return route.abort() }
      if (u.startsWith('http://127.0.0.1:4173/') || u.startsWith('data:') || u.startsWith('blob:')) return route.continue();
      if (u.includes('/route/v1/')) { // routing service: a fixed L-shaped route between the two points asked for
        const pts = u.split('/route/v1/')[1].split('/')[1].split('?')[0].split(';').map(p => p.split(',').map(Number));
        const walk = u.includes('foot'), mid = walk ? [(pts[0][0] + pts[1][0]) / 2 + 0.001, (pts[0][1] + pts[1][1]) / 2] : [pts[0][0], pts[1][1]];
        return route.fulfill({ contentType: 'application/json', body: JSON.stringify({ code: 'Ok', routes: [{ distance: walk ? 900 : 1400, duration: walk ? 700 : 240, geometry: { type: 'LineString', coordinates: [pts[0], mid, pts[1]] } }] }) });
      }
      return route.abort();
    });
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    await use(page);
    base.expect(blocked, 'no request may reach Supabase').toEqual([]);
    base.expect(errors, 'no JavaScript errors').toEqual([]);
  }
});
const expect = base.expect;
const SHOP = n => `d0000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

async function open(page, hash = '') {
  await page.goto('/index.html?demo-reset=1' + hash);
  await page.waitForFunction(() => typeof S === 'object' && typeof render === 'function');
}
async function login(page, phone, pin = '1234') {
  await page.evaluate(() => { S.screen = 'login'; render() });
  await page.fill('#ph', phone);
  await page.evaluate(() => phoneNext());
  await page.waitForFunction(() => S.screen === 'pin');
  for (const d of pin) await page.locator('.pad button', { hasText: new RegExp('^' + d + '$') }).click();
  await page.waitForFunction(() => S.screen === 'app');
}
async function shot(page, testInfo, name) {
  const file = testInfo.outputPath(name + '.png');
  await page.screenshot({ path: file });
  await testInfo.attach(name, { path: file, contentType: 'image/png' });
}
module.exports = { test, expect, SHOP, open, login, shot };
