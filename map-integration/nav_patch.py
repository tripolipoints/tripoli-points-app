# -*- coding: utf-8 -*-
"""Map step-back navigation patch (V3.4 candidate), applied on top of Production V3.3 index.html.
Changes: (1) the map's empty-tap handler calls tpnBgTap (one step back) instead of clearMapSel (full reset to zoom 13);
(2) the earlier cluster-only empty-tap listener is removed (now part of tpnBgTap); (3) zoomMap becomes re-assignable so «−»
can follow the steps; (4) tp_nav.js is added after zoomMap; (5) tpArtSync keeps the step history consistent with the zoom.
Usage: python3 nav_patch.py <index.html>"""
import os, sys
P = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__)); s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:90], c); s = s.replace(a, b)
R("on(el,'click',e=>{if(t.moved||e.target.closest('.mchip,.zb,.pn,#rtchip,#tpRouteActions'))return;if(S.sel)clearMapSel()});",
  "on(el,'click',e=>{if(t.moved||e.target.closest('.mchip,.zb,.pn,#rtchip,#tpRouteActions'))return;tpnBgTap(e)}); // V3.4: one step back, never a full reset")
R("  if(!t._tpBg){t._tpBg=1;t.el.addEventListener('click',tpaBgTap);t.off.push(()=>t.el.removeEventListener('click',tpaBgTap))}\n", "  tpnSync(t);\n")
a = s.index("const zoomMap=d=>"); b = s.index("\n", a)
line = s[a:b]
s = s[:a] + "let zoomMap=" + line[len("const zoomMap="):] + "\n" + open(os.path.join(HERE, 'tp_nav.js'), encoding='utf-8').read() + s[b:]
open(P, 'w', encoding='utf-8').write(s); print('step-back navigation patch applied')
