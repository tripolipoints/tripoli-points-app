-- Tripoli Points — G-1: the welcome gift comes from the server settings, never from the browser. v1.0 · 2026-11-13
-- Uses the existing Admin «هدية الترحيب» settings unchanged (app_text_settings.welcome_bonus / welcome_days, edited
-- by the primary Admin in the dashboard; latest value 3000 points). Nothing is recreated or duplicated.
-- Change: in customer_register (6- and 5-argument versions) the two gift arguments sent by the browser are replaced,
-- at the start of the function, by the server settings. Everything else is unchanged: one account per phone (no
-- second gift), the gift note, welcome_remain / welcome_exp = the original validity of that gift, the expiry rule.
-- The browser keeps sending the arguments (no app change needed); their values are simply ignored.
-- Guards: target line must occur exactly once per function; already-patched functions are skipped.
begin;
do $g1$
declare s text; d text; n int; done int := 0;
  old1 text := $o$  nm := coalesce(p_name, 'زبون جديد');$o$;
  new1 text := $n$  nm := coalesce(p_name, 'زبون جديد');
  /* G-1: gift from the server settings (Admin «هدية الترحيب»), never from the browser */
  p_welcome_bonus := coalesce((select case when value ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then greatest(0, trim(value)::numeric) end
                                 from public.app_text_settings where key = 'welcome_bonus'), 0);
  p_welcome_days  := coalesce((select case when value ~ '^\s*[0-9]+\s*$' then least(trim(value)::int, 3650) end
                                 from public.app_text_settings where key = 'welcome_days'), 0);$n$;
begin
  foreach s in array array['customer_register(text,text,text,numeric,integer,text)', 'customer_register(text,text,text,numeric,integer)'] loop
    if to_regprocedure('public.' || s) is null then raise notice 'G-1: % not present, skipped', s; continue; end if;
    d := pg_get_functiondef(('public.' || s)::regprocedure);
    if position('/* G-1:' in d) > 0 then raise notice 'G-1: % already patched, skipped', s; continue; end if;
    n := (length(d) - length(replace(d, old1, ''))) / length(old1);
    if n <> 1 then raise exception 'G-1 STOP (nothing changed): target line found % times in %', n, s; end if;
    execute replace(d, old1, new1);
    done := done + 1;
  end loop;
  raise notice 'G-1 applied to % function(s): welcome gift = server settings (now % points, % days)', done,
    (select value from public.app_text_settings where key = 'welcome_bonus'), (select value from public.app_text_settings where key = 'welcome_days');
end $g1$;
commit;
