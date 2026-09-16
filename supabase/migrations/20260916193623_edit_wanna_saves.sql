begin;

-- REC-497: edits belong to one immutable activity identity, never its place summary.
alter table public.place_wanna_saves
  add column edited_at timestamptz,
  add column is_historical_original boolean not null default false;
create unique index place_wanna_saves_original_idx
  on public.place_wanna_saves(user_place_id) where is_historical_original;

-- Preserve the existing private helper's stable/definer contract and pinned path.
create or replace function app.place_wanna_save_json(input_id uuid)
returns jsonb language sql stable security definer
set search_path = pg_catalog, public, app
as $$
  select jsonb_build_object(
    'id', wanna.id, 'owner_id', parent.user_id, 'user_place_id', parent.id,
    'occurred_at', wanna.occurred_at, 'note', wanna.note,
    'visibility', wanna.visibility, 'planned_date', wanna.planned_date,
    'attribute_answers_json', wanna.attribute_answers::text,
    'edited_at', wanna.edited_at, 'is_historical_original', wanna.is_historical_original)
  from public.place_wanna_saves wanna
  join public.user_places parent on parent.id = wanna.user_place_id
  where wanna.id = input_id
$$;
revoke all on function app.place_wanna_save_json(uuid) from public, anon, authenticated;

-- Narrow definer RPC: derive owner from JWT, lock the owner parent, and update
-- only its selected Wanna. Direct table access stays revoked and reads retain
-- event/parent/profile/block visibility checks. Edits do not create fresh activity.
create function public.update_own_place_wanna(input_user_place_id uuid, input_wanna jsonb)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  parent public.user_places;
  target public.place_wanna_saves;
  target_id uuid := (input_wanna->>'id')::uuid;
  edit_date timestamptz := (input_wanna->>'edited_at')::timestamptz;
  target_visibility text := input_wanna->>'visibility';
  historical boolean := coalesce((input_wanna->>'is_historical_original')::boolean, false);
  original_date timestamptz;
  attr jsonb;
  attr_question_definition_id uuid;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  select * into parent from public.user_places
    where id = input_user_place_id and user_id = viewer_id and deleted_at is null for update;
  if parent.id is null then raise exception 'invalid_user_place_identity'; end if;
  if jsonb_typeof(input_wanna) is distinct from 'object' or target_id is null
    or edit_date is null or edit_date > now() + interval '5 minutes'
    or target_visibility is null or target_visibility not in ('followers', 'mutuals', 'self')
    or jsonb_typeof(coalesce(input_wanna->'attribute_answers', '[]'::jsonb)) <> 'array' then
    raise exception 'invalid_wanna_payload';
  end if;
  if (select is_private_profile from public.profiles where id = viewer_id) then
    target_visibility := 'self';
  end if;
  if historical then
    select * into target from public.place_wanna_saves
      where user_place_id = parent.id and is_historical_original;
    if target.id is null then
      if parent.historical_wanted_at is null then raise exception 'invalid_historical_wanna'; end if;
      -- Reuse the original event so its likes, comments and date survive editing.
      select event.id, event.occurred_at into target_id, original_date
      from public.feed_events event
      where event.user_place_id = parent.id and event.actor_user_id = viewer_id
        and event.event_type = 'place_want_to_go' and event.visit_id is null
        and not exists(select 1 from public.place_wanna_saves w where w.id = event.id)
      order by event.occurred_at, event.id limit 1;
      if target_id is null then
        target_id := (input_wanna->>'id')::uuid;
        original_date := parent.historical_wanted_at;
        insert into public.feed_events(id, actor_user_id, event_type, user_place_id, place_id, occurred_at)
          values(target_id, viewer_id, 'place_want_to_go', parent.id, parent.place_id, original_date);
      end if;
      insert into public.place_wanna_saves(id, user_place_id, visibility, occurred_at, is_historical_original)
        values(target_id, parent.id, target_visibility, original_date, true)
        returning * into target;
    end if;
  else
    select * into target from public.place_wanna_saves
      where id = target_id and user_place_id = parent.id and not is_historical_original;
    if target.id is null then raise exception 'invalid_wanna_identity'; end if;
  end if;
  -- A replay or older in-flight edit must not overwrite a newer saved revision.
  if target.edited_at is null or target.edited_at < edit_date then
    update public.place_wanna_saves set note = nullif(input_wanna->>'note', ''),
      visibility = target_visibility, planned_date = (input_wanna->>'planned_date')::date,
      attribute_answers = coalesce(input_wanna->'attribute_answers', '[]'::jsonb), edited_at = edit_date
      where id = target.id;
    if target.is_historical_original and parent.status = 'wanna_go' then
      select * into target from public.place_wanna_saves where id = target.id;
      update public.user_places
      set note = target.note, visibility = target.visibility,
          planned_date = target.planned_date, updated_at = now()
      where id = parent.id and user_id = viewer_id and deleted_at is null;

      delete from public.place_attributes
      where user_place_id = parent.id;

      for attr in
        select value
        from jsonb_array_elements(
          target.attribute_answers
        ) as value
      loop
        select qd.id
        into attr_question_definition_id
        from public.question_definitions qd
        where qd.question_key = nullif(attr->>'question_key', '')
          and (qd.owner_user_id = parent.user_id or qd.is_system)
        order by (qd.owner_user_id = parent.user_id) desc, qd.is_system desc
        limit 1;

        if nullif(attr->>'question_key', '') is not null
          and nullif(attr->>'value_type', '') is not null
          and attr ? 'value'
          and attr->'value' <> 'null'::jsonb then
          insert into public.place_attributes (
            user_place_id,
            question_definition_id,
            question_key,
            value_type,
            value
          )
          values (
            parent.id,
            attr_question_definition_id,
            attr->>'question_key',
            attr->>'value_type',
            attr->'value'
          )
          on conflict (user_place_id, question_key)
          do update set
            question_definition_id = excluded.question_definition_id,
            value_type = excluded.value_type,
            value = excluded.value,
            updated_at = now();
        end if;
      end loop;
    end if;
  end if;
  return app.place_wanna_save_json(target.id);
end;
$$;
revoke all on function public.update_own_place_wanna(uuid,jsonb) from public, anon;
grant execute on function public.update_own_place_wanna(uuid,jsonb) to authenticated;

-- Historical Wanna content is served through visibility-filtered event RPCs.
-- These legacy raw columns otherwise remain readable with the check-in parent's
-- broader visibility. No current client reads them through the Data API.
revoke select (historical_want_note, historical_want_tags, historical_wanted_at)
  on public.user_places from authenticated;

-- Preserve the existing trigger's volatile/definer contract, pinned path and
-- private execute grants. Both hard- and soft-delete triggers use this function;
-- the still-has-visits and never-had-a-Wanna paths remain unchanged.
create or replace function app.sync_user_place_after_place_visit_delete()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  parent public.user_places;
  latest_visit public.place_visits;
  original_wanna public.place_wanna_saves;
  attr jsonb;
  attr_question_definition_id uuid;
begin
  select *
  into latest_visit
  from public.place_visits pv
  where pv.user_place_id = old.user_place_id
    and pv.deleted_at is null
  order by pv.visited_at desc, pv.created_at desc, pv.id desc
  limit 1;

  if latest_visit.id is not null then
    update public.user_places
    set status = 'been',
        note = latest_visit.note,
        rating_score = latest_visit.rating_score,
        visited_at = latest_visit.visited_at,
        deleted_at = null,
        updated_at = now()
    where id = old.user_place_id;

    delete from public.place_attributes
    where user_place_id = old.user_place_id;

    for attr in
      select value
      from jsonb_array_elements(
        coalesce(latest_visit.attribute_answers, '[]'::jsonb)
      ) as value
    loop
      select qd.id
      into attr_question_definition_id
      from public.question_definitions qd
      join public.user_places up on up.id = old.user_place_id
      where qd.question_key = nullif(attr->>'question_key', '')
        and (qd.owner_user_id = up.user_id or qd.is_system)
      order by (qd.owner_user_id = up.user_id) desc, qd.is_system desc
      limit 1;

      if nullif(attr->>'question_key', '') is not null
        and nullif(attr->>'value_type', '') is not null
        and attr ? 'value'
        and attr->'value' <> 'null'::jsonb then
        insert into public.place_attributes (
          user_place_id,
          question_definition_id,
          question_key,
          value_type,
          value
        )
        values (
          old.user_place_id,
          attr_question_definition_id,
          attr->>'question_key',
          attr->>'value_type',
          attr->'value'
        )
        on conflict (user_place_id, question_key)
        do update set
          question_definition_id = excluded.question_definition_id,
          value_type = excluded.value_type,
          value = excluded.value,
          updated_at = now();
      end if;
    end loop;

    return old;
  end if;

  select *
  into parent
  from public.user_places
  where id = old.user_place_id
  for update;

  if parent.id is null then
    return old;
  end if;

  -- An edited original Wanna owns its privacy and content independently of
  -- the check-in summary. Restore that canonical event after the last visit.
  select * into original_wanna from public.place_wanna_saves
  where user_place_id = parent.id and is_historical_original;

  if parent.historical_wanted_at is not null or original_wanna.id is not null then
    update public.user_places
    set status = 'wanna_go',
        note = case when original_wanna.id is not null then original_wanna.note else parent.historical_want_note end,
        visibility = case when original_wanna.id is not null then original_wanna.visibility else parent.visibility end,
        rating_signal = null,
        rating_score = null,
        visited_at = null,
        saved_at = case when original_wanna.id is not null then original_wanna.occurred_at else parent.historical_wanted_at end,
        planned_date = original_wanna.planned_date,
        deleted_at = null,
        historical_want_note = null,
        historical_want_attribute_answers = null,
        historical_want_tags = null,
        historical_wanted_at = null,
        updated_at = now()
    where id = parent.id;

    delete from public.place_attributes
    where user_place_id = parent.id;

    for attr in
      select value
      from jsonb_array_elements(
        case when original_wanna.id is not null then original_wanna.attribute_answers
          else coalesce(parent.historical_want_attribute_answers, '[]'::jsonb) end
      ) as value
    loop
      select qd.id
      into attr_question_definition_id
      from public.question_definitions qd
      where qd.question_key = nullif(attr->>'question_key', '')
        and (qd.owner_user_id = parent.user_id or qd.is_system)
      order by (qd.owner_user_id = parent.user_id) desc, qd.is_system desc
      limit 1;

      if nullif(attr->>'question_key', '') is not null
        and nullif(attr->>'value_type', '') is not null
        and attr ? 'value'
        and attr->'value' <> 'null'::jsonb then
        insert into public.place_attributes (
          user_place_id,
          question_definition_id,
          question_key,
          value_type,
          value
        )
        values (
          parent.id,
          attr_question_definition_id,
          attr->>'question_key',
          attr->>'value_type',
          attr->'value'
        )
        on conflict (user_place_id, question_key)
        do update set
          question_definition_id = excluded.question_definition_id,
          value_type = excluded.value_type,
          value = excluded.value,
          updated_at = now();
      end if;
    end loop;
  else
    update public.user_places
    set deleted_at = coalesce(deleted_at, now()),
        rating_score = null,
        visited_at = null,
        updated_at = now()
    where id = parent.id
      and status = 'been';
  end if;

  return old;
end;
$$;

revoke all on function app.sync_user_place_after_place_visit_delete()
  from public, anon, authenticated;


commit;
