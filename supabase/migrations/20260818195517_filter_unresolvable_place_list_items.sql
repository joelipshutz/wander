begin;

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
set search_path = public, app
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
   and exists (
     select 1
     from public.user_places active_reference
     where active_reference.id in (
         pli.owner_user_place_id,
         pli.source_user_place_id
       )
       and active_reference.place_id = pli.place_id
       and active_reference.deleted_at is null
   )
  where app.can_read_place_list(pl.id, app.current_user_id())
  group by pl.id, owner.handle, owner.display_name
  order by pl.updated_at desc;
$$;

create or replace function app.place_list_detail(input_list_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = public, app
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
          and exists (
            select 1
            from public.user_places active_reference
            where active_reference.id in (
                pli.owner_user_place_id,
                pli.source_user_place_id
              )
              and active_reference.place_id = pli.place_id
              and active_reference.deleted_at is null
          )
      ),
      '[]'::jsonb
    )
  )
  from public.place_lists pl
  where pl.id = input_list_id
    and app.can_read_place_list(pl.id, app.current_user_id());
$$;

create or replace function public.visible_place_lists_snapshot()
returns jsonb
language sql
stable
security invoker
set search_path = public, app
as $$
  with summaries as materialized (
    select summary.*
    from public.visible_place_lists() summary
  ),
  referenced_owner_ids as materialized (
    select distinct active_reference.user_id as owner_user_id
    from summaries summary
    join public.place_list_items item
      on item.list_id = summary.id
     and item.deleted_at is null
    join public.user_places active_reference
      on active_reference.id in (
          item.owner_user_place_id,
          item.source_user_place_id
        )
     and active_reference.place_id = item.place_id
     and active_reference.deleted_at is null
  ),
  owner_ids as materialized (
    select summary.owner_user_id
    from summaries summary
    union
    select referenced_owner.owner_user_id
    from referenced_owner_ids referenced_owner
  ),
  owner_places as materialized (
    select place_row.*
    from owner_ids owner
    cross join lateral public.profile_visible_places(owner.owner_user_id, null, null) place_row
  ),
  relationships as materialized (
    select
      owner.owner_user_id as profile_id,
      public.profile_relationship(owner.owner_user_id) as relationship
    from owner_ids owner
  )
  select jsonb_build_object(
    'summaries',
    coalesce(
      (
        select jsonb_agg(to_jsonb(summary) order by summary.updated_at desc, summary.id)
        from summaries summary
      ),
      '[]'::jsonb
    ),
    'details',
    coalesce(
      (
        select jsonb_agg(detail order by summary.updated_at desc, summary.id)
        from summaries summary
        cross join lateral (
          select public.place_list_detail(summary.id) as detail
        ) list_detail
        where detail is not null
      ),
      '[]'::jsonb
    ),
    'owner_places',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(place_row)
          order by place_row.owner_user_id, place_row.updated_at desc, place_row.user_place_id
        )
        from owner_places place_row
      ),
      '[]'::jsonb
    ),
    'relationships',
    coalesce(
      (
        select jsonb_agg(
          to_jsonb(relationship_row)
          order by relationship_row.profile_id
        )
        from relationships relationship_row
      ),
      '[]'::jsonb
    )
  );
$$;

revoke all on function app.visible_place_lists() from public, anon;
revoke all on function app.place_list_detail(uuid) from public, anon;
revoke all on function public.visible_place_lists_snapshot() from public, anon;

grant execute on function app.visible_place_lists() to authenticated;
grant execute on function app.place_list_detail(uuid) to authenticated;
grant execute on function public.visible_place_lists_snapshot() to authenticated;

comment on function app.visible_place_lists() is
  'Returns readable list summaries whose counts include only items backed by an active viewer-visible save reference.';
comment on function app.place_list_detail(uuid) is
  'Returns readable list metadata and only items backed by an active viewer-visible save reference.';
comment on function public.visible_place_lists_snapshot() is
  'Batches visible list summaries, details, referenced-save owner places, and viewer relationships. SECURITY INVOKER composes existing authenticated RLS-filtered contracts.';

commit;
