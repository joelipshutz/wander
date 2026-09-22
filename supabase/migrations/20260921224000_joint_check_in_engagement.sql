begin;

create function app.lock_activity_v2(input_activity_id uuid)
returns public.feed_events language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare target public.feed_events; resolved_id uuid;
begin
  if app.current_user_id() is null then raise exception 'not_authenticated'; end if;
  -- Shared order with rejoin: group -> participant/owned data -> event. Lock
  -- retained provenance as well, because a detached event can rejoin now.
  perform 1 from public.shared_visit_groups shared
    where shared.model_version=2 and (exists(select 1 from public.feed_events event
        where event.id=input_activity_id and event.shared_visit_group_id=shared.id)
      or exists(select 1 from public.shared_visit_participants member
        join public.feed_events event on event.visit_id=coalesce(member.visit_id,member.retained_visit_id)
        where member.group_id=shared.id and event.id=input_activity_id))
    order by shared.id for update;
  select * into target from public.feed_events where id=input_activity_id for update;
  resolved_id := app.resolve_activity_v2(app.current_user_id(),input_activity_id);
  if resolved_id is null then raise exception 'activity_not_visible'; end if;
  if resolved_id<>input_activity_id then raise exception 'activity_context_changed'; end if;
  return target;
end;
$$;

create function app.mark_joint_personal_engagement()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,app
as $$
declare target public.feed_events;
begin
  if exists(select 1 from public.feed_events event
    join public.shared_visit_participants member on member.retained_visit_id=event.visit_id
    join public.shared_visit_groups shared on shared.id=member.group_id and shared.model_version=2
    where event.id=new.activity_id and event.shared_visit_group_id is null) then
    target := app.lock_activity_v2(new.activity_id);
    update public.feed_events set standalone_engagement_started_at=now()
      where id=target.id and standalone_engagement_started_at is null;
  end if;
  return new;
end;
$$;
create trigger activity_likes_00_joint_identity before insert on public.activity_likes
  for each row execute function app.mark_joint_personal_engagement();
create trigger activity_comments_00_joint_identity before insert on public.activity_comments
  for each row execute function app.mark_joint_personal_engagement();

create function public.set_activity_like_v2(input_activity_id uuid,input_is_liked boolean)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,app
as $$
declare target public.feed_events := app.lock_activity_v2(input_activity_id);
begin
  if input_is_liked then
    insert into public.activity_likes(activity_id,user_id) values(target.id,app.current_user_id()) on conflict do nothing;
  else delete from public.activity_likes where activity_id=target.id and user_id=app.current_user_id(); end if;
  return app.activity_engagement_json(app.current_user_id(),target.id);
end;
$$;

create function public.activity_engagement_summaries_v2(input_activity_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,app
as $$
begin
  if app.current_user_id() is null then raise exception 'not_authenticated'; end if;
  if coalesce(cardinality(input_activity_ids),0)>100 then raise exception 'too_many_activity_ids'; end if;
  return coalesce((select jsonb_agg(app.activity_engagement_json(app.current_user_id(),id)) from (
    select distinct app.resolve_activity_v2(app.current_user_id(),requested) as id
      from unnest(coalesce(input_activity_ids,'{}'::uuid[])) requested) resolved where id is not null),'[]'::jsonb);
end;
$$;

create function public.place_activity_engagement_summaries_v2(input_user_place_ids uuid[])
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,app
as $$
begin
  if app.current_user_id() is null then raise exception 'not_authenticated'; end if;
  if coalesce(cardinality(input_user_place_ids),0)>100 then raise exception 'too_many_user_place_ids'; end if;
  return coalesce((select jsonb_agg(app.activity_engagement_json(app.current_user_id(),resolved.id)
    ||jsonb_build_object('user_place_id',event.user_place_id,'visit_id',coalesce(event.visit_id,compatibility_visit.id),
      'event_type',event.event_type,'occurred_at',event.occurred_at))
    from public.feed_events event
    left join public.place_visits compatibility_visit on event.visit_id is null
      and event.event_type in ('place_been','place_saved')
      and compatibility_visit.user_place_id=event.user_place_id
      and compatibility_visit.backfilled_from_user_place and compatibility_visit.deleted_at is null
    cross join lateral (select app.resolve_activity_v2(app.current_user_id(),event.id) as id) resolved
    where event.user_place_id=any(coalesce(input_user_place_ids,'{}'::uuid[]))
      and event.shared_visit_group_id is null and resolved.id is not null
      and event.event_type in ('place_saved','place_been','place_want_to_go')),'[]'::jsonb);
end;
$$;

create function app.activity_comment_json(input_comment_id uuid,input_viewer_id text)
returns jsonb language sql stable security definer set search_path=pg_catalog,public,app
as $$
 select jsonb_build_object('id',comment.id,'activity_id',comment.activity_id,
   'author',app.joint_profile_json(comment.author_user_id,input_viewer_id),'body',comment.body,'created_at',comment.created_at)
 from public.activity_comments comment where comment.id=input_comment_id
$$;

create function public.add_activity_comment_v2(input_activity_id uuid,input_body text,
 input_request_id uuid,input_consent_version integer default null)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,app
as $$
declare
 viewer_id text := app.lock_joint_check_in_request(input_request_id);
 target public.feed_events;
 receipt public.joint_check_in_operations;
 prior public.activity_comments;
 normalized_body text := btrim(coalesce(input_body,''));
 fingerprint text; group_id uuid; comment_id uuid;
begin
 target := app.lock_activity_v2(input_activity_id);
 if char_length(normalized_body)<1 or char_length(normalized_body)>1000 then raise exception 'invalid_comment_body'; end if;
 if target.shared_visit_group_id is not null and input_consent_version is distinct from 1 then
   raise exception 'joint_check_in_discussion_consent_required';
 end if;
 fingerprint := app.joint_check_in_payload_hash(jsonb_build_object('activity_id',target.id,'body',normalized_body,'consent',input_consent_version));
 group_id := target.shared_visit_group_id;
 if group_id is null then
   select member.group_id into group_id from public.shared_visit_participants member
     join public.shared_visit_groups shared on shared.id=member.group_id and shared.model_version=2
     where member.retained_visit_id=target.visit_id order by shared.id limit 1;
 end if;
 select * into receipt from public.joint_check_in_operations where actor_user_id=viewer_id and request_id=input_request_id;
 if receipt.request_id is not null then
   if receipt.operation_kind<>'comment_create' or receipt.payload_hash<>fingerprint then raise exception 'joint_check_in_request_conflict'; end if;
   comment_id := (receipt.committed_result->>'comment_id')::uuid;
   if not exists(select 1 from public.activity_comments where id=comment_id and author_user_id=viewer_id and activity_id=target.id) then
     raise exception 'comment_deleted';
   end if;
 else
   select * into prior from public.activity_comments where author_user_id=viewer_id and client_request_id=input_request_id;
   if prior.id is not null then
     if prior.activity_id<>target.id or prior.body<>normalized_body then raise exception 'joint_check_in_request_conflict'; end if;
     comment_id := prior.id;
   else
     insert into public.activity_comments(activity_id,author_user_id,body,client_request_id)
       values(target.id,viewer_id,normalized_body,input_request_id) returning id into comment_id;
   end if;
   if group_id is not null then
     insert into public.joint_check_in_operations(actor_user_id,request_id,group_id,operation_kind,payload_hash,committed_result)
       values(viewer_id,input_request_id,group_id,'comment_create',fingerprint,jsonb_build_object('comment_id',comment_id,'activity_id',target.id));
   end if;
 end if;
 return jsonb_build_object('comment',app.activity_comment_json(comment_id,viewer_id),
   'engagement',app.activity_engagement_json(viewer_id,target.id));
end;
$$;

-- Deleting one's own words remains possible after leaving, blocking or closure.
-- Counts from an inaccessible conversation are never returned as a side channel.
create or replace function public.delete_own_activity_comment(input_comment_id uuid)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,app
as $$
declare viewer_id text:=app.current_user_id(); deleted_activity_id uuid;
begin
 if viewer_id is null then raise exception 'not_authenticated'; end if;
 delete from public.activity_comments where id=input_comment_id and author_user_id=viewer_id
   returning activity_id into deleted_activity_id;
 if deleted_activity_id is null then raise exception 'comment_not_found_or_not_owned'; end if;
 if app.resolve_activity_v2(viewer_id,deleted_activity_id) is null then
   return jsonb_build_object('activity_id',deleted_activity_id,'is_available',false);
 end if;
 return app.activity_engagement_json(viewer_id,deleted_activity_id);
end;
$$;

revoke all on function app.lock_activity_v2(uuid) from public,anon,authenticated;
revoke all on function app.mark_joint_personal_engagement() from public,anon,authenticated;
revoke all on function app.activity_comment_json(uuid,text) from public,anon,authenticated;
revoke all on function public.set_activity_like_v2(uuid,boolean) from public,anon;
revoke all on function public.activity_engagement_summaries_v2(uuid[]) from public,anon;
revoke all on function public.place_activity_engagement_summaries_v2(uuid[]) from public,anon;
revoke all on function public.add_activity_comment_v2(uuid,text,uuid,integer) from public,anon;
grant execute on function public.set_activity_like_v2(uuid,boolean) to authenticated;
grant execute on function public.activity_engagement_summaries_v2(uuid[]) to authenticated;
grant execute on function public.place_activity_engagement_summaries_v2(uuid[]) to authenticated;
grant execute on function public.add_activity_comment_v2(uuid,text,uuid,integer) to authenticated;

create function public.activity_comments_v2(
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
  input_activity_id := app.resolve_activity_v2(viewer_id, input_activity_id);
  if input_activity_id is null then
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
revoke all on function public.activity_comments_v2(uuid,text,integer) from public,anon;
grant execute on function public.activity_comments_v2(uuid,text,integer) to authenticated;

commit;
