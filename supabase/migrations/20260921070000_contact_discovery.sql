begin;
-- REC-560: No address books or contact edges are retained. Only consenting
-- members' verified identifiers are indexed, using a database-private HMAC key.
create table app.contact_discovery_key (
  singleton boolean primary key default true check (singleton),
  secret bytea not null default extensions.gen_random_bytes(32)
);
insert into app.contact_discovery_key default values;
create table app.contact_discovery_settings (
  user_id text primary key references public.profiles(id) on delete cascade,
  enabled boolean not null default false,
  consent_version integer not null default 1 check (consent_version = 1),
  updated_at timestamptz not null default now()
);
create table app.contact_discovery_identity_state (
  clerk_user_id text primary key,
  user_id text not null references public.profiles(id) on delete cascade,
  identity_updated_at timestamptz not null
);
create table app.contact_discovery_identifiers (
  clerk_user_id text not null references app.contact_discovery_identity_state(clerk_user_id) on delete cascade,
  token bytea not null,
  primary key (clerk_user_id, token)
);
create index contact_discovery_token_idx on app.contact_discovery_identifiers(token);
create table app.contact_discovery_usage (
  user_id text primary key references public.profiles(id) on delete cascade,
  window_start timestamptz not null,
  requests integer not null,
  identifiers integer not null
);
alter table app.contact_discovery_key enable row level security;
alter table app.contact_discovery_settings enable row level security;
alter table app.contact_discovery_identity_state enable row level security;
alter table app.contact_discovery_identifiers enable row level security;
alter table app.contact_discovery_usage enable row level security;
revoke all on app.contact_discovery_key, app.contact_discovery_settings,
  app.contact_discovery_identity_state, app.contact_discovery_identifiers,
  app.contact_discovery_usage from public, anon, authenticated, service_role;

create function public.own_contact_discovery_enabled() returns boolean
language sql stable security definer set search_path = pg_catalog, app, public as $$
  select coalesce((select s.enabled from app.contact_discovery_settings s
    join public.profiles p on p.id = s.user_id and p.deleted_at is null
    where s.user_id = app.current_user_id()), false);
$$;

create function public.set_contact_discovery_enabled(input_enabled boolean) returns boolean
language plpgsql security definer set search_path = pg_catalog, app, public as $$
declare viewer text := app.current_user_id();
begin
  if viewer is null or not exists(select 1 from public.profiles where id = viewer and deleted_at is null) then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if input_enabled is null then raise exception 'invalid_consent'; end if;
  insert into app.contact_discovery_settings(user_id, enabled)
  values (viewer, input_enabled) on conflict(user_id) do update
    set enabled = excluded.enabled, updated_at = now();
  if not input_enabled then
    delete from app.contact_discovery_identifiers i using app.contact_discovery_identity_state s
      where i.clerk_user_id = s.clerk_user_id and s.user_id = viewer;
  end if;
  return input_enabled;
end;
$$;

-- Service-role input comes ONLY from a verified Clerk webhook or a BAPI fetch
-- for the bearer-authenticated member. Clients cannot register identifiers.
create function public.sync_contact_discovery_identity(
  input_clerk_user_id text, input_user_id text, input_updated_at timestamptz,
  input_identifiers text[]
) returns void language plpgsql security definer
set search_path = pg_catalog, app, public as $$
declare previous app.contact_discovery_identity_state; enabled_now boolean;
begin
  if input_updated_at is null or cardinality(input_identifiers) > 100 then
    raise exception 'invalid_identity';
  end if;
  if not exists(select 1 from public.clerk_identity_mappings
    where clerk_user_id = input_clerk_user_id and profile_id = input_user_id) then
    raise exception 'identity_mapping_required';
  end if;
  -- Lock settings first so disable and sync cannot resurrect a removed index.
  select enabled into enabled_now from app.contact_discovery_settings
    where user_id = input_user_id for update;
  if enabled_now is distinct from true then return; end if;
  if not exists(select 1 from public.profiles where id = input_user_id and deleted_at is null) then return; end if;
  insert into app.contact_discovery_identity_state values(input_clerk_user_id, input_user_id, input_updated_at)
    on conflict do nothing;
  select * into previous from app.contact_discovery_identity_state
    where clerk_user_id = input_clerk_user_id for update;
  if previous.user_id <> input_user_id then raise exception 'identity_conflict'; end if;
  if previous.identity_updated_at > input_updated_at then return; end if;
  update app.contact_discovery_identity_state set identity_updated_at = input_updated_at
    where clerk_user_id = input_clerk_user_id;
  delete from app.contact_discovery_identifiers where clerk_user_id = input_clerk_user_id;
  insert into app.contact_discovery_identifiers(clerk_user_id, token)
    select distinct input_clerk_user_id, extensions.hmac(convert_to(identifier, 'UTF8'), k.secret, 'sha256')
    from unnest(coalesce(input_identifiers, '{}'::text[])) identifier cross join app.contact_discovery_key k
    where length(identifier) between 5 and 260 and identifier ~ '^(email:|phone:)';
end;
$$;

-- Admission is committed before matching work. Counters contain only counts,
-- never contact identifiers; rolling day limits survive disable/re-enable.
create function public.admit_contact_discovery(input_count integer) returns boolean
language plpgsql security definer set search_path = pg_catalog, app, public as $$
declare viewer text := app.current_user_id(); usage app.contact_discovery_usage;
begin
  if not public.own_contact_discovery_enabled() then return false; end if;
  if input_count < 0 or input_count > 5000 then return false; end if;
  insert into app.contact_discovery_usage values(viewer, now(), 0, 0) on conflict do nothing;
  select * into usage from app.contact_discovery_usage where user_id = viewer for update;
  if usage.window_start < now() - interval '24 hours' then
    update app.contact_discovery_usage set window_start = now(), requests = 0, identifiers = 0 where user_id = viewer;
    usage.requests := 0; usage.identifiers := 0;
  end if;
  if usage.requests >= 24 or usage.identifiers + input_count > 30000 then return false; end if;
  update app.contact_discovery_usage set requests = requests + 1, identifiers = identifiers + input_count where user_id = viewer;
  return true;
end;
$$;

create function public.match_contact_discovery(input_viewer_id text, input_identifiers text[])
returns table(id text, handle text, display_name text, avatar_url text, bio text,
  home_area text, is_private_profile boolean, created_at timestamptz, relationship text)
language sql stable security definer set search_path = pg_catalog, app, public as $$
  select distinct p.id, p.handle, p.display_name, p.avatar_url, p.bio,
    p.home_area, p.is_private_profile, p.created_at,
    'non_follower'::text
  from unnest(input_identifiers) identifier
  cross join app.contact_discovery_key k
  join app.contact_discovery_identifiers i on i.token = extensions.hmac(convert_to(identifier, 'UTF8'), k.secret, 'sha256')
  join app.contact_discovery_identity_state s on s.clerk_user_id = i.clerk_user_id
  join public.profiles p on p.id = s.user_id
  join app.contact_discovery_settings target on target.user_id = p.id and target.enabled
  join app.contact_discovery_settings viewer on viewer.user_id = input_viewer_id and viewer.enabled
  left join app.profile_discovery_settings discovery on discovery.profile_id = p.id
  where cardinality(input_identifiers) <= 5000 and p.id <> input_viewer_id
    and p.deleted_at is null and not p.is_private_profile
    and not coalesce(discovery.hidden_from_suggestions, false)
    and not app.is_blocked(input_viewer_id, p.id)
    and not exists(select 1 from public.follows f where f.follower_user_id = input_viewer_id and f.followed_user_id = p.id)
    and exists(select 1 from public.profiles vp where vp.id = input_viewer_id and vp.deleted_at is null)
  order by p.display_name, p.id limit 100;
$$;

create function app.clear_deleted_contact_discovery() returns trigger language plpgsql
security definer set search_path = pg_catalog, app, public as $$
begin
  if new.deleted_at is not null then
    delete from app.contact_discovery_identity_state where user_id = new.id;
    delete from app.contact_discovery_settings where user_id = new.id;
    delete from app.contact_discovery_usage where user_id = new.id;
  end if;
  return new;
end;
$$;
create trigger clear_deleted_contact_discovery after update of deleted_at on public.profiles
  for each row execute function app.clear_deleted_contact_discovery();

revoke all on function public.own_contact_discovery_enabled(), public.set_contact_discovery_enabled(boolean),
  public.admit_contact_discovery(integer), public.sync_contact_discovery_identity(text,text,timestamptz,text[]),
  public.match_contact_discovery(text,text[]), app.clear_deleted_contact_discovery() from public, anon, authenticated;
grant execute on function public.own_contact_discovery_enabled(), public.set_contact_discovery_enabled(boolean),
  public.admit_contact_discovery(integer) to authenticated;
grant execute on function public.sync_contact_discovery_identity(text,text,timestamptz,text[]),
  public.match_contact_discovery(text,text[]) to service_role;

commit;
