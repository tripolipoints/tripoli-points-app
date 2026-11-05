# -*- coding: utf-8 -*-
"""Integrate the approved artistic gold map (preview v10) into the real app index.html (staging integration branch).
Same code changes as the approved preview (build.py + build6..10), WITHOUT the preview-only parts
(offline database stub, dummy merchants, test panel, auto test visitor, embedded base64 tiles).
Tiles and artwork become static files under assets/map/ (copied separately).
Usage: python3 integrate.py <index.html in/out> <tiles dir> <art_geo.json> <baked dir>"""
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
IDX, TILES, GEO, BAKED = sys.argv[1:5]
src = open(IDX, encoding='utf-8').read()

def R(a, b, n=1):
    global src
    c = src.count(a); assert c == n, (a[:90], c); src = src.replace(a, b)

# ---- 1) painted tiles as static files, with a compact coverage index (per zoom/column: y ranges) ----
cov = {}
for z in sorted(os.listdir(TILES)):
    if not z.isdigit(): continue
    for x in os.listdir(os.path.join(TILES, z)):
        ys = sorted(int(f[:-5]) for f in os.listdir(os.path.join(TILES, z, x)) if f.endswith('.webp'))
        rng = []
        for y in ys:
            if rng and y == rng[-1][1] + 1: rng[-1][1] = y
            else: rng.append([y, y])
        cov.setdefault(z, {})[x] = rng
cov_js = json.dumps(cov, separators=(',', ':'))
a = src.index("const T_STREET=["); b = src.index("];", a) + 2
src = src[:a] + "const T_STREET=['tp://{z}/{x}/{y}']; /* Tripoli Points painted map (OpenStreetMap data) — assets/map/tiles */" + src[b:]
R("const tileUrl=(u,z,x,y,n)=>u.replace(",
  """/* ===== Tripoli Points painted map tiles (static files assets/map/tiles/z/x/y.webp; © OpenStreetMap contributors, ODbL) ===== */
const TP_TILE_BASE='assets/map/tiles/',TP_COV=%s;
const tpHas=(z,x,y)=>{const c=TP_COV[z],r=c&&c[x];if(!r)return false;for(const [a,b] of r)if(y>=a&&y<=b)return true;return false};
const tpUrl=(z,x,y)=>TP_TILE_BASE+z+'/'+x+'/'+y+'.webp';
const TP_IMG={},TP_PEND={},TP_HI={},TP_PLAIN='data:image/svg+xml,'+encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256"><rect width="256" height="256" fill="#2c8fd6"/></svg>');
// sharp tiles on high-density screens: a 512 px tile made from the four painted children one zoom deeper (same geometry)
function tpHi(z,x,y){const ks=[[0,0],[1,0],[0,1],[1,1]].map(([a,b])=>[z+1,2*x+a,2*y+b]);if(!ks.every(k=>tpHas(...k)))return null;
  const key=z+'/'+x+'/'+y;if(TP_HI[key]&&TP_HI[key]!=='p')return TP_HI[key];
  if(!TP_HI[key]){TP_HI[key]='p';Promise.all(ks.map(k=>new Promise(r=>{const im=new Image();im.onload=()=>r(im);im.onerror=()=>r(null);im.src=tpUrl(...k)}))).then(ims=>{
    if(ims.some(i=>!i)){delete TP_HI[key];return}const c=document.createElement('canvas');c.width=c.height=512;const g=c.getContext('2d');
    ims.forEach((im,i)=>g.drawImage(im,(i%%2)*256,(i>>1)*256));TP_HI[key]=c.toDataURL('image/jpeg',.88);
    if(TM){const e=TM.tiles['s'+key];if(e&&e.src!==TP_HI[key])e.src=TP_HI[key]}})}
  return null}
function tpTile(z,x,y,n){x=((x%%n)+n)%%n;if(tpHas(z,x,y))return((window.devicePixelRatio||1)>1.4&&tpHi(z,x,y))||tpUrl(z,x,y);
  // no painted tile at this zoom here: magnify the nearest painted ancestor (same geometry, only softer)
  for(let dz=1;dz<=8&&z-dz>=12;dz++){const az=z-dz,ax=x>>dz,ay=y>>dz,ak=az+'/'+ax+'/'+ay;if(!tpHas(az,ax,ay))continue;
    let im=TP_IMG[ak];if(!im){im=TP_IMG[ak]=new Image();im.src=tpUrl(az,ax,ay)}
    if(!(im.complete&&im.naturalWidth)){(TP_PEND[ak]=TP_PEND[ak]||[]).push([z,x,y]);im.onload=()=>{const l=TP_PEND[ak]||[];delete TP_PEND[ak];
      if(TM)l.forEach(([zz,xx,yy])=>{const e=TM.tiles['s'+zz+'/'+xx+'/'+yy];if(e)e.src=tpTile(zz,xx,yy,2**zz)})};return TP_PLAIN}
    const c=document.createElement('canvas');c.width=c.height=256;const g=c.getContext('2d'),s=256>>dz,ox=(x-(ax<<dz))*s,oy=(y-(ay<<dz))*s;
    g.imageSmoothingQuality='high';g.drawImage(im,ox,oy,s,s,0,0,256,256);return c.toDataURL('image/jpeg',.86)}
  return TP_PLAIN}
const tileUrl=(u,z,x,y,n)=>u.startsWith('tp://')?tpTile(z,x,y,n):u.replace(""" % cov_js)
R('<div class="attr">Esri, HERE, Garmin, OpenStreetMap contributors</div>', '<div class="attr">© OpenStreetMap contributors · Tripoli Points · Esri (صور القمر الصناعي)</div>', 4)

# ---- 2) approved zoom range 13–20 ----
R("const CLUSTER_MAXZ=21;", "const CLUSTER_MAXZ=20; /* approved maximum zoom */")
R("zt=Math.max(8,Math.min(sat?17:19,", "zt=Math.max(8,Math.min(sat?17:20,")
R("function zoomAt(px,py,nz){const t=TM;if(!t)return;nz=Math.max(10,", "function zoomAt(px,py,nz){const t=TM;if(!t)return;nz=Math.max(TP_ZMIN,")
R("if(TM)flyTo(TM.lat,TM.lng,Math.max(10,Math.min(PIN_ZOOM_HI,TM.z+d)),300)}", "if(TM)flyTo(TM.lat,TM.lng,Math.max(TP_ZMIN,Math.min(PIN_ZOOM_HI,TM.z+d)),300)}")
R("  z=Math.max(10,Math.min(zCap||15,z));return{lat:(a+b)/2,lng:(c+d)/2,z}}", "  z=Math.max(TP_ZMIN,Math.min(zCap||15,z));return{lat:(a+b)/2,lng:(c+d)/2,z}}")
R("  return Math.max(10,Math.min(prefZ,maxZforFit))}", "  return Math.max(TP_ZMIN,Math.min(prefZ,maxZforFit))}")
R("if(t.pick)pickSet(v.lat,v.lng);t.lat=v.lat;t.lng=v.lng;t.z=v.z;", "if(t.pick)pickSet(v.lat,v.lng);t.lat=v.lat;t.lng=v.lng;t.z=Math.max(TP_ZMIN,v.z);")
R("function flyTo(lat,lng,z,ms){const t=TM;if(!t)return;", "function flyTo(lat,lng,z,ms){const t=TM;if(!t)return;z=Math.max(TP_ZMIN,z);")
R("const PIN_ZOOM_LO=12,", "const TP_ZMIN=13; /* approved minimum zoom: the artistic Tripoli overview */\nconst PIN_ZOOM_LO=12,")
R("const f=fitPts(allActiveMerchants().map(llOf),44);f.z+=TRIPOLI_ZOOM_BOOST;return f", "const f=fitPts(allActiveMerchants().map(llOf),44);f.z=TP_ZMIN;return f")
R("if(p.length){const v=fitPts(p,44);flyTo(v.lat,v.lng,v.z+(zBoost||0),600)}", "if(p.length){const v=fitPts(p,44);flyTo(v.lat,v.lng,zBoost===TRIPOLI_ZOOM_BOOST?TP_ZMIN:v.z+(zBoost||0),600)}")
R("if(!S.mv){const f=fitPts(allActiveMerchants().map(llOf),44);t.lat=f.lat;t.lng=f.lng;t.z=f.z+TRIPOLI_ZOOM_BOOST}", "if(!S.mv){const f=fitPts(allActiveMerchants().map(llOf),44);t.lat=f.lat;t.lng=f.lng;t.z=TP_ZMIN}")

# ---- 3) zoom 19–20: shops at their own positions; same-spot shops share one pin with a choice list (approved v2) ----
R("  t.pinLayer.innerHTML='';\n  if(S.route&&S.route.id){const selected=t.pins.find(p=>p.id===S.route.id);if(selected)drawSingle(selected);return}",
  "  t.pinLayer.innerHTML='';\n  if(S.route&&S.route.id){const selected=t.pins.find(p=>p.id===S.route.id);if(selected)drawSingle(selected);return}\n"
  "  if(t.z>=TP_DETAIL_Z-.05){tpDrawDetail(t,X,Y,pinHtml);if(labelZoomOk||S.sel)resolveLabelCollisions(t);return}")
bsrc = open(os.path.join(HERE, 'build.py'), encoding='utf-8').read()
det = bsrc[bsrc.index('R("function resolveLabelCollisions(t){", r"""') + len('R("function resolveLabelCollisions(t){", r"""'):bsrc.index('function resolveLabelCollisions(t){""")')]
R("function resolveLabelCollisions(t){", det + "function resolveLabelCollisions(t){")
pcss = bsrc[bsrc.index('.pn .tpCount,.pn .tpCount *{all:unset}'):bsrc.index('</style>\n<div id="tpTest"')].replace('%%', '%')

# ---- 4) artistic opening view + gold pin family (approved v10) ----
names = json.load(open(os.path.join(BAKED, 'names.json'), encoding='utf-8'))
g = json.load(open(GEO, encoding='utf-8'))
TPA = dict(m=g['m'], w=g['w'], h=g['h'], pins=g['pins'])
assets = ('<script>/* Tripoli Points artistic map: artwork (copy of the approved Treasures of Tripoli map) and gold pins */\n'
          'const TPA=%s;const TPA_IMG="assets/map/art.webp";const GP_R=%s;</script>'
          % (json.dumps(TPA, ensure_ascii=False), json.dumps({n: 'assets/map/pins/r%d.webp' % i for i, n in enumerate(names)}, ensure_ascii=False)))
R('<script>\n// ===== الاتصال بقاعدة البيانات (Supabase) =====', assets + '\n<script>\n// ===== الاتصال بقاعدة البيانات (Supabase) =====')
R("  if(t.pinLayer)drawPinClusters(t,X,Y);\n}\nfunction setMapStyle",
  "  if(t.pinLayer)drawPinClusters(t,X,Y);\n  tpArtSync(t,X,Y);\n}\n" + open(os.path.join(HERE, 'tp9_overview.js'), encoding='utf-8').read() + "\nfunction setMapStyle")
css = (open(os.path.join(HERE, 'tp10_overview.css'), encoding='utf-8').read()
       .replace('url(__PINC__)', "url('assets/map/pins/c.webp')").replace('url(__PINM2__)', "url('assets/map/pins/m2.webp')"))
assert '__PIN' not in css
R('</head>', '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Amiri:wght@700&display=swap">\n<style>/* Tripoli Points map: zoom 19–20 shared-spot list */\n' + pcss + '</style>\n<style>' + css + '</style>\n</head>')
R('<div class="pn cluster ${isOpen?\'open\':\'\'}" style="--c:${clr}">', '<div class="pn cluster ${isOpen?\'open\':\'\'}" style="--c:${clr}" data-area="${esc(areaName)}">')
R('<div class="pn cluster split ${isOpen?\'open\':\'\'}" style="--c:${AREA_COLORS[gr.area]||\'var(--navy)\'}">', '<div class="pn cluster split ${isOpen?\'open\':\'\'}" style="--c:${AREA_COLORS[gr.area]||\'var(--navy)\'}" data-area="${esc(gr.area)}">')
R("const CLUSTER_SPLIT_GAP=22;", "const CLUSTER_SPLIT_GAP=56; /* wider gold pins */")

assert 'lqbhfkowqaqlgcrdybvv' not in src or src.count('lqbhfkowqaqlgcrdybvv') == open(IDX, encoding='utf-8').read().count('lqbhfkowqaqlgcrdybvv')
open(IDX, 'w', encoding='utf-8').write(src)
print('index.html', os.path.getsize(IDX) // 1024, 'KB; coverage zooms', sorted(cov, key=int), 'tiles', sum(sum(b - a + 1 for a, b in r) for c in cov.values() for r in c.values()))
