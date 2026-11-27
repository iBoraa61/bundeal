-- Per-merchant capability flags. A program join does not enable cashback or referrals.
-- Existing merchants keep the previous behaviour. New merchants start closed.
-- Listing deals show a shop price only and keep confirmed commission at BunDeal.

alter table public.merchants
  add column listing_allowed boolean not null default false,
  add column affiliate_tracking_allowed boolean not null default false,
  add column cashback_allowed boolean not null default false,
  add column referral_reward_allowed boolean not null default false,
  add column creator_campaign_allowed boolean not null default false,
  add column deal_creator_reward_allowed boolean not null default false,
  add column approval_notes text,
  add column approval_date timestamptz;

alter table public.merchants
  add constraint merchants_approval_notes_length
  check (approval_notes is null or char_length(approval_notes) <= 500);

alter table public.merchants
  add constraint merchants_capability_order
  check (
    (not referral_reward_allowed or cashback_allowed)
    and (not creator_campaign_allowed or (cashback_allowed and referral_reward_allowed))
  );

update public.merchants
set listing_allowed = true,
    affiliate_tracking_allowed = true,
    cashback_allowed = true,
    referral_reward_allowed = true,
    creator_campaign_allowed = true,
    deal_creator_reward_allowed = false;

alter table public.deals drop constraint deals_offer_mode_check;
alter table public.deals
  add constraint deals_offer_mode_check
  check (offer_mode in ('listing', 'cashback', 'referral', 'creator'));

create or replace function public.merchant_allows_offer_mode(p_merchant_id uuid, p_mode text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select case p_mode
    when 'listing' then merchants.listing_allowed
    when 'cashback' then merchants.cashback_allowed
    when 'referral' then merchants.cashback_allowed and merchants.referral_reward_allowed
    when 'creator' then merchants.cashback_allowed and merchants.referral_reward_allowed and merchants.creator_campaign_allowed
    else false
  end
  from public.merchants
  where merchants.id = p_merchant_id
    and merchants.status = 'active';
$$;

revoke all on function public.merchant_allows_offer_mode(uuid, text) from public, anon;
grant execute on function public.merchant_allows_offer_mode(uuid, text) to authenticated;

create or replace function public.set_merchant_capabilities(
  p_merchant_id uuid,
  p_listing_allowed boolean,
  p_affiliate_tracking_allowed boolean,
  p_cashback_allowed boolean,
  p_referral_reward_allowed boolean,
  p_creator_campaign_allowed boolean,
  p_deal_creator_reward_allowed boolean,
  p_approval_notes text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_approval_notes is not null and char_length(btrim(p_approval_notes)) > 500 then
    raise exception 'invalid approval notes';
  end if;
  if coalesce(p_referral_reward_allowed, false) and not coalesce(p_cashback_allowed, false) then
    raise exception 'referral requires cashback';
  end if;
  if coalesce(p_creator_campaign_allowed, false)
     and not (coalesce(p_cashback_allowed, false) and coalesce(p_referral_reward_allowed, false)) then
    raise exception 'creator requires cashback and referral';
  end if;

  update public.merchants
  set listing_allowed = coalesce(p_listing_allowed, false),
      affiliate_tracking_allowed = coalesce(p_affiliate_tracking_allowed, false),
      cashback_allowed = coalesce(p_cashback_allowed, false),
      referral_reward_allowed = coalesce(p_referral_reward_allowed, false),
      creator_campaign_allowed = coalesce(p_creator_campaign_allowed, false),
      deal_creator_reward_allowed = coalesce(p_deal_creator_reward_allowed, false),
      approval_notes = nullif(btrim(p_approval_notes), ''),
      approval_date = now()
  where id = p_merchant_id;
  if not found then
    raise exception 'merchant not available';
  end if;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin', 'merchant_capabilities_set', 'merchants', p_merchant_id,
    jsonb_build_object(
      'listing_allowed', coalesce(p_listing_allowed, false),
      'affiliate_tracking_allowed', coalesce(p_affiliate_tracking_allowed, false),
      'cashback_allowed', coalesce(p_cashback_allowed, false),
      'referral_reward_allowed', coalesce(p_referral_reward_allowed, false),
      'creator_campaign_allowed', coalesce(p_creator_campaign_allowed, false),
      'deal_creator_reward_allowed', coalesce(p_deal_creator_reward_allowed, false)
    )
  );
end;
$$;

revoke all on function public.set_merchant_capabilities(uuid, boolean, boolean, boolean, boolean, boolean, boolean, text) from public, anon;
grant execute on function public.set_merchant_capabilities(uuid, boolean, boolean, boolean, boolean, boolean, boolean, text) to authenticated;

create or replace function public.guard_offer_mode_click()
returns trigger
language plpgsql
as $$
declare
  mode text;
begin
  select offer_mode into mode from public.deals where id = new.deal_id;
  if mode in ('cashback', 'listing') then
    new.referrer_user_id := null;
    new.campaign_id := null;
  elsif mode = 'referral' then
    new.campaign_id := null;
  end if;
  return new;
end;
$$;

create or replace function public.guard_offer_mode_attribution()
returns trigger
language plpgsql
as $$
declare
  mode text;
begin
  select offer_mode into mode from public.deals where id = new.deal_id;
  if mode in ('cashback', 'listing') then
    return null;
  end if;
  return new;
end;
$$;

create or replace function public.guard_offer_mode_campaign()
returns trigger
language plpgsql
as $$
declare
  mode text;
begin
  select offer_mode into mode from public.deals where id = new.deal_id;
  if mode is distinct from 'creator' then
    raise exception 'creator offer required' using errcode = '42501';
  end if;
  return new;
end;
$$;

create or replace function public.create_published_deal(
  p_merchant_id uuid,
  p_category_slug text,
  p_slug text,
  p_title text,
  p_description text,
  p_price_cents bigint,
  p_currency text,
  p_image_url text default null,
  p_offer_mode text default 'referral'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
  category_id uuid;
  code text;
  created boolean := false;
  conflict_name text;
  chosen_mode text := coalesce(p_offer_mode, 'referral');
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if chosen_mode not in ('listing', 'cashback', 'referral', 'creator') then
    raise exception 'invalid offer mode';
  end if;
  if p_slug is null or p_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'invalid deal slug';
  end if;
  if nullif(btrim(p_title), '') is null or char_length(btrim(p_title)) > 140 then
    raise exception 'invalid deal title';
  end if;
  if p_description is null or char_length(p_description) < 10 or char_length(p_description) > 4000 then
    raise exception 'invalid deal description';
  end if;
  if p_price_cents is null or p_price_cents < 0 then
    raise exception 'invalid price';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception 'invalid currency';
  end if;
  if p_image_url is not null and not public.is_safe_https_url(p_image_url) then
    raise exception 'invalid image url';
  end if;
  if not exists (
    select 1 from public.merchants where id = p_merchant_id and status = 'active'
  ) then
    raise exception 'merchant not available';
  end if;
  if not public.merchant_allows_offer_mode(p_merchant_id, chosen_mode) then
    raise exception 'offer mode not allowed' using errcode = '42501';
  end if;

  select id into category_id
  from public.deal_categories
  where slug = coalesce(p_category_slug, 'allgemein');
  if category_id is null then
    raise exception 'category not available';
  end if;

  while not created loop
    code := public.random_public_code();
    begin
      insert into public.deals (
        slug, title, description, product_image_url, merchant_id, category_id,
        current_price_cents, currency, status, public_code, created_by, approved_by,
        published_at, offer_mode
      ) values (
        p_slug, btrim(p_title), p_description, p_image_url, p_merchant_id, category_id,
        p_price_cents, p_currency, 'published', code, auth.uid(), auth.uid(), now(), chosen_mode
      )
      returning id into new_id;
      created := true;
    exception
      when unique_violation then
        get stacked diagnostics conflict_name = constraint_name;
        if conflict_name <> 'deals_public_code_key' then
          raise;
        end if;
    end;
  end loop;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, environment, metadata)
  values (
    auth.uid(), 'admin', 'deal_published', 'deals', new_id, 'simulation',
    jsonb_build_object('slug', p_slug, 'offer_mode', chosen_mode)
  );

  return new_id;
end;
$$;

create or replace function public.set_deal_offer_mode(p_deal_id uuid, p_offer_mode text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  merchant uuid;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_offer_mode not in ('listing', 'cashback', 'referral', 'creator') then
    raise exception 'invalid offer mode';
  end if;
  select merchant_id into merchant from public.deals where id = p_deal_id;
  if merchant is null then
    raise exception 'deal not available';
  end if;
  if not public.merchant_allows_offer_mode(merchant, p_offer_mode) then
    raise exception 'offer mode not allowed' using errcode = '42501';
  end if;
  update public.deals
  set offer_mode = p_offer_mode
  where id = p_deal_id;
  if not found then
    raise exception 'deal not available';
  end if;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (auth.uid(), 'admin', 'deal_offer_mode_set', 'deals', p_deal_id, jsonb_build_object('offer_mode', p_offer_mode));
end;
$$;

create or replace function public.guard_affiliate_tracking()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.merchants
    where id = new.merchant_id and affiliate_tracking_allowed
  ) then
    raise exception 'affiliate tracking not allowed' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists affiliate_links_guard_tracking on public.affiliate_links;
create trigger affiliate_links_guard_tracking
before insert on public.affiliate_links
for each row
execute function public.guard_affiliate_tracking();

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

  if exists (
    select 1 from public.deals
    where id = tx.deal_id and offer_mode = 'listing'
  ) then
    applied := false;
    creator_applied := false;
    campaign_creator := null;
    target_basic := 0;
    target_referral := 0;
    target_creator := 0;
    target_community := 0;
    target_rounding := 0;
    target_platform := target_gross;
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
