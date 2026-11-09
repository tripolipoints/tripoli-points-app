// Regional pins: records each pin's position (tip point, button box, layer transform) on the home-card map and the fullscreen map,
// plus screenshots, so baseline and new builds can be compared exactly. Also checks names, images and the tap → zoom flow.
const {chromium,devices}=require('playwright');(async()=>{const [U,STUBF,OUT,DEV,TAG]=process.argv.slice(2);const b=await chromium.launch();
const ctx=await b.newContext({...devices[DEV],hasTouch:true});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(String(e).slice(0,160)));
const STUB=require('fs').readFileSync(STUBF,'utf8');
await ctx.route('**/*',r=>{const u=r.request().url();if(u.includes('supabase-js'))return r.fulfill({status:200,contentType:'application/javascript',body:STUB});
  if(u.includes('fonts.g'))return r.abort();if(u.startsWith('http://127.0.0.1')||u.startsWith('data:'))return r.continue();r.abort()});
await p.goto(U);await p.waitForTimeout(2500);
await p.evaluate(()=>{S.phone='70111222';S.customers[S.phone]={name:'t',last:'',points:0,status:'active'};S.mode='customer';S.tab='home';S.screen='app';S.userLL={lat:34.4372,lng:35.8300};try{syncDirectory()}catch(e){};render()});await p.waitForTimeout(4500);
const rec=()=>p.evaluate(()=>{const o={z:+TM.z.toFixed(4),pins:{}};document.querySelectorAll('#tpBig .tpBigPin').forEach(d=>{const bt=d.querySelector('.tpBigBtn');const r=bt.getBoundingClientRect();
  const img=bt.querySelector('.gp img'),nm=bt.querySelector('.gpN'),k=bt.querySelector('.gpK');
  o.pins[d.dataset.n]={transform:d.style.transform,tip:[+(r.left+r.width*.4804).toFixed(2),+(r.top+r.height*.9223).toFixed(2)],box:[r.left,r.top,r.width,r.height].map(v=>+v.toFixed(2)),
    img:img&&img.getAttribute('src'),imgOk:!!(img&&img.complete&&img.naturalWidth),name:nm&&nm.textContent,count:k&&k.textContent,font:nm&&getComputedStyle(nm).fontFamily.split(',')[0]}});return o});
const out={};await p.waitForTimeout(800);
out.small=await rec();await p.screenshot({path:`${OUT}/${TAG}_small.png`});
await p.tap('.tp23-fullscreen-btn');await p.waitForTimeout(1600);out.big=await rec();await p.screenshot({path:`${OUT}/${TAG}_big.png`});
// flow: tap a regional pin → zooms into the area; step back → regional view again
await p.tap('.tpBigBtn[data-n="القبة"]');await p.waitForTimeout(1800);out.afterTap=await p.evaluate(()=>({z:+TM.z.toFixed(2),visibleShopOrCluster:[...document.querySelectorAll('.pinLayer .pn')].filter(e=>e.offsetParent).length}));
await p.evaluate(()=>tpStepBack());await p.waitForTimeout(3200);out.afterBack=await rec();
out.errors=errs;require('fs').writeFileSync(`${OUT}/${TAG}.json`,JSON.stringify(out,null,1));console.log(TAG,'done',JSON.stringify(errs));await b.close()})();
