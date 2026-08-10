begin;

create extension if not exists pgtap;
set local search_path = public, extensions;

select plan(16);

select has_function('app', 'leave_place_list', array['uuid']);
select has_function('public', 'leave_place_list', array['uuid']);

select ok(
  (select prosecdef from pg_proc where oid = 'app.leave_place_list(uuid)'::regprocedure),
  'the internal leave-list mutation is security definer'
);
select ok(
  (
    select 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'app.leave_place_list(uuid)'::regprocedure
  ),
  'the internal leave-list mutation pins its search path'
);
select ok(
  not (select prosecdef from pg_proc where oid = 'public.leave_place_list(uuid)'::regprocedure),
  'the public leave-list wrapper is security invoker'
);
select ok(
  (
    select 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
    from pg_proc
    where oid = 'public.leave_place_list(uuid)'::regprocedure
  ),
  'the public leave-list wrapper pins its search path'
);
select ok(
  has_function_privilege('authenticated', 'public.leave_place_list(uuid)', 'execute'),
  'authenticated callers can leave lists through the public wrapper'
);
select ok(
  not has_function_privilege('anon', 'public.leave_place_list(uuid)', 'execute'),
  'anonymous callers cannot leave lists'
);
select ok(
  has_function_privilege('authenticated', 'app.leave_place_list(uuid)', 'execute'),
  'the authenticated security-invoker wrapper can invoke its app implementation'
);

insert into public.profiles (id, handle, display_name)
values
  ('user_leave_list_owner', 'leave_list_owner', 'Leave List Owner'),
  ('user_leave_list_collaborator', 'leave_list_collab', 'Leave List Collaborator');

insert into public.follows (follower_user_id, followed_user_id, source)
values ('user_leave_list_collaborator', 'user_leave_list_owner', 'profile');

insert into public.place_lists (id, owner_user_id, name, description, visibility)
values (
  'ce3845a9-4794-459c-b368-22dc34199349',
  'user_leave_list_owner',
  'Leave-list contract',
  'Followers-visible before the collaborator opts out',
  'followers'
);

insert into public.place_list_members (list_id, user_id, role)
values (
  'ce3845a9-4794-459c-b368-22dc34199349',
  'user_leave_list_collaborator',
  'collaborator'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_leave_list_collaborator', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  app.can_read_place_list(
    'ce3845a9-4794-459c-b368-22dc34199349',
    'user_leave_list_collaborator'
  ),
  'an active collaborator can read the shared list'
);

select public.leave_place_list('ce3845a9-4794-459c-b368-22dc34199349');

reset role;
select ok(
  exists (
    select 1
    from public.place_list_members
    where list_id = 'ce3845a9-4794-459c-b368-22dc34199349'
      and user_id = 'user_leave_list_collaborator'
      and deleted_at is not null
  ),
  'leaving tombstones only the current collaborator membership'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_leave_list_collaborator', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select ok(
  not app.can_read_place_list(
    'ce3845a9-4794-459c-b368-22dc34199349',
    'user_leave_list_collaborator'
  ),
  'a collaborator who leaves cannot regain access through follower visibility'
);
select is(
  public.place_list_detail('ce3845a9-4794-459c-b368-22dc34199349'),
  null::jsonb,
  'a collaborator who leaves can no longer load list detail'
);
select throws_ok(
  $$select public.leave_place_list('ce3845a9-4794-459c-b368-22dc34199349')$$,
  'P0001',
  'place_list_not_found_or_forbidden',
  'leaving the same list twice is rejected'
);

select set_config('request.jwt.claim.sub', 'user_leave_list_owner', true);
select throws_ok(
  $$select public.leave_place_list('ce3845a9-4794-459c-b368-22dc34199349')$$,
  'P0001',
  'place_list_owner_cannot_leave',
  'the list owner cannot leave their own list'
);
select isnt(
  public.place_list_detail('ce3845a9-4794-459c-b368-22dc34199349'),
  null::jsonb,
  'the owner retains list access after a collaborator leaves'
);

select * from finish() as result(message);

rollback;
