-- Tripoli Points — STAGING · batch 2 settings ROLLBACK v1.1: restores the exact pre-batch state of the 4 keys.
--  * keys that existed before the batch: never touched (the batch did not change them either);
--  * keys the batch added: removed — but only if their value is still the one the batch inserted. If an Admin has
--    changed it since, it is kept and reported (an Admin decision is never undone by a rollback).
begin;
do $r$
declare k record; v_now text; n_removed int := 0; kept text := '';
begin
  if to_regclass('tp_backup.settings_snapshots') is null then raise exception 'ROLLBACK STOP: no B2 snapshot (batch 2 settings never applied)'; end if;
  for k in execute 'select tbl, key, existed, inserted_value from tp_backup.settings_snapshots where batch = ''B2''' loop
    continue when k.existed;
    v_now := case when k.tbl = 'app_settings' then (select value::text from public.app_settings where key = k.key)
                 else (select value::text from public.app_text_settings where key = k.key) end;
    if v_now is null then continue; end if;
    if v_now::numeric = k.inserted_value::numeric then
      execute format('delete from public.%I where key = $1', k.tbl) using k.key; n_removed := n_removed + 1;
    else kept := kept || format(' %s=%s (changed by an Admin after the batch, kept)', k.key, v_now); end if;
  end loop;
  raise notice 'B2 settings rolled back: % key(s) removed;%', n_removed, case when kept = '' then ' nothing else to do' else kept end;
end $r$;
commit;
