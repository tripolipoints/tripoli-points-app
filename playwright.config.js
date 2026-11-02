// Playwright runs only against the OFFLINE DEMO build (dist-demo, made by demo/build_demo.py).
// No test can reach Supabase: every request that is not to the local demo server is blocked (tests/fixtures.js).
const { defineConfig, devices } = require('@playwright/test');
const widths = [[320, 568], [375, 667], [390, 844], [430, 932]];
const mobile = { isMobile: true, hasTouch: true, deviceScaleFactor: 2 };
module.exports = defineConfig({
  testDir: 'tests',
  timeout: 60_000,
  expect: { timeout: 8_000 },
  fullyParallel: true,
  workers: process.env.CI ? 2 : 3,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }], ['json', { outputFile: 'test-results/results.json' }]],
  use: { baseURL: 'http://127.0.0.1:4173', trace: 'retain-on-failure', screenshot: 'only-on-failure', locale: 'ar-LB', timezoneId: 'Asia/Beirut' },
  webServer: { command: 'python3 -m http.server 4173 --bind 127.0.0.1 --directory dist-demo', url: 'http://127.0.0.1:4173/index.html', reuseExistingServer: true, timeout: 30_000 },
  projects: [
    ...widths.map(([w, h]) => ({
      name: `chromium-${w}`,
      use: { ...devices['Desktop Chrome'], ...mobile, viewport: { width: w, height: h },
        launchOptions: { args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream',
          ...(process.env.QR_CAMERA_FILE ? [`--use-file-for-fake-video-capture=${process.env.QR_CAMERA_FILE}`] : [])] },
        permissions: ['camera'] }
    })),
    // iPhone Safari engine (WebKit). The camera itself cannot be simulated in WebKit, so camera-decoding tests skip here.
    ...(process.env.SKIP_WEBKIT ? [] : [{ name: 'webkit-iphone-390', use: { ...devices['iPhone 13'] } }])
  ]
});
