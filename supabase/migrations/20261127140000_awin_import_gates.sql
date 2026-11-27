-- Phase L5–L7 scaffolding. Live booking, the 30-day policy, and payouts stay off.

create table public.live_gates (
  id boolean primary key default true check (id),
  live_booking_enabled boolean not null default false,
  live_payout_enabled boolean not null default false,
  purchase_copy_enabled boolean not null default false,
  note text not null
);

insert into public.live_gates (note)
values ('30-day policy is not published. Purchase stays impossible. Checklist is not signed.');

revoke all on table public.live_gates from public, anon, authenticated;

create table public.import_runs (
  id uuid primary key default gen_random_uuid(),
  environment text not null,
  source text not null default 'awin',
  apply boolean not null,
  status text not null,
  row_count integer not null,
  ready_count integer not null,
  inserted_count integer not null,
  duplicate_count integer not null,
  unattributed_count integer not null,
  invalid_count integer not null,
  error_message text,
  created_at timestamptz not null default now(),
  constraint import_runs_environment_check check (environment in ('simulation', 'live')),
  constraint import_runs_status_check check (status in ('dry_run', 'applied', 'failed')),
  constraint import_runs_counts_check check (
    row_count >= 0 and ready_count >= 0 and inserted_count >= 0
    and duplicate_count >= 0 and unattributed_count >= 0 and invalid_count >= 0
  )
);

alter table public.import_runs enable row level security;

create policy import_runs_admin_select
on public.import_runs
for select
to authenticated
using (public.is_admin());

revoke all on table public.import_runs from public, anon;
grant select on table public.import_runs to authenticated;

create table public.payout_markers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id),
  environment text not null,
  amount_cents bigint not null,
  currency char(3) not null default 'EUR',
  reference_note text not null,
  created_at timestamptz not null default now(),
  constraint payout_markers_environment_check check (environment in ('simulation', 'live')),
  constraint payout_markers_amount_check check (amount_cents > 0),
  constraint payout_markers_note_check check (char_length(reference_note) between 1 and 80)
);

alter table public.payout_markers enable row level security;

create policy payout_markers_select_own_or_admin
on public.payout_markers
for select
to authenticated
using (user_id = auth.uid() or public.is_admin());

revoke all on table public.payout_markers from public, anon;
grant select on table public.payout_markers to authenticated;

create function public.awin_money_cents(p_amount text)
returns bigint
language sql
immutable
as $$
  select case
    when p_amount ~ '^[0-9]+(\.[0-9]{1,2})?$' then round(p_amount::numeric * 100)::bigint
    else null
  end;
$$;

revoke all on function public.awin_money_cents(text) from public, anon, authenticated;

-- Awin fields used: id, clickRef, commissionStatus, commissionAmount, saleAmount, currency, transactionDate.
-- commissionStatus: pending, approved -> confirmed, declined -> rejected.
-- Amounts are major units and become integer cents. Live apply stays blocked.
create function public.import_awin_rows(
  p_rows jsonb,
  p_environment text,
  p_apply boolean,
  p_account_reference text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  row_data jsonb;
  mapped jsonb;
  imported jsonb;
  item_status text;
  tx_status text;
  commission_cents bigint;
  order_cents bigint;
  event_id text;
  v_click_ref text;
  occurred_at timestamptz;
  seen text[] := '{}';
  account_id uuid;
  row_count integer := 0;
  ready_count integer := 0;
  inserted_count integer := 0;
  duplicate_count integer := 0;
  unattributed_count integer := 0;
  invalid_count integer := 0;
  run_status text;
  summary jsonb;
begin
  if p_environment = 'live' and public.caller_jwt_role() <> 'service_role' then
    raise exception 'live imports are server-only' using errcode = '42501';
  end if;
  if p_environment = 'simulation' and public.caller_jwt_role() <> 'service_role' and not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_environment not in ('simulation', 'live') or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'invalid import';
  end if;
  if p_account_reference is null or p_account_reference !~ '^[a-z0-9_-]{2,64}$' then
    raise exception 'invalid import';
  end if;
  if coalesce(p_apply, false) and p_environment = 'live' then
    raise exception 'live booking not enabled' using errcode = '42501';
  end if;

  select id into account_id
  from public.affiliate_accounts
  where network = 'awin'
    and account_reference = p_account_reference
    and environment = p_environment
    and active = true;

  for row_data in select value from jsonb_array_elements(p_rows) loop
    row_count := row_count + 1;
    tx_status := case row_data ->> 'commissionStatus'
      when 'pending' then 'pending'
      when 'approved' then 'confirmed'
      when 'declined' then 'rejected'
      else null
    end;
    commission_cents := public.awin_money_cents(row_data ->> 'commissionAmount');
    order_cents := case
      when row_data ->> 'saleAmount' is null or btrim(row_data ->> 'saleAmount') = '' then null
      else public.awin_money_cents(row_data ->> 'saleAmount')
    end;
    v_click_ref := row_data ->> 'clickRef';
    event_id := coalesce(row_data ->> 'id', '') || ':' || coalesce(row_data ->> 'commissionStatus', '');
    begin
      occurred_at := nullif(row_data ->> 'transactionDate', '')::timestamptz;
    exception
      when others then
        occurred_at := null;
    end;

    if tx_status is null
       or commission_cents is null
       or (row_data ->> 'saleAmount' is not null and btrim(row_data ->> 'saleAmount') <> '' and order_cents is null)
       or v_click_ref is null or v_click_ref !~ '^[A-Za-z0-9._:-]{4,120}$'
       or row_data ->> 'id' is null or row_data ->> 'id' !~ '^[A-Za-z0-9_-]{2,64}$'
       or row_data ->> 'currency' is null or row_data ->> 'currency' !~ '^[A-Z]{3}$'
       or occurred_at is null
       or event_id = any (seen) then
      if event_id = any (seen) and tx_status is not null then
        duplicate_count := duplicate_count + 1;
      else
        invalid_count := invalid_count + 1;
      end if;
      continue;
    end if;
    seen := seen || event_id;

    if not exists (
      select 1 from public.clicks
      where clicks.click_ref = v_click_ref and clicks.environment = p_environment
    ) then
      unattributed_count := unattributed_count + 1;
    else
      ready_count := ready_count + 1;
    end if;

    if not coalesce(p_apply, false) then
      continue;
    end if;
    if account_id is null then
      invalid_count := invalid_count + 1;
      continue;
    end if;

    mapped := jsonb_build_array(jsonb_build_object(
      'network', 'awin',
      'account_reference', p_account_reference,
      'external_event_id', event_id,
      'external_transaction_id', row_data ->> 'id',
      'click_ref', v_click_ref,
      'transaction_status', tx_status,
      'currency', row_data ->> 'currency',
      'occurred_at', occurred_at,
      'order_amount_cents', order_cents,
      'commission_amount_cents', commission_cents
    ));
    begin
      imported := public.import_affiliate_events(mapped, p_environment);
      item_status := imported -> 0 ->> 'status';
      if item_status = 'processed' then
        inserted_count := inserted_count + 1;
      elsif item_status = 'duplicate' then
        duplicate_count := duplicate_count + 1;
      elsif item_status = 'unattributed' then
        null;
      else
        invalid_count := invalid_count + 1;
      end if;
    exception
      when others then
        invalid_count := invalid_count + 1;
    end;
  end loop;

  run_status := case when coalesce(p_apply, false) then 'applied' else 'dry_run' end;
  insert into public.import_runs (
    environment, source, apply, status, row_count, ready_count, inserted_count,
    duplicate_count, unattributed_count, invalid_count
  ) values (
    p_environment, 'awin', coalesce(p_apply, false), run_status, row_count, ready_count,
    inserted_count, duplicate_count, unattributed_count, invalid_count
  );

  summary := jsonb_build_object(
    'status', run_status,
    'row_count', row_count,
    'ready_count', ready_count,
    'inserted_count', inserted_count,
    'duplicate_count', duplicate_count,
    'unattributed_count', unattributed_count,
    'invalid_count', invalid_count
  );
  return summary;
end;
$$;

revoke all on function public.import_awin_rows(jsonb, text, boolean, text) from public, anon;
grant execute on function public.import_awin_rows(jsonb, text, boolean, text) to authenticated, service_role;

create function public.record_manual_payout(
  p_user_id uuid,
  p_environment text,
  p_amount_cents bigint,
  p_reference_note text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  available_cents bigint;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_environment <> 'simulation' or exists (select 1 from public.live_gates where not live_payout_enabled and p_environment = 'live') then
    raise exception 'live payout not enabled' using errcode = '42501';
  end if;
  select coalesce(sum(ledger.amount_cents), 0)::bigint into available_cents
  from public.cashback_ledger as ledger
  join public.transactions as tx on tx.id = ledger.transaction_id
  join public.deal_rounds as rounds on rounds.id = tx.deal_round_id
  where ledger.user_id = p_user_id
    and ledger.environment = 'simulation'
    and ledger.status = 'available'
    and rounds.round_status = 'closed';
  if available_cents < coalesce(p_amount_cents, 0) or coalesce(p_amount_cents, 0) <= 0 then
    raise exception 'nothing available' using errcode = '42501';
  end if;
  if p_reference_note is null or char_length(btrim(p_reference_note)) < 1 or char_length(btrim(p_reference_note)) > 80 then
    raise exception 'invalid payout note';
  end if;

  insert into public.payout_markers (user_id, environment, amount_cents, reference_note)
  values (p_user_id, 'simulation', p_amount_cents, btrim(p_reference_note))
  returning id into new_id;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, environment, metadata)
  values (
    auth.uid(), 'admin', 'payout_marker_recorded', 'payout_markers', new_id, 'simulation',
    jsonb_build_object('amount_cents', p_amount_cents)
  );
  return new_id;
end;
$$;

revoke all on function public.record_manual_payout(uuid, text, bigint, text) from public, anon;
grant execute on function public.record_manual_payout(uuid, text, bigint, text) to authenticated;
