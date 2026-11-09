# -*- coding: utf-8 -*-
"""V3.5 final: the user's 21 clean category images (Tripoli_Points_21_Categories_CLEAN_FOR_CLAUDE.zip) replace the old ZIP images.
Each 320 px circle is cropped to its inner 90 % (drops the light outer vignette, so no second rim shows inside the gold pin),
lightly sharpened and saved as a 128 px round WebP, same as the 77 board photos.
Usage: python3 -I add21.py <unzipped dir with CATEGORY_MAPPING.csv> <cat images dir>"""
import csv, os, sys
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
SRC, OUT = sys.argv[1:3]; N = 128
def mask(n, s=4):
    m = Image.new('L', (n * s, n * s), 0); ImageDraw.Draw(m).ellipse((0, 0, n * s - 1, n * s - 1), fill=255); return m.resize((n, n), Image.LANCZOS)
rows = list(csv.DictReader(open(os.path.join(SRC, 'CATEGORY_MAPPING.csv'), encoding='utf-8-sig')))
for r in rows:
    im = Image.open(os.path.join(SRC, r['image_path'])).convert('RGBA'); bb = im.getchannel('A').getbbox()
    cx, cy = (bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2; rad = (bb[2] - bb[0]) / 2 * .90
    bg = Image.new('RGBA', im.size, (250, 244, 234, 255)); bg.alpha_composite(im)
    t = bg.crop((round(cx - rad), round(cy - rad), round(cx + rad), round(cy + rad))).convert('RGB').resize((N, N), Image.LANCZOS)
    t = t.filter(ImageFilter.UnsharpMask(radius=1.0, percent=45, threshold=2)); t = ImageEnhance.Contrast(t).enhance(1.04)
    t = t.convert('RGBA'); t.putalpha(mask(N)); t.save(os.path.join(OUT, r['slug'] + '.webp'), quality=88, method=6)
print(len(rows), 'images written')
