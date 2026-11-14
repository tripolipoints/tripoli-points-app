-- Stored-XSS fix, server side: merchant_set_logo accepts only '' (clear), an https URL without quotes/spaces/angle
-- brackets/backslashes, or a base64 raster data:image (png/jpeg/webp/gif, ≤ 1.5 MB). Same signature, PIN check and lock.
create or replace function public.merchant_set_logo(p_phone text, p_pin text, p_logo_url text)
 returns jsonb language plpgsql security definer set search_path to 'public', 'extensions'
as $function$
declare r public.merchants; rl_key text := 'merchant:' || p_phone; u text := btrim(coalesce(p_logo_url, ''));
begin
  if public._rl_locked(rl_key) then return jsonb_build_object('ok', false, 'reason', 'locked'); end if;
  select * into r from public.merchants where phone = p_phone;
  if r is null then perform public._rl_record_fail(rl_key); return jsonb_build_object('ok', false, 'reason', 'wrong_pin'); end if;
  if r.pin_hash is null or crypt(p_pin, r.pin_hash) <> r.pin_hash then
    perform public._rl_record_fail(rl_key); return jsonb_build_object('ok', false, 'reason', 'wrong_pin');
  end if;
  perform public._rl_reset(rl_key);
  if u <> '' and not (
       (length(u) <= 2048 and u ~ '^https://[^\s"''<>`\\]+$')
    or (length(u) <= 1500000 and u ~* '^data:image/(png|jpe?g|webp|gif);base64,[A-Za-z0-9+/=]+$')) then
    return jsonb_build_object('ok', false, 'error', 'invalid_logo', 'message', 'رابط الشعار غير مقبول');
  end if;
  update public.merchants set logo_url = nullif(u, '') where id = r.id returning * into r;
  return jsonb_build_object('ok', true, 'logo_url', r.logo_url);
end; $function$;
