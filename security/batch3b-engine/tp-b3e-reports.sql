-- =====================================================================================================
-- Tripoli Points — BATCH 3e: complaints (reports) fixes (STAGING ONLY)
-- 1. Bug fix: report_tx cancels a still-pending purchase but did not give the branch allowance reservation back.
--    It now releases it, exactly like a cancel by the shop or the customer.
-- 2. Notification: when an admin reviews / dismisses a report, the reporter (customer or shop) gets a note.
-- Two existing functions are text-patched (one line each, md5-guarded); their previous text is saved in
-- tp_backup.func_snapshots (batch 'b3e_reports'). No table, row or privilege is changed. No drop / delete.
-- Rollback: R_tp-b3e-reports-rollback.sql
-- =====================================================================================================
begin;

do $$
declare r record; cur text; d text; n int;
begin
  for r in select * from (values
    ('report_tx(text,text,uuid,uuid,text)', 'f5a8d6ceee08ea2d9d567acae01a70d2',
     'update public.pos_transactions set status = ''CANCELLED'', decided_at = now() where id = t.id and status = ''PENDING'';',
     'update public.pos_transactions set status = ''CANCELLED'', decided_at = now() where id = t.id and status = ''PENDING''; perform public._allow_release(t.id, ''reported''); /* B3E */'),
    ('admin_resolve_report_v2(text,uuid,text,text)', '7e41661f408dc1636d305daede9bcb63',
     'if not found then return jsonb_build_object(''ok'', false, ''error'', ''not_found''); end if;',
     'if not found then return jsonb_build_object(''ok'', false, ''error'', ''not_found''); end if; perform public._report_notify(p_report_id); /* B3E */')
  ) v(sig, want, old, new) loop
    cur := (select md5(prosrc) from pg_proc where oid = to_regprocedure('public.' || r.sig));
    if cur is distinct from r.want then raise exception '% differs (md5 %), stop', r.sig, cur; end if;
    d := pg_get_functiondef(to_regprocedure('public.' || r.sig));
    insert into tp_backup.func_snapshots(batch, sig, def, src_md5) values ('b3e_reports', r.sig, d, cur);
    n := (length(d) - length(replace(d, r.old, ''))) / length(r.old);
    if n <> 1 then raise exception 'patch target found % times in %', n, r.sig; end if;
    perform set_config('tp.b3e_def_' || md5(r.sig), replace(d, r.old, r.new), true);
  end loop;
end $$;

-- note to the reporter after an admin decision (internal helper)
create function public._report_notify(p_report_id uuid) returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.tx_reports; msg text;
begin
  select * into r from public.tx_reports where id = p_report_id;
  if r.id is null then return; end if;
  msg := case r.status when 'reviewed' then 'راجعت الإدارة بلاغك واتخذت الإجراء المناسب' else 'راجعت الإدارة بلاغك وأغلقته' end;
  if r.reporter_role = 'customer' then
    insert into public.customer_notes(customer_phone, type, title, body) values (r.reporter, 'general', msg, nullif(r.admin_note, ''));
  elsif r.reporter ~ '^[0-9a-f-]{36}$' then
    insert into public.merchant_notes(merchant_id, type, title, body) values (r.reporter::uuid, 'info', msg, nullif(r.admin_note, ''));
  end if;
end $$;
revoke all on function public._report_notify(uuid) from public, anon, authenticated;

do $$
declare s text;
begin
  foreach s in array array['report_tx(text,text,uuid,uuid,text)', 'admin_resolve_report_v2(text,uuid,text,text)'] loop
    execute current_setting('tp.b3e_def_' || md5(s));
  end loop;
  if not has_function_privilege('anon', 'public.report_tx(text,text,uuid,uuid,text)', 'execute') then raise exception 'report_tx lost its grant'; end if;
  if has_function_privilege('anon', 'public._report_notify(uuid)', 'execute') then raise exception '_report_notify reachable by anon'; end if;
end $$;

commit;
