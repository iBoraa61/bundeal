-- Development foundation only. No cashback, affiliate secrets, or live processing.

create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text,
  display_name text,
  referral_code text not null,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (
    username is null or username ~ '^[a-z0-9_]{3,30}$'
  ),
  constraint profiles_referral_code_format check (
    referral_code ~ '^[a-z0-9]{10}$'
  )
);

create unique index profiles_username_key
  on public.profiles (username)
  where username is not null;

create unique index profiles_referral_code_key
  on public.profiles (referral_code);

create table public.user_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('user', 'admin')),
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

create table public.merchants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  website_url text not null,
  status text not null default 'inactive' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint merchants_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

create table public.deal_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  created_at timestamptz not null default now(),
  constraint deal_categories_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$')
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references auth.users (id) on delete set null,
  actor_type text not null check (actor_type in ('user', 'admin', 'system')),
  action text not null,
  target_table text,
  target_id uuid,
  environment text check (environment in ('simulation', 'live')),
  metadata jsonb,
  created_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger merchants_set_updated_at
before update on public.merchants
for each row execute function public.set_updated_at();

create or replace function public.protect_profile_identity()
returns trigger
language plpgsql
as $$
begin
  if new.id is distinct from old.id
     or new.referral_code is distinct from old.referral_code
     or new.created_at is distinct from old.created_at then
    raise exception 'profile identity fields are immutable';
  end if;
  return new;
end;
$$;

create trigger profiles_protect_identity
before update on public.profiles
for each row execute function public.protect_profile_identity();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  profile_created boolean := false;
begin
  while not profile_created loop
    new_code := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into public.profiles (id, referral_code)
      values (new.id, new_code);
      profile_created := true;
    exception
      when unique_violation then
        profile_created := false;
    end;
  end loop;

  insert into public.user_roles (user_id, role)
  values (new.id, 'user');

  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.protect_profile_identity() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;

revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.user_roles from public, anon, authenticated;
revoke all on table public.merchants from public, anon, authenticated;
revoke all on table public.deal_categories from public, anon, authenticated;
revoke all on table public.audit_logs from public, anon, authenticated;

grant select (
  id, username, display_name, referral_code, avatar_url, created_at, updated_at
) on table public.profiles to authenticated;

grant update (
  username, display_name, avatar_url
) on table public.profiles to authenticated;

grant select on table public.deal_categories to anon, authenticated;
