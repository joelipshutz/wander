begin;

-- Deploy the generic-card website reader before this storage cutover. Old public
-- artwork is retained privately; neither new clients nor old clients can publish
-- another unrestricted image. Previously downloaded external copies cannot be recalled.
-- Operational gate: purge this bucket through the Storage CDN API and verify old
-- public URLs fail. A metadata update here does not establish cache invalidation.
alter table public.share_card_previews alter column image_path drop not null;
update storage.buckets set public = false where id = 'share-card-previews';
-- Keep owner-only inserts for old-client compatibility: this bucket is now private.
drop policy "share card owner select" on storage.objects;
create policy "share card owner management" on storage.objects for select to authenticated
using (bucket_id = 'share-card-previews' and (storage.foldername(name))[1] = app.current_user_id()
  and storage.allow_any_operation(array['object.upload','object.upload_update','object.delete','object.delete_many','object.list','object.list_v2']));

create or replace function public.create_share_card_preview(input_kind text, input_identifier text,
  input_image_path text, input_title text)
returns jsonb language plpgsql volatile security definer
set search_path = public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  allowed boolean := false;
  share_token text;
begin
  if viewer_id is null or not exists (select 1 from public.profiles where id = viewer_id and deleted_at is null)
    then raise exception 'not_authenticated'; end if;
  if input_kind = 'profile' then
    allowed := exists (select 1 from public.profiles where id = input_identifier and deleted_at is null
      and (id = viewer_id or not is_private_profile) and not app.is_blocked(viewer_id, id));
  elsif input_kind = 'invite' then
    allowed := exists (select 1 from public.place_list_invites where
      token_hash = encode(extensions.digest(input_identifier, 'sha256'), 'hex')
      and created_by_user_id = viewer_id and revoked_at is null and accepted_at is null and expires_at > now());
  elsif input_identifier ~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' then
    case input_kind
      when 'place' then allowed := exists (select 1 from public.places where id = input_identifier::uuid);
      when 'list' then allowed := app.can_read_place_list(input_identifier::uuid, viewer_id);
      when 'activity' then allowed := app.can_read_activity_event(viewer_id, input_identifier::uuid);
      else allowed := false;
    end case;
  end if;
  if not coalesce(allowed, false) then raise exception 'share_target_unavailable'; end if;
  -- Lock the creator so concurrent requests cannot exceed the publication limit.
  perform 1 from public.profiles where id = viewer_id for update;
  if (select count(*) from public.share_card_previews where creator_id = viewer_id
      and created_at > now() - interval '1 day') >= 100 then raise exception 'share_limit_reached'; end if;
  share_token := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.share_card_previews(creator_id, token_hash, kind, identifier, image_path, title)
  values (viewer_id, encode(extensions.digest(share_token, 'sha256'), 'hex'), input_kind,
    input_identifier, null, 'Shared on Astir');
  return jsonb_build_object('token', share_token);
end;
$$;
revoke all on function public.create_share_card_preview(text,text,text,text) from public, anon;
grant execute on function public.create_share_card_preview(text,text,text,text) to authenticated;

create or replace function public.share_card_preview(input_token text, input_kind text, input_identifier text)
returns jsonb language sql stable security definer
set search_path = public, app, extensions
as $$
  select jsonb_build_object('preview_mode', 'generic')
  from public.share_card_previews card
  join public.profiles creator on creator.id = card.creator_id and creator.deleted_at is null
  where input_token ~ '^[a-f0-9]{48}$'
    and card.token_hash = encode(extensions.digest(input_token, 'sha256'), 'hex')
    and card.kind = input_kind and card.identifier = input_identifier
    and (card.kind <> 'invite' or exists (select 1 from public.place_list_invites invite
      where invite.token_hash = encode(extensions.digest(card.identifier, 'sha256'), 'hex')
        and invite.revoked_at is null and invite.accepted_at is null and invite.expires_at > now()));
$$;
revoke all on function public.share_card_preview(text,text,text) from public;
grant execute on function public.share_card_preview(text,text,text) to anon, authenticated;

create or replace function public.public_web_preview(
  input_kind text,
  input_identifier text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app, extensions
as $$
declare
  normalized_kind text := lower(trim(coalesce(input_kind, '')));
  normalized_identifier text := trim(coalesce(input_identifier, ''));
  result jsonb;
begin
  if normalized_kind not in ('profile', 'place', 'list', 'invite')
    or length(normalized_identifier) not between 1 and 256
  then
    return jsonb_build_object(
      'kind', normalized_kind,
      'is_available', false
    );
  end if;

  if normalized_kind = 'profile' then
    select jsonb_build_object(
      'kind', 'profile',
      'is_available', true,
      'eyebrow', 'Shared profile',
      'title', profile.display_name,
      'subtitle', '@' || profile.handle,
      'description', nullif(profile.bio, ''),
      'image_url', profile.avatar_url
    )
    into result
    from public.profiles profile
    where (
        profile.id = normalized_identifier
        or profile.search_handle = lower(normalized_identifier)
      )
      and profile.deleted_at is null
      and not profile.is_private_profile
    limit 1;

  elsif normalized_kind = 'place'
    and normalized_identifier ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  then
    select jsonb_build_object(
      'kind', 'place',
      'is_available', true,
      'eyebrow', 'Shared place',
      'title', place_row.canonical_name,
      'subtitle', concat_ws(' · ', nullif(place_row.category, ''), nullif(place_row.locality, '')),
      'description', nullif(place_row.address, ''),
      'place_id', place_row.id,
      'category', place_row.category,
      'primary_category', place_row.primary_category,
      'subcategory', place_row.subcategory,
      'category_source', place_row.category_source,
      'category_confidence', place_row.category_confidence,
      'raw_provider_type', place_row.raw_provider_type,
      'address', place_row.address,
      'locality', place_row.locality,
      'region', place_row.region,
      'country', place_row.country,
      'latitude', place_row.latitude,
      'longitude', place_row.longitude,
      'source_provider', place_row.source_provider,
      'source_provider_place_id', place_row.source_provider_place_id,
      'confidence', place_row.confidence
    )
    into result
    from public.places place_row
    where place_row.id = normalized_identifier::uuid;

  elsif normalized_kind = 'invite'
    and lower(normalized_identifier) ~ '^[a-f0-9]{48}$'
  then
    select jsonb_build_object(
      'kind', 'invite',
      'is_available', true,
      'eyebrow', 'List invitation',
      'title', 'You’re invited to a list on Astir',
      'description', 'Open Astir to review this invitation.'
    )
    into result
    from public.place_list_invites invite
    join public.place_lists list_row on list_row.id = invite.list_id
    join public.profiles owner_profile on owner_profile.id = list_row.owner_user_id
    where invite.token_hash = encode(
        extensions.digest(lower(normalized_identifier), 'sha256'),
        'hex'
      )
      and invite.accepted_at is null
      and invite.revoked_at is null
      and invite.expires_at > now()
      and list_row.deleted_at is null
      and owner_profile.deleted_at is null
      and not owner_profile.is_private_profile;
  end if;

  -- Direct list URLs are deliberately generic on the web because followers
  -- visibility is authenticated app state, not public-web visibility.
  return coalesce(
    result,
    jsonb_build_object(
      'kind', normalized_kind,
      'is_available', false
    )
  );
end;
$$;
revoke all on function public.public_web_preview(text,text) from public;
grant execute on function public.public_web_preview(text,text) to anon, authenticated;

commit;
