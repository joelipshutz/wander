begin;

-- REC-647: explicit sharing publishes an intentional copy, not a public source
-- grant. Never reopen the legacy private buckets. Build 184 still validates
-- tokens through the unchanged share_card_preview / generic-mode handshake.
alter table public.share_card_previews
  add column snapshot_version integer check (snapshot_version = 1),
  add column description text check (char_length(description) <= 500);

-- Definer helpers are required because source/card tables are not enumerable.
-- Identity is always the verified claim; there is no caller-supplied owner ID.
create function app.can_publish_own_share_snapshot(input_kind text, input_identifier text)
returns boolean language plpgsql stable security definer
set search_path = public, app, extensions
as $$
declare viewer_id text := app.current_user_id();
begin
  if viewer_id is null or not exists (select 1 from public.profiles
    where id = viewer_id and deleted_at is null) then return false; end if;
  if input_kind = 'profile' then return input_identifier = viewer_id;
  elsif input_kind = 'invite' then
    return exists (select 1 from public.place_list_invites i
      join public.place_lists l on l.id = i.list_id
      where i.token_hash = encode(extensions.digest(input_identifier, 'sha256'), 'hex')
        and i.created_by_user_id = viewer_id and l.owner_user_id = viewer_id
        and l.deleted_at is null and i.revoked_at is null and i.accepted_at is null and i.expires_at > now());
  elsif input_identifier ~* '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' then
    case input_kind
      when 'place' then return exists (select 1 from public.places where id = input_identifier::uuid);
      when 'list' then return exists (select 1 from public.place_lists
        where id = input_identifier::uuid and owner_user_id = viewer_id and deleted_at is null);
      when 'activity' then return exists (select 1 from public.feed_events
        where id = input_identifier::uuid and actor_user_id = viewer_id)
        and app.can_read_activity_event(viewer_id, input_identifier::uuid);
      else return false;
    end case;
  end if;
  return false;
end;
$$;
revoke all on function app.can_publish_own_share_snapshot(text,text) from public, anon;
grant execute on function app.can_publish_own_share_snapshot(text,text) to authenticated;

create function app.can_upload_share_snapshot(input_path text)
returns boolean language sql stable security definer
set search_path = public, app, extensions
as $$
  select exists (select 1 from public.share_card_previews c
    where c.creator_id = app.current_user_id()
      and input_path = c.creator_id || '/' || c.id::text || '/preview.png'
      and c.snapshot_version is null and c.created_at > now() - interval '15 minutes'
      and app.can_publish_own_share_snapshot(c.kind, c.identifier));
$$;
revoke all on function app.can_upload_share_snapshot(text) from public, anon;
grant execute on function app.can_upload_share_snapshot(text) to authenticated;

-- This new namespace contains only deliberate exports. Object names are issued
-- for an authorized pending share; uploads cannot overwrite another snapshot.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('shared-link-snapshots','shared-link-snapshots',true,5242880,array['image/png']);
create policy "explicit share snapshot insert" on storage.objects for insert to authenticated
with check (bucket_id = 'shared-link-snapshots' and app.can_upload_share_snapshot(name));
create policy "explicit share snapshot owner read" on storage.objects for select to authenticated
using (bucket_id = 'shared-link-snapshots' and (storage.foldername(name))[1] = app.current_user_id());
create policy "explicit share snapshot owner delete" on storage.objects for delete to authenticated
using (bucket_id = 'shared-link-snapshots' and (storage.foldername(name))[1] = app.current_user_id());

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
  return jsonb_build_object('token', share_token, 'snapshot_path',
    case when app.can_publish_own_share_snapshot(input_kind, input_identifier) then
      (select creator_id || '/' || id::text || '/preview.png' from public.share_card_previews
       where token_hash = encode(extensions.digest(share_token, 'sha256'), 'hex')) end);
end;
$$;
revoke all on function public.create_share_card_preview(text,text,text,text) from public, anon;
grant execute on function public.create_share_card_preview(text,text,text,text) to authenticated;


-- Finalize only the creator's pending authorized copy. Recheck after rendering
-- and upload: ownership, source access or an invitation may have changed.
create function public.publish_share_card_snapshot(input_token text, input_kind text,
  input_identifier text, input_image_path text, input_title text, input_description text)
returns jsonb language plpgsql volatile security definer
set search_path = public, app, extensions
as $$
declare card public.share_card_previews;
begin
  select * into card from public.share_card_previews c
    where c.token_hash = encode(extensions.digest(input_token, 'sha256'), 'hex')
      and c.creator_id = app.current_user_id() and c.kind = input_kind and c.identifier = input_identifier
      and input_token ~ '^[a-f0-9]{48}$' for update;
  if not found or not app.can_publish_own_share_snapshot(input_kind,input_identifier) then
    raise exception 'share_target_unavailable'; end if;
  if input_image_path is distinct from card.creator_id || '/' || card.id::text || '/preview.png'
    or not exists (select 1 from storage.objects where bucket_id = 'shared-link-snapshots' and name = input_image_path)
    then raise exception 'share_artwork_unavailable'; end if;
  if input_title is null or char_length(trim(input_title)) not between 1 and 500
    or char_length(coalesce(input_description,'')) > 500 then raise exception 'invalid_share_card'; end if;
  if card.snapshot_version = 1 then
    if card.image_path is distinct from input_image_path or card.title is distinct from trim(input_title)
      or card.description is distinct from coalesce(input_description,'') then raise exception 'share_snapshot_immutable'; end if;
    return jsonb_build_object('published',true);
  end if;
  if card.created_at <= now() - interval '15 minutes' then raise exception 'share_target_unavailable'; end if;
  update public.share_card_previews set snapshot_version = 1, image_path = input_image_path,
    title = trim(input_title), description = coalesce(input_description,'') where id = card.id;
  return jsonb_build_object('published',true);
end;
$$;
revoke all on function public.publish_share_card_snapshot(text,text,text,text,text,text) from public, anon;
grant execute on function public.publish_share_card_snapshot(text,text,text,text,text,text) to authenticated;

-- Keep the old Clip handshake unchanged. This separate website reader returns
-- either an explicitly published copy or already-public profile/place metadata.
-- It never upgrades an old protected card into a public copy retroactively.
create function public.share_card_context(input_token text, input_kind text, input_identifier text)
returns jsonb language plpgsql stable security definer
set search_path = public, app, extensions
as $$
declare card public.share_card_previews; preview jsonb;
begin
  if public.share_card_preview(input_token,input_kind,input_identifier) is null then return null; end if;
  select * into card from public.share_card_previews
    where token_hash = encode(extensions.digest(input_token,'sha256'),'hex')
      and kind = input_kind and identifier = input_identifier;
  if card.snapshot_version = 1 then
    if not exists (select 1 from storage.objects where bucket_id = 'shared-link-snapshots' and name = card.image_path)
      then return null; end if;
    return jsonb_build_object('preview_mode','snapshot','title',card.title,
      'description',card.description,'image_path',card.image_path);
  end if;
  preview := public.public_web_preview(input_kind,input_identifier);
  if input_kind in ('profile','place') and preview->>'is_available' = 'true' then
    return jsonb_build_object('preview_mode','public','title',preview->>'title',
      'subtitle',preview->>'subtitle','description',preview->>'description','image_url',preview->>'image_url');
  end if;
  return jsonb_build_object('preview_mode','generic');
end;
$$;
revoke all on function public.share_card_context(text,text,text) from public;
grant execute on function public.share_card_context(text,text,text) to anon, authenticated;

comment on column public.share_card_previews.snapshot_version is
  'Version 1 is an explicitly published owner-selected copy. Source access is unchanged; external copies cannot be recalled.';
commit;
