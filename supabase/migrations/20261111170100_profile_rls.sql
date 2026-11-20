-- Phase 2 reasserts that browser roles cannot write roles or identity columns.
-- Existing select/update policies from the foundation stay in place.

revoke all on table public.profiles from public, anon, authenticated;
revoke all on table public.user_roles from public, anon, authenticated;

grant select (
  id, username, display_name, referral_code, avatar_url, created_at, updated_at
) on table public.profiles to authenticated;

grant update (
  username, display_name, avatar_url
) on table public.profiles to authenticated;

grant select on table public.user_roles to authenticated;
