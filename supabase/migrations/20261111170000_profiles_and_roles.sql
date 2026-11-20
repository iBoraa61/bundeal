-- Phase 2 hardens signup. Tables already exist from the foundation migration.
-- User metadata may supply a username and display name, never a role or referral code.

alter table public.profiles
  drop constraint if exists profiles_display_name_length;

alter table public.profiles
  add constraint profiles_display_name_length
  check (display_name is null or char_length(btrim(display_name)) between 1 and 80);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  profile_created boolean := false;
  desired_username text;
  desired_display_name text;
  conflict_name text;
begin
  desired_username := nullif(lower(btrim(coalesce(new.raw_user_meta_data ->> 'username', ''))), '');
  desired_display_name := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), '');

  if desired_username is not null and desired_username !~ '^[a-z0-9_]{3,30}$' then
    raise exception 'invalid username';
  end if;

  if desired_display_name is not null and char_length(desired_display_name) > 80 then
    raise exception 'invalid display name';
  end if;

  while not profile_created loop
    new_code := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into public.profiles (id, username, display_name, referral_code)
      values (new.id, desired_username, desired_display_name, new_code);
      profile_created := true;
    exception
      when unique_violation then
        get stacked diagnostics conflict_name = constraint_name;
        if conflict_name = 'profiles_referral_code_key' then
          profile_created := false;
        else
          raise;
        end if;
    end;
  end loop;

  insert into public.user_roles (user_id, role)
  values (new.id, 'user');

  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
