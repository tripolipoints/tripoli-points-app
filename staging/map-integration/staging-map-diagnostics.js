/* Tripoli Points — STAGING diagnostics (Staging package only; not part of the app source). Read-only.
   Open the site with ?mapdiag=1 . A small bar appears at the bottom (tap it to open/close the details). It shows:
   - which Supabase project and public key the page really uses;
   - every phone lookup (merchant_check_phone / customer_check_phone): answer or exact error, time taken (phone masked);
   - JavaScript errors on the page;
   - the six regional gold pins: count, whether each is created, visible and inside the map, and whether its image loaded;
   - every shop from the Staging database and the regional pin it counts towards. Nothing is written anywhere. */
(function(){if(!/[?&]mapdiag=1/.test(location.search))return;
const LOG={rpc:[],err:[]},mask=p=>String(p||'').replace(/\d(?=\d{3})/g,'•');
window.addEventListener('error',e=>LOG.err.push((e.message||'error')+' @'+(e.filename||'').split('/').pop()+':'+(e.lineno||'')));
window.addEventListener('unhandledrejection',e=>LOG.err.push('promise: '+String(e.reason&&e.reason.message||e.reason)));
function hook(){if(typeof sbRpc!=='function'||typeof sb==='undefined')return setTimeout(hook,300);
  // same behaviour as the app's sbRpc (one request, same toast on error); it only records the phone-lookup answers
  window.sbRpc=sbRpc=async function(fn,args){const t0=performance.now(),rec=/check_phone/.test(fn),log=a=>{if(rec)LOG.rpc.push({fn,phone:mask(args&&args.p_phone),ms:Math.round(performance.now()-t0),answer:a})};
    try{const{data,error}=await sb.rpc(fn,args);if(error){log('ERROR '+(error.code||'')+' '+(error.message||error.hint||JSON.stringify(error)));console.error(fn,error);toast('خطأ: '+(error.message||error.hint||JSON.stringify(error)).slice(0,120));return null}
      log(JSON.stringify(data));return data}
    catch(e){log('EXCEPTION '+(e&&e.message||e));console.error(fn,e);toast('تعذّر الاتصال بالخادم: '+(e&&e.message?e.message:'تحقق من الإنترنت'));return null}}}
hook();
const esc=s=>String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
const bar=document.createElement('div');bar.id='tpDiag';
bar.style.cssText='position:fixed;left:6px;right:6px;bottom:6px;z-index:2147483646;max-height:46vh;overflow:auto;background:rgba(255,253,247,.97);color:#222;border:2px solid #c99a2e;border-radius:12px;padding:6px 10px;font:12px/1.45 system-ui,sans-serif;direction:rtl;box-shadow:0 4px 14px rgba(0,0,0,.25)';
let open=false;bar.onclick=e=>{if(e.target.closest('table'))return;open=!open;draw()};
function pinState(){const t=typeof TM!=='undefined'?TM:null,L=document.getElementById('tpBig');if(!t)return{note:'الخريطة غير مفتوحة'};
  const R=t.el.getBoundingClientRect(),cs=L?getComputedStyle(L):null;
  const pins=L?[...L.querySelectorAll('.tpBigBtn')].map(b=>{const r=b.getBoundingClientRect(),cx=(r.left+r.right)/2,cy=(r.top+r.bottom)/2,img=b.querySelector('img');
    return b.dataset.n+': '+(b.querySelector('.gpK')||{}).textContent+' — '+(cx>R.left&&cx<R.right&&cy>R.top&&cy<R.bottom?'داخل الخريطة':'خارج إطار الخريطة')+(img&&img.complete&&img.naturalWidth?'':' — صورة الدبوس لم تُحمَّل')}):[];
  const art=document.getElementById('tpArt');
  return{z:t.z.toFixed(2),centre:t.lat.toFixed(4)+', '+t.lng.toFixed(4),layer:L?('display '+cs.display+', opacity '+cs.opacity):'غير موجودة',pins,art:art?('opacity '+getComputedStyle(art).opacity+(art.complete&&art.naturalWidth?'':' — لم تُحمَّل')):'غير موجودة',route:!!(S.route&&S.route.id),sel:S.sel||''}}
function draw(){try{
  const key=typeof SB_KEY!=='undefined'?SB_KEY:'',url=typeof SB_URL!=='undefined'?SB_URL:'';
  const ps=pinState(),ms=typeof S!=='undefined'&&S.merchants?S.merchants:[],live=ms.filter(m=>m.status==='active'&&isLiveMerchant(m)&&m.lat!=null);
  const regs=typeof TPA_REGIONS==='function'?TPA_REGIONS().map(r=>r[0]):[],cnt={};regs.forEach(r=>cnt[r]=0);live.forEach(m=>{const g=tpaBigOf({area:m.area||nearestArea(m.lat,m.lng),lat:m.lat,lng:m.lng});if(g)cnt[g]++});
  let h=`<b>تشخيص Staging</b> · الدبابيس: ${ps.pins?ps.pins.length:0}/6 · فحوص الرقم: ${LOG.rpc.length} · أخطاء JS: ${LOG.err.length} · <u>${open?'إخفاء':'التفاصيل'}</u>`;
  if(open){h+=`<div style="margin-top:6px"><b>الاتصال:</b> ${esc(url)} — المفتاح ${esc(key.slice(0,18))}…${esc(key.slice(-6))}</div>
   <div><b>فحوص رقم الهاتف:</b> ${LOG.rpc.length?LOG.rpc.map(r=>esc(`${r.fn} (${r.phone}, ${r.ms} ms): ${r.answer}`)).join('<br>'):'لا شيء بعد'}</div>
   <div><b>أخطاء JavaScript:</b> ${LOG.err.length?LOG.err.map(esc).join('<br>'):'لا شيء'}</div>
   <div><b>الخريطة:</b> ${esc(JSON.stringify({z:ps.z,centre:ps.centre,layer:ps.layer,art:ps.art,route:ps.route,sel:ps.sel}))}</div>
   <div><b>الدبابيس الست:</b><br>${(ps.pins||[]).map(esc).join('<br>')||esc(ps.note||'—')}</div>
   <div><b>المتاجر من قاعدة Staging:</b> ${ms.length} محمّلة، ${live.length} فعّالة بإحداثيات — ${regs.map(r=>esc(r)+': '+cnt[r]).join(' · ')}</div>
   <table style="width:100%;border-collapse:collapse;margin-top:4px;font-size:11px"><tr style="background:#f3e6c4"><th>المتجر</th><th>الحالة</th><th>المنطقة المسجّلة</th><th>GPS</th><th>دبوس المنطقة</th></tr>
   ${ms.map(m=>{const l=m.lat!=null;return `<tr><td>${esc(m.name||m.id)}</td><td>${esc(m.status||'')}${isLiveMerchant(m)?'':' (غير فعّال/تجريبي)'}</td><td>${esc(m.area||'—')}</td><td>${l?m.lat.toFixed(4)+', '+m.lng.toFixed(4):'—'}</td><td>${l?esc(tpaBigOf({area:m.area||nearestArea(m.lat,m.lng),lat:m.lat,lng:m.lng})):'—'}</td></tr>`}).join('')}</table>`}
  bar.innerHTML=h}catch(e){bar.textContent='diag error: '+e.message}}
function start(){document.body.appendChild(bar);draw();setInterval(()=>{if(!open)draw()},1500)}
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',start):start()})();
