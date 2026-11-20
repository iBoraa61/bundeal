-- Phase 4: account referrals stay direct and cannot be self-assigned in the table.

do $$
declare
  user_a uuid := gen_random_uuid();
  user_b uuid := gen_random_uuid();
  user_c uuid := gen_random_uuid();
  code_a text;
  code_b text;
  referral_id uuid;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', user_a, 'authenticated', 'authenticated', 'phase4-a@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_b, 'authenticated', 'authenticated', 'phase4-b@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_c, 'authenticated', 'authenticated', 'phase4-c@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');

  select referral_code into code_a from public.profiles where id = user_a;
  select referral_code into code_b from public.profiles where id = user_b;
  if not exists (select 1 from public.attribution_rules where version = 'direct-v1' and active) then
    raise exception 'direct-v1 rule is missing';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_b::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_b::text, true);
  execute 'set local role authenticated';
  referral_id := public.record_account_referral(code_a);
  if referral_id is null then
    raise exception 'direct account referral was not recorded';
  end if;
  begin
    perform public.record_account_referral(code_a);
    raise exception 'second account referrer was accepted';
  exception
    when others then
      if sqlerrm not like '%already recorded%' then
        raise;
      end if;
  end;
  begin
    insert into public.referrals (referrer_user_id, referred_user_id, referral_code)
    values (user_a, user_b, code_a);
    raise exception 'user inserted a referral row';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', user_a::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_a::text, true);
  execute 'set local role authenticated';
  begin
    perform public.record_account_referral(code_a);
    raise exception 'self referral was accepted';
  exception
    when others then
      if sqlerrm not like '%not usable%' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', user_c::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_c::text, true);
  execute 'set local role authenticated';
  perform public.record_account_referral(code_b);
  if exists (
    select 1 from public.referrals
    where referred_user_id = user_c and referrer_user_id = user_a
  ) then
    raise exception 'second-level account referral was created';
  end if;

  execute 'reset role';
  delete from auth.users where id in (user_a, user_b, user_c);
end;
$$;
