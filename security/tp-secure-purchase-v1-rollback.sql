-- =====================================================================================================
-- Tripoli Points — PHASE 1 ROLLBACK (STAGING) — undoes tp-secure-purchase-v1.sql completely
-- Removes only what phase 1 added. Existing points, purchases, notes, customers and merchants are not touched.
-- What is lost: sessions (everyone signs in again with the old app), purchase codes, the new event log and reports,
-- saved profile timestamps, and treasure pictures unlocked by the new system (customer_unlocks rows with a shop).
-- Names, family names and photos saved through customer_update_profile stay in the customers table (existing columns).
-- =====================================================================================================
begin;
do $$ begin
  if to_regclass('public.app_sessions') is null then raise exception 'phase 1 is not applied — nothing to roll back'; end if;
end $$;

-- 1) functions created by phase 1 (100)
do $$ declare f regprocedure; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace
             and p.proname = any (array['_alerts_after_confirm', '_b64url', '_claim_for', '_client_ip', '_customer_json', '_ev', '_expire_pending', '_issue_session', '_login_allowed', '_login_failed', '_merchant_json', '_rl2_hit', '_rl2_locked', '_rl2_reset', '_sess', '_sess_admin', '_sess_any', '_sess_customer', '_sess_merchant', '_setting', '_sha', '_tx_hash', '_tx_json', '_tx_quote', '_unlock_treasure', 'admin_add_category_v2', 'admin_approve_merchant_photo_v2', 'admin_delete_customer_v2', 'admin_delete_merchant_v2', 'admin_delete_offer_v2', 'admin_force_delete_customer_v2', 'admin_force_delete_merchant_v2', 'admin_list_all_offers_v2', 'admin_list_customers_v2', 'admin_list_merchants_v2', 'admin_login', 'admin_mark_order_collected_v2', 'admin_reject_merchant_photo_v2', 'admin_resolve_report_v2', 'admin_resolve_topup_order_v2', 'admin_review_info_change_v2', 'admin_security_feed_v2', 'admin_set_category_active_v2', 'admin_set_customer_status_v2', 'admin_set_merchant_category_v2', 'admin_set_merchant_photo_v2', 'admin_set_merchant_status_v2', 'admin_set_setting_v2', 'admin_settings_v2', 'admin_topup_merchant_v2', 'admin_topup_orders_v2', 'admin_treasure_list_v2', 'admin_treasure_upsert_v2', 'admin_update_category_v2', 'admin_update_merchant_location_v2', 'admin_update_offer_image_v2', 'admin_update_text_settings_v2', 'admin_warn_merchant_v2', 'admin_wipe_all_data_v2', 'customer_decide_tx_v2', 'customer_login', 'customer_notes_list_v2', 'customer_notes_mark_read_v2', 'customer_profile_v2', 'customer_qr_issue', 'customer_qr_status', 'customer_transactions_v2', 'customer_treasures_v2', 'customer_update_profile', 'merchant_add_offer_v2', 'merchant_cancel_tx', 'merchant_create_topup_order_v2', 'merchant_create_tx_v2', 'merchant_delete_offer_v2', 'merchant_gallery_add_v2', 'merchant_gallery_delete_v2', 'merchant_login', 'merchant_me_v2', 'merchant_notes_list_v2', 'merchant_notes_mark_read_v2', 'merchant_offers_v2', 'merchant_quote_v2', 'merchant_request_info_change_v2', 'merchant_request_manual_topup_v2', 'merchant_scan_code', 'merchant_set_offer_active_v2', 'merchant_set_redeem_pct_v2', 'merchant_submit_photo_v2', 'merchant_topup_orders_v2', 'merchant_transactions_v2', 'merchant_update_page_v2', 'merchant_wallet_v2', 'report_tx', 'session_list', 'session_logout', 'session_logout_all', 'session_revoke', 'treasure_list']) loop
    execute format('drop function %s cascade', f);
  end loop;
end $$;

-- 2) triggers
drop trigger if exists customer_unlocks_skip_legacy on public.customer_unlocks;
drop trigger if exists customers_revoke_sessions on public.customers;
drop trigger if exists merchants_revoke_sessions on public.merchants;
drop trigger if exists admin_users_revoke_sessions on public.admin_users;
drop function if exists public._tr_unlocks_skip_legacy();
drop function if exists public._tr_revoke_sessions();

-- 3) treasures: new-system unlocks and the seeded landmarks go; the original unique key comes back
delete from public.customer_unlocks where merchant_id is not null;
drop index if exists public.customer_unlocks_phone_cycle_shop_uidx;
alter table public.customer_unlocks drop constraint if exists customer_unlocks_phone_cycle_pic_key;
alter table public.customer_unlocks drop column if exists merchant_id, drop column if exists tx_id, drop column if exists cycle, drop column if exists seq;
alter table public.customer_unlocks add constraint customer_unlocks_customer_phone_pic_id_key unique (customer_phone, pic_id);
delete from public.treasure_pics where slug is not null;
alter table public.treasure_pics drop column if exists slug, drop column if exists active;

-- 4) columns on existing tables (purchases made through the new flow stay, as ordinary rows)
drop index if exists public.pos_transactions_code_uidx;
drop index if exists public.pos_transactions_idem_uidx;
drop index if exists public.pos_transactions_customer_idx;
drop index if exists public.pos_transactions_merchant_idx;
alter table public.pos_transactions drop column if exists code_id, drop column if exists idem_key, drop column if exists offer_id,
  drop column if exists disc, drop column if exists bonus, drop column if exists detail_hash, drop column if exists decided_at;
alter table public.customers drop column if exists profile_completed_at, drop column if exists treasure_cycle, drop column if exists photo_hash;

-- 5) new tables
drop table if exists public.purchase_codes;
drop table if exists public.tx_reports;
drop table if exists public.tx_events;
drop table if exists public.rate_counters;
drop table if exists public.app_sessions;

-- 6) settings added by phase 1 (rate_pts_per_usd and redeem_cap_pct are not touched)
--    phase 0 objects (PIN limits, closed wipe, tp_backup copies, _tp_wipe_*) are not touched: they are protections
delete from public.app_settings where key in ('qr_ttl_sec','qr_claim_ttl_sec','qr_issue_per_hour','scan_fail_limit','manual_code_fail_limit',
  'scan_fail_window_min','scan_lock_min','login_fail_limit','login_ip_fail_limit','login_window_min','login_lock_min','session_days',
  'session_max_days','admin_session_hours','tx_pending_sec','tx_max_invoice','treasure_min_invoice','profile_photo_max_kb','report_per_day',
  'alert_same_shop_per_day','alert_merchant_per_hour','alert_customer_shops_per_hour','admin_wipe_enabled');

commit;
