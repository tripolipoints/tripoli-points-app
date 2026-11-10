# -*- coding: utf-8 -*-
"""V3.7 (Staging), on top of V3.6.1 (c9931ff). Full-screen map only:
1) «أحياء وشوارع» strip (real photos, RTL swipe + arrows + dots, selected card gold, hide/show) under the «Tripoli» button. Shown only
   on the full-screen map in its base state (regional view, nothing selected, no route); picking a card flies to that street/area and
   records a map step, so «back» returns to the base view and the strip comes back.
2) The app's bottom navigation bar stays visible on the full-screen map (the map ends at its top edge, safe area included);
   tapping a tab closes the full-screen map first, then the tab works as usual.
3) Regional pins on the full-screen map: no shop count (name centred in the ribbon). Small map unchanged.
4) «أبو سمراء» is shown as «أبي سمراء» on the regional pins (display only: area data and merchants' area values unchanged).
5) «شارع قاديشا» coordinates corrected; «جبل محسن» and «سوق حراج» are not in the strip (they stay in the area lists).
6) Base framing: when the full-screen map opens on the regional view, the six pins are centred in the space left between the strip and
   the bottom bar (the previous view is restored when the full-screen map closes).
Usage: python3 v37_patch.py <index.html>"""
import sys, json
P = sys.argv[1]; s = open(P, encoding='utf-8').read()
def R(a, b, n=1):
    global s
    c = s.count(a); assert c == n, (a[:90], c); s = s.replace(a, b)
HOOD = [('شارع مار مارون', 0), ('شارع قاديشا', 1), ('رياض الصلح', 2), ('نقابة الأطباء', 3), ('الزاهرية', 4), ('التبانة', 5),
        ('سوق العريض', 6), ('سوق النحاسين', 7), ('سرايا العتيقة', 8), ('ساحة النجمة', 9), ('ساحة الكورة', 10), ('ساحة النور', 11),
        ('طريق المعرض', 12), ('البحصاص', 13)]
# 5) Qadisha street: point on the street line (owner's coordinates, checked against the OpenStreetMap-based map tiles)
R("['شارع قاديشا',34.441105832364556,35.8337127337377]", "['شارع قاديشا',34.44083330909316,35.83399872214594]")
# 4) display name on the regional pins
R('<b class="gpN">${esc(n)}</b>', '<b class="gpN">${esc(TP_AREA_DISP[n]||n)}</b>')
js = r"""
/* ===== V3.7: full-screen map — «أحياء وشوارع» strip, bottom bar, base framing ===== */
const TP_AREA_DISP={'أبو سمراء':'أبي سمراء'};
const TP_HOOD=__HOOD__.map(([n,i])=>({n,img:'assets/map/hood/p'+String(i).padStart(2,'0')+'.webp'}));
let tpHoodSel=-1,tpHoodHidden=false;
function tpHoodLL(n){const a=(typeof SUBAREAS!=='undefined'?SUBAREAS:[]).find(x=>x[0]===n);return a?{lat:a[1],lng:a[2]}:null}
function tpHoodEl(){const rm=document.getElementById('rmap');if(!rm)return null;let el=rm.querySelector('#tpHood');if(el)return el;
  const cards=TP_HOOD.map((h,i)=>tpHoodLL(h.n)?`<button class="tpHoodCard" type="button" data-i="${i}" onclick="tpHoodPick(${i})"><img src="${h.img}" alt="" draggable="false" loading="lazy"><span>${esc(h.n)}</span></button>`:'').join('');
  rm.insertAdjacentHTML('beforeend',`<div id="tpHood" class="tpHood tpHoodP" dir="rtl" hidden>
    <button class="tpHoodHide" type="button" onclick="tpHoodToggle(true)" aria-label="إخفاء شريط الأحياء والشوارع"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 15l6-6 6 6"/></svg></button>
    <div class="tpHoodBody"><button class="tpHoodArr tpHoodNext" type="button" onclick="tpHoodScroll(1)" aria-label="التالي"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 6l-6 6 6 6"/></svg></button>
    <div class="tpHoodRow">${cards}</div>
    <button class="tpHoodArr tpHoodPrev" type="button" onclick="tpHoodScroll(-1)" aria-label="السابق"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 6l6 6-6 6"/></svg></button></div>
    </div>
    <button id="tpHoodShow" class="tpHoodShow" type="button" hidden onclick="tpHoodToggle(false)" aria-label="إظهار شريط الأحياء والشوارع">أحياء وشوارع<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg></button>`);
  el=rm.querySelector('#tpHood');const row=el.querySelector('.tpHoodRow');row.addEventListener('scroll',()=>tpHoodDots(),{passive:true});
  // swipes on the strip must not move the map underneath
  ['pointerdown','touchstart','mousedown','wheel','click','dblclick'].forEach(ev=>el.addEventListener(ev,e=>e.stopPropagation(),{passive:ev!=='click'}));
  const sh=rm.querySelector('#tpHoodShow');['pointerdown','touchstart','mousedown','click'].forEach(ev=>sh.addEventListener(ev,e=>e.stopPropagation(),{passive:ev!=='click'}));
  return el}
function tpHoodDots(){const el=document.getElementById('tpHood');if(!el||el.hidden)return;const row=el.querySelector('.tpHoodRow'),d=el.querySelector('.tpHoodDots')||{};
  const n=Math.max(1,Math.ceil((row.scrollWidth-4)/Math.max(1,row.clientWidth))),p=Math.min(n-1,Math.round(Math.abs(row.scrollLeft)/Math.max(1,row.scrollWidth-row.clientWidth)*(n-1))||0);
  const h=Array.from({length:n},(_,i)=>`<span class="${i===p?'on':''}"></span>`).join('');if(d.innerHTML!==h)d.innerHTML=h;
  const max=row.scrollWidth-row.clientWidth-2,pos=Math.abs(row.scrollLeft);el.querySelector('.tpHoodNext').disabled=pos>=max-8;el.querySelector('.tpHoodPrev').disabled=pos<=8}
function tpHoodScroll(dir){const row=document.querySelector('#tpHood .tpHoodRow');if(!row)return;row.scrollBy({left:-dir*row.clientWidth*.8,behavior:'smooth'})}
function tpHoodBase(){const t=TM,rm=document.getElementById('rmap');if(!t||!rm||!rm.classList.contains('tp23-fullscreen'))return false;
  return !TPN.stack.length&&!S.sel&&!(S.route&&S.route.id)&&!S._mapOpenGroup&&S.mapStyle!=='sat'&&t.z<13.1&&!t._tpFree}   // free hand zoom = the customer is exploring: strip out of the way
function tpHoodSync(){const rm=document.getElementById('rmap');if(!rm)return;const fs=rm.classList.contains('tp23-fullscreen');
  const el=fs?tpHoodEl():rm.querySelector('#tpHood'),sh=rm.querySelector('#tpHoodShow');if(!el)return;const base=fs&&tpHoodBase();
  if(fs){const cb=rm.querySelector('.tpCityBtn');if(cb&&cb.offsetParent!==null){const v=Math.round(cb.getBoundingClientRect().bottom-rm.getBoundingClientRect().top+9)+'px';if(rm.style.getPropertyValue('--tpHoodTop')!==v)rm.style.setProperty('--tpHoodTop',v)}}
  const show=base&&!tpHoodHidden;if(el.hidden===show){el.hidden=!show;if(show)requestAnimationFrame(tpHoodDots)}
  if(sh){const s2=base&&tpHoodHidden;if(sh.hidden===s2)sh.hidden=!s2}
  el.querySelectorAll('.tpHoodCard').forEach(c=>c.classList.toggle('on',+c.dataset.i===tpHoodSel))}
function tpHoodPick(i){const h=TP_HOOD[i],ll=h&&tpHoodLL(h.n);if(!ll)return;tpHoodSel=i;if(TM)TM._tpFree=false;areaTap(ll.lat,ll.lng,h.n);tpHoodSync()}
function tpHoodToggle(hide){tpHoodHidden=!!hide;tpHoodSync();tpFsFrame()}
// base framing: centre the six regional pins between the strip (or the top controls) and the bottom of the map
const tpMy=(lat,z)=>{const r=lat*Math.PI/180;return (1-Math.log(Math.tan(r)+1/Math.cos(r))/Math.PI)/2*256*Math.pow(2,z)};
const tpMlat=(y,z)=>{const n=Math.PI-2*Math.PI*y/(256*Math.pow(2,z));return 180/Math.PI*Math.atan(.5*(Math.exp(n)-Math.exp(-n)))};
function tpFsFrame(anim){const t=TM,rm=document.getElementById('rmap');if(!t||!rm||!rm.classList.contains('tp23-fullscreen'))return;
  if(!tpHoodBase()||t._tpFree||t.z>13.1)return;const L=document.getElementById('tpBig');if(!L)return;
  const bs=[...L.querySelectorAll('.tpBigBtn')].map(b=>b.getBoundingClientRect()).filter(r=>r.width);if(!bs.length)return;
  const mr=rm.getBoundingClientRect(),top=Math.min(...bs.map(r=>r.top)),bot=Math.max(...bs.map(r=>r.bottom));
  const hood=document.getElementById('tpHood'),hs=document.getElementById('tpHoodShow');let bandTop=mr.top+8;
  [hood&&!hood.hidden?hood:null,hs&&!hs.hidden?hs:null,rm.querySelector('.tpCityBtn'),rm.querySelector('.tp23-fullscreen-btn')].forEach(e=>{if(e&&e.offsetParent!==null){const r=e.getBoundingClientRect();if(r.height)bandTop=Math.max(bandTop,r.bottom+8)}});
  const loc=rm.querySelector('.mchip.mround'),bandBot=(loc&&loc.offsetParent!==null?loc.getBoundingClientRect().top:mr.bottom)-6;
  let dy=(bandTop+bandBot)/2-(top+bot)/2;if(bot-top>bandBot-bandTop)dy=bandTop-top;if(Math.abs(dy)<2)return;
  if(!t._tpFsHome)t._tpFsHome={lat:t.lat,lng:t.lng,z:t.z};const nl=tpMlat(tpMy(t.lat,t.z)-dy,t.z);t._tpFsFramed={lat:nl,lng:t.lng,z:t.z};
  if(anim){t._tpHoodFraming=1;try{flyTo(nl,t.lng,t.z,260)}finally{t._tpHoodFraming=0}}else{t.lat=nl;drawMap()}}
function tpNavH(){const nav=document.querySelector('.nav');if(!nav||getComputedStyle(nav).display==='none')return 0;const r=nav.getBoundingClientRect();return r.height>0&&r.bottom>=innerHeight-2?Math.round(innerHeight-r.top):0}
(function(){const f=toggleMapFullscreen;toggleMapFullscreen=function(force){const rm=document.getElementById('rmap'),was=!!(rm&&rm.classList.contains('tp23-fullscreen'));
  if(was&&TM&&TM._tpFsFramed){const a=TM._tpFsFramed,h=TM._tpFsHome;if(h&&Math.abs(TM.lat-a.lat)<1e-7&&Math.abs(TM.lng-a.lng)<1e-7&&TM.z===a.z){TM.lat=h.lat;TM.lng=h.lng}}
  if(TM){TM._tpFsFramed=null;TM._tpFsHome=null}
  const r=f.apply(this,arguments);const on=!!(rm&&rm.classList.contains('tp23-fullscreen'));
  if(rm){const nh=on?tpNavH():0;rm.classList.toggle('tpNavOn',on&&nh>0);document.body.style.setProperty('--tpNavH',nh+'px')}
  tpFsCloseIcon(rm,on);
  if(on)setTimeout(()=>{tpHoodSync();requestAnimationFrame(()=>requestAnimationFrame(tpFsFrame))},60);else tpHoodSync();return r}})();
function tpFsCloseIcon(rm,on){const b=rm&&rm.querySelector('.tp23-fullscreen-btn');if(!b)return;
  if(on)b.innerHTML='<svg class="tpXic" viewBox="0 0 24 24" aria-hidden="true"><path d="M6.5 6.5l11 11M17.5 6.5l-11 11"/></svg>';else if(b.querySelector('.tpXic'))b.textContent='⛶'}
// a tab in the bottom bar closes the full-screen map first, then works as usual
document.addEventListener('click',e=>{if(!document.body.classList.contains('tp23-map-open'))return;if(e.target.closest&&e.target.closest('.nav'))toggleMapFullscreen(false)},true);
addEventListener('resize',()=>{const rm=document.getElementById('rmap');if(rm&&rm.classList.contains('tp23-fullscreen')){const nh=tpNavH();rm.classList.toggle('tpNavOn',nh>0);document.body.style.setProperty('--tpNavH',nh+'px')}});
tpnWrap('tpHoodPick',true);
(function(){const f=flyTo;flyTo=function(lat,lng,z,ms){const r=f.apply(this,arguments),t=TM;
  if(t&&!t._tpHoodFraming&&z<13.1){clearTimeout(t._tpHoodT);t._tpHoodT=setTimeout(()=>{if(tpHoodBase()){tpHoodSync();requestAnimationFrame(()=>tpFsFrame(true))}},(ms||700)+80)}return r}})();
// the full-screen map is now a little shorter (bottom bar), so an open group can end at a slightly lower zoom: if the enlarged selected
// pin then covers a neighbour's head or tip, zoom in a little around the selected pin (max +1.2) so every close shop stays visible and tappable
function tpSelNudge(n){const t=TM;if(!t||!t.pinLayer||!S.sel||(S.route&&S.route.id))return;const e=t.pinLayer.querySelector('.pn.sel[data-id="'+S.sel+'"]');if(!e)return;
  const hitOther=(x,y,me)=>{const h=document.elementFromPoint(x,y),q=h&&h.closest&&h.closest('.pn');return !!(q&&q!==me)};
  const cov=[...t.pinLayer.querySelectorAll('.pn:not(.cluster)[data-id]')].some(x=>{if(x===e||!x.offsetParent)return false;const q=x.getBoundingClientRect(),cx=q.left+q.width/2;
    if(cx<0||cx>innerWidth||q.bottom<0||q.top>innerHeight)return false;return hitOther(cx,q.bottom-2,x)||hitOther(cx,q.top+q.height*.35,x)});
  if(!cov||n>=3||t.z>=PIN_ZOOM_HI-.25)return;const mr=t.el.getBoundingClientRect();const er=e.getBoundingClientRect(),nz=Math.min(PIN_ZOOM_HI,t.z+.3);zoomAt(er.left+er.width/2-mr.left,er.bottom-mr.top,nz);
  const top=TPN.stack[TPN.stack.length-1];if(top&&top.entryZ!=null)top.entryZ=nz;   // «−» still steps back from here in one tap
  setTimeout(()=>tpSelNudge(n+1),220)}
(function(){const f=pinTap;pinTap=function(){const r=f.apply(this,arguments);setTimeout(()=>tpSelNudge(0),420);setTimeout(()=>tpSelNudge(1),900);return r}})();
"""
R("function tpnSync(t){", js.replace('__HOOD__', json.dumps([[n, i] for n, i in HOOD], ensure_ascii=False)) + "function tpnSync(t){tpHoodSync();")
css = """<style>/* V3.7 — full-screen map: «أحياء وشوارع» strip, bottom bar, regional pins without counts */
.rmap .tpHood{position:absolute;z-index:40;top:calc(var(--tpHoodTop,78px));left:6px;right:52px;max-width:560px;background:none;border:0;box-shadow:none;
 font-family:'Tajawal',var(--gpFont,sans-serif);animation:tpHoodIn .22s ease-out}
.rmap .tpHood[hidden],.rmap .tpHoodShow[hidden]{display:none!important}
@keyframes tpHoodIn{from{opacity:0;transform:translateY(-6px)}to{opacity:1;transform:none}}
.tpHoodHide{position:absolute;z-index:3;left:50%;bottom:-11px;transform:translateX(-50%);width:34px;height:13px;border-radius:0 0 9px 9px;border:1px solid #d4a63a;border-top:0;
 background:linear-gradient(180deg,#fffaf0,#efdcb4);color:#7a5412;display:grid;place-items:center;padding:0;cursor:pointer;box-shadow:0 2px 4px rgba(0,0,0,.25)}
.tpHoodHide svg{width:12px;height:10px}
.tpHoodHide svg,.tpHoodShow svg,.tpHoodArr svg{width:14px;height:14px;fill:none;stroke:currentColor;stroke-width:2.6;stroke-linecap:round;stroke-linejoin:round}
.tpHoodBody{position:relative;display:flex;align-items:center;gap:0}
.tpHoodRow{flex:1;display:flex;gap:7px;overflow-x:auto;scroll-snap-type:x mandatory;scroll-behavior:smooth;-webkit-overflow-scrolling:touch;
 scrollbar-width:none;padding:3px 3px 5px;overscroll-behavior-x:contain;touch-action:pan-x}
.tpHoodRow::-webkit-scrollbar{display:none}
.tpHoodCard{position:relative;flex:0 0 auto;width:62px;height:82px;scroll-snap-align:start;padding:0;border-radius:12px;overflow:hidden;cursor:pointer;
 border:1.5px solid #f4ecd8;background:#d9d2c0;box-shadow:0 3px 8px rgba(0,20,60,.32);font:inherit}
.tpHoodCard img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;display:block}
/* name plate: the regional pins' cream ribbon — same font (Tajawal ExtraBold), dark brown, thin gold edge, light shine, overlapping the photo */
.tpHoodCard span{position:absolute;left:3px;right:3px;bottom:3px;min-height:21px;padding:4px 2px 3px;display:flex;align-items:center;justify-content:center;
 border-radius:50% 50% 7px 7px/7px 7px 7px 7px;border:1px solid #d4a63a;
 background:linear-gradient(180deg,#fffcf3 0%,#f8eed6 50%,#eedcb3 100%);box-shadow:inset 0 1px 0 rgba(255,255,255,.95),0 -1px 4px rgba(50,30,0,.28);
 font-family:'Tajawal',var(--gpFont,sans-serif);font-weight:800;font-size:9.6px;line-height:1.08;color:#2a1708;text-align:center;
 text-shadow:0 1px 0 rgba(255,250,236,.9);overflow-wrap:anywhere}
.tpHoodCard.on{border:2px solid transparent;background:linear-gradient(#d9d2c0,#d9d2c0) padding-box,linear-gradient(135deg,#fff4c8 0%,#e8b02a 30%,#fbe7a3 52%,#c88d14 75%,#ffe9a6 100%) border-box;
 box-shadow:0 0 0 1.5px rgba(242,184,39,.35),0 4px 11px rgba(140,90,0,.45)}
.tpHoodCard.on span{border-color:#c8901a;background:linear-gradient(180deg,#fff7dc 0%,#fde7a8 55%,#f1c862 100%)}
.tpHoodArr{position:relative;z-index:2;flex:0 0 22px;width:22px;height:22px;border-radius:50%;display:grid;place-items:center;padding:0;cursor:pointer;
 border:1px solid #e5d6b0;background:#fff;color:#0a2766;box-shadow:0 2px 6px rgba(0,0,0,.3)}
.tpHoodArr.tpHoodNext{margin-left:4px}.tpHoodArr.tpHoodPrev{margin-right:4px}
.tpHoodArr:disabled{visibility:hidden;pointer-events:none}
.rmap .tpHoodShow{position:absolute;z-index:40;top:calc(var(--tpHoodTop,78px));left:12px;display:flex;align-items:center;gap:5px;height:28px;padding:0 10px 0 12px;
 border-radius:14px;border:1.4px solid #e2b33f;background:linear-gradient(180deg,#123f95,#0a2766);color:#fff;font:800 13px 'Tajawal',sans-serif;
 box-shadow:0 4px 12px rgba(10,30,70,.3);cursor:pointer}
.rmap .tpHoodShow svg{color:#f2c14e}
/* bottom bar over the full-screen map: the map ends at its top edge (safe area included) */
body.tp23-map-open .nav{z-index:2147483600!important;visibility:visible!important}
body.tp23-map-open{background:#0c2a68!important}
body > .rmap.tp23-fullscreen.tpNavOn{bottom:var(--tpNavH,0px)!important;height:calc(100dvh - var(--tpNavH,0px))!important}
/* full-screen close button: SVG cross centred in the yellow square (replaces the text glyph and the V3.6.1 drawn bars) */
.rmap.tp23-fullscreen .tp23-fullscreen-btn{display:grid!important;place-items:center!important;padding:0!important;line-height:0!important}
.rmap.tp23-fullscreen .tp23-fullscreen-btn::before,.rmap.tp23-fullscreen .tp23-fullscreen-btn::after{content:none!important;display:none!important}
.rmap.tp23-fullscreen .tp23-fullscreen-btn .tpXic{width:17px;height:17px;display:block;fill:none;stroke:currentColor;stroke-width:2.7;stroke-linecap:round}
/* regional pins on the full-screen map: name only, centred in the ribbon */
.rmap.tp23-fullscreen .gp .gpK{display:none!important}
.rmap.tp23-fullscreen .gp .gpN{top:49.2%}
</style>
</head>"""
R("</head>", css)
open(P, 'w', encoding='utf-8').write(s); print('V3.7 patch applied')
