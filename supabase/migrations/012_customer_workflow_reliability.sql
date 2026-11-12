-- NEXFIT reliability patch: create customers through a validated server-side RPC,
-- and reassert the status-only RPC used by every role.
begin;

create or replace function public.nexfit_create_customer(
  p_customer_name text,
  p_customer_details text,
  p_customer_contact_phone text,
  p_customer_address text,
  p_product_images jsonb,
  p_phone text,
  p_moderator_id uuid,
  p_status text,
  p_notes text
)
returns uuid
language plpgsql
security definer
set search_path=public
set row_security=off
as $$
declare
  v_phone text;
  v_customer_id uuid;
  v_my_moderator_id uuid;
begin
  if not public.nexfit_is_active_user() then
    raise exception 'Active NEXFIT account required' using errcode='42501';
  end if;

  v_phone := public.normalize_bd_phone(p_phone);
  if v_phone is null then
    raise exception 'Enter a valid Bangladesh mobile number' using errcode='22023';
  end if;

  if p_status not in ('Confirm','Pending','Problem','Delivered') then
    raise exception 'Invalid customer status' using errcode='22023';
  end if;

  if jsonb_typeof(coalesce(p_product_images,'[]'::jsonb)) <> 'array' then
    raise exception 'Product images must be a list' using errcode='22023';
  end if;

  if public.nexfit_is_admin() then
    if p_moderator_id is null or not exists (
      select 1 from public.moderators m where m.id=p_moderator_id and m.active=true
    ) then
      raise exception 'Select an active Moderator' using errcode='22023';
    end if;
  else
    v_my_moderator_id := public.nexfit_my_moderator_id();
    if v_my_moderator_id is null or p_moderator_id is distinct from v_my_moderator_id then
      raise exception 'You can add customers only to your own active account' using errcode='42501';
    end if;
  end if;

  insert into public.customers(
    customer_name,customer_details,customer_contact_phone,customer_address,
    product_images,phone,normalized_phone,moderator_id,status,notes
  ) values (
    coalesce(trim(p_customer_name),''),
    coalesce(trim(p_customer_details),''),
    coalesce(trim(p_customer_contact_phone),''),
    coalesce(trim(p_customer_address),''),
    coalesce(p_product_images,'[]'::jsonb),
    v_phone,v_phone,p_moderator_id,p_status,coalesce(trim(p_notes),'')
  )
  returning id into v_customer_id;

  return v_customer_id;
exception
  when unique_violation then
    raise exception 'This WhatsApp number is already added' using errcode='23505';
end;
$$;

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
  set status=p_status, updated_at=now()
  where id=p_customer_id;

  if not found then
    raise exception 'Customer not found' using errcode='P0002';
  end if;
end;
$$;

revoke all on function public.nexfit_create_customer(text,text,text,text,jsonb,text,uuid,text,text) from public,anon;
revoke all on function public.nexfit_change_customer_status(uuid,text) from public,anon;
grant execute on function public.nexfit_create_customer(text,text,text,text,jsonb,text,uuid,text,text) to authenticated;
grant execute on function public.nexfit_change_customer_status(uuid,text) to authenticated;

commit;
