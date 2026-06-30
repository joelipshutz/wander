begin;

-- Keep this RPC as security invoker: callers update only their own profile,
-- and ownership is derived from app.current_user_id(), never from client input.
create or replace function app.update_profile_avatar(
  avatar_url text default null,
  storage_path text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public, app
as $$
declare
  updated_profile public.profiles;
  current_profile_id text := app.current_user_id();
  trimmed_avatar_url text := nullif(trim(avatar_url), '');
  trimmed_storage_path text := nullif(trim(storage_path), '');
  avatar_url_prefix constant text := 'https://rugmtlgufrhlxwfkumhw.supabase.co/storage/v1/object/public/profile-avatars/';
begin
  if current_profile_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if (trimmed_avatar_url is null) <> (trimmed_storage_path is null) then
    raise exception 'avatar_url_and_storage_path_must_match' using errcode = '22023';
  end if;

  if trimmed_storage_path is not null
    and trimmed_storage_path <> current_profile_id || '/avatar.jpg' then
    raise exception 'invalid_avatar_storage_path' using errcode = '42501';
  end if;

  if trimmed_avatar_url is not null
    and left(trimmed_avatar_url, length(avatar_url_prefix || trimmed_storage_path)) <> avatar_url_prefix || trimmed_storage_path then
    raise exception 'invalid_avatar_url' using errcode = '22023';
  end if;

  update public.profiles
  set
    avatar_url = trimmed_avatar_url,
    avatar_storage_path = trimmed_storage_path,
    avatar_url_source = 'app',
    updated_at = now()
  where id = current_profile_id
    and deleted_at is null
  returning *
  into updated_profile;

  if updated_profile.id is null then
    raise exception 'profile_not_found' using errcode = 'P0002';
  end if;

  return jsonb_build_object(
    'avatar_url', updated_profile.avatar_url,
    'avatar_storage_path', updated_profile.avatar_storage_path
  );
end;
$$;

comment on function app.update_profile_avatar(text, text) is
  'Updates the authenticated caller profile avatar URL after Storage upload, or clears it after delete.';

revoke all on function app.update_profile_avatar(text, text) from public, anon;
grant execute on function app.update_profile_avatar(text, text) to authenticated;

commit;
