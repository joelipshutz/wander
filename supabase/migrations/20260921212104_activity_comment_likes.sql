begin;

-- Comment likes are distinct from activity likes. Like rows remain private,
-- with RLS enabled and no direct client grants, matching activity engagement.
create table public.activity_comment_likes (
  comment_id uuid not null references public.activity_comments(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (comment_id, user_id)
);
create index activity_comment_likes_user_idx on public.activity_comment_likes(user_id);
alter table public.activity_comment_likes enable row level security;
revoke all on table public.activity_comment_likes from public, anon, authenticated;

-- Internal aggregation is definer-only because clients cannot read the tables.
-- Only the checked public RPCs may supply a viewer. Blocked/deleted likers do
-- not contribute to that viewer's count.
create function app.activity_comment_likes_json(input_viewer_id text, input_comment_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object(
    'comment_id', comment.id,
    'activity_id', comment.activity_id,
    'like_count', (
      select count(*)::integer
      from public.activity_comment_likes liked
      join public.profiles liker on liker.id = liked.user_id
      where liked.comment_id = comment.id
        and liker.deleted_at is null
        and not app.is_blocked(input_viewer_id, liked.user_id)
    ),
    'viewer_has_liked', exists (
      select 1 from public.activity_comment_likes liked
      where liked.comment_id = comment.id and liked.user_id = input_viewer_id
    )
  )
  from public.activity_comments comment where comment.id = input_comment_id
$$;
revoke all on function app.activity_comment_likes_json(text, uuid) from public, anon, authenticated;

-- Like the existing set_activity_like RPC, this narrow definer owns access to
-- private rows; identity always comes from current_user_id(), never a parameter.
-- Lock the comment to serialize opposite-state writes and concurrent deletion.
create function public.set_activity_comment_like(input_comment_id uuid, input_is_liked boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  target public.activity_comments;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if input_is_liked is null then raise exception 'like_state_required'; end if;

  select comment.* into target
  from public.activity_comments comment
  join public.profiles author on author.id = comment.author_user_id
  where comment.id = input_comment_id
    and author.deleted_at is null
    and not app.is_blocked(viewer_id, author.id)
    and app.can_read_activity_event(viewer_id, comment.activity_id)
  for update of comment;
  if not found then raise exception 'comment_not_visible'; end if;

  if input_is_liked then
    insert into public.activity_comment_likes(comment_id, user_id)
    values (target.id, viewer_id)
    on conflict (comment_id, user_id) do nothing;
  else
    delete from public.activity_comment_likes
    where comment_id = target.id and user_id = viewer_id;
  end if;
  return app.activity_comment_likes_json(viewer_id, target.id);
end;
$$;
revoke all on function public.set_activity_comment_like(uuid, boolean) from public, anon;
grant execute on function public.set_activity_comment_like(uuid, boolean) to authenticated;

-- Preserve activity_comments(uuid,text,integer): stable, jsonb, pinned
-- search_path, security definer, authenticated-only. The existing activity,
-- author visibility and cursor contracts are unchanged; each returned comment
-- now carries its count and viewer state without extra client round trips.
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

comment on function public.set_activity_comment_like(uuid, boolean) is
  'Idempotently sets the authenticated viewer comment like after current activity and author access checks.';

commit;
