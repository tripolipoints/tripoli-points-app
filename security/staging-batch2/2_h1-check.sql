-- Tripoli Points — HOTFIX H1 status (read-only). One row per function + VERDICT. Safe on Staging and Production.
with t(sig) as (values
 ('admin_topup_merchant(uuid,numeric,text)'),('admin_resolve_topup_order(uuid,boolean)'),('admin_mark_order_collected(uuid)'),
 ('admin_delete_topup_order_only(uuid)'),('whish_confirm_payment(uuid,text,numeric,bigint)'),('whish_set_collect_url(uuid,text,bigint)'),
 ('customer_reset_pin(text,text)'),('customer_set_pin(text,text,text)'),('admin_grant_customer_gift(text,numeric,integer)'),
 ('customer_check_welcome_expiry(text)')),
r as (select sig, to_regprocedure('public.'||sig) is not null ex,
  coalesce(has_function_privilege('anon','public.'||sig,'execute'),false) anon_x,
  coalesce(has_function_privilege('authenticated','public.'||sig,'execute'),false) auth_x,
  coalesce(has_function_privilege('service_role','public.'||sig,'execute'),false) svc_x,
  coalesce(has_function_privilege('postgres','public.'||sig,'execute'),false) owner_x
  from t where to_regprocedure('public.'||sig) is not null
  union all select sig,false,null,null,null,null from t where to_regprocedure('public.'||sig) is null)
select sig, ex, anon_x, auth_x, svc_x, owner_x, (ex and not anon_x and not auth_x and owner_x) closed from r
union all
select 'VERDICT h1_closed_to_public_key', null,null,null,null,null, bool_and(ex and not anon_x and not auth_x and owner_x) from r
order by 1;
