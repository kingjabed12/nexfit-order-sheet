-- NEXFIT: shared customer visibility, admin-only deletion, customer names and commission ledger
begin;

alter table public.customers add column if not exists customer_name text not null default '';
alter table public.moderators add column if not exists balance numeric(12,2) not null default 0;
update public.moderators set balance=0 where balance is null;
alter table public.moderators alter column balance set default 0;
alter table public.moderators alter column balance set not null;

create table if not exists public.moderator_balance_transactions(
 id uuid primary key default gen_random_uuid(),
 moderator_id uuid not null references public.moderators(id) on delete restrict,
 customer_id uuid null,
 amount numeric(12,2) not null,
 kind text not null check(kind in ('commission','reversal','admin_adjustment')),
 note text not null default '',
 source_event_id text not null unique,
 created_by uuid null,
 created_at timestamptz not null default now()
);
create index if not exists moderator_balance_transactions_mod_idx
 on public.moderator_balance_transactions(moderator_id,created_at desc);

create or replace function public.nexfit_is_active_user()
returns boolean language sql stable security definer
set search_path=public set row_security=off as $$
 select exists(select 1 from public.nexfit_user_profiles p
   where p.user_id=auth.uid() and p.active=true)
$$;
create or replace function public.nexfit_is_admin()
returns boolean language sql stable security definer
set search_path=public set row_security=off as $$
 select exists(select 1 from public.nexfit_user_profiles p
   where p.user_id=auth.uid() and p.role='admin' and p.active=true)
$$;

do $$
declare p record;
begin
 for p in select policyname from pg_policies where schemaname='public' and tablename='customers'
 loop execute format('drop policy if exists %I on public.customers',p.policyname); end loop;
 for p in select policyname from pg_policies where schemaname='public' and tablename='moderators'
 loop execute format('drop policy if exists %I on public.moderators',p.policyname); end loop;
 for p in select policyname from pg_policies where schemaname='public' and tablename='activity_logs'
 loop execute format('drop policy if exists %I on public.activity_logs',p.policyname); end loop;
 for p in select policyname from pg_policies where schemaname='public' and tablename='moderator_balance_transactions'
 loop execute format('drop policy if exists %I on public.moderator_balance_transactions',p.policyname); end loop;
end $$;

alter table public.customers enable row level security;
alter table public.moderators enable row level security;
alter table public.activity_logs enable row level security;
alter table public.moderator_balance_transactions enable row level security;

create policy "active users view all customers" on public.customers
 for select to authenticated using(public.nexfit_is_active_user());
create policy "active users add customers" on public.customers
 for insert to authenticated with check(public.nexfit_is_active_user());
create policy "active users update customers" on public.customers
 for update to authenticated using(public.nexfit_is_active_user()) with check(public.nexfit_is_active_user());
create policy "only admins delete customers" on public.customers
 for delete to authenticated using(public.nexfit_is_admin());
create policy "active users view moderators" on public.moderators
 for select to authenticated using(public.nexfit_is_active_user());
create policy "active users view activity" on public.activity_logs
 for select to authenticated using(public.nexfit_is_active_user());
create policy "active users view balance ledger" on public.moderator_balance_transactions
 for select to authenticated using(public.nexfit_is_active_user());

create or replace function public.nexfit_apply_balance_transaction()
returns trigger language plpgsql security definer
set search_path=public set row_security=off as $$
begin
 update public.moderators set balance=coalesce(balance,0)+new.amount where id=new.moderator_id;
 return new;
end $$;
drop trigger if exists nexfit_balance_transaction_apply on public.moderator_balance_transactions;
create trigger nexfit_balance_transaction_apply after insert on public.moderator_balance_transactions
 for each row execute function public.nexfit_apply_balance_transaction();

create or replace function public.nexfit_customer_commission_trigger()
returns trigger language plpgsql security definer
set search_path=public set row_security=off as $$
declare v_tx uuid; v_time text;
begin
 if tg_op='INSERT' then
   if new.status='Confirm' and new.moderator_id is not null then
     v_time:=coalesce(new.updated_at,new.created_at,now())::text;
     insert into public.moderator_balance_transactions(moderator_id,customer_id,amount,kind,note,source_event_id)
     values(new.moderator_id,new.id,20,'commission','Confirmed customer commission','confirm:'||new.id::text||':'||v_time)
     on conflict(source_event_id) do nothing returning id into v_tx;
   end if;
   return new;
 elsif tg_op='UPDATE' then
   if old.status='Confirm' and (new.status<>'Confirm' or old.moderator_id is distinct from new.moderator_id) and old.moderator_id is not null then
     v_time:=coalesce(new.updated_at,now())::text;
     insert into public.moderator_balance_transactions(moderator_id,customer_id,amount,kind,note,source_event_id)
     values(old.moderator_id,old.id,-20,'reversal','Confirmation removed or reassigned','unconfirm:'||old.id::text||':'||v_time)
     on conflict(source_event_id) do nothing returning id into v_tx;
   end if;
   if new.status='Confirm' and (old.status<>'Confirm' or old.moderator_id is distinct from new.moderator_id) and new.moderator_id is not null then
     v_time:=coalesce(new.updated_at,now())::text;
     insert into public.moderator_balance_transactions(moderator_id,customer_id,amount,kind,note,source_event_id)
     values(new.moderator_id,new.id,20,'commission','Confirmed customer commission','confirm:'||new.id::text||':'||v_time)
     on conflict(source_event_id) do nothing returning id into v_tx;
   end if;
   return new;
 else
   if old.status='Confirm' and old.moderator_id is not null then
     insert into public.moderator_balance_transactions(moderator_id,customer_id,amount,kind,note,source_event_id)
     values(old.moderator_id,old.id,-20,'reversal','Confirmed customer deleted','delete:'||old.id::text)
     on conflict(source_event_id) do nothing returning id into v_tx;
   end if;
   return old;
 end if;
end $$;
drop trigger if exists nexfit_customer_commission on public.customers;
create trigger nexfit_customer_commission after insert or update or delete on public.customers
 for each row execute function public.nexfit_customer_commission_trigger();

-- Credit existing Confirm records once when this migration is first applied.
insert into public.moderator_balance_transactions(moderator_id,customer_id,amount,kind,note,source_event_id)
select moderator_id,id,20,'commission','Opening balance for existing confirmed customer','backfill-confirm:'||id::text
from public.customers
where status='Confirm' and moderator_id is not null
on conflict(source_event_id) do nothing;

create or replace function public.nexfit_admin_set_moderator_balance(p_moderator_id uuid,p_new_balance numeric,p_note text default 'Admin balance adjustment')
returns numeric language plpgsql security definer
set search_path=public set row_security=off as $$
declare v_current numeric(12,2); v_delta numeric(12,2);
begin
 if not public.nexfit_is_admin() then raise exception 'Only Admin can edit moderator balance' using errcode='42501'; end if;
 if p_new_balance is null or p_new_balance<0 then raise exception 'Balance must be zero or greater'; end if;
 select balance into v_current from public.moderators where id=p_moderator_id for update;
 if not found then raise exception 'Moderator not found'; end if;
 v_delta:=round(p_new_balance-v_current,2);
 if v_delta<>0 then
   insert into public.moderator_balance_transactions(moderator_id,amount,kind,note,source_event_id,created_by)
   values(p_moderator_id,v_delta,'admin_adjustment',coalesce(nullif(trim(p_note),''),'Admin balance adjustment'),'admin:'||gen_random_uuid()::text,auth.uid());
 end if;
 return p_new_balance;
end $$;

revoke all on function public.nexfit_admin_set_moderator_balance(uuid,numeric,text) from public,anon;
grant execute on function public.nexfit_admin_set_moderator_balance(uuid,numeric,text) to authenticated;
revoke all on function public.nexfit_is_active_user() from public,anon;
revoke all on function public.nexfit_is_admin() from public,anon;
grant execute on function public.nexfit_is_active_user() to authenticated;
grant execute on function public.nexfit_is_admin() to authenticated;
revoke all on public.customers,public.moderators,public.activity_logs,public.moderator_balance_transactions from anon;
grant select,insert,update,delete on public.customers to authenticated;
grant select on public.moderators,public.activity_logs,public.moderator_balance_transactions to authenticated;
commit;
