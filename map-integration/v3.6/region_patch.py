# -*- coding: utf-8 -*-
"""V3.6 (Staging): regional pin name/count restyled to the «أبي سمراء» reference — Tajawal ExtraBold, dark brown, centred in the
beige ribbon (lower part of the medallion); the count sits under the name in the same ribbon. Only the text rules of .gp change:
the pin box (--w 104 px, 360×394 art), its anchor and the tip point are untouched. Usage: python3 region_patch.py <index.html>"""
import sys
P = sys.argv[1]; s = open(P, encoding='utf-8').read()
def R(a, b):
    global s
    assert s.count(a) == 1, a[:60]; s = s.replace(a, b)
R(""".gp .gpN{position:absolute;left:15%;width:68.4%;top:19.6%;height:11.4%;display:flex;align-items:center;justify-content:center;white-space:nowrap;
 font:700 calc(var(--w) * .092)/1 var(--gpFont);color:#341802;text-shadow:0 1px 0 rgba(255,246,222,.95),0 -1px 1px rgba(90,54,8,.25);direction:rtl}
.gp .gpK{position:absolute;left:34%;width:30.4%;top:36.6%;height:7.4%;display:flex;align-items:center;justify-content:center;white-space:nowrap;font-style:normal;
 font:700 calc(var(--w) * .07)/1 var(--gpFont);color:#fff3d6;direction:rtl}
.gp .gpK.two{font-size:calc(var(--w) * .062)}""",
""".gp .gpN{position:absolute;left:31.5%;width:35.6%;top:47.55%;height:8.6%;display:flex;align-items:center;justify-content:center;white-space:nowrap;
 font:800 calc(var(--w) * .088)/1.25 'Tajawal',var(--gpFont);color:#2a1708;text-shadow:0 1px 0 rgba(255,250,236,.9);direction:rtl}
.gp .gpK{position:absolute;left:36.4%;width:25.8%;top:54.64%;height:6%;display:flex;align-items:center;justify-content:center;white-space:nowrap;font-style:normal;
 font:700 calc(var(--w) * .064)/1.25 'Tajawal',var(--gpFont);color:#6a4313;direction:rtl}
.gp .gpK.two{font-size:calc(var(--w) * .062)}""")
# the name and count always fit inside the ribbon, whatever font the phone ends up using (shrinks only when needed)
A = "L.querySelectorAll('.tpBigBtn').forEach(b=>b.onclick=e=>{e.stopPropagation();if(TM&&TM.moved)return;tpaBigTap(b.dataset.n)})}"
R(A, A[:-1] + ";tpGpFit(L)}")
R("function gpRegionalH(n,c){", """function tpGpFit(L){const go=()=>L.querySelectorAll('.gp .gpN,.gp .gpK').forEach(e=>{if(!e.clientWidth)return;e.style.fontSize='';
    const rg=document.createRange(),tw=()=>{rg.selectNodeContents(e);return rg.getBoundingClientRect().width},bw=e.getBoundingClientRect().width*.94;
    let f=parseFloat(getComputedStyle(e).fontSize),n=0;while(tw()>bw&&f>5&&n++<60){f-=.25;e.style.fontSize=f+'px'}});
  go();requestAnimationFrame(go);if(document.fonts&&document.fonts.ready)document.fonts.ready.then(go)}
function gpRegionalH(n,c){""")
R(".gp .gpK.two{font-size:calc(var(--w) * .062)}", ".gp .gpK.two{font-size:calc(var(--w) * .062)}\n.gp .gpN,.gp .gpK{overflow:hidden}")
open(P, 'w', encoding='utf-8').write(s); print('regional pin text restyled')
