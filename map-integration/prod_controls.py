# -*- coding: utf-8 -*-
"""Map controls refinement for the Production release V3.2 (display only; no action, data or transaction change).
- Home map: the full-screen button gets exactly the size, corner radius, shadow and spacing of the + / − buttons.
- Full-screen map: the close (X) button matches + / − (same size, radius, right edge, even spacing).
- Full-screen map: a «Tripoli» control (the approved gold Tripoli pill: Poppins lettering + map icon, same action
  resetMapFilter()) at the top-left; on the small home map the same pill already sits in the row above the map.
- The approved Staging control shadow on + / − / X / Tripoli / directions buttons.
Usage: python3 prod_controls.py <index.html>"""
import sys
P = sys.argv[1]; s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:80], c); s = s.replace(a, b)
R("${tp30GoogleNavButton()}",
  "${tp30GoogleNavButton()}<button type=\"button\" class=\"tpCityBtn tpMapCity\" onclick=\"resetMapFilter()\" aria-label=\"Tripoli\"><span>Tripoli</span>${TRIPOLI_MAP_IC}</button>")
CSS = """<style>/* Production V3.2: map controls — one size, one shape, one shadow (approved Staging control shadow) */
:root{--tpCtl:34px;--tpCtlR:13px;--tpCtlGap:12px;--tpCtlSh:0 4px 12px rgba(0,25,65,.32),0 2px 4px rgba(0,25,65,.22),0 0 0 1px rgba(0,25,65,.08);
 --tpCtlShOn:0 1px 4px rgba(0,25,65,.26),0 1px 2px rgba(0,25,65,.18),0 0 0 1px rgba(0,25,65,.08)}
/* home map: + (top 12) − (top 50) full-screen (top 88): 34 px squares, 4 px apart, same right edge */
.rmap:not(.tp23-fullscreen) .tp23-fullscreen-btn{top:88px!important;right:10px!important;width:var(--tpCtl)!important;height:var(--tpCtl)!important;border-radius:var(--tpCtlR)!important;font-size:18px!important;line-height:1!important;padding:0!important}
/* full-screen map: X, +, − stacked 34 px squares with the same right edge and even 12 px gaps */
body > .rmap.tp23-fullscreen .tp23-fullscreen-btn,.rmap.tp23-fullscreen .tp23-fullscreen-btn{top:calc(34px + env(safe-area-inset-top))!important;right:12px!important;width:var(--tpCtl)!important;height:var(--tpCtl)!important;border-radius:var(--tpCtlR)!important;font-size:17px!important;line-height:1!important;padding:0!important}
body > .rmap.tp23-fullscreen .zb,.rmap.tp23-fullscreen .zb{right:12px!important;width:var(--tpCtl)!important;height:var(--tpCtl)!important;border-radius:var(--tpCtlR)!important}
body > .rmap.tp23-fullscreen .zb[style*="top:12px"],.rmap.tp23-fullscreen .zb[style*="top:12px"]{top:calc(80px + env(safe-area-inset-top))!important}
body > .rmap.tp23-fullscreen .zb[style*="top:50px"],.rmap.tp23-fullscreen .zb[style*="top:50px"]{top:calc(126px + env(safe-area-inset-top))!important}
/* «Tripoli» on the full-screen map: the approved gold pill (Poppins lettering + map icon), same height as the controls */
.rmap .tpMapCity{display:none}
.rmap.tp23-fullscreen .tpMapCity{display:flex;position:absolute;z-index:8;top:calc(34px + env(safe-area-inset-top));left:12px;width:auto;height:var(--tpCtl);padding:0 12px 0 13px;font-size:14px}
.rmap.tp23-fullscreen .tpMapCity .ic{width:19px;height:19px}
/* one consistent shadow on every main map control */
.rmap .zb,.rmap .tp23-fullscreen-btn,.rmap .tpMapCity,.rmap .tpRouteBtn{box-shadow:var(--tpCtlSh)!important}
.rmap .tpMapCity{box-shadow:var(--tpCtlSh),inset 0 1px 0 rgba(255,255,255,.45)!important}
.rmap .zb:active,.rmap .tp23-fullscreen-btn:active,.rmap .tpMapCity:active,.rmap .tpRouteBtn:active{transform:translateY(1px);box-shadow:var(--tpCtlShOn)!important}
</style>
</head>"""
R("</head>", CSS)
open(P, 'w', encoding='utf-8').write(s); print('controls refinement applied')
