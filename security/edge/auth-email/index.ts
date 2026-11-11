// Tripoli Points — Edge Function «auth-email» (STAGING first) · prepared 2026-11-11 · NOT DEPLOYED
// Sends the verification / PIN-recovery e-mails. All checks, limits and codes live in the database (tp-auth-email-v1.sql);
// this function only: calls the service_role-only _email_*_start functions, puts the code + link in an e-mail, reports
// the send result, and returns to the app the masked address — never the code or the link.
//
// Secrets (Supabase → Edge Functions → Secrets), per project:
//   EMAIL_API_KEY      API key of the e-mail provider (Resend by default)
//   EMAIL_FROM         e.g. "Tripoli Points <no-reply@mail.tripolipoints.com>"  (domain verified at the provider)
//   APP_URL            site that opens the links, e.g. https://<staging-site>.netlify.app   (no trailing slash)
//   ALLOWED_ORIGINS    comma-separated origins allowed to call this function (the same site, plus localhost for tests)
//   EMAIL_PROVIDER     "resend" (default) or "log" (Staging dry run: logs instead of sending — never in Production)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SB_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const API_KEY = Deno.env.get("EMAIL_API_KEY") ?? "";
const FROM = Deno.env.get("EMAIL_FROM") ?? "";
const APP_URL = (Deno.env.get("APP_URL") ?? "").replace(/\/$/, "");
const PROVIDER = Deno.env.get("EMAIL_PROVIDER") ?? "resend";
const ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? APP_URL).split(",").map((s) => s.trim()).filter(Boolean);

function cors(origin: string | null) {
  const ok = origin && ORIGINS.includes(origin);
  return {
    "Access-Control-Allow-Origin": ok ? origin! : ORIGINS[0] ?? "",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}
const json = (body: unknown, origin: string | null, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors(origin), "Content-Type": "application/json" } });

const SUBJECT: Record<string, string> = {
  register: "رمز تأكيد بريدك في Tripoli Points",
  add_email: "تأكيد بريدك في Tripoli Points",
  reset_pin: "استرجاع رمز الحماية في Tripoli Points",
};
const LEAD: Record<string, string> = {
  register: "أهلاً بك! لإكمال تسجيلك، اكتب هذا الرمز في التطبيق:",
  add_email: "لتأكيد بريدك وحماية حسابك، اكتب هذا الرمز في التطبيق:",
  reset_pin: "طلبتَ تعيين رمز حماية جديد. اكتب هذا الرمز في التطبيق:",
};

function mail(purpose: string, code: string, link: string, ttl: number) {
  const url = `${APP_URL}/#tpmail=${purpose}.${link}`;
  const btn = purpose === "reset_pin" ? "تعيين رمز جديد" : "تأكيد البريد";
  const warn = purpose === "reset_pin"
    ? "إن لم تطلب ذلك، تجاهل الرسالة: رمزك الحالي لم يتغيّر. لا تشارك هذا الرمز مع أحد، ولن يطلبه منك فريق Tripoli Points أبداً."
    : "إن لم تطلب ذلك، تجاهل الرسالة. لا تشارك هذا الرمز مع أحد.";
  const html = `<!doctype html><html lang="ar" dir="rtl"><body style="margin:0;background:#f4f6fb;font-family:Tahoma,Arial,sans-serif;color:#0c2a6b">
<div style="max-width:480px;margin:0 auto;padding:28px 20px;text-align:center">
<h2 style="margin:0 0 12px">Tripoli Points</h2>
<p style="font-size:16px;line-height:1.7;margin:0 0 16px">${LEAD[purpose]}</p>
<div style="font-size:34px;letter-spacing:8px;font-weight:bold;direction:ltr;background:#fff;border-radius:12px;padding:14px 0;margin:0 0 18px">${code}</div>
<p style="margin:0 0 18px">أو اضغط الزر من هذا الهاتف:</p>
<a href="${url}" style="display:inline-block;background:#0c2a6b;color:#fff;text-decoration:none;padding:12px 26px;border-radius:10px;font-size:16px">${btn}</a>
<p style="font-size:13px;color:#667;line-height:1.7;margin:22px 0 0">صالح ${ttl} دقيقة ولمرة واحدة. ${warn}</p>
</div></body></html>`;
  const text = `${LEAD[purpose]}\n\n${code}\n\n${btn}: ${url}\n\nصالح ${ttl} دقيقة ولمرة واحدة. ${warn}`;
  return { html, text };
}

async function send(to: string, purpose: string, code: string, link: string, ttl: number): Promise<{ ok: boolean; id?: string }> {
  const { html, text } = mail(purpose, code, link, ttl);
  if (PROVIDER === "log") { console.log(`[dry-run] ${purpose} → ${to}`); return { ok: true, id: "dry-run" }; }
  if (!API_KEY || !FROM || !APP_URL) return { ok: false };
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [to], subject: SUBJECT[purpose], html, text }),
  });
  const j = await r.json().catch(() => null);
  return { ok: r.ok, id: j?.id };
}

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (req.method !== "POST") return json({ ok: false, error: "method" }, origin, 405);
  if (origin && !ORIGINS.includes(origin)) return json({ ok: false, error: "origin" }, origin, 403);

  let b: Record<string, unknown>;
  try { b = await req.json(); } catch { return json({ ok: false, error: "bad_request" }, origin, 400); }
  // the app user's IP, forwarded to the database (trusted there only on service_role calls) for the per-IP limits
  const ip = (req.headers.get("cf-connecting-ip") ?? req.headers.get("x-forwarded-for")?.split(",")[0] ?? "").trim();
  const db = createClient(SB_URL, SERVICE_KEY, { global: { headers: ip ? { "x-tp-client-ip": ip } : {} } });

  const s = (k: string) => (typeof b[k] === "string" ? (b[k] as string) : null);
  let rpc: { fn: string; args: Record<string, unknown> };
  switch (b.action) {
    case "register_start":
      rpc = { fn: "_email_register_start", args: { p_role: s("role"), p_phone: s("phone"), p_pin: s("pin"), p_email: s("email"),
        p_terms_version: s("terms_version"), p_data: (b.data && typeof b.data === "object") ? b.data : {} } };
      break;
    case "register_resend": rpc = { fn: "_email_register_resend", args: { p_pending_id: s("pending_id") } }; break;
    case "email_add_start": rpc = { fn: "_email_add_start", args: { p_session: s("session"), p_email: s("email"), p_pin: s("pin") } }; break;
    case "pin_reset_start": rpc = { fn: "_email_reset_start", args: { p_role: s("role"), p_phone: s("phone") } }; break;
    default: return json({ ok: false, error: "bad_request" }, origin, 400);
  }

  const { data, error } = await db.rpc(rpc.fn, rpc.args);
  if (error) {
    const expired = String(error.message ?? "").includes("TP_SESSION_EXPIRED");
    return json({ ok: false, error: expired ? "session_expired" : "server", message: expired ? "انتهت جلستك. سجّل الدخول من جديد" : "تعذّر الطلب، حاول بعد قليل" }, origin);
  }
  if (!data?.ok) return json(data ?? { ok: false, error: "server" }, origin);   // refusals carry their own Arabic message

  const sent = await send(data.email, data.purpose, data.code, data.link_token, data.ttl_min).catch(() => ({ ok: false }));
  await db.rpc("_email_mark_sent", { p_token_id: data.token_id, p_ok: sent.ok, p_provider_id: sent.id ?? null });
  if (!sent.ok) return json({ ok: false, error: "send_failed", message: "تعذّر إرسال الرسالة. حاول بعد قليل" }, origin);

  // never the code or the link: only what the screen needs
  return json({ ok: true, purpose: data.purpose, masked: data.masked, domain: String(data.email).split("@")[1],
    pending_id: data.pending_id ?? null, ttl_min: data.ttl_min, resend_after: 60 }, origin);
});
