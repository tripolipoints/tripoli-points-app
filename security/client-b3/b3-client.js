/* ===== Batch 3 client (Staging): server sessions, secure purchase QR, branch allowance, manual payments, staff =====
   Loaded after the main app script. It only REPLACES the way the app talks to the server; the screens, map, pins,
   Discover, Treasures and the Admin gift screen stay the same.
   - Login keeps the same screens: the PIN check now returns a server session (memory only, never in localStorage).
   - Every account function is sent as its session version (*_v2) with p_session; ids typed by the browser are dropped.
   - Purchase: the customer shows a 5-minute single-use code (QR + 8-digit fallback); the shop scans it, the server
     quotes (customer balance, branch allowance 70 % / ≤ 10 all, daily limit) and the customer approves the exact details.
   - New screens: shop «الاشتراك ورصيد القبول» (plans, packages, transfer request), «الموظفون»; staff login;
     Admin «طلبات الدفع», «الاشتراكات والباقات», «إعدادات المحرّك», customer points ledger, audit log. */
(function(){
'use strict';
S.sess=null;   // {role:'customer'|'merchant'|'admin', token, staff?:{id,name,perms}}
const E=s=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
const idem=()=>'k'+Date.now().toString(36)+Math.random().toString(36).slice(2,12);
const dt=ms=>ms?new Date(ms).toLocaleDateString('ar-LB',{year:'numeric',month:'short',day:'numeric'}):'—';
const sess=()=>S.sess&&S.sess.token;

// ---------- 1. server calls ----------
const DROP_M=['p_merchant_id'],DROP_A=['p_admin_id'],DROP_C=['p_phone'];
const MAP={
 merchant_wallet:['merchant_wallet_v2','merchant',DROP_M], merchant_update_page:['merchant_update_page_v2','merchant',DROP_M],
 merchant_request_info_change:['merchant_request_info_change_v2','merchant',DROP_M], merchant_transactions:['merchant_transactions_v2','merchant',DROP_M],
 merchant_topup_orders:['merchant_topup_orders_v2','merchant',DROP_M], merchant_submit_photo:['merchant_submit_photo_v2','merchant',DROP_M],
 merchant_set_redeem_pct:['merchant_set_redeem_pct_v2','merchant',DROP_M], merchant_set_offer_active:['merchant_set_offer_active_v2','merchant',DROP_M],
 merchant_request_manual_topup:['merchant_request_manual_topup_v2','merchant',DROP_M], merchant_offers:['merchant_offers_v2','merchant',DROP_M],
 merchant_notes_list:['merchant_notes_list_v2','merchant',DROP_M], merchant_gallery_delete:['merchant_gallery_delete_v2','merchant',DROP_M],
 merchant_gallery_add:['merchant_gallery_add_v2','merchant',DROP_M], merchant_delete_offer:['merchant_delete_offer_v2','merchant',DROP_M],
 merchant_create_topup_order:['merchant_create_topup_order_v2','merchant',DROP_M], merchant_add_offer:['merchant_add_offer_v2','merchant',DROP_M],
 customer_transactions:['customer_transactions_v2','customer',DROP_C], customer_notes_list:['customer_notes_list_v2','customer',DROP_C],
 customer_profile:['customer_profile_v2','customer',DROP_C],
 admin_update_text_settings:['admin_update_text_settings_v2','admin',DROP_A], admin_update_offer_image:['admin_update_offer_image_v2','admin',DROP_A],
 admin_topup_merchant:['admin_topup_merchant_v2','admin',DROP_A], admin_review_info_change:['admin_review_info_change_v2','admin',DROP_A],
 admin_warn_merchant:['admin_warn_merchant_v2','admin',DROP_A], admin_update_merchant_location:['admin_update_merchant_location_v2','admin',DROP_A],
 admin_update_category:['admin_update_category_v2','admin',DROP_A], admin_topup_orders:['admin_topup_orders_v2','admin',DROP_A],
 admin_set_merchant_status:['admin_set_merchant_status_v2','admin',DROP_A], admin_set_merchant_photo:['admin_set_merchant_photo_v2','admin',DROP_A],
 admin_set_merchant_category:['admin_set_merchant_category_v2','admin',DROP_A], admin_set_customer_status:['admin_set_customer_status_v2','admin',DROP_A],
 admin_set_category_active:['admin_set_category_active_v2','admin',DROP_A], admin_resolve_topup_order:['admin_resolve_topup_order_v2','admin',DROP_A],
 admin_reject_merchant_photo:['admin_reject_merchant_photo_v2','admin',DROP_A], admin_mark_order_collected:['admin_mark_order_collected_v2','admin',DROP_A],
 admin_list_merchants:['admin_list_merchants_v2','admin',DROP_A], admin_list_customers:['admin_list_customers_v2','admin',DROP_A],
 admin_list_all_offers:['admin_list_all_offers_v2','admin',DROP_A], admin_force_delete_merchant:['admin_force_delete_merchant_v2','admin',DROP_A],
 admin_force_delete_customer:['admin_force_delete_customer_v2','admin',DROP_A], admin_delete_offer:['admin_delete_offer_v2','admin',DROP_A],
 admin_delete_merchant:['admin_delete_merchant_v2','admin',DROP_A], admin_delete_customer:['admin_delete_customer_v2','admin',DROP_A],
 admin_approve_merchant_photo:['admin_approve_merchant_photo_v2','admin',DROP_A], admin_add_category:['admin_add_category_v2','admin',DROP_A]
};
// functions a staff session may reach (the server enforces it too); the rest are skipped quietly for staff
const STAFF_OK={merchant_transactions_v2:'history',merchant_scan_code:'sell',merchant_quote_v2:'sell',merchant_create_tx_v2:'sell',
  merchant_cancel_tx:'cancel',merchant_allowance_v2:'wallet',merchant_catalog_v2:'payments',merchant_payment_request_v2:'payments',
  merchant_payment_requests_v2:'payments',merchant_payment_cancel_v2:'payments',merchant_me_v2:'sell',session_logout:'sell'};
const CLOSED={merchant_requests:()=>[],merchant_close_request:()=>({ok:true}),create_transaction:()=>({ok:false,error:'امسح رمز الزبون من تطبيقه'})};
const LOGIN={customer_verify_pin:['customer_login','customer'],merchant_verify_pin:['merchant_login','merchant'],admin_verify_pin:['admin_login','admin']};
const ERRS={TP_FORBIDDEN:'هذه العملية غير مسموحة لهذا الحساب',TP_LEDGER_ONLY:'لا يمكن تعديل الرصيد بهذه الطريقة'};
const rawRpc=sbRpc;
async function call(fn,args,quiet){
  try{const{data,error}=await sb.rpc(fn,args);
    if(error){const m=String(error.message||'');
      if(m.indexOf('TP_SESSION_EXPIRED')===0){sessionLost();return null}
      const k=Object.keys(ERRS).find(x=>m.indexOf(x)===0);if(!quiet)toast(k?ERRS[k]:'خطأ: '+(m||error.hint||'').slice(0,120));return null}
    return data}
  catch(e){if(!quiet)toast('تعذّر الاتصال بالخادم: '+(e&&e.message?e.message:'تحقق من الإنترنت'));return null}}
let _lost=false;
function sessionLost(){if(_lost)return;_lost=true;S.sess=null;toast('انتهت الجلسة، سجّل الدخول من جديد');setTimeout(()=>{_lost=false;origLogout()},50)}
window.tpCall=call;
window.tpS=(fn,args,quiet)=>call(fn,Object.assign({p_session:sess()},args||{}),quiet);

sbRpc=async function(fn,args){args=args||{};
  // login: same screens, session from the server
  if(LOGIN[fn]){const[f,role]=LOGIN[fn];const a=fn==='admin_verify_pin'?{p_username:args.p_username,p_pin:args.p_pin,p_device:navigator.userAgent.slice(0,100)}:{p_phone:args.p_phone,p_pin:args.p_pin,p_device:navigator.userAgent.slice(0,100)};
    const r=await call(f,a);if(r&&r.ok&&r.session)S.sess={role,token:r.session,staff:null};return r}
  // registration: the old public function creates the account, then a normal login gives the session
  if(fn==='customer_register'||fn==='merchant_register'){const r=await rawRpc(fn,args);
    if(r&&!(r.ok===false)&&args.p_pin){const l=await call(fn==='customer_register'?'customer_login':'merchant_login',{p_phone:args.p_phone,p_pin:args.p_pin});if(l&&l.ok&&l.session)S.sess={role:fn==='customer_register'?'customer':'merchant',token:l.session,staff:null}}
    return r}
  if(fn==='decide_transaction'&&S.sess&&S.sess.role==='customer'){
    return call('customer_decide_tx_v2',{p_session:sess(),p_tx_id:args.p_tx_id,p_confirm:!!args.p_confirm,p_detail_hash:(S._dh||{})[args.p_tx_id]||null})}
  const m=MAP[fn];
  if(m&&S.sess&&S.sess.role===m[1]){
    const a=Object.assign({},args);m[2].forEach(k=>delete a[k]);a.p_session=sess();
    if(S.sess.staff&&!(m[0] in STAFF_OK&&S.sess.staff.perms.indexOf(STAFF_OK[m[0]])>=0))return null;   // not for this employee
    const r=await call(m[0],a);
    if(m[0]==='customer_transactions_v2'&&Array.isArray(r)){S._dh=S._dh||{};r.forEach(t=>{if(t.detailHash)S._dh[t.id]=t.detailHash})}
    if(m[0]==='merchant_transactions_v2'&&Array.isArray(r))r.forEach(t=>{t.phone=t.cref||'••'});
    if(m[0]==='merchant_set_redeem_pct_v2'&&r&&r.pending)return{ok:false,error:r.message};
    return r}
  if(S.sess&&S.sess.staff&&/^merchant_/.test(fn))return null;            // staff: no owner-only legacy calls
  if(S.sess&&CLOSED[fn])return CLOSED[fn]();                              // replaced by the purchase code: closed on the server
  return rawRpc(fn,args)};

const origLogout=logout;
logout=function(){const t=sess();S.sess=null;if(t)call('session_logout',{p_session:t},true);payClose();return origLogout()};

// ---------- 2. customer: «رمز الشراء» ----------
let payT=null,payPoll=null,payCode=null,payBusy=false;
function payClose(){clearInterval(payT);clearInterval(payPoll);payT=payPoll=null;payCode=null;const md=document.getElementById('payModal');if(md)md.remove()}
window.payClose=payClose;
window.payOpen=async function(){if(!S.sess||S.sess.role!=='customer'){toast('سجّل الدخول من جديد لعرض رمز الشراء');return}
  payClose();const md=document.createElement('div');md.className='modal';md.id='payModal';md.setAttribute('role','dialog');md.setAttribute('aria-modal','true');
  md.onclick=e=>{if(e.target===md)payClose()};md.innerHTML='<div class="sheet qrsSheet" id="paySheet"><h3>رمز الشراء</h3><p class="muted">جارٍ إنشاء الرمز…</p></div>';
  document.body.appendChild(md);await payIssue()};
async function payIssue(){const r=await tpS('customer_qr_issue');const box=document.getElementById('paySheet');if(!box)return;
  if(!r||!r.ok){box.innerHTML=`<h3>رمز الشراء</h3><div class="alert">${E((r&&r.message)||'تعذّر إنشاء الرمز')}</div><button class="btn ghost" onclick="payClose()">إغلاق</button>`;return}
  payCode={id:r.code_id,qr:r.qr,short:r.short,exp:Date.now()+r.ttl*1000};payDraw('live');
  clearInterval(payT);payT=setInterval(()=>{const el=document.getElementById('payLeft');if(!payCode)return;const s=Math.max(0,Math.round((payCode.exp-Date.now())/1000));if(el)el.textContent=Math.floor(s/60)+':'+String(s%60).padStart(2,'0');if(s<=0&&payCode.state==='live')payDraw('expired')},1000);
  clearInterval(payPoll);payPoll=setInterval(payStatus,2500)}
function payDraw(state,st){const box=document.getElementById('paySheet');if(!box||!payCode)return;payCode.state=state;
  if(state==='live')box.innerHTML=`<h3>رمز الشراء</h3><p class="muted">اعرض هذا الرمز على المحل عند الدفع. صالح لعملية واحدة.</p>
   <div style="background:#fff;border-radius:14px;padding:10px;display:inline-block">${qrSvg(payCode.qr,220)}</div>
   <p style="margin:8px 0 2px">أو أعطِ المحل هذا الرقم</p><div class="ltr" style="font-size:26px;font-weight:800;letter-spacing:3px;color:var(--navy)">${payCode.short.slice(0,4)}-${payCode.short.slice(4)}</div>
   <p class="muted">ينتهي خلال <b id="payLeft" class="ltr">5:00</b></p>
   <div class="card" style="text-align:right;margin:8px 0"><label class="muted">النقاط التي تريد استخدامها في هذه العملية (اختياري)</label><div class="qrsRow" style="margin:6px 0 0"><input id="payWantIn" inputmode="numeric" dir="ltr" placeholder="الحد المسموح" value="${payCode.want!=null?payCode.want:''}"><button class="btn ghost" onclick="payWant()">حفظ</button></div><p class="small muted" style="margin:4px 0 0">${payCode.want!=null?'سيُستخدم حتى '+fmt(payCode.want)+' نقطة':'إن تركته فارغاً يقترح المحل الحد المسموح، وتراجع أنت التفاصيل قبل الموافقة'}</p></div>
   <button class="btn ghost" onclick="payClose()">إغلاق</button>
   <p class="small qrsNote">لا تُخصم أي نقطة قبل أن توافق أنت على تفاصيل العملية.</p>`;
  else if(state==='expired')box.innerHTML=`<h3>انتهت صلاحية الرمز</h3><p class="muted">الرمز يصلح 5 دقائق فقط.</p><button class="btn blue" onclick="payIssueAgain()">رمز جديد</button><button class="btn ghost" style="margin-top:8px" onclick="payClose()">إغلاق</button>`;
  else if(state==='claimed')box.innerHTML=`<h3>${E(st.shop||'المحل')}</h3><p class="muted">مسح المحل رمزك ويحضّر العملية… انتظر قليلاً.</p><div class="chkc" style="background:var(--yellow);margin:10px auto">…</div><button class="btn ghost" onclick="payClose()">إغلاق</button>`;
  else if(state==='tx'){const t=st.tx;S._dh=S._dh||{};S._dh[t.id]=t.detailHash;payCode.tx=t;
   const rows=[['الفاتورة',usd(t.invoice)],...(t.disc?[['خصم العرض','-'+usd(t.disc)]]:[]),['النقاط المستخدمة',fmt(t.redeemPts)+' نقطة'],['المطلوب دفعه',usd(t.net)],['النقاط الجديدة',fmt(t.earn)+' نقطة']];
   box.innerHTML=`<h3>${E(t.mname||st.shop||'')}</h3><p class="muted">راجع التفاصيل ثم وافق. لا يتغيّر شيء قبل موافقتك.</p>
    <div class="card" style="text-align:right">${rows.map(([a,b])=>`<div class="row" style="padding:6px 0"><span class="muted">${a}</span><b>${b}</b></div>`).join('')}</div>
    <button class="btn ok" ${payBusy?'disabled':''} onclick="payDecide(true)">نعم، أؤكد</button><button class="btn bad" style="margin-top:8px" ${payBusy?'disabled':''} onclick="payDecide(false)">لا، ألغِ العملية</button>${repLink(JSON.stringify(t.id))}`}
  else if(state==='done')box.innerHTML=`<div class="chkc" style="background:${st.ok?'var(--ok)':'var(--bad)'};margin:6px auto">${st.ok?'✓':'✕'}</div><h3>${E(st.msg)}</h3><button class="btn blue" onclick="payClose()">تم</button>`}
window.payIssueAgain=()=>payIssue();
async function payStatus(){if(!payCode||payCode.state==='tx'||payCode.state==='done')return;const r=await tpS('customer_qr_status',{p_code_id:payCode.id},true);if(!r||!r.ok||!payCode)return;
  if(r.state==='tx'&&r.tx){payDraw('tx',r);if(navigator.vibrate)try{navigator.vibrate(60)}catch(e){}}
  else if(r.state==='claimed'&&payCode.state!=='claimed')payDraw('claimed',r);
  else if((r.state==='expired'||r.state==='superseded')&&payCode.state!=='expired')payDraw('expired')
  else if(r.state==='used')payDraw('done',{ok:true,msg:'تم البت في هذه العملية'})}
window.payDecide=async function(ok){if(payBusy||!payCode||!payCode.tx)return;payBusy=true;const t=payCode.tx;
  try{const r=await call('customer_decide_tx_v2',{p_session:sess(),p_tx_id:t.id,p_confirm:ok,p_detail_hash:ok?t.detailHash:null});
    if(r&&r.ok){clearInterval(payPoll);payDraw('done',{ok:ok,msg:ok?'تمت العملية بنجاح':'تم إلغاء العملية'});await syncCustomerData(S.phone);if(ok&&r.unlocked&&typeof showUnlock==='function')try{showUnlock(r.unlocked)}catch(e){}}
    else{payDraw('done',{ok:false,msg:(r&&r.message)||'تعذّر تنفيذ الطلب'});syncCustomerData(S.phone)}}
  finally{payBusy=false}};
// the pay-code button on the customer home, above Scan / Tripoli
const origHomeV=homeV;
homeV=function(c){const h=origHomeV.apply(this,arguments);if(!S.sess||S.sess.role!=='customer')return h;
  return h.replace('<div class="qrsRowHome">',`<div style="display:grid;grid-template-columns:2fr 1fr;gap:8px;margin:8px 0 0"><button type="button" class="btn blue" id="payBtn" style="margin:0;display:flex;align-items:center;justify-content:center;gap:8px" onclick="payOpen()">${QRS_IC} رمز الشراء</button><button type="button" class="btn ghost" id="ptsBtn" style="margin:0" onclick="custPointsOpen()">نقاطي</button></div><div class="qrsRowHome">`)};
// points view: batches with expiry
window.custPointsOpen=async function(){const r=await tpS('customer_points_v2');if(!r||!r.ok)return;
  const md=document.createElement('div');md.className='modal';md.id='ptsModal';md.onclick=e=>{if(e.target===md)md.remove()};
  const K={welcome:'هدية الترحيب',earn:'مشتريات',legacy:'رصيد سابق',adjust:'تعديل من الإدارة',mirror:'رصيد',refund:'استرجاع'};
  md.innerHTML=`<div class="sheet"><h3>نقاطي: ${fmt(r.points)}</h3>${r.next_expiry&&r.next_expiry.at?`<div class="ask">تنتهي ${fmt(r.next_expiry.points)} نقطة في ${dt(r.next_expiry.at)}</div>`:''}
   <div class="card">${r.batches.length?r.batches.map(b=>`<div class="row" style="padding:6px 0;border-bottom:1px solid var(--line)"><div><b>${fmt(b.remaining)}</b> <span class="muted">${K[b.kind]||''}${b.shop?' · '+E(b.shop):''}</span></div><span class="muted">${b.expires_at?'حتى '+dt(b.expires_at):'بلا انتهاء'}</span></div>`).join(''):'<p class="muted">لا نقاط صالحة حالياً</p>'}</div>
   <div id="ptsVip"></div><p class="small muted">النقاط المكتسبة صالحة 3 أشهر. عند الاستخدام تُصرف النقاط الأقرب انتهاءً أولاً.</p><button class="btn ghost" onclick="this.closest('.modal').remove()">إغلاق</button></div>`;
  document.body.appendChild(md);custVips().then(v=>{const el=document.getElementById('ptsVip');if(el&&v.length)el.innerHTML='<h3>👑 VIP</h3><div class="card">'+v.map(x=>`<div class="row" style="padding:4px 0"><span>${E(x.shop)}</span><span>حتى ${fmt(x.cap)} يومياً${x.next_cap?` · من ${E(x.next_from)}: ${fmt(x.next_cap)}`:''}</span></div>`).join('')+'</div>'})};

// ---------- 3. shop: sell by scanning the customer's code ----------
const origMfReset=mfReset;
mfReset=function(){origMfReset();S.mf.claim=null;S.mf.quote=null;S.mf.idem=idem();S.mf.codeIn=''};
mfReset();
const secureShop=()=>S.sess&&S.sess.role==='merchant';
window.mfClaim=async function(raw){raw=String(raw||'').trim();if(!raw)return toast('امسح رمز الزبون أو أدخل الرقم');
  const r=await tpS('merchant_scan_code',{p_code:raw});if(!r)return;
  if(!r.ok){S.mf.claim=null;render();return toast(r.message||'رمز غير صالح')}
  S.mf.claim={id:r.code_id,name:r.customer&&r.customer.first_name,photo:r.customer&&r.customer.photo,exp:r.claim_expires_at};S.mf.quote=null;scanClose();render()};
// camera reader for the customer's code (reuses the bundled jsQR loader)
let scT=null,scStream=null;
function scanClose(){clearInterval(scT);scT=null;if(scStream){scStream.getTracks().forEach(t=>t.stop());scStream=null}const md=document.getElementById('scModal');if(md)md.remove()}
window.scanClose=scanClose;
window.scanOpen=async function(){scanClose();const md=document.createElement('div');md.className='modal';md.id='scModal';md.onclick=e=>{if(e.target===md)scanClose()};
  md.innerHTML=`<div class="sheet qrsSheet"><h3>امسح رمز الزبون</h3><div class="qrsCam"><video id="scVideo" playsinline muted></video><span class="qrsFrame"></span></div><div id="scMsg" class="qrsMsg">جارٍ تشغيل الكاميرا…</div><button class="btn ghost" onclick="scanClose()">إغلاق</button></div>`;
  document.body.appendChild(md);const msg=t=>{const n=document.getElementById('scMsg');if(n)n.textContent=t};
  if(!window.isSecureContext||!(navigator.mediaDevices&&navigator.mediaDevices.getUserMedia)){msg('الكاميرا تعمل عبر رابط https فقط. أدخل الرقم المكوّن من 8 خانات بدلاً من ذلك.');return}
  try{const lib=await qrsLoadLib();if(!lib){msg('تعذّر تحميل قارئ الرمز. أدخل الرقم يدوياً.');return}
    scStream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'}},audio:false});const v=document.getElementById('scVideo');if(!v){scanClose();return}
    v.srcObject=scStream;await v.play();msg('وجّه الكاميرا نحو رمز الزبون');const cv=document.createElement('canvas'),ctx=cv.getContext('2d',{willReadFrequently:true});let busy=false;
    scT=setInterval(async()=>{if(busy||v.readyState<2||!v.videoWidth)return;busy=true;try{const w=Math.min(v.videoWidth,640),hh=Math.round(v.videoHeight*w/v.videoWidth);cv.width=w;cv.height=hh;ctx.drawImage(v,0,0,w,hh);
      const r=window.jsQR(ctx.getImageData(0,0,w,hh).data,w,hh,{inversionAttempts:'attemptBoth'});if(r&&r.data){if(/^TPPAY1\./.test(r.data)){clearInterval(scT);await mfClaim(r.data)}else msg('هذا ليس رمز شراء من تطبيق الزبون')}}catch(e){}finally{busy=false}},300)}
  catch(e){msg(e&&e.name==='NotAllowedError'?'لم يُسمح باستخدام الكاميرا. أدخل الرقم يدوياً.':'تعذّر فتح الكاميرا. أدخل الرقم يدوياً.')}};
function claimCard(){const f=S.mf,c=f.claim;
  if(c)return `<div class="card"><div class="row"><div style="display:flex;gap:10px;align-items:center">${c.photo?`<img src="${E(c.photo)}" alt="" style="width:44px;height:44px;border-radius:50%;object-fit:cover">`:'<span class="avatar">👤</span>'}<div><b>${E(c.name||'زبون')}</b><div class="muted">تم التحقق من رمز الزبون</div></div></div><button class="btn ghost sm" onclick="S.mf.claim=null;S.mf.quote=null;render()">تغيير</button></div><button class="btn ghost sm" style="color:var(--bad);margin-top:6px" onclick='reportTx(null,${JSON.stringify(c.id)})'>الشخص ليس صاحب الحساب؟ أبلغ</button></div>`;
  return `<div class="card"><label class="muted">رمز الزبون</label><button class="btn blue" style="display:flex;align-items:center;justify-content:center;gap:8px;margin:6px 0 10px" onclick="scanOpen()">${QRS_IC} امسح رمز الزبون</button>
   <div class="qrsRow"><input id="mfcode" inputmode="numeric" dir="ltr" placeholder="1234-5678" value="${E(f.codeIn)}" oninput="S.mf.codeIn=this.value"><button class="btn ghost" onclick="mfClaim(document.getElementById('mfcode').value)">تحقق</button></div>
   <p class="small muted" style="margin:0">يطلب الزبون «رمز الشراء» من تطبيقه. الرمز يصلح 5 دقائق ولمرة واحدة.</p></div>`}
const origMnewView=mnewView;
mnewView=function(m){if(!secureShop())return origMnewView(m);const f=S.mf;
  if(f.step===1){const h=origMnewView(m);const a=h.indexOf('<div class="card"><label class="muted">رقم الزبون'),b=h.indexOf('<h3>العرض (اختياري)</h3>');
    return a>0&&b>a?h.slice(0,a)+claimCard()+h.slice(b):h}
  if(f.step===2){const q=f.quote||{},ln='padding:9px 0;border-bottom:1px solid var(--line)';
    return `<div class="top"><button class="back" style="margin:0" onclick="if(!S.mf.sending){S.mf.step=1;render()}">${ic('back',26)}</button><h3 style="margin:0;font-size:18px">تفاصيل العملية</h3><div style="width:34px"></div></div>
    <div class="muted" style="margin-bottom:8px">${E((f.claim&&f.claim.name)||'زبون')}</div>
    ${q.ok===false?`<div class="alert">${E(q.message||q.error)}</div>`:''}
    <div class="card"><div class="row" style="${ln}"><span>قيمة الفاتورة</span><b style="font-size:20px">${usd(mfTotal())}</b></div>
    ${q.disc?`<div class="row" style="${ln}"><span>خصم العرض</span><b>-${usd(q.disc)}</b></div>`:''}
    <div class="row" style="${ln}"><div><div>النقاط المستخدمة</div><div class="muted">الحد الأقصى في هذه العملية ${fmt(q.redeem_max||0)} نقطة (رصيد الزبون، نسبة المحل، ورصيد قبول الفرع)</div></div><div style="display:flex;align-items:center;gap:10px"><b style="font-size:19px;color:var(--blue)">${fmt(q.redeem_pts||0)} نقطة</b><button class="sw ${f.redeem?'on':''}" aria-label="استخدام النقاط" onclick="S.mf.redeem=!S.mf.redeem;mfQuote()"></button></div></div>
    <div class="row" style="${ln}"><span>المبلغ المطلوب دفعه</span><b style="font-size:20px">${q.ok?usd(q.net):'—'}</b></div>
    <div class="row" style="padding:9px 0"><span>النقاط الجديدة للزبون</span><b style="font-size:19px;color:var(--ok)">${fmt(q.earn||0)} نقطة</b></div></div>
    ${q.error==='INSUFFICIENT'?`<div class="alert"><b>⚠️ رصيد المحفظة غير كافٍ لمنح هذه النقاط</b><button class="btn sm" style="margin-top:8px" onclick="S.resumeTx=1;openBuy(1)">اشحن المحفظة</button></div>`:''}
    <div class="prev" style="font-size:13px">يرى الزبون هذه التفاصيل نفسها ويوافق عليها من تطبيقه. لا تتحرك النقاط قبل موافقته.</div>
    ${f.sendErr?`<div class="alert" style="margin:10px 0">${E(f.sendErr)}</div>`:''}<button class="btn blue" ${f.sending||!q.ok?'disabled':''} onclick="mfSend()">${f.sending?'جارٍ الإرسال…':'إرسال للزبون'}</button>`}
  return origMnewView(m)};
window.mfQuote=async function(){const f=S.mf;if(!f.claim)return;const r=await tpS('merchant_quote_v2',{p_code_id:f.claim.id,p_invoice:mfTotal(),p_redeem:!!f.redeem,p_offer_id:f.offer||null});
  if(r&&r.error==='claim_expired'){f.claim=null;f.step=1;toast(r.message);return render()}
  f.quote=r?Object.assign({ok:r.ok!==false},r,r.ok===false&&!r.message?{message:r.error}:{}):{ok:false,message:'تعذّر الاتصال'};render()};
const origMfNext=mfNext;
mfNext=async function(){if(!secureShop())return origMfNext();const f=S.mf;
  if(!f.claim)return toast('امسح رمز الزبون أولاً');
  if(!f.items.every(i=>i.n.trim()&&parseFloat(i.p)>0&&parseInt(i.q)>0))return toast('أكمل اسم الصنف والسعر والكمية لكل صنف قبل المتابعة');
  if(!(mfTotal()>0))return toast('أدخل سعر صنف واحد على الأقل');
  f.step=2;await mfQuote()};
const origMfSend=mfSend;
mfSend=async function(){if(!secureShop())return origMfSend();const f=S.mf;if(f.sending||!f.claim)return;f.sending=true;f.sendErr=null;render({bg:true});
  const items=f.items.filter(i=>parseFloat(i.p)>0).map(i=>({n:i.n.trim()||'أصناف أخرى',q:parseInt(i.q)||1,p:parseFloat(i.p)}));let r;
  try{r=await tpS('merchant_create_tx_v2',{p_code_id:f.claim.id,p_invoice:mfTotal(),p_redeem:!!f.redeem,p_offer_id:f.offer||null,p_items:items,p_idem_key:f.idem})}finally{f.sending=false}
  if(!r){f.sendErr='لم نتمكن من التأكد من الإرسال. أعد المحاولة: لن تُسجَّل العملية مرتين.';return render({bg:true})}
  if(!r.ok){if(r.error==='claim_expired'||r.error==='used'){f.claim=null;f.step=1}else if(r.error==='allowance_changed'){await mfQuote()}render({bg:true});return toast(r.message||r.error)}
  await syncMerchantData(S.merchantId);f.txId=r.tx.id;f.step=3;render();window.scrollTo(0,0);toast('تم إرسال العملية إلى الزبون، بانتظار موافقته')};
// pending purchase cancelled by the shop with its session
window.mCancelTx=async function(id){const r=await tpS('merchant_cancel_tx',{p_tx_id:id});if(r&&r.ok){toast('تم إلغاء العملية');syncMerchantData(S.merchantId)}else if(r)toast('لم تعد العملية قيد الانتظار')};

// ---------- 4. shop: subscription, allowance, transfer requests, staff ----------
const PST={pending:'قيد المراجعة',approved:'معتمد',rejected:'مرفوض',cancelled:'ملغى'};
window.mPlanOpen=async function(){S.sub='b3plan';S.b3=S.b3||{};render();const[al,cat,reqs]=await Promise.all([tpS('merchant_allowance_v2',{},true),tpS('merchant_catalog_v2',{},true),tpS('merchant_payment_requests_v2',{},true)]);
  Object.assign(S.b3,{al,cat,reqs:reqs&&reqs.requests});render()};
function mPlanV(){const b=S.b3||{},al=b.al,cat=b.cat,top=`<div class="top"><button class="back" style="margin:0" onclick="S.sub=null;render()">${ic('back',26)}</button><h3 style="margin:0">الاشتراك ورصيد القبول</h3><div style="width:34px"></div></div>`;
  if(!al&&!cat)return top+'<p class="muted" style="text-align:center">جارٍ التحميل…</p>';
  const sel=b.sel||null;
  return top+(al?`<div class="card"><div class="row"><span>رصيد قبول النقاط المتبقي</span><b style="font-size:20px">${fmt(al.remaining)}</b></div><div class="row"><span class="muted">الحد الأقصى في العملية الواحدة</span><b>${fmt(al.per_purchase_max)}</b></div>${al.held?`<div class="row"><span class="muted">محجوز لعمليات بانتظار التأكيد</span><b>${fmt(al.held)}</b></div>`:''}
    ${al.subscription?`<div class="muted" style="margin-top:6px">الاشتراك الحالي حتى ${dt(al.subscription.period_end)}</div>`:'<div class="muted" style="margin-top:6px">لا يوجد اشتراك فعّال</div>'}
    <p class="small muted" style="margin:8px 0 0">يمكن للزبون استخدام حتى 70% من الرصيد المتبقي في العملية، وإذا بقي 10 نقاط أو أقل يُستخدم كلها. يُستهلك الأقرب انتهاءً أولاً.</p>
    ${(al.grants||[]).filter(g=>g.active).map(g=>`<div class="row" style="padding:5px 0;border-top:1px solid var(--line)"><span class="muted">${g.source==='subscription'?'اشتراك':g.source==='package'?'باقة':'تعديل'}</span><span>${fmt(g.remaining)} / ${fmt(g.initial)} · حتى ${dt(g.expires_at)}</span></div>`).join('')}</div>`:'')
  +(cat?`<h3>اشترِ أو جدّد</h3>${(cat.transfer_number||'').trim()?`<div class="card"><b>طريقة الدفع: تحويل يدوي</b><div class="ltr" style="display:block;text-align:left;font-size:18px;font-weight:800;margin:6px 0">${E(cat.transfer_number)}</div><div class="muted" style="white-space:pre-line">${E(cat.transfer_instructions)}</div></div>`:'<div class="alert">الدفع غير متاح حالياً</div>'}
    ${[...cat.plans.map(p=>({k:al&&al.subscription?'renewal':'subscription',code:p.code,t:p.title,price:p.price,cur:p.currency,d:`${fmt(p.allowance_pts)} نقطة قبول · ${p.period_months} شهر`})),...cat.packages.map(p=>({k:'package',code:p.code,t:p.title,price:p.price,cur:p.currency,d:`${fmt(p.points)} نقطة قبول · صالحة ${p.validity_days} يوماً`}))]
      .map(x=>`<button class="card row" style="width:100%;text-align:right;border:${sel&&sel.code===x.code&&sel.k===x.k?'2px solid var(--blue)':'0'}" onclick='S.b3.sel=${JSON.stringify({k:x.k,code:x.code,price:x.price,cur:x.cur,t:x.t})};render()'><div><b>${E(x.t)}</b><div class="muted">${x.d}</div></div><b>${usd(x.price)}</b></button>`).join('')||'<p class="muted">لا توجد اشتراكات أو باقات متاحة بعد</p>'}
    ${sel?`<div class="card"><b>${E(sel.t)} · ${usd(sel.price)}</b><p class="muted" style="margin:4px 0">حوّل المبلغ إلى الرقم أعلاه، ثم أدخل رقم مرجع التحويل كما يظهر في الإيصال. تراجع الإدارة التحويل وتعتمده.</p>
      <div class="field"><input id="b3ref" dir="ltr" placeholder="رقم مرجع التحويل" maxlength="64"></div><div class="field"><input id="b3ev" placeholder="ملاحظة أو رابط صورة الإيصال (اختياري)" maxlength="300"></div>
      <button class="btn blue" ${b.sending?'disabled':''} onclick="mPayReq()">إرسال طلب الدفع</button></div>`:''}`:'')
  +(b.reqs&&b.reqs.length?`<h3>طلباتي</h3><div class="card">${b.reqs.map(r=>`<div class="row" style="padding:6px 0;border-bottom:1px solid var(--line)"><div><b>${E(r.item.title)}</b><div class="muted">${usd(r.amount)} · مرجع <span class="ltr">${E(r.transfer_ref)}</span> · ${dt(r.created_at)}${r.decision_note?' · '+E(r.decision_note):''}</div></div><div><span class="pill">${PST[r.status]}</span>${r.status==='pending'?`<button class="btn ghost sm" onclick="mPayCancel('${r.id}')">إلغاء</button>`:''}</div></div>`).join('')}</div>`:'')}
window.mPayReq=async function(){const b=S.b3,sel=b.sel;const ref=(document.getElementById('b3ref').value||'').trim(),ev=(document.getElementById('b3ev').value||'').trim();
  if(ref.replace(/[^A-Za-z0-9]/g,'').length<4)return toast('أدخل رقم مرجع التحويل');b.sending=true;b.idem=b.idem||idem();
  const r=await tpS('merchant_payment_request_v2',{p_kind:sel.k,p_item_code:sel.code,p_transfer_ref:ref,p_evidence:ev||null,p_idem_key:b.idem});b.sending=false;
  if(!r)return render();if(!r.ok){render();return toast(r.message||r.error)}b.sel=null;b.idem=null;toast('تم إرسال الطلب، بانتظار مراجعة الإدارة');mPlanOpen()};
window.mPayCancel=async function(id){if(!confirm('إلغاء هذا الطلب؟'))return;const r=await tpS('merchant_payment_cancel_v2',{p_id:id});if(r&&r.ok)mPlanOpen()};
const PERMS=[['sell','البيع'],['cancel','إلغاء عملية'],['history','سجل العمليات'],['wallet','رصيد القبول'],['payments','الدفع والاشتراك']];
window.mStaffOpen=async function(){S.sub='b3staff';render();const r=await tpS('merchant_staff_list_v2');S.b3=S.b3||{};S.b3.staff=r&&r.staff;render()};
function mStaffV(){const st=(S.b3||{}).staff,top=`<div class="top"><button class="back" style="margin:0" onclick="S.sub=null;render()">${ic('back',26)}</button><h3 style="margin:0">الموظفون</h3><div style="width:34px"></div></div>`;
  if(!st)return top+'<p class="muted" style="text-align:center">جارٍ التحميل…</p>';
  return top+`<p class="muted">كل موظف يدخل برقمه ورمزه الخاص، ويعمل في هذا الفرع فقط وبحسب الصلاحيات.</p>`+st.map(s=>`<div class="card"><div class="row"><div><b>${E(s.name)}</b><div class="muted ltr">${E(s.phone)}</div></div><span class="pill ${s.status==='active'?'active':'frozen'}">${s.status==='active'?'فعّال':'موقوف'}</span></div>
   <div class="muted" style="margin-top:4px">${s.perms.map(p=>(PERMS.find(x=>x[0]===p)||[,p])[1]).join('، ')}</div>
   <div class="row" style="justify-content:flex-start;gap:6px;margin-top:8px"><button class="btn ghost sm" onclick='mStaffSave(${JSON.stringify(s.id)},${JSON.stringify(s.name)},${JSON.stringify(s.perms)},${s.status!=='active'})'>${s.status==='active'?'إيقاف':'تفعيل'}</button><button class="btn ghost sm" onclick='mStaffPin(${JSON.stringify(s.id)},${JSON.stringify(s.name)},${JSON.stringify(s.perms)})'>رمز جديد</button></div></div>`).join('')
  +`<h3>إضافة موظف</h3><div class="card"><div class="field"><input id="sfn" placeholder="الاسم"></div><div class="field"><input id="sfp" dir="ltr" inputmode="numeric" placeholder="رقم الهاتف (8 أرقام)"></div><div class="field"><input id="sfc" dir="ltr" type="password" inputmode="numeric" placeholder="رمز الدخول (4 إلى 6 أرقام)"></div>
   ${PERMS.map(([k,l])=>`<label class="chk"><input type="checkbox" class="sfperm" value="${k}" ${k==='sell'?'checked':''}> ${l}</label>`).join('')}<button class="btn blue" onclick="mStaffAdd()">إضافة</button></div>`}
window.mStaffAdd=async function(){const perms=[...document.querySelectorAll('.sfperm:checked')].map(x=>x.value);
  const r=await tpS('merchant_staff_save_v2',{p_id:null,p_name:$('#sfn').value,p_phone:norm($('#sfp').value),p_pin:$('#sfc').value,p_perms:perms,p_active:true});
  if(r&&r.ok){toast('تمت إضافة الموظف');mStaffOpen()}else if(r)toast({bad_phone:'رقم الهاتف غير صحيح',bad_pin:'الرمز من 4 إلى 6 أرقام',phone_taken:'هذا الرقم مستعمل',bad_name:'أدخل الاسم'}[r.error]||r.error)};
window.mStaffSave=async function(id,name,perms,active){const r=await tpS('merchant_staff_save_v2',{p_id:id,p_name:name,p_phone:null,p_pin:null,p_perms:perms,p_active:active});if(r&&r.ok)mStaffOpen()};
window.mStaffPin=async function(id,name,perms){const p=prompt('الرمز الجديد للموظف (4 إلى 6 أرقام):');if(!p)return;const r=await tpS('merchant_staff_save_v2',{p_id:id,p_name:name,p_phone:null,p_pin:p.trim(),p_perms:perms,p_active:true});if(r&&r.ok)toast('تم تغيير الرمز');else if(r)toast('الرمز من 4 إلى 6 أرقام')};
const origMerchantView=merchantView;
merchantView=function(){const m=M(S.merchantId);
  if(S.sub==='b3plan'||S.sub==='b3staff'||S.sub==='b3vip'){const body=S.sub==='b3plan'?mPlanV():S.sub==='b3vip'?mVipV():mStaffV();return `<div class="scr">${body}</div>${nav([['mhome','الرئيسية','home'],['mops','العمليات','list'],['moff','العروض','gift'],['macc','حسابي','user']])}`}
  let h=origMerchantView();
  if(secureShop()&&!S.sub&&(S.tab==='macc'||S.tab==='mhome')){const st=S.sess.staff,can=p=>!st||st.perms.indexOf(p)>=0;
    const cards=(can('wallet')||can('payments')?`<button class="card row" style="width:100%;text-align:right;border:0" onclick="mPlanOpen()"><span style="font-size:24px">💳</span><div style="flex:1"><b>الاشتراك ورصيد القبول</b><div class="muted" style="font-size:13px">رصيد قبول النقاط، الاشتراكات والباقات، طلبات الدفع</div></div></button>`:'')
      +(!st&&S.tab==='macc'?`<button class="card row" style="width:100%;text-align:right;border:0" onclick="mStaffOpen()"><span style="font-size:24px">👥</span><div style="flex:1"><b>الموظفون</b><div class="muted" style="font-size:13px">حسابات دخول للموظفين بصلاحيات محددة</div></div></button><button class="card row" style="width:100%;text-align:right;border:0" onclick="mVipOpen()"><span style="font-size:24px">👑</span><div style="flex:1"><b>زبائن VIP</b><div class="muted" style="font-size:13px">حد استبدال يومي خاص لزبائن فرعك</div></div></button>`:'')
      +(st?`<div class="ask">دخول موظف: <b>${E(st.name)}</b></div>`:'');
    const i=h.indexOf('<div class="scr">')+'<div class="scr">'.length;
    if(S.tab==='macc'||st)h=h.slice(0,i)+cards+h.slice(i)}
  return h};

// ---------- 5. staff login (from the login screen) ----------
const origLoginView=loginView;
loginView=function(){return origLoginView().replace(/<\/div>\s*$/,`<button class="btn ghost" style="margin-top:14px" onclick="staffLoginOpen()">دخول موظف في محل</button></div>`)};
window.staffLoginOpen=function(){const md=document.createElement('div');md.className='modal';md.id='stModal';md.onclick=e=>{if(e.target===md)md.remove()};
  md.innerHTML=`<div class="sheet"><h3>دخول موظف</h3><div class="field"><input id="stp" dir="ltr" inputmode="numeric" placeholder="رقم الهاتف"></div><div class="field"><input id="stc" dir="ltr" type="password" inputmode="numeric" placeholder="رمز الدخول"></div><button class="btn blue" onclick="staffLogin()">دخول</button><button class="btn ghost" style="margin-top:8px" onclick="this.closest('.modal').remove()">إغلاق</button></div>`;
  document.body.appendChild(md)};
window.staffLogin=async function(){const p=norm($('#stp').value),c=($('#stc').value||'').trim();if(!/^\d{8}$/.test(p)||!c)return toast('أدخل الرقم والرمز');
  const r=await call('staff_login',{p_phone:p,p_pin:c,p_device:navigator.userAgent.slice(0,100)});
  if(!r||!r.ok)return toast(r&&r.reason==='locked'?'محاولات كثيرة، حاول بعد 15 دقيقة':r&&r.reason==='frozen'?'هذا الحساب موقوف':'الرقم أو الرمز غير صحيح');
  const md=document.getElementById('stModal');if(md)md.remove();
  S.sess={role:'merchant',token:r.session,staff:r.staff};const m=hydrateMerchant(r.merchant);S.merchantId=m.id;S.phone=null;S.mode='merchant';S.tab='mhome';S.sub=null;S.screen='app';
  mfReset();render();syncMerchantData(m.id)};

// ---------- 6. Admin: payments, catalogue, engine settings, ledgers, audit ----------
const admP=()=>S.adminInfo&&S.adminInfo.is_primary;
const atop=t=>`<div class="top"><button class="back" style="margin:0" onclick="S.sub=null;render()">${ic('back',26)}</button><h3 style="margin:0">${t}</h3><div style="width:34px"></div></div>`;
window.aPayOpen=async function(st){S.sub='b3pay';S.b3a=S.b3a||{};S.b3a.pst=st||S.b3a.pst||'pending';render();const r=await tpS('admin_payment_requests_v2',{p_status:S.b3a.pst==='all'?null:S.b3a.pst});S.b3a.reqs=r&&r.requests;render()};
function aPayV(){const a=S.b3a||{},rs=a.reqs;
  return atop('طلبات الدفع (تحويل يدوي)')+`<div class="row" style="gap:6px;justify-content:flex-start;margin-bottom:8px">${['pending','approved','rejected','all'].map(s=>`<button class="btn sm ${a.pst===s?'blue':'ghost'}" onclick="aPayOpen('${s}')">${s==='all'?'الكل':PST[s]}</button>`).join('')}</div>`
  +(!rs?'<p class="muted">جارٍ التحميل…</p>':rs.length?rs.map(r=>`<div class="card"><div class="row"><div><b>${E(r.merchant&&r.merchant.name)}</b><div class="muted">${r.kind==='package'?'باقة':r.kind==='renewal'?'تجديد':'اشتراك'}: ${E(r.item.title)} · ${fmt(r.item.allowance_pts||r.item.points)} نقطة قبول</div></div><b>${usd(r.amount)}</b></div>
    <div class="muted">مرجع التاجر: <span class="ltr">${E(r.transfer_ref)}</span>${r.ref_used_before?` · <b style="color:var(--bad)">استُعمل هذا المرجع في ${r.ref_used_before} طلب آخر</b>`:''}</div>${r.evidence?`<div class="muted">ملاحظة: ${E(r.evidence)}</div>`:''}<div class="muted">${dt(r.created_at)} · <span class="pill">${PST[r.status]}</span>${r.decision_note?' · '+E(r.decision_note):''}</div>
    ${r.status==='pending'&&admP()?`<div style="border-top:1px solid var(--line);margin-top:8px;padding-top:8px"><p class="small muted" style="margin:0 0 6px">تحقّق من التحويل في حساب الاستلام، ثم اكتب المبلغ والمرجع كما رأيتهما أنت.</p>
     <div class="row" style="gap:6px"><div class="field" style="flex:1;margin:0"><input id="va-${r.id}" dir="ltr" inputmode="decimal" placeholder="المبلغ المستلم"></div><div class="field" style="flex:2;margin:0"><input id="vr-${r.id}" dir="ltr" placeholder="مرجع التحويل"></div></div>
     <div class="row" style="gap:6px;margin-top:8px;justify-content:flex-start"><button class="btn ok sm" onclick="aPayDecide('${r.id}',true)">اعتماد</button><button class="btn sm" style="background:var(--bad);color:#fff" onclick="aPayDecide('${r.id}',false)">رفض</button></div></div>`:''}</div>`).join(''):'<p class="muted">لا توجد طلبات</p>')}
window.aPayDecide=async function(id,ok){let r;
  if(ok){const amt=parseFloat(($('#va-'+id).value||'').replace(',','.')),ref=($('#vr-'+id).value||'').trim();if(!(amt>=0)||!ref)return toast('اكتب المبلغ والمرجع اللذين تحققت منهما');
    r=await tpS('admin_payment_decide_v2',{p_id:id,p_approve:true,p_verified_amount:amt,p_verified_ref:ref,p_note:null})}
  else{const n=prompt('سبب الرفض (يظهر للتاجر):');if(!n)return;r=await tpS('admin_payment_decide_v2',{p_id:id,p_approve:false,p_verified_amount:null,p_verified_ref:null,p_note:n})}
  if(!r)return;if(!r.ok)return toast(r.message||({already_decided:'تم البت في هذا الطلب من قبل',duplicate_ref:'هذا المرجع معتمد في طلب آخر',note_required:'اكتب سبب الرفض'}[r.error])||r.error);
  toast(ok?'تم الاعتماد وأُضيف رصيد القبول':'تم الرفض');aPayOpen()};
window.aCatOpen=async function(){S.sub='b3cat';render();S.b3a=S.b3a||{};S.b3a.cat=await tpS('admin_catalog_v2');render()};
function aCatV(){const c=(S.b3a||{}).cat;if(!c)return atop('الاشتراكات والباقات')+'<p class="muted">جارٍ التحميل…</p>';const dis=admP()?'':'disabled';
  return atop('الاشتراكات والباقات')+`<div class="alert" style="font-size:13px">القيم هنا تجريبية (مؤقتة) إلى أن تُعتمد الأسعار والكميات النهائية.</div>
  <h3>بيانات التحويل</h3><div class="card"><div class="field"><input id="ptn" dir="ltr" placeholder="رقم التحويل" value="${E(c.transfer_number)}" ${dis}></div><div class="field"><textarea id="pti" rows="3" placeholder="تعليمات الدفع للتاجر" style="width:100%;border:0;background:transparent;font:inherit" ${dis}>${E(c.transfer_instructions)}</textarea></div>${admP()?'<button class="btn blue sm" onclick="aPaySave()">حفظ</button>':''}</div>
  <h3>الاشتراكات</h3>${c.plans.map(p=>`<div class="card"><div class="row"><b>${E(p.title)}</b><span class="pill ${p.active?'active':'frozen'}">${p.active?'متاح':'مخفي'}</span></div><div class="muted">${E(p.code)} · ${p.tier?TIERS[p.tier].n:'كل الفئات'} · ${usd(p.price)} · ${fmt(p.allowance_pts)} نقطة · ${p.period_months} شهر${p.provisional?' · مؤقت':''}</div>${admP()?`<button class="btn ghost sm" onclick='aPlanForm(${JSON.stringify(p)})'>تعديل</button>`:''}</div>`).join('')||'<p class="muted">لا اشتراكات بعد</p>'}
  ${admP()?'<button class="btn ghost sm" onclick="aPlanForm(null)">+ اشتراك</button>':''}
  <h3>الباقات الإضافية</h3>${c.packages.map(p=>`<div class="card"><div class="row"><b>${E(p.title)}</b><span class="pill ${p.active?'active':'frozen'}">${p.active?'متاح':'مخفي'}</span></div><div class="muted">${E(p.code)} · ${usd(p.price)} · ${fmt(p.points)} نقطة · ${p.validity_days} يوماً${p.provisional?' · مؤقت':''}</div>${admP()?`<button class="btn ghost sm" onclick='aPkgForm(${JSON.stringify(p)})'>تعديل</button>`:''}</div>`).join('')||'<p class="muted">لا باقات بعد</p>'}
  ${admP()?'<button class="btn ghost sm" onclick="aPkgForm(null)">+ باقة</button>':''}`}
window.aPaySave=async function(){const r=await tpS('admin_pay_settings_v2',{p_transfer_number:$('#ptn').value,p_instructions:$('#pti').value});if(r&&r.ok){toast('تم الحفظ');aCatOpen()}};
function formModal(title,fields,onSave){const md=document.createElement('div');md.className='modal';md.id='b3form';md.onclick=e=>{if(e.target===md)md.remove()};
  md.innerHTML=`<div class="sheet"><h3>${title}</h3>${fields.map(f=>f.type==='check'?`<label class="chk"><input type="checkbox" id="bf-${f.k}" ${f.v?'checked':''}> ${f.l}</label>`:f.type==='select'?`<label class="muted">${f.l}</label><div class="field"><select id="bf-${f.k}" style="width:100%;border:0;background:transparent;font:inherit">${f.opts.map(o=>`<option value="${o[0]}" ${String(f.v??'')===o[0]?'selected':''}>${o[1]}</option>`).join('')}</select></div>`:`<label class="muted">${f.l}</label><div class="field"><input id="bf-${f.k}" dir="ltr" value="${E(f.v??'')}" ${f.ro?'readonly':''}></div>`).join('')}<button class="btn blue" id="bfSave">حفظ</button><button class="btn ghost" style="margin-top:8px" onclick="this.closest('.modal').remove()">إلغاء</button></div>`;
  document.body.appendChild(md);document.getElementById('bfSave').onclick=async()=>{const v={};fields.forEach(f=>{const el=document.getElementById('bf-'+f.k);v[f.k]=f.type==='check'?el.checked:el.value});if(await onSave(v))md.remove()}}
window.aPlanForm=function(p){p=p||{};formModal('اشتراك',[{k:'code',l:'الرمز (أحرف إنكليزية صغيرة وأرقام)',v:p.code,ro:!!p.code},{k:'title',l:'الاسم',v:p.title},{k:'tier',l:'فئة المحل',type:'select',v:p.tier||'',opts:[['','كل الفئات'],['small','صغير'],['medium','متوسط'],['large','كبير']]},{k:'price',l:'السعر ($)',v:p.price},{k:'pts',l:'نقاط القبول',v:p.allowance_pts},{k:'months',l:'المدة (أشهر)',v:p.period_months||1},{k:'active',l:'متاح للتجار',type:'check',v:!!p.active},{k:'prov',l:'قيمة مؤقتة',type:'check',v:p.provisional!==false}],
  async v=>{const r=await tpS('admin_plan_save_v2',{p_code:v.code.trim(),p_title:v.title,p_tier:v.tier||null,p_price:+v.price,p_allowance_pts:+v.pts,p_period_months:parseInt(v.months),p_active:v.active,p_provisional:v.prov,p_currency:'USD'});if(r&&r.ok){toast('تم الحفظ');aCatOpen();return true}if(r)toast('تحقق من القيم');return false})};
window.aPkgForm=function(p){p=p||{};formModal('باقة',[{k:'code',l:'الرمز',v:p.code,ro:!!p.code},{k:'title',l:'الاسم',v:p.title},{k:'price',l:'السعر ($)',v:p.price},{k:'pts',l:'نقاط القبول',v:p.points},{k:'days',l:'الصلاحية (أيام)',v:p.validity_days||30},{k:'active',l:'متاحة للتجار',type:'check',v:!!p.active},{k:'prov',l:'قيمة مؤقتة',type:'check',v:p.provisional!==false}],
  async v=>{const r=await tpS('admin_package_save_v2',{p_code:v.code.trim(),p_title:v.title,p_price:+v.price,p_points:+v.pts,p_validity_days:parseInt(v.days),p_active:v.active,p_provisional:v.prov,p_currency:'USD'});if(r&&r.ok){toast('تم الحفظ');aCatOpen();return true}if(r)toast('تحقق من القيم');return false})};
const ENG=[['tx_per_customer_branch_day','عدد العمليات لكل زبون في الفرع يومياً'],['points_valid_months','صلاحية النقاط المكتسبة (أشهر)'],['allowance_cap_pct','نسبة الحد من رصيد قبول الفرع (%)'],['allowance_small_threshold','رصيد صغير يُستخدم كله (نقاط)'],['sub_carryover_months','ترحيل رصيد الاشتراك (أشهر)'],
 ['tier_redeem_max_small','حد الاستبدال للعملية: صغير'],['tier_redeem_max_medium','حد الاستبدال للعملية: متوسط'],['tier_redeem_max_large','حد الاستبدال للعملية: كبير'],
 ['tier_redeem_pct_small','أقصى نسبة من الفاتورة (%): صغير'],['tier_redeem_pct_medium','أقصى نسبة من الفاتورة (%): متوسط'],['tier_redeem_pct_large','أقصى نسبة من الفاتورة (%): كبير'],
 ['daily_eligible_pts_small','سقف المشتريات المؤهلة يومياً (نقطة مرجعية): صغير'],['daily_eligible_pts_medium','… متوسط'],['daily_eligible_pts_large','… كبير'],
 ['earn_pct_min','أدنى نسبة مكافأة (%)'],['earn_pct_max','أعلى نسبة مكافأة (%)'],
 ['vip_max_small','عدد VIP الأقصى: صغير (تحدده الإدارة)'],['vip_max_medium','عدد VIP الأقصى: متوسط'],['vip_max_large','عدد VIP الأقصى: كبير'],
 ['legacy_points_valid_months','صلاحية الرصيد القديم (أشهر) — مؤقت'],['pay_pending_max','طلبات الدفع المفتوحة لكل فرع']];
window.aEngOpen=async function(){S.sub='b3eng';render();S.b3a=S.b3a||{};S.b3a.cat=await tpS('admin_catalog_v2');render()};
function aEngV(){const c=(S.b3a||{}).cat;if(!c)return atop('إعدادات النقاط والحدود')+'<p class="muted">جارٍ التحميل…</p>';const s=c.settings||{};
  return atop('إعدادات النقاط والحدود')+`<div class="card">${ENG.map(([k,l])=>`<div class="row" style="padding:6px 0;border-bottom:1px solid var(--line);gap:8px"><span style="flex:1;font-size:14px">${l}</span><div class="field" style="width:90px;margin:0"><input id="en-${k}" dir="ltr" inputmode="numeric" value="${E(s[k])}" ${admP()?'':'disabled'}></div>${admP()?`<button class="btn ghost sm" onclick="aEngSave('${k}')">حفظ</button>`:''}</div>`).join('')}</div>
  <p class="small muted">تقريب كسور نقاط المكافأة: للأسفل حالياً، وهو قرار غير محسوم بعد (مؤقت).</p>
  ${admP()?`<button class="btn ghost" onclick="aRunExpiry()">تشغيل انتهاء الصلاحيات الآن</button>`:''}`}
window.aEngSave=async function(k){const r=await tpS('admin_engine_setting_v2',{p_key:k,p_value:+$('#en-'+k).value});if(r&&r.ok){toast('تم الحفظ');aEngOpen()}else if(r)toast(r.error)};
window.aRunExpiry=async function(){const r=await tpS('admin_run_expiry_v2');if(r&&r.ok)toast(`انتهت صلاحية ${fmt(r.points_expired)} نقطة لدى ${r.customers} زبون، و${fmt(r.allowance_expired)} من رصيد القبول`)};
window.aAuditOpen=async function(){S.sub='b3audit';render();S.b3a=S.b3a||{};const r=await tpS('admin_audit_log_v2',{p_limit:200});S.b3a.audit=r&&r.log;render()};
function aAuditV(){const l=(S.b3a||{}).audit;return atop('سجل التدقيق')+(!l?'<p class="muted">جارٍ التحميل…</p>':`<div class="card">${l.map(x=>`<div style="padding:6px 0;border-bottom:1px solid var(--line)"><b>${E(x.action)}</b> <span class="muted">${E(x.role)} · ${E(x.target_type||'')} ${E(x.target||'')}</span><div class="muted small">${new Date(x.at).toLocaleString('ar-LB')}</div></div>`).join('')||'<p class="muted">فارغ</p>'}</div>`)}
window.aCustPts=async function(p){S.sub='b3cpts';S.b3a=S.b3a||{};S.b3a.cp={phone:p};render();const r=await tpS('admin_customer_points_v2',{p_phone:p});S.b3a.cp=Object.assign({phone:p},r||{});render()};
function aCustPtsV(){const c=(S.b3a||{}).cp||{};return atop('نقاط الزبون')+`<p class="ltr" style="text-align:center">+961 ${E(c.phone)}</p>`+(c.ok?`<div class="card"><div class="row"><span>الرصيد الصالح</span><b>${fmt(c.spendable)}</b></div></div>
  <div class="card">${c.batches.filter(b=>b.remaining>0).map(b=>`<div class="row" style="padding:5px 0;border-bottom:1px solid var(--line)"><span>${E(b.kind)} · ${fmt(b.remaining)}/${fmt(b.initial)}</span><span class="muted">${b.expires_at?dt(Date.parse(b.expires_at)):'بلا انتهاء'}</span></div>`).join('')||'<p class="muted">لا دفعات صالحة</p>'}</div>
  ${admP()?`<h3>تعديل يدوي</h3><div class="card"><div class="field"><input id="cpd" dir="ltr" inputmode="numeric" placeholder="+500 أو -200"></div><div class="field"><input id="cpn" placeholder="السبب (إلزامي)"></div><button class="btn blue sm" onclick="aCustAdj()">تنفيذ</button></div>`:''}
  <h3>الحركات</h3><div class="card">${c.movements.map(m=>`<div class="row" style="padding:4px 0"><span>${E(m.reason)}</span><b class="ltr">${m.delta>0?'+':''}${fmt(m.delta)}</b></div>`).join('')}</div>`:'<p class="muted">جارٍ التحميل…</p>')}
window.aCustAdj=async function(){const c=S.b3a.cp,d=parseInt($('#cpd').value),n=$('#cpn').value;if(!d||!n||n.trim().length<3)return toast('أدخل العدد والسبب');if(!confirm(`تعديل رصيد الزبون بمقدار ${d} نقطة؟`))return;
  const r=await tpS('admin_points_adjust_v2',{p_phone:c.phone,p_points:d,p_note:n});if(r&&r.ok){toast('تم');aCustPts(c.phone)}else if(r)toast(r.error==='insufficient'?'الرصيد غير كافٍ':r.error)};
window.aAllowOpen=async function(mid){S.sub='b3mallow';S.b3a=S.b3a||{};S.b3a.ma={mid};render();const r=await tpS('admin_merchant_allowance_v2',{p_merchant_id:mid});S.b3a.ma=Object.assign({mid},r||{});render()};
function aAllowV(){const a=(S.b3a||{}).ma||{},m=M(a.mid)||{};return atop('رصيد قبول: '+E(m.name||''))+(a.ok?`<div class="card"><div class="row"><span>المتبقي</span><b>${fmt(a.remaining)}</b></div><div class="row"><span class="muted">الحد للعملية</span><b>${fmt(a.per_purchase_max)}</b></div><div class="row"><span class="muted">محجوز</span><b>${fmt(a.held)}</b></div></div>
  <div class="card">${a.grants.map(g=>`<div class="row" style="padding:5px 0;border-bottom:1px solid var(--line)"><span>${g.source} ${E(g.plan||g.package||'')} · ${fmt(g.remaining)}/${fmt(g.initial)}</span><span class="muted">${dt(g.valid_from)} → ${dt(g.expires_at)}</span></div>`).join('')||'<p class="muted">لا رصيد</p>'}</div>
  ${admP()?`<h3>تعديل يدوي</h3><div class="card"><div class="field"><input id="mad" dir="ltr" inputmode="numeric" placeholder="+1000 أو -200"></div><div class="field"><input id="mav" dir="ltr" inputmode="numeric" placeholder="الصلاحية بالأيام (للإضافة)" value="30"></div><div class="field"><input id="man" placeholder="السبب (إلزامي)"></div><button class="btn blue sm" onclick="aAllowAdj()">تنفيذ</button></div>`:''}
  ${a.staff&&a.staff.length?`<h3>موظفو الفرع</h3><div class="card">${a.staff.map(s=>`<div class="row"><span>${E(s.name)}</span><span class="muted">${s.status} · ${s.perms.join(', ')}</span></div>`).join('')}</div>`:''}`:'<p class="muted">جارٍ التحميل…</p>')}
window.aAllowAdj=async function(){const a=S.b3a.ma,d=parseInt($('#mad').value),v=parseInt($('#mav').value),n=$('#man').value;if(!d||!n||n.trim().length<3)return toast('أدخل العدد والسبب');if(!confirm(`تعديل رصيد قبول الفرع بمقدار ${d} نقطة؟`))return;
  const r=await tpS('admin_allowance_adjust_v2',{p_merchant_id:a.mid,p_points:d,p_valid_days:d>0?v:null,p_note:n});if(r&&r.ok){toast('تم');aAllowOpen(a.mid)}else if(r)toast(r.error==='insufficient'?'الرصيد غير كافٍ':r.error)};
const origAdminView=adminView;
adminView=function(){const V={b3pay:aPayV,b3cat:aCatV,b3eng:aEngV,b3audit:aAuditV,b3cpts:aCustPtsV,b3mallow:aAllowV,b3rep:aRepV,b3pct:aPctV,b3bak:aBakV}[S.sub];
  if(V&&S.sess&&S.sess.role==='admin'){const sub=S.sub;S.sub=null;const h=origAdminView.apply(this,arguments);S.sub=sub;const k=h.indexOf('<div class="nav');
    const head=`<div class="top">${logo()}<button class="btn ghost sm" onclick="logout()">خروج</button></div>`;
    return `<div class="scr">${head}${V()}</div>`+(k>0?h.slice(k):'')}
  let h=origAdminView.apply(this,arguments);
  if(S.sess&&S.sess.role==='admin'){
    if(!S.sub&&(S.tab==='ao'||!S.tab)){const g=`<h3>النقاط والاشتراكات</h3><div class="card" style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
      <button class="btn ghost" onclick="aPayOpen('pending')">💳 طلبات الدفع</button><button class="btn ghost" onclick="aCatOpen()">📦 الاشتراكات والباقات</button>
      <button class="btn ghost" onclick="aEngOpen()">⚙️ إعدادات النقاط والحدود</button><button class="btn ghost" onclick="aAuditOpen()">🧾 سجل التدقيق</button><button class="btn ghost" style="grid-column:1/-1" onclick="aRepOpen()">🚩 البلاغات والتنبيهات</button><button class="btn ghost" onclick="aPctOpen()">٪ طلبات نسبة الاستبدال</button><button class="btn ghost" onclick="aBakOpen()">💾 النسخ الاحتياطية</button></div>`;
      const k=h.indexOf('<div class="nav');h=k>0?h.slice(0,h.lastIndexOf('</div>',k))+g+h.slice(h.lastIndexOf('</div>',k)):h}
    if(!S.sub&&S.tab==='am')h=h.replace(/onclick="openMerchantMap\('([0-9a-f-]{36})'\)">الخريطة<\/button>/g,(x,id)=>x+`<button class="btn ghost sm" style="padding:2px 8px" onclick="aAllowOpen('${id}')">رصيد القبول</button>`);
    if(!S.sub&&S.tab==='ac')h=h.replace(/<span class="ltr" style="font-weight:700">\+961 (\d{7,8})<\/span>/g,(x,p)=>x+` <button class="btn ghost sm" style="padding:1px 6px" onclick="aCustPts('${p}')">النقاط</button>`)}
  return h};

// ---------- 6b. complaints: report a purchase or a scanned code; Admin reviews reports and monitoring alerts ----------
const RREASON=[['not_my_purchase','ليست عمليتي'],['wrong_amount','المبلغ غير صحيح'],['not_account_owner','الشخص ليس صاحب الحساب'],['other','سبب آخر']];
window.reportTx=function(txId,codeId){const md=document.createElement('div');md.className='modal';md.id='repModal';md.onclick=e=>{if(e.target===md)md.remove()};
  md.innerHTML=`<div class="sheet"><h3>الإبلاغ عن مشكلة</h3><p class="muted">إذا كانت العملية بانتظار التأكيد تُلغى فوراً، وتراجع الإدارة البلاغ.</p>
   ${RREASON.map(([k,l],i)=>`<label class="chk"><input type="radio" name="rr" value="${k}" ${(codeId?k==='not_account_owner':i===0)?'checked':''}> ${l}</label>`).join('')}
   <div class="field"><input id="rrn" maxlength="300" placeholder="تفاصيل (اختياري)"></div>
   <button class="btn bad" id="rrGo">إرسال البلاغ</button><button class="btn ghost" style="margin-top:8px" onclick="this.closest('.modal').remove()">إلغاء</button></div>`;
  document.body.appendChild(md);
  document.getElementById('rrGo').onclick=async()=>{const reason=(document.querySelector('input[name=rr]:checked')||{}).value||'other';
    const r=await tpS('report_tx',{p_reason:reason,p_tx_id:txId||null,p_code_id:codeId||null,p_note:(document.getElementById('rrn').value||'').trim()||null});
    if(!r)return;md.remove();if(!r.ok)return toast(r.message||'تعذّر إرسال البلاغ');toast('تم إرسال البلاغ إلى الإدارة');payClose();
    if(S.mode==='customer')syncCustomerData(S.phone);else if(S.mode==='merchant'){mfReset();render();syncMerchantData(S.merchantId)}}};
const repLink=id=>`<button class="btn ghost sm" style="margin-top:6px;color:var(--bad)" onclick='reportTx(${id},null)'>ليست عمليتي؟ أبلغ</button>`;
const withReport=h=>(S.sess&&S.sess.role==='customer'&&typeof h==='string')?h.replace(/(onclick='decide\(("[0-9a-f-]{36}"),false\)'[^>]*>[^<]*<\/button>)/g,(x,a,id)=>a+repLink(id)):h;
const origPendingBanner=pendingBanner;pendingBanner=function(){return withReport(origPendingBanner.apply(this,arguments))};
const origPendOverlay=pendOverlay;pendOverlay=function(){return withReport(origPendOverlay.apply(this,arguments))};
const REV={reported:'بلاغ',alert_same_shop:'مشتريات متكررة في محل واحد',alert_merchant_rate:'عمليات كثيرة لمحل خلال ساعة',alert_customer_shops:'زبون في محلات كثيرة خلال ساعة',
  scan_failed:'رموز غير صالحة',decide_hash_mismatch:'تفاصيل تغيّرت قبل التأكيد',qr_issue_limited:'طلب رموز كثيرة'};
window.aRepOpen=async function(){S.sub='b3rep';S.b3a=S.b3a||{};S.b3a.feed=null;render();const r=await tpS('admin_security_feed_v2',{p_limit:200});S.b3a.feed=r;render()};
function aRepV(){const f=(S.b3a||{}).feed;if(!f)return atop('البلاغات والتنبيهات')+'<p class="muted">جارٍ التحميل…</p>';
  const rr=Object.fromEntries(RREASON),RS={open:'مفتوح',reviewed:'تمت المراجعة',dismissed:'مغلق'},reps=f.reports||[],ev=(f.events||[]).filter(e=>REV[e.event]).slice(0,60);
  return atop('البلاغات والتنبيهات')+`<h3>البلاغات (${reps.filter(r=>r.status==='open').length} مفتوح)</h3>`
  +(reps.length?reps.map(r=>`<div class="card"><div class="row"><b>${rr[r.reason]||E(r.reason)}</b><span class="pill">${RS[r.status]||E(r.status)}</span></div>
     <div class="muted">${r.role==='customer'?'من زبون':'من محل'} · ${new Date(r.at).toLocaleString('ar-LB')}${r.note?' · '+E(r.note):''}</div>
     ${r.status==='open'?`<div class="row" style="gap:6px;justify-content:flex-start;margin-top:8px"><button class="btn ok sm" onclick="aRepResolve('${r.id}','reviewed')">تمت المراجعة</button><button class="btn ghost sm" onclick="aRepResolve('${r.id}','dismissed')">إغلاق</button></div>`:''}</div>`).join(''):'<p class="muted">لا توجد بلاغات</p>')
  +`<h3>تنبيهات المراقبة</h3><div class="card">${ev.map(e=>`<div style="padding:6px 0;border-bottom:1px solid var(--line)"><b>${REV[e.event]}</b> <span class="muted">${e.mname?E(e.mname):''}</span><div class="muted small">${new Date(e.at).toLocaleString('ar-LB')}</div></div>`).join('')||'<p class="muted">لا تنبيهات</p>'}</div>`}
window.aRepResolve=async function(id,st){const n=prompt(st==='reviewed'?'ملاحظة للمُبلِّغ (اختياري):':'سبب الإغلاق (اختياري):');if(n===null)return;
  const r=await tpS('admin_resolve_report_v2',{p_report_id:id,p_status:st,p_note:n.trim()||null});if(r&&r.ok){toast('تم، وأُرسل إشعار للمُبلِّغ');aRepOpen()}};

// ---------- 6c. register 12-Nov: customer-chosen points, VIP (§16), lower % approval (§03), Admin rules + backups ----------
window.payWant=async function(){if(!payCode)return;const v=(document.getElementById('payWantIn')||{}).value;const n=v===''?null:parseInt(v,10);
  if(v!==''&&!(n>=0))return toast('اكتب عدد النقاط');const r=await tpS('customer_qr_set_redeem',{p_code_id:payCode.id,p_points:n});
  if(r&&r.ok){payCode.want=r.redeem_want;toast(n===null?'سيستخدم المحل الحد المسموح':'سيُستخدم حتى '+fmt(n)+' نقطة في هذه العملية');payDraw('live')}else if(r)toast(r.message||'تعذّر الحفظ')};
const VIPL=(n)=>n==null?'غير محدد':fmt(n);
window.mVipOpen=async function(){S.sub='b3vip';S.b3=S.b3||{};S.b3.vip=null;render();const[l,c]=await Promise.all([tpS('merchant_vip_list_v2'),tpS('merchant_vip_candidates_v2')]);S.b3.vip={l,c};render()};
function mVipV(){const v=(S.b3||{}).vip,top=`<div class="top"><button class="back" style="margin:0" onclick="S.sub=null;render()">${ic('back',26)}</button><h3 style="margin:0">زبائن VIP 👑</h3><div style="width:34px"></div></div>`;
  if(!v||!v.l)return top+'<p class="muted" style="text-align:center">جارٍ التحميل…</p>';const l=v.l,c=(v.c&&v.c.customers)||[];
  return top+`<div class="card"><div class="row"><span>عدد VIP الحالي</span><b>${l.count} / ${VIPL(l.limit)}</b></div><p class="small muted" style="margin:6px 0 0">سقف VIP يحلّ محل سقف الاستبدال العادي، وهو إجمالي يومي في فرعك ضمن عمليتين، مع حدود النسبة ورصيد القبول ورصيد الزبون. الزيادة فورية، والتخفيض من اليوم التالي.</p></div>
  <h3>الحاليون</h3>${l.vips.length?l.vips.map(x=>`<div class="card"><div class="row"><div><b>👑 ${E(x.name||'زبون')}</b> <span class="muted ltr">${E(x.cref)}</span><div class="muted">الحد اليومي ${fmt(x.cap)}${x.next_cap?` · من ${E(x.next_from)}: ${fmt(x.next_cap)}`:''}</div></div><button class="btn ghost sm" style="color:var(--bad)" onclick="mVipCancel('${x.id}')">إلغاء</button></div></div>`).join(''):'<p class="muted">لا يوجد</p>'}
  <h3>زبائن أتمّوا عملية في فرعك</h3>${c.length?c.map(x=>`<div class="card"><div class="row"><div><b>${x.vip_cap?'👑 ':''}${E(x.name||'زبون')}</b> <span class="muted ltr">${E(x.cref)}</span><div class="muted">${x.purchases} عملية${x.vip_cap?' · VIP '+fmt(x.vip_cap):''}</div></div><button class="btn ghost sm" onclick='mVipSet(${JSON.stringify(x.ref)},${x.vip_cap||0})'>${x.vip_cap?'تعديل الحد':'اجعله VIP'}</button></div></div>`).join(''):'<p class="muted">لا يوجد زبائن بعد</p>'}`}
window.mVipSet=async function(ref,cur){const p=prompt('الحد اليومي للنقاط (VIP):',cur||'');if(!p)return;const r=await tpS('merchant_vip_set_v2',{p_ref:ref,p_cap:parseInt(p,10)});
  if(r&&r.ok){toast(r.effective==='now'?'تم':'يسري التخفيض من '+r.effective);mVipOpen()}else if(r)toast(r.message||({bad_cap:'اكتب عدداً صحيحاً'}[r.error])||r.error)};
window.mVipCancel=async function(id){if(!confirm('إلغاء عضوية VIP لهذا الزبون؟'))return;const r=await tpS('merchant_vip_cancel_v2',{p_vip_id:id});if(r&&r.ok){toast('أُلغيت العضوية');mVipOpen()}};
window.aPctOpen=async function(){S.sub='b3pct';S.b3a=S.b3a||{};S.b3a.pct=null;render();const r=await tpS('admin_redeem_pct_requests_v2');S.b3a.pct=r&&r.requests;render()};
function aPctV(){const l=(S.b3a||{}).pct;return atop('طلبات نسبة استبدال أقل')+(!l?'<p class="muted">جارٍ التحميل…</p>':l.length?l.map(x=>`<div class="card"><b>${E(x.name)}</b><div class="muted">الفئة ${TIERS[x.tier]?TIERS[x.tier].n:E(x.tier)} (حتى ${x.tier_pct}%) · الحالية ${x.current??'—'}% · المطلوبة ${x.requested}% · VIP ${x.requested_vip}%</div>
  ${admP()?`<div class="row" style="gap:6px;justify-content:flex-start;margin-top:8px"><button class="btn ok sm" onclick="aPctDecide('${x.merchant_id}',true)">موافقة</button><button class="btn ghost sm" onclick="aPctDecide('${x.merchant_id}',false)">رفض</button></div>`:''}</div>`).join(''):'<p class="muted">لا توجد طلبات</p>')}
window.aPctDecide=async function(mid,ok){const r=await tpS('admin_review_redeem_pct_v2',{p_merchant_id:mid,p_approve:ok});if(r&&r.ok){toast('تم');aPctOpen()}};
window.aBakOpen=async function(){S.sub='b3bak';S.b3a=S.b3a||{};S.b3a.bak=null;render();S.b3a.bak=await tpS('admin_backup_list_v2');render()};
function aBakV(){const b=(S.b3a||{}).bak;return atop('النسخ الاحتياطية')+(!b?'<p class="muted">جارٍ التحميل…</p>':`<div class="card"><div class="row"><span>المسح الشامل</span><b style="color:var(--ok)">${b.wipe_enabled?'مفعّل ⚠️':'معطّل'}</b></div><p class="small muted" style="margin:6px 0 0">النسخة تشمل كل الجداول المرتبطة بالتجار والزبائن (دفتر النقاط، رصيد القبول، الاشتراكات، الدفعات، الموظفين، العمليات). الاسترجاع يتحقق من تطابق الأرصدة مع الدفتر قبل قبوله، ويقوم به صاحب المشروع فقط.</p>
  <button class="btn blue" style="margin-top:8px" onclick="aBakNow()">نسخة احتياطية الآن</button></div>
  <div class="card">${(b.copies||[]).map(x=>`<div style="padding:6px 0;border-bottom:1px solid var(--line)"><b class="ltr">${E(x.stamp)}</b> <span class="muted">${E(x.by)}</span><div class="muted small">${new Date(x.at).toLocaleString('ar-LB')} · ${x.tables} جدول · ${fmt(x.rows||0)} صف${x.has_ledger?' · مع دفتر النقاط':' · قبل دفتر النقاط'}${x.restored_at?' · استُرجعت':''}</div></div>`).join('')||'<p class="muted">لا توجد نسخ</p>'}</div>`)}
window.aBakNow=async function(){const r=await tpS('admin_backup_now_v2');if(r&&r.ok){toast('تمت النسخة '+r.stamp);aBakOpen()}else if(r)toast(r.message||r.error)};
window.custVips=async function(){const r=await tpS('customer_vips_v2',{},true);return (r&&r.vips)||[]};
// ---------- 7. the old purchase-by-phone / request paths are not offered with a session ----------
const origSendToMerchant=sendToMerchant;
sendToMerchant=function(id){if(S.sess&&S.sess.role==='customer'){toast('اعرض «رمز الشراء» على المحل ليمسحه ويحضّر العملية');return payOpen()}return origSendToMerchant.apply(this,arguments)};
const origCreateTx=createTx;
createTx=function(){if(secureShop())return Promise.resolve('امسح رمز الزبون من تطبيقه');return origCreateTx.apply(this,arguments)};
})();
