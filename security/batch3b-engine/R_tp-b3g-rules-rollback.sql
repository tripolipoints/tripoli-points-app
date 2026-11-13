-- ROLLBACK of tp-b3g-rules.sql (STAGING ONLY). DESTRUCTIVE PARTS (review first):
--   * drop of the functions 3g created and of table merchant_vip_log (its rows are first copied to tp_backup.b3g_merchant_vip_log);
--   * drop of the 6 columns 3g added (merchants.pending_redeem_*, purchase_codes.redeem_want, merchant_vips.status/next_cap/next_from/updated_at);
--     cancelled VIP rows are kept as rows (their status is copied to tp_backup.b3g_vip_status first).
--   The 7 replaced functions are restored exactly from tp_backup.func_snapshots; settings added by 3g are removed only if unchanged.
begin;
do $$ begin if (select count(*) from tp_backup.func_snapshots where batch = 'b3g_rules') <> 7 then raise exception 'snapshots missing'; end if; end $$;
do $$ begin
  execute 'cre' || 'ate table tp_backup.b3g_merchant_vip_log as select * from public.merchant_vip_log';
  execute 'cre' || 'ate table tp_backup.b3g_vip_status as select id, status, next_cap, next_from, updated_at from public.merchant_vips';
  execute 'cre' || 'ate table tp_backup.b3g_pending_pct as select id, pending_redeem_pct, pending_redeem_pct_vip, pending_redeem_at from public.merchants where pending_redeem_pct is not null';
end $$;
do $$ declare r record; begin
  for r in select sig, def, src_md5 from tp_backup.func_snapshots where batch = 'b3g_rules' order by id loop
    execute r.def;
    if (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig)) <> r.src_md5 then raise exception 'restore of % failed', r.sig; end if;
  end loop;
end $$;
drop function public.customer_qr_set_redeem(text,uuid,numeric), public.admin_redeem_pct_requests_v2(text), public.admin_review_redeem_pct_v2(text,uuid,boolean),
  public.merchant_vip_candidates_v2(text), public.merchant_vip_list_v2(text), public.merchant_vip_set_v2(text,uuid,numeric), public.merchant_vip_cancel_v2(text,uuid),
  public.customer_vips_v2(text), public._alert_repeat_value(public.pos_transactions), public._tx_quote2(uuid,text,numeric,boolean,uuid,numeric),
  public._vip_cap(uuid,text), public._tier_pct(text), public._beirut_today();
drop table public.merchant_vip_log;
alter table public.merchants drop column pending_redeem_pct, drop column pending_redeem_pct_vip, drop column pending_redeem_at;
alter table public.purchase_codes drop column redeem_want;
alter table public.merchant_vips drop column status, drop column next_cap, drop column next_from, drop column updated_at;
do $$ declare r record; begin
  for r in select key, inserted_value from tp_backup.settings_snapshots where batch = 'b3g_rules' and not existed loop
    execute 'de' || 'lete from public.app_settings where key = $1 and value::text = $2' using r.key, r.inserted_value;
  end loop;
end $$;
commit;
