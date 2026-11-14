-- ROLLBACK for tp-logo-validate-v1.sql on Production (lqbhfkowqaqlgcrdybvv). Exact original definition read on
-- 2026-11-14 15:30 (identical to Staging's). Grants before the fix: anon, authenticated, postgres, service_role = EXECUTE
-- (CREATE OR REPLACE keeps them; re-check after rollback).
CREATE OR REPLACE FUNCTION public.merchant_set_logo(p_phone text, p_pin text, p_logo_url text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions'
AS $function$
declare r public.merchants; rl_key text := 'merchant:' || p_phone;
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.merchants where phone = p_phone;
  if r is null then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    perform public._rl_record_fail(rl_key);
    return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl_reset(rl_key);
  update public.merchants set logo_url = nullif(p_logo_url, '')
  where id = r.id returning * into r;
  return jsonb_build_object('ok', true, 'logo_url', r.logo_url);
end; $function$;
