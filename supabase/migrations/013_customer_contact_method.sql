-- NEXFIT contact method: WhatsApp number OR Messenger profile name/ID.
begin;

alter table public.customers
  add column if not exists contact_method text not null default 'whatsapp',
  add column if not exists messenger_id text not null default '';

alter table public.customers
  drop constraint if exists customers_contact_method_check;
alter table public.customers
  add constraint customers_contact_method_check
  check (contact_method in ('whatsapp','messenger'));

-- Messenger-only orders do not have a WhatsApp phone number.
alter table public.customers alter column phone drop not null;
alter table public.customers alter column normalized_phone drop not null;

drop function if exists public.nexfit_create_customer(text,text,text,text,jsonb,text,uuid,text,text);

create function public.nexfit_create_customer(
  p_customer_name text,
  p_customer_details text,
  p_customer_contact_phone text,
  p_customer_address text,
  p_product_images jsonb,
  p_phone text,
  p_moderator_id uuid,
  p_status text,
  p_notes text,
  p_contact_method text default 'whatsapp',
  p_messenger_id text default ''
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

  if p_contact_method not in ('whatsapp','messenger') then
    raise exception 'Select WhatsApp or Messenger' using errcode='22023';
  end if;

  if p_contact_method='whatsapp' then
    v_phone := public.normalize_bd_phone(p_phone);
    if v_phone is null then
      raise exception 'Enter a valid Bangladesh WhatsApp number' using errcode='22023';
    end if;
  else
    if nullif(trim(coalesce(p_messenger_id,'')),'') is null then
      raise exception 'Enter Messenger ID or Facebook name' using errcode='22023';
    end if;
    v_phone := null;
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
    product_images,phone,normalized_phone,moderator_id,status,notes,
    contact_method,messenger_id
  ) values (
    coalesce(trim(p_customer_name),''),
    coalesce(trim(p_customer_details),''),
    coalesce(trim(p_customer_contact_phone),''),
    coalesce(trim(p_customer_address),''),
    coalesce(p_product_images,'[]'::jsonb),
    v_phone,v_phone,p_moderator_id,p_status,coalesce(trim(p_notes),''),
    p_contact_method,case when p_contact_method='messenger' then trim(p_messenger_id) else '' end
  )
  returning id into v_customer_id;

  return v_customer_id;
exception
  when unique_violation then
    raise exception 'This WhatsApp number is already added' using errcode='23505';
end;
$$;

revoke all on function public.nexfit_create_customer(text,text,text,text,jsonb,text,uuid,text,text,text,text) from public,anon;
grant execute on function public.nexfit_create_customer(text,text,text,text,jsonb,text,uuid,text,text,text,text) to authenticated;

commit;
