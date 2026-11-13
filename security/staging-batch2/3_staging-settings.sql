-- Tripoli Points — STAGING ONLY · batch 2 settings v1.1 · 2026-11-13
-- Fills ONLY settings that are missing on Staging; never changes a value that already exists (including the gift amount
-- and validity the Admin set in «هدية الترحيب»). Values used when missing = Production's today, marked PROVISIONAL:
--   rate_pts_per_usd = 100 · redeem_cap_pct = 70 (LEGACY customer-balance restriction, not the merchant allowance)
--   welcome_bonus = 3000 · welcome_days = 7 (the latest Admin gift configuration)
-- Records the exact state of each of the 4 keys before the batch in tp_backup.settings_snapshots (batch 'B2'),
-- so the rollback restores exactly that state. Gives no gift and changes no balance.
begin;
do $s$
declare k record; v_old text; v_existed boolean; n_added int := 0;
begin
  execute 'create schema if not exists tp_backup';
  execute 'revoke all on schema tp_backup from public, anon, authenticated';
  if to_regclass('tp_backup.settings_snapshots') is null then
    execute 'cre' || 'ate table tp_backup.settings_snapshots (id bigint generated always as identity primary key, batch text not null, '
         || 'tbl text not null, key text not null, existed boolean not null, old_value text, inserted_value text, taken_at timestamptz not null default now(), unique (batch, tbl, key))';
    execute 'alter table tp_backup.settings_snapshots enable row level security';
    execute 'revoke all on tp_backup.settings_snapshots from public, anon, authenticated';
  end if;
  for k in select * from (values ('app_settings','rate_pts_per_usd','100'), ('app_settings','redeem_cap_pct','70'),
                                 ('app_text_settings','welcome_bonus','3000'), ('app_text_settings','welcome_days','7')) t(tbl, key, val) loop
    v_old := case when k.tbl = 'app_settings' then (select value::text from public.app_settings where key = k.key)
                 else (select value::text from public.app_text_settings where key = k.key) end;
    v_existed := v_old is not null;
    execute 'insert ' || 'into tp_backup.settings_snapshots(batch, tbl, key, existed, old_value, inserted_value) values (''B2'', $1, $2, $3, $4, $5) on conflict (batch, tbl, key) do nothing'
      using k.tbl, k.key, v_existed, v_old, case when v_existed then null else k.val end;
    if not v_existed then
      if k.tbl = 'app_settings' then execute 'insert ' || 'into public.app_settings(key, value) values ($1, $2::numeric)' using k.key, k.val;
      else execute 'insert ' || 'into public.app_text_settings(key, value) values ($1, $2)' using k.key, k.val; end if;
      n_added := n_added + 1;
    end if;
  end loop;
  raise notice 'B2 settings: % missing key(s) added, existing values untouched. Now: rate=%, legacy cap=%, welcome_bonus=%, welcome_days=%', n_added,
    (select value from public.app_settings where key = 'rate_pts_per_usd'), (select value from public.app_settings where key = 'redeem_cap_pct'),
    (select value from public.app_text_settings where key = 'welcome_bonus'), (select value from public.app_text_settings where key = 'welcome_days');
end $s$;
commit;
