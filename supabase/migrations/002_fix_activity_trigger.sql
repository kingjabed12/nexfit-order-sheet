create or replace function public.log_customer_activity()
returns trigger
language plpgsql
as $$
declare
  actor text;
begin
  if tg_op = 'DELETE' then
    select name into actor
    from public.moderators
    where id = old.moderator_id;

    insert into public.activity_logs(customer_id, action, details, actor_name)
    values(old.id, 'Customer deleted', old.phone, coalesce(actor, 'Shared user'));

    return old;

  elsif tg_op = 'INSERT' then
    select name into actor
    from public.moderators
    where id = new.moderator_id;

    insert into public.activity_logs(customer_id, action, details, actor_name)
    values(new.id, 'Customer added', new.phone, coalesce(actor, 'Shared user'));

    return new;

  else
    select name into actor
    from public.moderators
    where id = new.moderator_id;

    if old.status is distinct from new.status
       or old.notes is distinct from new.notes
       or old.phone is distinct from new.phone then
      insert into public.activity_logs(customer_id, action, details, actor_name)
      values(new.id, 'Customer updated', new.phone || ' · ' || new.status, coalesce(actor, 'Shared user'));
    end if;

    return new;
  end if;
end;
$$;