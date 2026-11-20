-- Phase 3: reviewed deals and suggestions. Affiliate destinations stay off the public deal.

create or replace function public.is_safe_https_url(p_url text)
returns boolean
language sql
immutable
as $$
  select p_url is not null
    and char_length(p_url) between 12 and 1000
    and p_url ~ '^https://'
    and p_url !~ '[[:space:]<>"\\@#]'
$$;

revoke all on function public.is_safe_https_url(text) from public, anon, authenticated;
grant execute on function public.is_safe_https_url(text) to authenticated;

create table public.deals (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  description text not null,
  product_image_url text,
  merchant_id uuid not null references public.merchants (id),
  category_id uuid references public.deal_categories (id),
  original_price_cents bigint,
  current_price_cents bigint not null,
  currency char(3) not null,
  cashback_estimate_cents bigint,
  cashback_estimate_label text,
  status text not null default 'draft',
  public_code text not null unique,
  created_by uuid not null references auth.users (id),
  approved_by uuid references auth.users (id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint deals_slug_format check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint deals_public_code_format check (public_code ~ '^[a-z0-9]{10}$'),
  constraint deals_currency_format check (currency ~ '^[A-Z]{3}$'),
  constraint deals_status_check check (status in ('draft', 'published', 'archived')),
  constraint deals_price_nonnegative check (
    current_price_cents >= 0
    and (original_price_cents is null or original_price_cents >= 0)
  ),
  constraint deals_estimate_nonnegative check (
    cashback_estimate_cents is null or cashback_estimate_cents >= 0
  ),
  constraint deals_estimate_label check (
    cashback_estimate_cents is null or nullif(btrim(cashback_estimate_label), '') is not null
  ),
  constraint deals_image_url check (
    product_image_url is null or public.is_safe_https_url(product_image_url)
  )
);

create table public.deal_submissions (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid not null references auth.users (id) on delete cascade,
  deal_id uuid references public.deals (id),
  proposed_title text not null,
  proposed_description text not null,
  proposed_url text not null,
  proposed_price_cents bigint,
  currency char(3),
  submission_status text not null default 'pending',
  admin_comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id),
  constraint deal_submissions_status_check check (submission_status in ('pending', 'approved', 'rejected')),
  constraint deal_submissions_title_length check (char_length(btrim(proposed_title)) between 3 and 140),
  constraint deal_submissions_description_length check (char_length(proposed_description) between 10 and 4000),
  constraint deal_submissions_url check (public.is_safe_https_url(proposed_url)),
  constraint deal_submissions_price check (proposed_price_cents is null or proposed_price_cents >= 0),
  constraint deal_submissions_currency check (currency is null or currency ~ '^[A-Z]{3}$'),
  constraint deal_submissions_comment_length check (admin_comment is null or char_length(admin_comment) <= 500)
);

create trigger deals_set_updated_at
before update on public.deals
for each row execute function public.set_updated_at();

create trigger deal_submissions_set_updated_at
before update on public.deal_submissions
for each row execute function public.set_updated_at();

create or replace function public.protect_deal_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is null then
      raise exception 'authentication required';
    end if;
    new.submitted_by := auth.uid();
    new.submission_status := 'pending';
    new.deal_id := null;
    new.admin_comment := null;
    new.reviewed_at := null;
    new.reviewed_by := null;
    return new;
  end if;

  if public.is_admin() then
    return new;
  end if;

  if old.submitted_by is distinct from auth.uid() or old.submission_status <> 'pending' then
    raise exception 'submission cannot be changed';
  end if;

  if new.submitted_by is distinct from old.submitted_by
     or new.submission_status is distinct from old.submission_status
     or new.deal_id is distinct from old.deal_id
     or new.admin_comment is distinct from old.admin_comment
     or new.reviewed_at is distinct from old.reviewed_at
     or new.reviewed_by is distinct from old.reviewed_by
     or new.created_at is distinct from old.created_at then
    raise exception 'submission review fields are immutable';
  end if;

  return new;
end;
$$;

create trigger deal_submissions_protect
before insert or update on public.deal_submissions
for each row execute function public.protect_deal_submission();

revoke all on function public.protect_deal_submission() from public, anon;
grant execute on function public.protect_deal_submission() to authenticated;

create or replace function public.random_public_code()
returns text
language sql
volatile
as $$
  select lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
$$;

revoke all on function public.random_public_code() from public, anon, authenticated;

create or replace function public.create_merchant(
  p_name text,
  p_slug text,
  p_website_url text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id uuid;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if nullif(btrim(p_name), '') is null or char_length(btrim(p_name)) > 120 then
    raise exception 'invalid merchant name';
  end if;
  if p_slug is null or p_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
    raise exception 'invalid merchant slug';
  end if;
  if not public.is_safe_https_url(p_website_url) then
    raise exception 'invalid merchant url';
  end if;

  insert into public.merchants (name, slug, website_url, status)
  values (btrim(p_name), p_slug, p_website_url, 'active')
  returning id into new_id;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (auth.uid(), 'admin', 'merchant_created', 'merchants', new_id, jsonb_build_object('slug', p_slug));

  return new_id;
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
  p_image_url text default null
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
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
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
        current_price_cents, currency, status, public_code, created_by, approved_by, published_at
      ) values (
        p_slug, btrim(p_title), p_description, p_image_url, p_merchant_id, category_id,
        p_price_cents, p_currency, 'published', code, auth.uid(), auth.uid(), now()
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
  values (auth.uid(), 'admin', 'deal_published', 'deals', new_id, 'simulation', jsonb_build_object('slug', p_slug));

  return new_id;
end;
$$;

create or replace function public.review_deal_submission(
  p_submission_id uuid,
  p_decision text,
  p_comment text,
  p_merchant_id uuid default null,
  p_slug text default null,
  p_price_cents bigint default null,
  p_currency text default null
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
    null
  );

  update public.deal_submissions
  set submission_status = 'approved',
      deal_id = created_deal_id,
      admin_comment = nullif(btrim(p_comment), ''),
      reviewed_at = now(),
      reviewed_by = auth.uid()
  where id = submission.id;

  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (auth.uid(), 'admin', 'submission_approved', 'deal_submissions', submission.id, jsonb_build_object('deal_id', created_deal_id));

  return created_deal_id;
end;
$$;

revoke all on function public.create_merchant(text, text, text) from public, anon;
revoke all on function public.create_published_deal(uuid, text, text, text, text, bigint, text, text) from public, anon;
revoke all on function public.review_deal_submission(uuid, text, text, uuid, text, bigint, text) from public, anon;
grant execute on function public.create_merchant(text, text, text) to authenticated;
grant execute on function public.create_published_deal(uuid, text, text, text, text, bigint, text, text) to authenticated;
grant execute on function public.review_deal_submission(uuid, text, text, uuid, text, bigint, text) to authenticated;

create view public.public_deals
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
  c.name as category_name
from public.deals d
join public.merchants m on m.id = d.merchant_id and m.status = 'active'
left join public.deal_categories c on c.id = d.category_id
where d.status = 'published';

revoke all on table public.deals from public, anon, authenticated;
revoke all on table public.deal_submissions from public, anon, authenticated;
revoke all on table public.public_deals from public, anon, authenticated;

grant select (
  id, slug, title, description, product_image_url, merchant_id, category_id,
  original_price_cents, current_price_cents, currency, cashback_estimate_cents,
  cashback_estimate_label, status, public_code, created_by, approved_by,
  published_at, created_at, updated_at
) on table public.deals to authenticated;

grant select on table public.merchants to authenticated;
grant select on table public.public_deals to anon, authenticated;

grant select (
  id, submitted_by, deal_id, proposed_title, proposed_description, proposed_url,
  proposed_price_cents, currency, submission_status, admin_comment, created_at,
  updated_at, reviewed_at, reviewed_by
) on table public.deal_submissions to authenticated;

grant insert (
  proposed_title, proposed_description, proposed_url, proposed_price_cents, currency
) on table public.deal_submissions to authenticated;

grant update (
  proposed_title, proposed_description, proposed_url, proposed_price_cents, currency
) on table public.deal_submissions to authenticated;

alter table public.deals enable row level security;
alter table public.deal_submissions enable row level security;

create policy deals_select_published_or_admin
on public.deals
for select
to authenticated
using (status = 'published' or public.is_admin());

create policy deal_submissions_select_own_or_admin
on public.deal_submissions
for select
to authenticated
using (submitted_by = auth.uid() or public.is_admin());

create policy deal_submissions_insert_own
on public.deal_submissions
for insert
to authenticated
with check (submitted_by = auth.uid() and submission_status = 'pending');

create policy deal_submissions_update_own_pending
on public.deal_submissions
for update
to authenticated
using (submitted_by = auth.uid() and submission_status = 'pending')
with check (submitted_by = auth.uid() and submission_status = 'pending');
