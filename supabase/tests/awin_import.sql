-- Phase L5–L7: Awin dry-run and apply stay in simulation. Live booking and payouts stay off.
-- Rolls back. Does not touch beispielhaendler.

begin;

do $$
declare
  admin_id uuid := gen_random_uuid();
  buyer_id uuid := gen_random_uuid();
  summary jsonb;
  event_count integer;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated',
    'l5-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb, now(), now(), '', '', '', ''
  );
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');
  insert into public.affiliate_accounts (network, account_reference, environment)
  values ('awin', 'dev', 'simulation');

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  summary := public.import_awin_rows(jsonb_build_array(
    jsonb_build_object(
      'id', 'awin-1001', 'clickRef', 'sampleclick0001', 'commissionStatus', 'approved',
      'commissionAmount', '10.50', 'saleAmount', '100.00', 'currency', 'EUR',
      'transactionDate', '2026-11-02T10:00:00Z'
    ),
    jsonb_build_object(
      'id', 'awin-1001', 'clickRef', 'sampleclick0001', 'commissionStatus', 'approved',
      'commissionAmount', '10.50', 'saleAmount', '100.00', 'currency', 'EUR',
      'transactionDate', '2026-11-02T10:00:00Z'
    ),
    jsonb_build_object(
      'id', 'awin-1003', 'clickRef', 'sampleclick0003', 'commissionStatus', 'bonus',
      'commissionAmount', '1.00', 'saleAmount', '5.00', 'currency', 'EUR',
      'transactionDate', '2026-11-04T10:00:00Z'
    )
  ), 'simulation', false, 'dev');

  if summary ->> 'status' <> 'dry_run'
     or (summary ->> 'unattributed_count')::int <> 1
     or (summary ->> 'duplicate_count')::int <> 1
     or (summary ->> 'invalid_count')::int <> 1
     or (summary ->> 'inserted_count')::int <> 0 then
    raise exception 'awin dry-run counts were wrong: %', summary;
  end if;

  summary := public.import_awin_rows(jsonb_build_array(
    jsonb_build_object(
      'id', 'awin-1001', 'clickRef', 'sampleclick0001', 'commissionStatus', 'approved',
      'commissionAmount', '10.50', 'saleAmount', '100.00', 'currency', 'EUR',
      'transactionDate', '2026-11-02T10:00:00Z'
    )
  ), 'simulation', true, 'dev');
  if summary ->> 'status' <> 'applied' or (summary ->> 'inserted_count')::int <> 0 then
    raise exception 'unattributed apply was stored as inserted: %', summary;
  end if;
  execute 'reset role';
  select count(*) into event_count
  from public.affiliate_events
  where external_event_id = 'awin-1001:approved';
  if event_count <> 1 then
    raise exception 'unattributed awin event was not stored once';
  end if;

  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';
  summary := public.import_awin_rows(jsonb_build_array(
    jsonb_build_object(
      'id', 'awin-1001', 'clickRef', 'sampleclick0001', 'commissionStatus', 'approved',
      'commissionAmount', '10.50', 'saleAmount', '100.00', 'currency', 'EUR',
      'transactionDate', '2026-11-02T10:00:00Z'
    )
  ), 'simulation', true, 'dev');
  if (summary ->> 'duplicate_count')::int <> 1 then
    raise exception 'second awin apply was not a duplicate: %', summary;
  end if;

  begin
    perform public.import_awin_rows('[]'::jsonb, 'live', true, 'dev');
    raise exception 'live awin import was applied';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'live imports are server-only' then
        raise;
      end if;
  end;

  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
  perform set_config('request.jwt.claim.role', 'service_role', true);
  execute 'set local role service_role';
  begin
    perform public.import_awin_rows('[]'::jsonb, 'live', true, 'dev');
    raise exception 'server role applied a live import';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'live booking not enabled' then
        raise;
      end if;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  begin
    perform public.record_manual_payout(buyer_id, 'live', 100, 'sepa');
    raise exception 'live payout was recorded';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'live payout not enabled' then
        raise;
      end if;
  end;

  begin
    perform public.record_manual_payout(admin_id, 'simulation', 100, 'lokal');
    raise exception 'empty balance was paid';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'nothing available' then
        raise;
      end if;
  end;

  execute 'reset role';
  if exists (select 1 from public.live_gates where live_booking_enabled or live_payout_enabled or purchase_copy_enabled) then
    raise exception 'a live gate was switched on';
  end if;
end;
$$;

rollback;
