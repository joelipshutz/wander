begin;

-- Sharing a plan deliberately publishes its rendered card and authored message
-- to holders of an unguessable link. No save notes, visits, ratings, or lists are
-- read by the anonymous resolver. Existing public_web_preview stays unchanged.
create table public.place_plan_invitations (
  id uuid primary key default gen_random_uuid(),
  sender_id text not null references public.profiles(id) on delete cascade,
  recipient_id text not null references public.profiles(id) on delete cascade,
  place_id uuid not null references public.places(id) on delete cascade,
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  image_path text not null,
  title text not null check (char_length(title) between 1 and 500),
  message text not null check (char_length(message) between 1 and 1000),
  connection text not null check (char_length(connection) between 1 and 300),
  date_label text not null check (char_length(date_label) between 1 and 100),
  suggested_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '90 days',
  check (sender_id <> recipient_id)
);
create index place_plan_invitations_sender_created_idx
  on public.place_plan_invitations(sender_id, created_at desc);
alter table public.place_plan_invitations enable row level security;
revoke all on public.place_plan_invitations from public, anon, authenticated;

-- These are intentional public share attachments, never private photo uploads.
-- The card contains venue facts and the chosen date; no participant/save data.
insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('place-plan-previews', 'place-plan-previews', true, 2097152, array['image/png'])
on conflict (id) do nothing;
create policy "plan preview owner insert" on storage.objects for insert to authenticated
with check (
  bucket_id = 'place-plan-previews'
  and (storage.foldername(name))[1] = app.current_user_id()
  and name ~ '^[^/]+/[a-f0-9-]{36}/preview[.]png$'
  and exists (select 1 from public.profiles where id = app.current_user_id() and deleted_at is null)
);
create policy "plan preview owner delete" on storage.objects for delete to authenticated
using (bucket_id = 'place-plan-previews' and (storage.foldername(name))[1] = app.current_user_id());
create policy "plan preview owner select" on storage.objects for select to authenticated
using (bucket_id = 'place-plan-previews' and (storage.foldername(name))[1] = app.current_user_id());

-- SECURITY DEFINER is necessary because the invitation table has no client
-- grants. All ownership is derived from the authenticated Clerk claim helper.
create function public.create_place_plan_invitation(
  input_place_id uuid, input_recipient_id text, input_image_path text,
  input_message text, input_connection text, input_date_label text, input_title text,
  input_suggested_at timestamptz default null
) returns jsonb language plpgsql volatile security definer
set search_path = public, app, extensions
as $$
declare
  viewer_id text := app.current_user_id();
  invite_token text;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if viewer_id = input_recipient_id
    or app.is_blocked(viewer_id, input_recipient_id)
    or not exists (select 1 from public.profiles where id = viewer_id and deleted_at is null)
    or not exists (select 1 from public.profiles where id = input_recipient_id and deleted_at is null)
    or not exists (select 1 from public.user_places where place_id = input_place_id
      and user_id = viewer_id and deleted_at is null)
    or not exists (select 1 from public.user_places where place_id = input_place_id
      and user_id = input_recipient_id and deleted_at is null
      and app.can_read_user_place(viewer_id, user_id, visibility))
  then raise exception 'plan_not_available'; end if;
  if split_part(input_image_path, '/', 1) <> viewer_id
    or not exists (select 1 from storage.objects where bucket_id = 'place-plan-previews' and name = input_image_path)
  then raise exception 'preview_not_available'; end if;
  if (select count(*) from public.place_plan_invitations where sender_id = viewer_id
    and created_at > now() - interval '1 day') >= 50
  then raise exception 'plan_limit_reached'; end if;

  invite_token := encode(extensions.gen_random_bytes(24), 'hex');
  insert into public.place_plan_invitations(sender_id, recipient_id, place_id, token_hash,
    image_path, title, message, connection, date_label, suggested_at, expires_at)
  values (viewer_id, input_recipient_id, input_place_id,
    encode(extensions.digest(invite_token, 'sha256'), 'hex'), input_image_path, trim(input_title),
    trim(input_message), trim(input_connection), trim(input_date_label), input_suggested_at,
    greatest(now() + interval '90 days', input_suggested_at + interval '7 days'));
  return jsonb_build_object('token', invite_token);
end;
$$;
revoke all on function public.create_place_plan_invitation(uuid,text,text,text,text,text,text,timestamptz) from public, anon;
grant execute on function public.create_place_plan_invitation(uuid,text,text,text,text,text,text,timestamptz) to authenticated;

-- Token possession permits reading only the content explicitly shared by the
-- sender. Account deletion or a block makes the invitation unavailable. Rendered
-- public artwork and third-party link caches cannot be recalled after sharing.
create function public.place_plan_preview(input_token text)
returns jsonb language plpgsql stable security definer
set search_path = public, app, extensions
as $$
declare result jsonb;
begin
  if input_token is null or input_token !~ '^[a-f0-9]{48}$' then return null; end if;
  select jsonb_build_object(
    'title', invite.title,
    'place_name', place.canonical_name,
    'location', concat_ws(', ', nullif(place.locality, ''), nullif(place.region, '')),
    'sender_name', sender.display_name, 'sender_avatar_url', sender.avatar_url,
    'message', invite.message, 'connection', invite.connection,
    'date_label', invite.date_label, 'suggested_at', invite.suggested_at,
    'image_path', invite.image_path
  ) into result
  from public.place_plan_invitations invite
  join public.places place on place.id = invite.place_id
  join public.profiles sender on sender.id = invite.sender_id
  join public.profiles recipient on recipient.id = invite.recipient_id
  where invite.token_hash = encode(extensions.digest(input_token, 'sha256'), 'hex')
    and invite.expires_at > now()
    and sender.deleted_at is null and recipient.deleted_at is null
    and not app.is_blocked(invite.sender_id, invite.recipient_id);
  return result;
end;
$$;
revoke all on function public.place_plan_preview(text) from public;
grant execute on function public.place_plan_preview(text) to anon, authenticated;

commit;
