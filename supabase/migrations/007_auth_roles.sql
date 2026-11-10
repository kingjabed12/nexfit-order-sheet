-- NEXFIT authenticated accounts and role-based access
create extension if not exists pgcrypto;

create table if not exists public.nexfit_user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  role text not null check (role in ('admin','moderator')),
  moderator_id uuid references public.moderators(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint nexfit_profile_role_link check (
    (role = 'admin' and moderator_id is null) or
    (role = 'moderator' and moderator_id is not null)
  )
);
create unique index if not exists nexfit_one_login_per_moderator
  on public.nexfit_user_profiles(moderator_id) where moderator_id is not null;
alter table public.activity_logs add column if not exists actor_user_id uuid;

create table if not exists public.nexfit_setup_secret (
  id boolean primary key default true check (id),
  secret_hash bytea
);
insert into public.nexfit_setup_secret(id, secret_hash)
values (true, decode('376f26dbb414b0fafceaa8f65eff2e5154968aba8107900568311ebae0f2100e','hex'))
on conflict (id) do nothing;

create or replace function public.nexfit_is_admin()
returns boolean language sql stable security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.nexfit_user_profiles p
    where p.user_id = auth.uid() and p.role = 'admin' and p.active = true
  );
$$;

create or replace function public.nexfit_my_moderator_id()
returns uuid language sql stable security definer
set search_path = public, auth
as $$
  select p.moderator_id
  from public.nexfit_user_profiles p
  join public.moderators m on m.id = p.moderator_id and m.active = true
  where p.user_id = auth.uid() and p.role = 'moderator' and p.active = true
  limit 1;
$$;

create or replace function public.nexfit_bootstrap_admin(p_setup_code text)
returns jsonb language plpgsql security definer
set search_path = public, auth, extensions
as $$
declare stored_hash bytea;
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  if exists(select 1 from public.nexfit_user_profiles where role='admin') then
    raise exception 'Admin is already configured';
  end if;
  select secret_hash into stored_hash from public.nexfit_setup_secret where id=true for update;
  if stored_hash is null or digest(coalesce(p_setup_code,''),'sha256') <> stored_hash then
    raise exception 'Invalid setup code';
  end if;
  insert into public.nexfit_user_profiles(user_id,username,role,moderator_id,active)
  values(auth.uid(),'admin','admin',null,true);
  update public.nexfit_setup_secret set secret_hash=null where id=true;
  return jsonb_build_object('role','admin','username','admin');
end;
$$;

create or replace function public.nexfit_admin_create_moderator(
  p_user_id uuid, p_username text, p_name text
) returns uuid language plpgsql security definer
set search_path = public, auth, extensions
as $$
declare mid uuid; uname text;
begin
  if not public.nexfit_is_admin() then raise exception 'Admin access required'; end if;
  uname := lower(trim(p_username));
  if uname !~ '^[a-z0-9_]{3,24}$' or uname = 'admin' then
    raise exception 'Username must be 3-24 characters (a-z, 0-9, underscore)';
  end if;
  if length(trim(p_name)) < 2 then raise exception 'Enter moderator name'; end if;
  if exists(select 1 from public.nexfit_user_profiles where username=uname) then
    raise exception 'This username is already in use';
  end if;
  select m.id into mid
  from public.moderators m
  where lower(m.name)=lower(trim(p_name)) and m.active=true
    and not exists(select 1 from public.nexfit_user_profiles p where p.moderator_id=m.id)
  order by m.created_at limit 1;
  if mid is null then
    insert into public.moderators(name,active) values(trim(p_name),true) returning id into mid;
  end if;
  insert into public.nexfit_user_profiles(user_id,username,role,moderator_id,active)
  values(p_user_id,uname,'moderator',mid,true);
  return mid;
end;
$$;

create or replace function public.nexfit_admin_set_moderator_active(
  p_moderator_id uuid, p_active boolean
) returns void language plpgsql security definer
set search_path = public, auth, extensions
as $$
begin
  if not public.nexfit_is_admin() then raise exception 'Admin access required'; end if;
  update public.moderators set active=p_active where id=p_moderator_id;
  update public.nexfit_user_profiles set active=p_active where moderator_id=p_moderator_id;
  if not found then raise exception 'Moderator account not found'; end if;
end;
$$;

create or replace function public.nexfit_admin_reset_moderator_password(
  p_moderator_id uuid, p_new_password text
) returns void language plpgsql security definer
set search_path = public, auth, extensions
as $$
declare target_user uuid;
begin
  if not public.nexfit_is_admin() then raise exception 'Admin access required'; end if;
  if length(coalesce(p_new_password,'')) < 8 then raise exception 'Password must be at least 8 characters'; end if;
  select user_id into target_user from public.nexfit_user_profiles
  where moderator_id=p_moderator_id and role='moderator';
  if target_user is null then raise exception 'Moderator login not found'; end if;
  update auth.users
  set encrypted_password=crypt(p_new_password, gen_salt('bf')), updated_at=now()
  where id=target_user;
  delete from auth.sessions where user_id=target_user;
end;
$$;

-- Remove all previous open/shared policies before enabling authenticated access.
do $$
declare pol record;
begin
  for pol in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname='public'
      and tablename in ('moderators','customers','activity_logs','nexfit_user_profiles','nexfit_setup_secret')
  loop
    execute format('drop policy if exists %I on %I.%I',pol.policyname,pol.schemaname,pol.tablename);
  end loop;
end $$;

alter table public.nexfit_user_profiles enable row level security;
alter table public.nexfit_setup_secret enable row level security;
alter table public.moderators enable row level security;
alter table public.customers enable row level security;
alter table public.activity_logs enable row level security;

create policy "nexfit profile read" on public.nexfit_user_profiles
for select to authenticated using (user_id=auth.uid() or public.nexfit_is_admin());

create policy "nexfit moderators read" on public.moderators
for select to authenticated using (public.nexfit_is_admin() or id=public.nexfit_my_moderator_id());
create policy "nexfit moderators admin insert" on public.moderators
for insert to authenticated with check (public.nexfit_is_admin());
create policy "nexfit moderators admin update" on public.moderators
for update to authenticated using (public.nexfit_is_admin()) with check (public.nexfit_is_admin());
create policy "nexfit moderators admin delete" on public.moderators
for delete to authenticated using (public.nexfit_is_admin());

create policy "nexfit customers read" on public.customers
for select to authenticated using (public.nexfit_is_admin() or moderator_id=public.nexfit_my_moderator_id());
create policy "nexfit customers insert" on public.customers
for insert to authenticated with check (public.nexfit_is_admin() or moderator_id=public.nexfit_my_moderator_id());
create policy "nexfit customers update" on public.customers
for update to authenticated using (public.nexfit_is_admin() or moderator_id=public.nexfit_my_moderator_id())
with check (public.nexfit_is_admin() or moderator_id=public.nexfit_my_moderator_id());
create policy "nexfit customers delete" on public.customers
for delete to authenticated using (public.nexfit_is_admin() or moderator_id=public.nexfit_my_moderator_id());

create policy "nexfit activity read" on public.activity_logs
for select to authenticated using (public.nexfit_is_admin() or actor_user_id=auth.uid());

create or replace function public.log_customer_activity()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, auth, extensions
as $$
declare actor text; actor_id uuid;
begin
  actor_id := auth.uid();
  if tg_op='DELETE' then
    select p.username into actor from public.nexfit_user_profiles p where p.user_id=actor_id;
    if actor is null then select m.name into actor from public.moderators m where m.id=old.moderator_id; end if;
    insert into public.activity_logs(customer_id,action,details,actor_name,actor_user_id)
    values(old.id,'Customer deleted',old.phone,coalesce(actor,'System'),actor_id);
    return old;
  elsif tg_op='INSERT' then
    select p.username into actor from public.nexfit_user_profiles p where p.user_id=actor_id;
    if actor is null then select m.name into actor from public.moderators m where m.id=new.moderator_id; end if;
    insert into public.activity_logs(customer_id,action,details,actor_name,actor_user_id)
    values(new.id,'Customer added',new.phone,coalesce(actor,'System'),actor_id);
    return new;
  else
    select p.username into actor from public.nexfit_user_profiles p where p.user_id=actor_id;
    if actor is null then select m.name into actor from public.moderators m where m.id=new.moderator_id; end if;
    if old.status is distinct from new.status or old.notes is distinct from new.notes
       or old.phone is distinct from new.phone or old.moderator_id is distinct from new.moderator_id then
      insert into public.activity_logs(customer_id,action,details,actor_name,actor_user_id)
      values(new.id,'Customer updated',new.phone||' · '||new.status,coalesce(actor,'System'),actor_id);
    end if;
    return new;
  end if;
end;
$$;

revoke all on function public.nexfit_is_admin() from public, anon;
revoke all on function public.nexfit_my_moderator_id() from public, anon;
revoke all on function public.nexfit_bootstrap_admin(text) from public, anon;
revoke all on function public.nexfit_admin_create_moderator(uuid,text,text) from public, anon;
revoke all on function public.nexfit_admin_set_moderator_active(uuid,boolean) from public, anon;
revoke all on function public.nexfit_admin_reset_moderator_password(uuid,text) from public, anon;
grant execute on function public.nexfit_is_admin() to authenticated;
grant execute on function public.nexfit_my_moderator_id() to authenticated;
grant execute on function public.nexfit_bootstrap_admin(text) to authenticated;
grant execute on function public.nexfit_admin_create_moderator(uuid,text,text) to authenticated;
grant execute on function public.nexfit_admin_set_moderator_active(uuid,boolean) to authenticated;
grant execute on function public.nexfit_admin_reset_moderator_password(uuid,text) to authenticated;

grant select on public.nexfit_user_profiles to authenticated;
grant select,insert,update,delete on public.moderators, public.customers to authenticated;
grant select on public.activity_logs to authenticated;

grant usage, select on all sequences in schema public to authenticated;
