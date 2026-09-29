begin;
set local lock_timeout = '5s';

-- REC-614. This migration changes event creation and installs a private,
-- explicitly scoped repair. It does NOT rewrite or delete existing history.
-- The separate repair operation requires one parent, its exact original visit
-- date, and an expected event count. It preserves old activity links.
create table app.activity_event_aliases (
  alias_id uuid primary key,
  activity_id uuid not null references public.feed_events(id) on delete cascade,
  check (alias_id <> activity_id)
);
create index activity_event_aliases_target_idx on app.activity_event_aliases(activity_id);
alter table app.activity_event_aliases enable row level security;
revoke all on app.activity_event_aliases from public, anon, authenticated;

create function app.canonical_activity_id(input_activity_id uuid)
returns uuid language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select coalesce((select activity_id from app.activity_event_aliases
                  where alias_id = input_activity_id), input_activity_id)
$$;
revoke all on function app.canonical_activity_id(uuid) from public, anon, authenticated;

-- Maintenance only: never callable by API roles. The original event and
-- compatibility visit must agree before duplicate activity can be repaired.
-- No place, visit, comment, comment-like or photo is removed. Likes are merged
-- as a set of people; existing rows are UPDATED so no new notification is sent.
create function app.repair_legacy_feed_events(
  input_user_place_id uuid,
  input_expected_event_count integer,
  input_expected_visited_at timestamptz
)
returns integer language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  canonical_id uuid;
  duplicate_ids uuid[];
  actual_count integer;
begin
  if input_user_place_id is null or input_expected_event_count < 2
     or input_expected_event_count is null or input_expected_visited_at is null then
    raise exception 'invalid_legacy_repair_scope';
  end if;
  -- Serialize parent writes and engagement for the short repair transaction.
  lock table public.user_places, public.feed_events,
    public.activity_likes, public.activity_comments in share row exclusive mode;
  if not exists (
    select 1 from public.place_visits visit
    join public.user_places parent on parent.id = visit.user_place_id
    where parent.id = input_user_place_id and parent.status = 'been'
      and parent.deleted_at is null and visit.deleted_at is null
      and visit.backfilled_from_user_place
      and visit.visited_at = input_expected_visited_at
  ) then raise exception 'legacy_repair_visit_mismatch'; end if;

  select event.id into canonical_id from public.feed_events event
  where event.user_place_id = input_user_place_id
    and event.event_type = 'place_been' and event.visit_id is null
    and event.occurred_at = input_expected_visited_at
  order by event.created_at, event.id limit 1;
  if canonical_id is null then raise exception 'legacy_repair_original_missing'; end if;
  select count(*) into actual_count from public.feed_events
  where user_place_id = input_user_place_id and event_type = 'place_been' and visit_id is null;
  if actual_count = 1 then return 0; end if;
  if actual_count <> input_expected_event_count then
    raise exception 'legacy_repair_count_changed';
  end if;
  select array_agg(id) into duplicate_ids from public.feed_events
  where user_place_id = input_user_place_id and event_type = 'place_been'
    and visit_id is null and id <> canonical_id;

  -- Flatten any prior aliases; no chains or cycles are created.
  update app.activity_event_aliases set activity_id = canonical_id
  where activity_id = any(duplicate_ids);
  insert into app.activity_event_aliases(alias_id, activity_id)
  select id, canonical_id from unnest(duplicate_ids) ids(id)
  on conflict (alias_id) do update set activity_id = excluded.activity_id;

  with ranked as (
    select activity_id, user_id,
      row_number() over (partition by user_id order by created_at, activity_id) as position
    from public.activity_likes
    where activity_id = canonical_id or activity_id = any(duplicate_ids)
  )
  delete from public.activity_likes target using ranked
  where ranked.position > 1 and target.activity_id = ranked.activity_id
    and target.user_id = ranked.user_id;
  update public.activity_likes set activity_id = canonical_id
  where activity_id = any(duplicate_ids);
  update public.activity_comments set activity_id = canonical_id
  where activity_id = any(duplicate_ids);
  delete from public.feed_events where id = any(duplicate_ids);
  return cardinality(duplicate_ids);
end;
$$;
revoke all on function app.repair_legacy_feed_events(uuid, integer, timestamptz)
  from public, anon, authenticated;

create index feed_events_been_parent_idx on public.feed_events(user_place_id)
  where event_type = 'place_been';

-- Preserve the private volatile SECURITY DEFINER trigger and pinned search
-- path from 20260720234500 and 20260725214500. The trigger writes the private
-- event table using its parent row, never a caller-selected actor identity.
create or replace function app.record_user_place_feed_event()
returns trigger language plpgsql volatile security definer
set search_path = public, app
as $$
declare
  resolved_event_type text;
  event_at timestamptz;
begin
  if new.deleted_at is not null or current_setting('app.explicit_check_in', true) = 'on' then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.deleted_at is null
    and not (old.status = 'wanna_go' and new.status = 'been') then
    return new;
  end if;
  resolved_event_type := case
    when new.source_type = 'social_save' then 'place_saved'
    when new.status = 'been' then 'place_been'
    else 'place_want_to_go'
  end;
  if resolved_event_type <> 'place_been' then
    perform app.record_feed_event(new.user_id, resolved_event_type, new.id, new.place_id);
    return new;
  end if;
  -- A parent INSERT/UPDATE holds its row lock until commit, serializing this
  -- check with other saves/restores of the same parent. Explicit check-ins
  -- continue through their existing per-visit UUID trigger and unique index.
  if exists (select 1 from public.feed_events where user_place_id = new.id
             and event_type = 'place_been') then return new; end if;
  event_at := coalesce(new.visited_at, new.saved_at, new.created_at);
  if tg_op = 'UPDATE' and old.status = 'wanna_go' and old.deleted_at is null then
    event_at := coalesce(new.visited_at, now());
  end if;
  insert into public.feed_events(actor_user_id, event_type, user_place_id, place_id, occurred_at)
  values(new.user_id, 'place_been', new.id, new.place_id, event_at);
  return new;
end;
$$;
revoke all on function app.record_user_place_feed_event() from public, anon, authenticated;

-- The following RPC/helper definitions retain their previous return types,
-- volatility, SECURITY DEFINER, search paths, grants, limits and visibility
-- checks. Only repaired IDs are resolved to the original activity first.

-- Prior definition: 20260916171502_repeat_wanna_saves.sql
create or replace function app.can_read_activity_event(
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
      where event.id = app.canonical_activity_id(input_activity_id)
        and actor.deleted_at is null
        and (
          event.actor_user_id = input_viewer_id
          or not coalesce(actor.is_private_profile, false)
        )
        and not app.is_blocked(input_viewer_id, event.actor_user_id)
        and not exists (
          select 1 from public.place_wanna_saves wanna
          where wanna.id = event.id
            and not app.can_read_user_place(input_viewer_id, event.actor_user_id, wanna.visibility)
        )
        and (
          (
            event.event_type in ('place_saved', 'place_been', 'place_want_to_go')
            and exists (
              select 1
              from public.user_places source_place
              where source_place.id = event.user_place_id
                and source_place.deleted_at is null
                and app.can_read_user_place(
                  input_viewer_id,
                  source_place.user_id,
                  source_place.visibility
                )
            )
            and (
              event.visit_id is null
              or exists (
                select 1
                from public.place_visits source_visit
                where source_visit.id = event.visit_id
                  and source_visit.user_place_id = event.user_place_id
                  and source_visit.deleted_at is null
              )
            )
          )
          or (
            event.event_type = 'list_created'
            and app.can_read_place_list(event.list_id, input_viewer_id)
          )
          or (
            event.event_type = 'list_item_added'
            and app.can_read_place_list(event.list_id, input_viewer_id)
            and exists (
              select 1
              from public.user_places source_place
              where source_place.id = event.user_place_id
                and source_place.deleted_at is null
                and app.can_read_user_place(
                  input_viewer_id,
                  source_place.user_id,
                  source_place.visibility
                )
            )
          )
        )
    )
$$;
revoke all on function app.can_read_activity_event(text, uuid) from public, anon, authenticated;

-- Prior definition: 20260810155601_activity_engagement.sql
create or replace function app.activity_engagement_json(
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
      where activity_like.activity_id = app.canonical_activity_id(input_activity_id)
        and liker.deleted_at is null
        and not app.is_blocked(input_viewer_id, activity_like.user_id)
    ),
    'comment_count', (
      select count(*)::integer
      from public.activity_comments comment
      join public.profiles author on author.id = comment.author_user_id
      where comment.activity_id = app.canonical_activity_id(input_activity_id)
        and author.deleted_at is null
        and not app.is_blocked(input_viewer_id, comment.author_user_id)
    ),
    'viewer_has_liked', exists (
      select 1
      from public.activity_likes activity_like
      where activity_like.activity_id = app.canonical_activity_id(input_activity_id)
        and activity_like.user_id = input_viewer_id
    )
  )
$$;
revoke all on function app.activity_engagement_json(text, uuid) from public, anon, authenticated;

-- Prior definition: 20260916171502_repeat_wanna_saves.sql
create or replace function public.activity_detail(input_activity_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  result jsonb;
begin
  input_activity_id := app.canonical_activity_id(input_activity_id);
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;
  if not app.can_read_activity_event(viewer_id, input_activity_id) then
    raise exception 'activity_not_visible';
  end if;

  select jsonb_build_object(
    'id', event.id,
    'event_type', event.event_type,
    'occurred_at', event.occurred_at,
    'actor', jsonb_build_object(
      'id', actor.id,
      'handle', actor.handle,
      'display_name', actor.display_name,
      'avatar_url', actor.avatar_url,
      'bio', actor.bio,
      'home_area', actor.home_area,
      'is_private_profile', actor.is_private_profile,
      'created_at', actor.created_at,
      'relationship', case
        when actor.id = viewer_id then 'owner'
        when app.is_mutual(viewer_id, actor.id) then 'mutual'
        when app.follows(viewer_id, actor.id) then 'follower'
        else 'non_follower'
      end
    ),
    'place', app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id),
    'list', app.feed_list_projection(event.list_id),
    'note', case
      when event.event_type = 'list_created'
        then app.feed_list_projection(event.list_id)->>'description'
      else app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id)->>'note'
    end,
    'rating', case
      when event.event_type in ('place_been', 'list_item_added')
        then (app.feed_wanna_place_projection(event.user_place_id, event.visit_id, event.id)->>'rating_score')::double precision
      else null
    end,
    'media', '[]'::jsonb
  )
  into result
  from public.feed_events event
  join public.profiles actor on actor.id = event.actor_user_id
  where event.id = input_activity_id;

  return result;
end;
$$;
revoke all on function public.activity_detail(uuid) from public, anon;
grant execute on function public.activity_detail(uuid) to authenticated;

-- Prior definition: 20260921212104_activity_comment_likes.sql
create or replace function public.activity_comments(
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
  input_activity_id := app.canonical_activity_id(input_activity_id);
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
            ) || app.activity_comment_likes_json(viewer_id, comment.id)
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
revoke all on function public.activity_comments(uuid, text, integer) from public, anon;
grant execute on function public.activity_comments(uuid, text, integer) to authenticated;

-- Prior definition: 20260810155601_activity_engagement.sql
create or replace function public.set_activity_like(
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
  input_activity_id := app.canonical_activity_id(input_activity_id);
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
revoke all on function public.set_activity_like(uuid, boolean) from public, anon;
grant execute on function public.set_activity_like(uuid, boolean) to authenticated;

-- Prior definition: 20260810155601_activity_engagement.sql
create or replace function public.add_activity_comment(
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
  input_activity_id := app.canonical_activity_id(input_activity_id);
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
revoke all on function public.add_activity_comment(uuid, text) from public, anon;
grant execute on function public.add_activity_comment(uuid, text) to authenticated;

-- Prior definition: 20260811220214_activity_ticket_media.sql
create or replace function public.activity_media(input_activity_ids uuid[])
returns table(activity_id uuid, media jsonb)
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select
    requested.id as activity_id,
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', photo.id,
            'url', null,
            'storage_bucket', photo.storage_bucket,
            'storage_path', photo.storage_path,
            'accessibility_label', 'Activity photo'
          )
          order by photo.sort_order, photo.created_at, photo.id
        )
        from public.visit_photos photo
        where photo.visit_id = event.visit_id
          and photo.upload_state = 'uploaded'
          and photo.deleted_at is null
      ),
      '[]'::jsonb
    ) as media
  from (select distinct unnest(coalesce(input_activity_ids, '{}'::uuid[])) as id) requested
  join public.feed_events event on event.id = app.canonical_activity_id(requested.id)
  where app.can_read_activity_event(app.current_user_id(), event.id)
  order by event.occurred_at desc, event.id desc
$$;
revoke all on function public.activity_media(uuid[]) from public, anon;
grant execute on function public.activity_media(uuid[]) to authenticated;

commit;
