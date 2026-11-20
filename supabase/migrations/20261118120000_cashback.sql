-- Phase 6 books confirmed commission in integer cents.
-- A published rule or policy is insert-only. Later decisions get a new version.
-- pilot-v1 pays the buyer and referrer as soon as a transaction is confirmed.
-- The unassigned 15% stays a community allocation. It is not platform revenue.
-- A closed monthly round is not reopened. Currency for this pilot is EUR.
-- Nothing here sends a payout.

create table public.commission_rules (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  basic_cashback_basis_points integer not null,
  referral_bonus_basis_points integer not null,
  platform_basis_points integer not null,
  effective_from timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  constraint commission_rules_version_check check (version ~ '^[a-z0-9][a-z0-9._-]{0,40}$'),
  constraint commission_rules_points_check check (
    basic_cashback_basis_points >= 0
    and referral_bonus_basis_points >= 0
    and platform_basis_points >= 0
    and basic_cashback_basis_points + referral_bonus_basis_points + platform_basis_points = 10000
  )
);

create table public.cashback_policies (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  release_delay_days integer not null,
  community_treatment text not null,
  late_arrival text not null,
  currency char(3) not null,
  effective_from timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  constraint cashback_policies_version_check check (version ~ '^[a-z0-9][a-z0-9._-]{0,40}$'),
  constraint cashback_policies_delay_check check (release_delay_days between 0 and 3650),
  constraint cashback_policies_community_check check (community_treatment = 'hold'),
  constraint cashback_policies_late_check check (late_arrival = 'reject_closed_round'),
  constraint cashback_policies_currency_check check (currency = 'EUR')
);

create table public.commissions (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null unique references public.transactions (id),
  rule_id uuid not null references public.commission_rules (id),
  referral_applied boolean not null,
  gross_commission_cents bigint not null,
  basic_cashback_cents bigint not null,
  referral_bonus_cents bigint not null,
  unassigned_community_cents bigint not null,
  bundeal_revenue_cents bigint not null,
  rounding_adjustment_cents bigint not null,
  commission_status text not null,
  environment text not null,
  currency char(3) not null,
  processed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint commissions_status_check check (commission_status in ('booked', 'reversed')),
  constraint commissions_environment_check check (environment in ('simulation', 'live')),
  constraint commissions_currency_check check (currency = 'EUR'),
  constraint commissions_nonnegative_check check (
    gross_commission_cents >= 0
    and basic_cashback_cents >= 0
    and referral_bonus_cents >= 0
    and unassigned_community_cents >= 0
    and bundeal_revenue_cents >= 0
    and rounding_adjustment_cents >= 0
  ),
  constraint commissions_split_check check (
    (referral_applied and unassigned_community_cents = 0)
    or (not referral_applied and referral_bonus_cents = 0)
  ),
  constraint commissions_reconcile_check check (
    basic_cashback_cents + referral_bonus_cents + unassigned_community_cents + bundeal_revenue_cents
      = gross_commission_cents
  )
);

create table public.cashback_accounts (
  user_id uuid not null references auth.users (id),
  environment text not null,
  currency char(3) not null,
  pending_balance_cents bigint not null default 0,
  available_balance_cents bigint not null default 0,
  reserved_balance_cents bigint not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, environment),
  constraint cashback_accounts_environment_check check (environment in ('simulation', 'live')),
  constraint cashback_accounts_currency_check check (currency = 'EUR'),
  constraint cashback_accounts_balance_check check (
    pending_balance_cents >= 0
    and available_balance_cents >= 0
    and reserved_balance_cents >= 0
  )
);

create table public.cashback_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id),
  transaction_id uuid references public.transactions (id),
  commission_id uuid references public.commissions (id),
  deal_round_id uuid references public.deal_rounds (id),
  reverses_entry_id uuid references public.cashback_ledger (id),
  bucket text not null,
  entry_type text not null,
  amount_cents bigint not null,
  currency char(3) not null,
  status text not null,
  environment text not null,
  available_on timestamptz,
  idempotency_key text not null unique,
  description text not null,
  created_at timestamptz not null default now(),
  constraint cashback_ledger_bucket_check check (bucket in ('basic_cashback', 'referral_bonus')),
  constraint cashback_ledger_type_check check (entry_type in ('credit', 'reversal', 'release')),
  constraint cashback_ledger_amount_check check (amount_cents <> 0),
  constraint cashback_ledger_status_check check (status in ('pending', 'available')),
  constraint cashback_ledger_environment_check check (environment in ('simulation', 'live')),
  constraint cashback_ledger_currency_check check (currency = 'EUR')
);

create table public.community_allocations (
  id uuid primary key default gen_random_uuid(),
  commission_id uuid not null references public.commissions (id),
  amount_cents bigint not null,
  currency char(3) not null,
  status text not null,
  rule_version text not null,
  environment text not null,
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  constraint community_allocations_amount_check check (amount_cents <> 0),
  constraint community_allocations_status_check check (status = 'held'),
  constraint community_allocations_currency_check check (currency = 'EUR'),
  constraint community_allocations_environment_check check (environment in ('simulation', 'live'))
);

create index cashback_ledger_user_idx
  on public.cashback_ledger (user_id, environment, status);
create index cashback_ledger_release_idx
  on public.cashback_ledger (environment, available_on)
  where status = 'pending' and amount_cents > 0;

create or replace function public.reject_financial_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' and current_user = 'postgres' then
    return old;
  end if;
  raise exception 'published financial rows are append-only';
end;
$$;

create trigger commission_rules_append_only
before update or delete on public.commission_rules
for each row execute function public.reject_financial_mutation();

create trigger cashback_policies_append_only
before update or delete on public.cashback_policies
for each row execute function public.reject_financial_mutation();

create trigger cashback_ledger_append_only
before update or delete on public.cashback_ledger
for each row execute function public.reject_financial_mutation();

create trigger community_allocations_append_only
before update or delete on public.community_allocations
for each row execute function public.reject_financial_mutation();

create or replace function public.protect_commission_identity()
returns trigger
language plpgsql
as $$
begin
  if new.transaction_id <> old.transaction_id
     or new.rule_id <> old.rule_id
     or new.referral_applied <> old.referral_applied
     or new.environment <> old.environment
     or new.currency <> old.currency then
    raise exception 'commission identity is immutable';
  end if;
  return new;
end;
$$;

create trigger commissions_protect_identity
before update on public.commissions
for each row execute function public.protect_commission_identity();

create trigger commissions_set_updated_at
before update on public.commissions
for each row execute function public.set_updated_at();

insert into public.commission_rules (
  version, basic_cashback_basis_points, referral_bonus_basis_points, platform_basis_points
) values ('direct-v1', 3500, 1500, 5000);

insert into public.cashback_policies (
  version, release_delay_days, community_treatment, late_arrival, currency
) values ('pilot-v1', 0, 'hold', 'reject_closed_round', 'EUR');

create or replace function public.current_commission_rule()
returns public.commission_rules
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.commission_rules
  order by effective_from desc, created_at desc
  limit 1;
$$;

create or replace function public.current_cashback_policy()
returns public.cashback_policies
language sql
stable
security definer
set search_path = public
as $$
  select *
  from public.cashback_policies
  order by effective_from desc, created_at desc
  limit 1;
$$;

create or replace function public.post_cashback_entry(
  p_user_id uuid,
  p_transaction_id uuid,
  p_commission_id uuid,
  p_round_id uuid,
  p_bucket text,
  p_entry_type text,
  p_amount_cents bigint,
  p_status text,
  p_environment text,
  p_available_on timestamptz,
  p_idempotency_key text,
  p_description text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.cashback_ledger (
    user_id, transaction_id, commission_id, deal_round_id, bucket, entry_type,
    amount_cents, currency, status, environment, available_on, idempotency_key, description
  ) values (
    p_user_id, p_transaction_id, p_commission_id, p_round_id, p_bucket, p_entry_type,
    p_amount_cents, 'EUR', p_status, p_environment, p_available_on, p_idempotency_key, p_description
  );

  -- Update first. A negative delta must not be inserted as a new row: the balance
  -- check rejects that proposed row before ON CONFLICT can add it to the existing account.
  update public.cashback_accounts as account
  set pending_balance_cents = account.pending_balance_cents
        + case when p_status = 'pending' then p_amount_cents else 0 end,
      available_balance_cents = account.available_balance_cents
        + case when p_status = 'available' then p_amount_cents else 0 end,
      updated_at = now()
  where account.user_id = p_user_id
    and account.environment = p_environment;

  if not found then
    insert into public.cashback_accounts (
      user_id, environment, currency, pending_balance_cents, available_balance_cents
    ) values (
      p_user_id, p_environment, 'EUR',
      case when p_status = 'pending' then p_amount_cents else 0 end,
      case when p_status = 'available' then p_amount_cents else 0 end
    );
  end if;
end;
$$;

create or replace function public.process_commission(p_transaction_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  tx public.transactions%rowtype;
  rule public.commission_rules%rowtype;
  policy public.cashback_policies%rowtype;
  commission_row public.commissions%rowtype;
  referrer uuid;
  applied boolean;
  target_gross bigint;
  target_basic bigint;
  target_referral bigint;
  target_community bigint;
  target_platform bigint;
  target_rounding bigint;
  platform_floor bigint;
  net_basic bigint;
  net_referral bigint;
  net_community bigint;
  delta bigint;
  bucket_status text;
  due_on timestamptz;
begin
  select * into tx from public.transactions where id = p_transaction_id for update;
  if tx.id is null then
    raise exception 'transaction not found';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_transaction_id::text, 0));

  if tx.environment = 'live' and public.caller_jwt_role() <> 'service_role' then
    raise exception 'live processing is server-only' using errcode = '42501';
  end if;
  if tx.environment = 'simulation' and public.caller_jwt_role() <> 'service_role' and not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;

  if tx.transaction_status = 'pending' then
    if exists (select 1 from public.commissions where transaction_id = tx.id) then
      raise exception 'confirmed commission cannot return to pending';
    end if;
    return jsonb_build_object('booked', false, 'reason', 'pending');
  end if;
  if tx.transaction_status not in ('confirmed', 'rejected', 'adjusted') then
    raise exception 'invalid transaction status';
  end if;

  policy := public.current_cashback_policy();
  if tx.currency <> policy.currency then
    raise exception 'currency not enabled';
  end if;

  select * into commission_row from public.commissions where transaction_id = tx.id;
  if commission_row.id is null then
    rule := public.current_commission_rule();
    select attributions.referrer_user_id into referrer
    from public.referral_attributions as attributions
    where attributions.id = tx.referral_attribution_id
      and attributions.referrer_user_id <> tx.user_id;
    applied := referrer is not null;
  else
    select * into rule from public.commission_rules where id = commission_row.rule_id;
    applied := commission_row.referral_applied;
    if applied then
      select attributions.referrer_user_id into referrer
      from public.referral_attributions as attributions
      where attributions.id = tx.referral_attribution_id;
    end if;
  end if;

  target_gross := case when tx.transaction_status = 'rejected' then 0 else tx.commission_amount_cents end;
  target_basic := (target_gross * rule.basic_cashback_basis_points) / 10000;
  target_referral := (target_gross * rule.referral_bonus_basis_points) / 10000;
  platform_floor := (target_gross * rule.platform_basis_points) / 10000;
  target_rounding := target_gross - target_basic - target_referral - platform_floor;
  target_platform := platform_floor + target_rounding;
  if applied then
    target_community := 0;
  else
    target_community := target_referral;
    target_referral := 0;
  end if;

  if commission_row.id is null then
    if target_gross = 0 then
      return jsonb_build_object('booked', false, 'reason', 'nothing_to_reverse');
    end if;
    insert into public.commissions (
      transaction_id, rule_id, referral_applied, gross_commission_cents,
      basic_cashback_cents, referral_bonus_cents, unassigned_community_cents,
      bundeal_revenue_cents, rounding_adjustment_cents, commission_status,
      environment, currency, processed_at
    ) values (
      tx.id, rule.id, applied, target_gross, target_basic, target_referral, target_community,
      target_platform, target_rounding,
      case when target_gross = 0 then 'reversed' else 'booked' end,
      tx.environment, tx.currency, now()
    )
    returning * into commission_row;
  end if;

  select coalesce(sum(amount_cents), 0) into net_basic
  from public.cashback_ledger
  where commission_id = commission_row.id and bucket = 'basic_cashback';
  select coalesce(sum(amount_cents), 0) into net_referral
  from public.cashback_ledger
  where commission_id = commission_row.id and bucket = 'referral_bonus';
  select coalesce(sum(amount_cents), 0) into net_community
  from public.community_allocations
  where commission_id = commission_row.id;

  due_on := coalesce(tx.confirmed_at, tx.transaction_date) + make_interval(days => policy.release_delay_days);

  if target_basic <> net_basic and tx.user_id is not null then
    delta := target_basic - net_basic;
    if delta > 0 and policy.release_delay_days = 0 then
      bucket_status := 'available';
    elsif delta > 0 then
      bucket_status := 'pending';
    elsif exists (
      select 1 from public.cashback_ledger
      where commission_id = commission_row.id and bucket = 'basic_cashback' and entry_type = 'release'
    ) or exists (
      select 1 from public.cashback_ledger
      where commission_id = commission_row.id and bucket = 'basic_cashback' and status = 'available' and amount_cents > 0
    ) then
      bucket_status := 'available';
    else
      bucket_status := 'pending';
    end if;
    perform public.post_cashback_entry(
      tx.user_id, tx.id, commission_row.id, tx.deal_round_id, 'basic_cashback',
      case when delta > 0 then 'credit' else 'reversal' end,
      delta, bucket_status, tx.environment,
      case when delta > 0 and bucket_status = 'pending' then due_on else null end,
      'book:' || commission_row.id::text || ':basic:' || net_basic::text || ':' || target_basic::text,
      case when delta > 0 then 'Grund-Cashback' else 'Storno Grund-Cashback' end
    );
  end if;

  if applied and referrer is not null and target_referral <> net_referral then
    delta := target_referral - net_referral;
    if delta > 0 and policy.release_delay_days = 0 then
      bucket_status := 'available';
    elsif delta > 0 then
      bucket_status := 'pending';
    elsif exists (
      select 1 from public.cashback_ledger
      where commission_id = commission_row.id and bucket = 'referral_bonus' and entry_type = 'release'
    ) or exists (
      select 1 from public.cashback_ledger
      where commission_id = commission_row.id and bucket = 'referral_bonus' and status = 'available' and amount_cents > 0
    ) then
      bucket_status := 'available';
    else
      bucket_status := 'pending';
    end if;
    perform public.post_cashback_entry(
      referrer, tx.id, commission_row.id, tx.deal_round_id, 'referral_bonus',
      case when delta > 0 then 'credit' else 'reversal' end,
      delta, bucket_status, tx.environment,
      case when delta > 0 and bucket_status = 'pending' then due_on else null end,
      'book:' || commission_row.id::text || ':referral:' || net_referral::text || ':' || target_referral::text,
      case when delta > 0 then 'Empfehlungsbonus' else 'Storno Empfehlungsbonus' end
    );
  end if;

  if target_community <> net_community then
    insert into public.community_allocations (
      commission_id, amount_cents, currency, status, rule_version, environment, idempotency_key
    ) values (
      commission_row.id, target_community - net_community, 'EUR', 'held', rule.version, tx.environment,
      'community:' || commission_row.id::text || ':' || net_community::text || ':' || target_community::text
    );
  end if;

  update public.commissions
  set gross_commission_cents = target_gross,
      basic_cashback_cents = target_basic,
      referral_bonus_cents = target_referral,
      unassigned_community_cents = target_community,
      bundeal_revenue_cents = target_platform,
      rounding_adjustment_cents = target_rounding,
      commission_status = case when target_gross = 0 then 'reversed' else 'booked' end,
      processed_at = now()
  where id = commission_row.id;

  return jsonb_build_object(
    'booked', true,
    'commission_id', commission_row.id,
    'basic_cashback_cents', target_basic,
    'referral_bonus_cents', target_referral,
    'unassigned_community_cents', target_community,
    'bundeal_revenue_cents', target_platform,
    'rounding_adjustment_cents', target_rounding
  );
end;
$$;

create or replace function public.reverse_commission(
  p_transaction_id uuid,
  p_new_commission_cents bigint,
  p_new_status text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  tx_environment text;
begin
  if p_new_status not in ('rejected', 'adjusted', 'confirmed')
     or p_new_commission_cents is null or p_new_commission_cents < 0 then
    raise exception 'invalid reversal';
  end if;
  select environment into tx_environment from public.transactions where id = p_transaction_id;
  if tx_environment is null then
    raise exception 'transaction not found';
  end if;
  if tx_environment = 'live' and public.caller_jwt_role() <> 'service_role' then
    raise exception 'live processing is server-only' using errcode = '42501';
  end if;
  if tx_environment = 'simulation' and public.caller_jwt_role() <> 'service_role' and not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;

  update public.transactions
  set transaction_status = p_new_status,
      commission_amount_cents = case when p_new_status = 'rejected' then 0 else p_new_commission_cents end,
      updated_at = now()
  where id = p_transaction_id;
  return public.process_commission(p_transaction_id);
end;
$$;

create or replace function public.release_due_cashback(
  p_environment text,
  p_as_of timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  due record;
  released integer := 0;
begin
  if p_environment = 'live' and public.caller_jwt_role() <> 'service_role' then
    raise exception 'live processing is server-only' using errcode = '42501';
  end if;
  if p_environment = 'simulation' and public.caller_jwt_role() <> 'service_role' and not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_environment not in ('simulation', 'live') then
    raise exception 'invalid environment';
  end if;

  for due in
    select commission_id, user_id, transaction_id, deal_round_id, bucket, currency,
           (sum(amount_cents) filter (where status = 'pending'))::bigint as net_pending
    from public.cashback_ledger
    where environment = p_environment
    group by commission_id, user_id, transaction_id, deal_round_id, bucket, currency
    having sum(amount_cents) filter (where status = 'pending') > 0
       and min(available_on) filter (where status = 'pending' and amount_cents > 0) <= p_as_of
  loop
    if exists (
      select 1 from public.cashback_ledger
      where idempotency_key = 'release:' || due.commission_id::text || ':' || due.bucket
    ) then
      continue;
    end if;
    perform public.post_cashback_entry(
      due.user_id, due.transaction_id, due.commission_id, due.deal_round_id, due.bucket,
      'release', -due.net_pending, 'pending', p_environment, null,
      'release-out:' || due.commission_id::text || ':' || due.bucket,
      'Freigabe aus vorgemerkt'
    );
    perform public.post_cashback_entry(
      due.user_id, due.transaction_id, due.commission_id, due.deal_round_id, due.bucket,
      'release', due.net_pending, 'available', p_environment, null,
      'release:' || due.commission_id::text || ':' || due.bucket,
      'Cashback verfuegbar'
    );
    released := released + 1;
  end loop;
  return released;
end;
$$;

create or replace function public.publish_commission_rule(
  p_version text,
  p_basic_points integer,
  p_referral_points integer,
  p_platform_points integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  rule_id uuid;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  insert into public.commission_rules (
    version, basic_cashback_basis_points, referral_bonus_basis_points, platform_basis_points,
    effective_from, created_at
  ) values (
    p_version, p_basic_points, p_referral_points, p_platform_points,
    clock_timestamp(), clock_timestamp()
  )
  returning id into rule_id;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin', 'commission_rule_published', 'commission_rules', rule_id,
    jsonb_build_object('version', p_version, 'basic', p_basic_points, 'referral', p_referral_points, 'platform', p_platform_points)
  );
  return rule_id;
end;
$$;

create or replace function public.publish_cashback_policy(
  p_version text,
  p_release_delay_days integer
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  policy_id uuid;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  insert into public.cashback_policies (
    version, release_delay_days, community_treatment, late_arrival, currency,
    effective_from, created_at
  ) values (
    p_version, p_release_delay_days, 'hold', 'reject_closed_round', 'EUR',
    clock_timestamp(), clock_timestamp()
  )
  returning id into policy_id;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin', 'cashback_policy_published', 'cashback_policies', policy_id,
    jsonb_build_object('version', p_version, 'release_delay_days', p_release_delay_days)
  );
  return policy_id;
end;
$$;

create or replace function public.cashback_admin_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rule public.commission_rules%rowtype;
  policy public.cashback_policies%rowtype;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  rule := public.current_commission_rule();
  policy := public.current_cashback_policy();
  return jsonb_build_object(
    'rule', jsonb_build_object(
      'version', rule.version,
      'basic', rule.basic_cashback_basis_points,
      'referral', rule.referral_bonus_basis_points,
      'platform', rule.platform_basis_points
    ),
    'policy', jsonb_build_object(
      'version', policy.version,
      'release_delay_days', policy.release_delay_days,
      'community_treatment', policy.community_treatment,
      'late_arrival', policy.late_arrival,
      'currency', policy.currency
    ),
    'reconciliation_failures', (
      select count(*) from public.commissions
      where basic_cashback_cents + referral_bonus_cents + unassigned_community_cents + bundeal_revenue_cents
        <> gross_commission_cents
    ),
    'pending_entries', (
      select count(*) from public.cashback_ledger
      where status = 'pending' and amount_cents > 0 and environment = 'simulation'
    ),
    'recent', coalesce((
      select jsonb_agg(row_to_json(items))
      from (
        select transactions.external_transaction_id, transactions.environment,
               commissions.gross_commission_cents, commissions.basic_cashback_cents,
               commissions.referral_bonus_cents, commissions.unassigned_community_cents,
               commissions.bundeal_revenue_cents, commissions.rounding_adjustment_cents,
               commissions.commission_status
        from public.commissions
        join public.transactions on transactions.id = commissions.transaction_id
        order by commissions.created_at desc
        limit 12
      ) items
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.book_transaction_commission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.transaction_status in ('confirmed', 'rejected', 'adjusted') then
    perform public.process_commission(new.id);
  end if;
  return new;
end;
$$;

create trigger transactions_book_commission
after insert or update of transaction_status, commission_amount_cents
on public.transactions
for each row execute function public.book_transaction_commission();

revoke all on function public.reject_financial_mutation() from public, anon, authenticated;
revoke all on function public.protect_commission_identity() from public, anon, authenticated;
revoke all on function public.current_commission_rule() from public, anon, authenticated;
revoke all on function public.current_cashback_policy() from public, anon, authenticated;
revoke all on function public.post_cashback_entry(uuid, uuid, uuid, uuid, text, text, bigint, text, text, timestamptz, text, text) from public, anon, authenticated;
revoke all on function public.process_commission(uuid) from public, anon;
revoke all on function public.reverse_commission(uuid, bigint, text) from public, anon;
revoke all on function public.release_due_cashback(text, timestamptz) from public, anon;
revoke all on function public.publish_commission_rule(text, integer, integer, integer) from public, anon;
revoke all on function public.publish_cashback_policy(text, integer) from public, anon;
revoke all on function public.cashback_admin_snapshot() from public, anon;
revoke all on function public.book_transaction_commission() from public, anon, authenticated;

grant execute on function public.process_commission(uuid) to authenticated, service_role;
grant execute on function public.reverse_commission(uuid, bigint, text) to authenticated, service_role;
grant execute on function public.release_due_cashback(text, timestamptz) to authenticated, service_role;
grant execute on function public.publish_commission_rule(text, integer, integer, integer) to authenticated;
grant execute on function public.publish_cashback_policy(text, integer) to authenticated;
grant execute on function public.cashback_admin_snapshot() to authenticated;

revoke all on table public.commission_rules from public, anon, authenticated;
revoke all on table public.cashback_policies from public, anon, authenticated;
revoke all on table public.commissions from public, anon, authenticated;
revoke all on table public.cashback_accounts from public, anon, authenticated;
revoke all on table public.cashback_ledger from public, anon, authenticated;
revoke all on table public.community_allocations from public, anon, authenticated;

grant select on table public.commission_rules to authenticated;
grant select on table public.cashback_policies to authenticated;
grant select on table public.commissions to authenticated;
grant select on table public.cashback_accounts to authenticated;
grant select on table public.cashback_ledger to authenticated;
grant select on table public.community_allocations to authenticated;

alter table public.commission_rules enable row level security;
alter table public.cashback_policies enable row level security;
alter table public.commissions enable row level security;
alter table public.cashback_accounts enable row level security;
alter table public.cashback_ledger enable row level security;
alter table public.community_allocations enable row level security;

create policy commission_rules_read
on public.commission_rules for select to authenticated
using (true);

create policy cashback_policies_read
on public.cashback_policies for select to authenticated
using (true);

create policy commissions_read_own
on public.commissions for select to authenticated
using (
  public.is_admin()
  or exists (
    select 1
    from public.transactions
    left join public.referral_attributions
      on referral_attributions.id = transactions.referral_attribution_id
    where transactions.id = commissions.transaction_id
      and (
        transactions.user_id = auth.uid()
        or referral_attributions.referrer_user_id = auth.uid()
      )
  )
);

create policy cashback_accounts_read_own
on public.cashback_accounts for select to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy cashback_ledger_read_own
on public.cashback_ledger for select to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy community_allocations_admin_read
on public.community_allocations for select to authenticated
using (public.is_admin());
