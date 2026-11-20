-- Phase 2 authentication invariants. The block removes its own auth users.
-- A failure rolls the insert back with the function transaction.

do $$
declare
  user_a uuid := gen_random_uuid();
  user_b uuid := gen_random_uuid();
  user_c uuid := gen_random_uuid();
  seen integer;
  updated integer;
  referral text;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', user_a, 'authenticated', 'authenticated',
    'phase2-a@example.com', '', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    now(), now(), '', '', '', ''
  );

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', user_b, 'authenticated', 'authenticated',
    'phase2-b@example.com', '', now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"username":"beta_user","display_name":"Beta","role":"admin","referral_code":"hijacked01"}'::jsonb,
    now(), now(), '', '', '', ''
  );

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token,
    email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', user_c, 'authenticated', 'authenticated',
    'phase2-c@example.com', '', now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb,
    now(), now(), '', '', '', ''
  );

  insert into public.user_roles (user_id, role) values (user_c, 'admin');

  if not exists (
    select 1 from public.profiles
    where id = user_a and username is null and referral_code ~ '^[a-z0-9]{10}$'
  ) then
    raise exception 'registration did not create a profile';
  end if;

  if not exists (
    select 1 from public.user_roles where user_id = user_a and role = 'user'
  ) then
    raise exception 'registration did not assign the user role';
  end if;

  if exists (
    select 1 from public.user_roles where user_id = user_b and role = 'admin'
  ) then
    raise exception 'signup metadata granted the admin role';
  end if;

  select referral_code into referral from public.profiles where id = user_b;
  if referral = 'hijacked01' or referral is null then
    raise exception 'signup metadata overwrote the referral code';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = user_b and username = 'beta_user' and display_name = 'Beta'
  ) then
    raise exception 'signup metadata did not store the allowed profile fields';
  end if;

  begin
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at, confirmation_token, recovery_token,
      email_change_token_new, email_change
    ) values (
      '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
      'phase2-bad@example.com', '', now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"username":"BAD NAME"}'::jsonb,
      now(), now(), '', '', '', ''
    );
    raise exception 'invalid username was accepted';
  exception
    when others then
      if sqlerrm not like '%invalid username%' then
        raise;
      end if;
  end;

  update public.profiles set username = 'alpha_user' where id = user_a;

  begin
    update public.profiles set username = 'alpha_user' where id = user_b;
    raise exception 'duplicate username was accepted';
  exception
    when unique_violation then
      null;
  end;

  begin
    update public.profiles set referral_code = 'zzzzzzzzzz' where id = user_a;
    raise exception 'referral code change was accepted';
  exception
    when others then
      if sqlerrm not like '%immutable%' then
        raise;
      end if;
  end;

  if exists (
    select 1
    from information_schema.column_privileges
    where grantee in ('anon', 'authenticated')
      and table_schema = 'public'
      and table_name = 'profiles'
      and column_name = 'referral_code'
      and privilege_type = 'UPDATE'
  ) then
    raise exception 'browser roles can update referral_code';
  end if;

  if exists (
    select 1
    from information_schema.role_table_grants
    where grantee in ('anon', 'authenticated')
      and table_schema = 'public'
      and table_name = 'user_roles'
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE')
  ) then
    raise exception 'browser roles can write user_roles';
  end if;

  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_a::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('request.jwt.claim.sub', user_a::text, true);
  execute 'set local role authenticated';

  select count(*) into seen from public.profiles where id = user_a;
  if seen <> 1 then
    raise exception 'user cannot read the own profile';
  end if;

  select count(*) into seen from public.profiles where id = user_b;
  if seen <> 0 then
    raise exception 'user can read another private profile';
  end if;

  update public.profiles set display_name = 'Ada' where id = user_a;
  get diagnostics updated = row_count;
  if updated <> 1 then
    raise exception 'user could not update the own profile';
  end if;

  update public.profiles set display_name = 'Nein' where id = user_b;
  get diagnostics updated = row_count;
  if updated <> 0 then
    raise exception 'user updated another profile';
  end if;

  begin
    update public.profiles set referral_code = 'yyyyyyyyyy' where id = user_a;
    raise exception 'user updated the referral code';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    insert into public.user_roles (user_id, role) values (user_a, 'admin');
    raise exception 'user inserted an admin role';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    update public.user_roles set role = 'admin' where user_id = user_a;
    raise exception 'user changed a role';
  exception
    when insufficient_privilege then
      null;
  end;

  begin
    delete from public.profiles where id = user_a;
    raise exception 'user deleted a profile';
  exception
    when insufficient_privilege then
      null;
  end;

  execute 'set local role anon';

  begin
    select count(*) into seen from public.profiles;
    raise exception 'anonymous role read profiles';
  exception
    when insufficient_privilege then
      null;
  end;

  execute 'reset role';

  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_c::text, 'role', 'authenticated')::text,
    true
  );
  perform set_config('request.jwt.claim.sub', user_c::text, true);
  execute 'set local role authenticated';

  select count(*) into seen from public.profiles where id in (user_a, user_b);
  if seen <> 2 then
    raise exception 'admin cannot read profiles for support';
  end if;

  execute 'reset role';
  delete from auth.users where id in (user_a, user_b, user_c);
end;
$$;
