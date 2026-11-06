/* ===== TRIAL (Staging only): category photo inside individual shop pins — one category: «سماعات أذن» =====
   Only individual shop pins (the miniature gold pin) get the photo, in place of the category icon, same pin, same size.
   Regional pins (zoom 13) and cluster pins are untouched. A shop whose logo is currently shown keeps its logo.
   Applies to a shop whose category (main or extra) name contains «سماعات» or whose slug is 'earbuds'.
   ?catdemo=1 : if Staging has no such shop, adds ONE in-memory test shop «سماعات أذن (تجريبي)» on Azmi Bek street for comparison.
   Nothing is written to the database; the test shop disappears on reload. */
const TP_CAT_IMG=[{test:(slug,name)=>slug==='earbuds'||/سماعات/.test(name||''),src:'assets/map/cat/cat-earbuds.webp'}];
function tpCatImgOf(m){if(!m)return null;const ks=[m.cat].concat(m.extraCats||[]);
  for(const k of ks){const c=CAT(k);for(const r of TP_CAT_IMG)if(r.test(k,c[1]))return r.src}return null}
function tpCatDress(t){if(!t||!t.pinLayer)return;
  t.pinLayer.querySelectorAll('.pn:not(.cluster):not(.ref)[data-id]').forEach(e=>{if(e.querySelector('.tpCatImg'))return;
    const img=e.querySelector('.pnimg');if(img&&img.style.display!=='none')return;            // a shown logo keeps priority
    const src=tpCatImgOf(M(e.dataset.id));if(!src)return;
    e.classList.add('tpCatPin');e.insertAdjacentHTML('beforeend',`<img class="tpCatImg" src="${src}" alt="" draggable="false">`)})}
(function(){if(!/[?&]catdemo=1/.test(location.search))return;
  const add=()=>{if(typeof S==='undefined'||S.dirState!=='ok'||!S.cats)return setTimeout(add,700);
    if(S.merchants.some(m=>tpCatImgOf(m)&&m.status==='active'))return;                     // Staging already has such a shop
    if(!S.cats.some(c=>c.slug==='earbuds'))S.cats.push({id:-901,slug:'earbuds',name_ar:'سماعات أذن (تجريبي)',icon:'🎧',color:'#8a6a2a',parent_id:null,is_active:false,sort_order:999});
    hydrateMerchant({id:'demo-earbuds',name:'سماعات أذن (تجريبي)',status:'active',cat:'earbuds',extra_cats:[],pct:5,tier:'small',
      lat:34.4420180,lng:35.8331420,addr:'شارع عزمي بك (متجر تجريبي — في الذاكرة فقط)',area:'عزمي بك',photo_url:'',logo_url:'',page_enabled:false});
    try{if(TM){buildMarks();drawMap()}}catch(e){}};add()})();
