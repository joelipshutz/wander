begin;

-- One small control plane: a null user_id is the global default and a
-- populated user_id overrides that default for one Clerk-backed profile.
create table public.feature_flags (
  id uuid primary key default gen_random_uuid(),
  key text not null check (key ~ '^[a-z0-9_]+$'),
  user_id text references public.profiles(id) on delete cascade,
  enabled boolean not null
);

create unique index feature_flags_global_key
  on public.feature_flags (key)
  where user_id is null;

create unique index feature_flags_user_key
  on public.feature_flags (key, user_id)
  where user_id is not null;

alter table public.feature_flags enable row level security;

create policy "feature flags read global and own override"
  on public.feature_flags for select
  to authenticated
  using (user_id is null or user_id = app.current_user_id());

revoke all privileges on table public.feature_flags from anon, authenticated;
grant select on table public.feature_flags to authenticated;

insert into public.feature_flags(key, user_id, enabled)
values ('first_visit_nux', null, true);

commit;
