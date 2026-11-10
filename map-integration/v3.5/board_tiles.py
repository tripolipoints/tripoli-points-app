# -*- coding: utf-8 -*-
"""Cut the realistic category photos out of the source boards (picture.rar): finds each tile's gold ring (marching inward from the
cream background: first gold = outer edge, end of gold = inner edge), fits the inner circle, and keeps only the photo inside it —
the board's gold ring, the label ribbon and any text are left out. Writes <out>/<board>_<row><col>.png (col counted from the right).
Usage: python3 -I board_tiles.py <boards dir> <out dir>"""
import os, sys, math, glob
import numpy as np
from PIL import Image
SRC, OUT = sys.argv[1:3]; os.makedirs(OUT, exist_ok=True)
CROP = float(os.environ.get('CROP', '.90'))
COLS = [.8812, .6895, .4962, .3045, .1143]; ROWS = [.188, .684]
def gold(p): r, g, b = int(p[0]), int(p[1]), int(p[2]); return r > 170 and g > 110 and b < 120 and r - b > 95 and r >= g
def fit(pts):
    A = np.array([[x, y, 1] for x, y in pts], float); bb = np.array([-(x * x + y * y) for x, y in pts], float)
    D, E, F = np.linalg.lstsq(A, bb, rcond=None)[0]; cx, cy = -D / 2, -E / 2; return cx, cy, math.sqrt(cx * cx + cy * cy - F)
def tile(a, ex, ey, W):
    R0 = int(W * .105); inner = []
    for k in range(48):
        t = math.radians(-200 + k * (220 / 47))            # upper arc only (the pin tail is below)
        dx, dy = math.cos(t), math.sin(t); seen = False; run = 0
        for r in range(R0, int(W * .03), -1):
            x, y = int(ex + dx * r), int(ey + dy * r)
            if not (0 <= x < a.shape[1] and 0 <= y < a.shape[0]): continue
            g = gold(a[y, x])
            if g: seen = True; run = 0
            elif seen:
                run += 1
                if run >= 3: inner.append((x + dx * 3, y + dy * 3)); break
    cx, cy, r = fit(inner)
    for _ in range(2):                                     # drop outliers (gold objects inside the photo) and refit
        d = [abs(math.hypot(x - cx, y - cy) - r) for x, y in inner]; m = sorted(d)[len(d) // 2] * 2.5 + 2
        inner = [p for p, e in zip(inner, d) if e <= m]; cx, cy, r = fit(inner)
    return cx, cy, r
for f in sorted(glob.glob(os.path.join(SRC, '*.png'))):
    im0 = Image.open(f).convert('RGBA'); im = Image.new('RGBA', im0.size, (250, 242, 224, 255)); im.alpha_composite(im0); im = im.convert('RGB'); a = np.asarray(im); W, H = im.size; base = os.path.splitext(os.path.basename(f))[0]
    if 'LAST_2' in base: slots = [(0, 0, .70, .34), (0, 1, .31, .34)]
    else: slots = [(ri, ci, COLS[ci], ROWS[ri]) for ri in range(2) for ci in range(5)]
    for ri, ci, fx, fy in slots:
        try: cx, cy, r = tile(a, fx * W, fy * H, W if 'LAST_2' not in base else W * 1.9)
        except Exception as e: print('fail', base, ri, ci, e); continue
        rc = r * CROP
        cy += r * float(os.environ.get("DY", ".03")); im.crop((int(cx - rc), int(cy - rc), int(cx + rc), int(cy + rc))).save(os.path.join(OUT, f'{base}_{ri}{ci}.png'))
        print(f'{base[:28]:28} {ri}{ci} c=({cx:.0f},{cy:.0f}) r={r:.0f}')
