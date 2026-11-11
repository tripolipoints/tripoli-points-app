-- =====================================================================================================
-- Tripoli Points — E-MAIL VERIFICATION AND PIN RECOVERY TESTS (STAGING, after tp-auth-email-v1.sql)
-- One transaction, ROLLBACK at the end. The Edge Function's part (the _email_*_start calls that return the code and
-- link) is played by this script; the app's part (confirm functions) runs as the public role, like the app.
-- No e-mail is sent by these tests. Test numbers 70999701-70999709, addresses @tp-test.invalid.
-- =====================================================================================================
begin;
set local client_min_messages = warning;
create temp table _t (n serial primary key, name text, ok boolean, detail text) on commit drop;
create temp table _ctx (k text primary key, v text) on commit drop;
grant all on _t, _ctx to anon; grant usage on sequence _t_n_seq to anon;
create function pg_temp.ok(p_name text, p_cond boolean, p_detail text default null) returns void language sql as $$
  insert into _t(name, ok, detail) values (p_name, coalesce(p_cond, false), p_detail) $$;
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
begin execute p_sql; return 'NO_ERROR'; exception when others then return sqlerrm; end $$;
create function pg_temp.set(p_k text, p_v text) returns void language sql as $$
  insert into _ctx values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.get(p_k text) returns text language sql as $$ select v from _ctx where k = p_k $$;

do $$ begin
  if exists (select 1 from public.customers where phone like '709997__') or exists (select 1 from public.merchants where phone like '709997__') then
    raise exception 'test numbers 709997xx already exist — tests stopped';
  end if;
end $$;
-- a legacy customer (no e-mail) with points and a purchase, and a legacy merchant
insert into public.merchants(id, name, phone, pin_hash, cat, pct, tier, redeem_pct, status) values
  ('00000000-0000-4000-8000-0000000007a1', 'محل بريد', '70999709', extensions.crypt('4321', extensions.gen_salt('bf', 4)), 'cafe', 5, 'medium', 5, 'active');
insert into public.customers(phone, pin_hash, name, last_name, status, points) values
  ('70999701', extensions.crypt('1234', extensions.gen_salt('bf', 4)), 'قديم', 'زبون', 'active', 750);
insert into public.pos_transactions(merchant_id, customer_phone, invoice, net, earn, status) values
  ('00000000-0000-4000-8000-0000000007a1', '70999701', 20, 20, 100, 'CONFIRMED');
insert into public.app_text_settings(key, value) values ('welcome_bonus', '50'), ('welcome_days', '7')
  on conflict (key) do update set value = excluded.value;

-- ---------------------------------------------------------------- 1. customer registration
do $$
declare r jsonb; s jsonb; i int; e text;
begin
  r := public._email_register_start('customer', '70999702', '2468', 'Sara@TP-Test.invalid', 'v1');
  perform pg_temp.ok('register: start returns a pending id, a 6-digit code and a link for the e-mail',
    (r->>'ok')::boolean and r->>'code' ~ '^\d{6}$' and length(r->>'link_token') >= 40 and r->>'email' = 'sara@tp-test.invalid', left(r::text, 120));
  perform pg_temp.ok('register: the app only sees the masked address', r->>'masked' = 's•••@tp-test.invalid', r->>'masked');
  perform pg_temp.ok('register: no account exists before the e-mail is verified', not exists (select 1 from public.customers where phone = '70999702'));
  perform pg_temp.ok('register: the PIN is stored only as a bcrypt hash',
    (select pin_hash like '$2%' and pin_hash <> '2468' from public.pending_registrations where id = (r->>'pending_id')::uuid));
  perform pg_temp.ok('register: code and link are stored only as SHA-256',
    not exists (select 1 from public.email_tokens where encode(code_hash, 'escape') like '%' || (r->>'code') || '%'));
  s := public._email_register_start('customer', '70999702', '2468', 'sara@tp-test.invalid', 'v1');
  perform pg_temp.ok('register: a second e-mail within 60 s is refused', s->>'error' = 'too_soon', s::text);
  perform pg_temp.set('pend', r->>'pending_id'); perform pg_temp.set('code', r->>'code');
  r := public._email_register_start('customer', '70999701', '1234', 'x@tp-test.invalid');
  perform pg_temp.ok('register: an existing number is refused, pointing to login / forgot PIN', r->>'error' = 'phone_taken', r->>'message');
  r := public._email_register_start('customer', '70999703', '1234', 'not-an-email');
  perform pg_temp.ok('register: an invalid address is refused', r->>'error' = 'email');
end $$;

set local role anon;
do $$
declare r jsonb; i int; e text;
begin
  e := pg_temp.err($q$select public._email_register_start('customer', '70999704', '1111', 'a@tp-test.invalid')$q$);
  perform pg_temp.ok('the public key cannot start e-mail flows (only the Edge Function can)', e like 'permission denied%', e);
  e := pg_temp.err('select count(*) from public.email_tokens');
  perform pg_temp.ok('the public key cannot read e-mail codes', e like 'permission denied%', e);
  r := public.register_confirm(pg_temp.get('pend')::uuid, '000000');
  perform pg_temp.ok('register: a wrong code is refused', r->>'error' = 'invalid_code');
  r := public.register_confirm(pg_temp.get('pend')::uuid, pg_temp.get('code'), null, 'phone-1');
  perform pg_temp.ok('register: the right code creates the account and signs in', (r->>'ok')::boolean and r->>'session' like 'tps1_%', left(r::text, 140));
  perform pg_temp.set('c2', r->>'session');
  r := public.register_confirm(pg_temp.get('pend')::uuid, pg_temp.get('code'));
  perform pg_temp.ok('register: the same code cannot be used twice', (r->>'ok')::boolean = false);
  r := public.customer_login('70999702', '2468');
  perform pg_temp.ok('register: the chosen PIN works for login', (r->>'ok')::boolean);
  r := public.email_status(pg_temp.get('c2'));
  perform pg_temp.ok('register: the e-mail is saved and verified', (r->>'verified')::boolean and r->>'email' like 's%@tp-test.invalid', r::text);
end $$;
reset role;
do $$ begin
  perform pg_temp.ok('register: the welcome gift comes from the server setting (50)', (select points from public.customers where phone = '70999702') = 50);
end $$;

-- 5 wrong codes kill the code; expiry; link on another device
do $$
declare r jsonb; i int; p uuid; l text; c text;
begin
  r := public._email_register_start('customer', '70999703', '1357', 'omar@tp-test.invalid');
  p := (r->>'pending_id')::uuid; c := r->>'code';
  for i in 1..5 loop perform public.register_confirm(p, case when c = '111111' then '222222' else '111111' end); end loop;
  r := public.register_confirm(p, c);
  perform pg_temp.ok('register: after 5 wrong codes even the right code is refused', r->>'error' in ('invalid_code', 'locked'), r::text);
  update public.email_tokens set created_at = now() - interval '2 minutes' where pending_id = p;   -- pass the 60 s wait
  r := public._email_register_resend(p);
  perform pg_temp.ok('register: «resend» gives a new code', (r->>'ok')::boolean, left(r::text, 80));
  update public.email_tokens set expires_at = now() - interval '1 second' where pending_id = p and used_at is null and superseded_at is null;
  perform public._rl2_reset('mailcode:' || p);
  r := public.register_confirm(p, r->>'code');
  perform pg_temp.ok('register: an expired code is refused', r->>'error' = 'invalid_code', r::text);
  update public.email_tokens set created_at = now() - interval '2 minutes' where pending_id = p;
  r := public._email_register_resend(p); l := r->>'link_token';
  r := public.register_confirm(null, null, l, 'laptop');
  perform pg_temp.ok('register: the e-mail link alone works on another device', (r->>'ok')::boolean and r->>'session' like 'tps1_%', left(r::text, 100));
end $$;

-- the same verified address cannot serve two customer accounts
do $$ declare r jsonb; begin
  r := public._email_register_start('customer', '70999705', '1111', 'SARA@tp-test.invalid');
  perform pg_temp.ok('register: an address already verified on another account is refused', r->>'error' = 'email_taken', r::text);
end $$;

-- ---------------------------------------------------------------- 2. merchant registration
do $$
declare r jsonb;
begin
  r := public._email_register_start('merchant', '70999706', '8642', 'shop@tp-test.invalid', 'v1',
        jsonb_build_object('name', 'متجر جديد', 'cat', 'cafe', 'pct', 5, 'addr', 'التل', 'lat', 34.43, 'lng', 35.84, 'redeem_pct', 5, 'area', 'التل', 'extra_cats', '[]'::jsonb));
  perform pg_temp.ok('merchant: registration starts with the shop data', (r->>'ok')::boolean, left(r::text, 80));
  r := public.register_confirm((r->>'pending_id')::uuid, r->>'code', null, 'shop-phone');
  perform pg_temp.ok('merchant: confirmed → shop created as pending review, with a session', (r->>'ok')::boolean and r->'merchant'->>'status' = 'pending' and r->>'session' like 'tps1_%', left(r::text, 160));
  perform pg_temp.ok('merchant: the e-mail is verified on the shop', (select email_verified_at is not null and email = 'shop@tp-test.invalid' from public.merchants where phone = '70999706'));
  r := public.merchant_login('70999706', '8642');
  perform pg_temp.ok('merchant: the chosen PIN works', (r->>'ok')::boolean);
end $$;

-- ---------------------------------------------------------------- 3. old accounts add an e-mail (no loss)
do $$
declare r jsonb; s text; p0 bigint; t0 bigint;
begin
  select points into p0 from public.customers where phone = '70999701'; select count(*) into t0 from public.pos_transactions where customer_phone = '70999701';
  s := public.customer_login('70999701', '1234', 'old-phone')->>'session'; perform pg_temp.set('c1', s);
  r := public.email_status(s);
  perform pg_temp.ok('old account: no e-mail yet', (r->>'verified')::boolean = false and r->'email' = 'null'::jsonb, r::text);
  r := public._email_reset_start('customer', '70999701');
  perform pg_temp.ok('old account: «forgot PIN» explains there is no verified e-mail', r->>'error' = 'no_verified_email', r->>'message');
  r := public._email_add_start(s, 'old@tp-test.invalid');
  perform pg_temp.ok('old account: add-e-mail sends a code', (r->>'ok')::boolean and r->>'purpose' = 'add_email');
  perform pg_temp.set('addcode', r->>'code');
  r := public.email_add_confirm(s, '999999');
  perform pg_temp.ok('old account: a wrong code is refused', r->>'error' = 'invalid_code');
  r := public.email_add_confirm(s, pg_temp.get('addcode'));
  perform pg_temp.ok('old account: the right code verifies the e-mail', (r->>'ok')::boolean, r::text);
  perform pg_temp.ok('old account: points and purchases unchanged',
    (select points from public.customers where phone = '70999701') = p0 and (select count(*) from public.pos_transactions where customer_phone = '70999701') = t0);
  r := public._email_add_start(s, 'new@tp-test.invalid');
  perform pg_temp.ok('changing a verified e-mail needs the PIN', r->>'error' = 'wrong_pin', r::text);
  r := public._email_add_start(s, 'sara@tp-test.invalid', '1234');
  perform pg_temp.ok('changing to an address used by another account is refused', r->>'error' = 'email_taken', r::text);
  r := public._email_add_start(public.merchant_login('70999709', '4321')->>'session', 'shop9@tp-test.invalid');
  r := public.email_link_confirm(r->>'link_token');
  perform pg_temp.ok('old merchant: the e-mail link verifies the shop e-mail', (r->>'ok')::boolean
    and (select email_verified_at is not null from public.merchants where phone = '70999709'), r::text);
end $$;

-- ---------------------------------------------------------------- 4. forgotten PIN
do $$
declare r jsonb; c text; old_s text := pg_temp.get('c1'); i int;
begin
  r := public._email_reset_start('customer', '70999701');
  perform pg_temp.ok('reset: the code goes only to the verified e-mail (masked in the app)', (r->>'ok')::boolean and r->>'masked' = 'o••@tp-test.invalid' and r->>'purpose' = 'reset_pin', r->>'masked');
  c := r->>'code';
  r := public.pin_reset_confirm('5555', 'customer', '70999701', '000000');
  perform pg_temp.ok('reset: a wrong code is refused', r->>'error' = 'invalid_code');
  r := public.pin_reset_confirm('5555', 'customer', '70999702', c);
  perform pg_temp.ok('reset: a code works only for its own account', r->>'error' = 'invalid_code');
  r := public.pin_reset_confirm('12', 'customer', '70999701', c);
  perform pg_temp.ok('reset: the new PIN must be 4 digits', r->>'error' = 'pin');
  r := public.pin_reset_confirm('5555', 'customer', '70999701', c, null, 'new-phone');
  perform pg_temp.ok('reset: the right code sets the new PIN and signs in', (r->>'ok')::boolean and r->>'session' like 'tps1_%', left(r::text, 100));
  perform pg_temp.ok('reset: the old PIN no longer works', (public.customer_login('70999701', '1234')->>'ok')::boolean = false);
  perform pg_temp.ok('reset: the new PIN works', (public.customer_login('70999701', '5555')->>'ok')::boolean);
  perform pg_temp.ok('reset: every session from before the reset is ended', pg_temp.err(format('select public.email_status(%L)', old_s)) = 'TP_SESSION_EXPIRED');
  perform pg_temp.ok('reset: the code cannot be used again', (public.pin_reset_confirm('7777', 'customer', '70999701', c)->>'ok')::boolean = false);
  perform pg_temp.ok('reset: the old PIN is never returned anywhere', r::text !~ '1234' and r::text !~ '\$2[aby]\$');
  perform pg_temp.ok('reset: the customer gets a notice', exists (select 1 from public.customer_notes where customer_phone = '70999701' and title = 'تم تغيير رمز الحماية'));
  r := public._email_reset_start('merchant', '70999709');
  r := public.pin_reset_confirm('2468', null, null, null, r->>'link_token', 'shop-tablet');
  perform pg_temp.ok('reset (merchant): the e-mail link works too', (r->>'ok')::boolean and (public.merchant_login('70999709', '2468')->>'ok')::boolean, left(r::text, 100));
  for i in 1..3 loop r := public._email_reset_start('customer', '70999701'); update public.email_tokens set created_at = now() - interval '2 minutes' where customer_phone = '70999701'; end loop;
  r := public._email_reset_start('customer', '70999701');
  perform pg_temp.ok('reset: at most 3 reset e-mails per hour per account', r->>'error' = 'rate_limited', r::text);
end $$;

-- ---------------------------------------------------------------- 5. shared PIN lock with the October / phase-0 functions
do $$
declare r jsonb; i int;
begin
  if not exists (select 1 from pg_proc where proname = 'customer_verify_pin' and position('_rl_locked' in prosrc) > 0) then
    perform pg_temp.ok('shared lock: needs phase 0 (customer_verify_pin limit) — skipped', true, 'phase 0 not applied here');
  else
    for i in 1..3 loop perform public.customer_verify_pin('70999702', '0000'); end loop;
    for i in 1..2 loop perform public.customer_login('70999702', '0000'); end loop;
    r := public.customer_login('70999702', '2468');
    perform pg_temp.ok('shared lock: 3 wrong on the old login + 2 on the new one lock both', r->>'reason' = 'locked', r::text);
  end if;
end $$;

select n, case when ok then 'PASS' else 'FAIL' end as result, name, detail from _t order by n;
select count(*) filter (where ok) as passed, count(*) filter (where not ok) as failed, count(*) as total from _t;
rollback;
