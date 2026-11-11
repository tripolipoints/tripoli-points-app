# Generates the pass-through *_v2 wrappers, new admin functions, treasure seed and grants of phase 1.
import re, sys, json
OUT = sys.argv[1]; CORE = sys.argv[2]
L = []
def w(s): L.append(s)
w("-- ----------------------------------------------------------------------------------------------------")
w("-- 8b) Merchant pass-through functions: the merchant is the session's, never an id sent by the browser")
w("-- ----------------------------------------------------------------------------------------------------")
M = [  # (name, params after p_session, call args — MID = the session merchant)
 ('merchant_add_offer', "p_type text, p_title text, p_badge text default 'جديد', p_val numeric default null, p_gift_text text default null, p_pts numeric default null, p_per numeric default null, p_old_price numeric default null, p_new_price numeric default null, p_img_url text default null, p_min_amount numeric default 0, p_days integer default 30, p_first_time_only boolean default false, p_specs text default null",
  "MID, p_type, p_title, p_badge, p_val, p_gift_text, p_pts, p_per, p_old_price, p_new_price, p_img_url, p_min_amount, p_days, p_first_time_only, p_specs"),
 ('merchant_create_topup_order', "p_amount numeric, p_points numeric, p_pack_label text default null", "MID, p_amount, p_points, p_pack_label"),
 ('merchant_delete_offer', "p_offer_id uuid", "p_offer_id, MID"),
 ('merchant_gallery_add', "p_name text, p_price numeric, p_img_url text", "MID, p_name, p_price, p_img_url"),
 ('merchant_gallery_delete', "p_item_id uuid", "p_item_id, MID"),
 ('merchant_notes_list', "", "MID"),
 ('merchant_notes_mark_read', "", "MID"),
 ('merchant_offers', "", "MID"),
 ('merchant_request_info_change', "p_name text default null, p_addr text default null", "MID, p_name, p_addr"),
 ('merchant_request_manual_topup', "p_amount numeric, p_points numeric, p_pack_label text default null", "MID, p_amount, p_points, p_pack_label"),
 ('merchant_set_offer_active', "p_offer_id uuid, p_active boolean", "p_offer_id, MID, p_active"),
 ('merchant_set_redeem_pct', "p_redeem_pct numeric, p_redeem_pct_vip numeric default null", "MID, p_redeem_pct, p_redeem_pct_vip"),
 ('merchant_submit_photo', "p_photo_url text", "MID, p_photo_url"),
 ('merchant_topup_orders', "", "MID"),
 ('merchant_update_page', "p_blurb text default null, p_enabled boolean default false", "MID, p_blurb, p_enabled"),
 ('merchant_wallet', "", "MID"),
]
for n, ps, ca in M:
    w(f"create function public.{n}_v2(p_session text{', ' + ps if ps else ''}) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$\n"
      f"declare m public.merchants;\nbegin\n  m := public._sess_merchant(p_session);\n  return public.{n}({ca.replace('MID', 'm.id')});\nend $$;")
w("")
w("-- ----------------------------------------------------------------------------------------------------")
w("-- 9) Admin functions with a session. «P» = primary admin only. Every change is written to tx_events.")
w("-- ----------------------------------------------------------------------------------------------------")
A = [  # (name, params, call args — AID = the session admin, primary?, write?)
 ('admin_add_category', "p_name_ar text, p_parent_id uuid, p_icon text default '▦', p_color text default '#6b7a99', p_image text default null, p_slug text default null", "p_name_ar, p_parent_id, p_icon, p_color, p_image, p_slug", False, True),
 ('admin_approve_merchant_photo', "p_merchant_id uuid", "p_merchant_id", False, True),
 ('admin_delete_customer', "p_phone text", "p_phone, AID", True, True),
 ('admin_delete_merchant', "p_merchant_id uuid", "p_merchant_id, AID", True, True),
 ('admin_delete_offer', "p_offer_id uuid", "p_offer_id", False, True),
 ('admin_force_delete_customer', "p_phone text", "p_phone, AID", True, True),
 ('admin_force_delete_merchant', "p_merchant_id uuid", "p_merchant_id, AID", True, True),
 ('admin_list_all_offers', "", "", False, False),
 ('admin_list_customers', "", "", False, False),
 ('admin_list_merchants', "", "", False, False),
 ('admin_mark_order_collected', "p_order_id uuid", "p_order_id", True, True),
 ('admin_reject_merchant_photo', "p_merchant_id uuid", "p_merchant_id", False, True),
 ('admin_resolve_topup_order', "p_order_id uuid, p_approve boolean", "p_order_id, p_approve", True, True),
 ('admin_review_info_change', "p_merchant_id uuid, p_approve boolean", "p_merchant_id, p_approve", False, True),
 ('admin_set_category_active', "p_id uuid, p_active boolean", "p_id, p_active", False, True),
 ('admin_set_customer_status', "p_phone text, p_status text", "p_phone, p_status", False, True),
 ('admin_set_merchant_category', "p_merchant_id uuid, p_cat text, p_extra_cats text[] default '{}'::text[]", "p_merchant_id, p_cat, p_extra_cats", False, True),
 ('admin_set_merchant_photo', "p_merchant_id uuid, p_photo_url text", "p_merchant_id, p_photo_url", False, True),
 ('admin_set_merchant_status', "p_merchant_id uuid, p_status text", "p_merchant_id, p_status", False, True),
 ('admin_topup_merchant', "p_merchant_id uuid, p_amount numeric, p_source text default 'admin'", "p_merchant_id, p_amount, p_source", True, True),
 ('admin_topup_orders', "", "", False, False),
 ('admin_update_category', "p_id uuid, p_name_ar text default null, p_icon text default null, p_color text default null, p_image text default null, p_sort_order integer default null, p_parent_id uuid default null, p_clear_parent boolean default false", "p_id, p_name_ar, p_icon, p_color, p_image, p_sort_order, p_parent_id, p_clear_parent", False, True),
 ('admin_update_merchant_location', "p_merchant_id uuid, p_lat numeric, p_lng numeric, p_x numeric, p_y numeric, p_addr text default null, p_area text default null", "p_merchant_id, p_lat, p_lng, p_x, p_y, p_addr, p_area", False, True),
 ('admin_update_offer_image', "p_offer_id uuid, p_img_url text default null", "p_offer_id, p_img_url", False, True),
 ('admin_update_text_settings', "p_settings jsonb", "AID, p_settings", True, True),
 ('admin_warn_merchant', "p_merchant_id uuid, p_max_warns integer default 3", "p_merchant_id, p_max_warns", False, True),
]
for n, ps, ca, prim, wr in A:
    ev = f"\n  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', '{n}', 'admin', a.id, 'result', r));" if wr else ""
    w(f"create function public.{n}_v2(p_session text{', ' + ps if ps else ''}) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$\n"
      f"declare a public.admin_users; r jsonb;\nbegin\n  a := public._sess_admin(p_session, {'true' if prim else 'false'});\n"
      f"  r := public.{n}({ca.replace('AID', 'a.id')});{ev}\n  return r;\nend $$;")
w("")
w(r"""create function public.admin_security_feed_v2(p_session text, p_limit integer default 200) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; ev jsonb; rp jsonb;
begin
  a := public._sess_admin(p_session, false);
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'at', floor(extract(epoch from e.at) * 1000), 'event', e.event, 'role', e.actor_role,
           'phone', e.customer_phone, 'mid', e.merchant_id, 'mname', m.name, 'tx', e.tx_id, 'detail', e.detail) order by e.at desc), '[]'::jsonb) into ev
    from (select * from public.tx_events
           where event like 'alert_%' or event in ('reported','scan_failed','decide_hash_mismatch','qr_issue_limited','login_failed','admin_action')
           order by at desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) e
    left join public.merchants m on m.id = e.merchant_id;
  select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'at', floor(extract(epoch from r.created_at) * 1000), 'tx', r.tx_id, 'code', r.code_id,
           'role', r.reporter_role, 'reporter', r.reporter, 'reason', r.reason, 'note', r.note, 'status', r.status) order by r.created_at desc), '[]'::jsonb) into rp
    from (select * from public.tx_reports order by created_at desc limit 300) r;
  return jsonb_build_object('ok', true, 'events', ev, 'reports', rp);
end $$;

create function public.admin_resolve_report_v2(p_session text, p_report_id uuid, p_status text, p_note text default null) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  if p_status not in ('reviewed','dismissed') then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  update public.tx_reports set status = p_status, admin_note = left(p_note, 500), resolved_at = now(), resolved_by = a.id where id = p_report_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_resolve_report_v2', 'admin', a.id, 'report', p_report_id, 'status', p_status));
  return jsonb_build_object('ok', true);
end $$;

-- Full wipe from the app. All of these, in this order, or nothing is deleted:
--   · a session of a PRIMARY admin (not an admin id sent by the browser);
--   · the switch admin_wipe_enabled = 1, which only the project owner can set (SQL editor; it is not in
--     admin_set_setting_v2, so a stolen admin session cannot turn it on). It turns itself off after one wipe;
--   · the exact confirmation phrase «امسح كل البيانات» typed by the admin;
--   · the admin's PIN, with the October limit (key 'admin:<id>', 5 wrong → 15 min, shared with admin_reset_merchant_pin).
-- The work is done by phase 0's admin_wipe_all_data (closed to every API key): it copies every affected table into
-- tp_backup first and returns the copy's stamp; the owner can restore with _tp_wipe_restore('<stamp>').
create function public.admin_wipe_all_data_v2(p_session text, p_pin text, p_confirm text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r jsonb;
begin
  a := public._sess_admin(p_session, true);
  if public._setting('admin_wipe_enabled', 0) <> 1 then
    perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_wipe_all_data_v2', 'admin', a.id, 'result', 'disabled'));
    return jsonb_build_object('ok', false, 'error', 'wipe_disabled', 'message', 'المسح الشامل معطّل. يفعّله صاحب المشروع لمرة واحدة عند الحاجة');
  end if;
  if coalesce(btrim(p_confirm), '') <> 'امسح كل البيانات' then
    return jsonb_build_object('ok', false, 'error', 'confirm', 'message', 'اكتب «امسح كل البيانات» للتأكيد');
  end if;
  r := public.admin_wipe_all_data(a.id, p_pin);
  if coalesce((r->>'ok')::boolean, false) then
    update public.app_settings set value = 0 where key = 'admin_wipe_enabled';
  end if;
  perform public._ev('admin_action', 'admin', null, null, null, null,
    jsonb_build_object('fn', 'admin_wipe_all_data_v2', 'admin', a.id, 'result', coalesce(r->>'reason', case when (r->>'ok')::boolean then 'wiped' else 'refused' end), 'snapshot', r->>'snapshot'));
  return r;
end $$;

-- limits are editable without a migration; only the keys of this phase, inside sane ranges
create function public.admin_settings_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  return (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.app_settings);
end $$;

create function public.admin_set_setting_v2(p_session text, p_key text, p_value numeric) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; lo numeric; hi numeric;
begin
  a := public._sess_admin(p_session, true);
  select x.lo, x.hi into lo, hi from (values
    ('qr_ttl_sec', 60, 900), ('qr_claim_ttl_sec', 60, 1800), ('qr_issue_per_hour', 5, 200), ('scan_fail_limit', 3, 100), ('manual_code_fail_limit', 3, 20),
    ('scan_fail_window_min', 1, 120), ('scan_lock_min', 1, 240), ('login_ip_fail_limit', 10, 500), ('login_window_min', 1, 120),
    ('login_lock_min', 1, 240), ('session_days', 1, 90), ('session_max_days', 7, 365), ('admin_session_hours', 1, 72), ('tx_pending_sec', 60, 1800),
    ('tx_max_invoice', 10, 1000000), ('treasure_min_invoice', 0, 10000), ('profile_photo_max_kb', 30, 400), ('report_per_day', 1, 50),
    ('alert_same_shop_per_day', 2, 100), ('alert_merchant_per_hour', 5, 1000), ('alert_customer_shops_per_hour', 2, 50)) as x(k, lo, hi)
   where x.k = p_key;
  if lo is null then return jsonb_build_object('ok', false, 'error', 'unknown_key'); end if;
  if p_value is null or p_value < lo or p_value > hi then return jsonb_build_object('ok', false, 'error', format('القيمة يجب أن تكون بين %s و %s', lo, hi)); end if;
  insert into public.app_settings(key, value) values (p_key, p_value) on conflict (key) do update set value = excluded.value;
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_set_setting_v2', 'admin', a.id, 'key', p_key, 'value', p_value));
  return jsonb_build_object('ok', true);
end $$;

create function public.admin_treasure_list_v2(p_session text) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users;
begin
  a := public._sess_admin(p_session, false);
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'slug', p.slug, 'name', p.name, 'note', p.note, 'img', p.img_url, 'order', p.display_order,
          'active', p.active, 'unlocked_by', (select count(*) from public.customer_unlocks u where u.pic_id = p.id and u.merchant_id is not null)) order by p.display_order, p.created_at), '[]'::jsonb)
          from public.treasure_pics p);
end $$;

-- add or edit a landmark. Progress already made never changes: an unlock stores its picture, and a new landmark only
-- becomes the next one to discover. Pictures are hidden (active = false), never deleted, so collections stay intact.
create function public.admin_treasure_upsert_v2(p_session text, p_id uuid, p_name text, p_note text default null, p_img_url text default null,
  p_display_order integer default null, p_active boolean default true) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare a public.admin_users; r public.treasure_pics;
begin
  a := public._sess_admin(p_session, false);
  if p_name is null or length(trim(p_name)) = 0 or length(p_name) > 80 then return jsonb_build_object('ok', false, 'error', 'اكتب اسم المعلم'); end if;
  if p_id is null then
    insert into public.treasure_pics(name, note, img_url, display_order, active, slug)
    values (trim(p_name), p_note, p_img_url, coalesce(p_display_order, (select coalesce(max(display_order), 0) + 10 from public.treasure_pics)), coalesce(p_active, true),
            't' || substr(md5(gen_random_uuid()::text), 1, 8))
    returning * into r;
  else
    update public.treasure_pics set name = trim(p_name), note = p_note, img_url = coalesce(p_img_url, img_url),
      display_order = coalesce(p_display_order, display_order), active = coalesce(p_active, active)
     where id = p_id returning * into r;
    if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  perform public._ev('admin_action', 'admin', null, null, null, null, jsonb_build_object('fn', 'admin_treasure_upsert_v2', 'admin', a.id, 'pic', r.id));
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;
""")
w("-- ----------------------------------------------------------------------------------------------------")
w("-- 10) Treasures list (the 11 landmarks of the app today, same order). Adding more later: admin_treasure_upsert_v2.")
w("-- ----------------------------------------------------------------------------------------------------")
P = json.load(open(sys.argv[3]))
vals = ",\n  ".join("('{}', '{}', '{}', '{}', {})".format(p['id'], p['name'].replace("'", "''"), p['note'].replace("'", "''"), p['img'], (i + 1) * 10) for i, p in enumerate(P))
w("-- rows that were already in the table (none in Production today) are kept but hidden, so the official order starts at p1;\n-- an admin can show them again with admin_treasure_upsert_v2.")
w("do $$ declare n int; begin update public.treasure_pics set active = false where slug is null; get diagnostics n = row_count;\n  if n > 0 then raise notice 'treasure_pics: % existing row(s) hidden (active = false)', n; end if; end $$;")
w(f"insert into public.treasure_pics(slug, name, note, img_url, display_order) values\n  {vals}\non conflict (slug) do nothing;")
w("")
# grants: every function this phase creates
core = open(CORE, encoding='utf-8').read() + "\n".join(L)
names = sorted(set(re.findall(r"create function public\.([a-z0-9_]+)\(", core)))
api = [n for n in names if not n.startswith('_')]
w("-- ----------------------------------------------------------------------------------------------------")
w("-- 11) Privileges. Supabase grants EXECUTE on new functions to anon by default: everything is revoked first,")
w("--     then only the API functions (no leading underscore) are granted. Internal helpers stay unreachable.")
w("-- ----------------------------------------------------------------------------------------------------")
w("do $$ declare f regprocedure; begin\n  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[" +
  ", ".join(f"'{n}'" for n in names) + "]) loop\n    execute format('revoke all on function %s from public, anon, authenticated', f);\n  end loop;\n"
  "  for f in select p.oid::regprocedure from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any (array[" +
  ", ".join(f"'{n}'" for n in api) + "]) loop\n    execute format('grant execute on function %s to anon, authenticated', f);\n  end loop;\nend $$;")
w("")
w("commit;")
open(OUT, 'w', encoding='utf-8').write("\n".join(L) + "\n")
json.dump({'all': names, 'api': api}, open(OUT + '.names.json', 'w'), indent=0)
print(len(names), 'functions,', len(api), 'API')
