-- =====================================================================================================
-- Tripoli Points — SECURITY STATUS CHECK (read-only: SELECT only, changes nothing)
-- Run in the SQL editor of Staging and of Production. One row per fix: applied = true / false.
-- Empty (null) = that function does not exist on this database.
-- Answers "is it really on this database?" — a passing local test is not proof that a fix is applied.
-- =====================================================================================================
with f as (select p.oid, p.proname, p.pronargs, p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace),
anon_exec as (select f.proname, f.pronargs, has_function_privilege('anon', f.oid, 'EXECUTE') as anon from f)
select * from (values
 -- October 2026 (merchant PIN review, logo migration, emergency hardening)
 ('oct', 'merchant_reset_pin closed to the public key',      (select not bool_or(anon) from anon_exec where proname = 'merchant_reset_pin')),
 ('oct', 'wrong-PIN limit on merchant_verify_pin',             coalesce((select bool_or(position('_rl_locked' in prosrc) > 0) from f where proname = 'merchant_verify_pin'), false)),
 ('oct', 'merchant_set_logo checks phone + PIN, limited',      coalesce((select bool_or(position('_rl_locked' in prosrc) > 0 and position('crypt(' in prosrc) > 0) from f where proname = 'merchant_set_logo'), false)),
 ('oct', 'admin_reset_merchant_pin checks admin PIN, limited', coalesce((select bool_or(position('_rl_locked' in prosrc) > 0 and position('crypt(' in prosrc) > 0) from f where proname = 'admin_reset_merchant_pin'), false)),
 ('oct', '_rl_* helpers closed to the public key',            (select not bool_or(anon) from anon_exec where proname in ('_rl_locked','_rl_record_fail','_rl_reset'))),
 ('oct', 'old admin overloads dropped (wipe(), delete(uuid))', not exists (select 1 from f where (proname = 'admin_wipe_all_data' and pronargs = 0)
                                                                  or (proname in ('admin_delete_merchant','admin_delete_customer','admin_force_delete_merchant') and pronargs = 1))),
 ('oct', 'leftover admin_*_test functions dropped',            not exists (select 1 from f where proname like 'admin\_%\_test%')),
 -- November phase 0
 ('p0',  'customer_reset_pin closed',                          (select not bool_or(anon) from anon_exec where proname = 'customer_reset_pin')),
 ('p0',  'whish_confirm_payment / whish_set_collect_url closed', (select not bool_or(anon) from anon_exec where proname in ('whish_confirm_payment','whish_set_collect_url'))),
 ('p0',  'admin_grant_customer_gift closed',                   (select not bool_or(anon) from anon_exec where proname = 'admin_grant_customer_gift')),
 ('p0',  'wrong-PIN limit on customer_verify_pin',             coalesce((select bool_or(position('_rl_locked' in prosrc) > 0) from f where proname = 'customer_verify_pin'), false)),
 ('p0',  'wrong-PIN limit on admin_verify_pin',                coalesce((select bool_or(position('_rl_locked' in prosrc) > 0) from f where proname = 'admin_verify_pin'), false)),
 ('p0',  'wrong-PIN limit on admin_wipe_all_data',             coalesce((select bool_or(position('_rl' in prosrc) > 0) from f where proname = 'admin_wipe_all_data'), false)),
 ('p0',  'auth_rate_limits table closed to the public key',    not has_table_privilege('anon', 'public.auth_rate_limits', 'SELECT')),
 -- November phase 1
 ('p1',  'sessions table exists',                              to_regclass('public.app_sessions') is not null),
 ('p1',  'purchase QR functions exist',                        exists (select 1 from f where proname = 'merchant_scan_code')),
 ('p1',  'Treasures on the server (customer_unlocks.merchant_id)', exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'customer_unlocks' and column_name = 'merchant_id')),
 -- November phase 3 (old functions closed)
 ('p3',  'decide_transaction closed',                          (select not bool_or(anon) from anon_exec where proname = 'decide_transaction')),
 ('p3',  'create_transaction closed',                          (select not bool_or(anon) from anon_exec where proname = 'create_transaction')),
 ('p3',  'admin_list_customers closed',                        (select not bool_or(anon) from anon_exec where proname = 'admin_list_customers')),
 ('p3',  'merchant_transactions closed',                       (select not bool_or(anon) from anon_exec where proname = 'merchant_transactions'))
) as t(phase, fix, applied)
union all
select 'info', 'functions callable with the public key: ' || count(*) filter (where anon) || ' of ' || count(*), null from anon_exec;
