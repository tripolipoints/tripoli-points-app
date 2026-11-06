/* ===== TRIAL (Staging only): compare two ways of showing 3 close shops. Enabled only with ?pindemo=1 =====
   Six in-memory test shops (never written to the database; gone on reload), two groups of three, same spacing (18 m, on a real
   street), same categories and the same current images:
   - Group A «نديم الجسر» — progressive enlargement: tap a shop → its pin grows one step; «توجّه للمتجر» / route → one more step.
     Other pins keep their size. Choosing another shop, stepping back or cancelling the route returns to normal sizes.
   - Group B «شارع مار مارون» — the current behaviour, unchanged.
   Same pin design, same images, same tip position (the pin grows from its tip, so it still points to the exact location). */
const TP_GROW_SEL=1.45,TP_GROW_ROUTE=1.9;      // group A only; the current app uses 1.12 (selected) and 1.4 (route) for all shops
// the route view zooms the map out, and pins shrink with the zoom; so the 2nd step is anchored to the size the pin had when it was
// selected (at least ×1.18 of it), keeping the order normal < selected < route visible whatever the zoom
function tpGrowDress(t){if(!t||!t.pinLayer)return;
  t.pinLayer.querySelectorAll('.pn:not(.cluster)[data-id^="demo-a"]').forEach(e=>{e.classList.add('tpGrow');
    const zs=parseFloat(e.style.getPropertyValue('--zs'))||1;
    if(e.classList.contains('sel')&&!e.classList.contains('route')){t._tpGrowSel={id:e.dataset.id,px:38*zs*TP_GROW_SEL};e.style.transform=''}
    else if(e.classList.contains('route')){const g=t._tpGrowSel&&t._tpGrowSel.id===e.dataset.id?t._tpGrowSel.px:0;
      e.style.transform=`scale(${Math.max(zs*TP_GROW_ROUTE,g*1.18/38).toFixed(3)})`}
    else e.style.transform=''})}
(function(){if(!/[?&]pindemo=1/.test(location.search))return;
  const G=[['demo-a','نديم الجسر',[[34.4406579,35.8319347],[34.4407749,35.8320703],[34.4408919,35.8322060]]],
           ['demo-b','شارع مار مارون',[[34.4403927,35.8344528],[34.4402547,35.8343501],[34.4401168,35.8342474]]]];
  const CATS=[['earbuds','سماعات'],['cafe','مقهى'],['fashion','ألبسة']];
  const add=()=>{if(typeof S==='undefined'||S.dirState!=='ok'||!S.cats)return setTimeout(add,700);if(M('demo-a1'))return;
    if(!S.cats.some(c=>c.slug==='earbuds'))S.cats.push({id:-901,slug:'earbuds',name_ar:'سماعات أذن (تجريبي)',icon:'🎧',color:'#8a6a2a',parent_id:null,is_active:false,sort_order:999});
    G.forEach(([pre,area,pts])=>pts.forEach(([lat,lng],i)=>{const [cat,label]=CATS[i],real=(S.cats||[]).find(c=>c.slug===cat);
      hydrateMerchant({id:pre+(i+1),name:`${label} ${pre==='demo-a'?'أ':'ب'}${i+1} (تجريبي)`,status:'active',cat:(real||cat==='earbuds')?cat:((mainCats()[i]||{}).slug||'earbuds'),extra_cats:[],pct:5,tier:'small',
        lat,lng,addr:`${area} (متجر تجريبي — في الذاكرة فقط)`,area,photo_url:'',logo_url:'',page_enabled:false})}));
    try{if(TM){buildMarks();drawMap()}}catch(e){}};add()})();
