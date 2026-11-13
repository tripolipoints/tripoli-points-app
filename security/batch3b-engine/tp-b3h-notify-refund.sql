-- =====================================================================================================
-- Tripoli Points — BATCH 3h: expiry reminders, 7-day compensation, full / partial refunds (STAGING ONLY)
-- Register 12-Nov-2026:
--   §07  reminders 3 days before, 24 h before and at expiry, grouped (one note per occasion per customer), no reminder
--        for points already used; an administrative compensation separate from a verified technical error, valid 7 days,
--        linked to a complaint, audited, notified, never twice for the same complaint.
--   §10  full or partial cancellation / refund with both parties' agreement: used and earned points reversed in
--        proportion, in separate correction entries, the original purchase is never deleted; returned points do not get
--        back an expired validity; earned points already spent elsewhere are documented as a settlement between the
--        customer and the shop (no new points, no touching the other branch).
--   Rounding of proportional amounts: floor — PROVISIONAL (register: fractional rounding not decided).
-- Changes: 3 new tables, 1 setting (fill-missing), _pts_expire text-patched (reminders) and admin_run_expiry_v2
--   text-patched (reminders for everyone), both saved in tp_backup.func_snapshots ('b3h'); new functions.
--   No drop / delete / truncate. Rollback: R_tp-b3h-notify-refund-rollback.sql
-- =====================================================================================================
begin;

do $$ begin
  if to_regprocedure('public._tx_quote2(uuid,text,numeric,boolean,uuid,numeric)') is null then raise exception 'batch 3g required'; end if;
  if exists (select 1 from tp_backup.func_snapshots where batch = 'b3h') then raise exception 'already applied'; end if;
end $$;

do $$
declare r record; cur text;
begin
  for r in select * from (values
    ('_pts_expire(text)', '891d4de465aad5729ffeb96f9baecfe7'),
    ('admin_run_expiry_v2(text)', 'd6fb3b1b1292f3386dadfdbb1ec19e36')) v(sig, want) loop
    cur := (select md5(replace(prosrc, chr(13), '')) from pg_proc where oid = to_regprocedure('public.' || r.sig));
    if cur is distinct from r.want then raise exception '% differs (md5 %), stop', r.sig, cur; end if;
    insert into tp_backup.func_snapshots(batch, sig, def, src_md5)
    values ('b3h', r.sig, pg_get_functiondef(to_regprocedure('public.' || r.sig)), (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)));
  end loop;
  if not exists (select 1 from public.app_settings where key = 'compensation_days') then
    execute 'insert ' || 'into public.app_settings(key, value) values ($1, $2)' using 'compensation_days', 7;          -- §07 approved
    insert into tp_backup.settings_snapshots(batch, tbl, key, existed, old_value, inserted_value) values ('b3h', 'app_settings', 'compensation_days', false, null, '7');
  end if;
end $$;

-- ---------------------------------------------------------------- tables
create table public.point_reminders(
  batch_id bigint not null references public.point_batches(id) on delete cascade,
  kind text not null check (kind in ('3d','24h')),
  customer_phone text not null references public.customers(phone) on delete cascade on update cascade,
  at timestamptz not null default now(),
  primary key (batch_id, kind));
create table public.compensations(
  id bigserial primary key,
  report_id uuid not null unique,                          -- one compensation per complaint, ever
  customer_phone text not null references public.customers(phone) on delete cascade on update cascade,
  batch_id bigint references public.point_batches(id) on delete set null,
  points numeric not null check (points > 0),
  note text not null, granted_by uuid, at timestamptz not null default now());
create table public.tx_refunds(
  id bigserial primary key,
  tx_id uuid not null references public.pos_transactions(id) on delete cascade,
  fraction numeric not null check (fraction > 0 and fraction <= 1),
  redeem_back numeric not null default 0, redeem_lapsed numeric not null default 0,
  earn_back numeric not null default 0, earn_shortfall numeric not null default 0,
  allowance_back numeric not null default 0, allowance_lapsed numeric not null default 0,
  note text not null, customer_agreed boolean not null, merchant_agreed boolean not null,
  by_admin uuid, at timestamptz not null default now());
create index tx_refunds_tx_idx on public.tx_refunds(tx_id);
do $$
declare t text;
begin
  foreach t in array array['point_reminders','compensations','tx_refunds'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on table public.%I from public, anon, authenticated', t);
  end loop;
  execute 'revoke all on sequence public.compensations_id_seq from public, anon, authenticated';
  execute 'revoke all on sequence public.tx_refunds_id_seq from public, anon, authenticated';
end $$;

-- ---------------------------------------------------------------- §07 reminders (grouped per occasion)
create function public._pts_remind(p_phone text) returns int language plpgsql security definer set search_path = public, pg_temp as $$
declare n24 numeric; n3 numeric; at24 timestamptz; at3 timestamptz; sent int := 0;
begin
  -- 24 h: batches expiring within a day, not yet reminded at 24 h
  select sum(b.remaining), min(b.expires_at) into n24, at24 from public.point_batches b
   where b.customer_phone = p_phone and b.remaining > 0 and b.expires_at > now() and b.expires_at <= now() + interval '24 hours'
     and not exists (select 1 from public.point_reminders r where r.batch_id = b.id and r.kind = '24h');
  if n24 > 0 then
    insert into public.point_reminders(batch_id, kind, customer_phone)
    select b.id, '24h', p_phone from public.point_batches b
     where b.customer_phone = p_phone and b.remaining > 0 and b.expires_at > now() and b.expires_at <= now() + interval '24 hours'
       and not exists (select 1 from public.point_reminders r where r.batch_id = b.id and r.kind = '24h');
    insert into public.point_reminders(batch_id, kind, customer_phone)       -- a 24 h reminder replaces a missed 3-day one
    select b.id, '3d', p_phone from public.point_batches b
     where b.customer_phone = p_phone and b.remaining > 0 and b.expires_at > now() and b.expires_at <= now() + interval '24 hours'
       and not exists (select 1 from public.point_reminders r where r.batch_id = b.id and r.kind = '3d');
    insert into public.customer_notes(customer_phone, type, title, body)
    values (p_phone, 'points', format('تنتهي %s نقطة خلال 24 ساعة', n24), 'استخدمها قبل انتهاء صلاحيتها.');
    sent := sent + 1;
  end if;
  select sum(b.remaining), min(b.expires_at) into n3, at3 from public.point_batches b
   where b.customer_phone = p_phone and b.remaining > 0 and b.expires_at > now() + interval '24 hours' and b.expires_at <= now() + interval '3 days'
     and not exists (select 1 from public.point_reminders r where r.batch_id = b.id and r.kind = '3d');
  if n3 > 0 then
    insert into public.point_reminders(batch_id, kind, customer_phone)
    select b.id, '3d', p_phone from public.point_batches b
     where b.customer_phone = p_phone and b.remaining > 0 and b.expires_at > now() + interval '24 hours' and b.expires_at <= now() + interval '3 days'
       and not exists (select 1 from public.point_reminders r where r.batch_id = b.id and r.kind = '3d');
    insert into public.customer_notes(customer_phone, type, title, body)
    values (p_phone, 'points', format('تنتهي %s نقطة خلال 3 أيام', n3), 'تُستخدم النقاط الأقرب انتهاءً أولاً عند الشراء.');
    sent := sent + 1;
  end if;
  return sent;
end $$;

-- ---------------------------------------------------------------- §07 compensation (7 days, linked to a complaint, once)
create function public.admin_compensate_v2(p_session text, p_report_id uuid, p_points numeric, p_note text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; rep public.tx_reports; b bigint; d int := public._setting('compensation_days', 7)::int;
begin
  a := public._sess_admin(p_session, true);
  if p_points is null or p_points <= 0 or p_points <> floor(p_points) or p_points > 100000 or p_note is null or length(trim(p_note)) < 5 then
    return jsonb_build_object('ok', false, 'error', 'bad_request', 'message', 'اكتب عدد النقاط ووصف الخطأ التقني المُتحقَّق منه');
  end if;
  select * into rep from public.tx_reports where id = p_report_id for update;
  if rep.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if rep.reporter_role <> 'customer' then return jsonb_build_object('ok', false, 'error', 'not_customer', 'message', 'التعويض للزبون صاحب البلاغ فقط'); end if;
  if exists (select 1 from public.compensations where report_id = rep.id) then
    return jsonb_build_object('ok', false, 'error', 'already_compensated', 'message', 'سبق التعويض عن هذا البلاغ');
  end if;
  perform 1 from public.customers where phone = rep.reporter for update;
  b := public._pts_add(rep.reporter, p_points, 'adjust', now() + make_interval(days => d), rep.tx_id, null, a.id::text, 'تعويض: ' || left(trim(p_note), 250));
  insert into public.compensations(report_id, customer_phone, batch_id, points, note, granted_by) values (rep.id, rep.reporter, b, p_points, left(trim(p_note), 300), a.id);
  perform public._pts_sync(rep.reporter);
  insert into public.customer_notes(customer_phone, type, title, body)
  values (rep.reporter, 'points', format('تعويض من الإدارة: %s نقطة', p_points), format('صالحة %s أيام. %s', d, left(trim(p_note), 200)));
  perform public._audit('admin', a.id::text, 'compensation', 'report', rep.id::text, jsonb_build_object('points', p_points, 'days', d, 'batch', b));
  return jsonb_build_object('ok', true, 'batch_id', b, 'expires_in_days', d);
end $$;

-- ---------------------------------------------------------------- §10 refunds (full or partial, proportional)
create function public.admin_tx_refund_v2(p_session text, p_tx_id uuid, p_fraction numeric, p_note text,
  p_customer_agreed boolean, p_merchant_agreed boolean) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; t public.pos_transactions; done numeric; f numeric; rb numeric; eb numeric; need numeric; take numeric;
  r_back numeric := 0; r_lapsed numeric := 0; e_back numeric := 0; e_short numeric := 0; a_back numeric := 0; a_lapsed numeric := 0;
  mv record; b public.point_batches; h record; g public.allowance_grants; rid bigint;
begin
  a := public._sess_admin(p_session, true);
  if p_fraction is null or p_fraction <= 0 or p_fraction > 1 or p_note is null or length(trim(p_note)) < 5 then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  if not coalesce(p_customer_agreed, false) or not coalesce(p_merchant_agreed, false) then
    return jsonb_build_object('ok', false, 'error', 'agreement_required', 'message', 'الإرجاع يحتاج موافقة الزبون والمحل');
  end if;
  select * into t from public.pos_transactions where id = p_tx_id for update;
  if t.id is null or t.status <> 'CONFIRMED' then return jsonb_build_object('ok', false, 'error', 'not_confirmed'); end if;
  done := coalesce((select sum(fraction) from public.tx_refunds where tx_id = t.id), 0);
  if done + p_fraction > 1.000001 then return jsonb_build_object('ok', false, 'error', 'over_refund', 'message', format('سبق إرجاع %s%% من العملية', round(done * 100, 2))); end if;
  f := p_fraction;
  perform 1 from public.customers where phone = t.customer_phone for update;
  -- used points come back to the batches they were taken from, unless those batches have expired since
  rb := floor(t.redeem_pts * f);                                             -- PROVISIONAL rounding: floor
  need := rb;
  for mv in select m.batch_id, -m.delta as took from public.point_movements m where m.tx_id = t.id and m.reason = 'spend' and m.batch_id is not null order by m.id loop
    exit when need <= 0;
    select * into b from public.point_batches where id = mv.batch_id for update;
    take := least(need, mv.took - coalesce((select sum(x.delta) from public.point_movements x where x.tx_id = t.id and x.batch_id = b.id and x.reason = 'refund' and x.delta > 0), 0));
    if take <= 0 then continue; end if;
    if b.expires_at is null or b.expires_at > now() then
      take := least(take, b.initial - b.remaining);
      if take > 0 then
        update public.point_batches set remaining = remaining + take where id = b.id;
        insert into public.point_movements(customer_phone, batch_id, delta, reason, tx_id, actor) values (t.customer_phone, b.id, take, 'refund', t.id, a.id::text);
        r_back := r_back + take;
      end if;
    else
      r_lapsed := r_lapsed + take;                                           -- expired meanwhile: validity is not given back
    end if;
    need := need - take;
  end loop;
  -- earned points go back out of the purchase's own earn batch; what was already spent is a documented settlement
  eb := floor(t.earn * f);
  select * into b from public.point_batches where tx_id = t.id and kind = 'earn' for update;
  if b.id is not null and eb > 0 then
    take := least(eb, b.remaining);
    if take > 0 then
      update public.point_batches set remaining = remaining - take where id = b.id;
      insert into public.point_movements(customer_phone, batch_id, delta, reason, tx_id, actor) values (t.customer_phone, b.id, -take, 'refund', t.id, a.id::text);
    end if;
    e_back := take; e_short := eb - take;
  else e_short := eb; end if;
  -- the branch gets back the allowance the used points took (to grants still valid)
  need := rb;
  for h in select hh.grant_id, hh.pts from public.allowance_holds hh where hh.tx_id = t.id and hh.status = 'consumed' order by hh.grant_id loop
    exit when need <= 0;
    select * into g from public.allowance_grants where id = h.grant_id for update;
    take := least(need, h.pts);
    if g.expires_at > now() then
      take := least(take, g.initial - g.remaining);
      if take > 0 then
        update public.allowance_grants set remaining = remaining + take where id = g.id;
        insert into public.allowance_movements(merchant_id, grant_id, delta, pts, kind, tx_id, actor) values (g.merchant_id, g.id, take, take, 'adjust', t.id, 'refund:' || a.id);
        a_back := a_back + take;
      end if;
    else a_lapsed := a_lapsed + take; end if;
    need := need - take;
  end loop;
  insert into public.tx_refunds(tx_id, fraction, redeem_back, redeem_lapsed, earn_back, earn_shortfall, allowance_back, allowance_lapsed, note, customer_agreed, merchant_agreed, by_admin)
  values (t.id, f, r_back, r_lapsed, e_back, e_short, a_back, a_lapsed, left(trim(p_note), 300), true, true, a.id) returning id into rid;
  perform public._pts_sync(t.customer_phone);
  insert into public.customer_notes(customer_phone, type, title, body) values (t.customer_phone, 'points',
    case when done + f >= 0.999999 then 'تم إرجاع العملية' else 'تم إرجاع جزء من العملية' end,
    format('أُعيدت %s نقطة مستخدمة وسُحبت %s نقطة مكتسبة', r_back, e_back));
  insert into public.merchant_notes(merchant_id, type, title, body) values (t.merchant_id, 'info',
    case when done + f >= 0.999999 then 'إرجاع كامل لعملية' else 'إرجاع جزئي لعملية' end, format('$%s · %s%%', t.invoice, round(f * 100, 2)));
  perform public._audit('admin', a.id::text, 'tx_refund', 'tx', t.id::text, jsonb_build_object('fraction', f, 'redeem_back', r_back, 'redeem_lapsed', r_lapsed,
    'earn_back', e_back, 'earn_shortfall', e_short, 'allowance_back', a_back, 'allowance_lapsed', a_lapsed, 'refund_id', rid));
  return jsonb_build_object('ok', true, 'refund_id', rid, 'redeem_back', r_back, 'redeem_lapsed', r_lapsed, 'earn_back', e_back,
    'earn_shortfall', e_short, 'allowance_back', a_back, 'allowance_lapsed', a_lapsed, 'refunded_total', done + f);
end $$;

create function public.admin_tx_lookup_v2(p_session text, p_tx_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; t public.pos_transactions;
begin
  a := public._sess_admin(p_session, false);
  select * into t from public.pos_transactions where id = p_tx_id;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'tx', public._tx_json(t, 'merchant') || jsonb_build_object('customer', t.customer_phone),
    'refunds', (select coalesce(jsonb_agg(to_jsonb(r) order by r.at), '[]'::jsonb) from public.tx_refunds r where r.tx_id = t.id),
    'reports', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'reason', reason, 'status', status)), '[]'::jsonb) from public.tx_reports where tx_id = t.id),
    'compensated', exists (select 1 from public.compensations c join public.tx_reports r on r.id = c.report_id where r.tx_id = t.id));
end $$;

-- refunds are visible to both sides as receipts (§12)
create function public.tx_receipt_v2(p_session text, p_tx_id uuid) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.app_sessions; t public.pos_transactions;
begin
  select * into s from public.app_sessions where token_hash = public._sha(coalesce(p_session, ''));
  if s.id is null or s.revoked_at is not null or s.expires_at <= now() or s.role not in ('customer','merchant') then
    raise exception 'TP_SESSION_EXPIRED' using errcode = 'P0001', hint = 'login_required';
  end if;
  if s.role = 'merchant' then perform public._sess_branch(p_session, 'history'); else perform public._sess_customer(p_session); end if;
  select * into t from public.pos_transactions where id = p_tx_id
     and ((s.role = 'customer' and customer_phone = s.customer_phone) or (s.role = 'merchant' and merchant_id = s.merchant_id));
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'receipt', public._tx_json(t, case when s.role = 'customer' then 'customer' else 'merchant' end)
    || jsonb_build_object('cref', case when s.role = 'merchant' then '••' || right(t.customer_phone, 2) end,
       'refunds', (select coalesce(jsonb_agg(jsonb_build_object('fraction', fraction, 'redeem_back', redeem_back, 'earn_back', earn_back,
                    'at', floor(extract(epoch from at) * 1000)) order by at), '[]'::jsonb) from public.tx_refunds where tx_id = t.id)));
end $$;

-- ---------------------------------------------------------------- text patches: reminders run with every expiry pass
do $$
declare r record; d text; n int;
begin
  for r in select * from (values
    ('_pts_expire(text)', 'perform public._pts_sync(p_phone);', 'perform public._pts_remind(p_phone); /* B3H */ perform public._pts_sync(p_phone);'),
    ('admin_run_expiry_v2(text)', 'al := public._allow_expire(null);',
     'for r in select distinct customer_phone from public.point_batches where remaining > 0 and expires_at > now() and expires_at <= now() + interval ''3 days'' loop perform public._pts_remind(r.customer_phone); end loop; /* B3H */ al := public._allow_expire(null);')) v(sig, old, new) loop
    d := (select def from tp_backup.func_snapshots where batch = 'b3h' and sig = r.sig);
    n := (length(d) - length(replace(d, r.old, ''))) / length(r.old);
    if n <> 1 then raise exception 'patch target found % times in %', n, r.sig; end if;
    execute replace(d, r.old, r.new);
  end loop;
end $$;

do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = '_pts_remind' loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array['admin_compensate_v2','admin_tx_refund_v2','admin_tx_lookup_v2','tx_receipt_v2']) loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
  if has_function_privilege('anon', 'public._pts_remind(text)', 'execute') then raise exception 'self-check: helper open'; end if;
end $$;

commit;
