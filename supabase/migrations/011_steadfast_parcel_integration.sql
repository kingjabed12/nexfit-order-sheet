-- Secure, idempotent SteadFast parcel creation metadata and RPCs.
begin;

alter table public.customers
  add column if not exists steadfast_consignment_id text,
  add column if not exists steadfast_status text,
  add column if not exists steadfast_payload jsonb,
  add column if not exists steadfast_sent_at timestamptz,
  add column if not exists steadfast_error text;

create unique index if not exists customers_steadfast_consignment_id_uidx
  on public.customers(steadfast_consignment_id)
  where steadfast_consignment_id is not null;

create or replace function public.nexfit_claim_steadfast_parcel(
  p_customer_id uuid,
  p_payload jsonb
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

  update public.customers
  set steadfast_status='processing',
      steadfast_payload=p_payload,
      steadfast_error=null,
      updated_at=now()
  where id=p_customer_id
    and steadfast_consignment_id is null
    and (steadfast_status is null or steadfast_status='failed')
    and (public.nexfit_is_admin() or moderator_id=public.nexfit_my_moderator_id());

  if not found then
    raise exception 'Parcel already sent, processing, or not permitted for this account' using errcode='55000';
  end if;
end;
$$;

create or replace function public.nexfit_complete_steadfast_parcel(
  p_customer_id uuid,
  p_consignment_id text
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
  if coalesce(trim(p_consignment_id),'')='' then
    raise exception 'Consignment ID is required' using errcode='22023';
  end if;

  update public.customers
  set steadfast_consignment_id=trim(p_consignment_id),
      steadfast_status='created',
      steadfast_sent_at=now(),
      steadfast_error=null,
      updated_at=now()
  where id=p_customer_id
    and steadfast_status='processing'
    and (public.nexfit_is_admin() or moderator_id=public.nexfit_my_moderator_id());

  if not found then
    raise exception 'Parcel claim not found or not permitted' using errcode='55000';
  end if;
end;
$$;

create or replace function public.nexfit_fail_steadfast_parcel(
  p_customer_id uuid,
  p_status text,
  p_error text
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
  if p_status not in ('failed','unknown') then
    raise exception 'Invalid parcel failure status' using errcode='22023';
  end if;

  update public.customers
  set steadfast_status=p_status,
      steadfast_error=left(coalesce(p_error,''),400),
      updated_at=now()
  where id=p_customer_id
    and steadfast_status='processing'
    and steadfast_consignment_id is null
    and (public.nexfit_is_admin() or moderator_id=public.nexfit_my_moderator_id());

  if not found then
    raise exception 'Parcel claim not found or not permitted' using errcode='55000';
  end if;
end;
$$;

revoke all on function public.nexfit_claim_steadfast_parcel(uuid,jsonb) from public,anon;
revoke all on function public.nexfit_complete_steadfast_parcel(uuid,text) from public,anon;
revoke all on function public.nexfit_fail_steadfast_parcel(uuid,text,text) from public,anon;
grant execute on function public.nexfit_claim_steadfast_parcel(uuid,jsonb) to authenticated;
grant execute on function public.nexfit_complete_steadfast_parcel(uuid,text) to authenticated;
grant execute on function public.nexfit_fail_steadfast_parcel(uuid,text,text) to authenticated;

commit;
