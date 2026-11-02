const { test, expect, SHOP, open, login, shot } = require('./fixtures');

test('poster link #q-<shop> opened before login → that shop’s purchase screen after login', async ({ page }) => {
  await open(page, '#q-' + SHOP(3));
  expect(await page.evaluate(() => S.qrMid)).toBe(SHOP(3));
  await login(page, '70000001');
  await page.waitForFunction(id => S.sub === 'calc' && S.storeId === id, SHOP(3));
  await expect(page.locator('#app')).toContainText('حلويات الأمراء');
});

test('«امسح QR»: opens from the home picture, bundled decoder, pasted link opens the shop', async ({ page }, ti) => {
  const libs = [];
  page.on('request', r => { if (/jsqr/i.test(r.url())) libs.push(r.url()) });
  await open(page);
  await login(page, '70000001');
  const pill = page.locator('.hero2 .qrsHero');
  await expect(pill).toBeVisible();
  const g = await page.evaluate(() => { const r = s => document.querySelector(s).getBoundingClientRect(); const p = r('.hero2 .qrsHero'), b = r('.hero2 .bell'), h = r('.hero2');
    return { underBell: p.top >= b.bottom - 1, inHero: p.left >= h.left && p.right <= h.right && p.bottom <= h.bottom } });
  expect(g).toEqual({ underBell: true, inHero: true }); // on the picture, under the bell, not over it
  await pill.click();
  await expect(page.locator('#qrsModal')).toBeVisible();
  await page.waitForFunction(() => typeof window.jsQR === 'function');
  expect(libs.length).toBeGreaterThan(0);
  for (const u of libs) expect(u).toMatch(/^http:\/\/127\.0\.0\.1:4173\/assets\/js\/jsqr-1\.4\.0\./);
  await shot(page, ti, 'scanner-open');
  await page.fill('#qrsVal', 'https://example.com/not-a-shop');
  await page.locator('.qrsRow .btn').click();
  await expect(page.locator('#qrsMsg')).toHaveClass(/bad/);
  await page.fill('#qrsVal', 'https://tripoli.example/index.html#q-' + SHOP(2));
  await page.locator('.qrsRow .btn').click();
  await page.waitForFunction(id => S.sub === 'calc' && S.storeId === id, SHOP(2));
  await expect(page.locator('#qrsModal')).toHaveCount(0);
});

test('camera reads a printed shop QR (Chromium test camera)', async ({ page, browserName }, ti) => {
  test.skip(browserName !== 'chromium' || !process.env.QR_CAMERA_FILE, 'needs the Chromium fake camera with the poster video');
  await open(page);
  await login(page, '70000001');
  await page.locator('.hero2 .qrsHero').click();
  await page.locator('#qrsCam').click();
  await page.waitForFunction(id => S.sub === 'calc' && S.storeId === id, SHOP(1), { timeout: 15000 });
  expect(await page.evaluate(() => qrsStream)).toBeNull(); // camera released
  await shot(page, ti, 'camera-opened-shop');
});

test('QR poster sheet shows the 8 demo shops', async ({ page }, ti) => {
  await page.goto('/qr-posters.html');
  await expect(page.locator('.c svg')).toHaveCount(8);
  await shot(page, ti, 'qr-posters');
});
