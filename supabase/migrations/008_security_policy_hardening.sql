-- NEXFIT security hardening after shared-customer/balance migration.
-- Moderators may see all customers, but can only create/update their own.
-- Only Admin may manage moderator records or delete customers.
-- Activity history remains Admin-or-own-actor only.

begin;

-- Restore the intended moderator-management policies that were replaced by
-- the initial shared-visibility migration.
drop policy if exists "active users view moderators" on public.moderators;
drop policy if exists "nexfit moderators read" on public.moderators;
drop policy if exists "nexfit moderators admin insert" on public.moderators;
drop policy if exists "nexfit moderators admin update" on public.moderators;
drop policy if exists "nexfit moderators admin delete" on public.moderators;

create policy "active users view moderators"
on public.moderators for select to authenticated
using (public.nexfit_is_active_user());

create policy "nexfit moderators admin insert"
on public.moderators for insert to authenticated
with check (public.nexfit_is_admin());

create policy "nexfit moderators admin update"
on public.moderators for update to authenticated
using (public.nexfit_is_admin())
with check (public.nexfit_is_admin());

create policy "nexfit moderators admin delete"
on public.moderators for delete to authenticated
using (public.nexfit_is_admin());

-- Keep global customer visibility, while enforcing ownership for writes.
drop policy if exists "active users add customers" on public.customers;
drop policy if exists "active users update customers" on public.customers;

create policy "active users add own customers"
on public.customers for insert to authenticated
with check (
  public.nexfit_is_admin()
  or (
    public.nexfit_is_active_user()
    and moderator_id = public.nexfit_my_moderator_id()
  )
);

create policy "active users update own customers"
on public.customers for update to authenticated
using (
  public.nexfit_is_admin()
  or (
    public.nexfit_is_active_user()
    and moderator_id = public.nexfit_my_moderator_id()
  )
)
with check (
  public.nexfit_is_admin()
  or (
    public.nexfit_is_active_user()
    and moderator_id = public.nexfit_my_moderator_id()
  )
);

-- Activity logs are private to Admin and the user who performed the action.
drop policy if exists "active users view activity" on public.activity_logs;
drop policy if exists "nexfit activity read" on public.activity_logs;

create policy "nexfit activity read"
on public.activity_logs for select to authenticated
using (public.nexfit_is_admin() or actor_user_id = auth.uid());

-- Explicitly restore the Admin-only moderator management grants.
revoke all on public.moderators from anon;
grant select, insert, update, delete on public.moderators to authenticated;

-- No browser role may directly write ledger entries or adjust balances.
revoke insert, update, delete on public.moderator_balance_transactions from anon, authenticated;
grant select on public.moderator_balance_transactions to authenticated;

commit;
