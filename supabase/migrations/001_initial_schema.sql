create extension if not exists pgcrypto;
create table if not exists public.moderators(id uuid primary key default gen_random_uuid(),name text not null unique check(char_length(trim(name)) between 2 and 60),active boolean not null default true,created_at timestamptz not null default now());
create or replace function public.normalize_bd_phone(raw text) returns text language plpgsql immutable as $$ declare n text; begin n:=regexp_replace(coalesce(raw,''),'[^0-9]','','g'); if left(n,5)='00880' then n:=substring(n from 3); end if; if left(n,3)='880' then n:='0'||substring(n from 4); end if; if length(n)=10 and left(n,1)='1' then n:='0'||n; end if; if n~'^01[3-9][0-9]{8}$' then return n; end if; return null; end $$;
create table if not exists public.customers(id uuid primary key default gen_random_uuid(),serial_number bigint generated always as identity,phone text not null,normalized_phone text not null,moderator_id uuid references public.moderators(id) on delete set null,status text not null default 'New Customer' check(status in('New Customer','Contacted','Convinced','Order Confirmed','Not Interested','Pending')),notes text not null default '',created_at timestamptz not null default now(),updated_at timestamptz not null default now(),constraint customers_normalized_phone_unique unique(normalized_phone));
create or replace function public.customers_before_write() returns trigger language plpgsql as $$ declare n text; begin n:=public.normalize_bd_phone(coalesce(new.phone,new.normalized_phone)); if n is null then raise exception 'Invalid Bangladesh mobile number' using errcode='22023'; end if; new.phone:=n;new.normalized_phone:=n;if tg_op='UPDATE' then new.updated_at:=now();end if;return new;end $$;
drop trigger if exists customers_normalize_trigger on public.customers;create trigger customers_normalize_trigger before insert or update on public.customers for each row execute function public.customers_before_write();
create table if not exists public.activity_logs(id uuid primary key default gen_random_uuid(),customer_id uuid,action text not null,details text not null default '',actor_name text not null default 'Shared user',created_at timestamptz not null default now());
create or replace function public.log_customer_activity() returns trigger language plpgsql as $$
declare actor text;
begin
  if tg_op = 'DELETE' then
    select name into actor from public.moderators where id = old.moderator_id;
    insert into public.activity_logs(customer_id,action,details,actor_name) values(old.id,'Customer deleted',old.phone,coalesce(actor,'Shared user'));
    return old;
  elsif tg_op = 'INSERT' then
    select name into actor from public.moderators where id = new.moderator_id;
    insert into public.activity_logs(customer_id,action,details,actor_name) values(new.id,'Customer added',new.phone,coalesce(actor,'Shared user'));
    return new;
  else
    select name into actor from public.moderators where id = new.moderator_id;
    if old.status is distinct from new.status or old.notes is distinct from new.notes or old.phone is distinct from new.phone then
      insert into public.activity_logs(customer_id,action,details,actor_name) values(new.id,'Customer updated',new.phone||' · '||new.status,coalesce(actor,'Shared user'));
    end if;
    return new;
  end if;
end $$;
drop trigger if exists customers_activity_trigger on public.customers;create trigger customers_activity_trigger after insert or update or delete on public.customers for each row execute function public.log_customer_activity();
alter table public.moderators enable row level security;alter table public.customers enable row level security;alter table public.activity_logs enable row level security;
drop policy if exists "shared moderators select" on public.moderators;create policy "shared moderators select" on public.moderators for select to anon,authenticated using(true);
drop policy if exists "shared moderators insert" on public.moderators;create policy "shared moderators insert" on public.moderators for insert to anon,authenticated with check(true);
drop policy if exists "shared moderators update" on public.moderators;create policy "shared moderators update" on public.moderators for update to anon,authenticated using(true) with check(true);
drop policy if exists "shared customers select" on public.customers;create policy "shared customers select" on public.customers for select to anon,authenticated using(true);
drop policy if exists "shared customers insert" on public.customers;create policy "shared customers insert" on public.customers for insert to anon,authenticated with check(true);
drop policy if exists "shared customers update" on public.customers;create policy "shared customers update" on public.customers for update to anon,authenticated using(true) with check(true);
drop policy if exists "shared customers delete" on public.customers;create policy "shared customers delete" on public.customers for delete to anon,authenticated using(true);
drop policy if exists "shared activity select" on public.activity_logs;create policy "shared activity select" on public.activity_logs for select to anon,authenticated using(true);
do $$ begin alter publication supabase_realtime add table public.customers; exception when duplicate_object then null;when undefined_object then null;end $$;
do $$ begin alter publication supabase_realtime add table public.moderators; exception when duplicate_object then null;when undefined_object then null;end $$;
do $$ begin alter publication supabase_realtime add table public.activity_logs; exception when duplicate_object then null;when undefined_object then null;end $$;
create index if not exists customers_created_at_idx on public.customers(created_at desc);create index if not exists customers_moderator_idx on public.customers(moderator_id);create index if not exists customers_status_idx on public.customers(status);