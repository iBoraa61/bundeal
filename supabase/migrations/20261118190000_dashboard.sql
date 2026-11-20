-- Creator access is an application. Signup metadata cannot grant the role.
-- The account snapshot shows only the caller's cashback. It does not pay anyone.

create table public.creator_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  channel_note text not null,
  status text not null default 'pending',
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id),
  constraint creator_applications_status_check check (status in ('pending', 'approved', 'rejected')),
  constraint creator_applications_channel_check check (char_length(btrim(channel_note)) between 8 and 160)
);

create unique index creator_applications_one_pending
  on public.creator_applications (user_id)
  where status = 'pending';

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_code text;
  profile_created boolean := false;
  desired_username text;
  desired_display_name text;
  request_channel text;
  conflict_name text;
begin
  desired_username := nullif(lower(btrim(coalesce(new.raw_user_meta_data ->> 'username', ''))), '');
  desired_display_name := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'display_name', '')), '');
  request_channel := nullif(btrim(coalesce(new.raw_user_meta_data ->> 'creator_request', '')), '');

  if desired_username is not null and desired_username !~ '^[a-z0-9_]{3,30}$' then
    raise exception 'invalid username';
  end if;
  if desired_display_name is not null and char_length(desired_display_name) > 80 then
    raise exception 'invalid display name';
  end if;
  if request_channel is not null and char_length(request_channel) not between 8 and 160 then
    raise exception 'invalid creator request';
  end if;

  while not profile_created loop
    new_code := lower(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    begin
      insert into public.profiles (id, username, display_name, referral_code)
      values (new.id, desired_username, desired_display_name, new_code);
      profile_created := true;
    exception
      when unique_violation then
        get stacked diagnostics conflict_name = constraint_name;
        if conflict_name = 'profiles_referral_code_key' then
          profile_created := false;
        else
          raise;
        end if;
    end;
  end loop;

  insert into public.user_roles (user_id, role)
  values (new.id, 'user');

  if request_channel is not null then
    insert into public.creator_applications (user_id, channel_note)
    values (new.id, request_channel);
  end if;

  return new;
end;
$$;

create or replace function public.request_creator_role(p_channel text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  channel text := nullif(btrim(coalesce(p_channel, '')), '');
begin
  if actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if exists (select 1 from public.user_roles where user_id = actor and role = 'creator') then
    raise exception 'already creator';
  end if;
  if channel is null or char_length(channel) not between 8 and 160 then
    raise exception 'invalid creator request';
  end if;
  if exists (
    select 1 from public.creator_applications
    where user_id = actor and status = 'pending'
  ) then
    raise exception 'application pending';
  end if;
  insert into public.creator_applications (user_id, channel_note)
  values (actor, channel);
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id)
  values (actor, 'user', 'creator_application_requested', 'creator_applications', actor);
end;
$$;

create or replace function public.review_creator_application(p_application_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  applicant uuid;
  current_status text;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_approve is null then
    raise exception 'application not found';
  end if;
  select user_id, status into applicant, current_status
  from public.creator_applications
  where id = p_application_id;
  if applicant is null or current_status is distinct from 'pending' then
    raise exception 'application not found';
  end if;
  if p_approve then
    insert into public.user_roles (user_id, role)
    values (applicant, 'creator')
    on conflict do nothing;
    update public.creator_applications
    set status = 'approved', reviewed_at = now(), reviewed_by = auth.uid()
    where id = p_application_id;
  else
    update public.creator_applications
    set status = 'rejected', reviewed_at = now(), reviewed_by = auth.uid()
    where id = p_application_id;
  end if;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin', 'creator_application_reviewed', 'creator_applications', p_application_id,
    jsonb_build_object('approved', p_approve)
  );
end;
$$;

create or replace function public.creator_application_snapshot()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object('status', status, 'channel_note', channel_note)
  from public.creator_applications
  where user_id = auth.uid()
  order by created_at desc
  limit 1;
$$;

create or replace function public.creator_application_admin_snapshot()
returns table (
  id uuid,
  username text,
  display_name text,
  channel_note text,
  status text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  return query
  select
    applications.id,
    coalesce(profiles.username, 'nutzer'),
    coalesce(profiles.display_name, ''),
    applications.channel_note,
    applications.status,
    applications.created_at
  from public.creator_applications as applications
  join public.profiles on profiles.id = applications.user_id
  order by (applications.status = 'pending') desc, applications.created_at desc
  limit 30;
end;
$$;

create or replace function public.cashback_account_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
begin
  if actor is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'balances', coalesce((
      select jsonb_agg(jsonb_build_object(
        'environment', accounts.environment,
        'pending_cents', accounts.pending_balance_cents,
        'available_cents', accounts.available_balance_cents
      ))
      from public.cashback_accounts as accounts
      where accounts.user_id = actor
    ), '[]'::jsonb),
    'shares', coalesce((
      select jsonb_agg(jsonb_build_object(
        'environment', grouped.environment,
        'bucket', grouped.bucket,
        'pending_cents', grouped.pending_cents,
        'available_cents', grouped.available_cents
      ))
      from (
        select
          ledger.environment,
          ledger.bucket,
          coalesce(sum(ledger.amount_cents) filter (where ledger.status = 'pending'), 0)::bigint as pending_cents,
          coalesce(sum(ledger.amount_cents) filter (where ledger.status = 'available'), 0)::bigint as available_cents
        from public.cashback_ledger as ledger
        where ledger.user_id = actor
        group by ledger.environment, ledger.bucket
      ) as grouped
    ), '[]'::jsonb),
    'referral_count', (
      select count(*)
      from public.referrals
      where referrer_user_id = actor and attribution_status = 'active'
    ),
    'submissions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'title', rows.proposed_title,
        'status', rows.submission_status
      ) order by rows.created_at desc)
      from (
        select proposed_title, submission_status, created_at
        from public.deal_submissions
        where submitted_by = actor
        order by created_at desc
        limit 20
      ) as rows
    ), '[]'::jsonb),
    'history', coalesce((
      select jsonb_agg(entries.row_json order by entries.occurred_at desc)
      from (
        select occurred_at, row_json
        from (
          select
            tx.transaction_date as occurred_at,
            jsonb_build_object(
              'kind', 'purchase',
              'deal_title', offer.title,
              'environment', tx.environment,
              'transaction_status', tx.transaction_status,
              'cashback_status', case
                when coalesce(led.reversed, false) and coalesce(led.net_cents, 0) = 0 and coalesce(led.credited_cents, 0) > 0 then 'reversed'
                when coalesce(led.pending_cents, 0) > 0 then 'pending'
                when coalesce(led.net_cents, 0) > 0 then 'available'
                when tx.transaction_status = 'pending' then 'open'
                when tx.transaction_status = 'rejected' then 'rejected'
                else 'none'
              end,
              'amount_cents', case
                when coalesce(led.reversed, false) and coalesce(led.net_cents, 0) = 0 and coalesce(led.credited_cents, 0) > 0 then led.credited_cents
                when coalesce(led.net_cents, 0) > 0 then led.net_cents
                else null
              end
            ) as row_json
          from public.transactions as tx
          join public.deals as offer on offer.id = tx.deal_id
          left join lateral (
            select
              coalesce(sum(ledger.amount_cents), 0)::bigint as net_cents,
              coalesce(sum(ledger.amount_cents) filter (where ledger.entry_type = 'credit' and ledger.amount_cents > 0), 0)::bigint as credited_cents,
              coalesce(sum(ledger.amount_cents) filter (where ledger.status = 'pending'), 0)::bigint as pending_cents,
              bool_or(ledger.entry_type = 'reversal') as reversed
            from public.cashback_ledger as ledger
            where ledger.user_id = actor
              and ledger.transaction_id = tx.id
              and ledger.bucket = 'basic_cashback'
          ) as led on true
          where tx.user_id = actor
          union all
          select
            grouped.occurred_at,
            jsonb_build_object(
              'kind', case grouped.bucket when 'referral_bonus' then 'referral' else 'creator' end,
              'deal_title', coalesce(offer.title, ''),
              'environment', grouped.environment,
              'transaction_status', coalesce(tx.transaction_status, ''),
              'cashback_status', case
                when grouped.reversed and grouped.net_cents = 0 and grouped.credited_cents > 0 then 'reversed'
                when grouped.pending_cents > 0 then 'pending'
                when grouped.net_cents > 0 then 'available'
                else 'none'
              end,
              'amount_cents', case
                when grouped.reversed and grouped.net_cents = 0 and grouped.credited_cents > 0 then grouped.credited_cents
                when grouped.net_cents > 0 then grouped.net_cents
                else null
              end
            )
          from (
            select
              ledger.transaction_id,
              ledger.bucket,
              ledger.environment,
              coalesce(sum(ledger.amount_cents), 0)::bigint as net_cents,
              coalesce(sum(ledger.amount_cents) filter (where ledger.entry_type = 'credit' and ledger.amount_cents > 0), 0)::bigint as credited_cents,
              coalesce(sum(ledger.amount_cents) filter (where ledger.status = 'pending'), 0)::bigint as pending_cents,
              bool_or(ledger.entry_type = 'reversal') as reversed,
              max(ledger.created_at) as occurred_at
            from public.cashback_ledger as ledger
            where ledger.user_id = actor
              and ledger.bucket in ('referral_bonus', 'creator_share')
            group by ledger.transaction_id, ledger.bucket, ledger.environment
          ) as grouped
          left join public.transactions as tx on tx.id = grouped.transaction_id
          left join public.deals as offer on offer.id = tx.deal_id
        ) as combined
        order by occurred_at desc
        limit 40
      ) as entries
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.request_creator_role(text) from public, anon;
revoke all on function public.review_creator_application(uuid, boolean) from public, anon;
revoke all on function public.creator_application_snapshot() from public, anon;
revoke all on function public.creator_application_admin_snapshot() from public, anon;
revoke all on function public.cashback_account_snapshot() from public, anon;

grant execute on function public.request_creator_role(text) to authenticated;
grant execute on function public.review_creator_application(uuid, boolean) to authenticated;
grant execute on function public.creator_application_snapshot() to authenticated;
grant execute on function public.creator_application_admin_snapshot() to authenticated;
grant execute on function public.cashback_account_snapshot() to authenticated;

revoke all on table public.creator_applications from public, anon, authenticated;
grant select on table public.creator_applications to authenticated;

alter table public.creator_applications enable row level security;

create policy creator_applications_read_own
on public.creator_applications for select to authenticated
using (user_id = auth.uid() or public.is_admin());
