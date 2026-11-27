-- Dashboard snapshot and creator applications stay on the caller's own rows.

do $$
declare
  admin_id uuid := gen_random_uuid();
  buyer uuid := gen_random_uuid();
  other_user uuid := gen_random_uuid();
  merchant_id uuid;
  main_deal uuid;
  round_id uuid;
  account_id uuid;
  purchase_id uuid;
  application_id uuid;
  snapshot jsonb;
  purchase jsonb;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated', 'dash7-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', buyer, 'authenticated', 'authenticated', 'dash7-buyer@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', other_user, 'authenticated', 'authenticated', 'dash7-other@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  perform set_config('request.jwt.claims', json_build_object('sub', buyer::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', buyer::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.request_creator_role('youtube kochkanal');
  begin
    perform public.create_creator_campaign('kopfhoerer');
    raise exception 'pending applicant created a campaign';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform public.review_creator_application(
      (select id from public.creator_applications where user_id = buyer and status = 'pending'),
      true
    );
    raise exception 'applicant reviewed their own application';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  select id into application_id
  from public.creator_applications
  where user_id = buyer and status = 'pending';
  perform public.review_creator_application(application_id, false);
  if exists (select 1 from public.user_roles where user_id = buyer and role = 'creator') then
    raise exception 'rejected application granted the creator role';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', buyer::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', buyer::text, true);
  execute 'set local role authenticated';
  perform public.request_creator_role('youtube kochkanal');

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  merchant_id := public.create_merchant('Dash Haendler', 'dash7-haendler', 'https://example.com');
  perform public.set_merchant_capabilities(merchant_id, true, true, true, true, true, false, null);
  main_deal := public.create_published_deal(merchant_id, 'allgemein', 'dash7-deal', 'Dash Produkt', 'Ein ausreichend langer Beschreibungstext.', 10000, 'EUR', null);
  perform public.attach_affiliate_link(main_deal, 'webgains', 'dash7', 'simulation', 'https://example.com/track', 'clickref');
  select id into application_id
  from public.creator_applications
  where user_id = buyer and status = 'pending';
  perform public.review_creator_application(application_id, true);
  if not exists (select 1 from public.user_roles where user_id = buyer and role = 'creator') then
    raise exception 'approved application did not grant the creator role';
  end if;

  execute 'reset role';
  round_id := public.ensure_open_round(main_deal, 'simulation', now());
  select affiliate_account_id into account_id
  from public.affiliate_links
  where deal_id = main_deal and active;
  insert into public.transactions (
    affiliate_account_id, external_transaction_id, user_id, deal_id, deal_round_id,
    affiliate_network, order_amount_cents, commission_amount_cents, currency,
    transaction_status, environment, transaction_date
  ) values (
    account_id, 'dash7-open', buyer, main_deal, round_id,
    'webgains', 10000, 0, 'EUR',
    'pending', 'simulation', now()
  ) returning id into purchase_id;

  perform set_config('request.jwt.claims', json_build_object('sub', buyer::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', buyer::text, true);
  execute 'set local role authenticated';
  snapshot := public.cashback_account_snapshot();
  select entry into purchase
  from jsonb_array_elements(snapshot -> 'history') as entry
  where entry ->> 'kind' = 'purchase';
  if purchase ->> 'cashback_status' is distinct from 'open' or purchase ->> 'amount_cents' is not null then
    raise exception 'open purchase was shown as cashback';
  end if;

  execute 'reset role';
  insert into public.cashback_accounts (user_id, environment, currency, pending_balance_cents, available_balance_cents)
  values (buyer, 'simulation', 'EUR', 350, 0), (other_user, 'simulation', 'EUR', 100, 0);
  insert into public.cashback_ledger (
    user_id, transaction_id, bucket, entry_type, amount_cents, currency, status, environment, idempotency_key, description
  ) values (
    buyer, purchase_id, 'basic_cashback', 'credit', 350, 'EUR', 'pending', 'simulation', 'dash7-credit', 'test credit'
  );

  perform set_config('request.jwt.claims', json_build_object('sub', buyer::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', buyer::text, true);
  execute 'set local role authenticated';
  snapshot := public.cashback_account_snapshot();
  if (snapshot -> 'balances' -> 0 ->> 'pending_cents')::bigint is distinct from 350 then
    raise exception 'buyer pending balance was not 350';
  end if;
  select entry into purchase
  from jsonb_array_elements(snapshot -> 'history') as entry
  where entry ->> 'kind' = 'purchase';
  if purchase ->> 'cashback_status' is distinct from 'pending' or (purchase ->> 'amount_cents')::bigint is distinct from 350 then
    raise exception 'confirmed cashback was not pending';
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', other_user::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', other_user::text, true);
  execute 'set local role authenticated';
  snapshot := public.cashback_account_snapshot();
  if (snapshot -> 'balances' -> 0 ->> 'pending_cents')::bigint is distinct from 100 then
    raise exception 'other user did not see only their own balance';
  end if;
  if exists (
    select 1 from jsonb_array_elements(snapshot -> 'history') as entry
    where entry ->> 'deal_title' = 'Dash Produkt'
  ) then
    raise exception 'other user saw the buyer purchase';
  end if;
  if (select count(*) from public.cashback_accounts where user_id = buyer) <> 0 then
    raise exception 'buyer account was readable through the table';
  end if;

  execute 'reset role';
  insert into public.cashback_ledger (
    user_id, transaction_id, bucket, entry_type, amount_cents, currency, status, environment, idempotency_key, description
  ) values (
    buyer, purchase_id, 'basic_cashback', 'reversal', -350, 'EUR', 'pending', 'simulation', 'dash7-reverse', 'test reversal'
  );
  update public.cashback_accounts
  set pending_balance_cents = 0
  where user_id = buyer and environment = 'simulation';

  perform set_config('request.jwt.claims', json_build_object('sub', buyer::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', buyer::text, true);
  execute 'set local role authenticated';
  snapshot := public.cashback_account_snapshot();
  select entry into purchase
  from jsonb_array_elements(snapshot -> 'history') as entry
  where entry ->> 'kind' = 'purchase';
  if purchase ->> 'cashback_status' is distinct from 'reversed' or (purchase ->> 'amount_cents')::bigint is distinct from 350 then
    raise exception 'reversal disappeared from the history';
  end if;
  if (snapshot -> 'balances' -> 0 ->> 'pending_cents')::bigint is distinct from 0 then
    raise exception 'reversed balance was not zero';
  end if;

  execute 'reset role';
  delete from public.cashback_ledger where idempotency_key in ('dash7-credit', 'dash7-reverse');
  delete from public.cashback_accounts where user_id in (buyer, other_user);
  delete from public.transactions where id = purchase_id;
  delete from public.deal_rounds where id = round_id;
  delete from public.affiliate_links where deal_id = main_deal;
  delete from public.affiliate_accounts where account_reference = 'dash7';
  delete from public.deals where id = main_deal;
  delete from public.merchants where id = merchant_id;
  delete from public.creator_applications where user_id in (buyer, other_user, admin_id);
  delete from public.audit_logs where actor_user_id in (buyer, other_user, admin_id);
  delete from public.user_roles where user_id in (buyer, other_user, admin_id);
  delete from public.profiles where id in (buyer, other_user, admin_id);
  delete from auth.users where id in (buyer, other_user, admin_id);
end;
$$;
