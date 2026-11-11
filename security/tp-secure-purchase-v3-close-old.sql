-- =====================================================================================================
-- Tripoli Points — PHASE 3: CLOSE THE OLD FUNCTIONS (run only after the app uses the *_v2 functions everywhere)
-- Prepared 2026-11-11 · NOT EXECUTED · requires phase 1 and the phase-2 app on the same environment.
-- After this file, nothing reachable with the public key trusts a phone number, a merchant id or an admin id
-- sent by the browser. Read-only public data (shops, offers, categories, texts, galleries, landmarks) stays open.
-- Undo: tp-security-DANGEROUS-reopen-phase3.sql — reopening old functions reopens their holes, so it is never routine.
-- =====================================================================================================
begin;
do $$ declare f regprocedure; n int := 0; begin
  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in (
      -- replaced by the purchase QR flow
      'create_transaction', 'decide_transaction', 'customer_create_request', 'merchant_requests', 'merchant_close_request',
      -- replaced by login / *_v2 with a session
      'customer_verify_pin', 'merchant_verify_pin', 'admin_verify_pin', 'customer_register', 'merchant_register',
      'customer_profile', 'customer_transactions', 'customer_notes_list',
      'merchant_add_offer', 'merchant_create_topup_order', 'merchant_delete_offer', 'merchant_gallery_add', 'merchant_gallery_delete',
      'merchant_notes_list', 'merchant_offers', 'merchant_request_info_change', 'merchant_request_manual_topup',
      'merchant_set_offer_active', 'merchant_set_redeem_pct', 'merchant_submit_photo', 'merchant_topup_orders', 'merchant_transactions',
      'merchant_update_page', 'merchant_wallet')
     or (p.proname like 'admin\_%' and p.proname not like '%\_v2' and p.proname <> 'admin_reset_merchant_pin')
  loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    n := n + 1;
  end loop;
  raise notice 'phase 3: % old function(s) closed', n;
end $$;
-- still public on purpose (no personal data, read-only): list_merchants, list_active_offers_all, active_offers, get_categories,
-- get_app_text_settings, store_gallery, merchant_gallery_list, treasure_list, customer_check_phone, merchant_check_phone (login screen).
-- Kept from October because they check the PIN themselves, with a lock: merchant_set_logo (phone + PIN), admin_reset_merchant_pin (admin PIN).
commit;

-- Undo: tp-security-DANGEROUS-reopen-phase3.sql (separate on purpose, all statements commented out).
