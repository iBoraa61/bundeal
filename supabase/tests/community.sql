-- Phase L4: a vote, a comment and a report stay on the test deal and roll back.

begin;

do $$
declare
  admin_id uuid := gen_random_uuid();
  member_id uuid := gen_random_uuid();
  other_id uuid := gen_random_uuid();
  merchant uuid;
  comment_id uuid;
  community jsonb;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values
    ('00000000-0000-0000-0000-000000000000', admin_id, 'authenticated', 'authenticated', 'l4-admin@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', member_id, 'authenticated', 'authenticated', 'l4-member@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', ''),
    ('00000000-0000-0000-0000-000000000000', other_id, 'authenticated', 'authenticated', 'l4-other@example.com', '', now(), '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  execute 'set local role authenticated';

  merchant := public.create_merchant('L4 Haendler', 'l4-haendler', 'https://example.com');
  perform public.set_merchant_capabilities(merchant, true, false, false, false, false, false, null);
  perform public.create_published_deal(merchant, 'allgemein', 'l4-deal', 'L4 Angebot', 'Ein ausreichend langer Beschreibungstext.', 1000, 'EUR', null, 'listing', null);

  perform set_config('request.jwt.claims', json_build_object('sub', member_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', member_id::text, true);
  perform public.cast_deal_vote('l4-deal', 1::smallint);
  perform public.cast_deal_vote('l4-deal', 1::smallint);
  community := public.deal_community('l4-deal');
  if (community ->> 'temperature')::int <> 1 or (community ->> 'my_vote')::int <> 1 then
    raise exception 'vote was not stored';
  end if;
  perform public.cast_deal_vote('l4-deal', -1::smallint);
  comment_id := public.save_deal_comment('l4-deal', 'Ein kurzer Hinweis.');
  perform public.set_deal_favorite('l4-deal', true);
  begin
    perform public.save_deal_comment('l4-deal', 'x');
    raise exception 'short comment was stored';
  exception
    when others then
      if sqlerrm <> 'invalid comment' then
        raise;
      end if;
  end;
  begin
    perform public.report_deal_comment(comment_id);
    raise exception 'author reported the own comment';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'own comment' then
        raise;
      end if;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', other_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', other_id::text, true);
  perform public.report_deal_comment(comment_id);
  community := public.deal_community('l4-deal');
  if community -> 'comments' <> '[]'::jsonb or (community ->> 'temperature')::int <> -1 then
    raise exception 'reported comment stayed public or the vote was lost';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', admin_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform public.moderate_deal_comment(comment_id, 'visible');
  community := public.deal_community('l4-deal');
  if community -> 'comments' -> 0 ->> 'body' <> 'Ein kurzer Hinweis.' then
    raise exception 'restored comment was missing';
  end if;
  perform public.moderate_deal_comment(comment_id, 'hidden');
  community := public.deal_community('l4-deal');
  if community -> 'comments' <> '[]'::jsonb then
    raise exception 'hidden comment stayed public';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', member_id::text, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', member_id::text, true);
  begin
    perform public.moderate_deal_comment(comment_id, 'visible');
    raise exception 'member moderated a comment';
  exception
    when insufficient_privilege then
      if sqlerrm <> 'admin required' then
        raise;
      end if;
  end;

  execute 'reset role';
  if (select temperature_score from public.public_deals where slug = 'l4-deal') <> -1 then
    raise exception 'public temperature was wrong';
  end if;
  if (select comment_count from public.public_deals where slug = 'l4-deal') <> 0 then
    raise exception 'hidden comment was counted';
  end if;
end;
$$;

rollback;
