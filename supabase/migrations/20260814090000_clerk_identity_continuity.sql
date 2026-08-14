begin;

-- Preserve the existing rec.me profile ID while Clerk moves from its
-- development instance to production. Imported production users carry their
-- prior profile ID in a signed canonical_user_id claim; users created after
-- cutover continue to use their Clerk subject unchanged.

create or replace function app.current_user_id()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif(
    coalesce(
      nullif(auth.jwt() ->> 'canonical_user_id', ''),
      nullif(current_setting('request.jwt.claim.canonical_user_id', true), ''),
      nullif(auth.jwt() ->> 'sub', ''),
      nullif(current_setting('request.jwt.claim.sub', true), '')
    ),
    ''
  )
$$;

comment on function app.current_user_id() is
  'Returns the stable rec.me profile ID from the signed Clerk canonical_user_id claim, falling back to the Clerk subject for legacy and newly created users.';

create table if not exists public.clerk_identity_mappings (
  clerk_user_id text primary key,
  profile_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(clerk_user_id)) > 0),
  check (length(btrim(profile_id)) > 0)
);

alter table public.clerk_identity_mappings enable row level security;

revoke all on table public.clerk_identity_mappings from public, anon, authenticated;
grant select, insert, update, delete on table public.clerk_identity_mappings to service_role;

insert into public.clerk_identity_mappings (clerk_user_id, profile_id)
select profile.id, profile.id
from public.profiles profile
on conflict (clerk_user_id) do update
set profile_id = excluded.profile_id,
    updated_at = now();

comment on table public.clerk_identity_mappings is
  'Private service-role mapping from a Clerk environment-specific user ID to the stable rec.me profile ID. Used to resolve sparse user.deleted webhooks without rewriting user-owned data.';

commit;
