-- Allow active moderators to change only a customer's order status,
-- including customers assigned to another moderator. All other customer
-- fields remain protected by the existing row-level security policies.
begin;

create or replace function public.nexfit_change_customer_status(
  p_customer_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path=public
set row_security=off
as $$
begin
  if not public.nexfit_is_active_user() then
    raise exception 'Active NEXFIT account required' using errcode='42501';
  end if;

  if p_status not in ('Confirm','Pending','Problem','Delivered') then
    raise exception 'Invalid customer status' using errcode='22023';
  end if;

  update public.customers
  set status=p_status,
      updated_at=now()
  where id=p_customer_id;

  if not found then
    raise exception 'Customer not found' using errcode='P0002';
  end if;
end;
$$;

revoke all on function public.nexfit_change_customer_status(uuid,text) from public,anon;
grant execute on function public.nexfit_change_customer_status(uuid,text) to authenticated;

commit;
