-- Phase 5: clickref is server-built, self and second-level referrals do not pay upstream,
-- and live imports are refused to browser admins.

do $$
declare
  admin_id uuid := gen_random_uuid();
  user_r uuid := gen_random_uuid();
  user_b uuid := gen_random_uuid();
  user_c uuid := gen_random_uuid();
  code_r text;
  code_b text;
  merchant_id uuid;
  deal_id uuid;
  click_r jsonb;
  click_b jsonb;
  click_c jsonb;
  click_self jsonb;
  imported jsonb;
  seen integer;
  stored_url text := 'https://example.com/track';
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated', 'phase5-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_r, 'authenticated', 'authenticated', 'phase5-r@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_b, 'authenticated', 'authenticated', 'phase5-b@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_c, 'authenticated', 'authenticated', 'phase5-c@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');
  select referral_code into code_r from public.profiles where id = user_r;
  select referral_code into code_b from public.profiles where id = user_b;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  merchant_id := public.create_merchant('Beispielhaendler', 'tracking-haendler', 'https://example.com');
  perform public.set_merchant_capabilities(merchant_id, true, true, true, true, true, false, null);
  deal_id := public.create_published_deal(merchant_id, 'allgemein', 'tracking-deal', 'Tracking Produkt', 'Ein ausreichend langer Beschreibungstext.', 10000, 'EUR', null);
  perform public.attach_affiliate_link(deal_id, 'webgains', 'dev', 'simulation', stored_url, 'clickref');

  perform set_config('request.jwt.claims', json_build_object('sub', user_r::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_r::text, true);
  execute 'set local role authenticated';
  click_r := public.begin_affiliate_click('tracking-deal', null);
  if click_r ->> 'outbound_url' not like stored_url || '%clickref=' || (click_r ->> 'click_ref') then
    raise exception 'click did not stay on the stored affiliate url';
  end if;
  if click_r ->> 'referrer_attached' <> 'false' then
    raise exception 'first click attached a referrer';
  end if;
  select count(*) into seen from public.affiliate_links;
  if seen <> 0 then
    raise exception 'buyer can read affiliate links';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  imported := public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'dev', 'external_event_id', 'evt-r',
    'external_transaction_id', 'tx-r', 'click_ref', click_r ->> 'click_ref',
    'transaction_status', 'pending', 'currency', 'EUR', 'occurred_at', now(),
    'order_amount_cents', 10000, 'commission_amount_cents', 1000
  )), 'simulation');
  if imported -> 0 ->> 'status' <> 'processed' then
    raise exception 'referrer transaction was not imported';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_b::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_b::text, true);
  execute 'set local role authenticated';
  click_b := public.begin_affiliate_click('tracking-deal', code_r);
  if click_b ->> 'referrer_attached' <> 'true' then
    raise exception 'direct referrer was not attached';
  end if;
  if position(code_r in (click_b ->> 'click_ref')) = 0 then
    raise exception 'clickref omitted the pseudonymous referrer';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_r::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_r::text, true);
  execute 'set local role authenticated';
  click_self := public.begin_affiliate_click('tracking-deal', code_r);
  if click_self ->> 'click_ref' like '%f' || code_r then
    raise exception 'self referral remained in the clickref';
  end if;
  if exists (
    select 1 from public.clicks
    where click_ref = click_self ->> 'click_ref' and referrer_user_id is not null
  ) then
    raise exception 'self referral was stored on the click';
  end if;
  execute 'reset role';
  if not exists (select 1 from public.risk_events where user_id = user_r and risk_type = 'self_referral') then
    raise exception 'self referral was not recorded';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'dev', 'external_event_id', 'evt-b',
    'external_transaction_id', 'tx-b', 'click_ref', click_b ->> 'click_ref',
    'transaction_status', 'pending', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  imported := public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'dev', 'external_event_id', 'evt-b',
    'external_transaction_id', 'tx-b', 'click_ref', click_b ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  if imported -> 0 ->> 'status' <> 'duplicate' then
    raise exception 'replayed event was imported again';
  end if;
  select count(*) into seen from public.transactions where external_transaction_id = 'tx-b';
  if seen <> 1 then
    raise exception 'transaction was duplicated';
  end if;
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'dev', 'external_event_id', 'evt-b-2',
    'external_transaction_id', 'tx-b', 'click_ref', click_b ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  if not exists (
    select 1 from public.transactions
    where external_transaction_id = 'tx-b' and transaction_status = 'confirmed'
  ) then
    raise exception 'transaction status was not updated';
  end if;
  imported := public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'dev', 'external_event_id', 'evt-unknown',
    'external_transaction_id', 'tx-unknown', 'click_ref', 'cunknown.d0000000000.m202611.f0000000000',
    'transaction_status', 'pending', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 100
  )), 'simulation');
  if imported -> 0 ->> 'status' <> 'unattributed' then
    raise exception 'unknown clickref became a transaction';
  end if;
  begin
    perform public.import_affiliate_events('[]'::jsonb, 'live');
    raise exception 'browser admin imported a live event';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', user_c::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_c::text, true);
  execute 'set local role authenticated';
  begin
    perform public.import_affiliate_events('[]'::jsonb, 'simulation');
    raise exception 'user imported events';
  exception
    when insufficient_privilege then null;
  end;
  click_c := public.begin_affiliate_click('tracking-deal', code_b);
  if click_c ->> 'referrer_attached' <> 'true' then
    raise exception 'second buyer was not attributed to the direct referrer';
  end if;
  execute 'reset role';
  if exists (
    select 1 from public.referral_attributions
    where buyer_user_id = user_c and referrer_user_id = user_r
  ) then
    raise exception 'second-level referrer received the attribution';
  end if;
  if not exists (
    select 1 from public.referral_attributions
    where buyer_user_id = user_c and referrer_user_id = user_b and status = 'active'
  ) then
    raise exception 'direct referrer was missing';
  end if;

  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  execute 'set local role service_role';
  perform public.import_affiliate_events('[]'::jsonb, 'live');

  execute 'reset role';
  delete from public.cashback_ledger as rows
  where rows.transaction_id in (
    select tx.id from public.transactions as tx where tx.deal_id in (select deals.id from public.deals as deals where deals.slug = 'tracking-deal')
  );
  delete from public.community_allocations as rows
  where rows.commission_id in (
    select id from public.commissions
    where transaction_id in (
      select tx.id from public.transactions as tx where tx.deal_id in (select deals.id from public.deals as deals where deals.slug = 'tracking-deal')
    )
  );
  delete from public.commissions as rows
  where rows.transaction_id in (
    select tx.id from public.transactions as tx where tx.deal_id in (select deals.id from public.deals as deals where deals.slug = 'tracking-deal')
  );
  delete from public.cashback_accounts as rows
  where rows.user_id in (admin_id, user_r, user_b, user_c);
  delete from public.transactions as rows
  where rows.deal_id in (select id from public.deals where slug = 'tracking-deal');
  delete from public.affiliate_events as rows
  where rows.external_event_id in ('evt-r', 'evt-b', 'evt-b-2', 'evt-unknown');
  delete from public.referral_attributions as rows
  where rows.deal_id in (select id from public.deals where slug = 'tracking-deal');
  delete from public.clicks as rows
  where rows.deal_id in (select id from public.deals where slug = 'tracking-deal');
  delete from public.risk_events as rows
  where rows.user_id in (admin_id, user_r, user_b, user_c);
  delete from public.deal_rounds as rows
  where rows.deal_id in (select id from public.deals where slug = 'tracking-deal');
  delete from public.affiliate_links as rows
  where rows.deal_id in (select id from public.deals where slug = 'tracking-deal');
  delete from public.deals where slug = 'tracking-deal';
  delete from public.merchants where slug = 'tracking-haendler';
  delete from public.affiliate_accounts as accounts
  where accounts.account_reference = 'dev'
    and accounts.network = 'webgains'
    and not exists (
      select 1 from public.affiliate_links as links
      where links.affiliate_account_id = accounts.id
    );
  delete from auth.users where id in (admin_id, user_r, user_b, user_c);
end;
$$;
