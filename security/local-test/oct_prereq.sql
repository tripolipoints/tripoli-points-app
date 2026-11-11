CREATE OR REPLACE FUNCTION public.merchant_reset_pin(p_phone text, p_new_pin text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $function$
begin
  if not exists (select 1 from public.merchants where phone = p_phone) then raise exception 'الحساب غير موجود'; end if;
  if p_new_pin is null or length(p_new_pin) <> 4 then raise exception 'رمز الحماية يجب أن يكون 4 أرقام'; end if;
  update public.merchants set pin_hash = crypt(p_new_pin, gen_salt('bf')) where phone = p_phone;
  return jsonb_build_object('ok', true);
end; $function$;
create or replace function public.list_merchants() returns jsonb language sql security definer as $$ select '[]'::jsonb $$;
