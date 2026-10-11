begin;
-- REVIEW DRAFT: not a migration and not applied to hosted Supabase.
-- Package through the migration CLI before deployment; SQL regression/hosted smoke remain unverified.



-- REC-636: private, contextual, mutual-friends-only 1:1 messaging.
-- No prior messaging RPCs exist. Existing auth, visibility and graph helpers
-- are reused without replacement. Tables have RLS with no client policies or
-- grants. The narrow definer RPCs below are the only client access path; each
-- derives the caller from app.current_user_id() and rechecks current access.
-- No message content is copied into analytics, push, public storage, or Feed.
create table public.private_conversations (
  id uuid primary key default gen_random_uuid(),
  low_user_id text not null references public.profiles(id) on delete cascade,
  high_user_id text not null references public.profiles(id) on delete cascade,
  created_by text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  low_read_sent_at timestamptz,
  low_read_message_id uuid,
  low_read_at timestamptz,
  high_read_sent_at timestamptz,
  high_read_message_id uuid,
  high_read_at timestamptz,
  unique (low_user_id, high_user_id),
  check (low_user_id < high_user_id),
  check (created_by in (low_user_id, high_user_id)),
  check ((low_read_sent_at is null) = (low_read_message_id is null)),
  check ((high_read_sent_at is null) = (high_read_message_id is null))
);
create index private_conversations_low_updated_idx on public.private_conversations(low_user_id, updated_at desc, id desc);
create index private_conversations_high_updated_idx on public.private_conversations(high_user_id, updated_at desc, id desc);
create index private_conversations_creator_idx on public.private_conversations(created_by, created_at desc);

create table public.private_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.private_conversations(id) on delete cascade,
  sender_id text not null references public.profiles(id) on delete cascade,
  client_id uuid not null,
  body text not null check (char_length(body) between 1 and 2000 and body = btrim(body, E' \t\n\r') and body !~ '^[[:space:]]*$'),
  sent_at timestamptz not null default clock_timestamp(),
  context_kind text check (context_kind in ('activity', 'place')),
  -- No copied source text and no FK cascade: access is resolved afresh and a
  -- revoked/deleted context suppresses its message, including inbox previews.
  context_id uuid,
  unique(sender_id, client_id),
  check ((context_kind is null) = (context_id is null))
);
create index private_messages_history_idx on public.private_messages(conversation_id, sent_at desc, id desc);
create index private_messages_sender_rate_idx on public.private_messages(sender_id, sent_at desc);

alter table public.private_conversations enable row level security;
alter table public.private_messages enable row level security;
revoke all on table public.private_conversations, public.private_messages from public, anon, authenticated;

create function app.private_message_pair_allowed(first_user text, second_user text)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select first_user is not null and second_user is not null
    and first_user <> second_user
    and exists(select 1 from public.profiles where id = first_user and deleted_at is null)
    and exists(select 1 from public.profiles where id = second_user and deleted_at is null)
    and not app.is_blocked(first_user, second_user)
    and app.is_mutual(first_user, second_user)
$$;

create function app.private_message_context_allowed(first_user text, second_user text, source_kind text, source_id uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select case
    when source_kind is null and source_id is null then true
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

create function app.private_message_json(message_id uuid, viewer_id text)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object(
    'id', message.id, 'conversationID', message.conversation_id,
    'senderID', message.sender_id, 'clientID', message.client_id,
    'body', message.body, 'sentAt', message.sent_at,
    'context', case when message.context_kind is null then null else jsonb_build_object(
      'kind', message.context_kind, 'id', message.context_id,
      'title', case when message.context_kind = 'place' then
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

create function app.private_conversation_json(conversation_id uuid, viewer_id text)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object(
    'id', conversation.id,
    'participant', jsonb_build_object('id', other.id, 'displayName', other.display_name,
      'handle', other.handle, 'avatarURL', other.avatar_url),
    'updatedAt', conversation.updated_at,
    'lastMessageAt', latest.sent_at, 'lastMessagePreview', left(latest.body, 160),
    'unreadCount', (select count(*) from public.private_messages unread
      where unread.conversation_id = conversation.id and unread.sender_id <> viewer_id
        and (case when viewer_id = conversation.low_user_id then
          conversation.low_read_sent_at is null or (unread.sent_at, unread.id) > (conversation.low_read_sent_at, conversation.low_read_message_id)
        else conversation.high_read_sent_at is null or (unread.sent_at, unread.id) > (conversation.high_read_sent_at, conversation.high_read_message_id) end)
        and app.private_message_context_allowed(conversation.low_user_id, conversation.high_user_id, unread.context_kind, unread.context_id))
  )
  from public.private_conversations conversation
  join public.profiles other on other.id = case when viewer_id = conversation.low_user_id then conversation.high_user_id else conversation.low_user_id end
  left join lateral (select message.sent_at, message.body from public.private_messages message
    where message.conversation_id = conversation.id
      and app.private_message_context_allowed(conversation.low_user_id, conversation.high_user_id, message.context_kind, message.context_id)
    order by message.sent_at desc, message.id desc limit 1) latest on true
  where conversation.id = conversation_id
    and viewer_id in (conversation.low_user_id, conversation.high_user_id)
    and app.private_message_pair_allowed(conversation.low_user_id, conversation.high_user_id)
$$;

create function public.private_message_conversation(input_conversation_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, app
as $$
declare payload jsonb;
begin
  payload := app.private_conversation_json(input_conversation_id, app.current_user_id());
  if payload is null then raise exception 'private_message_unavailable'; end if;
  return payload;
end;
$$;

create function public.private_message_start(input_recipient_id text, input_context_kind text, input_context_id uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare viewer text := app.current_user_id(); thread_id uuid;
begin
  if not app.private_message_pair_allowed(viewer, input_recipient_id)
    or input_context_kind is null or input_context_id is null
    or not app.private_message_context_allowed(viewer, input_recipient_id, input_context_kind, input_context_id)
  then raise exception 'private_message_unavailable'; end if;
  perform pg_advisory_xact_lock(hashtextextended('private-message:' || viewer, 0));
  select id into thread_id from public.private_conversations
    where low_user_id = least(viewer, input_recipient_id) and high_user_id = greatest(viewer, input_recipient_id);
  if thread_id is null then
    if (select count(*) from public.private_conversations where created_by = viewer and created_at > clock_timestamp() - interval '1 day') >= 50
    then raise exception 'private_message_rate_limited'; end if;
    insert into public.private_conversations(low_user_id, high_user_id, created_by)
      values(least(viewer, input_recipient_id), greatest(viewer, input_recipient_id), viewer)
      on conflict(low_user_id, high_user_id) do nothing;
    select id into thread_id from public.private_conversations
      where low_user_id = least(viewer, input_recipient_id) and high_user_id = greatest(viewer, input_recipient_id);
  end if;
  return public.private_message_conversation(thread_id);
end;
$$;

create function public.private_message_inbox(input_before_at timestamptz default null, input_before_id uuid default null, input_limit integer default 20)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, app
as $$
declare viewer text := app.current_user_id(); page_limit integer := least(greatest(coalesce(input_limit,20),1),50); payload jsonb;
begin
  if viewer is null or not exists(select 1 from public.profiles where id = viewer and deleted_at is null)
  then raise exception 'private_message_unavailable'; end if;
  if (input_before_at is null) <> (input_before_id is null)
  then raise exception 'private_message_invalid_cursor'; end if;
  with candidates as materialized (
    select conversation.id, conversation.updated_at from public.private_conversations conversation
    where viewer in (conversation.low_user_id, conversation.high_user_id)
      and app.private_message_pair_allowed(conversation.low_user_id, conversation.high_user_id)
      and exists (select 1 from public.private_messages visible where visible.conversation_id = conversation.id
        and app.private_message_context_allowed(conversation.low_user_id,conversation.high_user_id,visible.context_kind,visible.context_id))
      and (input_before_at is null or (conversation.updated_at, conversation.id) < (input_before_at, input_before_id))
    order by conversation.updated_at desc, conversation.id desc limit page_limit + 1
  ), page as materialized (select * from candidates order by updated_at desc, id desc limit page_limit)
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(app.private_conversation_json(id,viewer) order by updated_at desc,id desc) from page),'[]'::jsonb),
    'nextCursor', case when (select count(*) from candidates) > page_limit then
      (select jsonb_build_object('timestamp',updated_at,'id',id) from page order by updated_at,id limit 1) else null end
  ) into payload;
  return payload;
end;
$$;

create function public.private_message_history(input_conversation_id uuid, input_before_at timestamptz default null, input_before_id uuid default null, input_limit integer default 30)
returns jsonb language plpgsql stable security definer
set search_path = pg_catalog, public, app
as $$
declare viewer text := app.current_user_id(); thread public.private_conversations; page_limit integer := least(greatest(coalesce(input_limit,30),1),50); payload jsonb;
begin
  perform public.private_message_conversation(input_conversation_id);
  select * into strict thread from public.private_conversations where id = input_conversation_id;
  if (input_before_at is null) <> (input_before_id is null) or (input_before_id is not null and not exists (
    select 1 from public.private_messages where id = input_before_id and conversation_id = input_conversation_id and sent_at = input_before_at))
  then raise exception 'private_message_invalid_cursor'; end if;
  with candidates as materialized (
    select message.id, message.sent_at from public.private_messages message
    where message.conversation_id = input_conversation_id
      and app.private_message_context_allowed(thread.low_user_id,thread.high_user_id,message.context_kind,message.context_id)
      and (input_before_at is null or (message.sent_at,message.id) < (input_before_at,input_before_id))
    order by message.sent_at desc,message.id desc limit page_limit + 1
  ), page as materialized (select * from candidates order by sent_at desc,id desc limit page_limit)
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(app.private_message_json(id,viewer) order by sent_at desc,id desc) from page),'[]'::jsonb),
    'nextCursor', case when (select count(*) from candidates) > page_limit then
      (select jsonb_build_object('timestamp',sent_at,'id',id) from page order by sent_at,id limit 1) else null end
  ) into payload;
  return payload;
end;
$$;

create function public.private_message_send(input_conversation_id uuid, input_body text, input_client_id uuid, input_context_kind text default null, input_context_id uuid default null)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare viewer text := app.current_user_id(); thread public.private_conversations; prior public.private_messages;
  normalized_body text := btrim(input_body,E' \t\n\r'); source_id uuid := input_context_id; message_id uuid;
begin
  perform public.private_message_conversation(input_conversation_id);
  if normalized_body is null or char_length(normalized_body) not between 1 and 2000 or normalized_body ~ '^[[:space:]]*$'
  then raise exception 'private_message_invalid_body'; end if;
  if input_client_id is null then raise exception 'private_message_unavailable'; end if;
  perform pg_advisory_xact_lock(hashtextextended('private-message:' || viewer,0));
  select * into strict thread from public.private_conversations where id = input_conversation_id for update;
  -- Recheck after waiting for a lock, before idempotent acknowledgment or write.
  if not app.private_message_pair_allowed(thread.low_user_id,thread.high_user_id)
    or not app.private_message_context_allowed(thread.low_user_id,thread.high_user_id,input_context_kind,source_id)
  then raise exception 'private_message_unavailable'; end if;
  if input_context_kind = 'activity' then source_id := app.canonical_activity_id(source_id); end if;
  select * into prior from public.private_messages where sender_id = viewer and client_id = input_client_id;
  if found then
    if prior.conversation_id <> input_conversation_id or prior.body <> normalized_body
      or prior.context_kind is distinct from input_context_kind or prior.context_id is distinct from source_id
    then raise exception 'private_message_idempotency_conflict'; end if;
    return app.private_message_json(prior.id, viewer);
  end if;
  -- Sender lock serializes quota checks across all their conversations. A retry
  -- is acknowledged before quota evaluation and does not consume another send.
  if (select count(*) from public.private_messages where sender_id = viewer and sent_at > clock_timestamp()-interval '1 minute') >= 20
    or (select count(*) from public.private_messages where sender_id = viewer and sent_at > clock_timestamp()-interval '1 day') >= 200
  then raise exception 'private_message_rate_limited'; end if;
  insert into public.private_messages(conversation_id,sender_id,client_id,body,context_kind,context_id)
    values(input_conversation_id,viewer,input_client_id,normalized_body,input_context_kind,source_id) returning id into message_id;
  update public.private_conversations set updated_at = (select sent_at from public.private_messages where id = message_id)
    where id = input_conversation_id;
  return app.private_message_json(message_id,viewer);
end;
$$;

create function public.private_message_mark_read(input_conversation_id uuid, input_through_message_id uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare viewer text := app.current_user_id(); thread public.private_conversations; target public.private_messages;
begin
  perform public.private_message_conversation(input_conversation_id);
  select * into strict thread from public.private_conversations where id = input_conversation_id for update;
  if not app.private_message_pair_allowed(thread.low_user_id,thread.high_user_id)
  then raise exception 'private_message_unavailable'; end if;
  select * into target from public.private_messages where id = input_through_message_id and conversation_id = input_conversation_id;
  if not found or not app.private_message_context_allowed(thread.low_user_id,thread.high_user_id,target.context_kind,target.context_id)
  then raise exception 'private_message_unavailable'; end if;
  if viewer = thread.low_user_id then
    update public.private_conversations set low_read_sent_at = target.sent_at, low_read_message_id = target.id, low_read_at = clock_timestamp()
      where id = thread.id and (low_read_sent_at is null or (low_read_sent_at,low_read_message_id) < (target.sent_at,target.id));
  else
    update public.private_conversations set high_read_sent_at = target.sent_at, high_read_message_id = target.id, high_read_at = clock_timestamp()
      where id = thread.id and (high_read_sent_at is null or (high_read_sent_at,high_read_message_id) < (target.sent_at,target.id));
  end if;
  return '{}'::jsonb;
end;
$$;

-- Private helpers have no client execute grants. API definer posture is
-- intentional: clients have no direct table rights and cannot supply actor IDs.
revoke all on function app.private_message_pair_allowed(text,text), app.private_message_context_allowed(text,text,text,uuid),
  app.private_message_json(uuid,text), app.private_conversation_json(uuid,text) from public, anon, authenticated;
revoke all on function public.private_message_conversation(uuid), public.private_message_start(text,text,uuid),
  public.private_message_inbox(timestamptz,uuid,integer), public.private_message_history(uuid,timestamptz,uuid,integer),
  public.private_message_send(uuid,text,uuid,text,uuid), public.private_message_mark_read(uuid,uuid) from public, anon, authenticated;
grant execute on function public.private_message_conversation(uuid), public.private_message_start(text,text,uuid),
  public.private_message_inbox(timestamptz,uuid,integer), public.private_message_history(uuid,timestamptz,uuid,integer),
  public.private_message_send(uuid,text,uuid,text,uuid), public.private_message_mark_read(uuid,uuid) to authenticated;

-- Extend, preserving every existing registered key and integer range from
-- 20260924013000_notification_reprompt_campaign.sql. Existing flag RLS and grants
-- are unchanged. Activation uses the app's frozen full-launch flag snapshot.
alter table public.feature_flags drop constraint feature_flags_registered_key_check, drop constraint feature_flags_key_value_contract_check;
alter table public.feature_flags
  add constraint feature_flags_registered_key_check check (key in (
    'first_visit_nux','debug_settings','place_profile_save_tray_v1','semantic_place_search_v1',
    'social_import_apify_gemini_v1','place_profile_action_variant','profile_feedback_v1',
    'notification_reprompt_campaign','unified_live_v1'
  )),
  add constraint feature_flags_key_value_contract_check check (
    (key in ('first_visit_nux','debug_settings','place_profile_save_tray_v1','semantic_place_search_v1',
      'social_import_apify_gemini_v1','profile_feedback_v1','unified_live_v1') and value_type = 'boolean' and integer_value is null)
    or (key = 'place_profile_action_variant' and value_type = 'integer' and integer_value is not null and integer_value between 1 and 5)
    or (key = 'notification_reprompt_campaign' and value_type = 'integer' and integer_value is not null and integer_value between 0 and 1000000)
  );
insert into public.feature_flags(key,user_id,enabled,value_type,integer_value)
values('unified_live_v1',null,false,'boolean',null)
on conflict (key) where user_id is null do nothing;

notify pgrst, 'reload schema';
commit;
