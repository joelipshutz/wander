begin;

-- Engagement is attached to immutable feed-event ids so Feed and a place's
-- check-in/Wanna history always resolve to the same conversation. The tables
-- remain private; authenticated clients can only use the visibility-checked
-- RPCs below.
create table public.activity_likes (
  activity_id uuid not null references public.feed_events(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (activity_id, user_id)
);

create index activity_likes_user_created_idx
  on public.activity_likes (user_id, created_at desc);

create table public.activity_comments (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.feed_events(id) on delete cascade,
  author_user_id text not null references public.profiles(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint activity_comments_body_check check (
    body = btrim(body)
    and char_length(body) between 1 and 1000
  )
);

create index activity_comments_activity_created_idx
  on public.activity_comments (activity_id, created_at desc, id desc);

create index activity_comments_author_created_idx
  on public.activity_comments (author_user_id, created_at desc);

alter table public.activity_likes enable row level security;
alter table public.activity_comments enable row level security;

revoke all on table public.activity_likes from public, anon, authenticated;
revoke all on table public.activity_comments from public, anon, authenticated;

-- This restates the current feed visibility contract for a single place event.
-- It intentionally re-evaluates graph, block, deletion, and visit state on every
-- request so stale activity cannot retain an engagement back door.
create function app.can_read_activity_event(
  input_viewer_id text,
  input_activity_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select input_viewer_id is not null
    and exists (
      select 1
      from public.feed_events event
      join public.profiles actor on actor.id = event.actor_user_id
      join public.user_places source_place on source_place.id = event.user_place_id
      where event.id = input_activity_id
        and event.event_type in ('place_saved', 'place_been', 'place_want_to_go')
        and actor.deleted_at is null
        and source_place.deleted_at is null
        and not app.is_blocked(input_viewer_id, event.actor_user_id)
        and app.can_read_user_place(
          input_viewer_id,
          source_place.user_id,
          source_place.visibility
        )
        and (
          event.visit_id is null
          or exists (
            select 1
            from public.place_visits source_visit
            where source_visit.id = event.visit_id
              and source_visit.user_place_id = source_place.id
              and source_visit.deleted_at is null
          )
        )
    )
$$;

create function app.activity_engagement_json(
  input_viewer_id text,
  input_activity_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object(
    'activity_id', input_activity_id,
    'like_count', (
      select count(*)::integer
      from public.activity_likes activity_like
      join public.profiles liker on liker.id = activity_like.user_id
      where activity_like.activity_id = input_activity_id
        and liker.deleted_at is null
        and not app.is_blocked(input_viewer_id, activity_like.user_id)
    ),
    'comment_count', (
      select count(*)::integer
      from public.activity_comments comment
      join public.profiles author on author.id = comment.author_user_id
      where comment.activity_id = input_activity_id
        and author.deleted_at is null
        and not app.is_blocked(input_viewer_id, comment.author_user_id)
    ),
    'viewer_has_liked', exists (
      select 1
      from public.activity_likes activity_like
      where activity_like.activity_id = input_activity_id
        and activity_like.user_id = input_viewer_id
    )
  )
$$;

create function public.activity_engagement_summaries(
  input_activity_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if coalesce(cardinality(input_activity_ids), 0) > 100 then
    raise exception 'too_many_activity_ids';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        app.activity_engagement_json(viewer_id, requested.activity_id)
        order by requested.ordinal
      )
      from unnest(coalesce(input_activity_ids, '{}'::uuid[]))
        with ordinality as requested(activity_id, ordinal)
      where app.can_read_activity_event(viewer_id, requested.activity_id)
    ),
    '[]'::jsonb
  );
end;
$$;

create function public.place_activity_engagement_summaries(
  input_user_place_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if coalesce(cardinality(input_user_place_ids), 0) > 100 then
    raise exception 'too_many_user_place_ids';
  end if;

  return coalesce(
    (
      select jsonb_agg(
        app.activity_engagement_json(viewer_id, event.id)
          || jsonb_build_object(
            'user_place_id', event.user_place_id,
            'visit_id', event.visit_id,
            'event_type', event.event_type,
            'occurred_at', event.occurred_at
          )
        order by event.occurred_at desc, event.id desc
      )
      from public.feed_events event
      where event.user_place_id = any(coalesce(input_user_place_ids, '{}'::uuid[]))
        and event.event_type in ('place_saved', 'place_been', 'place_want_to_go')
        and app.can_read_activity_event(viewer_id, event.id)
    ),
    '[]'::jsonb
  );
end;
$$;

create function public.set_activity_like(
  input_activity_id uuid,
  input_is_liked boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if not app.can_read_activity_event(viewer_id, input_activity_id) then
    raise exception 'activity_not_visible';
  end if;

  if input_is_liked then
    insert into public.activity_likes (activity_id, user_id)
    values (input_activity_id, viewer_id)
    on conflict (activity_id, user_id) do nothing;
  else
    delete from public.activity_likes
    where activity_id = input_activity_id
      and user_id = viewer_id;
  end if;

  return app.activity_engagement_json(viewer_id, input_activity_id);
end;
$$;

create function public.activity_comments(
  input_activity_id uuid,
  input_before text default null,
  input_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  page_limit integer := greatest(1, least(coalesce(input_limit, 50), 100));
  cursor_created_at timestamptz;
  cursor_id uuid;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if not app.can_read_activity_event(viewer_id, input_activity_id) then
    raise exception 'activity_not_visible';
  end if;

  if input_before is not null and position('|' in input_before) > 1 then
    begin
      cursor_created_at := split_part(input_before, '|', 1)::timestamptz;
      cursor_id := split_part(input_before, '|', 2)::uuid;
    exception when others then
      cursor_created_at := null;
      cursor_id := null;
    end;
  end if;

  return (
    with visible_comments as (
      select comment.*
      from public.activity_comments comment
      join public.profiles author on author.id = comment.author_user_id
      where comment.activity_id = input_activity_id
        and author.deleted_at is null
        and not app.is_blocked(viewer_id, comment.author_user_id)
        and (
          cursor_created_at is null
          or (comment.created_at, comment.id) < (cursor_created_at, cursor_id)
        )
    ),
    page_with_extra as (
      select *
      from visible_comments
      order by created_at desc, id desc
      limit page_limit + 1
    ),
    page as (
      select *
      from page_with_extra
      order by created_at desc, id desc
      limit page_limit
    )
    select jsonb_build_object(
      'comments', coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', comment.id,
              'activity_id', comment.activity_id,
              'author', jsonb_build_object(
                'id', author.id,
                'handle', author.handle,
                'display_name', author.display_name,
                'avatar_url', author.avatar_url,
                'bio', author.bio,
                'home_area', author.home_area,
                'is_private_profile', author.is_private_profile,
                'created_at', author.created_at,
                'relationship', case
                  when author.id = viewer_id then 'owner'
                  when app.is_mutual(viewer_id, author.id) then 'mutual'
                  when app.follows(viewer_id, author.id) then 'follower'
                  else 'non_follower'
                end
              ),
              'body', comment.body,
              'created_at', comment.created_at
            )
            order by comment.created_at asc, comment.id asc
          )
          from page comment
          join public.profiles author on author.id = comment.author_user_id
        ),
        '[]'::jsonb
      ),
      'next_cursor', case
        when (select count(*) from page_with_extra) > page_limit then (
          select created_at::text || '|' || id::text
          from page
          order by created_at asc, id asc
          limit 1
        )
        else null
      end,
      'engagement', app.activity_engagement_json(viewer_id, input_activity_id)
    )
  );
end;
$$;

create function public.add_activity_comment(
  input_activity_id uuid,
  input_body text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_body text := btrim(coalesce(input_body, ''));
  saved_comment public.activity_comments;
  author public.profiles;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if not app.can_read_activity_event(viewer_id, input_activity_id) then
    raise exception 'activity_not_visible';
  end if;
  if char_length(normalized_body) < 1 or char_length(normalized_body) > 1000 then
    raise exception 'invalid_comment_body';
  end if;

  insert into public.activity_comments (activity_id, author_user_id, body)
  values (input_activity_id, viewer_id, normalized_body)
  returning * into saved_comment;

  select * into author
  from public.profiles
  where id = viewer_id
    and deleted_at is null;

  return jsonb_build_object(
    'comment', jsonb_build_object(
      'id', saved_comment.id,
      'activity_id', saved_comment.activity_id,
      'author', jsonb_build_object(
        'id', author.id,
        'handle', author.handle,
        'display_name', author.display_name,
        'avatar_url', author.avatar_url,
        'bio', author.bio,
        'home_area', author.home_area,
        'is_private_profile', author.is_private_profile,
        'created_at', author.created_at,
        'relationship', 'owner'
      ),
      'body', saved_comment.body,
      'created_at', saved_comment.created_at
    ),
    'engagement', app.activity_engagement_json(viewer_id, input_activity_id)
  );
end;
$$;

revoke all on function app.can_read_activity_event(text, uuid) from public, anon, authenticated;
revoke all on function app.activity_engagement_json(text, uuid) from public, anon, authenticated;

revoke all on function public.activity_engagement_summaries(uuid[]) from public, anon;
revoke all on function public.place_activity_engagement_summaries(uuid[]) from public, anon;
revoke all on function public.set_activity_like(uuid, boolean) from public, anon;
revoke all on function public.activity_comments(uuid, text, integer) from public, anon;
revoke all on function public.add_activity_comment(uuid, text) from public, anon;

grant execute on function public.activity_engagement_summaries(uuid[]) to authenticated;
grant execute on function public.place_activity_engagement_summaries(uuid[]) to authenticated;
grant execute on function public.set_activity_like(uuid, boolean) to authenticated;
grant execute on function public.activity_comments(uuid, text, integer) to authenticated;
grant execute on function public.add_activity_comment(uuid, text) to authenticated;

comment on function public.activity_engagement_summaries(uuid[]) is
  'Returns visibility-filtered like and comment counts for activity events.';
comment on function public.place_activity_engagement_summaries(uuid[]) is
  'Maps visible place history rows to their immutable activity events and engagement.';
comment on function public.set_activity_like(uuid, boolean) is
  'Idempotently sets the authenticated viewer like state on a visible activity.';
comment on function public.activity_comments(uuid, text, integer) is
  'Returns a visibility- and block-filtered comment page for a visible activity.';
comment on function public.add_activity_comment(uuid, text) is
  'Adds a normalized comment by the authenticated viewer to a visible activity.';

commit;
