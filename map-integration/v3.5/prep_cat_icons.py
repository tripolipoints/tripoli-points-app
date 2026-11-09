# -*- coding: utf-8 -*-
"""Prepare the 102 category images for the inner circle of the miniature gold shop pin.
- Circular photos: cropped inside their own thin gold outline (circle at 92 % of the content) — no new frame is added.
- Images with a gold rim / ribbon / text cut from a board: manual square crop first (MANUAL), then the same circle.
- Transparent-background icons (and small icons on a soft dark glow): the icon is isolated (opaque pixels), enlarged to fill
  ~80 % of the circle and placed on the same ivory used inside the pin (#fbf3e1) — not yellow, no extra frame.
- Light clarity boost for the small size (unsharp mask, +6 % contrast/saturation). Output: 128×128 WebP with a round alpha.
Usage: python3 -I prep_cat_icons.py <src dir with manifest.csv> <out dir>"""
import csv, os, sys
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
SRC, OUT = sys.argv[1:3]; os.makedirs(OUT, exist_ok=True)
N = 128; IVORY = (251, 243, 225, 255)
MANUAL = {  # slug: (centre x, centre y, square size) as fractions of the image — removes board rims, ribbons and text
    'accessories': (.37, .40, .66), 'shoes_sport': (.63, .37, .68), 'food': (.55, .45, .72),
    'electrical': (.42, .36, .70), 'beautysupplies': (.38, .28, .56), 'salons': (.48, .22, .44)}
def circle_mask(n, scale=4):
    m = Image.new('L', (n * scale, n * scale), 0); ImageDraw.Draw(m).ellipse((0, 0, n * scale - 1, n * scale - 1), fill=255)
    return m.resize((n, n), Image.LANCZOS)
def finish(im):
    im = im.convert('RGB').resize((N, N), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2))
    im = ImageEnhance.Contrast(im).enhance(1.06); im = ImageEnhance.Color(im).enhance(1.06)
    im = im.convert('RGBA'); im.putalpha(circle_mask(N)); return im
report = []
for row in csv.DictReader(open(os.path.join(SRC, 'manifest.csv'), encoding='utf-8-sig')):
    slug = row['slug']; im = Image.open(os.path.join(SRC, row['filename'])).convert('RGBA'); W, H = im.size
    if slug in MANUAL:
        cx, cy, s = MANUAL[slug]; half = s * W / 2
        im = im.crop((int(cx * W - half), int(cy * H - half), int(cx * W + half), int(cy * H + half))); kind = 'manual crop (rim/ribbon removed)'
        out = finish(im)
    else:
        a = im.getchannel('A'); box = a.point(lambda v: 255 if v > 200 else 0).getbbox()
        sub = im.crop(box); bw, bh = sub.size
        opaque = sum(1 for v in sub.getchannel('A').get_flattened_data() if v > 200) / (bw * bh)
        if opaque > .70 and abs(bw - bh) < .08 * max(bw, bh):           # a full circular photo: keep inside its own outline
            c = .92; dx, dy = bw * (1 - c) / 2, bh * (1 - c) / 2
            out = finish(sub.crop((int(dx), int(dy), int(bw - dx), int(bh - dy)))); kind = 'circle photo'
        else:                                                         # an icon on transparency (or on a soft glow)
            solid = sub.copy(); solid.putalpha(sub.getchannel('A').point(lambda v: 0 if v < 140 else v))
            sb = solid.getchannel('A').getbbox(); solid = solid.crop(sb)
            side = int(max(solid.size) / .80); bg = Image.new('RGBA', (side, side), IVORY)
            bg.alpha_composite(solid, ((side - solid.size[0]) // 2, (side - solid.size[1]) // 2)); out = finish(bg)
            kind = 'icon on ivory' + (' (small icon on glow, enlarged)' if opaque < .2 else '')
    out.save(os.path.join(OUT, slug + '.webp'), quality=86, method=6)
    report.append((slug, row['name_ar'], kind))
csv.writer(open(os.path.join(OUT, 'prep_report.csv'), 'w', encoding='utf-8', newline='')).writerows([('slug', 'name_ar', 'processing')] + report)
print(len(report), 'images ->', OUT)
