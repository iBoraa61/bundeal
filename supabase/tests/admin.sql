-- Admin reads and actions stay behind the admin role.
-- A ledger row cannot be edited, including by an admin session.

do $$
declare
  admin_id uuid := gen_random_uuid();
  buyer uuid := gen_random_uuid();
  merchant_id uuid;
  main_deal uuid;
  round_id uuid;
  risk_id uuid;
  snapshot jsonb;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated', 'dash8-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', buyer, 'authenticated', 'authenticated', 'dash8-buyer@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  perform set_config('request.jwt.claims', json_build_object('sub', buyer::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', buyer::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  begin
    perform public.admin_operations_snapshot();
    raise exception 'user read the admin snapshot';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform public.close_risk_event(gen_random_uuid());
    raise exception 'user closed a risk event';
  exception
    when insufficient_privilege then null;
  end;
  begin
    perform public.close_deal_round(gen_random_uuid());
    raise exception 'user closed a round';
  exception
    when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  merchant_id := public.create_merchant('Dash8 Haendler', 'dash8-haendler', 'https://example.com');
  main_deal := public.create_published_deal(merchant_id, 'allgemein', 'dash8-deal', 'Dash8 Produkt', 'Ein ausreichend langer Beschreibungstext.', 10000, 'EUR', null);
  perform public.attach_affiliate_link(main_deal, 'webgains', 'dash8', 'simulation', 'https://example.com/track', 'clickref');
  execute 'reset role';
  select id into round_id
  from public.deal_rounds
  where deal_id = main_deal and environment = 'simulation' and round_status = 'open';
  if round_id is null then
    raise exception 'open round was not created';
  end if;
  insert into public.risk_events (user_id, risk_type, severity, status)
  values (buyer, 'self_referral', 'low', 'open')
  returning id into risk_id;
  insert into public.cashback_ledger (
    user_id, bucket, entry_type, amount_cents, currency, status, environment, idempotency_key, description
  ) values (
    buyer, 'basic_cashback', 'credit', 350, 'EUR', 'pending', 'simulation', 'dash8-ledger', 'admin test'
  );

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  snapshot := public.admin_operations_snapshot();
  if snapshot -> 'rounds' is null or snapshot -> 'audit' is null or snapshot -> 'payout_ready' is null then
    raise exception 'admin snapshot is incomplete';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(snapshot -> 'rounds') as entry
    where entry ->> 'deal_title' = 'Dash8 Produkt'
  ) then
    raise exception 'open round was missing from the admin snapshot';
  end if;
  perform public.close_risk_event(risk_id);
  perform public.close_deal_round(round_id);
  begin
    update public.cashback_ledger
    set description = 'changed'
    where idempotency_key = 'dash8-ledger';
    raise exception 'ledger was edited';
  exception
    when insufficient_privilege then null;
  end;

  execute 'reset role';
  begin
    update public.cashback_ledger
    set description = 'changed'
    where idempotency_key = 'dash8-ledger';
    raise exception 'ledger was edited by the table owner';
  exception
    when others then
      if sqlerrm not like '%append-only%' then
        raise;
      end if;
  end;

  if (select status from public.risk_events where id = risk_id) is distinct from 'closed' then
    raise exception 'risk event stayed open';
  end if;
  if (select round_status from public.deal_rounds where id = round_id) is distinct from 'closed' then
    raise exception 'round stayed open';
  end if;
  if not exists (
    select 1 from public.audit_logs
    where actor_user_id = admin_id and action in ('risk_event_closed', 'round_closed')
  ) then
    raise exception 'admin action was not audited';
  end if;

  delete from public.cashback_ledger where idempotency_key = 'dash8-ledger';
  delete from public.risk_events where id = risk_id;
  delete from public.audit_logs where actor_user_id in (admin_id, buyer);
  delete from public.deal_rounds where id = round_id;
  delete from public.affiliate_links where deal_id = main_deal;
  delete from public.affiliate_accounts where account_reference = 'dash8';
  delete from public.deals where id = main_deal;
  delete from public.merchants where id = merchant_id;
  delete from public.user_roles where user_id in (admin_id, buyer);
  delete from public.profiles where id in (admin_id, buyer);
  delete from auth.users where id in (admin_id, buyer);
end;
$$;
