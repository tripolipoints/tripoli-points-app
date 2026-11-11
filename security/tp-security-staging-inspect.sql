-- =====================================================================================================
-- Tripoli Points — STAGING INSPECTION before phase 0 · v1.3.1 · 2026-11-11
-- READ ONLY: three SELECT statements, nothing is written, no function is called. Safe on Staging and Production.
-- Run each statement separately in the SQL editor (or all at once: the editor shows the last result; then run them
-- one by one) and Download CSV of each result.
--   1) every function phase 0 touches: exact signature, owner, SECURITY DEFINER, who may execute it today,
--      fingerprint and whether it is the reviewed code, and what phase 0 will do to it;
--   2) the functions the public key can call today, with what phase 0 does (close / keep open);
--   3) Whish top-ups in the last 90 days, counts only (no phone, no name, no amount per person): shows whether
--      Whish confirmations work on Staging today, independently of phase 0.
-- =====================================================================================================

-- 1) functions phase 0 replaces or closes
with t(fn, action, h) as (values
  ('customer_verify_pin(text,text)',                 'replaced: same answers + wrong-PIN limit', 'c804486649aadaa57bc5a87fc8b6bcdf'),
  ('admin_verify_pin(text,text)',                    'replaced: same answers + wrong-PIN limit', 'a0e676d3290388fde1feae6f3d17564d'),
  ('admin_wipe_all_data(uuid,text)',                 'replaced: copy first + limit; closed to every API key', 'bd7d4982c8e56ca244c87eda058356f3'),
  ('merchant_verify_pin(text,text)',                 'not touched (October limit, prerequisite)', null),
  ('customer_reset_pin(text,text)',                  'closed to public/anon/authenticated; service_role kept as is', null),
  ('customer_set_pin(text,text,text)',               'closed to public/anon/authenticated; service_role kept as is', null),
  ('admin_grant_customer_gift(text,numeric,integer)', 'closed to public/anon/authenticated; service_role kept as is', null),
  ('whish_confirm_payment(uuid,text,numeric,bigint)', 'closed to public/anon/authenticated; service_role kept as is', null),
  ('whish_set_collect_url(uuid,text,bigint)',        'closed to public/anon/authenticated; service_role kept as is', null))
select t.fn as signature,
       case when p.oid is null then 'MISSING' else 'exists' end as found,
       t.action as phase0_action,
       pg_get_function_result(p.oid) as returns,
       p.prosecdef as security_definer,
       pg_get_userbyid(p.proowner) as owner,
       array_to_string(p.proconfig, ' ') as settings,
       has_function_privilege('anon', p.oid, 'EXECUTE') as anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_exec,
       p.proacl::text as acl,
       md5(regexp_replace(lower(p.prosrc), '\s+', '', 'g')) as fingerprint,
       case when t.h is null then null when p.prosrc like '%tp-phase0%' then 'phase 0 version'
            when md5(regexp_replace(lower(p.prosrc), '\s+', '', 'g')) = t.h then 'reviewed version' else 'DIFFERENT' end as code_check
  from t left join pg_proc p on p.oid = to_regprocedure('public.' || t.fn)
 order by t.fn;

-- 2) what the public key can call today, and what phase 0 does to each
select p.oid::regprocedure::text as signature,
       case when p.proname in ('customer_reset_pin','customer_set_pin','admin_grant_customer_gift','admin_delete_topup_order_only',
                               'whish_confirm_payment','whish_set_collect_url','_expire_topup_orders','customer_check_welcome_expiry',
                               'customer_notes_mark_read','merchant_notes_mark_read','_test_noop','admin_wipe_all_data')
              or (p.proname = 'customer_register' and p.pronargs in (3, 5)) or (p.proname = 'merchant_register' and p.pronargs between 11 and 14)
              or (p.proname = 'merchant_add_offer' and p.pronargs = 14) or (p.proname = 'admin_update_merchant_location' and p.pronargs = 6)
            then 'phase 0 closes it'
            when p.proname in ('customer_verify_pin','admin_verify_pin') then 'stays open, gets the PIN limit'
            else 'stays open (phase 1 / phase 3)' end as phase0,
       has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role_exec
  from pg_proc p
 where p.pronamespace = 'public'::regnamespace and has_function_privilege('anon', p.oid, 'EXECUTE')
 order by 2, 1;

-- 3) Whish top-ups, last 90 days (counts only)
select method, status, collected, count(*) as orders, count(paid_at) as with_paid_at, max(created_at)::date as last_order,
       max(paid_at)::date as last_paid
  from public.topup_orders where created_at > now() - interval '90 days'
 group by 1, 2, 3 order by 1, 2, 3;
