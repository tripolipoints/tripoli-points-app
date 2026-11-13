-- Tripoli Points — C-1 ROLLBACK: puts the two original lines back (expired gifts become spendable again).
begin;
do $rb$
declare f regprocedure; d text;
  old1 text := 'avail_pts := greatest(0, c.points);';
  new1 text := 'avail_pts := greatest(0, c.points - case when c.welcome_exp is not null and c.welcome_exp < now() then coalesce(c.welcome_remain,0) else 0 end); /* C-1 */';
  old2 text := 'update public.customers set points = points + t.earn - t.redeem_pts where phone = t.customer_phone;';
  new2 text := 'if t.redeem_pts > 0 and t.redeem_pts > (select greatest(0, c.points - case when c.welcome_exp is not null and c.welcome_exp < now() then coalesce(c.welcome_remain,0) else 0 end) from public.customers c where c.phone = t.customer_phone) then raise exception ''TP_C1: the points to be spent include an expired welcome gift'' using errcode = ''P0001''; end if; /* C-1 */
    update public.customers set points = points + t.earn - t.redeem_pts where phone = t.customer_phone;';
begin
  f := 'public.create_transaction(uuid,text,numeric,boolean,uuid,jsonb)'::regprocedure; d := pg_get_functiondef(f);
  if position(new1 in d) > 0 then execute replace(d, new1, old1); end if;
  f := 'public.decide_transaction(uuid,boolean)'::regprocedure; d := pg_get_functiondef(f);
  if position(new2 in d) > 0 then execute replace(d, new2, old2); end if;
  if position('/* C-1 */' in pg_get_functiondef('public.create_transaction(uuid,text,numeric,boolean,uuid,jsonb)'::regprocedure) || pg_get_functiondef('public.decide_transaction(uuid,boolean)'::regprocedure)) > 0
    then raise exception 'C-1 ROLLBACK STOP: patch marker still present'; end if;
  raise notice 'C-1 rolled back';
end $rb$;
commit;
