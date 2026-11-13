-- removes only the four provisional rows added by 0b-staging-settings.sql (Staging)
begin;
delete from public.app_settings where key in ('rate_pts_per_usd', 'redeem_cap_pct');
delete from public.app_text_settings where key in ('welcome_bonus', 'welcome_days');
commit;
