-- Row Level Security for the Phase 1 foundation.
-- The service role bypasses RLS and remains server-side only.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_roles
    where user_id = auth.uid()
      and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

alter table public.profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.merchants enable row level security;
alter table public.deal_categories enable row level security;
alter table public.audit_logs enable row level security;

create policy profiles_select_own_or_admin
on public.profiles
for select
to authenticated
using (id = auth.uid() or public.is_admin());

create policy profiles_update_own
on public.profiles
for update
to authenticated
using (id = auth.uid())
with check (id = auth.uid());

create policy user_roles_select_own_or_admin
on public.user_roles
for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy merchants_admin_all
on public.merchants
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy deal_categories_public_select
on public.deal_categories
for select
to anon, authenticated
using (true);

create policy deal_categories_admin_write
on public.deal_categories
for insert
to authenticated
with check (public.is_admin());

create policy deal_categories_admin_update
on public.deal_categories
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create policy deal_categories_admin_delete
on public.deal_categories
for delete
to authenticated
using (public.is_admin());

create policy audit_logs_admin_select
on public.audit_logs
for select
to authenticated
using (public.is_admin());
