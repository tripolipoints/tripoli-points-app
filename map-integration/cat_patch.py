# -*- coding: utf-8 -*-
"""TRIAL (Staging only): category photo inside individual shop pins, one category («سماعات أذن»). Applied on top of V3.4.1.
Usage: python3 cat_patch.py <index.html>"""
import os, sys
P = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__)); s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:80], c); s = s.replace(a, b)
R("function tpnSync(t){", open(os.path.join(HERE, 'tp_catimg.js'), encoding='utf-8').read() + "function tpnSync(t){tpCatDress(t);")
R("</head>", """<style>/* TRIAL v2: category photo inside the individual shop pin — same pin, same size, same gold frame and shine.
   No extra yellow glow or yellow ring, no area-colour (green) ring around the photo; the photo exactly fills the inner circle. */
.rmap.tpv6 .pn.tpCatPin > b{visibility:hidden}
.rmap.tpv6 .pn.tpCatPin .pnring{background:transparent!important;box-shadow:none!important}
.rmap.tpv6 .pn .tpCatImg{position:absolute;left:8.65px;top:4.75px;width:20.5px;height:20.5px;border-radius:50%;object-fit:cover;pointer-events:none;z-index:2;box-shadow:none}
.rmap.tpv6 .pn.tpCatPin.sel,.rmap.tpv6 .pn.tpCatPin.route{filter:drop-shadow(0 2px 3px rgba(50,30,0,.38))}
.rmap.tpv6 .pn.tpCatPin.sel .pnring,.rmap.tpv6 .pn.tpCatPin.route .pnring,.rmap.tpv6 .pn.tpCatPin.sel .tpCatImg,.rmap.tpv6 .pn.tpCatPin.route .tpCatImg{box-shadow:none!important}
</style>
</head>""")
open(P, 'w', encoding='utf-8').write(s); print('category-photo trial applied')
