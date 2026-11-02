#!/usr/bin/env python3
"""Build the OFFLINE DEMO of Tripoli Points from the app's index.html (test use only).

    python3 demo/build_demo.py [output_dir]      # default: dist-demo

The output is a static folder: the unchanged app, except that the Supabase client is swapped for
demo/demo-server.js (sample data in the browser) and the production project address is removed.
The build stops with an error if any reference to the production project is left.
It also writes qr-posters.html (QR codes of the demo shops, drawn with the app's own QR encoder)
and README-DEMO.txt. The app's own files in the repository are not modified.
"""
import os, re, shutil, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'dist-demo'))
PROD = 'lqbhfkowqaqlgcrdybvv'
SB_SCRIPT = '<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>'

src = open(os.path.join(ROOT, 'index.html'), encoding='utf-8').read()

def sub_once(pattern, repl, text, label):
    new, n = re.subn(pattern, repl, text, count=1)
    if n != 1:
        sys.exit(f'build_demo: could not find {label}')
    return new

html = src
if html.count(SB_SCRIPT) != 1:
    sys.exit('build_demo: Supabase script tag not found')
html = html.replace(SB_SCRIPT, '<script src="demo-server.js"></script>')
html = sub_once(r"const SB_URL='[^']*';", "const SB_URL='https://demo.invalid';", html, 'SB_URL')
html = sub_once(r"const SB_KEY='[^']*';", "const SB_KEY='offline-demo';", html, 'SB_KEY')
html = re.sub(r'<link rel="preconnect" href="https://[a-z0-9]+\.supabase\.co"[^>]*>\n?', '', html)
html = html.replace('<title>Tripoli Points</title>', '<title>Tripoli Points — نسخة تجريبية</title>', 1)

BADGE = """
<script>
/* OFFLINE DEMO badge: tap it to see the demo accounts. Test builds only. */
(function(){function add(){if(document.getElementById('tpDemoBadge'))return;const b=document.createElement('button');b.id='tpDemoBadge';b.type='button';
 b.textContent='نسخة تجريبية · بيانات وهمية';
 b.style.cssText='position:fixed;z-index:99998;top:calc(4px + env(safe-area-inset-top,0px));left:calc(4px + env(safe-area-inset-left,0px));font:700 10px system-ui;background:#f5b301;color:#0c2a6b;border:0;border-radius:999px;padding:3px 8px;opacity:.92;direction:rtl';
 b.onclick=()=>toast('زبون: 70000001 أو 70000002 · تاجر: 71000001 أو 71000002 · الرمز 1234');document.body.appendChild(b)}
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',add);else add()})();
</script>
"""
html = html.replace('</body>', BADGE + '</body>', 1) if '</body>' in html else html + BADGE

if PROD in html or 'supabase.co' in html:
    sys.exit('build_demo: a production Supabase reference is still present')

# QR encoder taken from the app itself, for the poster sheet
m = re.search(r"const QRMini=\(function\(\)\{.*?\n\}\)\(\);", src, re.S)
q = re.search(r"function qrSvg\(text,px\)\{.*?\n\}", src, re.S)
if not (m and q):
    sys.exit('build_demo: QR encoder not found in index.html')
shops = [(1, 'مقهى الميناء'), (2, 'بصريات التل'), (3, 'حلويات الأمراء'), (4, 'ساعات عزمي'),
         (5, 'عبايات الأمل'), (6, 'إلكترونيات النور'), (7, 'ستائر الفيحاء'), (8, 'أحذية البولفار')]
cards = ','.join("['d0000000-0000-4000-8000-%012d','%s']" % (n, name) for n, name in shops)
posters = """<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>ملصقات QR — النسخة التجريبية</title>
<style>body{font-family:system-ui,sans-serif;background:#f2f6fc;color:#13234a;margin:0;padding:16px}h1{font-size:20px;margin:0 0 4px}p{margin:0 0 14px;color:#4c5b78}
.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:14px}.c{background:#fff;border-radius:16px;padding:14px;text-align:center;box-shadow:0 2px 10px #0c2a6b14}
.c b{display:block;margin-top:8px}.c small{display:block;color:#6b7a99;direction:ltr;font-size:10px;word-break:break-all}</style></head><body>
<h1>ملصقات QR للمحلات التجريبية</h1><p>افتح هذه الصفحة على شاشة الكمبيوتر، ثم امسح أحد الرموز من الآيفون: بزر «امسح QR» داخل التطبيق، أو بكاميرا الآيفون العادية.</p>
<div class="g" id="g"></div><script>
""" + m.group(0) + "\n" + q.group(0) + """
const base=location.href.replace(/qr-posters\\.html.*$/,'index.html');
document.getElementById('g').innerHTML=[""" + cards + """].map(([id,n])=>`<div class="c">${qrSvg(base+'#q-'+id,200)}<b>${n}</b><small>${base}#q-${id}</small></div>`).join('');
</script></body></html>"""

README = """Tripoli Points — OFFLINE DEMO (test build only)
=================================================
This build makes NO connection to any Supabase project. All data are invented and stay in the
browser of the device (localStorage). No real customers, purchases, payments or PIN changes.

Demo accounts (PIN 1234):
  Customer 70000001 (450 points), customer 70000002 (1,200 points)
  Merchant 71000001 = مقهى الميناء, merchant 71000002 = بصريات التل
Tap the yellow «نسخة تجريبية» badge to see them. Add ?demo-reset=1 to the address to restore the sample data.

QR posters: open qr-posters.html on a computer screen and scan with the iPhone, or log in as a
merchant and open «حسابي» → «رمز QR الخاص بمحلك».

Payments, photo uploads and the admin panel are not available in this demo (they show a message).
The camera only works over HTTPS: see TESTING-ON-IPHONE.txt.
"""
IPHONE = """Testing the offline demo on an iPhone over HTTPS
==================================================
The iPhone camera (and so «امسح QR») needs an https:// address. Two free options that do not touch
the production site or the production database:

Option A — Netlify Drop (about 2 minutes, no account needed for a temporary link)
  1. On a computer, unzip the demo ZIP.
  2. Open https://app.netlify.com/drop and drag the unzipped folder onto the page.
  3. Netlify gives a new random https:// address. It is a separate test site, not the production site.
  4. Open that address in Safari on the iPhone.

Option B — GitHub Pages from the test branch (a stable link)
  Ask Claude to publish the demo to a separate test repository with GitHub Pages; never use the
  production repository's Pages or the production Netlify site.

What to check on the iPhone
  1. Log in as customer 70000001 / 1234.
  2. Home: tap «امسح QR» (on the picture, under the bell) → «فتح الكاميرا» → allow the camera →
     point it at a code on qr-posters.html (on the computer). The shop's purchase screen opens.
  3. In the purchase screen «متابعة» is grey until you type an amount above 0.
  4. Send a request; then log in as the merchant (71000001 for مقهى الميناء) on the computer to see it.
  5. Scan a poster with the normal iPhone camera app: Safari opens the demo, log in, and the same
     shop's purchase screen opens by itself.
  6. Log out, enter 70000001, tap «نسيت رمز الحماية؟»: a support screen appears (no new PIN form).
  7. Maps: pins, zoom, selecting a shop and the walking/driving route work as before.
"""

if os.path.exists(OUT):
    shutil.rmtree(OUT)
os.makedirs(OUT)
for d in ('assets',):
    shutil.copytree(os.path.join(ROOT, d), os.path.join(OUT, d))
for f in ('_headers',):
    if os.path.exists(os.path.join(ROOT, f)):
        shutil.copy(os.path.join(ROOT, f), OUT)
shutil.copy(os.path.join(ROOT, 'demo', 'demo-server.js'), OUT)
open(os.path.join(OUT, 'index.html'), 'w', encoding='utf-8').write(html)
open(os.path.join(OUT, 'qr-posters.html'), 'w', encoding='utf-8').write(posters)
open(os.path.join(OUT, 'README-DEMO.txt'), 'w', encoding='utf-8').write(README)
open(os.path.join(OUT, 'TESTING-ON-IPHONE.txt'), 'w', encoding='utf-8').write(IPHONE)
for root, _, files in os.walk(OUT):
    for f in files:
        if f.endswith(('.html', '.js', '.txt')) and PROD in open(os.path.join(root, f), encoding='utf-8', errors='ignore').read():
            sys.exit('build_demo: production reference found in ' + f)
print('demo built in', OUT)
