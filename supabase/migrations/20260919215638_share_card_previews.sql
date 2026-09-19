begin;

-- Explicit sharing publishes one static rendered card to holders of a random
-- link. Anonymous callers cannot enumerate saves or resolve cards by entity ID.
create table public.share_card_previews (
  id uuid primary key default gen_random_uuid(),
  creator_id text not null references public.profiles(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  kind text not null check (kind in ('profile', 'place', 'list', 'activity', 'invite')),
  identifier text not null check (char_length(identifier) between 1 and 256),
  image_path text not null unique,
  title text not null check (char_length(title) between 1 and 500),
  created_at timestamptz not null default now()
);
create index share_card_previews_creator_idx on public.share_card_previews(creator_id, created_at);
alter table public.share_card_previews enable row level security;
revoke all on public.share_card_previews from public, anon, authenticated;

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('share-card-previews', 'share-card-previews', true, 5242880, array['image/png']);
create policy "share card owner insert" on storage.objects for insert to authenticated
with check (bucket_id = 'share-card-previews'
  and (storage.foldername(name))[1] = app.current_user_id()
  and name ~ '^[A-Za-z0-9_-]+/[a-f0-9-]{36}/preview[.]png$'
  and exists (select 1 from public.profiles where id = app.current_user_id() and deleted_at is null));
create policy "share card owner select" on storage.objects for select to authenticated
using (bucket_id = 'share-card-previews' and (storage.foldername(name))[1] = app.current_user_id());
create policy "share card owner delete" on storage.objects for delete to authenticated
using (bucket_id = 'share-card-previews' and (storage.foldername(name))[1] = app.current_user_id());

-- Definer is deliberate: the table has no client grants. Caller identity comes
-- only from the verified claim. Existing access helpers authorize the target.
create function public.create_share_card_preview(input_kind text, input_identifier text,
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
  if input_image_path is null or split_part(input_image_path, '/', 1) <> viewer_id
    or input_image_path !~ '^[A-Za-z0-9_-]+/[a-f0-9-]{36}/preview[.]png$'
    or not exists (select 1 from storage.objects where bucket_id = 'share-card-previews' and name = input_image_path)
    then raise exception 'share_artwork_unavailable'; end if;
  -- Lock the creator so concurrent requests cannot exceed the publication limit.
  perform 1 from public.profiles where id = viewer_id for update;
  if (select count(*) from public.share_card_previews where creator_id = viewer_id
      and created_at > now() - interval '1 day') >= 100 then raise exception 'share_limit_reached'; end if;
  share_token := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.share_card_previews(creator_id, token_hash, kind, identifier, image_path, title)
  values (viewer_id, encode(extensions.digest(share_token, 'sha256'), 'hex'), input_kind,
    input_identifier, input_image_path, trim(input_title));
  return jsonb_build_object('token', share_token);
end;
$$;
revoke all on function public.create_share_card_preview(text,text,text,text) from public, anon;
grant execute on function public.create_share_card_preview(text,text,text,text) to authenticated;

-- Definer reads only the explicitly published snapshot, never the underlying
-- restricted data. The token is bound to the canonical route and cannot be
-- reused as another entity's artwork. Existing app authorization is unchanged.
create function public.share_card_preview(input_token text, input_kind text, input_identifier text)
returns jsonb language sql stable security definer
set search_path = public, app, extensions
as $$
  select jsonb_build_object('title', card.title, 'image_path', card.image_path)
  from public.share_card_previews card
  join public.profiles creator on creator.id = card.creator_id and creator.deleted_at is null
  where input_token ~ '^[a-f0-9]{48}$'
    and card.token_hash = encode(extensions.digest(input_token, 'sha256'), 'hex')
    and card.kind = input_kind and card.identifier = input_identifier
    and exists (select 1 from storage.objects where bucket_id = 'share-card-previews' and name = card.image_path)
    and (card.kind <> 'invite' or exists (select 1 from public.place_list_invites invite
      where invite.token_hash = encode(extensions.digest(card.identifier, 'sha256'), 'hex')
        and invite.revoked_at is null and invite.accepted_at is null and invite.expires_at > now()));
$$;
revoke all on function public.share_card_preview(text,text,text) from public;
grant execute on function public.share_card_preview(text,text,text) to anon, authenticated;

comment on table public.share_card_previews is 'User-published static card copies. Public artwork and third-party caches cannot be recalled; underlying content keeps its existing access controls.';
commit;
