-- Upgrade existing customer statuses without deleting customer records.
alter table public.customers drop constraint if exists customers_status_check;
alter table public.customers drop constraint if exists customers_status_valid_check;
update public.customers
set status = case
  when status in ('Order Confirmed','Convinced','Confirm') then 'Confirm'
  when status in ('Not Interested','Problem') then 'Problem'
  else 'Pending'
end;
alter table public.customers alter column status set default 'Pending';
alter table public.customers
  add constraint customers_status_check check (status in ('Confirm','Pending','Problem'));
