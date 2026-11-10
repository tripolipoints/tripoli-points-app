// V3.6.1: free hand zoom on the regional overview, Tell anchor, centred − / ✕ marks.
const {chromium,devices}=require('playwright');(async()=>{const [U,STUBF,OUT,DEV]=process.argv.slice(2);const b=await chromium.launch();
const ctx=await b.newContext({...devices[DEV],hasTouch:true});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(String(e).slice(0,160)));
const STUB=require('fs').readFileSync(STUBF,'utf8');
await ctx.route('**/*',r=>{const u=r.request().url();if(u.includes('supabase-js'))return r.fulfill({status:200,contentType:'application/javascript',body:STUB});
  if(u.startsWith('http://127.0.0.1')||u.startsWith('data:'))return r.continue();r.abort()});
await p.goto(U);await p.waitForTimeout(2500);
await p.evaluate(()=>{S.phone='70111222';S.customers[S.phone]={name:'t',last:'',points:0,status:'active'};S.mode='customer';S.tab='home';S.screen='app';S.userLL={lat:34.4372,lng:35.8300};try{syncDirectory()}catch(e){};render()});await p.waitForTimeout(4500);
await p.tap('.tp23-fullscreen-btn');await p.waitForTimeout(1500);
const st=()=>p.evaluate(()=>{const L=document.getElementById('tpBig'),pl=TM.pinLayer;const one=L&&L.querySelector('.tpBigPin[data-n="القبة"] .tpBigBtn');const r=one&&one.getBoundingClientRect();
  return {z:+TM.z.toFixed(2),free:!!TM._tpFree,stack:TPN.stack.length,bigShown:!!(L&&L.style.display!=='none'&&+(L.style.opacity||1)>.5),bigW:r?Math.round(r.width):0,
    shopLayer:pl?(pl.style.opacity===''?1:+pl.style.opacity):null,shopTaps:pl?pl.style.pointerEvents!=='none':null,openGroup:!!S._mapOpenGroup}});
const log=async(k,shot)=>{const s=await st();console.log(k.padEnd(30),JSON.stringify(s));if(shot)await p.screenshot({path:`${OUT}/${shot}.png`});return s};
await log('0 overview','v0');
// tell vs the «طرابلس» label
console.log('   tell/label',JSON.stringify(await p.evaluate(()=>{const t=document.querySelector('.tpBigPin[data-n="التل"] .tpBigBtn').getBoundingClientRect();
  const lab=[...document.querySelectorAll('#rmk *, .rmap *')].find(e=>e.children.length===0&&e.textContent.trim()==='طرابلس'&&e.offsetParent);const l=lab&&lab.getBoundingClientRect();
  return {tellTip:[Math.round(t.left+t.width*.4804),Math.round(t.top+t.height*.9223)],label:l&&[Math.round(l.left),Math.round(l.top),Math.round(l.right),Math.round(l.bottom)]}})));
// pinch (zoomAt is what the two-finger gesture calls) in small steps from 13 to 15.5
for(let z=13.2;z<=15.51;z+=.3)await p.evaluate(z=>zoomAt(TM.w/2,TM.h/2,z),z);await p.waitForTimeout(400);
await log('1 pinch to 15.5','v1');
await p.evaluate(()=>{for(let i=0;i<8;i++)TM.lng+=.0006;drawMap()});await p.waitForTimeout(300);await log('2 pan while free');
await p.tap('.zb[aria-label="تكبير"]');await p.waitForTimeout(700);await log('3 «+» while free');
// tap a regional pin → stages
const bb=await p.evaluate(()=>{const e=document.querySelector('.tpBigPin[data-n="القبة"] .tpBigBtn');const r=e.getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height*.35,vis:r.left>0&&r.right<innerWidth&&r.top>0&&r.bottom<innerHeight}});
if(!bb.vis){await p.evaluate(()=>{const R=TPA_REGIONS().find(r=>r[0]==='القبة');TM._tpKeepFree=1;TM.lat=R[1];TM.lng=R[2];drawMap();TM._tpKeepFree=0});await p.waitForTimeout(400)}
const b2=await p.evaluate(()=>{const e=document.querySelector('.tpBigPin[data-n="القبة"] .tpBigBtn');const r=e.getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height*.35}});
await p.touchscreen.tap(b2.x,b2.y);await p.waitForTimeout(1900);await log('4 tap القبة pin','v4');
await p.evaluate(()=>tpStepBack());await p.waitForTimeout(1500);await log('5 step back');
for(let i=0;i<4;i++){await p.tap('.zb[aria-label="تصغير"]');await p.waitForTimeout(500)}await log('6 «−» ×4 (to overview)','v6');
await p.tap('.zb[aria-label="تكبير"]');await p.waitForTimeout(800);await log('7 «+» from overview (old)');
await p.evaluate(()=>{tpStepBack()});await p.waitForTimeout(1200);
for(let i=0;i<3;i++){await p.tap('.zb[aria-label="تصغير"]');await p.waitForTimeout(500)}await log('8 back to overview');
// centring of − and ✕ marks: pixel bbox of the dark mark inside each button
const marks=[];for(const sel of ['.tp23-fullscreen-btn','.zb[aria-label="تصغير"]','.zb[aria-label="تكبير"]']){const e=await p.$(sel);const r=await e.boundingBox();
  const buf=await p.screenshot({clip:{x:r.x,y:r.y,width:r.width,height:r.height},scale:'css'});marks.push([sel,r.width,buf.toString('base64')])}
require('fs').writeFileSync(OUT+'/marks.json',JSON.stringify(marks));
console.log('errors',JSON.stringify(errs));await b.close()})();
