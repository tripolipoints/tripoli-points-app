# -*- coding: utf-8 -*-
"""V3.6 (Staging): the six regional pins get the user's area photos in the medallion and the «أبي سمراء» reference look —
photo filling the inner circle, beige name ribbon (arched top, thin gold edge) on the lower part. The gold body, shine, shadow,
canvas (360×394) and tip point are taken unchanged from the current r0..r5 art, so pin size and anchor stay identical.
Name and count stay live HTML text (CSS in region_patch). Usage: python3 -I region_pins.py <photos dir> <pins dir>"""
import os, sys, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
SRC, PINS = sys.argv[1:3]
CX, CY, R = 177.6, 142.3, 103.4            # inner circle of the current art (fitted on all six: identical)
SS = 4                                      # supersampling
# region → (pin file, photo, focus x, focus y, zoom) — the photo is cover-fitted into the circle around the focus point
P = {'الميناء': ('r0', 'الميناء.jpg', .50, .58, 1.0), 'التل': ('r1', 'ساعة التل.jpg', .46, .44, 1.0),
     'عزمي بك': ('r2', 'عزمي بك.jpg', .50, .42, 1.0), 'القبة': ('r3', 'القبة.jpeg', .42, .50, 1.0),
     'ضم والفرز': ('r4', 'ضم والفرز.jpg', .55, .45, 1.0), 'أبو سمراء': ('r5', 'ابي سمراء.png', None, None, None)}
def photo(name, fx, fy, zoom, side):
    im = Image.open(os.path.join(SRC, name)).convert('RGB')
    if fx is None:                          # «أبي سمراء»: the scene inside the reference pin (above its ribbon), no ring, no text
        im = im.crop((290, 150, 830, 690)); fx = fy = .5; zoom = 1.0
    W, H = im.size; s = min(W, H) / zoom
    x0 = min(max(fx * W - s / 2, 0), W - s); y0 = min(max(fy * H - s / 2, 0), H - s)
    t = im.crop((round(x0), round(y0), round(x0 + s), round(y0 + s))).resize((side, side), Image.LANCZOS)
    t = ImageEnhance.Contrast(t).enhance(1.04); return t.filter(ImageFilter.UnsharpMask(radius=2, percent=40, threshold=2))
def build(key, out):
    base = Image.open(os.path.join(PINS, key + '.webp')).convert('RGBA'); W, H = base.size
    big = base.resize((W * SS, H * SS), Image.LANCZOS); cx, cy, r = CX * SS, CY * SS, (R + 1.2) * SS
    return big, cx, cy, r
for area, (key, fn, fx, fy, z) in P.items():
    base = Image.open(os.path.join(PINS, key + '.webp')).convert('RGBA'); W, H = base.size
    big = base.resize((W * SS, H * SS), Image.LANCZOS); cx, cy, r = CX * SS, CY * SS, (R + 1.0) * SS
    d = round(2 * r); ph = photo(fn, fx, fy, z, d).convert('RGBA')
    circ = Image.new('L', (d, d), 0); ImageDraw.Draw(circ).ellipse((0, 0, d - 1, d - 1), fill=255)
    # soft inner shadow along the top of the circle (depth under the gold ring, as in the reference)
    sh = Image.new('L', (d, d), 0); ImageDraw.Draw(sh).ellipse((0, 0, d - 1, d - 1), fill=90)
    ImageDraw.Draw(sh).ellipse((int(.03 * d), int(.06 * d), int(.97 * d), int(1.0 * d)), fill=0); sh = sh.filter(ImageFilter.GaussianBlur(.03 * d))
    ph.alpha_composite(Image.new('RGBA', (d, d), (40, 22, 0, 255)), (0, 0)) if False else None
    dark = Image.new('RGBA', (d, d), (45, 25, 0, 0)); dark.putalpha(sh); ph.alpha_composite(dark)
    # ribbon: lower part of the circle under an arched top edge (top of arch .30 r below centre, meets the circle at .58 r)
    rib = Image.new('L', (d, d), 0); px = rib.load()
    ys = np.arange(d)[:, None] - d / 2; xs = np.arange(d)[None, :] - d / 2
    top = .30 * r + (.58 - .30) * r * (xs / (.815 * r)) ** 2
    inside = (xs ** 2 + ys ** 2) <= (r - .5 * SS) ** 2
    m = (ys >= top) & inside; rib = Image.fromarray((m * 255).astype('uint8')).filter(ImageFilter.GaussianBlur(.6 * SS))
    edge = Image.fromarray((((ys >= top - 2.0 * SS) & inside) * 255).astype('uint8')).filter(ImageFilter.GaussianBlur(.5 * SS))
    # shadow cast by the ribbon onto the photo
    shadow = Image.new('RGBA', (d, d), (40, 22, 0, 0)); shadow.putalpha(Image.fromarray((((ys >= top - 3.5 * SS) & inside) * 70).astype('uint8')).filter(ImageFilter.GaussianBlur(2.2 * SS)))
    ph.alpha_composite(shadow)
    gold = Image.new('RGBA', (d, d)); g = np.zeros((d, d, 4), 'uint8')
    t = np.clip((ys - top) / (.6 * r) + .5, 0, 1); g[..., 0] = 205 + 45 * (1 - t); g[..., 1] = 150 + 70 * (1 - t); g[..., 2] = 45 + 70 * (1 - t); g[..., 3] = 255
    gold = Image.fromarray(g); gold.putalpha(edge); ph.alpha_composite(gold)
    c = np.zeros((d, d, 4), 'uint8'); u = np.clip((ys - top) / (.55 * r), 0, 1)
    c[..., 0] = 253 - 14 * u; c[..., 1] = 245 - 25 * u; c[..., 2] = 225 - 45 * u; c[..., 3] = 255
    cream = Image.fromarray(c); cream.putalpha(rib); ph.alpha_composite(cream)
    ph.putalpha(Image.fromarray(np.minimum(np.asarray(ph.getchannel('A')), np.asarray(circ))))
    big.alpha_composite(ph, (round(cx - d / 2), round(cy - d / 2)))
    # the gold ring's own inner edge goes back on top (photo never covers the frame)
    ring = big.copy(); orig = base.resize((W * SS, H * SS), Image.LANCZOS)
    keep = Image.new('L', big.size, 255); ImageDraw.Draw(keep).ellipse((cx - R * SS + 1.5 * SS, cy - R * SS + 1.5 * SS, cx + R * SS - 1.5 * SS, cy + R * SS - 1.5 * SS), fill=0)
    big.paste(orig, (0, 0), keep.filter(ImageFilter.GaussianBlur(.8 * SS)))
    out = big.resize((W, H), Image.LANCZOS); out.save(os.path.join(PINS, key + '.webp'), quality=92, method=6)
    print(area, key, 'ok', out.size)
