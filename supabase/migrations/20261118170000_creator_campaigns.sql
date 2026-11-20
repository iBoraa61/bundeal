-- Creator campaigns sit beside direct-v1. They do not replace it.
-- A campaign purchase uses 35/15/10/40. The 10% comes out of BunDeal's former 50%.
-- A purchase without a campaign folds those 10% back into BunDeal, so 35/15/50 stays.
-- The campaign id is stored on the click. The network clickref stays pseudonymous.

alter table public.commission_rules
  add column creator_share_basis_points integer not null default 0;

alter table public.commission_rules
  drop constraint commission_rules_points_check;

alter table public.commission_rules
  add constraint commission_rules_points_check check (
    basic_cashback_basis_points >= 0
    and referral_bonus_basis_points >= 0
    and creator_share_basis_points >= 0
    and platform_basis_points >= 0
    and basic_cashback_basis_points + referral_bonus_basis_points
      + creator_share_basis_points + platform_basis_points = 10000
  );

alter table public.commissions
  add column creator_applied boolean not null default false,
  add column creator_user_id uuid references auth.users (id),
  add column creator_share_cents bigint not null default 0;

alter table public.commissions
  drop constraint commissions_nonnegative_check;

alter table public.commissions
  add constraint commissions_nonnegative_check check (
    gross_commission_cents >= 0
    and basic_cashback_cents >= 0
    and referral_bonus_cents >= 0
    and unassigned_community_cents >= 0
    and creator_share_cents >= 0
    and bundeal_revenue_cents >= 0
    and rounding_adjustment_cents >= 0
  );

alter table public.commissions
  drop constraint commissions_reconcile_check;

alter table public.commissions
  add constraint commissions_reconcile_check check (
    basic_cashback_cents + referral_bonus_cents + unassigned_community_cents
      + creator_share_cents + bundeal_revenue_cents = gross_commission_cents
  );

alter table public.commissions
  add constraint commissions_creator_check check (
    (creator_applied and creator_user_id is not null)
    or (not creator_applied and creator_share_cents = 0 and creator_user_id is null)
  );

alter table public.cashback_ledger
  drop constraint cashback_ledger_bucket_check;

alter table public.cashback_ledger
  add constraint cashback_ledger_bucket_check check (
    bucket in ('basic_cashback', 'referral_bonus', 'creator_share')
  );

create table public.creator_campaigns (
  id uuid primary key default gen_random_uuid(),
  public_code text not null unique,
  creator_user_id uuid not null references auth.users (id),
  deal_id uuid not null references public.deals (id),
  status text not null default 'active',
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  constraint creator_campaigns_code_check check (public_code ~ '^[a-z0-9]{10}$'),
  constraint creator_campaigns_status_check check (status in ('active', 'ended')),
  constraint creator_campaigns_window_check check (ends_at > starts_at)
);

create unique index creator_campaigns_one_active
  on public.creator_campaigns (creator_user_id, deal_id)
  where status = 'active' and ended_at is null;

alter table public.clicks
  add column campaign_id uuid references public.creator_campaigns (id);

alter table public.clicks
  alter column clicked_at set default clock_timestamp();

alter table public.transactions
  add column campaign_id uuid references public.creator_campaigns (id);

create index transactions_campaign_idx
  on public.transactions (campaign_id)
  where campaign_id is not null;

create or replace function public.copy_click_campaign()
returns trigger
language plpgsql
as $$
begin
  if new.campaign_id is null and new.click_id is not null then
    select clicks.campaign_id into new.campaign_id
    from public.clicks
    where clicks.id = new.click_id;
  end if;
  return new;
end;
$$;

create trigger transactions_copy_campaign
before insert on public.transactions
for each row execute function public.copy_click_campaign();

create or replace function public.protect_commission_identity()
returns trigger
language plpgsql
as $$
begin
  if new.transaction_id <> old.transaction_id
     or new.rule_id <> old.rule_id
     or new.referral_applied <> old.referral_applied
     or new.creator_applied <> old.creator_applied
     or new.creator_user_id is distinct from old.creator_user_id
     or new.environment <> old.environment
     or new.currency <> old.currency then
    raise exception 'commission identity is immutable';
  end if;
  return new;
end;
$$;

drop function public.begin_affiliate_click(text, text);

create function public.begin_affiliate_click(
  p_deal_slug text,
  p_referrer_code text default null,
  p_campaign_code text default null
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
  campaign_code text;
  campaign_id uuid;
  campaign_creator uuid;
  round_id uuid;
  round_end timestamptz;
  click_id uuid;
  click_ref text;
  created boolean := false;
  outbound text;
  attached boolean := false;
  campaign_attached boolean := false;
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

  campaign_code := nullif(lower(btrim(coalesce(p_campaign_code, ''))), '');
  if campaign_code is not null then
    if campaign_code !~ '^[a-z0-9]{10}$' then
      insert into public.risk_events (user_id, risk_type, severity, metadata)
      values (buyer, 'invalid_campaign', 'low', jsonb_build_object('deal_id', deal_row.id));
    else
      select id, creator_user_id into campaign_id, campaign_creator
      from public.creator_campaigns
      where public_code = campaign_code
        and deal_id = deal_row.id
        and status = 'active'
        and ended_at is null
        and starts_at <= now()
        and ends_at > now();
      if campaign_id is null then
        insert into public.risk_events (user_id, risk_type, severity, metadata)
        values (buyer, 'invalid_campaign', 'low', jsonb_build_object('deal_id', deal_row.id));
      elsif campaign_creator = buyer then
        insert into public.risk_events (user_id, risk_type, severity, metadata)
        values (buyer, 'self_campaign', 'medium', jsonb_build_object('deal_id', deal_row.id, 'campaign_id', campaign_id));
        campaign_id := null;
        campaign_creator := null;
      else
        campaign_attached := true;
      end if;
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

    if not frozen and (
      exists (
        select 1 from public.transactions
        where user_id = referrer
          and deal_id = deal_row.id
          and environment = account_row.environment
          and transaction_status in ('pending', 'confirmed')
      )
      or (campaign_id is not null and referrer = campaign_creator)
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
        click_ref, user_id, deal_id, affiliate_link_id, referrer_user_id, campaign_id, affiliate_network, environment
      ) values (
        click_ref, buyer, deal_row.id, link_row.id, referrer, campaign_id, account_row.network, account_row.environment
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
    'referrer_attached', attached,
    'campaign_attached', campaign_attached
  );
end;
$$;

create or replace function public.campaign_code_for_share(p_deal_slug text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  buyer uuid := auth.uid();
  found_deal uuid;
  link_environment text;
  latest_campaign uuid;
  share_code text;
begin
  if buyer is null then
    return null;
  end if;
  select deals.id into found_deal
  from public.deals
  where deals.slug = p_deal_slug and deals.status = 'published';
  if found_deal is null then
    return null;
  end if;
  select accounts.environment into link_environment
  from public.affiliate_links as links
  join public.affiliate_accounts as accounts on accounts.id = links.affiliate_account_id
  where links.deal_id = found_deal and links.active = true and accounts.active = true;
  if link_environment is null then
    return null;
  end if;

  select clicks.campaign_id into latest_campaign
  from public.clicks
  where clicks.user_id = buyer
    and clicks.deal_id = found_deal
    and clicks.environment = link_environment
  order by clicks.clicked_at desc, clicks.ctid desc
  limit 1;
  if latest_campaign is null then
    return null;
  end if;

  select public_code into share_code
  from public.creator_campaigns
  where id = latest_campaign
    and status = 'active'
    and ended_at is null
    and ends_at > now();
  return share_code;
end;
$$;

create or replace function public.create_creator_campaign(p_deal_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  creator uuid := auth.uid();
  found_deal uuid;
  new_code text;
  campaign_id uuid;
  created boolean := false;
  conflict_name text;
  campaign_end timestamptz;
begin
  if creator is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  select id into found_deal
  from public.deals
  where slug = p_deal_slug and status = 'published';
  if found_deal is null then
    raise exception 'deal not available';
  end if;
  if exists (
    select 1 from public.creator_campaigns as existing
    where existing.creator_user_id = creator
      and existing.deal_id = found_deal
      and existing.status = 'active'
      and existing.ended_at is null
  ) then
    raise exception 'campaign already active';
  end if;

  campaign_end := now() + interval '90 days';
  while not created loop
    new_code := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into public.creator_campaigns (
        public_code, creator_user_id, deal_id, ends_at
      ) values (
        new_code, creator, found_deal, campaign_end
      )
      returning id into campaign_id;
      created := true;
    exception
      when unique_violation then
        get stacked diagnostics conflict_name = constraint_name;
        if conflict_name = 'creator_campaigns_public_code_key' then
          created := false;
        else
          raise exception 'campaign already active';
        end if;
    end;
  end loop;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    creator, 'user', 'creator_campaign_created', 'creator_campaigns', campaign_id,
    jsonb_build_object('deal_id', found_deal, 'public_code', new_code)
  );
  return jsonb_build_object(
    'public_code', new_code,
    'ends_at', campaign_end
  );
end;
$$;

create or replace function public.end_creator_campaign(p_public_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  actor uuid := auth.uid();
  campaign_id uuid;
begin
  if actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_public_code is null or p_public_code !~ '^[a-z0-9]{10}$' then
    raise exception 'campaign not available';
  end if;
  update public.creator_campaigns
  set status = 'ended', ended_at = now()
  where public_code = p_public_code
    and status = 'active'
    and ended_at is null
    and (creator_user_id = actor or public.is_admin())
  returning id into campaign_id;
  if campaign_id is null then
    raise exception 'campaign not available';
  end if;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (actor, case when public.is_admin() then 'admin' else 'user' end, 'creator_campaign_ended', 'creator_campaigns', campaign_id, '{}'::jsonb);
end;
$$;

create or replace function public.creator_campaign_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  creator uuid := auth.uid();
begin
  if creator is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(row_to_json(items))
    from (
      select
        campaigns.public_code,
        deals.slug as deal_slug,
        deals.title as deal_title,
        campaigns.status,
        campaigns.starts_at,
        campaigns.ends_at,
        campaigns.ended_at,
        coalesce((
          select count(*)
          from public.transactions
          where transactions.campaign_id = campaigns.id
            and transactions.environment = 'simulation'
            and transactions.transaction_status = 'pending'
        ), 0) as simulation_pending,
        coalesce((
          select count(*)
          from public.transactions
          where transactions.campaign_id = campaigns.id
            and transactions.environment = 'live'
            and transactions.transaction_status = 'pending'
        ), 0) as live_pending,
        coalesce((
          select sum(creator_share_cents)
          from public.commissions
          join public.transactions on transactions.id = commissions.transaction_id
          where transactions.campaign_id = campaigns.id
            and commissions.creator_user_id = creator
            and transactions.environment = 'simulation'
            and commissions.commission_status = 'booked'
        ), 0) as simulation_creator_cents,
        coalesce((
          select sum(creator_share_cents)
          from public.commissions
          join public.transactions on transactions.id = commissions.transaction_id
          where transactions.campaign_id = campaigns.id
            and commissions.creator_user_id = creator
            and transactions.environment = 'live'
            and commissions.commission_status = 'booked'
        ), 0) as live_creator_cents
      from public.creator_campaigns as campaigns
      join public.deals on deals.id = campaigns.deal_id
      where campaigns.creator_user_id = creator
      order by campaigns.created_at desc
    ) items
  ), '[]'::jsonb);
end;
$$;

create or replace function public.creator_admin_snapshot()
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
  return coalesce((
    select jsonb_agg(row_to_json(items))
    from (
      select
        campaigns.public_code,
        coalesce(profiles.display_name, profiles.username, 'Creator') as creator_name,
        deals.title as deal_title,
        campaigns.status,
        campaigns.ends_at,
        coalesce((
          select sum(creator_share_cents)
          from public.commissions
          join public.transactions on transactions.id = commissions.transaction_id
          where transactions.campaign_id = campaigns.id
            and commissions.creator_applied
            and transactions.environment = 'simulation'
        ), 0) as simulation_creator_cents,
        coalesce((
          select sum(creator_share_cents)
          from public.commissions
          join public.transactions on transactions.id = commissions.transaction_id
          where transactions.campaign_id = campaigns.id
            and commissions.creator_applied
            and transactions.environment = 'live'
        ), 0) as live_creator_cents
      from public.creator_campaigns as campaigns
      join public.deals on deals.id = campaigns.deal_id
      join public.profiles on profiles.id = campaigns.creator_user_id
      order by campaigns.created_at desc
      limit 20
    ) items
  ), '[]'::jsonb);
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
  campaign_creator uuid;
  creator_applied boolean;
  target_gross bigint;
  target_basic bigint;
  target_referral bigint;
  target_creator bigint;
  creator_part bigint;
  target_community bigint;
  target_platform bigint;
  target_rounding bigint;
  platform_floor bigint;
  net_basic bigint;
  net_referral bigint;
  net_creator bigint;
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
    select campaigns.creator_user_id into campaign_creator
    from public.creator_campaigns as campaigns
    where campaigns.id = tx.campaign_id
      and campaigns.deal_id = tx.deal_id
      and campaigns.creator_user_id <> tx.user_id
      and tx.transaction_date >= campaigns.starts_at
      and tx.transaction_date < campaigns.ends_at
      and (campaigns.ended_at is null or tx.transaction_date < campaigns.ended_at);
    creator_applied := campaign_creator is not null;
  else
    select * into rule from public.commission_rules where id = commission_row.rule_id;
    applied := commission_row.referral_applied;
    creator_applied := commission_row.creator_applied;
    campaign_creator := commission_row.creator_user_id;
    if applied then
      select attributions.referrer_user_id into referrer
      from public.referral_attributions as attributions
      where attributions.id = tx.referral_attribution_id;
    end if;
  end if;

  target_gross := case when tx.transaction_status = 'rejected' then 0 else tx.commission_amount_cents end;
  target_basic := (target_gross * rule.basic_cashback_basis_points) / 10000;
  target_referral := (target_gross * rule.referral_bonus_basis_points) / 10000;
  creator_part := (target_gross * rule.creator_share_basis_points) / 10000;
  platform_floor := (target_gross * rule.platform_basis_points) / 10000;
  if creator_applied then
    target_creator := creator_part;
  else
    target_creator := 0;
    platform_floor := platform_floor + creator_part;
  end if;
  target_rounding := target_gross - target_basic - target_referral - target_creator - platform_floor;
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
      transaction_id, rule_id, referral_applied, creator_applied, creator_user_id,
      gross_commission_cents, basic_cashback_cents, referral_bonus_cents,
      unassigned_community_cents, creator_share_cents, bundeal_revenue_cents,
      rounding_adjustment_cents, commission_status, environment, currency, processed_at
    ) values (
      tx.id, rule.id, applied, creator_applied, case when creator_applied then campaign_creator else null end,
      target_gross, target_basic, target_referral, target_community, target_creator, target_platform,
      target_rounding,
      case when target_gross = 0 then 'reversed' else 'booked' end,
      tx.environment, tx.currency, now()
    )
    returning * into commission_row;
  end if;

  select coalesce(sum(amount_cents), 0)::bigint into net_basic
  from public.cashback_ledger
  where commission_id = commission_row.id and bucket = 'basic_cashback';
  select coalesce(sum(amount_cents), 0)::bigint into net_referral
  from public.cashback_ledger
  where commission_id = commission_row.id and bucket = 'referral_bonus';
  select coalesce(sum(amount_cents), 0)::bigint into net_creator
  from public.cashback_ledger
  where commission_id = commission_row.id and bucket = 'creator_share';
  select coalesce(sum(amount_cents), 0)::bigint into net_community
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

  if creator_applied and campaign_creator is not null and target_creator <> net_creator then
    delta := target_creator - net_creator;
    if delta > 0 and policy.release_delay_days = 0 then
      bucket_status := 'available';
    elsif delta > 0 then
      bucket_status := 'pending';
    elsif exists (
      select 1 from public.cashback_ledger
      where commission_id = commission_row.id and bucket = 'creator_share' and entry_type = 'release'
    ) or exists (
      select 1 from public.cashback_ledger
      where commission_id = commission_row.id and bucket = 'creator_share' and status = 'available' and amount_cents > 0
    ) then
      bucket_status := 'available';
    else
      bucket_status := 'pending';
    end if;
    perform public.post_cashback_entry(
      campaign_creator, tx.id, commission_row.id, tx.deal_round_id, 'creator_share',
      case when delta > 0 then 'credit' else 'reversal' end,
      delta, bucket_status, tx.environment,
      case when delta > 0 and bucket_status = 'pending' then due_on else null end,
      'book:' || commission_row.id::text || ':creator:' || net_creator::text || ':' || target_creator::text,
      case when delta > 0 then 'Creator-Beteiligung' else 'Storno Creator-Beteiligung' end
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
      creator_share_cents = target_creator,
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
    'creator_share_cents', target_creator,
    'bundeal_revenue_cents', target_platform,
    'rounding_adjustment_cents', target_rounding
  );
end;
$$;

drop function public.publish_commission_rule(text, integer, integer, integer);

create function public.publish_commission_rule(
  p_version text,
  p_basic_points integer,
  p_referral_points integer,
  p_platform_points integer,
  p_creator_points integer default 0
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
  if p_basic_points + p_referral_points + p_creator_points + p_platform_points <> 10000
     or p_creator_points < 0 then
    raise exception 'invalid commission rule';
  end if;
  insert into public.commission_rules (
    version, basic_cashback_basis_points, referral_bonus_basis_points,
    creator_share_basis_points, platform_basis_points, effective_from, created_at
  ) values (
    p_version, p_basic_points, p_referral_points, p_creator_points, p_platform_points,
    clock_timestamp(), clock_timestamp()
  )
  returning id into rule_id;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin', 'commission_rule_published', 'commission_rules', rule_id,
    jsonb_build_object(
      'version', p_version, 'basic', p_basic_points, 'referral', p_referral_points,
      'creator', p_creator_points, 'platform', p_platform_points
    )
  );
  return rule_id;
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
      'creator', rule.creator_share_basis_points,
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
      where basic_cashback_cents + referral_bonus_cents + unassigned_community_cents
        + creator_share_cents + bundeal_revenue_cents <> gross_commission_cents
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
               commissions.creator_share_cents, commissions.bundeal_revenue_cents,
               commissions.rounding_adjustment_cents, commissions.commission_status
        from public.commissions
        join public.transactions on transactions.id = commissions.transaction_id
        order by commissions.created_at desc
        limit 12
      ) items
    ), '[]'::jsonb)
  );
end;
$$;

insert into public.commission_rules (
  version, basic_cashback_basis_points, referral_bonus_basis_points,
  creator_share_basis_points, platform_basis_points, effective_from, created_at
) values (
  'creator-v1', 3500, 1500, 1000, 4000, clock_timestamp(), clock_timestamp()
);

revoke all on function public.copy_click_campaign() from public, anon, authenticated;
revoke all on function public.begin_affiliate_click(text, text, text) from public, anon;
revoke all on function public.campaign_code_for_share(text) from public, anon;
revoke all on function public.create_creator_campaign(text) from public, anon;
revoke all on function public.end_creator_campaign(text) from public, anon;
revoke all on function public.creator_campaign_snapshot() from public, anon;
revoke all on function public.creator_admin_snapshot() from public, anon;
revoke all on function public.publish_commission_rule(text, integer, integer, integer, integer) from public, anon;

grant execute on function public.begin_affiliate_click(text, text, text) to authenticated;
grant execute on function public.campaign_code_for_share(text) to authenticated;
grant execute on function public.create_creator_campaign(text) to authenticated;
grant execute on function public.end_creator_campaign(text) to authenticated;
grant execute on function public.creator_campaign_snapshot() to authenticated;
grant execute on function public.creator_admin_snapshot() to authenticated;
grant execute on function public.publish_commission_rule(text, integer, integer, integer, integer) to authenticated;

revoke all on table public.creator_campaigns from public, anon, authenticated;
grant select on table public.creator_campaigns to authenticated;

alter table public.creator_campaigns enable row level security;

create policy creator_campaigns_read_own
on public.creator_campaigns for select to authenticated
using (creator_user_id = auth.uid() or public.is_admin());
