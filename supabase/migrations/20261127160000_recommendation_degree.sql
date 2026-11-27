-- Empfehlungsgrad counts members who recommend a deal. Downvotes stay stored, but they are not the public degree.

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
  m.slug as merchant_slug,
  coalesce((select sum(v.direction)::bigint from public.deal_votes v where v.deal_id = d.id), 0) as temperature_score,
  coalesce((select count(*)::bigint from public.deal_comments comments where comments.deal_id = d.id and comments.status = 'visible'), 0) as comment_count,
  coalesce((select count(*)::bigint from public.deal_votes v where v.deal_id = d.id and v.direction = 1), 0) as recommendation_count
from public.deals d
join public.merchants m on m.id = d.merchant_id and m.status = 'active'
left join public.deal_categories c on c.id = d.category_id
where d.status = 'published';

create or replace function public.deal_community(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  deal uuid;
  score bigint;
  recommends bigint;
  mine smallint;
  saved boolean;
  comments jsonb;
begin
  deal := public.published_deal_id(p_slug);
  if deal is null then
    return null;
  end if;
  select coalesce(sum(direction), 0)::bigint into score from public.deal_votes where deal_id = deal;
  select count(*)::bigint into recommends from public.deal_votes where deal_id = deal and direction = 1;
  select direction into mine from public.deal_votes where deal_id = deal and user_id = auth.uid();
  select exists (
    select 1 from public.deal_favorites where deal_id = deal and user_id = auth.uid()
  ) into saved;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rows.id,
    'body', rows.body,
    'created_at', rows.created_at,
    'author', rows.author,
    'mine', rows.mine
  ) order by rows.created_at), '[]'::jsonb)
  into comments
  from (
    select
      comments.id,
      comments.body,
      comments.created_at,
      coalesce(nullif(profiles.display_name, ''), nullif(profiles.username, ''), 'Mitglied') as author,
      comments.user_id = auth.uid() as mine
    from public.deal_comments as comments
    left join public.profiles on profiles.id = comments.user_id
    where comments.deal_id = deal and comments.status = 'visible'
    order by comments.created_at
    limit 50
  ) as rows;
  return jsonb_build_object(
    'temperature', score,
    'recommendations', recommends,
    'my_vote', mine,
    'favorite', saved,
    'comments', comments
  );
end;
$$;
