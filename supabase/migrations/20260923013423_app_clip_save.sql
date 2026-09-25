begin;

-- Definer is intentional: this narrow write uses the verified current caller,
-- canonical place data, and existing table/trigger contracts. It exposes no
-- private saves and never rewrites provider-owned place metadata.
create function public.save_app_clip_place(input_place_id uuid)
returns jsonb language plpgsql volatile security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  viewer public.profiles;
  venue public.places;
  existing public.user_places;
  saved public.user_places;
  visibility text;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  select * into viewer from public.profiles where id = viewer_id and deleted_at is null;
  if viewer.id is null then raise exception 'profile_not_found'; end if;
  select * into venue from public.places where id = input_place_id;
  if venue.id is null then raise exception 'place_not_found'; end if;

  -- Match app.save_own_place's lock order so concurrent full-app saves and
  -- Clip retries cannot replace one another's already-committed content.
  if venue.source_provider_place_id is not null then
    perform pg_advisory_xact_lock(hashtextextended(
      'recme:place-provider:' || viewer_id || ':' || venue.source_provider || ':' || venue.source_provider_place_id, 0));
  end if;
  perform pg_advisory_xact_lock(hashtextextended('recme:user-place:' || viewer_id || ':' || venue.id::text, 0));
  select * into existing from public.user_places
    where user_id = viewer_id and place_id = venue.id and deleted_at is null for update;
  if existing.id is not null then
    return jsonb_build_object('user_place_id', existing.id, 'place_id', venue.id, 'created', false);
  end if;
  visibility := case when viewer.is_private_profile then 'self' else viewer.default_visibility end;
  -- The canonical UUID is authoritative even for places without a provider ID.
  -- Reconstructing a provider payload through save_own_place could create a
  -- different place for these legacy records.
  insert into public.user_places(user_id, place_id, status, visibility, source_type, nearby_confirmed)
    values(viewer_id, venue.id, 'wanna_go', visibility, 'link', false)
  on conflict(user_id, place_id) do update set
    status = 'wanna_go', visibility = excluded.visibility, source_type = 'link',
    note = null, rating_signal = null, rating_score = null, nearby_confirmed = false,
    visited_at = null, saved_at = now(), source_artifact_id = null,
    source_user_place_id = null, attribution_user_id = null,
    category_override = null, subcategory_override = null, category_override_source = null,
    category_override_confidence = null, planned_date = null, deleted_at = null
  where user_places.deleted_at is not null
  returning * into saved;
  if saved.id is null then
    select * into existing from public.user_places where user_id = viewer_id and place_id = venue.id;
    return jsonb_build_object('user_place_id', existing.id, 'place_id', venue.id, 'created', false);
  end if;
  -- A restored, previously deleted snapshot starts without its old answers;
  -- immutable visits/Wanna history remain intact, as in the full-app save flow.
  delete from public.place_attributes where user_place_id = saved.id;
  return jsonb_build_object('user_place_id', saved.id, 'place_id', venue.id, 'created', true);
end;
$$;
revoke all on function public.save_app_clip_place(uuid) from public, anon;
grant execute on function public.save_app_clip_place(uuid) to authenticated;
comment on function public.save_app_clip_place(uuid) is
  'Idempotent save-to-Wanna for the authenticated Clip caller. Existing live saves and visit history remain unchanged.';
commit;
