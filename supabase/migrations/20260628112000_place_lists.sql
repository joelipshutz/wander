create table if not exists public.place_lists (
  id uuid primary key default gen_random_uuid(),
  owner_user_id text not null references public.profiles(id) on delete cascade,
  name text not null check (length(trim(name)) between 1 and 96),
  description text not null default '' check (length(description) <= 500),
  visibility text not null default 'followers' check (visibility in ('followers', 'stealth')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.place_list_members (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.place_lists(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  role text not null default 'collaborator' check (role = 'collaborator'),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (list_id, user_id)
);

create table if not exists public.place_list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.place_lists(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  owner_user_place_id uuid references public.user_places(id) on delete set null,
  source_user_place_id uuid references public.user_places(id) on delete set null,
  added_by_user_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create unique index if not exists place_list_items_active_place_idx
  on public.place_list_items(list_id, place_id)
  where deleted_at is null;

create index if not exists place_lists_owner_idx
  on public.place_lists(owner_user_id)
  where deleted_at is null;

create index if not exists place_list_members_user_idx
  on public.place_list_members(user_id)
  where deleted_at is null;

create index if not exists place_list_items_list_idx
  on public.place_list_items(list_id)
  where deleted_at is null;

drop trigger if exists place_lists_set_updated_at on public.place_lists;
create trigger place_lists_set_updated_at
  before update on public.place_lists
  for each row execute function app.set_updated_at();

drop trigger if exists place_list_items_set_updated_at on public.place_list_items;
create trigger place_list_items_set_updated_at
  before update on public.place_list_items
  for each row execute function app.set_updated_at();

alter table public.place_lists enable row level security;
alter table public.place_list_members enable row level security;
alter table public.place_list_items enable row level security;

create or replace function app.is_place_list_owner(input_list_id uuid, profile_id text)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select exists (
    select 1
    from public.place_lists pl
    where pl.id = input_list_id
      and pl.owner_user_id = profile_id
      and pl.deleted_at is null
  );
$$;

create or replace function app.is_place_list_member(input_list_id uuid, profile_id text)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select exists (
    select 1
    from public.place_list_members plm
    where plm.list_id = input_list_id
      and plm.user_id = profile_id
      and plm.deleted_at is null
  );
$$;

create or replace function app.can_read_place_list(input_list_id uuid, viewer_id text)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select exists (
    select 1
    from public.place_lists pl
    where pl.id = input_list_id
      and pl.deleted_at is null
      and viewer_id is not null
      and not app.is_blocked(viewer_id, pl.owner_user_id)
      and (
        pl.owner_user_id = viewer_id
        or app.is_place_list_member(pl.id, viewer_id)
        or (
          pl.visibility = 'followers'
          and app.follows(viewer_id, pl.owner_user_id)
        )
      )
  );
$$;

drop policy if exists "place lists readable by owner members followers" on public.place_lists;
create policy "place lists readable by owner members followers"
  on public.place_lists for select
  using (app.can_read_place_list(id, app.current_user_id()));

drop policy if exists "place lists insert owner" on public.place_lists;
create policy "place lists insert owner"
  on public.place_lists for insert
  with check (owner_user_id = app.current_user_id());

drop policy if exists "place lists update owner" on public.place_lists;
create policy "place lists update owner"
  on public.place_lists for update
  using (app.is_place_list_owner(id, app.current_user_id()))
  with check (owner_user_id = app.current_user_id());

drop policy if exists "place lists delete owner" on public.place_lists;
create policy "place lists delete owner"
  on public.place_lists for delete
  using (app.is_place_list_owner(id, app.current_user_id()));

drop policy if exists "place list members readable through list" on public.place_list_members;
create policy "place list members readable through list"
  on public.place_list_members for select
  using (app.can_read_place_list(list_id, app.current_user_id()));

drop policy if exists "place list members owner writes" on public.place_list_members;
create policy "place list members owner writes"
  on public.place_list_members for all
  using (app.is_place_list_owner(list_id, app.current_user_id()))
  with check (
    app.is_place_list_owner(list_id, app.current_user_id())
    and user_id <> app.current_user_id()
  );

drop policy if exists "place list items readable through list" on public.place_list_items;
create policy "place list items readable through list"
  on public.place_list_items for select
  using (app.can_read_place_list(list_id, app.current_user_id()));

drop policy if exists "place list items owner writes" on public.place_list_items;
create policy "place list items owner writes"
  on public.place_list_items for all
  using (app.is_place_list_owner(list_id, app.current_user_id()))
  with check (
    app.is_place_list_owner(list_id, app.current_user_id())
    and added_by_user_id = app.current_user_id()
    and exists (
      select 1
      from public.user_places up
      where up.id = coalesce(owner_user_place_id, source_user_place_id)
        and up.place_id = place_id
        and up.deleted_at is null
        and app.can_read_user_place(app.current_user_id(), up.user_id, up.visibility)
    )
  );

create or replace function app.visible_place_lists()
returns table (
  id uuid,
  owner_user_id text,
  owner_handle text,
  owner_display_name text,
  name text,
  description text,
  visibility text,
  created_at timestamptz,
  updated_at timestamptz,
  collaborators jsonb,
  item_count integer
)
language sql
stable
security invoker
as $$
  select
    pl.id,
    pl.owner_user_id,
    owner.handle as owner_handle,
    owner.display_name as owner_display_name,
    pl.name,
    pl.description,
    pl.visibility,
    pl.created_at,
    pl.updated_at,
    coalesce(
      jsonb_agg(
        distinct jsonb_build_object(
          'user_id', member_profile.id,
          'handle', member_profile.handle,
          'display_name', member_profile.display_name,
          'role', plm.role
        )
      ) filter (where member_profile.id is not null),
      '[]'::jsonb
    ) as collaborators,
    count(distinct pli.id)::integer as item_count
  from public.place_lists pl
  join public.profiles owner on owner.id = pl.owner_user_id
  left join public.place_list_members plm
    on plm.list_id = pl.id
   and plm.deleted_at is null
  left join public.profiles member_profile on member_profile.id = plm.user_id
  left join public.place_list_items pli
    on pli.list_id = pl.id
   and pli.deleted_at is null
  where app.can_read_place_list(pl.id, app.current_user_id())
  group by pl.id, owner.handle, owner.display_name
  order by pl.updated_at desc;
$$;

create or replace function app.place_list_detail(input_list_id uuid)
returns jsonb
language sql
stable
security invoker
as $$
  select jsonb_build_object(
    'list',
    to_jsonb(pl),
    'collaborators',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'user_id', p.id,
            'handle', p.handle,
            'display_name', p.display_name,
            'role', plm.role
          )
          order by p.handle
        )
        from public.place_list_members plm
        join public.profiles p on p.id = plm.user_id
        where plm.list_id = pl.id
          and plm.deleted_at is null
      ),
      '[]'::jsonb
    ),
    'items',
    coalesce(
      (
        select jsonb_agg(to_jsonb(pli) order by pli.created_at)
        from public.place_list_items pli
        where pli.list_id = pl.id
          and pli.deleted_at is null
      ),
      '[]'::jsonb
    )
  )
  from public.place_lists pl
  where pl.id = input_list_id
    and app.can_read_place_list(pl.id, app.current_user_id());
$$;

create or replace function app.upsert_place_list(input_list jsonb)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  input_id uuid := nullif(input_list->>'id', '')::uuid;
  output_id uuid;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  if input_id is null then
    insert into public.place_lists(owner_user_id, name, description, visibility)
    values (
      viewer_id,
      trim(input_list->>'name'),
      coalesce(input_list->>'description', ''),
      coalesce(nullif(input_list->>'visibility', ''), 'followers')
    )
    returning id into output_id;
  else
    update public.place_lists
    set
      name = trim(input_list->>'name'),
      description = coalesce(input_list->>'description', ''),
      visibility = coalesce(nullif(input_list->>'visibility', ''), visibility),
      deleted_at = null
    where id = input_id
      and owner_user_id = viewer_id
      and deleted_at is null
    returning id into output_id;
  end if;

  if output_id is null then
    raise exception 'place_list_not_found_or_forbidden';
  end if;

  return output_id;
end;
$$;

create or replace function app.delete_place_list(input_list_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  update public.place_lists
  set deleted_at = now()
  where id = input_list_id
    and owner_user_id = app.current_user_id()
    and deleted_at is null;
end;
$$;

create or replace function app.set_place_list_collaborators(
  input_list_id uuid,
  collaborator_user_ids text[]
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  collaborator_id text;
begin
  if not app.is_place_list_owner(input_list_id, app.current_user_id()) then
    raise exception 'place_list_not_found_or_forbidden';
  end if;

  update public.place_list_members
  set deleted_at = now()
  where list_id = input_list_id
    and deleted_at is null
    and not (user_id = any(collaborator_user_ids));

  foreach collaborator_id in array collaborator_user_ids loop
    if collaborator_id <> app.current_user_id() then
      insert into public.place_list_members(list_id, user_id, role, deleted_at)
      values (input_list_id, collaborator_id, 'collaborator', null)
      on conflict (list_id, user_id) do update
        set deleted_at = null,
            role = 'collaborator';
    end if;
  end loop;
end;
$$;

create or replace function app.add_place_list_item(
  input_list_id uuid,
  input_place_id uuid,
  input_owner_user_place_id uuid default null,
  input_source_user_place_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  output_id uuid;
begin
  if not app.is_place_list_owner(input_list_id, viewer_id) then
    raise exception 'place_list_not_found_or_forbidden';
  end if;

  if not exists (
    select 1
    from public.user_places up
    where up.id = coalesce(input_owner_user_place_id, input_source_user_place_id)
      and up.place_id = input_place_id
      and up.deleted_at is null
      and app.can_read_user_place(viewer_id, up.user_id, up.visibility)
  ) then
    raise exception 'place_not_visible';
  end if;

  insert into public.place_list_items(
    list_id,
    place_id,
    owner_user_place_id,
    source_user_place_id,
    added_by_user_id
  )
  values (
    input_list_id,
    input_place_id,
    input_owner_user_place_id,
    input_source_user_place_id,
    viewer_id
  )
  on conflict (list_id, place_id) where deleted_at is null do update
    set owner_user_place_id = excluded.owner_user_place_id,
        source_user_place_id = excluded.source_user_place_id,
        deleted_at = null
  returning id into output_id;

  update public.place_lists
  set updated_at = now()
  where id = input_list_id;

  return output_id;
end;
$$;

create or replace function app.remove_place_list_item(input_list_id uuid, input_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if not app.is_place_list_owner(input_list_id, app.current_user_id()) then
    raise exception 'place_list_not_found_or_forbidden';
  end if;

  update public.place_list_items
  set deleted_at = now()
  where id = input_item_id
    and list_id = input_list_id
    and deleted_at is null;

  update public.place_lists
  set updated_at = now()
  where id = input_list_id;
end;
$$;

create or replace function public.visible_place_lists()
returns table (
  id uuid,
  owner_user_id text,
  owner_handle text,
  owner_display_name text,
  name text,
  description text,
  visibility text,
  created_at timestamptz,
  updated_at timestamptz,
  collaborators jsonb,
  item_count integer
)
language sql
stable
security invoker
as $$
  select * from app.visible_place_lists();
$$;

create or replace function public.place_list_detail(input_list_id uuid)
returns jsonb
language sql
stable
security invoker
as $$
  select app.place_list_detail(input_list_id);
$$;

create or replace function public.upsert_place_list(input_list jsonb)
returns uuid
language sql
security invoker
as $$
  select app.upsert_place_list(input_list);
$$;

create or replace function public.delete_place_list(input_list_id uuid)
returns void
language sql
security invoker
as $$
  select app.delete_place_list(input_list_id);
$$;

create or replace function public.set_place_list_collaborators(input_list_id uuid, collaborator_user_ids text[])
returns void
language sql
security invoker
as $$
  select app.set_place_list_collaborators(input_list_id, collaborator_user_ids);
$$;

create or replace function public.add_place_list_item(
  input_list_id uuid,
  input_place_id uuid,
  input_owner_user_place_id uuid default null,
  input_source_user_place_id uuid default null
)
returns uuid
language sql
security invoker
as $$
  select app.add_place_list_item(input_list_id, input_place_id, input_owner_user_place_id, input_source_user_place_id);
$$;

create or replace function public.remove_place_list_item(input_list_id uuid, input_item_id uuid)
returns void
language sql
security invoker
as $$
  select app.remove_place_list_item(input_list_id, input_item_id);
$$;

grant select, insert, update, delete on public.place_lists to authenticated;
grant select, insert, update, delete on public.place_list_members to authenticated;
grant select, insert, update, delete on public.place_list_items to authenticated;

revoke all on function app.visible_place_lists() from public, anon;
revoke all on function app.place_list_detail(uuid) from public, anon;
revoke all on function app.upsert_place_list(jsonb) from public, anon;
revoke all on function app.delete_place_list(uuid) from public, anon;
revoke all on function app.set_place_list_collaborators(uuid, text[]) from public, anon;
revoke all on function app.add_place_list_item(uuid, uuid, uuid, uuid) from public, anon;
revoke all on function app.remove_place_list_item(uuid, uuid) from public, anon;

grant execute on function public.visible_place_lists() to authenticated;
grant execute on function public.place_list_detail(uuid) to authenticated;
grant execute on function public.upsert_place_list(jsonb) to authenticated;
grant execute on function public.delete_place_list(uuid) to authenticated;
grant execute on function public.set_place_list_collaborators(uuid, text[]) to authenticated;
grant execute on function public.add_place_list_item(uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.remove_place_list_item(uuid, uuid) to authenticated;

comment on table public.place_lists is 'Map-native planning collections owned by one user.';
comment on table public.place_list_members is 'Read-only collaborators for private/shared place lists.';
comment on table public.place_list_items is 'Places attached to a list, keyed to visible social or owner saves when possible.';
