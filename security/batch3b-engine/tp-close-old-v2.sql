-- =====================================================================================================
-- Tripoli Points — BATCH 3d: close the old phone / id based functions (STAGING ONLY)
-- File: security/batch3b-engine/tp-close-old-v2.sql   (replaces tp-secure-purchase-v3-close-old.sql)
-- Run only after the Staging site uses sessions (staging-netlify ≥ 6051518).
-- What it does:
--   * saves the exact privileges of every function it touches in tp_backup.acl_snapshots (batch 'b3_close_old');
--   * revokes EXECUTE from public / anon / authenticated on:
--       - the purchase-by-phone path: create_transaction, decide_transaction, customer_create_request,
--         merchant_requests, merchant_close_request;
--       - the old PIN checks: customer_verify_pin, merchant_verify_pin, admin_verify_pin (login gives a session now);
--       - every old account function that has a *_v2 session version (customer_*, merchant_*);
--       - every old admin_* function except admin_reset_merchant_pin (it re-checks the admin PIN itself).
--   * sets engine_strict = 1: customers.points can then change only through the ledger.
-- Kept open on purpose: customer_register / merchant_register (registration: gift from the server since G-1; no other
--   registration exists until e-mail verification is enabled), public reads (list_merchants, offers, categories,
--   text settings, galleries, treasure_list), customer_check_phone / merchant_check_phone (login screen),
--   merchant_set_logo (re-checks the shop PIN).
-- No drop, no delete. Rollback: R_tp-close-old-v2-rollback.sql restores the saved privileges exactly.
-- =====================================================================================================
begin;

do $$ begin
  if to_regclass('public.point_batches') is null then raise exception 'batch 3b is required first'; end if;
  if exists (select 1 from tp_backup.acl_snapshots where batch = 'b3_close_old') then raise exception 'already applied (snapshot exists)'; end if;
end $$;

create temp table _close on commit drop as
select p.oid::regprocedure as f from pg_proc p
 where p.pronamespace = 'public'::regnamespace and (
   p.proname in ('create_transaction','decide_transaction','customer_create_request','merchant_requests','merchant_close_request',
                 'customer_verify_pin','merchant_verify_pin','admin_verify_pin',
                 'customer_profile','customer_transactions','customer_notes_list',
                 'merchant_add_offer','merchant_create_topup_order','merchant_delete_offer','merchant_gallery_add','merchant_gallery_delete',
                 'merchant_notes_list','merchant_offers','merchant_request_info_change','merchant_request_manual_topup',
                 'merchant_set_offer_active','merchant_set_redeem_pct','merchant_submit_photo','merchant_topup_orders','merchant_transactions',
                 'merchant_update_page','merchant_wallet')
   or (p.proname like 'admin\_%' and p.proname not like '%\_v2' and p.proname not in ('admin_reset_merchant_pin','admin_login')));

insert into tp_backup.acl_snapshots(batch, sig, acl, owner_name)
select 'b3_close_old', f::text, p.proacl, pg_get_userbyid(p.proowner) from _close c join pg_proc p on p.oid = c.f::oid;

do $$
declare r record; n int := 0;
begin
  for r in select f from _close loop
    execute format('revoke execute on function %s from public, anon, authenticated', r.f);
    n := n + 1;
  end loop;
  raise notice 'b3 close-old: % function(s) closed', n;
end $$;

-- strict ledger (the previous value is recorded for the rollback)
insert into tp_backup.settings_snapshots(batch, tbl, key, existed, old_value, inserted_value)
select 'b3_close_old', 'app_settings', 'engine_strict', true, value::text, '1' from public.app_settings where key = 'engine_strict';
update public.app_settings set value = 1 where key = 'engine_strict';

-- self-check
do $$
declare bad text;
begin
  bad := (select string_agg(c.f::text, ', ') from _close c where has_function_privilege('anon', c.f::oid, 'execute'));
  if bad is not null then raise exception 'still open to anon: %', bad; end if;
  bad := (select string_agg(x, ', ') from unnest(array['customer_register(text,text,text,numeric,integer,text)','list_merchants()','customer_login(text,text,text)',
            'merchant_login(text,text,text)','admin_login(text,text,text)','staff_login(text,text,text)','merchant_create_tx_v2(text,uuid,numeric,boolean,uuid,jsonb,text)']) x
          where to_regprocedure('public.' || x) is not null and not has_function_privilege('anon', to_regprocedure('public.' || x), 'execute'));
  if bad is not null then raise exception 'closed by mistake: %', bad; end if;
end $$;

commit;
