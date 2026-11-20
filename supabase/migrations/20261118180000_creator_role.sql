-- Only an account with the creator role may start a campaign.
-- An admin assigns or removes that role. The base user role stays.

alter table public.user_roles drop constraint user_roles_role_check;

alter table public.user_roles
  add constraint user_roles_role_check check (role in ('user', 'admin', 'creator'));

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
  if not exists (
    select 1 from public.user_roles
    where user_id = creator and role = 'creator'
  ) then
    raise exception 'creator role required' using errcode = '42501';
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

create or replace function public.set_creator_role(p_username text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_variable
declare
  target uuid;
begin
  if not public.is_admin() then
    raise exception 'admin required' using errcode = '42501';
  end if;
  if p_username is null or p_username !~ '^[a-z0-9_]{3,30}$' or p_enabled is null then
    raise exception 'user not found';
  end if;
  select id into target from public.profiles where username = p_username;
  if target is null then
    raise exception 'user not found';
  end if;
  if p_enabled then
    insert into public.user_roles (user_id, role)
    values (target, 'creator')
    on conflict do nothing;
  else
    delete from public.user_roles
    where user_id = target and role = 'creator';
  end if;
  insert into public.audit_logs (actor_user_id, actor_type, action, target_table, target_id, metadata)
  values (
    auth.uid(), 'admin', 'creator_role_set', 'user_roles', target,
    jsonb_build_object('username', p_username, 'enabled', p_enabled)
  );
end;
$$;

revoke all on function public.set_creator_role(text, boolean) from public, anon;
grant execute on function public.set_creator_role(text, boolean) to authenticated;
