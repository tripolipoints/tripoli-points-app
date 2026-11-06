# -*- coding: utf-8 -*-
"""TRIAL (Staging only): category photo inside individual shop pins, one category («سماعات أذن»). Applied on top of V3.4.1.
Usage: python3 cat_patch.py <index.html>"""
import os, sys
P = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__)); s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:80], c); s = s.replace(a, b)
R("function tpnSync(t){", open(os.path.join(HERE, 'tp_catimg.js'), encoding='utf-8').read() + "function tpnSync(t){tpCatDress(t);")
R("</head>", """<style>/* TRIAL: category photo inside the individual shop pin — same pin, same inner circle size as the icon ring */
.rmap.tpv6 .pn.tpCatPin > b{visibility:hidden}
.rmap.tpv6 .pn .tpCatImg{position:absolute;left:9.2px;top:5.3px;width:19.4px;height:19.4px;border-radius:50%;object-fit:cover;pointer-events:none;z-index:2;
 box-shadow:0 0 0 1.5px color-mix(in srgb,var(--c) 45%,#e8c66e)}
.rmap.tpv6 .pn.sel .tpCatImg,.rmap.tpv6 .pn.route .tpCatImg{box-shadow:0 0 0 2px color-mix(in srgb,var(--c) 65%,#e8c66e),0 0 0 3.4px #ffd23f}
</style>
</head>""")
open(P, 'w', encoding='utf-8').write(s); print('category-photo trial applied')
