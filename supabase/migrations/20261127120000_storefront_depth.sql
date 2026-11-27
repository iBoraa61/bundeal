-- Phase L2: public cards can show a previous shop price. No new payout path.

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
  d.offer_mode,
  d.original_price_cents,
  c.slug as category_slug,
  m.slug as merchant_slug
from public.deals d
join public.merchants m on m.id = d.merchant_id and m.status = 'active'
left join public.deal_categories c on c.id = d.category_id
where d.status = 'published';

grant select on table public.public_deals to anon, authenticated;

drop function public.create_published_deal(uuid, text, text, text, text, bigint, text, text, text);

create function public.create_published_deal(
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

grant execute on function public.create_published_deal(uuid, text, text, text, text, bigint, text, text, text, bigint) to authenticated;
