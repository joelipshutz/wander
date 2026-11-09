begin;

-- Circle Questions use RPC-only access. Every read and write derives its caller
-- from app.current_user_id() and rechecks the current graph/block state.
create table public.circle_questions (
  id uuid primary key,
  author_id text not null references public.profiles(id) on delete cascade,
  draft jsonb not null check (jsonb_typeof(draft) = 'object'),
  stealth boolean not null default false,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  deleted_at timestamptz,
  check (expires_at > created_at and expires_at <= created_at + interval '30 days')
);
create index circle_questions_recent_idx on public.circle_questions(created_at desc, id desc) where deleted_at is null;
create table public.circle_question_tags (
  question_id uuid not null references public.circle_questions(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  read_at timestamptz,
  primary key(question_id,user_id)
);
create index circle_question_tags_user_idx on public.circle_question_tags(user_id,question_id);
create table public.circle_question_replies (
  id uuid primary key,
  question_id uuid not null references public.circle_questions(id) on delete cascade,
  author_id text not null references public.profiles(id) on delete cascade,
  places jsonb not null default '[]' check (jsonb_typeof(places) = 'array' and jsonb_array_length(places) <= 50),
  note text not null default '' check (char_length(note) <= 1000),
  created_at timestamptz not null default now()
);
create index circle_question_replies_question_idx on public.circle_question_replies(question_id,created_at,id);
create table public.circle_question_likes (
  question_id uuid not null references public.circle_questions(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  primary key(question_id,user_id)
);
alter table public.circle_questions enable row level security;
alter table public.circle_question_tags enable row level security;
alter table public.circle_question_replies enable row level security;
alter table public.circle_question_likes enable row level security;
revoke all on public.circle_questions,public.circle_question_tags,public.circle_question_replies,public.circle_question_likes from public,anon,authenticated;

create function app.can_read_circle_question(viewer text, question_id uuid)
returns boolean language sql stable security definer set search_path = pg_catalog,public,app as $$
  select viewer is not null and exists (
    select 1 from public.circle_questions q join public.profiles p on p.id=q.author_id
    where q.id=question_id and q.deleted_at is null and p.deleted_at is null
      and exists(select 1 from public.profiles where id=viewer and deleted_at is null)
      and not app.is_blocked(viewer,q.author_id)
      and (q.author_id=viewer
        or exists(select 1 from public.circle_question_tags t where t.question_id=q.id and t.user_id=viewer)
        or (not q.stealth and exists(select 1 from public.follows f where f.follower_user_id=viewer and f.followed_user_id=q.author_id)))
  )
$$;
revoke all on function app.can_read_circle_question(text,uuid) from public,anon,authenticated;

create function app.circle_question_json(question_id uuid,viewer text)
returns jsonb language sql stable security definer set search_path = pg_catalog,public,app as $$
  select jsonb_build_object(
    'draft',q.draft || jsonb_build_object('id',q.id,'stealth',q.stealth,'recipientIDs',
      case when viewer=q.author_id then coalesce((select jsonb_agg(user_id order by user_id) from public.circle_question_tags where question_id=q.id),'[]') else '[]'::jsonb end),
    'author',jsonb_build_object('id',p.id,'name',p.display_name,'isFriend',app.is_mutual(viewer,p.id)),
    'createdAt',q.created_at,'expiresAt',q.expires_at,
    'likes',(select count(*) from public.circle_question_likes l where l.question_id=q.id and not app.is_blocked(viewer,l.user_id)),
    'liked',exists(select 1 from public.circle_question_likes l where l.question_id=q.id and l.user_id=viewer),
    'replies',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,
      'author',jsonb_build_object('id',a.id,'name',a.display_name,'isFriend',app.is_mutual(viewer,a.id)),
      'note',r.note,'places',r.places,'createdAt',r.created_at) order by r.created_at,r.id)
      from public.circle_question_replies r join public.profiles a on a.id=r.author_id and a.deleted_at is null
      where r.question_id=q.id and not app.is_blocked(viewer,r.author_id)),'[]')
  ) from public.circle_questions q join public.profiles p on p.id=q.author_id
  where q.id=question_id and app.can_read_circle_question(viewer,q.id)
$$;
revoke all on function app.circle_question_json(uuid,text) from public,anon,authenticated;

create function public.circle_questions() returns jsonb language sql stable security definer
set search_path=pg_catalog,public,app as $$
  select coalesce(jsonb_agg(app.circle_question_json(q.id,app.current_user_id()) order by q.created_at desc,q.id desc),'[]')
  from (select id,created_at from public.circle_questions where app.can_read_circle_question(app.current_user_id(),id)
    order by created_at desc,id desc limit 100) q
$$;
create function public.circle_question(input_question_id uuid) returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public,app as $$
begin
  if not app.can_read_circle_question(app.current_user_id(),input_question_id) then raise exception 'question_unavailable'; end if;
  return app.circle_question_json(input_question_id,app.current_user_id());
end $$;

create function public.circle_question_publish(input_draft jsonb) returns jsonb language plpgsql volatile security definer
set search_path=pg_catalog,public,app as $$
declare viewer text:=app.current_user_id(); qid uuid; days integer; target text; mode text; draft jsonb;
begin
  if viewer is null or not exists(select 1 from public.profiles where id=viewer and deleted_at is null) then raise exception 'not_authenticated'; end if;
  qid:=(input_draft->>'id')::uuid;
  if qid is null then raise exception 'invalid_question'; end if;
  -- Serialize the idempotency check as well as the write, including overlapping retries.
  perform pg_advisory_xact_lock(hashtextextended('circle_question:'||viewer,0));
  -- An ambiguous transport retry cannot duplicate a post or its notifications.
  if exists(select 1 from public.circle_questions where id=qid and author_id=viewer) then
    if not exists(select 1 from public.circle_questions q where q.id=qid
      and q.draft->'categories'=input_draft->'categories' and q.draft->'subcategories'=input_draft->'subcategories'
      and q.draft->'area'=input_draft->'area' and q.draft->>'note'=coalesce(input_draft->>'note','')
      and q.draft->>'audience'=input_draft->>'audience' and q.draft->>'days'=input_draft->>'days'
      and q.stealth=coalesce((input_draft->>'stealth')::boolean,false)
      and (q.draft->>'audience'='all' or
        array(select t.user_id from public.circle_question_tags t where t.question_id=qid order by t.user_id)
        = array(select distinct value from jsonb_array_elements_text(input_draft->'recipientIDs') order by value)))
      then raise exception 'idempotency_conflict'; end if;
    return app.circle_question_json(qid,viewer);
  end if;
  days:=(input_draft->>'days')::integer; mode:=input_draft->>'audience';
  if days is null or days not between 1 and 30 or mode is null or mode not in ('all','hometown','people')
    or jsonb_typeof(input_draft->'area') is distinct from 'object'
    or char_length(coalesce(input_draft#>>'{area,name}','')) not between 1 and 200
    or (input_draft#>>'{area,latitude}')::numeric not between -90 and 90
    or (input_draft#>>'{area,longitude}')::numeric not between -180 and 180
    or input_draft#>>'{area,latitude}' is null or input_draft#>>'{area,longitude}' is null
    or char_length(coalesce(input_draft->>'note','')) > 1000
    or jsonb_typeof(input_draft->'categories') is distinct from 'array'
    or jsonb_typeof(input_draft->'subcategories') is distinct from 'array'
    or jsonb_typeof(input_draft->'recipientIDs') is distinct from 'array'
    or jsonb_array_length(input_draft->'categories') > 20 or jsonb_array_length(input_draft->'subcategories') > 50
    or jsonb_array_length(input_draft->'recipientIDs') > 500
    or octet_length(input_draft::text) > 32000 then raise exception 'invalid_question'; end if;
  -- Persist the exact Codable shape consumed by every authorized viewer.
  if jsonb_typeof(input_draft#>'{area,name}') is distinct from 'string'
    or jsonb_typeof(input_draft#>'{area,detail}') is distinct from 'string'
    or jsonb_typeof(input_draft#>'{area,latitude}') is distinct from 'number'
    or jsonb_typeof(input_draft#>'{area,longitude}') is distinct from 'number'
    or char_length(input_draft#>>'{area,detail}') > 1000
    or exists(select 1 from jsonb_each(input_draft->'area') where key in ('city','region','countryCode')
      and jsonb_typeof(value) not in ('string','null'))
    or exists(select 1 from jsonb_array_elements((input_draft->'categories')||(input_draft->'subcategories')) value
      where jsonb_typeof(value) <> 'string' or char_length(value#>>'{}') not between 1 and 100)
    then raise exception 'invalid_question'; end if;
  if coalesce((input_draft->>'stealth')::boolean,false) and mode='all' then raise exception 'stealth_requires_tags'; end if;
  if (select count(*) from public.circle_questions where author_id=viewer and created_at>now()-interval '1 day')>=20 then raise exception 'rate_limited'; end if;
  -- Store the sentence/area only. Client recipient arrays never become authority.
  draft:=jsonb_build_object('id',qid,'categories',input_draft->'categories','subcategories',input_draft->'subcategories',
    'area',input_draft->'area','note',coalesce(input_draft->>'note',''),'audience',mode,'days',days);
  insert into public.circle_questions(id,author_id,draft,stealth,expires_at)
    values(qid,viewer,draft,coalesce((input_draft->>'stealth')::boolean,false),now()+days*interval '1 day');
  if mode='all' then
    insert into public.circle_question_tags(question_id,user_id)
      select qid,f.follower_user_id from public.follows f join public.profiles p on p.id=f.follower_user_id and p.deleted_at is null
      where f.followed_user_id=viewer and not app.is_blocked(viewer,f.follower_user_id);
  else
    for target in select distinct jsonb_array_elements_text(input_draft->'recipientIDs') loop
      if target=viewer or not exists(select 1 from public.profiles where id=target and deleted_at is null)
        or app.is_blocked(viewer,target) or not exists(select 1 from public.follows where
          (follower_user_id=viewer and followed_user_id=target) or (follower_user_id=target and followed_user_id=viewer)) then raise exception 'invalid_recipient'; end if;
      if mode='hometown' and (not app.is_mutual(viewer,target) or not exists(select 1 from public.profiles p
        where p.id=target and lower(p.home_area)=lower(input_draft#>>'{area,city}'))) then raise exception 'invalid_hometown_recipient'; end if;
      insert into public.circle_question_tags(question_id,user_id) values(qid,target);
    end loop;
    if not exists(select 1 from public.circle_question_tags where question_id=qid) then raise exception 'tags_required'; end if;
  end if;
  for target in select user_id from public.circle_question_tags where question_id=qid loop
    perform app.queue_notification_event(target,viewer,'circle_question_tagged','A question for your circle',
      'Someone in your circle is looking for a recommendation.','recme://questions/'||qid::text,
      jsonb_build_object('question_id',qid),'circle-question:'||qid::text||':'||target);
  end loop;
  return app.circle_question_json(qid,viewer);
end $$;

create function public.circle_question_reply(input_question_id uuid,input_client_id uuid,input_places jsonb,input_note text)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,app as $$
declare viewer text:=app.current_user_id(); item jsonb; prior public.circle_question_replies;
begin
  if not app.can_read_circle_question(viewer,input_question_id) then raise exception 'question_unavailable'; end if;
  if input_client_id is null or jsonb_typeof(input_places) is distinct from 'array' or jsonb_array_length(input_places)>50
    or char_length(coalesce(input_note,''))>1000 or octet_length(input_places::text)>100000
    or (jsonb_array_length(input_places)=0 and char_length(btrim(coalesce(input_note,'')))=0) then raise exception 'invalid_reply'; end if;
  for item in select * from jsonb_array_elements(input_places) loop
    if jsonb_typeof(item->'id') is distinct from 'string' or jsonb_typeof(item->'name') is distinct from 'string'
      or jsonb_typeof(item->'detail') is distinct from 'string' or jsonb_typeof(item->'note') is distinct from 'string'
      or jsonb_typeof(item->'latitude') is distinct from 'number' or jsonb_typeof(item->'longitude') is distinct from 'number'
      or char_length(coalesce(item->>'id','')) not between 1 and 500 or char_length(coalesce(item->>'name','')) not between 1 and 200
      or char_length(coalesce(item->>'detail',''))>1000 or char_length(coalesce(item->>'note',''))>1000
      or item->>'latitude' is null or item->>'longitude' is null
      or (item->>'latitude')::numeric not between -90 and 90 or (item->>'longitude')::numeric not between -180 and 180
      then raise exception 'invalid_place'; end if;
  end loop;
  perform pg_advisory_xact_lock(hashtextextended('circle_reply:'||viewer,0));
  select * into prior from public.circle_question_replies where id=input_client_id;
  if found then
    if prior.author_id<>viewer or prior.question_id<>input_question_id or prior.places<>input_places
      or prior.note<>btrim(coalesce(input_note,'')) then raise exception 'idempotency_conflict'; end if;
    return app.circle_question_json(input_question_id,viewer);
  end if;
  if (select count(*) from public.circle_question_replies where author_id=viewer and created_at>now()-interval '1 minute')>=20 then raise exception 'rate_limited'; end if;
  insert into public.circle_question_replies(id,question_id,author_id,places,note)
    values(input_client_id,input_question_id,viewer,input_places,btrim(coalesce(input_note,'')));
  return app.circle_question_json(input_question_id,viewer);
end $$;

create function public.circle_question_like(input_question_id uuid,input_liked boolean)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,app as $$
declare viewer text:=app.current_user_id();
begin
  if not app.can_read_circle_question(viewer,input_question_id) then raise exception 'question_unavailable'; end if;
  if input_liked then insert into public.circle_question_likes values(input_question_id,viewer) on conflict do nothing;
  else delete from public.circle_question_likes where question_id=input_question_id and user_id=viewer; end if;
  return app.circle_question_json(input_question_id,viewer);
end $$;

create function public.circle_question_inbox() returns jsonb language sql stable security definer
set search_path=pg_catalog,public,app as $$
  select coalesce(jsonb_agg(jsonb_build_object('question',app.circle_question_json(q.id,app.current_user_id()),'isRead',t.read_at is not null) order by q.created_at desc),'[]')
  from public.circle_question_tags t join public.circle_questions q on q.id=t.question_id
  where t.user_id=app.current_user_id() and app.can_read_circle_question(app.current_user_id(),q.id)
    and q.created_at>now()-interval '30 days'
$$;
create function public.circle_question_read(input_question_id uuid) returns void language sql volatile security definer
set search_path=pg_catalog,public,app as $$
  update public.circle_question_tags set read_at=coalesce(read_at,now())
  where question_id=input_question_id and user_id=app.current_user_id() and app.can_read_circle_question(app.current_user_id(),question_id)
$$;

revoke all on function public.circle_questions(),public.circle_question(uuid),public.circle_question_publish(jsonb),public.circle_question_reply(uuid,uuid,jsonb,text),public.circle_question_like(uuid,boolean),public.circle_question_inbox(),public.circle_question_read(uuid) from public,anon;
grant execute on function public.circle_questions(),public.circle_question(uuid),public.circle_question_publish(jsonb),public.circle_question_reply(uuid,uuid,jsonb,text),public.circle_question_like(uuid,boolean),public.circle_question_inbox(),public.circle_question_read(uuid) to authenticated;

-- Extend existing notification and private-message contracts without changing
-- their definer posture, ABI, auth helpers, volatility, or pinned search_path.


alter table public.notification_events drop constraint notification_events_notification_type_check;
alter table public.notification_events add constraint notification_events_notification_type_check check (notification_type in ('followed_you','mutual_follow','list_collaborator_added','list_place_added','place_saved_from_your_map','capture_ready','followed_activity_digest','followed_place_visit','shared_visit','activity_liked','activity_commented','import_finished','wanna_go_reminder','save_streak_reminder','calendar_reservation_live','calendar_reservation_follow_up','circle_question_tagged'));


create or replace function app.notification_type_enabled(
  input_preferences public.notification_preferences,
  input_notification_type text
)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select coalesce(input_preferences.push_enabled, false)
    and case
      when input_notification_type in ('followed_you', 'mutual_follow') then input_preferences.social_graph_enabled
      when input_notification_type in ('list_collaborator_added', 'list_place_added') then input_preferences.shared_lists_enabled
      when input_notification_type = 'shared_visit' then input_preferences.shared_visits_enabled
      when input_notification_type in ('place_saved_from_your_map','circle_question_tagged') then input_preferences.recommendations_enabled
      when input_notification_type in ('capture_ready', 'import_finished') then input_preferences.capture_enabled
      when input_notification_type = 'followed_activity_digest' then input_preferences.discovery_digest_enabled
      when input_notification_type = 'followed_place_visit' then input_preferences.followed_activity_enabled
      when input_notification_type in ('activity_liked', 'activity_commented') then input_preferences.engagement_enabled
      when input_notification_type = 'wanna_go_reminder' then input_preferences.wanna_go_reminders_enabled
      when input_notification_type = 'save_streak_reminder' then true
      when input_notification_type in ('calendar_reservation_live', 'calendar_reservation_follow_up')
        then input_preferences.reservation_reminders_enabled
      else false
    end
$$;

create or replace function app.queue_notification_event(
  input_recipient_user_id text,
  input_actor_user_id text,
  input_notification_type text,
  input_title text,
  input_body text,
  input_deeplink_url text default null,
  input_data jsonb default '{}'::jsonb,
  input_dedupe_key text default null,
  input_not_before timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public, app
as $$
declare
  recipient_preferences public.notification_preferences;
  output_event_id uuid;
  actor_is_muted boolean := false;
begin
  if input_recipient_user_id is null or input_recipient_user_id = '' then return null; end if;
  if input_actor_user_id is not null and input_actor_user_id = input_recipient_user_id then return null; end if;
  if input_notification_type not in (
    'circle_question_tagged', 'followed_you', 'mutual_follow', 'list_collaborator_added',
    'list_place_added', 'place_saved_from_your_map', 'capture_ready',
    'followed_activity_digest', 'followed_place_visit', 'shared_visit',
    'activity_liked', 'activity_commented', 'import_finished',
    'wanna_go_reminder', 'save_streak_reminder',
    'calendar_reservation_live', 'calendar_reservation_follow_up'
  ) then raise exception 'invalid_notification_type'; end if;
  if coalesce(jsonb_typeof(coalesce(input_data, '{}'::jsonb)), '') <> 'object' then
    raise exception 'invalid_notification_data';
  end if;
  if length(trim(coalesce(input_title, ''))) not between 1 and 120
     or length(trim(coalesce(input_body, ''))) not between 1 and 240 then
    raise exception 'invalid_notification_copy';
  end if;
  if not exists (
    select 1 from public.profiles profile
    where profile.id = input_recipient_user_id and profile.deleted_at is null
  ) then return null; end if;
  if input_actor_user_id is not null then
    if not exists (
      select 1 from public.profiles profile
      where profile.id = input_actor_user_id and profile.deleted_at is null
    ) then return null; end if;
    if app.is_blocked(input_recipient_user_id, input_actor_user_id) then return null; end if;
    if to_regclass('public.profile_mutes') is not null then
      execute
        'select exists (
           select 1 from public.profile_mutes
           where muter_user_id = $1 and muted_user_id = $2
         )'
      into actor_is_muted
      using input_recipient_user_id, input_actor_user_id;
      if actor_is_muted then return null; end if;
    end if;
  end if;

  recipient_preferences := app.ensure_notification_preferences(input_recipient_user_id);
  if not app.notification_type_enabled(recipient_preferences, input_notification_type) then return null; end if;

  if input_dedupe_key is not null then
    select id into output_event_id
    from public.notification_events
    where dedupe_key = input_dedupe_key and status in ('pending', 'claimed')
    order by created_at desc limit 1;
    if output_event_id is not null then return output_event_id; end if;
  end if;

  insert into public.notification_events(
    recipient_user_id, actor_user_id, notification_type, title, body,
    deeplink_url, data, dedupe_key, not_before, expires_at, latest_at
  ) values (
    input_recipient_user_id, input_actor_user_id, input_notification_type,
    left(trim(input_title), 120), left(trim(input_body), 240),
    nullif(trim(coalesce(input_deeplink_url, '')), ''), coalesce(input_data, '{}'::jsonb),
    nullif(trim(coalesce(input_dedupe_key, '')), ''), coalesce(input_not_before, now()),
    greatest(coalesce(input_not_before, now()) + interval '24 hours', now() + interval '24 hours'),
    greatest(coalesce(input_not_before, now()) + interval '24 hours', now() + interval '24 hours')
  ) returning id into output_event_id;
  return output_event_id;
end;
$$;

create or replace function app.notification_source_readable(event public.notification_events)
returns boolean language plpgsql stable security definer
set search_path = pg_catalog, public, app
as $$
declare viewer text := event.recipient_user_id;
begin
  if not exists (select 1 from public.profiles where id = viewer and deleted_at is null)
    then return false; end if;
  if event.actor_user_id is not null and (
    app.is_blocked(viewer, event.actor_user_id)
    or not exists (select 1 from public.profiles where id = event.actor_user_id and deleted_at is null)
  ) then return false; end if;
  case event.notification_type
    when 'circle_question_tagged' then
      return app.can_read_circle_question(viewer,app.privacy_uuid(event.data->>'question_id'));
    when 'activity_liked', 'activity_commented' then
      return app.can_read_activity_event(viewer, app.privacy_uuid(event.data->>'activity_id'));
    when 'followed_place_visit' then
      -- REC-589 batches an import behind one notification without a visit_id.
      -- Its existing helper recomputes currently readable, non-silent sources.
      -- Keep compatibility when that optional feature has not been installed.
      if event.data->>'sender_import_id' is not null then
        if to_regprocedure('app.import_notification_content(text,text,text)') is null
          or exists (select 1 from public.profiles where id=event.actor_user_id and is_private_profile) then
          return false;
        end if;
        return app.import_notification_content(event.actor_user_id, viewer,
          event.data->>'sender_import_id') is not null;
      end if;
      return app.can_read_visit_source(viewer, app.privacy_uuid(event.data->>'visit_id'));
    when 'shared_visit' then
      return exists (
        select 1 from public.shared_visit_participants participant
        join public.shared_visit_groups shared_group on shared_group.id = participant.group_id
        where participant.id = app.privacy_uuid(event.data->>'participant_id')
          and participant.user_id = viewer and participant.status = 'pending'
          and participant.invitation_generation::text = event.data->>'invitation_generation'
          and participant.invitation_snapshot is not null and shared_group.cancelled_at is null
          and app.can_read_visit_source(viewer, shared_group.source_visit_id)
      );
    when 'list_collaborator_added' then
      return app.can_read_place_list(app.privacy_uuid(event.data->>'list_id'), viewer);
    when 'list_place_added' then
      return app.can_read_place_list(app.privacy_uuid(event.data->>'list_id'), viewer)
        and exists (select 1 from public.place_list_items item
          where item.list_id = app.privacy_uuid(event.data->>'list_id')
            and item.place_id = app.privacy_uuid(event.data->>'place_id')
            and item.added_by_user_id = event.actor_user_id and item.deleted_at is null);
    when 'place_saved_from_your_map' then
      return exists (select 1 from public.user_places saved
        join public.profiles owner on owner.id = saved.user_id
        where saved.id = app.privacy_uuid(event.data->>'user_place_id')
          and saved.user_id = event.actor_user_id and saved.deleted_at is null
          and owner.deleted_at is null and not owner.is_private_profile
          and app.can_read_user_place(viewer, saved.user_id, saved.visibility));
    when 'followed_you', 'mutual_follow' then
      return exists (select 1 from public.follows
        where follower_user_id = event.actor_user_id and followed_user_id = viewer);
    when 'capture_ready', 'import_finished', 'wanna_go_reminder', 'save_streak_reminder',
         'calendar_reservation_live', 'calendar_reservation_follow_up' then
      -- These producers are authenticated owner-only or internal self-reminders.
      return event.actor_user_id is null or event.actor_user_id = viewer;
    else return false;
  end case;
end;
$$;

create or replace function public.authorize_push_notification_delivery(input_event_id uuid, input_claim_token uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare event public.notification_events; allowed boolean; import_content jsonb;
begin
  select * into event from public.notification_events
  where id = input_event_id and status = 'claimed' and claim_token = input_claim_token
    and claim_expires_at > now() for update;
  if not found then return null; end if;
  allowed := app.notification_source_readable(event)
    and (event.source <> 'calendar_reservation' or exists (
      select 1 from public.calendar_reservations reservation
      where reservation.user_id = event.recipient_user_id
        and reservation.completed_at is null and reservation.cancelled_at is null
        and event.conflict_group = 'calendar_reservation:' || reservation.id))
    and least(event.expires_at, event.latest_at) > now()
    and exists (select 1 from public.notification_preferences preferences
      where preferences.user_id = event.recipient_user_id
        and app.notification_type_enabled(preferences, event.notification_type))
    and not exists (select 1 from public.profile_mutes
      where muter_user_id = event.recipient_user_id and muted_user_id = event.actor_user_id);
  -- A source can become hidden after queue claim. Re-render only the frozen
  -- import manifest at final authorization so detailed copy cannot name/count
  -- a revoked place. The ledger never expands to later import saves.
  if event.notification_type = 'followed_place_visit'
      and event.data->>'sender_import_id' is not null then
    import_content := app.import_notification_content(event.actor_user_id,
      event.recipient_user_id, event.data->>'sender_import_id');
    allowed := allowed and import_content is not null;
  end if;
  if not coalesce(allowed, false) then
    update public.notification_events set status = 'skipped', skip_reason = 'source_not_visible',
      claim_token = null, claim_expires_at = null, error_message = null
      where id = event.id;
    return null;
  end if;
  if import_content is not null then
    update public.notification_events
      set body = import_content->>'body',
          deeplink_url = 'recme://places/' || (import_content->>'place_id'),
          data = data || jsonb_build_object('place_id', import_content->>'place_id',
            'place_count', import_content->'place_count')
      where id = event.id
      returning * into event;
  end if;
  return jsonb_build_object(
    'event_id', event.id, 'claim_token', event.claim_token,
    'recipient_user_id', event.recipient_user_id, 'actor_user_id', event.actor_user_id,
    'notification_type', event.notification_type,
    -- Eligibility, not the presence of an actor, controls delivery. Friends and
    -- other authorized recipients receive the producer's personalized copy.
    'title', event.title,
    'body', event.body,
    'deeplink_url', event.deeplink_url,
    'data', (select coalesce(jsonb_object_agg(key, value), '{}'::jsonb)
      from jsonb_each(event.data) where key in ('question_id','activity_id','visit_id','user_place_id','place_id',
        'list_id','participant_id','invitation_generation','group_id','source_visit_id',
        'actor_user_id','event_type','reservation_id','job_id')),
    'attempt_count', event.attempt_count, 'max_attempts', event.max_attempts,
    'claim_expires_at', event.claim_expires_at,
    'tokens', (select coalesce(jsonb_agg(jsonb_build_object('id', token.id,
      'device_token', token.device_token, 'environment', token.environment,
      'app_bundle_id', token.app_bundle_id)), '[]'::jsonb)
      from public.notification_device_tokens token
      where token.user_id = event.recipient_user_id and token.is_active
        and not exists (select 1 from public.notification_push_deliveries delivery
          where delivery.event_id = event.id and delivery.token_id = token.id
            and delivery.status in ('accepted','permanent_token_failure','permanent_event_failure')))
  );
end;
$$;

alter table public.private_messages drop constraint private_messages_context_kind_check;
alter table public.private_messages add constraint private_messages_context_kind_check check(context_kind in ('activity','place','question'));


create or replace function app.private_message_context_allowed(first_user text, second_user text, source_kind text, source_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select case
    when source_kind is null and source_id is null then true
    when source_kind = 'question' and source_id is not null then
      app.can_read_circle_question(first_user,source_id) and app.can_read_circle_question(second_user,source_id)
    when source_kind = 'activity' and source_id is not null then
      app.can_read_activity_event(first_user, source_id)
      and app.can_read_activity_event(second_user, source_id)
    when source_kind = 'place' and source_id is not null then exists (
      select 1 from public.user_places saved
      join public.profiles owner on owner.id = saved.user_id and owner.deleted_at is null
      where saved.place_id = source_id and saved.deleted_at is null
        and saved.user_id in (first_user, second_user)
        and not coalesce(owner.is_private_profile, false)
        and app.can_read_user_place(first_user, saved.user_id, saved.visibility)
        and app.can_read_user_place(second_user, saved.user_id, saved.visibility)
    )
    else false
  end
$$;

create or replace function app.private_message_json(message_id uuid, viewer_id text)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object(
    'id', message.id, 'conversationID', message.conversation_id,
    'senderID', message.sender_id, 'clientID', message.client_id,
    'body', message.body, 'sentAt', message.sent_at,
    'context', case when message.context_kind is null then null else jsonb_build_object(
      'kind', message.context_kind, 'id', message.context_id,
      'title', case when message.context_kind = 'question' then 'Question for your circle'
      when message.context_kind = 'place' then
        (select canonical_name from public.places where id = message.context_id)
      else (select coalesce(place.canonical_name, list.name, 'Activity')
        from public.feed_events event
        left join public.user_places saved on saved.id = event.user_place_id
        left join public.places place on place.id = saved.place_id
        left join public.place_lists list on list.id = event.list_id
        where event.id = app.canonical_activity_id(message.context_id)) end
    ) end,
    'recipientReadAt', case
      when message.sender_id = conversation.low_user_id
        and (message.sent_at, message.id) <= (conversation.high_read_sent_at, conversation.high_read_message_id)
        then conversation.high_read_at
      when message.sender_id = conversation.high_user_id
        and (message.sent_at, message.id) <= (conversation.low_read_sent_at, conversation.low_read_message_id)
        then conversation.low_read_at
      else null end
  )
  from public.private_messages message
  join public.private_conversations conversation on conversation.id = message.conversation_id
  where message.id = message_id
    and viewer_id in (conversation.low_user_id, conversation.high_user_id)
    and app.private_message_pair_allowed(conversation.low_user_id, conversation.high_user_id)
    and app.private_message_context_allowed(conversation.low_user_id, conversation.high_user_id, message.context_kind, message.context_id)
$$;

revoke all on function app.notification_type_enabled(public.notification_preferences,text),app.queue_notification_event(text,text,text,text,text,text,jsonb,text,timestamptz),app.notification_source_readable(public.notification_events),app.private_message_context_allowed(text,text,text,uuid),app.private_message_json(uuid,text) from public,anon,authenticated;
grant execute on function app.queue_notification_event(text,text,text,text,text,text,jsonb,text,timestamptz) to service_role;
revoke all on function public.authorize_push_notification_delivery(uuid,uuid) from public,anon,authenticated;
grant execute on function public.authorize_push_notification_delivery(uuid,uuid) to service_role;
commit;
