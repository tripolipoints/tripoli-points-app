-- Tripoli Points — read-only audit export of manual transfer requests, credits and wallet notes.
-- Run in the SQL editor of the project (Production), then Download → CSV and keep the file with the date.
-- Changes nothing (single SELECT). Do not edit.
select 'order' as kind, o.ref, o.status, o.method, o.amount, o.points, o.pack_label, o.paid_amount, o.collected,
       o.created_at, o.paid_at, m.name as merchant, m.phone as merchant_phone, o.id::text as record_id,
       (select count(*) from public.topups t where t.ref = o.ref) as credits_with_this_ref,
       (select count(*) from public.topup_orders o2 where o2.merchant_id = o.merchant_id and o2.amount = o.amount
          and o2.id <> o.id and abs(extract(epoch from o2.created_at - o.created_at)) < 120) as same_amount_within_2min
from public.topup_orders o left join public.merchants m on m.id = o.merchant_id
union all
select 'credit', t.ref, null, t.source, t.amount, null, null, null, null, t.created_at, null, m.name, m.phone, t.id::text, null, null
from public.topups t left join public.merchants m on m.id = t.merchant_id
union all
select 'wallet_note', null, n.type, null, null, null, n.title, null, null, n.created_at, null, m.name, m.phone, n.id::text, null, null
from public.merchant_notes n left join public.merchants m on m.id = n.merchant_id where n.type = 'wallet'
order by created_at;
