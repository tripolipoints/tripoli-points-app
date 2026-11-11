-- =====================================================================================================
-- Tripoli Points — SECURITY STATUS CHECK · v1.3 (read-only: SELECT only, changes nothing)
-- Run in the SQL editor of Staging and of Production. One row per fix: applied = true / false.
-- Empty (null) = that function does not exist on this database.
-- Answers "is it really on this database?" — a passing local test is not proof that a fix is applied.
-- After phase 0 the behavioural proof is a separate call (it adds throw-away rows inside a step that is undone, so it is
-- not part of this read-only file):   select * from public._phase0_selfcheck() where not ok;   → no rows = all pass.
-- =====================================================================================================
with f as (select p.oid, p.proname, p.pronargs, p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace),
anon_exec as (select f.proname, f.pronargs, has_function_privilege('anon', f.oid, 'EXECUTE') as anon,
                     has_function_privilege('authenticated', f.oid, 'EXECUTE') as authd,
                     has_function_privilege('service_role', f.oid, 'EXECUTE') as svc from f)
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
 ('p0',  'old register / offer / location overloads closed',   (select not bool_or(anon) from anon_exec where (proname = 'customer_register' and pronargs in (3, 5))
                                                                  or (proname = 'merchant_register' and pronargs between 11 and 14)
                                                                  or (proname = 'merchant_add_offer' and pronargs = 14) or (proname = 'admin_update_merchant_location' and pronargs = 6))),
 ('p0',  'admin_wipe_all_data closed to anon + authenticated', (select not bool_or(anon or authd) from anon_exec where proname = 'admin_wipe_all_data')),
 ('p0',  'admin_wipe_all_data closed to service_role too',     (select not bool_or(svc) from anon_exec where proname = 'admin_wipe_all_data')),
 ('p0',  'every wipe copies the data first (tp_backup)',       case when to_regclass('tp_backup.wipe_runs') is null then false
                                                                    else coalesce((select bool_or(position('_tp_wipe_snapshot' in prosrc) > 0) from f where proname = 'admin_wipe_all_data'), false)
                                                                     and exists (select 1 from f where proname = '_tp_wipe_restore') end),
 ('p0',  'backup schema and restore closed to every API key',  case when to_regnamespace('tp_backup') is null then null else not (
                                                                  has_schema_privilege('anon', 'tp_backup', 'USAGE') or has_schema_privilege('authenticated', 'tp_backup', 'USAGE')
                                                                  or has_schema_privilege('service_role', 'tp_backup', 'USAGE')
                                                                  or coalesce((select bool_or(anon or authd or svc) from anon_exec where proname like '\_tp\_wipe\_%'), false)) end),
 ('p0',  'behavioural self-check installed (_phase0_selfcheck)', to_regprocedure('public._phase0_selfcheck()') is not null),
 ('p0',  'v1.3: copy records cannot be deleted or rewritten',  exists (select 1 from pg_trigger where tgrelid = to_regclass('tp_backup.wipe_runs') and tgname = 'wipe_runs_guard')),
 ('p0',  'v1.3: deleting a copy needs a typed confirmation',   to_regprocedure('public._tp_wipe_drop(text,text)') is not null and to_regprocedure('public._tp_wipe_drop(text)') is null),
 ('p0',  'v1.3: manual lock releases are logged',              to_regclass('tp_backup.lock_releases') is not null),
 ('p0',  'v1.3: reviewed PIN / wipe code in place (marker)',    coalesce((select bool_and(position('tp-phase0' in prosrc) > 0) from f
                                                                  where proname in ('customer_verify_pin','admin_verify_pin','admin_wipe_all_data')), false)),
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
-- pre-flight for phase 0: the functions it replaces must be the reviewed code (phase 0 stops otherwise)
select 'pre', x.fn || ' = reviewed version: ' || coalesce(case when p.prosrc like '%tp-phase0%' then 'yes (phase 0 already)'
         when md5(regexp_replace(lower(p.prosrc), '\s+', '', 'g')) = x.h then 'yes' else 'NO — fingerprint ' || md5(regexp_replace(lower(p.prosrc), '\s+', '', 'g')) end, 'MISSING'), null
  from (values ('customer_verify_pin(text,text)', 'c804486649aadaa57bc5a87fc8b6bcdf'), ('admin_verify_pin(text,text)', 'a0e676d3290388fde1feae6f3d17564d'),
               ('admin_wipe_all_data(uuid,text)', 'bd7d4982c8e56ca244c87eda058356f3')) x(fn, h)
  left join pg_proc p on p.oid = to_regprocedure('public.' || x.fn)
union all
select 'pre', 'October helpers present (_rl_locked, _rl_record_fail, _rl_reset, auth_rate_limits): ' ||
       (to_regclass('public.auth_rate_limits') is not null and to_regprocedure('public._rl_locked(text)') is not null
        and to_regprocedure('public._rl_record_fail(text)') is not null and to_regprocedure('public._rl_reset(text)') is not null)::text, null
union all
select 'info', 'service_role (Whish callback) can execute whish_confirm_payment: ' || coalesce(bool_or(svc)::text, 'function missing'), null
  from anon_exec where proname = 'whish_confirm_payment'
union all
select 'info', 'functions callable with the public key: ' || count(*) filter (where anon) || ' of ' || count(*), null from anon_exec;
