-- One deal has one public offer mode. Cashback has no referral link.
-- Empfehlung adds the direct referral. Creator adds a campaign on top of that.

alter table public.deals
  add column offer_mode text not null default 'referral';

alter table public.deals
  add constraint deals_offer_mode_check
  check (offer_mode in ('cashback', 'referral', 'creator'));

grant select (offer_mode) on table public.deals to authenticated;

create or replace view public.public_deals
with (security_barrier = true, security_invoker = false) as
select
  d.id,
  d.slug,
  d.public_code,
  d.title,
  d.description,
  d.product_image_url,
  d.current_price_cents,
  d.currency,
  d.cashback_estimate_cents,
  d.cashback_estimate_label,
  d.published_at,
  m.name as merchant_name,
  c.name as category_name,
  d.offer_mode
from public.deals d
join public.merchants m on m.id = d.merchant_id and m.status = 'active'
left join public.deal_categories c on c.id = d.category_id
where d.status = 'published';

grant select on table public.public_deals to anon, authenticated;

drop function public.create_published_deal(uuid, text, text, text, text, bigint, text, text);

create function public.create_published_deal(
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
  if chosen_mode not in ('cashback', 'referral', 'creator') then
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

revoke all on function public.create_published_deal(uuid, text, text, text, text, bigint, text, text, text) from public, anon;
grant execute on function public.create_published_deal(uuid, text, text, text, text, bigint, text, text, text) to authenticated;

create or replace function public.set_deal_offer_mode(p_deal_id uuid, p_offer_mode text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_offer_mode not in ('cashback', 'referral', 'creator') then
    raise exception 'invalid offer mode';
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

revoke all on function public.set_deal_offer_mode(uuid, text) from public, anon;
grant execute on function public.set_deal_offer_mode(uuid, text) to authenticated;

drop function public.review_deal_submission(uuid, text, text, uuid, text, bigint, text);

create function public.review_deal_submission(
  p_submission_id uuid,
  p_decision text,
  p_comment text,
  p_merchant_id uuid default null,
  p_slug text default null,
  p_price_cents bigint default null,
  p_currency text default null,
  p_offer_mode text default 'referral'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  submission public.deal_submissions%rowtype;
  created_deal_id uuid;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_decision not in ('approved', 'rejected') then
    raise exception 'invalid decision';
  end if;
  if p_comment is not null and char_length(p_comment) > 500 then
    raise exception 'invalid comment';
  end if;

  select * into submission
  from public.deal_submissions
  where id = p_submission_id
  for update;
  if submission.id is null then
    raise exception 'submission not available';
  end if;
  if submission.submission_status <> 'pending' then
    raise exception 'submission already reviewed';
  end if;

  if p_decision = 'rejected' then
    update public.deal_submissions
    set submission_status = 'rejected',
        admin_comment = nullif(btrim(p_comment), ''),
        reviewed_at = now(),
        reviewed_by = auth.uid()
    where id = submission.id;
    insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
    values (auth.uid(), 'admin', 'submission_rejected', 'deal_submissions', submission.id, jsonb_build_object('comment_present', p_comment is not null));
    return null;
  end if;

  created_deal_id := public.create_published_deal(
    p_merchant_id,
    'allgemein',
    p_slug,
    submission.proposed_title,
    submission.proposed_description,
    coalesce(p_price_cents, submission.proposed_price_cents, 0),
    coalesce(p_currency, submission.currency, 'EUR'),
    null,
    coalesce(p_offer_mode, 'referral')
  );

  update public.deal_submissions
  set submission_status = 'approved',
      deal_id = created_deal_id,
      admin_comment = nullif(btrim(p_comment), ''),
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = submission.id;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (auth.uid(), 'admin', 'submission_approved', 'deal_submissions', submission.id, jsonb_build_object('deal_id', created_deal_id, 'offer_mode', coalesce(p_offer_mode, 'referral')));

  return created_deal_id;
end;
$$;

revoke all on function public.review_deal_submission(uuid, text, text, uuid, text, bigint, text, text) from public, anon;
grant execute on function public.review_deal_submission(uuid, text, text, uuid, text, bigint, text, text) to authenticated;

create or replace function public.guard_offer_mode_click()
returns trigger
language plpgsql
as $$
declare
  mode text;
begin
  select offer_mode into mode from public.deals where id = new.deal_id;
  if mode = 'cashback' then
    new.referrer_user_id := null;
    new.campaign_id := null;
  elsif mode = 'referral' then
    new.campaign_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists clicks_guard_offer_mode on public.clicks;
create trigger clicks_guard_offer_mode
before insert on public.clicks
for each row
execute function public.guard_offer_mode_click();

create or replace function public.guard_offer_mode_attribution()
returns trigger
language plpgsql
as $$
declare
  mode text;
begin
  select offer_mode into mode from public.deals where id = new.deal_id;
  if mode = 'cashback' then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists attributions_guard_offer_mode on public.referral_attributions;
create trigger attributions_guard_offer_mode
before insert on public.referral_attributions
for each row
execute function public.guard_offer_mode_attribution();

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

drop trigger if exists campaigns_guard_offer_mode on public.creator_campaigns;
create trigger campaigns_guard_offer_mode
before insert on public.creator_campaigns
for each row
execute function public.guard_offer_mode_campaign();
