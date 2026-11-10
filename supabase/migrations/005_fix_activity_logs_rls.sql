-- Fix activity log writes performed by the customer trigger.
-- The trigger runs as the function owner so the browser's anon role does not
-- need direct INSERT permission on activity_logs.
create or replace function public.log_customer_activity()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  actor text;
begin
  if tg_op = 'DELETE' then
    select m.name into actor
    from public.moderators as m
    where m.id = old.moderator_id;

    insert into public.activity_logs(customer_id, action, details, actor_name)
    values (old.id, 'Customer deleted', old.phone, coalesce(actor, 'Shared user'));
    return old;

  elsif tg_op = 'INSERT' then
    select m.name into actor
    from public.moderators as m
    where m.id = new.moderator_id;

    insert into public.activity_logs(customer_id, action, details, actor_name)
    values (new.id, 'Customer added', new.phone, coalesce(actor, 'Shared user'));
    return new;

  else
    select m.name into actor
    from public.moderators as m
    where m.id = new.moderator_id;

    if old.status is distinct from new.status
       or old.notes is distinct from new.notes
       or old.phone is distinct from new.phone
       or old.moderator_id is distinct from new.moderator_id then
      insert into public.activity_logs(customer_id, action, details, actor_name)
      values (new.id, 'Customer updated', new.phone || ' · ' || new.status, coalesce(actor, 'Shared user'));
    end if;
    return new;
  end if;
end;
$$;
