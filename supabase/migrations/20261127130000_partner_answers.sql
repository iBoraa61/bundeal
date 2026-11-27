-- Phase L3: store written advertiser answers. No live link, no payout, no purchase.

create table public.advertiser_answers (
  merchant_id uuid primary key references public.merchants (id),
  cashback_answer text not null,
  referral_answer text not null,
  source_note text not null,
  owner_confirmed boolean not null default false,
  recorded_at timestamptz not null default now(),
  confirmed_at timestamptz,
  constraint advertiser_answers_cashback check (cashback_answer in ('yes', 'no', 'pending')),
  constraint advertiser_answers_referral check (referral_answer in ('yes', 'no', 'pending')),
  constraint advertiser_answers_order check (referral_answer <> 'yes' or cashback_answer = 'yes'),
  constraint advertiser_answers_note check (char_length(source_note) between 1 and 240)
);

alter table public.advertiser_answers enable row level security;

create policy advertiser_answers_admin_select
on public.advertiser_answers
for select
to authenticated
using (public.is_admin());

revoke all on table public.advertiser_answers from public, anon;
grant select on table public.advertiser_answers to authenticated;

create function public.assert_advertiser_answer(p_merchant_id uuid, p_mode text)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  answer public.advertiser_answers%rowtype;
begin
  select * into answer
  from public.advertiser_answers
  where merchant_id = p_merchant_id;
  if not found then
    return;
  end if;
  if not answer.owner_confirmed then
    raise exception 'partner matrix not confirmed' using errcode = '42501';
  end if;
  if p_mode in ('cashback', 'referral', 'creator') and answer.cashback_answer <> 'yes' then
    raise exception 'cashback not approved' using errcode = '42501';
  end if;
  if p_mode in ('referral', 'creator') and answer.referral_answer <> 'yes' then
    raise exception 'referral not approved' using errcode = '42501';
  end if;
end;
$$;

revoke all on function public.assert_advertiser_answer(uuid, text) from public, anon, authenticated;

create function public.save_advertiser_answer(
  p_merchant_id uuid,
  p_cashback_answer text,
  p_referral_answer text,
  p_source_note text
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
  if p_cashback_answer not in ('yes', 'no', 'pending')
     or p_referral_answer not in ('yes', 'no', 'pending') then
    raise exception 'invalid advertiser answer';
  end if;
  if p_referral_answer = 'yes' and p_cashback_answer <> 'yes' then
    raise exception 'referral requires cashback';
  end if;
  if p_source_note is null
     or char_length(btrim(p_source_note)) < 1
     or char_length(btrim(p_source_note)) > 240 then
    raise exception 'invalid advertiser note';
  end if;
  if not exists (
    select 1 from public.merchants where id = p_merchant_id and status = 'active'
  ) then
    raise exception 'merchant not available';
  end if;

  insert into public.advertiser_answers (
    merchant_id, cashback_answer, referral_answer, source_note, owner_confirmed, confirmed_at
  ) values (
    p_merchant_id, p_cashback_answer, p_referral_answer, btrim(p_source_note), false, null
  )
  on conflict (merchant_id) do update
  set cashback_answer = excluded.cashback_answer,
      referral_answer = excluded.referral_answer,
      source_note = excluded.source_note,
      owner_confirmed = false,
      confirmed_at = null,
      recorded_at = now();

  update public.merchants
  set cashback_allowed = (p_cashback_answer = 'yes'),
      referral_reward_allowed = (p_referral_answer = 'yes'),
      creator_campaign_allowed = case
        when p_referral_answer = 'yes' then creator_campaign_allowed
        else false
      end,
      deal_creator_reward_allowed = false
  where id = p_merchant_id;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin', 'advertiser_answer_recorded', 'advertiser_answers', p_merchant_id,
    jsonb_build_object(
      'cashback_answer', p_cashback_answer,
      'referral_answer', p_referral_answer,
      'owner_confirmed', false
    )
  );
end;
$$;

revoke all on function public.save_advertiser_answer(uuid, text, text, text) from public, anon;
grant execute on function public.save_advertiser_answer(uuid, text, text, text) to authenticated;

create function public.confirm_advertiser_answer(p_merchant_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  update public.advertiser_answers
  set owner_confirmed = true,
      confirmed_at = now()
  where merchant_id = p_merchant_id;
  if not found then
    raise exception 'advertiser answer not available';
  end if;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin', 'advertiser_answer_confirmed', 'advertiser_answers', p_merchant_id,
    jsonb_build_object('owner_confirmed', true)
  );
end;
$$;

revoke all on function public.confirm_advertiser_answer(uuid) from public, anon;
grant execute on function public.confirm_advertiser_answer(uuid) to authenticated;

create or replace function public.create_published_deal(
  p_merchant_id uuid,
  p_category_slug text,
  p_slug text,
  p_title text,
  p_description text,
  p_price_cents bigint,
  p_currency text,
  p_image_url text default null,
  p_offer_mode text default 'referral',
  p_original_price_cents bigint default null
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
  if p_original_price_cents is not null and p_original_price_cents < p_price_cents then
    raise exception 'invalid original price';
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
  perform public.assert_advertiser_answer(p_merchant_id, chosen_mode);
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
        original_price_cents, current_price_cents, currency, status, public_code,
        created_by, approved_by, published_at, offer_mode
      ) values (
        p_slug, btrim(p_title), p_description, p_image_url, p_merchant_id, category_id,
        p_original_price_cents, p_price_cents, p_currency, 'published', code,
        auth.uid(), auth.uid(), now(), chosen_mode
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
  perform public.assert_advertiser_answer(merchant, p_offer_mode);
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

with inserted as (
  insert into public.merchants (
    name, slug, website_url, status,
    listing_allowed, affiliate_tracking_allowed, cashback_allowed,
    referral_reward_allowed, creator_campaign_allowed, deal_creator_reward_allowed,
    approval_notes, approval_date
  ) values
    (
      'Finanzguru', 'finanzguru', 'https://finanzguru.de', 'active',
      true, false, true, false, false, false,
      'Cashback ja, Empfehlung nein. Matrix noch nicht bestätigt.', now()
    ),
    (
      '123.live', '123-live', 'https://123.live', 'active',
      true, false, true, false, false, false,
      'Cashback ja, Empfehlung nein. Matrix noch nicht bestätigt.', now()
    ),
    (
      'Guiders', 'guiders', 'https://guiders.de', 'active',
      true, false, true, false, false, false,
      'Cashback ja, Empfehlung offen. Matrix noch nicht bestätigt.', now()
    ),
    (
      'Wondershare', 'wondershare', 'https://www.wondershare.com', 'active',
      true, false, true, true, false, false,
      'Cashback ja, Empfehlung ja. Matrix noch nicht bestätigt. Kein Live-Link.', now()
    )
  returning id, slug
)
insert into public.advertiser_answers (merchant_id, cashback_answer, referral_answer, source_note)
select
  inserted.id,
  'yes',
  case inserted.slug
    when 'finanzguru' then 'no'
    when '123-live' then 'no'
    when 'guiders' then 'pending'
    else 'yes'
  end,
  case inserted.slug
    when 'guiders' then 'Schriftliche Antwort: Cashback ja, Empfehlung offen. Startseite noch bestätigen.'
    when 'wondershare' then 'Schriftliche Antwort: Cashback ja, Empfehlung ja. Kein Live-Link.'
    else 'Schriftliche Antwort: Cashback ja, Empfehlung nein.'
  end
from inserted;

insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
select
  null, 'system', 'advertiser_answer_recorded', 'advertiser_answers', answers.merchant_id,
  jsonb_build_object(
    'cashback_answer', answers.cashback_answer,
    'referral_answer', answers.referral_answer,
    'owner_confirmed', false
  )
from public.advertiser_answers answers
join public.merchants merchants on merchants.id = answers.merchant_id
where merchants.slug in ('finanzguru', '123-live', 'guiders', 'wondershare');
