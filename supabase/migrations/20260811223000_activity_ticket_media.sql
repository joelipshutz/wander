begin;

-- Return private-storage coordinates only for activity tickets the current
-- authenticated viewer may already read. The iOS client exchanges these for
-- short-lived signed URLs; this RPC never makes the visit-photos bucket public.
create or replace function public.activity_media(input_activity_ids uuid[])
returns table(activity_id uuid, media jsonb)
language sql
stable
security definer
set search_path = pg_catalog, public, app
as $$
  select
    event.id as activity_id,
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
  from public.feed_events event
  where event.id = any(coalesce(input_activity_ids, '{}'::uuid[]))
    and app.can_read_activity_event(app.current_user_id(), event.id)
  order by event.occurred_at desc, event.id desc
$$;

revoke all on function public.activity_media(uuid[]) from public, anon;
grant execute on function public.activity_media(uuid[]) to authenticated;

comment on function public.activity_media(uuid[]) is
  'Returns uploaded photo storage coordinates for visible immutable Feed tickets.';

commit;
