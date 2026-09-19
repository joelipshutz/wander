begin;

alter table public.place_plan_invitations add column read_at timestamptz;
create index place_plan_invitations_recipient_created_idx
  on public.place_plan_invitations(recipient_id, created_at desc, id);

-- Shared projection for public bearer links and authenticated recipient reads.
-- Internal SECURITY DEFINER helper: no client execute grant. Visibility follows
-- the original invitation resolver, including expiry, deleted accounts, blocks.
create function app.place_plan_payload(input_invitation_id uuid)
returns jsonb language sql stable security definer
set search_path = public, app, extensions
as $$
  select jsonb_build_object(
    'title', invite.title, 'place_name', place.canonical_name,
    'location', concat_ws(', ', nullif(place.locality, ''), nullif(place.region, '')),
    'sender_name', sender.display_name, 'sender_avatar_url', sender.avatar_url,
    'message', invite.message, 'connection', invite.connection,
    'date_label', invite.date_label, 'suggested_at', invite.suggested_at,
    'image_path', invite.image_path
  )
  from public.place_plan_invitations invite
  join public.places place on place.id = invite.place_id
  join public.profiles sender on sender.id = invite.sender_id
  join public.profiles recipient on recipient.id = invite.recipient_id
  where invite.id = input_invitation_id and invite.expires_at > now()
    and sender.deleted_at is null and recipient.deleted_at is null
    and not app.is_blocked(invite.sender_id, invite.recipient_id);
$$;
revoke all on function app.place_plan_payload(uuid) from public, anon, authenticated;

-- Preserve the previously deployed public token resolver's security posture,
-- search_path, stability, return type, and anon/authenticated grants.
create or replace function public.place_plan_preview(input_token text)
returns jsonb language plpgsql stable security definer
set search_path = public, app, extensions
as $$
declare invitation_id uuid;
begin
  if input_token is null or input_token !~ '^[a-f0-9]{48}$' then return null; end if;
  select id into invitation_id from public.place_plan_invitations
    where token_hash = encode(extensions.digest(input_token, 'sha256'), 'hex');
  return app.place_plan_payload(invitation_id);
end;
$$;
revoke all on function public.place_plan_preview(text) from public;
grant execute on function public.place_plan_preview(text) to anon, authenticated;

-- Only the signed-in recipient can enumerate their invitations. The public
-- bearer token/hash is never returned or stored in a notification payload.
create function public.received_place_plan_invitations()
returns jsonb language sql stable security definer
set search_path = public, app, extensions
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'created_at', created_at, 'read_at', read_at, 'invitation', payload
  ) order by created_at desc, id), '[]'::jsonb)
  from (
    select id, created_at, read_at, app.place_plan_payload(id) as payload
    from public.place_plan_invitations
    where recipient_id = app.current_user_id() and expires_at > now()
      and app.place_plan_payload(id) is not null
    order by created_at desc, id limit 100
  ) received;
$$;
revoke all on function public.received_place_plan_invitations() from public, anon;
grant execute on function public.received_place_plan_invitations() to authenticated;

-- Opening is a recipient-owned read transition, never acceptance or editing.
-- SECURITY DEFINER is necessary: the table intentionally has no client grants.
create function public.open_received_place_plan_invitation(input_invitation_id uuid)
returns jsonb language plpgsql volatile security definer
set search_path = public, app, extensions
as $$
declare result jsonb;
begin
  if not exists (select 1 from public.place_plan_invitations
    where id = input_invitation_id and recipient_id = app.current_user_id())
  then return null; end if;
  result := app.place_plan_payload(input_invitation_id);
  if result is not null then
    update public.place_plan_invitations set read_at = coalesce(read_at, now())
      where id = input_invitation_id and recipient_id = app.current_user_id();
  end if;
  return result;
end;
$$;
revoke all on function public.open_received_place_plan_invitation(uuid) from public, anon;
grant execute on function public.open_received_place_plan_invitation(uuid) to authenticated;

commit;
