// Tripoli Points — «فتح البريد» button (for the phase-2 app; prepared 2026-11-11, not in index.html yet)
// After the Edge Function answers {ok:true, masked, domain}, the screen shows «أرسلنا رمزاً إلى s•••@gmail.com»,
// six code boxes, «فتح البريد», «إعادة الإرسال» (after 60 s) and «تغيير البريد».
// The button opens the provider's inbox for the address domain; web inbox links open the installed mail app on most
// phones (Gmail / Outlook app links). For unknown domains the button is hidden and the text says «افتح تطبيق البريد».
// The code is typed in the app, so the session stays in the same app (an installed home-screen app and the phone
// browser keep separate storage). The e-mail link also works, on any device.
function tpOpenMailUrl(domain) {
  const d = String(domain || '').toLowerCase();
  const isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent);
  if (['gmail.com', 'googlemail.com'].includes(d)) return 'https://mail.google.com/mail/u/0/#inbox';
  if (['outlook.com', 'hotmail.com', 'live.com', 'msn.com', 'outlook.sa', 'hotmail.fr'].includes(d)) return 'https://outlook.live.com/mail/0/inbox';
  if (['yahoo.com', 'ymail.com', 'yahoo.fr'].includes(d)) return 'https://mail.yahoo.com/';
  if (['icloud.com', 'me.com', 'mac.com'].includes(d)) return isIOS ? 'message://' : 'https://www.icloud.com/mail';
  if (['proton.me', 'protonmail.com'].includes(d)) return 'https://mail.proton.me/';
  return null;
}
function tpOpenMail(domain) {
  const u = tpOpenMailUrl(domain);
  if (!u) return false;
  if (u.startsWith('message://')) { location.href = u; return true; }
  window.open(u, '_blank', 'noopener');
  return true;
}
// Links in the e-mail open APP_URL/#tpmail=<purpose>.<link>; the app reads the fragment once, removes it from the
// address bar, then calls register_confirm(p_link) / email_link_confirm(p_link) / shows the new-PIN form for
// pin_reset_confirm(p_link). The fragment is never sent to a server log.
function tpReadMailLink() {
  const m = /^#tpmail=(register|add_email|reset_pin)\.([A-Za-z0-9_-]{40,100})$/.exec(location.hash);
  if (!m) return null;
  history.replaceState(null, '', location.pathname + location.search);
  return { purpose: m[1], link: m[2] };
}
