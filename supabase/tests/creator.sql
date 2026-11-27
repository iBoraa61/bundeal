-- Creator campaign: 35/15/10/40 on the chain, 35/15/50 without a campaign.

do $$
declare
  admin_id uuid := gen_random_uuid();
  lisa uuid := gen_random_uuid();
  user_a uuid := gen_random_uuid();
  user_b uuid := gen_random_uuid();
  user_c uuid := gen_random_uuid();
  user_d uuid := gen_random_uuid();
  code_lisa text;
  code_a text;
  merchant_id uuid;
  main_deal uuid;
  campaign jsonb;
  campaign_code text;
  click jsonb;
  share_code text;
  row_basic bigint;
  row_referral bigint;
  row_community bigint;
  row_creator bigint;
  row_platform bigint;
  available_lisa bigint;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated', 'creator-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', lisa, 'authenticated', 'authenticated', 'creator-lisa@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_a, 'authenticated', 'authenticated', 'creator-a@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_b, 'authenticated', 'authenticated', 'creator-b@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_c, 'authenticated', 'authenticated', 'creator-c@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_d, 'authenticated', 'authenticated', 'creator-d@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin'), (lisa, 'creator');
  select referral_code into code_lisa from public.profiles where id = lisa;
  select referral_code into code_a from public.profiles where id = user_a;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  merchant_id := public.create_merchant('Creator Haendler', 'creator-haendler', 'https://example.com');
  perform public.set_merchant_capabilities(merchant_id, true, true, true, true, true, false, null);
  main_deal := public.create_published_deal(merchant_id, 'allgemein', 'creator-deal', 'Creator Produkt', 'Ein ausreichend langer Beschreibungstext.', 10000, 'EUR', null);
  perform public.attach_affiliate_link(main_deal, 'webgains', 'creator6', 'simulation', 'https://example.com/track', 'clickref');

  perform set_config('request.jwt.claims', json_build_object('sub', user_a::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_a::text, true);
  execute 'set local role authenticated';
  begin
    perform public.create_creator_campaign('creator-deal');
    raise exception 'normal user created a campaign';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', lisa::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', lisa::text, true);
  execute 'set local role authenticated';
  campaign := public.create_creator_campaign('creator-deal');
  campaign_code := campaign ->> 'public_code';
  if campaign_code !~ '^[a-z0-9]{10}$' then
    raise exception 'campaign code was not created';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_a::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_a::text, true);
  execute 'set local role authenticated';
  click := public.begin_affiliate_click('creator-deal', code_lisa, campaign_code);
  if click ->> 'campaign_attached' <> 'true' or click ->> 'referrer_attached' <> 'true' then
    raise exception 'creator link did not attach campaign and direct referrer';
  end if;
  share_code := public.campaign_code_for_share('creator-deal');
  if share_code is distinct from campaign_code then
    raise exception 'share link lost the campaign';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'creator6', 'external_event_id', 'cr-a',
    'external_transaction_id', 'cr-a', 'click_ref', click ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  select basic_cashback_cents, referral_bonus_cents, unassigned_community_cents,
         creator_share_cents, bundeal_revenue_cents
    into row_basic, row_referral, row_community, row_creator, row_platform
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'cr-a');
  if row_basic <> 350 or row_referral <> 150 or row_community <> 0 or row_creator <> 100 or row_platform <> 400 then
    raise exception 'direct creator purchase was not 3.50 / 1.50 / 1.00 / 4.00';
  end if;
  select available_balance_cents into available_lisa
  from public.cashback_accounts where user_id = lisa and environment = 'simulation';
  if available_lisa <> 250 then
    raise exception 'creator did not receive referral plus campaign share';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_a::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_a::text, true);
  execute 'set local role authenticated';
  perform public.begin_affiliate_click('creator-deal', null, null);
  if public.campaign_code_for_share('creator-deal') is not null then
    raise exception 'a plain click kept the campaign on the next share';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_b::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_b::text, true);
  execute 'set local role authenticated';
  click := public.begin_affiliate_click('creator-deal', code_a, campaign_code);
  if click ->> 'referrer_attached' <> 'true' or click ->> 'campaign_attached' <> 'true' then
    raise exception 'downstream purchase lost the direct referrer or the campaign';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'creator6', 'external_event_id', 'cr-b',
    'external_transaction_id', 'cr-b', 'click_ref', click ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  select basic_cashback_cents, referral_bonus_cents, creator_share_cents, bundeal_revenue_cents
    into row_basic, row_referral, row_creator, row_platform
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'cr-b');
  if row_basic <> 350 or row_referral <> 150 or row_creator <> 100 or row_platform <> 400 then
    raise exception 'downstream campaign purchase did not keep the original creator';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_c::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_c::text, true);
  execute 'set local role authenticated';
  click := public.begin_affiliate_click('creator-deal', null, null);

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'creator6', 'external_event_id', 'cr-plain',
    'external_transaction_id', 'cr-plain', 'click_ref', click ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  select basic_cashback_cents, referral_bonus_cents, unassigned_community_cents,
         creator_share_cents, bundeal_revenue_cents
    into row_basic, row_referral, row_community, row_creator, row_platform
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'cr-plain');
  if row_basic <> 350 or row_referral <> 0 or row_community <> 150 or row_creator <> 0 or row_platform <> 500 then
    raise exception 'a purchase without a campaign did not stay 35/15/50';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', lisa::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', lisa::text, true);
  execute 'set local role authenticated';
  click := public.begin_affiliate_click('creator-deal', code_lisa, campaign_code);
  if click ->> 'campaign_attached' <> 'false' or click ->> 'referrer_attached' <> 'false' then
    raise exception 'creator self-purchase was rewarded';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'creator6', 'external_event_id', 'cr-self',
    'external_transaction_id', 'cr-self', 'click_ref', click ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  select creator_share_cents, unassigned_community_cents, bundeal_revenue_cents
    into row_creator, row_community, row_platform
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'cr-self');
  if row_creator <> 0 or row_community <> 150 or row_platform <> 500 then
    raise exception 'self campaign still paid the creator';
  end if;

  perform public.reverse_commission((select id from public.transactions where external_transaction_id = 'cr-a'), 0, 'rejected');
  if (select coalesce(sum(amount_cents), 0) from public.cashback_ledger where transaction_id = (select id from public.transactions where external_transaction_id = 'cr-a')) <> 0 then
    raise exception 'creator reversal did not clear the ledger';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', lisa::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', lisa::text, true);
  execute 'set local role authenticated';
  perform public.end_creator_campaign(campaign_code);

  perform set_config('request.jwt.claims', json_build_object('sub', user_d::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_d::text, true);
  execute 'set local role authenticated';
  click := public.begin_affiliate_click('creator-deal', code_a, campaign_code);
  if click ->> 'campaign_attached' <> 'false' then
    raise exception 'ended campaign still attached';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_b::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_b::text, true);
  execute 'set local role authenticated';
  if (select count(*) from public.creator_campaigns) <> 0 then
    raise exception 'another user can read the campaign';
  end if;
  begin
    insert into public.creator_campaigns (public_code, creator_user_id, deal_id, ends_at)
    values ('abcdefghij', user_b, main_deal, now() + interval '1 day');
    raise exception 'user inserted a campaign row';
  exception
    when insufficient_privilege then null;
  end;

  execute 'reset role';
  delete from public.cashback_ledger as rows
  where rows.user_id in (admin_id, lisa, user_a, user_b, user_c, user_d);
  delete from public.community_allocations as rows
  where rows.commission_id in (
    select commissions.id from public.commissions
    where commissions.transaction_id in (
      select tx.id from public.transactions as tx where tx.deal_id = main_deal
    )
  );
  delete from public.commissions as rows
  where rows.transaction_id in (select tx.id from public.transactions as tx where tx.deal_id = main_deal);
  delete from public.cashback_accounts as rows
  where rows.user_id in (admin_id, lisa, user_a, user_b, user_c, user_d);
  delete from public.transactions as rows where rows.deal_id = main_deal;
  delete from public.affiliate_events as rows
  where rows.external_event_id in ('cr-a', 'cr-b', 'cr-plain', 'cr-self');
  delete from public.referral_attributions as rows where rows.deal_id = main_deal;
  delete from public.clicks as rows where rows.deal_id = main_deal;
  delete from public.risk_events as rows
  where rows.user_id in (admin_id, lisa, user_a, user_b, user_c, user_d);
  delete from public.deal_rounds as rows where rows.deal_id = main_deal;
  delete from public.affiliate_links as rows where rows.deal_id = main_deal;
  delete from public.creator_campaigns as rows where rows.deal_id = main_deal;
  delete from public.deals where id = main_deal;
  delete from public.merchants where id = merchant_id;
  delete from public.affiliate_accounts where account_reference = 'creator6';
  delete from auth.users where id in (admin_id, lisa, user_a, user_b, user_c, user_d);
end;
$$;
