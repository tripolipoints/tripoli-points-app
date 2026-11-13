-- Tripoli Points — G-1 ROLLBACK: puts back the original lines (the browser-supplied gift is trusted again).
begin;
do $r$
declare s text; d text; n int := 0;
  old1 text := $o$  nm := coalesce(p_name, 'زبون جديد');$o$;
  new1 text := $n$  nm := coalesce(p_name, 'زبون جديد');
  /* G-1: gift from the server settings (Admin «هدية الترحيب»), never from the browser */
  p_welcome_bonus := coalesce((select case when value ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then greatest(0, trim(value)::numeric) end
                                 from public.app_text_settings where key = 'welcome_bonus'), 0);
  p_welcome_days  := coalesce((select case when value ~ '^\s*[0-9]+\s*$' then least(trim(value)::int, 3650) end
                                 from public.app_text_settings where key = 'welcome_days'), 0);$n$;
begin
  foreach s in array array['customer_register(text,text,text,numeric,integer,text)', 'customer_register(text,text,text,numeric,integer)'] loop
    continue when to_regprocedure('public.' || s) is null;
    d := pg_get_functiondef(('public.' || s)::regprocedure);
    if position(new1 in d) > 0 then execute replace(d, new1, old1); n := n + 1; end if;
  end loop;
  raise notice 'G-1 rolled back on % function(s)', n;
end $r$;
commit;
