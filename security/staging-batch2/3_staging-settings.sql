-- Tripoli Points — STAGING ONLY: provisional settings so the current engine computes points (Staging app_settings is empty).
-- Values = Production's today. PROVISIONAL / TEST-ONLY: the new rewards engine (batch 4) replaces them with the approved rules.
-- redeem_cap_pct is the LEGACY customer-balance restriction, not the merchant acceptance allowance.
-- Inserting them gives no gift and changes no balance (they are read only when a transaction or a new account is created).
begin;
do $s$
begin
  if current_setting('server_version_num')::int < 0 then raise exception 'never'; end if;
  insert into public.app_settings(key, value) values ('rate_pts_per_usd', 100), ('redeem_cap_pct', 70)
    on conflict (key) do nothing;
  insert into public.app_text_settings(key, value) values ('welcome_bonus', '3000'), ('welcome_days', '7')
    on conflict (key) do nothing;
  raise notice 'staging settings: rate_pts_per_usd=%, redeem_cap_pct=% (legacy), welcome_bonus=%, welcome_days=%',
    (select value from public.app_settings where key = 'rate_pts_per_usd'), (select value from public.app_settings where key = 'redeem_cap_pct'),
    (select value from public.app_text_settings where key = 'welcome_bonus'), (select value from public.app_text_settings where key = 'welcome_days');
end $s$;
commit;
