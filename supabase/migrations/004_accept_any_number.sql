-- Allow any non-empty digit sequence as a WhatsApp/contact identifier.
-- Keep Bangladesh prefix normalization when recognizable, but do not reject other lengths.
create or replace function public.normalize_bd_phone(raw text)
returns text language plpgsql immutable as $$
declare n text;
begin
  n := regexp_replace(coalesce(raw,''), '[^0-9]', '', 'g');
  if left(n,5) = '00880' then n := substring(n from 3); end if;
  if left(n,3) = '880' then n := '0' || substring(n from 4); end if;
  if length(n) = 10 and left(n,1) = '1' then n := '0' || n; end if;
  if n = '' then return null; end if;
  return n;
end $$;

create or replace function public.customers_before_write()
returns trigger language plpgsql as $$
declare n text;
begin
  n := public.normalize_bd_phone(coalesce(new.phone,new.normalized_phone));
  if n is null then
    raise exception 'Please enter at least one digit for the WhatsApp number' using errcode='22023';
  end if;
  new.phone := n;
  new.normalized_phone := n;
  if tg_op = 'UPDATE' then new.updated_at := now(); end if;
  return new;
end $$;

drop trigger if exists customers_normalize_trigger on public.customers;
create trigger customers_normalize_trigger
before insert or update on public.customers
for each row execute function public.customers_before_write();

-- Keep only the three status choices used by the updated app.
alter table public.customers drop constraint if exists customers_status_check;
update public.customers
set status = case
  when status in ('Order Confirmed','Convinced','Confirm') then 'Confirm'
  when status in ('Not Interested','Problem') then 'Problem'
  else 'Pending'
end;
alter table public.customers alter column status set default 'Pending';
alter table public.customers
  add constraint customers_status_check check (status in ('Confirm','Pending','Problem'));
