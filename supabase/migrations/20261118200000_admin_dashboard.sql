-- Admin operations are read models plus two audited actions.
-- Nothing here grants the admin role, edits a ledger row, or sends a payout.

create or replace function public.close_risk_event(p_event_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  update public.risk_events
  set status = 'closed'
  where id = p_event_id and status = 'open';
  if not found then
    raise exception 'risk event not open';
  end if;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id)
  values (auth.uid(), 'admin', 'risk_event_closed', 'risk_events', p_event_id);
end;
$$;

create or replace function public.admin_operations_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'rounds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rows.id,
        'deal_title', rows.title,
        'environment', rows.environment,
        'period_start', rows.period_start,
        'period_end', rows.period_end
      ) order by rows.period_start desc)
      from (
        select rounds.id, offer.title, rounds.environment, rounds.period_start, rounds.period_end
        from public.deal_rounds as rounds
        join public.deals as offer on offer.id = rounds.deal_id
        where rounds.round_status = 'open'
        order by rounds.period_start desc
        limit 20
      ) as rows
    ), '[]'::jsonb),
    'transactions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'deal_title', rows.title,
        'environment', rows.environment,
        'transaction_status', rows.transaction_status,
        'commission_cents', rows.commission_amount_cents,
        'buyer_name', rows.buyer_name,
        'transaction_date', rows.transaction_date
      ) order by rows.transaction_date desc)
      from (
        select offer.title, tx.environment, tx.transaction_status, tx.commission_amount_cents,
          coalesce(profiles.display_name, profiles.username, '') as buyer_name,
          tx.transaction_date
        from public.transactions as tx
        join public.deals as offer on offer.id = tx.deal_id
        left join public.profiles on profiles.id = tx.user_id
        order by tx.transaction_date desc
        limit 20
      ) as rows
    ), '[]'::jsonb),
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'event_type', rows.event_type,
        'environment', rows.environment,
        'processing_status', rows.processing_status,
        'error_code', rows.error_code,
        'received_at', rows.received_at
      ) order by rows.received_at desc)
      from (
        select event_type, environment, processing_status, error_code, received_at
        from public.affiliate_events
        order by received_at desc
        limit 20
      ) as rows
    ), '[]'::jsonb),
    'risks', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', rows.id,
        'risk_type', rows.risk_type,
        'severity', rows.severity,
        'status', rows.status,
        'created_at', rows.created_at
      ) order by rows.created_at desc)
      from (
        select id, risk_type, severity, status, created_at
        from public.risk_events
        order by created_at desc
        limit 20
      ) as rows
    ), '[]'::jsonb),
    'payout_ready', coalesce((
      select jsonb_agg(jsonb_build_object(
        'environment', grouped.environment,
        'cents', grouped.cents
      ))
      from (
        select ledger.environment, coalesce(sum(ledger.amount_cents), 0)::bigint as cents
        from public.cashback_ledger as ledger
        join public.transactions as tx on tx.id = ledger.transaction_id
        join public.deal_rounds as rounds on rounds.id = tx.deal_round_id
        where ledger.status = 'available'
          and rounds.round_status = 'closed'
        group by ledger.environment
      ) as grouped
    ), '[]'::jsonb),
    'payout_accounts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'name', grouped.account_name,
        'environment', grouped.environment,
        'cents', grouped.cents
      ))
      from (
        select
          coalesce(profiles.display_name, profiles.username, 'Konto') as account_name,
          ledger.environment,
          coalesce(sum(ledger.amount_cents), 0)::bigint as cents
        from public.cashback_ledger as ledger
        join public.transactions as tx on tx.id = ledger.transaction_id
        join public.deal_rounds as rounds on rounds.id = tx.deal_round_id
        left join public.profiles on profiles.id = ledger.user_id
        where ledger.status = 'available'
          and rounds.round_status = 'closed'
        group by profiles.display_name, profiles.username, ledger.environment
        having sum(ledger.amount_cents) > 0
        limit 20
      ) as grouped
    ), '[]'::jsonb),
    'audit', coalesce((
      select jsonb_agg(jsonb_build_object(
        'action', rows.action,
        'target_table', rows.target_table,
        'environment', rows.environment,
        'actor_name', rows.actor_name,
        'created_at', rows.created_at
      ) order by rows.created_at desc)
      from (
        select logs.action, logs.target_table, logs.environment, logs.created_at,
          coalesce(profiles.display_name, profiles.username, 'System') as actor_name
        from public.audit_logs as logs
        left join public.profiles on profiles.id = logs.actor_user_id
        order by logs.created_at desc
        limit 30
      ) as rows
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.close_risk_event(uuid) from public, anon;
revoke all on function public.admin_operations_snapshot() from public, anon;
grant execute on function public.close_risk_event(uuid) to authenticated;
grant execute on function public.admin_operations_snapshot() to authenticated;
