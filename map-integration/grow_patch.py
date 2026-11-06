# -*- coding: utf-8 -*-
"""TRIAL (Staging only): pin-size comparison (?pindemo=1). Applied on top of the earbuds trial v2.
Usage: python3 grow_patch.py <index.html>"""
import os, sys
P = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__)); s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:80], c); s = s.replace(a, b)
R("function tpnSync(t){tpCatDress(t);", open(os.path.join(HERE, 'tp_pindemo.js'), encoding='utf-8').read() + "function tpnSync(t){tpCatDress(t);tpGrowDress(t);")
R("</head>", """<style>/* TRIAL: group A progressive enlargement — same pin, grows from its tip; group B and all other shops unchanged */
.rmap.tpv6 .pn.tpGrow.sel{transform:scale(calc(var(--zs,1) * 1.45))}
.rmap.tpv6 .pn.tpGrow.route{transform:scale(calc(var(--zs,1) * 1.9))}
.rmap.tpv6 .pn.tpGrow.sel~.pnname,.rmap.tpv6 .pn.tpGrow.route~.pnname{top:calc(3px + 6px)}
</style>
</head>""")
open(P, 'w', encoding='utf-8').write(s); print('pin-size comparison trial applied')
