-- Phase 4: direct referral records. Rule direct-v1 is the versioned pilot rule.
-- A newer version must be inserted. This rule is not edited in place.

create table public.attribution_rules (
  version text primary key,
  summary text not null,
  duration text not null,
  precedence text not null,
  referrer_requires_matched_purchase boolean not null,
  replace_before_purchase boolean not null,
  cross_device text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into public.attribution_rules (
  version, summary, duration, precedence,
  referrer_requires_matched_purchase, replace_before_purchase, cross_device, active
) values (
  'direct-v1',
  'Direct deal-link referral only. No second level and no cashback on the click.',
  'until_open_round_end',
  'last_eligible_click',
  true,
  true,
  'same_account',
  true
);

create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_user_id uuid not null references auth.users (id) on delete cascade,
  referred_user_id uuid not null references auth.users (id) on delete cascade,
  referral_code text not null,
  attribution_status text not null default 'active',
  attributed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint referrals_not_self check (referrer_user_id <> referred_user_id),
  constraint referrals_status_check check (attribution_status in ('active', 'closed')),
  constraint referrals_code_format check (referral_code ~ '^[a-z0-9]{10}$')
);

create unique index referrals_one_active_referrer
  on public.referrals (referred_user_id)
  where attribution_status = 'active';

create table public.referral_attributions (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.deals (id),
  referrer_user_id uuid not null references auth.users (id),
  buyer_user_id uuid not null references auth.users (id),
  source_click_id uuid,
  status text not null default 'active',
  rule_version text not null references public.attribution_rules (version),
  environment text not null,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  constraint referral_attributions_not_self check (referrer_user_id <> buyer_user_id),
  constraint referral_attributions_status_check check (status in ('active', 'replaced', 'expired')),
  constraint referral_attributions_environment_check check (environment in ('simulation', 'live'))
);

create unique index referral_attributions_one_active
  on public.referral_attributions (deal_id, buyer_user_id, environment)
  where status = 'active';

create table public.risk_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete set null,
  click_id uuid,
  transaction_id uuid,
  risk_type text not null,
  severity text not null,
  status text not null default 'open',
  metadata jsonb,
  created_at timestamptz not null default now(),
  constraint risk_events_severity_check check (severity in ('low', 'medium', 'high')),
  constraint risk_events_status_check check (status in ('open', 'closed'))
);

create or replace function public.record_account_referral(p_referral_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  referrer uuid;
  new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_referral_code is null or p_referral_code !~ '^[a-z0-9]{10}$' then
    raise exception 'invalid referral code';
  end if;

  select id into referrer
  from public.profiles
  where referral_code = p_referral_code;
  if referrer is null or referrer = auth.uid() then
    raise exception 'referral code not usable';
  end if;
  if exists (
    select 1 from public.referrals
    where referred_user_id = auth.uid() and attribution_status = 'active'
  ) then
    raise exception 'referral already recorded';
  end if;

  insert into public.referrals (referrer_user_id, referred_user_id, referral_code)
  values (referrer, auth.uid(), p_referral_code)
  returning id into new_id;
  return new_id;
end;
$$;

revoke all on function public.record_account_referral(text) from public, anon;
grant execute on function public.record_account_referral(text) to authenticated;

revoke all on table public.attribution_rules from public, anon, authenticated;
revoke all on table public.referrals from public, anon, authenticated;
revoke all on table public.referral_attributions from public, anon, authenticated;
revoke all on table public.risk_events from public, anon, authenticated;

grant select on table public.attribution_rules to authenticated;
grant select on table public.referrals to authenticated;
grant select on table public.referral_attributions to authenticated;
grant select on table public.risk_events to authenticated;

alter table public.attribution_rules enable row level security;
alter table public.referrals enable row level security;
alter table public.referral_attributions enable row level security;
alter table public.risk_events enable row level security;

create policy attribution_rules_read
on public.attribution_rules
for select
to authenticated
using (true);

create policy referrals_select_own
on public.referrals
for select
to authenticated
using (referrer_user_id = auth.uid() or referred_user_id = auth.uid() or public.is_admin());

create policy referral_attributions_select_own
on public.referral_attributions
for select
to authenticated
using (referrer_user_id = auth.uid() or buyer_user_id = auth.uid() or public.is_admin());

create policy risk_events_admin_select
on public.risk_events
for select
to authenticated
using (public.is_admin());
