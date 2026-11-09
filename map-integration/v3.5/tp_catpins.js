/* ===== V3.5 (Staging): category image inside individual shop pins + progressive enlargement =====
   1) Category image: every individual shop pin (miniature gold pin) shows the image of the shop's PRIMARY category in place of
      the category icon — same pin, same gold frame/shine/shadow and size; only the inner image changes. Lookup by slug
      (assets/map/cat/<slug>.webp); if the primary category has no image, its parent category's image is used; with neither, the
      current icon stays. A shop logo that is currently shown keeps priority. Regional and cluster pins are untouched.
   2) Progressive enlargement (all individual shop pins): normal → selected (one step, ×1.45, above neighbours) → route
      («توجّه للمتجر», one more step). The pin grows from its tip, so it keeps pointing at the shop's exact location. The route
      view zooms the map out, so the route size is anchored to the size the pin had when selected (≥ ×1.18 of it). Cancelling
      the route, stepping back or choosing another shop returns to normal sizes (the map redraws the pins). */
const TP_CAT_SLUGS=new Set('__SLUGS__'.split(','));
const TP_CAT_ALIAS={earbuds:'earphones',headphones:'earphones',wedding:'wedding_dresses',bridal:'wedding_dresses',restaurants:'food',coffee:'cafe',clothes:'fashion'};
function tpCatImgOf(m){if(!m||!m.cat)return null;const cats=(typeof S!=='undefined'&&S.cats)||[];
  let slug=m.cat,c=cats.find(x=>x.slug===slug);
  for(let i=0;i<4&&slug;i++){const b=String(slug).toLowerCase().replace(/^(stg|test|demo)_/,'');   // Staging test slugs: stg_cafe → cafe
    const k=TP_CAT_SLUGS.has(b)?b:TP_CAT_ALIAS[b];if(k&&TP_CAT_SLUGS.has(k))return'assets/map/cat/'+k+'.webp';
    if(!c||c.parent_id==null)break;c=cats.find(x=>x.id===c.parent_id);slug=c&&c.slug}
  return null}
function tpCatDress(t){if(!t||!t.pinLayer)return;
  t.pinLayer.querySelectorAll('.pn:not(.cluster):not(.ref)[data-id]').forEach(e=>{if(e.querySelector('.tpCatImg'))return;
    const img=e.querySelector('.pnimg');if(img&&img.style.display!=='none')return;
    const src=tpCatImgOf(M(e.dataset.id));if(!src)return;
    e.classList.add('tpCatPin');const im=new Image();im.className='tpCatImg';im.alt='';im.draggable=false;im.decoding='async';
    im.onerror=()=>{im.remove();e.classList.remove('tpCatPin')};im.src=src;e.appendChild(im)})}
const TP_GROW_SEL=1.45,TP_GROW_ROUTE=1.9,TP_GROW_STEP=1.18,TP_GROW_SEL_MAX=2.6,TP_GROW_MAX=3.1; // caps keep the pin reasonable at the highest zoom on small phones
function tpGrowRouteScale(zs,t){const g=t&&t._tpGrowSel&&S.route&&t._tpGrowSel.id===S.route.id?t._tpGrowSel.s*TP_GROW_STEP:0;
  return Math.min(TP_GROW_MAX,Math.max(zs*TP_GROW_ROUTE,g))}
function tpGrowDress(t){if(!t||!t.pinLayer)return;
  if(t._tpNoGrow&&(S.sel!==t._tpNoGrow.id||Math.abs(t.z-t._tpNoGrow.z)>.05))t._tpNoGrow=null;   // another shop, a step back or a zoom → normal rules
  t.pinLayer.querySelectorAll('.pn:not(.cluster):not(.ref)[data-id]').forEach(e=>{e.classList.add('tpGrow');
    const zs=parseFloat(e.style.getPropertyValue('--zs'))||1;
    if(e.classList.contains('route'))e.style.transform=`scale(${tpGrowRouteScale(zs,t).toFixed(3)})`;
    else if(e.classList.contains('sel')&&t._tpNoGrow&&t._tpNoGrow.id===e.dataset.id)e.style.transform=`scale(${zs.toFixed(3)})`; // route cancelled: normal size
    else if(e.classList.contains('sel')){const k=Math.max(zs*1.12,Math.min(TP_GROW_SEL_MAX,zs*TP_GROW_SEL));t._tpGrowSel={id:e.dataset.id,s:k};e.style.transform=`scale(${k.toFixed(3)})`}
    else e.style.transform=''})}
// height (px) the destination pin will take in the route view — used by routeFitView so the enlarged pin stays fully on screen
function tpGrowRouteH(){return 33.8*tpGrowRouteScale(pinZoomScale(17),TM)}
// cancelling the route returns the selected pin to its normal size (the shop card stays open); called by clearRoute
function tpGrowRouteCancelled(){if(typeof TM!=='undefined'&&TM&&S.sel)TM._tpNoGrow={id:S.sel,z:TM.z}}
