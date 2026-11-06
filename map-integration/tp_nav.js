/* ===== Map step-back navigation (V3.4 candidate). Display/navigation only: no data, QR, points or account logic. =====
   Every forward map step (regional pin, cluster, split pin, shop selection, route start) records the state BEFORE it:
   open cluster/split groups, selected shop, route on/off, and the exact view (centre + zoom).
   A tap on genuinely empty map goes back exactly one step and restores that state and view:
   route → selected shop (card kept) → open cluster → closed split pins → regional view → Tripoli overview (no further action).
   «−» at the zoom where a map step was entered goes back that step; otherwise it zooms out one level as before.
   Zooming far out of an open cluster (pinch or «−») closes that cluster, so a cluster pin never shows with its own shops.
   Routes are never cancelled by zooming; only by the explicit route controls or by a step back. */
const TPN={stack:[],depth:0,MAX:12,resets:0};
const tpnView=()=>TM?{lat:TM.lat,lng:TM.lng,z:TM.z}:null;
const tpnClone=o=>o==null?o:JSON.parse(JSON.stringify(o));
function tpnSnap(){return{og:tpnClone(S._mapOpenGroup),split:tpnClone(S._mapSplitGroups||[]),sel:S.sel||null,route:!!(S.route&&S.route.id),view:tpnView()}}
const tpnSig=s=>JSON.stringify([s.og,(s.split||[]).map(g=>[g.ids,g.off]),s.sel,s.route]);
function tpnKind(a,b){if(a.route!==b.route)return'route';if(a.sel!==b.sel)return'sel';if(tpnSig({og:a.og,split:a.split})!==tpnSig({og:b.og,split:b.split}))return'cluster';return'view'}
function tpnPush(before,kind){const top=TPN.stack[TPN.stack.length-1];
  // choosing another shop while one is selected: keep a single «selected» step (back leaves the selection)
  if(kind==='sel'&&top&&top.kind==='sel'&&before.sel&&S.sel&&!before.route)return;
  if(top&&tpnSig(top.snap)===tpnSig(before)&&top.kind===kind&&kind!=='view')return;      // repeated tap: no duplicate step
  const e={snap:before,kind,entryZ:null};TPN.stack.push(e);setTimeout(()=>{if(e.entryZ==null&&TM&&!TM.flying)e.entryZ=TM.z},900);if(TPN.stack.length>TPN.MAX)TPN.stack.shift()}
// wrap a forward action: record the state before it, if the action really changed the logical state (or always, for view steps)
function tpnWrap(name,always){const f=window[name];if(typeof f!=='function'||f._tpn)return;
  const w=function(){if(TPN.depth||!TM)return f.apply(this,arguments);const before=tpnSnap(),r0=TPN.resets;TPN.depth++;
    let r;try{r=f.apply(this,arguments)}finally{TPN.depth--}
    if(TPN.resets!==r0)return r;const after=tpnSnap(),k=tpnKind(before,after);if(k!=='view'||always)tpnPush(before,k);return r};
  w._tpn=1;window[name]=w;try{eval(name+'=w')}catch(e){}}
// routes are asynchronous: record the step when a route starts for a shop that has none (switching walk/drive is not a new step)
(function(){const f=showRoute;showRoute=window.showRoute=function(id,mode){
  if(TM&&!(S.route&&S.route.id===id)){const b=tpnSnap();b.route=false;b.sel=S.sel||null;tpnPush(b,'route')}return f.apply(this,arguments)}})();
// a second quick tap right after a cluster opens must not select the shop that just appeared under the finger
['clusterTap','openSplitGroup'].forEach(n=>{const f=window[n];if(typeof f!=='function')return;const w=function(){const r=f.apply(this,arguments);if(TM)TM._tpnOpenAt=performance.now();return r};window[n]=w;try{eval(n+'=w')}catch(e){}});
(function(){const f=pinTap;const w=function(id){if(TM&&TM._tpnOpenAt&&performance.now()-TM._tpnOpenAt<600)return;return f.apply(this,arguments)};window.pinTap=w;try{pinTap=w}catch(e){}})();
['clusterTap','openSplitGroup','pinTap'].forEach(n=>tpnWrap(n,false));tpnWrap('tpaBigTap',true);
// explicit full resets keep their behaviour and start a fresh history
['resetMapFilter','clearMapSel'].forEach(n=>{const f=window[n];if(typeof f!=='function')return;const w=function(){TPN.stack=[];TPN.resets++;return f.apply(this,arguments)};window[n]=w;try{eval(n+'=w')}catch(e){}});
function tpnRestore(s,moveView){
  const hadRoute=!!(S.route&&S.route.id);if(hadRoute&&!s.route)clearRoute();
  const selChanged=(S.sel||null)!==(s.sel||null);S.sel=s.sel;if(selChanged){S.sheetFull=false;try{refreshCardUi(false)}catch(e){}try{refreshGoogleNavButton()}catch(e){}}
  S._mapOpenGroup=tpnClone(s.og);S._mapSplitGroups=tpnClone(s.split)||[];
  if(moveView&&s.view&&TM){cancelAnimationFrame(TM.anim);flyTo(s.view.lat,s.view.lng,s.view.z,550)}else drawMarks()}
// one step back (empty-map tap or «−» at a step's entry zoom). Returns true when something went back.
function tpStepBack(){if(!TM)return false;
  while(TPN.stack.length){const e=TPN.stack.pop(),cur=tpnSnap();
    const sameState=tpnSig(e.snap)===tpnSig(cur),v=e.snap.view,c=cur.view,sameView=v&&c&&Math.abs(v.z-c.z)<.05&&Math.abs(v.lat-c.lat)<1e-5&&Math.abs(v.lng-c.lng)<1e-5;
    if(sameState&&sameView)continue;                                 // a step that changed nothing (e.g. a route that failed): skip it
    tpnRestore(e.snap,true);return true}
  // no recorded step (e.g. the map was opened at a deeper state): derive one step back from the current state, no view jump
  const og=S._mapOpenGroup;
  if(S.route&&S.route.id){clearRoute();return true}
  if(S.sel){tpnRestore(Object.assign(tpnSnap(),{sel:null}),false);return true}
  if(og&&og.type==='split'){S._mapOpenGroup={type:'area',area:og.area,split:true};drawMarks();return true}
  if(og&&og.type==='area'){S._mapOpenGroup=null;S._mapSplitGroups=[];drawMarks();return true}
  return false}                                                       // Tripoli overview: nothing to go back to
// empty-map tap: ignore taps on any control, card, pin, list, or on/near the drawn route line
function tpnOnRoute(e){const R=S.route;if(!R||!R.coords||!TM)return false;const r=TM.el.getBoundingClientRect(),x=e.clientX-r.left,y=e.clientY-r.top,X=wx(TM.lng,TM.z),Y=wy(TM.lat,TM.z);
  const P=R.coords.map(([la,ln])=>[TM.w/2+wx(ln,TM.z)-X,TM.h/2+wy(la,TM.z)-Y]);
  for(let i=1;i<P.length;i++){const[a,b]=[P[i-1],P[i]],dx=b[0]-a[0],dy=b[1]-a[1],L=dx*dx+dy*dy||1,k=Math.max(0,Math.min(1,((x-a[0])*dx+(y-a[1])*dy)/L));
    if(Math.hypot(x-(a[0]+k*dx),y-(a[1]+k*dy))<16)return true}return false}
function tpnBgTap(e){const t=TM;if(!t||t.moved||t.pick)return;
  if(e.target.closest('.mchip,.zb,.pn,#rtchip,#tpRouteActions,#tpBig,button,a,input,select,textarea,.tpPick,#storeSheet,#mapcard,.attr,.tpCityBtn,.tp23-fullscreen-btn,.pnname'))return;
  if(tpnOnRoute(e))return;
  tpStepBack()}
// «−» follows the steps: at the zoom where the current map step was entered it goes back that step; otherwise a normal zoom out
(function(){const f=zoomMap;const w=function(d){
  if(d<0&&TM&&!(S.route&&S.route.id)&&!S.sel){const top=TPN.stack[TPN.stack.length-1];
    if(top&&(top.kind==='cluster'||top.kind==='view')&&top.entryZ!=null&&TM.z<=top.entryZ+.05&&tpStepBack())return}
  return f(d)};window.zoomMap=w;try{zoomMap=w}catch(e){}})();
// keep the state consistent with the zoom (called on every map draw): note each step's settled zoom; after pinching or zooming
// far out of an open cluster, close it (logical state only, the view stays where the customer put it)
function tpnSync(t){if(!t||t.flying)return;const top=TPN.stack[TPN.stack.length-1];if(!top)return;
  if(top.entryZ==null){top.entryZ=t.z;return}
  if((t.ptr&&t.ptr.size)||S.sel||(S.route&&S.route.id))return;
  if((top.kind==='cluster')&&t.z<top.entryZ-1.25){TPN.stack.pop();tpnRestore(top.snap,false)}}
