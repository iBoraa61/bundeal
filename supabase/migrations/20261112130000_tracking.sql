-- Phase 5: server-side click references and idempotent transaction import.
-- Live rows cannot be created by a browser role.

create table public.affiliate_accounts (
  id uuid primary key default gen_random_uuid(),
  network text not null,
  account_reference text not null,
  environment text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint affiliate_accounts_network_check check (network ~ '^[a-z0-9_]{2,32}$'),
  constraint affiliate_accounts_reference_check check (account_reference ~ '^[a-z0-9_-]{2,64}$'),
  constraint affiliate_accounts_environment_check check (environment in ('simulation', 'live')),
  constraint affiliate_accounts_unique unique (network, account_reference, environment)
);

create table public.affiliate_links (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals (id),
  merchant_id uuid not null references public.merchants (id),
  affiliate_account_id uuid not null references public.affiliate_accounts (id),
  affiliate_url text not null,
  tracking_configuration jsonb not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint affiliate_links_url check (public.is_safe_https_url(affiliate_url)),
  constraint affiliate_links_parameter check (
    coalesce(tracking_configuration ->> 'parameter', '') ~ '^[a-z][a-z0-9_]{0,31}$'
  )
);

create unique index affiliate_links_one_active_per_deal
  on public.affiliate_links (deal_id)
  where active;

create trigger affiliate_links_set_updated_at
before update on public.affiliate_links
for each row execute function public.set_updated_at();

create table public.deal_rounds (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals (id),
  period_start timestamptz not null,
  period_end timestamptz not null,
  round_status text not null default 'open',
  environment text not null,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  constraint deal_rounds_period check (period_end > period_start),
  constraint deal_rounds_status_check check (round_status in ('open', 'closed')),
  constraint deal_rounds_environment_check check (environment in ('simulation', 'live')),
  constraint deal_rounds_unique unique (deal_id, period_start, environment)
);

create table public.clicks (
  id uuid primary key default gen_random_uuid(),
  click_ref text not null unique,
  user_id uuid not null references auth.users (id),
  deal_id uuid not null references public.deals (id),
  affiliate_link_id uuid not null references public.affiliate_links (id),
  referrer_user_id uuid references auth.users (id),
  affiliate_network text not null,
  environment text not null,
  clicked_at timestamptz not null default now(),
  constraint clicks_ref_format check (click_ref ~ '^[a-z0-9.]+$'),
  constraint clicks_environment_check check (environment in ('simulation', 'live')),
  constraint clicks_not_self check (referrer_user_id is null or referrer_user_id <> user_id)
);

alter table public.referral_attributions
  add constraint referral_attributions_source_click_fk
  foreign key (source_click_id) references public.clicks (id);

create table public.affiliate_events (
  id uuid primary key default gen_random_uuid(),
  affiliate_account_id uuid not null references public.affiliate_accounts (id),
  network text not null,
  environment text not null,
  external_event_id text not null,
  event_type text not null,
  payload jsonb not null,
  payload_hash text not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_status text not null,
  error_code text,
  constraint affiliate_events_environment_check check (environment in ('simulation', 'live')),
  constraint affiliate_events_status_check check (
    processing_status in ('processed', 'duplicate', 'unattributed', 'invalid')
  ),
  constraint affiliate_events_unique unique (affiliate_account_id, external_event_id, environment)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  affiliate_account_id uuid not null references public.affiliate_accounts (id),
  external_transaction_id text not null,
  user_id uuid references auth.users (id),
  deal_id uuid not null references public.deals (id),
  deal_round_id uuid not null references public.deal_rounds (id),
  click_id uuid references public.clicks (id),
  referral_attribution_id uuid references public.referral_attributions (id),
  affiliate_network text not null,
  order_amount_cents bigint,
  commission_amount_cents bigint not null,
  currency char(3) not null,
  transaction_status text not null,
  environment text not null,
  transaction_date timestamptz not null,
  confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint transactions_unique unique (affiliate_account_id, external_transaction_id, environment),
  constraint transactions_amounts_check check (
    commission_amount_cents >= 0
    and (order_amount_cents is null or order_amount_cents >= 0)
  ),
  constraint transactions_currency_check check (currency ~ '^[A-Z]{3}$'),
  constraint transactions_status_check check (
    transaction_status in ('pending', 'confirmed', 'rejected', 'adjusted')
  ),
  constraint transactions_environment_check check (environment in ('simulation', 'live'))
);

create trigger transactions_set_updated_at
before update on public.transactions
for each row execute function public.set_updated_at();

create or replace function public.caller_jwt_role()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role',
    ''
  );
$$;

revoke all on function public.caller_jwt_role() from public, anon, authenticated;

create or replace function public.ensure_open_round(
  p_deal_id uuid,
  p_environment text,
  p_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  round_id uuid;
  month_start timestamptz;
begin
  if p_environment not in ('simulation', 'live') then
    raise exception 'invalid environment';
  end if;
  month_start := date_trunc('month', p_at);
  select id into round_id
  from public.deal_rounds
  where deal_id = p_deal_id
    and environment = p_environment
    and round_status = 'open'
    and period_start <= p_at
    and period_end > p_at;
  if round_id is not null then
    return round_id;
  end if;
  if exists (
    select 1 from public.deal_rounds
    where deal_id = p_deal_id
      and environment = p_environment
      and period_start = month_start
      and round_status = 'closed'
  ) then
    return null;
  end if;

  insert into public.deal_rounds (deal_id, period_start, period_end, round_status, environment)
  values (p_deal_id, month_start, month_start + interval '1 month', 'open', p_environment)
  on conflict (deal_id, period_start, environment) do nothing
  returning id into round_id;

  if round_id is null then
    select id into round_id
    from public.deal_rounds
    where deal_id = p_deal_id
      and environment = p_environment
      and period_start = month_start
      and round_status = 'open';
  end if;
  return round_id;
end;
$$;

revoke all on function public.ensure_open_round(uuid, text, timestamptz) from public, anon, authenticated;

create or replace function public.attach_affiliate_link(
  p_deal_id uuid,
  p_network text,
  p_account_reference text,
  p_environment text,
  p_affiliate_url text,
  p_parameter text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  account_id uuid;
  link_id uuid;
  merchant_id uuid;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_environment not in ('simulation', 'live') then
    raise exception 'invalid environment';
  end if;
  if not public.is_safe_https_url(p_affiliate_url) then
    raise exception 'invalid affiliate url';
  end if;
  if p_parameter is null or p_parameter !~ '^[a-z][a-z0-9_]{0,31}$' then
    raise exception 'invalid tracking parameter';
  end if;

  select deals.merchant_id into merchant_id
  from public.deals
  where deals.id = p_deal_id and deals.status = 'published';
  if merchant_id is null then
    raise exception 'deal not available';
  end if;

  insert into public.affiliate_accounts (network, account_reference, environment)
  values (p_network, p_account_reference, p_environment)
  on conflict (network, account_reference, environment)
  do update set active = true
  returning id into account_id;

  update public.affiliate_links
  set active = false, updated_at = now()
  where deal_id = p_deal_id and active = true;

  insert into public.affiliate_links (
    deal_id, merchant_id, affiliate_account_id, affiliate_url, tracking_configuration, active
  ) values (
    p_deal_id, merchant_id, account_id, p_affiliate_url,
    jsonb_build_object('parameter', p_parameter), true
  )
  returning id into link_id;

  perform public.ensure_open_round(p_deal_id, p_environment, now());

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, environment, metadata)
  values (
    auth.uid(), 'admin', 'affiliate_link_attached', 'affiliate_links', link_id, p_environment,
    jsonb_build_object('network', p_network, 'parameter', p_parameter)
  );
  return link_id;
end;
$$;

create or replace function public.close_deal_round(p_round_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  update public.deal_rounds
  set round_status = 'closed', closed_at = now()
  where id = p_round_id and round_status = 'open';
  if not found then
    raise exception 'round not open';
  end if;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (auth.uid(), 'admin', 'round_closed', 'deal_rounds', p_round_id, '{}'::jsonb);
end;
$$;

create or replace function public.begin_affiliate_click(
  p_deal_slug text,
  p_referrer_code text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  buyer uuid := auth.uid();
  deal_row public.deals%rowtype;
  link_row public.affiliate_links%rowtype;
  account_row public.affiliate_accounts%rowtype;
  referrer uuid;
  referrer_code text;
  round_id uuid;
  round_end timestamptz;
  click_id uuid;
  click_ref text;
  created boolean := false;
  outbound text;
  attached boolean := false;
  frozen boolean := false;
  attribution_id uuid;
begin
  if buyer is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into deal_row
  from public.deals
  where slug = p_deal_slug and status = 'published';
  if deal_row.id is null then
    raise exception 'deal not available';
  end if;

  select * into link_row
  from public.affiliate_links
  where deal_id = deal_row.id and active = true;
  if link_row.id is null or not public.is_safe_https_url(link_row.affiliate_url) then
    raise exception 'affiliate link not available';
  end if;

  select * into account_row
  from public.affiliate_accounts
  where id = link_row.affiliate_account_id and active = true;
  if account_row.id is null then
    raise exception 'affiliate link not available';
  end if;

  referrer_code := nullif(lower(btrim(coalesce(p_referrer_code, ''))), '');
  if referrer_code is not null then
    select id into referrer from public.profiles where referral_code = referrer_code;
    if referrer is null then
      insert into public.risk_events (user_id, risk_type, severity, metadata)
      values (buyer, 'invalid_referrer', 'low', jsonb_build_object('deal_id', deal_row.id));
      referrer := null;
      referrer_code := null;
    elsif referrer = buyer then
      insert into public.risk_events (user_id, risk_type, severity, metadata)
      values (buyer, 'self_referral', 'medium', jsonb_build_object('deal_id', deal_row.id));
      referrer := null;
      referrer_code := null;
    end if;
  end if;

  round_id := public.ensure_open_round(deal_row.id, account_row.environment, now());
  if round_id is not null then
    select period_end into round_end from public.deal_rounds where id = round_id;
  end if;

  if referrer is not null and round_id is not null then
    select exists (
      select 1 from public.transactions
      where user_id = buyer
        and deal_id = deal_row.id
        and environment = account_row.environment
        and transaction_status in ('pending', 'confirmed')
        and referral_attribution_id is not null
    ) into frozen;

    if not frozen and exists (
      select 1 from public.transactions
      where user_id = referrer
        and deal_id = deal_row.id
        and environment = account_row.environment
        and transaction_status in ('pending', 'confirmed')
    ) then
      update public.referral_attributions
      set status = 'replaced'
      where deal_id = deal_row.id
        and buyer_user_id = buyer
        and environment = account_row.environment
        and status = 'active';

      insert into public.referral_attributions (
        deal_id, referrer_user_id, buyer_user_id, status, rule_version, environment, expires_at
      ) values (
        deal_row.id, referrer, buyer, 'active', 'direct-v1', account_row.environment, round_end
      )
      returning id into attribution_id;
      attached := true;
    elsif frozen then
      select referrer_user_id into referrer
      from public.referral_attributions
      where deal_id = deal_row.id
        and buyer_user_id = buyer
        and environment = account_row.environment
        and status = 'active';
      if referrer is null then
        referrer_code := null;
      else
        select referral_code into referrer_code from public.profiles where id = referrer;
      end if;
    else
      insert into public.risk_events (user_id, risk_type, severity, metadata)
      values (buyer, 'referrer_ineligible', 'low', jsonb_build_object('deal_id', deal_row.id));
      referrer := null;
      referrer_code := null;
    end if;
  elsif referrer is not null then
    insert into public.risk_events (user_id, risk_type, severity, metadata)
    values (buyer, 'no_open_round', 'low', jsonb_build_object('deal_id', deal_row.id));
    referrer := null;
    referrer_code := null;
  end if;

  while not created loop
    click_ref := 'c' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)
      || '.d' || deal_row.public_code
      || '.m' || to_char(coalesce((select period_start from public.deal_rounds where id = round_id), now()), 'YYYYMM')
      || '.f' || coalesce(referrer_code, '0000000000');
    begin
      insert into public.clicks (
        click_ref, user_id, deal_id, affiliate_link_id, referrer_user_id, affiliate_network, environment
      ) values (
        click_ref, buyer, deal_row.id, link_row.id, referrer, account_row.network, account_row.environment
      )
      returning id into click_id;
      created := true;
    exception
      when unique_violation then
        created := false;
    end;
  end loop;

  if attribution_id is not null then
    update public.referral_attributions
    set source_click_id = click_id
    where id = attribution_id;
  end if;

  if position('?' in link_row.affiliate_url) > 0 then
    outbound := link_row.affiliate_url || '&';
  else
    outbound := link_row.affiliate_url || '?';
  end if;
  outbound := outbound || (link_row.tracking_configuration ->> 'parameter') || '=' || click_ref;
  if outbound !~ '^https://' or click_ref !~ '^[a-z0-9.]+$' then
    raise exception 'unsafe affiliate url';
  end if;

  return jsonb_build_object(
    'click_ref', click_ref,
    'outbound_url', outbound,
    'environment', account_row.environment,
    'referrer_attached', attached
  );
end;
$$;

create or replace function public.referral_link_for_deal(p_deal_slug text)
returns text
language plpgsql
security definer
set search_path = public
stable
as $$
#variable_conflict use_variable
declare
  buyer uuid := auth.uid();
  deal_id uuid;
  link_environment text;
  own_code text;
begin
  if buyer is null then
    return null;
  end if;
  select deals.id into deal_id
  from public.deals
  where deals.slug = p_deal_slug and deals.status = 'published';
  if deal_id is null then
    return null;
  end if;
  select accounts.environment into link_environment
  from public.affiliate_links links
  join public.affiliate_accounts accounts on accounts.id = links.affiliate_account_id
  where links.deal_id = deal_id and links.active = true and accounts.active = true;
  if link_environment is null then
    return null;
  end if;
  if not exists (
    select 1 from public.transactions
    where user_id = buyer
      and transactions.deal_id = deal_id
      and environment = link_environment
      and transaction_status in ('pending', 'confirmed')
  ) then
    return null;
  end if;
  select referral_code into own_code from public.profiles where id = buyer;
  return own_code;
end;
$$;

create or replace function public.import_affiliate_events(
  p_events jsonb,
  p_environment text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  event_row jsonb;
  result jsonb := '[]'::jsonb;
  account_id uuid;
  network text;
  external_event_id text;
  external_transaction_id text;
  v_click_ref text;
  click_row public.clicks%rowtype;
  round_id uuid;
  existing_event uuid;
  existing_tx uuid;
  tx_status text;
  order_cents bigint;
  commission_cents bigint;
  currency text;
  occurred_at timestamptz;
  safe_payload jsonb;
  payload_hash text;
  attribution_id uuid;
  tx_id uuid;
begin
  if p_environment = 'live' and public.caller_jwt_role() <> 'service_role' then
    raise exception 'live imports are server-only' using errcode = '42501';
  end if;
  if p_environment = 'simulation' and public.caller_jwt_role() <> 'service_role' and not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_environment not in ('simulation', 'live') or jsonb_typeof(p_events) <> 'array' then
    raise exception 'invalid import';
  end if;

  for event_row in select value from jsonb_array_elements(p_events) loop
    network := event_row ->> 'network';
    external_event_id := event_row ->> 'external_event_id';
    external_transaction_id := event_row ->> 'external_transaction_id';
    v_click_ref := event_row ->> 'click_ref';
    tx_status := event_row ->> 'transaction_status';
    currency := event_row ->> 'currency';
    occurred_at := nullif(event_row ->> 'occurred_at', '')::timestamptz;
    order_cents := nullif(event_row ->> 'order_amount_cents', '')::bigint;
    commission_cents := nullif(event_row ->> 'commission_amount_cents', '')::bigint;

    if network is null or network !~ '^[a-z0-9_]{2,32}$'
       or external_event_id is null or external_transaction_id is null
       or v_click_ref is null or tx_status not in ('pending', 'confirmed', 'rejected', 'adjusted')
       or currency is null or currency !~ '^[A-Z]{3}$'
       or occurred_at is null or commission_cents is null or commission_cents < 0
       or (order_cents is not null and order_cents < 0)
       or event_row ->> 'account_reference' !~ '^[a-z0-9_-]{2,64}$' then
      raise exception 'invalid import';
    end if;

    select id into account_id
    from public.affiliate_accounts
    where affiliate_accounts.network = network
      and account_reference = event_row ->> 'account_reference'
      and environment = p_environment
      and active = true;
    if account_id is null then
      raise exception 'affiliate account not available';
    end if;

    safe_payload := jsonb_build_object(
      'network', network,
      'external_event_id', external_event_id,
      'external_transaction_id', external_transaction_id,
      'click_ref', v_click_ref,
      'transaction_status', tx_status,
      'currency', currency,
      'order_amount_cents', order_cents,
      'commission_amount_cents', commission_cents
    );
    payload_hash := md5(safe_payload::text);

    select id into existing_event
    from public.affiliate_events
    where affiliate_account_id = account_id
      and affiliate_events.external_event_id = external_event_id
      and environment = p_environment;
    if existing_event is not null then
      result := result || jsonb_build_array(jsonb_build_object('status', 'duplicate', 'external_event_id', external_event_id));
      continue;
    end if;

    select * into click_row from public.clicks where clicks.click_ref = v_click_ref;
    if click_row.id is null or click_row.environment <> p_environment then
      insert into public.affiliate_events (
        affiliate_account_id, network, environment, external_event_id, event_type,
        payload, payload_hash, processed_at, processing_status, error_code
      ) values (
        account_id, network, p_environment, external_event_id, 'transaction',
        safe_payload, payload_hash, now(), 'unattributed', 'unknown_click_ref'
      );
      result := result || jsonb_build_array(jsonb_build_object('status', 'unattributed', 'external_event_id', external_event_id));
      continue;
    end if;

    round_id := public.ensure_open_round(click_row.deal_id, p_environment, occurred_at);
    if round_id is null then
      insert into public.affiliate_events (
        affiliate_account_id, network, environment, external_event_id, event_type,
        payload, payload_hash, processed_at, processing_status, error_code
      ) values (
        account_id, network, p_environment, external_event_id, 'transaction',
        safe_payload, payload_hash, now(), 'unattributed', 'no_open_round'
      );
      result := result || jsonb_build_array(jsonb_build_object('status', 'unattributed', 'external_event_id', external_event_id));
      continue;
    end if;

    select id into attribution_id
    from public.referral_attributions
    where deal_id = click_row.deal_id
      and buyer_user_id = click_row.user_id
      and environment = p_environment
      and status = 'active'
      and referrer_user_id is not distinct from click_row.referrer_user_id
      and (expires_at is null or expires_at > occurred_at);

    select id into existing_tx
    from public.transactions
    where affiliate_account_id = account_id
      and transactions.external_transaction_id = external_transaction_id
      and environment = p_environment;

    if existing_tx is null then
      insert into public.transactions (
        affiliate_account_id, external_transaction_id, user_id, deal_id, deal_round_id,
        click_id, referral_attribution_id, affiliate_network, order_amount_cents,
        commission_amount_cents, currency, transaction_status, environment, transaction_date, confirmed_at
      ) values (
        account_id, external_transaction_id, click_row.user_id, click_row.deal_id, round_id,
        click_row.id, attribution_id, network, order_cents, commission_cents, currency, tx_status,
        p_environment, occurred_at, case when tx_status = 'confirmed' then now() else null end
      )
      returning id into tx_id;
    else
      update public.transactions
      set transaction_status = tx_status,
          commission_amount_cents = commission_cents,
          order_amount_cents = order_cents,
          confirmed_at = case
            when tx_status = 'confirmed' then coalesce(confirmed_at, now())
            else confirmed_at
          end
      where id = existing_tx
      returning id into tx_id;
    end if;

    insert into public.affiliate_events (
      affiliate_account_id, network, environment, external_event_id, event_type,
      payload, payload_hash, processed_at, processing_status
    ) values (
      account_id, network, p_environment, external_event_id, 'transaction',
      safe_payload, payload_hash, now(), 'processed'
    );
    result := result || jsonb_build_array(jsonb_build_object(
      'status', 'processed',
      'external_event_id', external_event_id,
      'transaction_id', tx_id
    ));
  end loop;

  return result;
end;
$$;

revoke all on function public.attach_affiliate_link(uuid, text, text, text, text, text) from public, anon;
revoke all on function public.close_deal_round(uuid) from public, anon;
revoke all on function public.begin_affiliate_click(text, text) from public, anon;
revoke all on function public.referral_link_for_deal(text) from public, anon;
revoke all on function public.import_affiliate_events(jsonb, text) from public, anon;
grant execute on function public.attach_affiliate_link(uuid, text, text, text, text, text) to authenticated;
grant execute on function public.close_deal_round(uuid) to authenticated;
grant execute on function public.begin_affiliate_click(text, text) to authenticated;
grant execute on function public.referral_link_for_deal(text) to authenticated;
grant execute on function public.import_affiliate_events(jsonb, text) to authenticated, service_role;

revoke all on table public.affiliate_accounts from public, anon, authenticated;
revoke all on table public.affiliate_links from public, anon, authenticated;
revoke all on table public.deal_rounds from public, anon, authenticated;
revoke all on table public.clicks from public, anon, authenticated;
revoke all on table public.affiliate_events from public, anon, authenticated;
revoke all on table public.transactions from public, anon, authenticated;

grant select on table public.affiliate_accounts to authenticated;
grant select on table public.affiliate_links to authenticated;
grant select on table public.deal_rounds to authenticated;
grant select on table public.clicks to authenticated;
grant select on table public.affiliate_events to authenticated;
grant select on table public.transactions to authenticated;

alter table public.affiliate_accounts enable row level security;
alter table public.affiliate_links enable row level security;
alter table public.deal_rounds enable row level security;
alter table public.clicks enable row level security;
alter table public.affiliate_events enable row level security;
alter table public.transactions enable row level security;

create policy affiliate_accounts_admin_select
on public.affiliate_accounts for select to authenticated
using (public.is_admin());

create policy affiliate_links_admin_select
on public.affiliate_links for select to authenticated
using (public.is_admin());

create policy deal_rounds_admin_select
on public.deal_rounds for select to authenticated
using (public.is_admin());

create policy clicks_select_own_or_admin
on public.clicks for select to authenticated
using (user_id = auth.uid() or public.is_admin());

create policy affiliate_events_admin_select
on public.affiliate_events for select to authenticated
using (public.is_admin());

create policy transactions_select_own_or_admin
on public.transactions for select to authenticated
using (user_id = auth.uid() or public.is_admin());
