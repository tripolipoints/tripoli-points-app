// Regression test for the stored-XSS fix in tpStoreLogoHtml (run: node security/xss-logo/logo-xss-test.js)
const src=require('fs').readFileSync(__dirname+'/../../index.html','utf8');
const pick=n=>{const i=src.indexOf('const '+n+'=');return src.slice(i,src.indexOf('\n',src.indexOf('\n',i)+1)>0&&n==='tpSafeImgSrc'?src.indexOf('const tpStoreLogoSrc',i):src.indexOf('\n',i))};
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));const PIN_T='pin.png';
eval(['tpSafeImgSrc','tpStoreLogoSrc','tpStoreLogoHtml'].map(pick).join('\n').replace(/const /g,'var '));
const cases=[
 ['x" onerror="alert(1)" data-a="',false],['javascript:alert(1)',false],['data:text/html;base64,PHNjcmlwdD4=',false],
 ['http://evil.example/a.png',false],['https://a.example/x.png" onload="x',false],["https://a.example/x'.png",false],
 ['https://lqbhfkowqaqlgcrdybvv.supabase.co/storage/v1/object/public/a/logo.png',true],['data:image/jpeg;base64,/9j/4AAQSkZJRg==',true],['',false],[null,false]];
let ok=0;for(const [v,keep] of cases){const h=tpStoreLogoHtml({name:'x',logo:v});const injected=/src="[^"]*"\s+on|javascript:|text\/html/i.test(h);
 const kept=!h.includes('src="pin.png"');const pass=!injected&&kept===keep;ok+=pass;if(!pass)console.log('FAIL',v,h)}
console.log(`${ok}/${cases.length} passed`);process.exit(ok===cases.length?0:1);
