-- Phase L2: previous shop price is public; a lower previous price and a non-https image are rejected.
-- Run inside a transaction that rolls back. Does not touch beispielhaendler.

begin;

do $$
declare
  admin_id uuid := gen_random_uuid();
  merchant uuid;
  deal uuid;
  seen_original bigint;
  seen_category text;
  seen_merchant text;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated',
    'l2-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb, now(), now(), '', '', '', ''
  );
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  merchant := public.create_merchant('L2 Haendler', 'l2-haendler', 'https://example.com');
  perform public.set_merchant_capabilities(merchant, true, false, false, false, false, false, null);

  begin
    perform public.create_published_deal(merchant, 'allgemein', 'l2-low', 'Zu niedrig', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'listing', 500);
    raise exception 'lower original price was stored';
  exception
    when others then
      if sqlerrm <> 'invalid original price' then
        raise;
      end if;
  end;

  begin
    perform public.create_published_deal(merchant, 'allgemein', 'l2-http', 'Unsicheres Bild', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', 'http://example.com/a.png', 'listing', null);
    raise exception 'http image was stored';
  exception
    when others then
      if sqlerrm <> 'invalid image url' then
        raise;
      end if;
  end;

  deal := public.create_published_deal(merchant, 'allgemein', 'l2-price', 'Mit Vorpreis', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', 'https://example.com/bild.png', 'listing', 2500);
  execute 'reset role';

  select original_price_cents, category_slug, merchant_slug
    into seen_original, seen_category, seen_merchant
  from public.public_deals
  where slug = 'l2-price';

  if seen_original is distinct from 2500 or seen_category is distinct from 'allgemein' or seen_merchant is distinct from 'l2-haendler' then
    raise exception 'public deal did not expose the shop price fields';
  end if;
  if deal is null then
    raise exception 'listing deal was not created';
  end if;
end;
$$;

rollback;
