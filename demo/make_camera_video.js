// Makes a short test-camera video of one demo shop's QR poster (for the Chromium fake camera).
// Usage: node demo/make_camera_video.js dist-demo/qr-camera.y4m   (needs ffmpeg and the demo server running)
const { chromium } = require('@playwright/test');
const { execFileSync } = require('child_process');
(async () => {
  const out = process.argv[2] || 'dist-demo/qr-camera.y4m', png = out.replace(/\.y4m$/, '.png');
  const b = await chromium.launch(); const p = await b.newPage({ viewport: { width: 640, height: 480 } });
  await p.goto('http://127.0.0.1:4173/qr-posters.html');
  const svg = await p.locator('.c svg').first().evaluate(e => e.outerHTML);
  await p.setContent(`<body style="margin:0;width:640px;height:480px;display:flex;align-items:center;justify-content:center;background:#cfc8b8"><div style="background:#fff;padding:20px;transform:rotate(4deg)">${svg}</div></body>`);
  await p.screenshot({ path: png }); await b.close();
  execFileSync('ffmpeg', ['-loglevel', 'error', '-y', '-loop', '1', '-i', png, '-t', '4', '-r', '15', '-pix_fmt', 'yuv420p', out]);
  console.log('camera video:', out);
})();
