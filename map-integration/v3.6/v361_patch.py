# -*- coding: utf-8 -*-
"""V3.6.1 (Staging), on top of V3.6:
1) «التل» regional pin raised a little on the opening (zoom 13) artwork so it no longer covers the «طرابلس» label
   (art-space anchor only: v 1036 → 973; its real area coordinates are unchanged).
2) Free hand zoom on the opening map: a pinch / ctrl-wheel / double-tap zoom started on the regional overview keeps the six
   regional pins (they grow with the zoom, up to ×1.45) and the map stays free to explore — it no longer jumps to the cluster
   stage. Tapping a regional pin goes into the usual stages; zooming back out to the overview, a step back, or any programmatic
   move ends free mode. «+»/«−» keep free mode while it is on.
3) «−» and «✕» map buttons: glyphs replaced by drawn marks centred in their boxes (same size/weight as the «+» icon).
Usage: python3 v361_patch.py <index.html>"""
import sys
P = sys.argv[1]; s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:80], c); s = s.replace(a, b)
# 1) Tell art anchor
R('["التل", 1045, 1036]', '["التل", 1045, 973]')
# 2) free hand zoom
R("function zoomAt(px,py,nz){const t=TM;if(!t)return;nz=Math.max(TP_ZMIN,Math.min(PIN_ZOOM_HI,nz));",
  "function zoomAt(px,py,nz){const t=TM;if(!t)return;nz=Math.max(TP_ZMIN,Math.min(PIN_ZOOM_HI,nz));tpFreeMark(t,nz);")
R("function flyTo(lat,lng,z,ms){const t=TM;if(!t)return;", "function flyTo(lat,lng,z,ms){const t=TM;if(!t)return;if(!t._tpKeepFree)t._tpFree=false;t._tpReqAt=performance.now();")
R("const hand=tpaSm((t.z-13.85)/.2),pa=busy?0:1-hand,ca=busy?1:hand;",
  "if(t._tpFree&&t.z<=13.08)t._tpFree=false;const fr=!!t._tpFree&&!busy;\n  const hand=tpaSm((t.z-13.85)/.2),pa=busy?0:(fr?1:1-hand),ca=busy?1:(fr?0:hand);")
R("const g=tpaSm((t.z-13.05)/.8),bs=tpaBigScale(t.z);", "const g=tpaSm((t.z-13.05)/.8),bs=fr?tpaFreeScale(t.z):tpaBigScale(t.z);")
R("function tpaBigTap(n){const t=TM;if(!t)return;", "function tpaBigTap(n){const t=TM;if(!t)return;const fz=!!t._tpFree;t._tpFree=false;")
R("cancelAnimationFrame(t.anim);clusterCenterView(ps.map(p=>({lat:p.lat,lng:p.lng})),Math.min(CLUSTER_MAXZ,t.z+3),650)}",
  "cancelAnimationFrame(t.anim);clusterCenterView(ps.map(p=>({lat:p.lat,lng:p.lng})),Math.min(CLUSTER_MAXZ,(fz?13:t.z)+3),650)}")
R("function tpnSync(t){", """/* V3.6.1: free hand zoom on the opening (regional) map */
function tpaFreeScale(z){return +Math.min(1.45,1+.3*Math.max(0,z-13)).toFixed(3)}
function tpFreeAtRoot(){return !TPN.stack.length&&!S.sel&&!(S.route&&S.route.id)&&!S._mapOpenGroup&&S.mapStyle!=='sat'}
function tpFreeMark(t,nz){if(t.pick)return;if(nz<=13.08){t._tpFree=false;return}
  if(!t._tpFree&&nz>t.z&&t.z<13.85&&tpFreeAtRoot())t._tpFree=true}
(function(){const f=zoomMap;zoomMap=function(d){const t=TM;if(t&&t._tpFree){t._tpKeepFree=1;try{return f(d)}finally{t._tpKeepFree=0}}return f(d)}})();
(function(){const f=tpStepBack;tpStepBack=function(){const r=f.apply(this,arguments),t=TM;
  if(t&&!t.pick&&tpFreeAtRoot()&&((t.req&&performance.now()-(t._tpReqAt||0)<80)?t.req.z:t.z)>13.1)t._tpFree=true;return r}})();
function tpnSync(t){""")
# 3) centred «−» and «✕»
R("</head>", """<style>/* V3.6.1: «−» and «✕» drawn as centred marks (same size and weight as the «+» icon) */
.zb[aria-label="تصغير"]{font-size:0!important}
.zb[aria-label="تصغير"]::before{content:"";display:block;width:9.75px;height:1.95px;border-radius:2px;background:currentColor}
.rmap.tp23-fullscreen .tp23-fullscreen-btn{font-size:0!important}
.rmap.tp23-fullscreen .tp23-fullscreen-btn::before,.rmap.tp23-fullscreen .tp23-fullscreen-btn::after{content:"";position:absolute;left:50%;top:50%;width:15px;height:2.3px;border-radius:2px;background:currentColor;transform:translate(-50%,-50%) rotate(45deg)}
.rmap.tp23-fullscreen .tp23-fullscreen-btn::after{transform:translate(-50%,-50%) rotate(-45deg)}
</style>
</head>""")
open(P, 'w', encoding='utf-8').write(s); print('V3.6.1 patch applied')
