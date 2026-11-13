-- Tripoli Points — C-1: expired welcome-gift points can no longer be spent. Version 1.0 · 2026-11-13.
-- PREPARED AND TESTED LOCALLY ONLY. Not applied anywhere. Separate approval per environment.
--
-- Changes exactly two lines of server code (everything else in both functions is untouched):
--   create_transaction: spendable = points − (welcome_remain if the gift has expired), never below 0.
--                       The 70% legacy customer cap and every other limit then apply to this spendable amount.
--   decide_transaction: at confirmation, if the points to be spent exceed what is spendable now (the gift expired
--                       during the 5-minute window), the confirmation is refused and nothing changes; the purchase
--                       stays PENDING and expires as usual.
-- Does NOT change any balance, gift, expiry date, history row or setting; does not restore, renew or delete gifts.
-- The existing expiry rule (gift withdrawn with an explanatory note at the customer's next login) is unchanged.
-- Guards: each target line must occur exactly once; body fingerprints are recorded (and checked if filled in).
begin;
do $c1$
declare
  -- normalised md5 of the reviewed bodies. Staging replica values below; READ AND CONFIRM THE PRODUCTION VALUES
  -- (read-only) BEFORE APPLYING THERE. Empty string = do not check.
  v_md5_create text := '93a7f4bcffd8d13d9ebab5838d0b13d2';
  v_md5_decide text := 'c381c2829c62463a292a55b5cf81880f';
  f regprocedure; d text; m text; n int;
  old1 text := 'avail_pts := greatest(0, c.points);';
  new1 text := 'avail_pts := greatest(0, c.points - case when c.welcome_exp is not null and c.welcome_exp < now() then coalesce(c.welcome_remain,0) else 0 end); /* C-1 */';
  old2 text := 'update public.customers set points = points + t.earn - t.redeem_pts where phone = t.customer_phone;';
  new2 text := 'if t.redeem_pts > 0 and t.redeem_pts > (select greatest(0, c.points - case when c.welcome_exp is not null and c.welcome_exp < now() then coalesce(c.welcome_remain,0) else 0 end) from public.customers c where c.phone = t.customer_phone) then raise exception ''TP_C1: the points to be spent include an expired welcome gift'' using errcode = ''P0001''; end if; /* C-1 */
    update public.customers set points = points + t.earn - t.redeem_pts where phone = t.customer_phone;';
begin
  -- create_transaction
  f := 'public.create_transaction(uuid,text,numeric,boolean,uuid,jsonb)'::regprocedure;
  d := pg_get_functiondef(f); m := md5(regexp_replace(d, '\s+', ' ', 'g'));
  if position('/* C-1 */' in d) > 0 then raise notice 'C-1: create_transaction already patched, skipped';
  else
    if v_md5_create <> '' and m <> v_md5_create then raise exception 'C-1 STOP (nothing changed): create_transaction body differs from the reviewed version (%)', m; end if;
    n := (length(d) - length(replace(d, old1, ''))) / length(old1);
    if n <> 1 then raise exception 'C-1 STOP (nothing changed): create_transaction target line found % times', n; end if;
    execute replace(d, old1, new1);
  end if;
  -- decide_transaction
  f := 'public.decide_transaction(uuid,boolean)'::regprocedure;
  d := pg_get_functiondef(f); m := md5(regexp_replace(d, '\s+', ' ', 'g'));
  if position('/* C-1 */' in d) > 0 then raise notice 'C-1: decide_transaction already patched, skipped';
  else
    if v_md5_decide <> '' and m <> v_md5_decide then raise exception 'C-1 STOP (nothing changed): decide_transaction body differs from the reviewed version (%)', m; end if;
    n := (length(d) - length(replace(d, old2, ''))) / length(old2);
    if n <> 1 then raise exception 'C-1 STOP (nothing changed): decide_transaction target line found % times', n; end if;
    execute replace(d, old2, new2);
  end if;
  raise notice 'C-1 applied: expired welcome gifts are no longer spendable; no balance changed';
end $c1$;
commit;
