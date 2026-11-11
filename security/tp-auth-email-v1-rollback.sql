-- =====================================================================================================
-- Tripoli Points — E-MAIL ROLLBACK (STAGING) — undoes tp-auth-email-v1.sql only
-- Accounts created through e-mail registration stay (ordinary customers / merchants with their PIN, points and
-- purchases); their e-mail columns are removed. Registrations still waiting for a code are lost.
-- Phase 0 / phase 1 / October fixes are not touched. Nothing here reopens a closed function.
-- =====================================================================================================
begin;
do $$ begin if to_regclass('public.email_tokens') is null then raise exception 'e-mail phase not applied'; end if; end $$;
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in
      ('_email_norm','_email_valid','_email_mask','_email_issue','_email_consume','_email_register_start','_email_register_resend',
       '_email_add_start','_email_reset_start','_email_mark_sent','register_confirm','email_add_confirm','email_link_confirm','pin_reset_confirm','email_status') loop
    execute format('drop function %s', f);
  end loop;
end $$;
drop table public.email_tokens;
drop table public.pending_registrations;
drop index if exists public.customers_email_verified_uidx;
drop index if exists public.merchants_email_verified_uidx;
alter table public.customers drop column email, drop column email_verified_at;
alter table public.merchants drop column email, drop column email_verified_at;
delete from public.app_settings where key in ('email_code_ttl_min','email_reset_ttl_min','email_code_attempts','email_resend_sec',
  'email_per_hour_per_address','email_per_hour_per_phone','email_per_hour_per_ip','email_pending_hours');
commit;
