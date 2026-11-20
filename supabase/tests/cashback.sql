-- Phase 6: 35/15/50 in cents, community hold, reversals, closed rounds, simulation/live split.

do $$
declare
  admin_id uuid := gen_random_uuid();
  user_r uuid := gen_random_uuid();
  user_b uuid := gen_random_uuid();
  user_c uuid := gen_random_uuid();
  code_r text;
  merchant_id uuid;
  main_deal uuid;
  delay_deal uuid;
  live_deal uuid;
  click_r jsonb;
  click_b jsonb;
  click_c jsonb;
  click_late jsonb;
  click_delay jsonb;
  click_live jsonb;
  imported jsonb;
  booked jsonb;
  row_basic bigint;
  row_referral bigint;
  row_community bigint;
  row_platform bigint;
  row_rounding bigint;
  row_gross bigint;
  ledger_count integer;
  ledger_after integer;
  available_r bigint;
  available_b bigint;
  pending_b bigint;
  seen integer;
  live_tx uuid;
  released integer;
  alt_version text := 't' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  delay_version text := 'd' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  restore_rule text := 'r' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
  restore_policy text := 'p' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12);
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated', 'phase6-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_r, 'authenticated', 'authenticated', 'phase6-r@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_b, 'authenticated', 'authenticated', 'phase6-b@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', user_c, 'authenticated', 'authenticated', 'phase6-c@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');
  select referral_code into code_r from public.profiles where id = user_r;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  merchant_id := public.create_merchant('Cashback Haendler', 'cashback-haendler', 'https://example.com');
  main_deal := public.create_published_deal(merchant_id, 'allgemein', 'cashback-deal', 'Cashback Produkt', 'Ein ausreichend langer Beschreibungstext.', 10000, 'EUR', null);
  delay_deal := public.create_published_deal(merchant_id, 'allgemein', 'cashback-delay', 'Spaeter Produkt', 'Ein ausreichend langer Beschreibungstext.', 10000, 'EUR', null);
  live_deal := public.create_published_deal(merchant_id, 'allgemein', 'cashback-live', 'Live Produkt', 'Ein ausreichend langer Beschreibungstext.', 10000, 'EUR', null);
  perform public.attach_affiliate_link(main_deal, 'webgains', 'phase6', 'simulation', 'https://example.com/track', 'clickref');
  perform public.attach_affiliate_link(delay_deal, 'webgains', 'phase6', 'simulation', 'https://example.com/track', 'clickref');

  perform set_config('request.jwt.claims', json_build_object('sub', user_r::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_r::text, true);
  execute 'set local role authenticated';
  click_r := public.begin_affiliate_click('cashback-deal', null);

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-r-pending',
    'external_transaction_id', 'p6-r', 'click_ref', click_r ->> 'click_ref',
    'transaction_status', 'pending', 'currency', 'EUR', 'occurred_at', now(),
    'order_amount_cents', 10000, 'commission_amount_cents', 1000
  )), 'simulation');
  if exists (select 1 from public.commissions where transaction_id in (
    select id from public.transactions where external_transaction_id = 'p6-r'
  )) then
    raise exception 'pending transaction created a commission';
  end if;

  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-r-confirmed',
    'external_transaction_id', 'p6-r', 'click_ref', click_r ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  select basic_cashback_cents, referral_bonus_cents, unassigned_community_cents,
         bundeal_revenue_cents, rounding_adjustment_cents
    into row_basic, row_referral, row_community, row_platform, row_rounding
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'p6-r');
  if row_basic <> 350 or row_referral <> 0 or row_community <> 150 or row_platform <> 500 or row_rounding <> 0 then
    raise exception 'unassigned 15 percent became platform revenue or the 10 euro split is wrong';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_b::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_b::text, true);
  execute 'set local role authenticated';
  click_b := public.begin_affiliate_click('cashback-deal', code_r);
  if click_b ->> 'referrer_attached' <> 'true' then
    raise exception 'direct referrer was not attached';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-b-confirmed',
    'external_transaction_id', 'p6-b', 'click_ref', click_b ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  select id into live_tx from public.transactions where external_transaction_id = 'p6-b';
  select basic_cashback_cents, referral_bonus_cents, unassigned_community_cents,
         bundeal_revenue_cents, rounding_adjustment_cents
    into row_basic, row_referral, row_community, row_platform, row_rounding
  from public.commissions where transaction_id = live_tx;
  if row_basic <> 350 or row_referral <> 150 or row_community <> 0 or row_platform <> 500 or row_rounding <> 0 then
    raise exception '10 euro commission did not produce 3.50 / 1.50 / 5.00';
  end if;
  select available_balance_cents into available_b
  from public.cashback_accounts where user_id = user_b and environment = 'simulation';
  select available_balance_cents into available_r
  from public.cashback_accounts where user_id = user_r and environment = 'simulation';
  if available_b <> 350 or available_r <> 500 then
    raise exception 'available balances do not match buyer cashback plus referrer bonus';
  end if;

  select count(*) into ledger_count from public.cashback_ledger where transaction_id = live_tx;
  perform public.process_commission(live_tx);
  select count(*) into ledger_after from public.cashback_ledger where transaction_id = live_tx;
  if ledger_count <> ledger_after then
    raise exception 'reprocessing created a duplicate credit';
  end if;

  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-c-pending',
    'external_transaction_id', 'p6-c-reject', 'click_ref', click_r ->> 'click_ref',
    'transaction_status', 'pending', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-c-rejected',
    'external_transaction_id', 'p6-c-reject', 'click_ref', click_r ->> 'click_ref',
    'transaction_status', 'rejected', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  if exists (
    select 1 from public.commissions
    where transaction_id = (select id from public.transactions where external_transaction_id = 'p6-c-reject')
  ) then
    raise exception 'rejection before confirmation created a payable commission';
  end if;

  booked := public.reverse_commission(live_tx, 0, 'rejected');
  if (booked ->> 'basic_cashback_cents')::bigint <> 0 or (booked ->> 'referral_bonus_cents')::bigint <> 0 then
    raise exception 'full reversal left a payable amount';
  end if;
  if (select coalesce(sum(amount_cents), 0) from public.cashback_ledger where transaction_id = live_tx) <> 0 then
    raise exception 'full reversal ledger does not return to zero';
  end if;
  select available_balance_cents into available_b
  from public.cashback_accounts where user_id = user_b and environment = 'simulation';
  select available_balance_cents into available_r
  from public.cashback_accounts where user_id = user_r and environment = 'simulation';
  if available_b <> 0 or available_r <> 350 then
    raise exception 'full reversal did not restore the balances';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_c::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_c::text, true);
  execute 'set local role authenticated';
  click_c := public.begin_affiliate_click('cashback-deal', null);

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-odd-1',
    'external_transaction_id', 'p6-odd-1', 'click_ref', click_c ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1
  )), 'simulation');
  select gross_commission_cents, basic_cashback_cents, referral_bonus_cents, unassigned_community_cents,
         bundeal_revenue_cents, rounding_adjustment_cents
    into row_gross, row_basic, row_referral, row_community, row_platform, row_rounding
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'p6-odd-1');
  if row_basic + row_referral + row_community + row_platform <> row_gross or row_rounding <> 1 then
    raise exception 'one cent did not reconcile';
  end if;

  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-odd-101',
    'external_transaction_id', 'p6-odd-101', 'click_ref', click_c ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 101
  )), 'simulation');
  select gross_commission_cents, basic_cashback_cents, unassigned_community_cents,
         bundeal_revenue_cents, rounding_adjustment_cents
    into row_gross, row_basic, row_community, row_platform, row_rounding
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'p6-odd-101');
  if row_basic <> 35 or row_community <> 15 or row_platform <> 51 or row_rounding <> 1
     or row_basic + row_community + row_platform <> row_gross then
    raise exception '101 cents did not reconcile with the remainder on the platform';
  end if;

  booked := public.reverse_commission(
    (select id from public.transactions where external_transaction_id = 'p6-odd-101'),
    40, 'adjusted'
  );
  if (booked ->> 'basic_cashback_cents')::bigint
       + (booked ->> 'unassigned_community_cents')::bigint
       + (booked ->> 'bundeal_revenue_cents')::bigint <> 40 then
    raise exception 'partial reversal does not reconcile to the new gross';
  end if;

  perform public.publish_commission_rule(alt_version, 4000, 1000, 5000);
  select basic_cashback_cents into row_basic
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'p6-r');
  perform public.process_commission((select id from public.transactions where external_transaction_id = 'p6-r'));
  if (select basic_cashback_cents from public.commissions
      where transaction_id = (select id from public.transactions where external_transaction_id = 'p6-r')) <> row_basic then
    raise exception 'a new rule changed an existing booking';
  end if;
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-new-rule',
    'external_transaction_id', 'p6-new-rule', 'click_ref', click_c ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  select basic_cashback_cents, unassigned_community_cents into row_basic, row_community
  from public.commissions
  where transaction_id = (select id from public.transactions where external_transaction_id = 'p6-new-rule');
  if row_basic <> 400 or row_community <> 100 then
    raise exception 'the new rule was not used for a later transaction';
  end if;
  begin
    update public.commission_rules set basic_cashback_basis_points = 1 where version = 'direct-v1';
    raise exception 'a published rule was edited';
  exception
    when others then
      if sqlerrm = 'a published rule was edited' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', user_b::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_b::text, true);
  execute 'set local role authenticated';
  click_delay := public.begin_affiliate_click('cashback-delay', null);
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.publish_cashback_policy(delay_version, 14);
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-delay',
    'external_transaction_id', 'p6-delay', 'click_ref', click_delay ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  select pending_balance_cents, available_balance_cents into pending_b, available_b
  from public.cashback_accounts where user_id = user_b and environment = 'simulation';
  if pending_b <> 400 or available_b <> 0 then
    raise exception 'release delay did not keep the cashback pending';
  end if;
  released := public.release_due_cashback('simulation', now());
  if released <> 0 then
    raise exception 'cashback was released before the delay';
  end if;
  released := public.release_due_cashback('simulation', now() + interval '15 days');
  if released <> 1 then
    raise exception 'due cashback was not released';
  end if;
  select pending_balance_cents, available_balance_cents into pending_b, available_b
  from public.cashback_accounts where user_id = user_b and environment = 'simulation';
  if pending_b <> 0 or available_b <> 400 then
    raise exception 'release did not move the pending balance';
  end if;

  begin
    perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
      'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-usd',
      'external_transaction_id', 'p6-usd', 'click_ref', click_c ->> 'click_ref',
      'transaction_status', 'confirmed', 'currency', 'USD', 'occurred_at', now(),
      'commission_amount_cents', 1000
    )), 'simulation');
    raise exception 'foreign currency was booked';
  exception
    when others then
      if sqlerrm = 'foreign currency was booked' then
        raise;
      end if;
  end;

  perform public.close_deal_round((
    select rounds.id from public.deal_rounds as rounds
    where rounds.deal_id = main_deal and rounds.environment = 'simulation' and rounds.round_status = 'open'
  ));
  perform set_config('request.jwt.claims', json_build_object('sub', user_c::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_c::text, true);
  execute 'set local role authenticated';
  click_late := public.begin_affiliate_click('cashback-deal', null);
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  imported := public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6', 'external_event_id', 'p6-late',
    'external_transaction_id', 'p6-late', 'click_ref', click_late ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'simulation');
  if imported -> 0 ->> 'status' <> 'unattributed' then
    raise exception 'a closed round accepted a new transaction';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', user_b::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_b::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  select count(*) into seen from public.cashback_ledger where user_id <> user_b;
  if seen <> 0 then
    raise exception 'buyer can read another ledger';
  end if;
  select count(*) into seen from public.community_allocations;
  if seen <> 0 then
    raise exception 'buyer can read the community allocation';
  end if;
  begin
    insert into public.cashback_ledger (
      user_id, bucket, entry_type, amount_cents, currency, status, environment, idempotency_key, description
    ) values (
      user_b, 'basic_cashback', 'credit', 1, 'EUR', 'available', 'simulation', 'forged', 'forged'
    );
    raise exception 'user inserted a ledger row';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform public.process_commission((select tx.id from public.transactions as tx where tx.external_transaction_id = 'p6-delay'));
    raise exception 'user processed a commission';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  perform public.attach_affiliate_link(live_deal, 'webgains', 'phase6-live', 'live', 'https://example.com/track', 'clickref');
  perform set_config('request.jwt.claims', json_build_object('sub', user_b::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', user_b::text, true);
  execute 'set local role authenticated';
  click_live := public.begin_affiliate_click('cashback-live', null);
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  execute 'set local role service_role';
  perform public.import_affiliate_events(jsonb_build_array(jsonb_build_object(
    'network', 'webgains', 'account_reference', 'phase6-live', 'external_event_id', 'p6-live',
    'external_transaction_id', 'p6-live', 'click_ref', click_live ->> 'click_ref',
    'transaction_status', 'confirmed', 'currency', 'EUR', 'occurred_at', now(),
    'commission_amount_cents', 1000
  )), 'live');
  execute 'reset role';
  select pending_balance_cents, available_balance_cents into pending_b, available_b
  from public.cashback_accounts where user_id = user_b and environment = 'live';
  if pending_b <> 400 or available_b <> 0 then
    raise exception 'live booking ignored the release delay';
  end if;
  select pending_balance_cents, available_balance_cents into pending_b, available_b
  from public.cashback_accounts where user_id = user_b and environment = 'simulation';
  if pending_b <> 0 or available_b <> 400 then
    raise exception 'simulation and live balances were mixed';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  begin
    perform public.process_commission((select id from public.transactions where external_transaction_id = 'p6-live'));
    raise exception 'browser admin processed a live commission';
  exception
    when insufficient_privilege then null;
  end;

  perform public.publish_commission_rule(restore_rule, 3500, 1500, 4000, 1000);
  perform public.publish_cashback_policy(restore_policy, 0);

  execute 'reset role';
  delete from public.cashback_ledger as rows
  where rows.user_id in (admin_id, user_r, user_b, user_c);
  delete from public.community_allocations as rows
  where rows.commission_id in (
    select id from public.commissions
    where transaction_id in (
      select tx.id from public.transactions as tx where tx.deal_id in (main_deal, delay_deal, live_deal)
    )
  );
  delete from public.commissions as rows
  where rows.transaction_id in (
    select tx.id from public.transactions as tx where tx.deal_id in (main_deal, delay_deal, live_deal)
  );
  delete from public.cashback_accounts as rows
  where rows.user_id in (admin_id, user_r, user_b, user_c);
  delete from public.transactions as rows where rows.deal_id in (main_deal, delay_deal, live_deal);
  delete from public.affiliate_events as rows
  where rows.affiliate_account_id in (
    select id from public.affiliate_accounts where account_reference in ('phase6', 'phase6-live')
  );
  delete from public.referral_attributions as rows where rows.deal_id in (main_deal, delay_deal, live_deal);
  delete from public.clicks as rows where rows.deal_id in (main_deal, delay_deal, live_deal);
  delete from public.risk_events as rows where rows.user_id in (admin_id, user_r, user_b, user_c);
  delete from public.deal_rounds as rows where rows.deal_id in (main_deal, delay_deal, live_deal);
  delete from public.affiliate_links as rows where rows.deal_id in (main_deal, delay_deal, live_deal);
  delete from public.deals where id in (main_deal, delay_deal, live_deal);
  delete from public.merchants where id = merchant_id;
  delete from public.affiliate_accounts where account_reference in ('phase6', 'phase6-live');
  delete from auth.users where id in (admin_id, user_r, user_b, user_c);
end;
$$;
