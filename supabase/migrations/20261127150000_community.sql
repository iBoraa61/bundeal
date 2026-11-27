-- Phase L4: votes, comments, reports and favorites. No payout path.

create table public.deal_votes (
  deal_id uuid not null references public.deals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  direction smallint not null,
  created_at timestamptz not null default now(),
  primary key (deal_id, user_id),
  constraint deal_votes_direction_check check (direction in (-1, 1))
);

create table public.deal_comments (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  status text not null default 'visible',
  created_at timestamptz not null default now(),
  constraint deal_comments_body_check check (char_length(btrim(body)) between 2 and 400),
  constraint deal_comments_status_check check (status in ('visible', 'hidden', 'reported'))
);

create table public.deal_comment_reports (
  comment_id uuid not null references public.deal_comments (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);

create table public.deal_favorites (
  deal_id uuid not null references public.deals (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (deal_id, user_id)
);

alter table public.deal_votes enable row level security;
alter table public.deal_comments enable row level security;
alter table public.deal_comment_reports enable row level security;
alter table public.deal_favorites enable row level security;

revoke all on table public.deal_votes from public, anon, authenticated;
revoke all on table public.deal_comments from public, anon, authenticated;
revoke all on table public.deal_comment_reports from public, anon, authenticated;
revoke all on table public.deal_favorites from public, anon, authenticated;

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
  coalesce((select count(*)::bigint from public.deal_comments comments where comments.deal_id = d.id and comments.status = 'visible'), 0) as comment_count
from public.deals d
join public.merchants m on m.id = d.merchant_id and m.status = 'active'
left join public.deal_categories c on c.id = d.category_id
where d.status = 'published';

grant select on table public.public_deals to anon, authenticated;

create function public.published_deal_id(p_slug text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id from public.deals where slug = p_slug and status = 'published';
$$;

revoke all on function public.published_deal_id(text) from public, anon, authenticated;

create function public.cast_deal_vote(p_slug text, p_direction smallint)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  deal uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  if p_direction is not null and p_direction not in (-1, 0, 1) then
    raise exception 'invalid vote';
  end if;
  deal := public.published_deal_id(p_slug);
  if deal is null then
    raise exception 'deal not available';
  end if;
  if coalesce(p_direction, 0) = 0 then
    delete from public.deal_votes where deal_id = deal and user_id = auth.uid();
    return;
  end if;
  insert into public.deal_votes (deal_id, user_id, direction)
  values (deal, auth.uid(), p_direction)
  on conflict (deal_id, user_id) do update set direction = excluded.direction, created_at = now();
end;
$$;

revoke all on function public.cast_deal_vote(text, smallint) from public, anon;
grant execute on function public.cast_deal_vote(text, smallint) to authenticated;

create function public.save_deal_comment(p_slug text, p_body text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  deal uuid;
  new_id uuid;
  clean text;
begin
  if auth.uid() is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  clean := btrim(coalesce(p_body, ''));
  if char_length(clean) < 2 or char_length(clean) > 400 or clean ~ '[<>]' then
    raise exception 'invalid comment';
  end if;
  deal := public.published_deal_id(p_slug);
  if deal is null then
    raise exception 'deal not available';
  end if;
  if (
    select count(*) from public.deal_comments
    where user_id = auth.uid() and created_at > now() - interval '1 hour'
  ) >= 10 or (
    select count(*) from public.deal_comments
    where user_id = auth.uid() and deal_id = deal and status <> 'hidden'
  ) >= 5 then
    raise exception 'comment limit' using errcode = '42501';
  end if;
  insert into public.deal_comments (deal_id, user_id, body)
  values (deal, auth.uid(), clean)
  returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.save_deal_comment(text, text) from public, anon;
grant execute on function public.save_deal_comment(text, text) to authenticated;

create function public.report_deal_comment(p_comment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  select user_id into owner from public.deal_comments where id = p_comment_id and status <> 'hidden';
  if owner is null then
    raise exception 'comment not available';
  end if;
  if owner = auth.uid() then
    raise exception 'own comment' using errcode = '42501';
  end if;
  insert into public.deal_comment_reports (comment_id, user_id)
  values (p_comment_id, auth.uid())
  on conflict do nothing;
  update public.deal_comments set status = 'reported' where id = p_comment_id and status = 'visible';
end;
$$;

revoke all on function public.report_deal_comment(uuid) from public, anon;
grant execute on function public.report_deal_comment(uuid) to authenticated;

create function public.set_deal_favorite(p_slug text, p_saved boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  deal uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;
  deal := public.published_deal_id(p_slug);
  if deal is null then
    raise exception 'deal not available';
  end if;
  if coalesce(p_saved, false) then
    insert into public.deal_favorites (deal_id, user_id)
    values (deal, auth.uid())
    on conflict do nothing;
  else
    delete from public.deal_favorites where deal_id = deal and user_id = auth.uid();
  end if;
end;
$$;

revoke all on function public.set_deal_favorite(text, boolean) from public, anon;
grant execute on function public.set_deal_favorite(text, boolean) to authenticated;

create function public.deal_community(p_slug text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  deal uuid;
  score bigint;
  mine smallint;
  saved boolean;
  comments jsonb;
begin
  deal := public.published_deal_id(p_slug);
  if deal is null then
    return null;
  end if;
  select coalesce(sum(direction), 0)::bigint into score from public.deal_votes where deal_id = deal;
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
    'my_vote', mine,
    'favorite', saved,
    'comments', comments
  );
end;
$$;

revoke all on function public.deal_community(text) from public;
grant execute on function public.deal_community(text) to anon, authenticated;

create function public.moderate_deal_comment(p_comment_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_status not in ('visible', 'hidden') then
    raise exception 'invalid comment status';
  end if;
  update public.deal_comments set status = p_status where id = p_comment_id and status <> 'hidden' or (p_status = 'visible' and id = p_comment_id);
  if not found then
    raise exception 'comment not available';
  end if;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (auth.uid(), 'admin', 'comment_moderated', 'deal_comments', p_comment_id, jsonb_build_object('status', p_status));
end;
$$;

revoke all on function public.moderate_deal_comment(uuid, text) from public, anon;
grant execute on function public.moderate_deal_comment(uuid, text) to authenticated;

create function public.community_queue()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', rows.id,
    'body', rows.body,
    'status', rows.status,
    'author', rows.author,
    'deal_title', rows.deal_title,
    'created_at', rows.created_at
  ) order by rows.created_at desc), '[]'::jsonb)
  from (
    select
      comments.id,
      comments.body,
      comments.status,
      comments.created_at,
      deals.title as deal_title,
      coalesce(nullif(profiles.display_name, ''), nullif(profiles.username, ''), 'Mitglied') as author
    from public.deal_comments as comments
    join public.deals on deals.id = comments.deal_id
    left join public.profiles on profiles.id = comments.user_id
    where public.is_admin() and comments.status in ('reported', 'hidden')
    order by comments.created_at desc
    limit 30
  ) as rows;
$$;

revoke all on function public.community_queue() from public, anon;
grant execute on function public.community_queue() to authenticated;
