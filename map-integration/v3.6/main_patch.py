# -*- coding: utf-8 -*-
"""Map V3.6.1 → main (Production code line). Applied on top of the approved Staging build (feature/region-pins-v3.6.1):
1) Staging-only slug tolerance removed (stg_/test_/demo_ prefixes).
2) The six regional pin images get content-hashed file names (r0.<sha256-10>.webp …): _headers caches /assets/* for a year as
   immutable, and these six files changed content under the same name — phones that opened V3.3 would otherwise keep the old art.
3) Map images can be served from Supabase Storage (public bucket «map-assets», folder v3.6.1/) — switched on automatically and
   only when that folder's manifest.json is published with the matching version; until then, and for any single image that
   fails, the app uses its own local files exactly as before. No database table or policy is involved.
Usage: python3 main_patch.py <repo dir>"""
import hashlib, json, os, sys
D = sys.argv[1]; P = os.path.join(D, 'index.html'); s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:80], c); s = s.replace(a, b)
# 1) no Staging slug tolerance in Production
R("const b=String(slug).toLowerCase().replace(/^(stg|test|demo)_/,'');   // Staging test slugs: stg_cafe → cafe", "const b=String(slug).toLowerCase();")
# 2) hashed regional pin names
pins = {}
for i in range(6):
    src = os.path.join(D, f'assets/map/pins/r{i}.webp'); h = hashlib.sha256(open(src, 'rb').read()).hexdigest()[:10]
    dst = f'assets/map/pins/r{i}.{h}.webp'; os.rename(src, os.path.join(D, dst)); pins[f'assets/map/pins/r{i}.webp'] = dst
    R(f'"assets/map/pins/r{i}.webp"', f'"{dst}"')
# 3) optional Supabase Storage source with local fallback
R("function gpRegionalH(n,c){const k=String(c).length>1?' two':'';return `<span class=\"gp\" style=\"--w:${GP_RW}px\"><img src=\"${GP_R[n]||GP_R['التل']}\" alt=\"\" draggable=\"false\">",
  "function gpRegionalH(n,c){const k=String(c).length>1?' two':'',lo=GP_R[n]||GP_R['التل'];return `<span class=\"gp\" style=\"--w:${GP_RW}px\"><img src=\"${tpMapSrc(lo)}\" data-lo=\"${lo}\" onerror=\"tpMapImgFail(this)\" alt=\"\" draggable=\"false\">")
R("const m=M(e.dataset.id),logo=m&&typeof safeLogoUrl==='function'?safeLogoUrl(m.logo):'',cat=tpCatImgOf(m),src=logo||cat;",
  "const m=M(e.dataset.id),logo=m&&typeof safeLogoUrl==='function'?safeLogoUrl(m.logo):'',catLo=tpCatImgOf(m),cat=catLo&&tpMapSrc(catLo),src=logo||cat;")
R("im.onerror=()=>{if(logo&&cat&&im.src.indexOf(cat)<0){im.classList.remove('tpLogo');im.src=cat;return}im.remove();e.classList.remove('tpCatPin')};",
  "im.onerror=()=>{if(logo&&cat&&im.src.indexOf(cat)<0){im.classList.remove('tpLogo');im.src=cat;return}\n      if(catLo&&cat!==catLo&&im.src.indexOf(catLo)<0){im.classList.remove('tpLogo');im.src=catLo;return}im.remove();e.classList.remove('tpCatPin')};")
R("function tpCatImgOf(m){", """/* Map images from Supabase Storage (public bucket map-assets, folder v3.6.1/). Off until v3.6.1/manifest.json is published there with
   {"version":"v3.6.1"}; then pins/<rN>.webp and cat/<slug>.webp are read from Storage. Any image that fails falls back to the local file. */
const TP_MAP_REMOTE='https://lqbhfkowqaqlgcrdybvv.supabase.co/storage/v1/object/public/map-assets/v3.6.1/',TP_MAP_VER='v3.6.1';
let TP_MAP_ON=null;                                   // null/false: local files; object: published manifest
function tpMapSrc(lo){if(!TP_MAP_ON||!lo)return lo;let m=lo.match(/^assets\\/map\\/pins\\/(r\\d)\\.[0-9a-f]{10}\\.webp$/);
  if(m)return TP_MAP_ON.pins&&TP_MAP_ON.pins.indexOf(m[1])>=0?TP_MAP_REMOTE+'pins/'+m[1]+'.webp':lo;
  m=lo.match(/^assets\\/map\\/cat\\/([a-z0-9_]+)\\.webp$/);
  return m&&TP_MAP_ON.categories&&TP_MAP_ON.categories.indexOf(m[1])>=0?TP_MAP_REMOTE+'cat/'+m[1]+'.webp':lo}
function tpMapImgFail(i){const lo=i.dataset.lo;if(lo&&i.getAttribute('src')!==lo)i.src=lo}
(function(){if(typeof fetch!=='function')return;let c=null;try{c=new AbortController();setTimeout(()=>c.abort(),4000)}catch(e){}
  fetch(TP_MAP_REMOTE+'manifest.json',{cache:'no-cache',signal:c&&c.signal}).then(r=>r.ok?r.json():null).then(j=>{
    if(!j||j.version!==TP_MAP_VER||!Array.isArray(j.pins)||!Array.isArray(j.categories))return;TP_MAP_ON=j;
    try{const L=document.getElementById('tpBig');if(L)L._sig='';if(typeof TM!=='undefined'&&TM&&TM.pinLayer){TM.pinLayer.querySelectorAll('.tpCatImg').forEach(x=>x.remove());drawMap()}}catch(e){}
  }).catch(()=>{})})();
function tpCatImgOf(m){""")
open(P, 'w', encoding='utf-8').write(s)
json.dump(pins, open(os.path.join(D, 'map-integration', 'v3.6', 'pin_files.json'), 'w'), ensure_ascii=False, indent=1)
print('main patch applied', pins)
