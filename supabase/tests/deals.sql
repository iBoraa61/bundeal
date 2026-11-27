-- Phase 3: publication is admin-only and public rows contain no affiliate destination.

do $$
declare
  admin_id uuid := gen_random_uuid();
  user_id uuid := gen_random_uuid();
  other_id uuid := gen_random_uuid();
  merchant_id uuid;
  deal_id uuid;
  submission_id uuid;
  seen integer;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated', 'phase3-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_id, 'authenticated', 'authenticated', 'phase3-user@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', other_id, 'authenticated', 'authenticated', 'phase3-other@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  merchant_id := public.create_merchant('Beispielhaendler', 'beispielhaendler', 'https://example.com');
  perform public.set_merchant_capabilities(merchant_id, true, true, true, true, true, false, null);
  deal_id := public.create_published_deal(merchant_id, 'allgemein', 'beispiel-deal', 'Beispielprodukt', 'Ein ausreichend langer Beschreibungstext.', 10000, 'EUR', null);

  execute 'set local role anon';
  select count(*) into seen from public.public_deals where slug = 'beispiel-deal';
  if seen <> 1 then
    raise exception 'anonymous visitor cannot see the published deal';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'public_deals' and column_name = 'affiliate_url'
  ) then
    raise exception 'public deal exposes an affiliate url';
  end if;
  begin
    perform 1 from public.deals;
    raise exception 'anonymous role read the deals table';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', user_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  execute 'set local role authenticated';

  begin
    perform public.create_published_deal(merchant_id, 'allgemein', 'user-deal', 'Unerlaubt', 'Ein ausreichend langer Beschreibungstext.', 100, 'EUR', null);
    raise exception 'user published a deal';
  exception
    when insufficient_privilege then null;
  end;

  insert into public.deal_submissions (proposed_title, proposed_description, proposed_url, proposed_price_cents, currency)
  values ('Neuer Vorschlag', 'Ein ausreichend langer Beschreibungstext.', 'https://example.com/produkt', 2500, 'EUR')
  returning id into submission_id;

  update public.deal_submissions
  set proposed_title = 'Geaenderter Vorschlag'
  where id = submission_id;
  if not found then
    raise exception 'user could not edit an own pending submission';
  end if;

  begin
    update public.deal_submissions set submission_status = 'approved' where id = submission_id;
    raise exception 'user approved a submission';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', other_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', other_id::text, true);
  execute 'set local role authenticated';
  update public.deal_submissions set proposed_title = 'Fremd' where id = submission_id;
  if found then
    raise exception 'user edited another submission';
  end if;
  select count(*) into seen from public.deal_submissions where id = submission_id;
  if seen <> 0 then
    raise exception 'user read another submission';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  perform public.review_deal_submission(submission_id, 'approved', null, merchant_id, 'freigegebener-deal', 2500, 'EUR');
  select count(*) into seen from public.public_deals where slug = 'freigegebener-deal';
  if seen <> 1 then
    raise exception 'approved submission did not publish a deal';
  end if;

  execute 'reset role';
  if not exists (
    select 1 from public.audit_logs where action = 'submission_approved' and target_id = submission_id
  ) then
    raise exception 'approval was not audited';
  end if;
  delete from public.deal_submissions as submissions
  where submissions.submitted_by in (admin_id, user_id, other_id)
     or submissions.deal_id in (select id from public.deals where created_by in (admin_id, user_id, other_id));
  delete from public.deals where created_by in (admin_id, user_id, other_id);
  delete from public.merchants where slug = 'beispielhaendler';
  delete from auth.users where id in (admin_id, user_id, other_id);
end;
$$;
