-- Phase L1: merchant flags gate offer modes. Listing stores no referral.

do $$
declare
  admin_id uuid := gen_random_uuid();
  buyer uuid := gen_random_uuid();
  referrer uuid := gen_random_uuid();
  merchant uuid;
  listing_deal uuid;
  before_count integer;
  after_count integer;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated', 'l1-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', buyer, 'authenticated', 'authenticated', 'l1-buyer@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', referrer, 'authenticated', 'authenticated', 'l1-referrer@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  merchant := public.create_merchant('L1 Haendler', 'l1-haendler', 'https://example.com');

  begin
    perform public.create_published_deal(merchant, 'allgemein', 'l1-closed', 'Geschlossen', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'referral');
    raise exception 'closed merchant published a referral deal';
  exception
    when insufficient_privilege then null;
  end;

  perform public.set_merchant_capabilities(merchant, true, false, true, false, false, false, 'nur cashback');
  begin
    perform public.create_published_deal(merchant, 'allgemein', 'l1-no-ref', 'Ohne Empfehlung', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'referral');
    raise exception 'cashback-only merchant published a referral deal';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform public.create_published_deal(merchant, 'allgemein', 'l1-no-creator', 'Ohne Creator', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'creator');
    raise exception 'cashback-only merchant published a creator deal';
  exception
    when insufficient_privilege then null;
  end;

  perform public.create_published_deal(merchant, 'allgemein', 'l1-cash', 'Nur Cashback', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'cashback');
  perform public.set_merchant_capabilities(merchant, true, false, true, false, false, false, 'listing dazu');
  listing_deal := public.create_published_deal(merchant, 'allgemein', 'l1-listing', 'Normaler Deal', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'listing');

  execute 'reset role';
  select count(*) into before_count from public.referral_attributions;
  insert into public.referral_attributions (deal_id, referrer_user_id, buyer_user_id, status, rule_version, environment)
  values (listing_deal, referrer, buyer, 'active', 'direct-v1', 'simulation');
  select count(*) into after_count from public.referral_attributions;
  if after_count <> before_count then
    raise exception 'listing deal stored a referral attribution';
  end if;

  begin
    insert into public.creator_campaigns (public_code, creator_user_id, deal_id, ends_at)
    values ('l1testcode', admin_id, listing_deal, now() + interval '1 day');
    raise exception 'listing deal accepted a creator campaign';
  exception
    when insufficient_privilege then null;
  end;

  if exists (select 1 from public.deals where slug = 'kopfhoerer')
     and (select offer_mode from public.deals where slug = 'kopfhoerer') is distinct from 'referral' then
    raise exception 'existing demo deal changed mode';
  end if;

  delete from public.deals where created_by = admin_id;
  delete from public.merchants where id = merchant;
  delete from auth.users where id in (admin_id, buyer, referrer);
end;
$$;
