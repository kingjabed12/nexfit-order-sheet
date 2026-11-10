-- Add Delivered as a supported customer status without changing existing records.
alter table public.customers drop constraint if exists customers_status_check;
alter table public.customers
  add constraint customers_status_check
  check (status in ('Confirm','Pending','Problem','Delivered'));
