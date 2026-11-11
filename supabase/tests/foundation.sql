-- Run with a privileged database connection after migrations and seed.
-- The script fails if a foundation security invariant is missing.

do $$
declare
  unprotected_table text;
  role_insert_policy_count integer;
begin
  select c.relname
  into unprotected_table
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relname in ('profiles', 'user_roles', 'merchants', 'deal_categories', 'audit_logs')
    and c.relrowsecurity = false
  limit 1;

  if unprotected_table is not null then
    raise exception 'RLS is disabled for public.%', unprotected_table;
  end if;

  select count(*)
  into role_insert_policy_count
  from pg_policies
  where schemaname = 'public'
    and tablename = 'user_roles'
    and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL');

  if role_insert_policy_count <> 0 then
    raise exception 'client roles must not be able to change user_roles';
  end if;

  if not exists (
    select 1
    from public.deal_categories
    where slug = 'allgemein'
  ) then
    raise exception 'development seed category is missing';
  end if;
end;
$$;
