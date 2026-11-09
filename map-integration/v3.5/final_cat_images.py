# -*- coding: utf-8 -*-
"""V3.5 final category images: realistic photos cut from the source boards (picture.rar) wherever the board has that category;
the remaining categories keep the cleaned image from the 102-image ZIP (listed as still needing a realistic photo).
Usage: python3 -I final_cat_images.py <tiles dir> <zip-processed dir> <out dir>"""
import os, sys, csv, shutil
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter
TILES, ZIPD, OUT = sys.argv[1:4]; os.makedirs(OUT, exist_ok=True); N = 128
B = {'A': 'Automotive and Lifestyle Category Icons', 'EG': 'Elegant Gold Fashion Category Pins', 'F1': 'Glossy Gold Food Category Icons-1',
     'HO': 'Glossy Gold Home Essentials Infographic', 'AC': 'Glossy Gold-Marked Accessories Catalog', 'AR': 'Golden Arabic Fashion Collection Icons',
     'BE': 'Golden Beauty and Electronics Category Board', 'FC': 'Golden Icons of Fashion and Cuisine', 'F2': 'Gourmet Market Categories Map-2',
     'L2': 'LAST_2_GROUP_PREVIEW'}
MAP = {  # slug: board tile (row, column counted from the right) — matched to the label printed under the tile on the board
 'carrent': 'A00', 'carparts': 'A01', 'carshowroom': 'A02', 'main_auto': 'A03', 'baby_wear': 'A04',
 'sportswear_men': 'A10', 'insurance': 'A11', 'carservices': 'A12', 'fuel': 'A13', 'carrental': 'A14',
 'sportswear': 'EG01', 'kidswear': 'EG02', 'womenswear': 'EG03', 'menswear': 'EG04',
 'accessories': 'EG10', 'handbags': 'EG11', 'shoes_kids': 'EG12', 'shoes_women': 'EG13', 'shoes_men': 'EG14',
 'nuts': 'F100', 'oriental': 'F101', 'bakery': 'F102', 'chocolate': 'F103', 'sweets': 'F104',
 'cafe': 'F110', 'vegetables': 'F111', 'naturaldrinks': 'F112', 'drinks': 'F113', 'grocery': 'F114',
 'food': 'F201',                                   # restaurants: the second board's mezze plate (oriental keeps the first board's)
 'curtains': 'HO00', 'carpets': 'HO01', 'linens': 'HO02', 'furniture': 'HO03', 'main_home': 'HO04', 'home': 'HO04',
 'antiques': 'HO10', 'homeappliances': 'HO11', 'decor': 'HO12', 'homeware': 'HO13', 'chandeliers': 'HO14',
 'wallets': 'AC00', 'belts': 'AC01', 'bags_travel': 'AC02', 'bags_school': 'AC03', 'bags_hand': 'AC04',
 'main_electronics': 'AC11', 'mobile': 'AC12', 'electronics': 'AC13', 'fashion_accessories': 'AC14',
 'main_jewelry': 'AR00', 'islamic_wear': 'AR01', 'hijab': 'AR02', 'jalabiyas': 'AR03', 'abayas': 'AR04',
 'girls_wear': 'AR10', 'boys_wear': 'AR11', 'glasses': 'AR12', 'watches': 'AR13', 'jewelry': 'AR14',
 'main_beauty': 'BE00', 'electrical': 'BE01', 'ac': 'BE02', 'homeelec': 'BE03', 'electronics_acc': 'BE04',
 'beautycenters': 'BE10', 'salons': 'BE11', 'beautysupplies': 'BE12', 'beauty': 'BE13', 'perfume': 'BE14',
 'sewing_supplies': 'FC00', 'fabrics': 'FC01', 'fashion': 'FC02', 'main_fashion': 'FC03', 'main_food': 'FC10',
 'wedding_dresses': 'L200', 'earphones': 'L201'}
DROP = {'hospitals': 'identical to clinics', 'main_health': 'identical to pharma',
        'sportswear_women': 'red dress, not sportswear', 'sportswear_kids': 'kidswear picture, not sportswear'}
def circle_mask(n, scale=4):
    m = Image.new('L', (n * scale, n * scale), 0); ImageDraw.Draw(m).ellipse((0, 0, n * scale - 1, n * scale - 1), fill=255)
    return m.resize((n, n), Image.LANCZOS)
def finish(im):
    im = im.convert('RGB').resize((N, N), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=1.1, percent=55, threshold=2))
    im = ImageEnhance.Contrast(im).enhance(1.05); im = ImageEnhance.Color(im).enhance(1.05)
    im = im.convert('RGBA'); im.putalpha(circle_mask(N)); return im
rows = list(csv.DictReader(open(os.path.join(ZIPD, 'prep_report.csv'), encoding='utf-8')))
used = {}; rep = []
for r in rows:
    slug = r['slug']; t = MAP.get(slug)
    if t:
        key = t[:-2]; f = os.path.join(TILES, f"{B[key]}_{t[-2:]}.png")
        finish(Image.open(f)).save(os.path.join(OUT, slug + '.webp'), quality=88, method=6)
        used.setdefault(t, []).append(slug); rep.append((slug, r['name_ar'], 'realistic photo (board ' + t + ')'))
    elif slug in DROP:
        rep.append((slug, r['name_ar'], 'no image yet (duplicate/wrong subject removed) — shows parent image or category icon'))
    else:
        shutil.copy(os.path.join(ZIPD, slug + '.webp'), os.path.join(OUT, slug + '.webp'))
        rep.append((slug, r['name_ar'], 'ZIP image kept — needs a realistic photo'))
csv.writer(open(os.path.join(OUT, 'final_report.csv'), 'w', encoding='utf-8', newline='')).writerows([('slug', 'name_ar', 'source')] + rep)
print('realistic', sum(1 for x in rep if x[2].startswith('real')), '| kept', sum(1 for x in rep if 'kept' in x[2]))
print('shared tiles', {k: v for k, v in used.items() if len(v) > 1})
print('dropped:', ' '.join(DROP)); print('kept:', ' '.join(x[0] for x in rep if 'kept' in x[2]))
