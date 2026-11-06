/* ===== PREVIEW v9 (from v8): artistic opening view + the approved gold pin family (visual only, except the v6.2 empty-map close) =====
   - Regional pins (zoom 13): gold pin, per-area heritage engraving, live area name + live total count (gpRegional).
   - Cluster pins (the app's own .pn.cluster elements): same gold pin, geometric ornament, live count; the area name appears
     under the pin only where it fits. The app's markup, handlers and clustering are untouched; the gold artwork is layered in.
   - Unchanged from v6.2: artwork cross-fade 13.35-14.15, regional pins gliding to their area's cluster spot and handing over
     at about 13.95, empty-map tap closing only the expanded cluster, hidden pin of an expanded cluster. */
const TPA_Z0=13.35,TPA_Z1=14.15,GP_TIPX=576/1199,GP_TIPY=1210/1312,GP_AR=1312/1199;
const GP_RW=104,GP_CW=74;           // regional pin width at zoom 13; cluster pin width at zoom 14 (CSS px)
function gpRegionalH(n,c){const k=String(c).length>1?' two':'';return `<span class="gp" style="--w:${GP_RW}px"><img src="${GP_R[n]||GP_R['التل']}" alt="" draggable="false"><b class="gpN">${esc(n)}</b><i class="gpK${k}">${c} متجر</i></span>`}
const tpaSm=k=>{k=Math.max(0,Math.min(1,k));return k*k*(3-2*k)};
function tpaAlpha(z){return 1-tpaSm((z-TPA_Z0)/(TPA_Z1-TPA_Z0))}
function tpaBigScale(z){return +(GP_CW/GP_RW+(1-GP_CW/GP_RW)*(1-tpaSm((z-13.05)/.9))).toFixed(3)}   // 104 px -> 74 px by 13.95
function tpaClusterScale(z){return +(.84+.16*(1-tpaSm((z-14)/2))).toFixed(3)}                     // 74 px at 14 -> 62 px from 16
// the six regional areas of the opening map: the five main areas + Azmi Bek (its own shopping area)
const TPA_REGIONS=()=>{const az=(SUBAREAS.find(a=>a[0]==='عزمي بك')||[0,34.44008,35.83607]);return TAREAS.map(a=>[a[0],a[2],a[3]]).concat([['عزمي بك',az[1],az[2]]])};
// regional area of a merchant: an exact regional name stays itself; any other area (sub-area/street name saved at registration,
// e.g. «شارع مار مارون») goes to the NEAREST of the six regional areas, by that area's point (or the shop's own GPS if unknown)
function tpaBigOf(p){const a=p.area||'',R=TPA_REGIONS();if(R.some(r=>r[0]===a))return a;
  const c=areaLL(a)||(p.lat!=null?{lat:p.lat,lng:p.lng}:null);if(!c)return '';
  let best='',bd=1e18;R.forEach(r=>{const d=hav(c,{lat:r[1],lng:r[2]});if(d<bd){bd=d;best=r[0]}});return best}
function tpaBigTap(n){const t=TM;if(!t)return;const ps=(t.pins||[]).filter(p=>tpaBigOf(p)===n);if(!ps.length){const ll=TPA_REGIONS().find(r=>r[0]===n);if(ll){cancelAnimationFrame(t.anim);flyTo(ll[1],ll[2],15,650)}return}
  S._mapOpenGroup=null;S._mapSplitGroups=[];if(S.areaSel){S.areaSel=null;const row=$('#catrow');if(row)row.innerHTML=catsHtml()}
  const areas=[...new Set(ps.map(p=>p.area||''))];
  if(areas.length===1&&ps.length>=AREA_MIN_CLUSTER&&areaLL(areas[0])){clusterTap(ps.map(p=>p.id),areas[0]);return}
  cancelAnimationFrame(t.anim);clusterCenterView(ps.map(p=>({lat:p.lat,lng:p.lng})),Math.min(CLUSTER_MAXZ,t.z+3),650)}
function tpaBgTap(e){const t=TM;if(!t||t.moved||t.pick)return;
  if(e.target.closest('.mchip,.zb,.pn,#rtchip,#tpRouteActions,#tpBig,button,a,input,.tpPick,#storeSheet,.attr'))return;
  if(S.sel||(S.route&&S.route.id))return;
  const og=S._mapOpenGroup;if(!og)return;
  if(og.type==='split')S._mapOpenGroup={type:'area',area:og.area,split:true};
  else if(og.type==='area'&&!og.split)S._mapOpenGroup=null;else return;
  drawMarks()}
// v8: split pins — first tap from the closed split view zooms exactly two levels above the zoom at which the split appeared
// (capped at 20), centred on that group's shops, and opens it through the app's own openSplitGroup. Switching to the other
// half or re-opening after an empty-map close re-centres without stacking further zoom. Taps during the fly are ignored.
const _tpOpenSplit=openSplitGroup;
openSplitGroup=function(gid){const t=TM;if(!t)return _tpOpenSplit(gid);
  if(t._tpLock&&performance.now()<t._tpLock)return;
  const og=S._mapOpenGroup,g=(S._mapSplitGroups||[]).find(x=>x.gid===gid),closing=!!(og&&og.type==='split'&&og.gid===gid);
  _tpOpenSplit(gid);if(!g||closing)return;
  t._tpLock=performance.now()+750;
  const pts=g.ids.map(id=>{const m=M(id);return m?llOf(m):null}).filter(Boolean);if(!pts.length)return;
  const base=S._tpSplitZ||t.z,z=Math.min(PIN_ZOOM_HI,Math.max(t.z,base+2));
  t.w=t.el.clientWidth||t.w;t.h=t.el.clientHeight||t.h;const bc=clusterBBoxCenter(pts);
  flyTo(adjustLatForUsableCenter(bc.lat,bc.lng,z,t.el,t.h),bc.lng,z,650)};
// v9: shops of an opened cluster that sit too close on screen are fanned out a little (screen space only); each moved pin
// keeps a fine gold leader line and a dot at its true GPS point. The selected shop stays exactly on its true point.
function tpaSpread(t,X,Y){const og=S._mapOpenGroup;if(!t.pinLayer)return;
  if(!og||!(og.type==='split'||(og.type==='area'&&!og.split))||(S.route&&S.route.id)||t.z>=18.95)return;
  const mks=[...t.pinLayer.querySelectorAll('.mk')].filter(m=>{const p=m.firstElementChild;return p&&p.classList.contains('pn')&&!p.classList.contains('cluster')&&(m.style.zIndex==='7'||m.style.zIndex==='9')});
  if(mks.length<2)return;
  const P=mks.map((m,i)=>{const id=m.firstElementChild.dataset.id,pin=(t.pins||[]).find(p=>String(p.id)===String(id));
    const tx=pin?t.w/2+wx(pin.lng,t.z)-X:0,ty=pin?t.h/2+wy(pin.lat,t.z)-Y:0,r=/translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(m.style.transform)||[0,tx,ty];
    return{m,tx,ty,x:+r[1],y:+r[2],fix:String(id)===String(S.sel),i}});
  const D=34*pinZoomScale(t.z),MAX=2.4*D;
  for(let it=0;it<40;it++){let moved=false;
    for(let a=0;a<P.length;a++)for(let b=a+1;b<P.length;b++){const A=P[a],B=P[b];let dx=B.x-A.x,dy=B.y-A.y,d=Math.hypot(dx,dy);
      if(d>=D)continue;moved=true;if(d<.01){const an=(a*2.4+b*1.3);dx=Math.cos(an);dy=Math.sin(an)*.4;d=Math.hypot(dx,dy)}
      const push=(D-d)/(A.fix||B.fix?1:2)+.5,ux=dx/d,uy=dy/d*.6;               // mostly sideways, a little vertical
      if(!A.fix){A.x-=ux*push;A.y-=uy*push}if(!B.fix){B.x+=ux*push;B.y+=uy*push}}
    P.forEach(p=>{const ox=p.x-p.tx,oy=p.y-p.ty,o=Math.hypot(ox,oy);if(o>MAX){p.x=p.tx+ox/o*MAX;p.y=p.ty+oy/o*MAX}});
    if(!moved)break}
  let svg='';P.forEach(p=>{p.m.style.transform=`translate(${p.x.toFixed(0)}px,${p.y.toFixed(0)}px)`;
    if(Math.hypot(p.x-p.tx,p.y-p.ty)>3)svg+=`<line x1="${p.tx.toFixed(1)}" y1="${p.ty.toFixed(1)}" x2="${p.x.toFixed(1)}" y2="${p.y.toFixed(1)}" stroke="#a87a1c" stroke-width="1.4" stroke-dasharray="2 2"/>`;
    svg+=`<circle cx="${p.tx.toFixed(1)}" cy="${p.ty.toFixed(1)}" r="2.6" fill="#ffd23f" stroke="#5a3608" stroke-width="1"/>`});
  const L=document.createElementNS('http://www.w3.org/2000/svg','svg');L.setAttribute('class','tpLeads');L.innerHTML=svg;t.pinLayer.appendChild(L)}
// v8: keep the unopened half of a split visibly apart from the opened half's shops (screen-space only; GPS untouched)
function tpaSeparate(t){const og=S._mapOpenGroup;if(!t.pinLayer)return;
  if(og&&og.type==='area'&&og.split&&!S._tpSplitZ&&!t.flying)S._tpSplitZ=t.z;
  if(!og||!(og.type==='split'||(og.type==='area'&&og.split)))S._tpSplitZ=null;
  if(!og||og.type!=='split')return;
  const shops=[...t.pinLayer.querySelectorAll('.mk')].filter(m=>{const p=m.firstElementChild;return p&&p.classList.contains('pn')&&!p.classList.contains('cluster')&&(m.style.zIndex==='7'||m.style.zIndex==='9')});
  if(!shops.length)return;let U=null;
  shops.forEach(m=>m.querySelectorAll('.pn,.pnname').forEach(e=>{if(e.offsetParent===null)return;const r=e.getBoundingClientRect();U=U?{l:Math.min(U.l,r.left),r:Math.max(U.r,r.right),t:Math.min(U.t,r.top),b:Math.max(U.b,r.bottom)}:{l:r.left,r:r.right,t:r.top,b:r.bottom}}));
  if(!U)return;const G=10,uc=(U.l+U.r)/2;
  t.pinLayer.querySelectorAll('.pn.cluster.split:not(.open)').forEach(p=>{const mk=p.parentElement,r=p.getBoundingClientRect();
    if(r.right<U.l-G||r.left>U.r+G||r.bottom<U.t-G||r.top>U.b+G)return;
    const dx=((r.left+r.right)/2<uc)?(U.l-G-r.right):(U.r+G-r.left);
    const m=/translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(mk.style.transform);if(!m)return;
    mk.style.transform=`translate(${(+m[1]+dx).toFixed(0)}px,${m[2]}px)`;p.classList.add('tpShift')})}
function tpaNameTags(t){if(!t.pinLayer)return;const cl=[...t.pinLayer.querySelectorAll('.pn.cluster')];if(!cl.length)return;
  if(t.z<13.8){cl.forEach(e=>e.classList.remove('tpNamed'));return}
  const mr=t.el.getBoundingClientRect(),pins=[...t.pinLayer.querySelectorAll('.pn')].filter(e=>e.offsetParent!==null).map(e=>({e,r:e.getBoundingClientRect()}));
  const hit=(a,b)=>!(a.r<b.left||a.l>b.right||a.b<b.top||a.t>b.bottom),kept=[];
  cl.filter(e=>e.offsetParent!==null).sort((a,b)=>(+(b.querySelector('b')||{}).textContent||0)-(+(a.querySelector('b')||{}).textContent||0)).forEach(e=>{const r=e.getBoundingClientRect(),n=e.dataset.area||'',w=n.length*6.6+20,cx=r.left+r.width*GP_TIPX;
    const tag={l:cx-w/2,r:cx+w/2,t:r.bottom+2,b:r.bottom+22};
    const ok=n&&tag.l>mr.left+4&&tag.r<mr.right-4&&tag.b<mr.bottom-4&&!pins.some(p=>p.e!==e&&hit(tag,p.r))&&!kept.some(k=>hit(tag,{left:k.l,right:k.r,top:k.t,bottom:k.b}));
    e.classList.toggle('tpNamed',!!ok);if(ok)kept.push(tag)})}
function tpArtSync(t,X,Y){if(!t||t.pick||!t.tl||!t.mk)return;
  if(!t._tpBg){t._tpBg=1;t.el.addEventListener('click',tpaBgTap);t.off.push(()=>t.el.removeEventListener('click',tpaBgTap))}
  const a=S.mapStyle==='sat'?0:tpaAlpha(t.z),s=2**(t.z-14),m=TPA.m;
  t.el.classList.add('tpv6');t.el.style.setProperty('--tpcs',tpaClusterScale(t.z));
  let im=document.getElementById('tpArt');
  if(!im||im.parentNode!==t.tl){im=document.createElement('img');im.id='tpArt';im.alt='';im.draggable=false;im.decoding='async';im.src=TPA_IMG;t.tl.appendChild(im)}
  if(a<=.002)im.style.display='none';
  else{im.style.display='';im.style.opacity=a.toFixed(3);
    im.style.transform=`matrix(${m[0]*s},${m[1]*s},${m[2]*s},${m[3]*s},${(m[4]*s-X+t.w/2).toFixed(2)},${(m[5]*s-Y+t.h/2).toFixed(2)})`}
  tpaSpread(t,X,Y);tpaSeparate(t);
  const busy=!!(S.route&&S.route.id)||S.mapStyle==='sat';
  const hand=tpaSm((t.z-13.85)/.2),pa=busy?0:1-hand,ca=busy?1:hand;
  if(t.pinLayer){t.pinLayer.style.opacity=ca<.998?ca.toFixed(3):'';t.pinLayer.style.pointerEvents=ca<.5?'none':''}
  tpaNameTags(t);
  let L=document.getElementById('tpBig');
  if(!L||L.parentNode!==t.mk){L=document.createElement('div');L.id='tpBig';L._sig='';t.mk.appendChild(L)}
  if(pa<=.002){L.style.display='none';return}
  L.style.display='';L.style.opacity=pa.toFixed(3);L.classList.toggle('off',pa<.5);
  const cnt={};(t.pins||[]).forEach(p=>{const b=tpaBigOf(p);(cnt[b]=cnt[b]||[]).push(p.id)});
  const sig=TPA.pins.map(([n])=>n+':'+((cnt[n]||[]).length)).join('|');
  if(L._sig!==sig){L._sig=sig;
    L.innerHTML=TPA.pins.map(([n,u,v])=>{cnt[n]=cnt[n]||[];return [n,u,v]}).map(([n,u,v])=>`<div class="tpBigPin" data-n="${esc(n)}" data-u="${u}" data-v="${v}"><button type="button" class="tpBigBtn" data-n="${esc(n)}" aria-label="${esc(n)}: ${cnt[n].length} متجر">${gpRegionalH(n,cnt[n].length)}</button></div>`).join('');
    L.querySelectorAll('.tpBigBtn').forEach(b=>b.onclick=e=>{e.stopPropagation();if(TM&&TM.moved)return;tpaBigTap(b.dataset.n)})}
  const g=tpaSm((t.z-13.05)/.8),bs=tpaBigScale(t.z);
  L.querySelectorAll('.tpBigPin').forEach(d=>{const u=+d.dataset.u,v=+d.dataset.v,ll=areaLL(d.dataset.n);
    let x=(m[0]*u+m[2]*v+m[4])*s-X+t.w/2,y=(m[1]*u+m[3]*v+m[5])*s-Y+t.h/2;
    if(ll&&g>0){const rx=t.w/2+wx(ll.lng,t.z)-X,ry=t.h/2+wy(ll.lat,t.z)-Y;x+=(rx-x)*g;y+=(ry-y)*g}
    d.style.transform=`translate(${x.toFixed(1)}px,${y.toFixed(1)}px) scale(${bs})`})}
