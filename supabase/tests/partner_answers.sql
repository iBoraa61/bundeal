-- Phase L3: a written answer blocks a public deal until the owner confirms it.
-- Run inside a transaction that rolls back. Does not touch beispielhaendler.

begin;

do $$
declare
  admin_id uuid := gen_random_uuid();
  plain_merchant uuid;
  partner uuid;
  deal uuid;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated',
    'l3-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb, now(), now(), '', '', '', ''
  );
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  plain_merchant := public.create_merchant('L3 Beispiel', 'l3-beispiel', 'https://example.com');
  perform public.set_merchant_capabilities(plain_merchant, true, false, false, false, false, false, null);
  deal := public.create_published_deal(
    plain_merchant, 'allgemein', 'l3-beispiel-deal', 'Ohne Antwort',
    'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'listing', null
  );
  if deal is null then
    raise exception 'demo listing without an answer was blocked';
  end if;

  partner := public.create_merchant('L3 Partner', 'l3-partner', 'https://example.com/partner');
  perform public.set_merchant_capabilities(partner, true, false, true, false, false, false, null);
  perform public.save_advertiser_answer(partner, 'yes', 'no', 'Cashback ja, Empfehlung nein.');

  begin
    perform public.create_published_deal(
      partner, 'allgemein', 'l3-offen', 'Noch offen',
      'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'cashback', null
    );
    raise exception 'unconfirmed partner was published';
  exception
    when others then
      if sqlerrm <> 'partner matrix not confirmed' then
        raise;
      end if;
  end;

  perform public.confirm_advertiser_answer(partner);
  deal := public.create_published_deal(
    partner, 'allgemein', 'l3-cashback', 'Nur Cashback',
    'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'cashback', null
  );
  if deal is null then
    raise exception 'confirmed cashback deal was blocked';
  end if;

  begin
    perform public.create_published_deal(
      partner, 'allgemein', 'l3-referral', 'Empfehlung zu frueh',
      'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'referral', null
    );
    raise exception 'refused referral was published';
  exception
    when others then
      if sqlerrm <> 'referral not approved' then
        raise;
      end if;
  end;

  perform public.save_advertiser_answer(partner, 'yes', 'yes', 'Cashback ja, Empfehlung ja.');
  begin
    perform public.create_published_deal(
      partner, 'allgemein', 'l3-erneut', 'Bestaetigung zurueckgesetzt',
      'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'referral', null
    );
    raise exception 'changed answer stayed confirmed';
  exception
    when others then
      if sqlerrm <> 'partner matrix not confirmed' then
        raise;
      end if;
  end;

  perform public.confirm_advertiser_answer(partner);
  deal := public.create_published_deal(
    partner, 'allgemein', 'l3-referral-ok', 'Empfehlung nach Ja',
    'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'referral', null
  );
  if deal is null then
    raise exception 'confirmed referral deal was blocked';
  end if;

  begin
    perform public.create_published_deal(
      partner, 'allgemein', 'l3-creator', 'Creator nicht freigegeben',
      'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'creator', null
    );
    raise exception 'creator was published without a creator flag';
  exception
    when others then
      if sqlerrm <> 'offer mode not allowed' then
        raise;
      end if;
  end;
end;
$$;

rollback;
