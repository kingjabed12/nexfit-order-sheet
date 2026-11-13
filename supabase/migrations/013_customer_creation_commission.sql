-- NEXFIT: moderator earns a one-time 20 BDT credit for every customer created.
-- Status changes, moderator reassignment, and customer deletion never reverse this credit.
begin;

create or replace function public.nexfit_customer_commission_trigger()
returns trigger
language plpgsql
security definer
set search_path=public
set row_security=off
as $$
begin
  if new.moderator_id is not null then
    insert into public.moderator_balance_transactions
      (moderator_id, customer_id, amount, kind, note, source_event_id)
    values
      (new.moderator_id, new.id, 20, 'commission',
       'New customer added commission',
       'customer-created:' || new.id::text)
    on conflict (source_event_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists nexfit_customer_commission on public.customers;
create trigger nexfit_customer_commission
after insert on public.customers
for each row
execute function public.nexfit_customer_commission_trigger();

-- Reconcile existing customers to the new rule without changing admin adjustments:
-- each current customer contributes exactly +20 to their currently assigned moderator,
-- and zero to any previous moderator who may have received/reversed a credit before.
with customer_moderator_pairs as (
  select customer_id, moderator_id
  from public.moderator_balance_transactions
  where customer_id is not null
  union
  select id as customer_id, moderator_id
  from public.customers
  where moderator_id is not null
),
customer_net as (
  select p.customer_id,
         p.moderator_id,
         coalesce(sum(t.amount), 0)::numeric(12,2) as net_amount
  from customer_moderator_pairs p
  left join public.moderator_balance_transactions t
    on t.customer_id = p.customer_id
   and t.moderator_id = p.moderator_id
  group by p.customer_id, p.moderator_id
),
corrections as (
  select n.customer_id,
         n.moderator_id,
         (case when c.moderator_id = n.moderator_id then 20 else 0 end - n.net_amount)::numeric(12,2) as delta
  from customer_net n
  join public.customers c on c.id = n.customer_id
)
insert into public.moderator_balance_transactions
  (moderator_id, customer_id, amount, kind, note, source_event_id)
select moderator_id,
       customer_id,
       delta,
       case when delta > 0 then 'commission' else 'reversal' end,
       'One-time adjustment to new per-customer commission policy',
       'customer-credit-policy-v1:' || customer_id::text || ':' || moderator_id::text
from corrections
where delta <> 0
on conflict (source_event_id) do nothing;

commit;
