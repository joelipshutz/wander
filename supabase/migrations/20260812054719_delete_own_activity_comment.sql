begin;

-- Keep the comments table private and expose deletion through a narrow RPC.
-- The authenticated identity is derived from the request claims; callers can
-- never choose an author id or delete another person's comment.
create function public.delete_own_activity_comment(
  input_comment_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  deleted_activity_id uuid;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  delete from public.activity_comments comment
  where comment.id = input_comment_id
    and comment.author_user_id = viewer_id
  returning comment.activity_id into deleted_activity_id;

  if deleted_activity_id is null then
    raise exception 'comment_not_found_or_not_owned';
  end if;

  return app.activity_engagement_json(viewer_id, deleted_activity_id);
end;
$$;

revoke all on function public.delete_own_activity_comment(uuid) from public, anon;
grant execute on function public.delete_own_activity_comment(uuid) to authenticated;

comment on function public.delete_own_activity_comment(uuid) is
  'Deletes only the authenticated viewer comment and returns synchronized engagement.';

commit;
