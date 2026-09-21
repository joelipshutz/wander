begin;

-- REC-578: an invitation may start from either person's saved place. Owners may
-- choose to invite someone to their own private save; a recipient-only save must
-- still be readable to the sender through the existing visibility policy.
-- Preserve the original 20260918032922 contract: SECURITY DEFINER is required
-- because place_plan_invitations has no client table grants. The sender comes
-- only from app.current_user_id(); active accounts, bilateral blocks, preview
-- ownership, rate limit, token hashing, expiry, jsonb result, VOLATILE behavior,
-- pinned search_path, and authenticated-only execute privileges remain intact.
create or replace function public.create_place_plan_invitation(
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
    or not (
      exists (select 1 from public.user_places where place_id = input_place_id
        and user_id = viewer_id and deleted_at is null)
      or exists (select 1 from public.user_places where place_id = input_place_id
        and user_id = input_recipient_id and deleted_at is null
        and app.can_read_user_place(viewer_id, user_id, visibility))
    )
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

commit;
