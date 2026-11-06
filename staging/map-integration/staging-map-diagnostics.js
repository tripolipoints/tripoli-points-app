/* Tripoli Points — STAGING map diagnostics (Staging package only; not part of the app source).
   Open the site with ?mapdiag=1 : after the shops load, a panel lists what the map received from the Staging database
   and how every shop is counted in the six regional pins. Read-only: it changes nothing in the app or the database. */
(function(){if(!/[?&]mapdiag=1/.test(location.search))return;
function run(){try{
  if(typeof S==='undefined'||!S.merchants)return setTimeout(run,1500);
  const all=S.merchants,byStatus={};all.forEach(m=>{byStatus[m.status||'?']=(byStatus[m.status||'?']||0)+1});
  const live=all.filter(m=>m.status==='active'&&isLiveMerchant(m)),vis=visibleMerchants();
  const regions=TPA_REGIONS().map(r=>r[0]),cnt={};regions.forEach(r=>cnt[r]=0);
  const rows=all.map(m=>{const l=m.lat!=null?{lat:m.lat,lng:m.lng}:null,area=m.area||(l?nearestArea(l.lat,l.lng):'');
    const reg=tpaBigOf({area,lat:l&&l.lat,lng:l&&l.lng});const onMap=vis.some(v=>v.id===m.id);if(onMap&&reg)cnt[reg]++;
    const why=m.status!=='active'?'status: '+m.status:!isLiveMerchant(m)?'not live (isLiveMerchant)':!l?'no GPS':!onMap?'hidden by current filter/search':'';
    return [m.name||m.id,m.status||'',m.area||'(none → '+area+')',l?l.lat.toFixed(5)+', '+l.lng.toFixed(5):'—',reg||'—',onMap?'✓':'✗ '+why]});
  const esc=s=>String(s).replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
  const d=document.createElement('div');d.id='tpMapDiag';
  d.style.cssText='position:fixed;inset:8px;z-index:2147483646;background:#fffdf7;color:#222;border:2px solid #c99a2e;border-radius:12px;overflow:auto;padding:12px;font:13px/1.45 system-ui,sans-serif;direction:rtl';
  d.innerHTML=`<b style="font-size:15px">تشخيص الخريطة (Staging)</b> <button id="tpDiagX" style="float:left">إغلاق</button><br>
   المتاجر المحمّلة من قاعدة Staging: <b>${all.length}</b> — حسب الحالة: ${esc(JSON.stringify(byStatus))} — فعّالة وظاهرة: <b>${live.length}</b> — على الخريطة الآن: <b>${vis.length}</b>
   — دبابيس الخريطة: <b>${TM&&TM.pins?TM.pins.length:'(افتح الخريطة)'}</b><br>
   <b>عدد كل منطقة من المناطق الست:</b> ${regions.map(r=>`${esc(r)}: <b>${cnt[r]}</b>`).join(' · ')}
   <table style="width:100%;border-collapse:collapse;margin-top:8px;font-size:12px"><tr style="background:#f3e6c4">${['المتجر','الحالة','المنطقة المسجّلة','GPS','دبوس المنطقة','على الخريطة'].map(h=>`<th style="border:1px solid #ddd;padding:3px">${h}</th>`).join('')}</tr>
   ${rows.map(r=>`<tr>${r.map(c=>`<td style="border:1px solid #eee;padding:3px">${esc(c)}</td>`).join('')}</tr>`).join('')}</table>`;
  document.body.appendChild(d);document.getElementById('tpDiagX').onclick=()=>d.remove();
  console.log('[mapdiag] six regional counts',cnt,'rows',rows);
}catch(e){console.error('[mapdiag]',e)}}
setTimeout(run,4000)})();
