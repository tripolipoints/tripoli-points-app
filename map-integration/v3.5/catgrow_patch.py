# -*- coding: utf-8 -*-
"""V3.5 (Staging): category images inside individual shop pins + progressive enlargement for all shop pins.
Applied on top of V3.4.1 (step-back). Usage: python3 catgrow_patch.py <index.html> <assets/map/cat dir>"""
import os, sys
P, CAT = sys.argv[1:3]; HERE = os.path.dirname(os.path.abspath(__file__)); s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:80], c); s = s.replace(a, b)
slugs = sorted(f[:-5] for f in os.listdir(CAT) if f.endswith('.webp'))
js = open(os.path.join(HERE, 'tp_catpins.js'), encoding='utf-8').read().replace('__SLUGS__', ','.join(slugs))
R("function tpnSync(t){", js + "function tpnSync(t){tpCatDress(t);tpGrowDress(t);")
# route framing: reserve the real height (and half-width) of the enlarged destination pin
R("const r=clusterTargetRect(t.el,t.h),PAD_X=40,",
  "const r=clusterTargetRect(t.el,t.h),PAD_X=Math.max(40,Math.round(tpGrowRouteH()*28/33.8/2)+14),")
R("const pv=pinVisualH(17)*PIN_ROUTE_SCALE,aw=t.w-2*PAD_X,", "const pv=tpGrowRouteH()+6,aw=t.w-2*PAD_X,")
# cancelling the route returns the pins to their sizes immediately (before, they changed only on the next map move)
R("function clearRoute(){S.route=null;routeUi()}", "function clearRoute(){const had=!!S.route;S.route=null;routeUi();if(TM)try{if(had)tpGrowRouteCancelled();drawMap()}catch(e){}}")
R("</head>", """<style>/* V3.5: category image inside the individual shop pin — same pin, same gold frame and shine, no extra ring or yellow */
.rmap.tpv6 .pn.tpCatPin > b{visibility:hidden}
.rmap.tpv6 .pn.tpCatPin .pnring{background:transparent!important;box-shadow:none!important}
.rmap.tpv6 .pn .tpCatImg{position:absolute;left:8.65px;top:4.75px;width:20.5px;height:20.5px;border-radius:50%;object-fit:cover;pointer-events:none;z-index:2;box-shadow:none;image-rendering:auto}
.rmap.tpv6 .pn.tpCatPin.sel,.rmap.tpv6 .pn.tpCatPin.route{filter:drop-shadow(0 2px 3px rgba(50,30,0,.38))}
.rmap.tpv6 .pn.tpCatPin.sel .pnring,.rmap.tpv6 .pn.tpCatPin.route .pnring,.rmap.tpv6 .pn.tpCatPin.sel .tpCatImg,.rmap.tpv6 .pn.tpCatPin.route .tpCatImg{box-shadow:none!important}
/* V3.5: progressive enlargement — grows from the tip (transform-origin 50% 100%), above neighbours (z-index set by drawPinClusters) */
.rmap.tpv6 .pn.tpGrow.sel{transform:scale(calc(var(--zs,1) * 1.45))}
.rmap.tpv6 .pn.tpGrow.route{transform:scale(calc(var(--zs,1) * 1.9))}
.rmap.tpv6 .pn.tpGrow.sel~.pnname,.rmap.tpv6 .pn.tpGrow.route~.pnname{top:calc(3px + 6px)}
</style>
</head>""")
open(P, 'w', encoding='utf-8').write(s); print('V3.5 category images + progressive enlargement applied;', len(slugs), 'category images')
