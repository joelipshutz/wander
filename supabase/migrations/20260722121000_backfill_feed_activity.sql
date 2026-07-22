begin;

-- `feed_events` began recording only after the Feed shipped. Existing saved
-- places and lists are still valid social history, so create the one current
-- activity fact each source would have emitted at creation time. The
-- per-source/event-type guards make this safe to rerun without duplicating
-- either already-recorded new activity or an earlier backfill.
create or replace function app.backfill_feed_events()
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  insert into public.feed_events (
    actor_user_id,
    event_type,
    user_place_id,
    place_id,
    occurred_at
  )
  select
    source_place.user_id,
    case
      when source_place.source_type = 'social_save' then 'place_saved'
      when source_place.status = 'been' then 'place_been'
      else 'place_want_to_go'
    end,
    source_place.id,
    source_place.place_id,
    case
      when source_place.status = 'been'
        then coalesce(source_place.visited_at, source_place.saved_at, source_place.created_at)
      else coalesce(source_place.saved_at, source_place.created_at)
    end
  from public.user_places source_place
  where source_place.deleted_at is null
    and not exists (
      select 1
      from public.feed_events event
      where event.user_place_id = source_place.id
        and event.event_type = case
          when source_place.source_type = 'social_save' then 'place_saved'
          when source_place.status = 'been' then 'place_been'
          else 'place_want_to_go'
        end
    );

  insert into public.feed_events (
    actor_user_id,
    event_type,
    list_id,
    occurred_at
  )
  select
    list.owner_user_id,
    'list_created',
    list.id,
    list.created_at
  from public.place_lists list
  where list.deleted_at is null
    and not exists (
      select 1
      from public.feed_events event
      where event.list_id = list.id
        and event.event_type = 'list_created'
    );

  insert into public.feed_events (
    actor_user_id,
    event_type,
    user_place_id,
    place_id,
    list_id,
    list_item_id,
    occurred_at
  )
  select
    item.added_by_user_id,
    'list_item_added',
    source_place.id,
    item.place_id,
    item.list_id,
    item.id,
    item.created_at
  from public.place_list_items item
  join public.user_places source_place
    on source_place.id = coalesce(item.owner_user_place_id, item.source_user_place_id)
  where item.deleted_at is null
    and source_place.deleted_at is null
    and source_place.place_id = item.place_id
    and not exists (
      select 1
      from public.feed_events event
      where event.list_item_id = item.id
        and event.event_type = 'list_item_added'
    );
end;
$$;

revoke all on function app.backfill_feed_events() from public, anon, authenticated;

select app.backfill_feed_events();

comment on function app.backfill_feed_events() is
  'Maintains the private Feed event projection for historical source rows. Migration and privileged maintenance only.';

commit;
