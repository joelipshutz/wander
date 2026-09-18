begin;

-- REC-540: immutable deletion identities prevent a delayed create retry from
-- recreating a removed Wanna. Private table: RPCs derive ownership from JWT.
create table app.deleted_place_wannas (
  id uuid primary key,
  user_place_id uuid not null references public.user_places(id) on delete cascade,
  deleted_at timestamptz not null default now()
);
alter table app.deleted_place_wannas enable row level security;
revoke all on app.deleted_place_wannas from public, anon, authenticated;

create function app.reject_deleted_wanna_event()
returns trigger language plpgsql security definer
set search_path = pg_catalog, public, app
as $$
begin
  if exists (select 1 from app.deleted_place_wannas where id = new.id) then
    raise exception 'wanna_deleted';
  end if;
  return new;
end;
$$;
revoke all on function app.reject_deleted_wanna_event() from public, anon, authenticated;
create trigger feed_events_reject_deleted_wanna
  before insert on public.feed_events for each row
  execute function app.reject_deleted_wanna_event();

-- Definer is intentional: clients have no direct event-table write access.
-- Lock the authenticated owner's parent, scope every deletion to that parent,
-- and retain the place while any independent visit, Wanna or list uses it.
create function public.delete_own_place_wanna(
  input_user_place_id uuid, input_wanna_id uuid, input_historical_original boolean default false
)
returns boolean language plpgsql security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  parent public.user_places;
  target_id uuid;
  survivor public.place_wanna_saves;
  attr jsonb;
  attr_definition_id uuid;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  select * into parent from public.user_places
    where id = input_user_place_id and user_id = viewer_id for update;
  if parent.id is null then raise exception 'invalid_user_place_identity'; end if;
  if input_wanna_id is null then raise exception 'invalid_wanna_identity'; end if;
  if exists (select 1 from public.feed_events where id = input_wanna_id
      and (user_place_id is distinct from parent.id or actor_user_id <> viewer_id))
    or exists (select 1 from app.deleted_place_wannas where id = input_wanna_id and user_place_id <> parent.id) then
    raise exception 'wanna_identity_conflict';
  end if;
  if input_historical_original and exists (select 1 from public.feed_events where id = input_wanna_id
      and event_type <> 'place_want_to_go') then raise exception 'invalid_wanna_identity'; end if;
  if exists (select 1 from app.deleted_place_wannas where id = input_wanna_id and user_place_id = parent.id) then
    return true;
  end if;
  if input_historical_original then
    -- The original predates independent Wanna rows on older clients. Delete
    -- only original Wanna events, never check-ins or independent repeat IDs.
    for target_id in
      select event.id from public.feed_events event
      left join public.place_wanna_saves wanna on wanna.id = event.id
      where event.user_place_id = parent.id and event.actor_user_id = viewer_id
        and event.event_type = 'place_want_to_go'
        and (wanna.id is null or wanna.is_historical_original)
    loop
      insert into app.deleted_place_wannas(id, user_place_id) values(target_id, parent.id) on conflict do nothing;
      delete from public.feed_events where id = target_id;
    end loop;
    insert into app.deleted_place_wannas(id, user_place_id) values(input_wanna_id, parent.id) on conflict do nothing;
    update public.user_places set historical_want_note = null,
      historical_want_attribute_answers = null, historical_want_tags = null,
      historical_wanted_at = null, updated_at = now() where id = parent.id;
    if parent.status = 'wanna_go' then
      update public.user_places set note = null, planned_date = null,
        rating_signal = null, rating_score = null, updated_at = now() where id = parent.id;
      delete from public.place_attributes where user_place_id = parent.id;
    end if;
  else
    if exists (select 1 from public.feed_events where id = input_wanna_id)
      and not exists (select 1 from public.place_wanna_saves
        where id = input_wanna_id and user_place_id = parent.id and not is_historical_original) then
      raise exception 'invalid_wanna_identity';
    end if;
    insert into app.deleted_place_wannas(id, user_place_id) values(input_wanna_id, parent.id) on conflict do nothing;
    delete from public.feed_events where id = input_wanna_id and user_place_id = parent.id;
  end if;
  -- A replacement Wanna can be the remaining action on a Wanna-only parent.
  -- Restore that event's own content instead of retaining deleted metadata.
  if parent.status = 'wanna_go' then
    select * into survivor from public.place_wanna_saves where user_place_id = parent.id
      order by is_historical_original desc, occurred_at desc, id limit 1;
    if survivor.id is not null then
      update public.user_places set note = survivor.note, visibility = survivor.visibility,
        planned_date = survivor.planned_date, saved_at = survivor.occurred_at,
        rating_signal = null, rating_score = null, updated_at = now() where id = parent.id;
      delete from public.place_attributes where user_place_id = parent.id;
      for attr in select value from jsonb_array_elements(survivor.attribute_answers) loop
        select qd.id into attr_definition_id from public.question_definitions qd
          where qd.question_key = nullif(attr->>'question_key','') and (qd.owner_user_id = viewer_id or qd.is_system)
          order by (qd.owner_user_id = viewer_id) desc, qd.is_system desc limit 1;
        if nullif(attr->>'question_key','') is not null and nullif(attr->>'value_type','') is not null
          and attr ? 'value' and attr->'value' <> 'null'::jsonb then
          insert into public.place_attributes(user_place_id, question_definition_id, question_key, value_type, value)
            values(parent.id, attr_definition_id, attr->>'question_key', attr->>'value_type', attr->'value')
            on conflict(user_place_id, question_key) do update set question_definition_id=excluded.question_definition_id,
              value_type=excluded.value_type, value=excluded.value, updated_at=now();
        end if;
      end loop;
    elsif not exists(select 1 from public.feed_events where user_place_id=parent.id and event_type='place_want_to_go') then
      update public.user_places set note=null, planned_date=null, rating_signal=null, rating_score=null, updated_at=now()
        where id=parent.id;
      delete from public.place_attributes where user_place_id=parent.id;
    end if;
  end if;
  if not exists (select 1 from public.place_visits where user_place_id = parent.id and deleted_at is null)
    and not exists (select 1 from public.place_wanna_saves where user_place_id = parent.id)
    and not exists (select 1 from public.place_list_items where deleted_at is null
      and (owner_user_place_id = parent.id or source_user_place_id = parent.id))
    and not exists (select 1 from public.feed_events event where event.user_place_id = parent.id
      and event.event_type = 'place_want_to_go') then
    update public.user_places set deleted_at = coalesce(deleted_at, now()), updated_at = now()
      where id = parent.id;
  end if;
  return true;
end;
$$;
revoke all on function public.delete_own_place_wanna(uuid, uuid, boolean) from public, anon;
grant execute on function public.delete_own_place_wanna(uuid, uuid, boolean) to authenticated;

-- Preserve the existing trigger's volatile/definer contract, search_path and
-- private grants. Restore an independent Wanna after the last visit, or retain
-- a metadata-free companion bookmark while list memberships still need it.
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
  where user_place_id = parent.id and (is_historical_original or parent.historical_wanted_at is null)
  order by is_historical_original desc, occurred_at desc, id limit 1;

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
  elsif exists (select 1 from public.place_list_items where deleted_at is null
    and (owner_user_place_id = parent.id or source_user_place_id = parent.id)) then
    update public.user_places set status = 'wanna_go', note = null, rating_signal = null,
      rating_score = null, visited_at = null, planned_date = null, deleted_at = null,
      historical_want_note = null, historical_want_attribute_answers = null,
      historical_want_tags = null, historical_wanted_at = null, updated_at = now()
      where id = parent.id;
    delete from public.place_attributes where user_place_id = parent.id;
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
