begin;

create extension if not exists pgtap;

select plan(14);

select is(
  (
    select prosecdef
    from pg_proc
    where oid = 'app.current_user_id()'::regprocedure
  ),
  false,
  'current_user_id remains security invoker'
);

select ok(
  (
    select exists (
      select 1
      from unnest(coalesce(proconfig, array[]::text[])) setting
      where setting in ('search_path=', 'search_path=""')
    )
    from pg_proc
    where oid = 'app.current_user_id()'::regprocedure
  ),
  'current_user_id pins an empty search_path'
);

select ok(
  has_function_privilege('authenticated', 'app.current_user_id()', 'execute'),
  'authenticated RLS can resolve the current user ID'
);

select ok(
  has_table_privilege('service_role', 'public.clerk_identity_mappings', 'select')
  and has_table_privilege('service_role', 'public.clerk_identity_mappings', 'insert')
  and has_table_privilege('service_role', 'public.clerk_identity_mappings', 'update')
  and has_table_privilege('service_role', 'public.clerk_identity_mappings', 'delete'),
  'service role can maintain identity mappings'
);

select ok(
  not has_table_privilege('anon', 'public.clerk_identity_mappings', 'select')
  and not has_table_privilege('authenticated', 'public.clerk_identity_mappings', 'select'),
  'client roles cannot read identity mappings'
);

select ok(
  (
    select relrowsecurity
    from pg_class
    where oid = 'public.clerk_identity_mappings'::regclass
  ),
  'identity mappings enforce RLS'
);

insert into public.profiles(id, handle, display_name)
values ('user_original_identity', 'originalidentity', 'Original Identity');

insert into public.clerk_identity_mappings(clerk_user_id, profile_id)
values ('user_production_identity', 'user_original_identity');

select is(
  (
    select profile_id
    from public.clerk_identity_mappings
    where clerk_user_id = 'user_production_identity'
  ),
  'user_original_identity',
  'production Clerk ID maps to the stable profile ID'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_development_identity', true);
select set_config('request.jwt.claim.canonical_user_id', '', true);

select is(
  app.current_user_id(),
  'user_development_identity',
  'legacy development tokens continue to use sub'
);

select set_config('request.jwt.claim.canonical_user_id', 'user_original_identity', true);

select is(
  app.current_user_id(),
  'user_original_identity',
  'production tokens prefer the stable canonical user ID'
);

select is(
  (select count(*)::integer from public.profiles where id = 'user_original_identity'),
  1,
  'canonical production identity can read its existing profile through RLS'
);

select set_config('request.jwt.claim.canonical_user_id', '', true);
select set_config('request.jwt.claim.sub', '', true);

select is(
  app.current_user_id(),
  null,
  'missing identity claims resolve to null'
);

reset role;

delete from public.profiles where id = 'user_original_identity';

select is(
  (
    select count(*)::integer
    from public.clerk_identity_mappings
    where clerk_user_id = 'user_production_identity'
  ),
  0,
  'profile deletion cascades to every Clerk identity mapping'
);

select is(
  (
    select count(*)::integer
    from public.clerk_identity_mappings mapping
    join public.profiles profile on profile.id = mapping.profile_id
    where mapping.clerk_user_id = profile.id
  ),
  (select count(*)::integer from public.profiles),
  'migration backfills a rollback mapping for every existing profile'
);

select is(
  (
    select confdeltype::text
    from pg_constraint
    where conrelid = 'public.clerk_identity_mappings'::regclass
      and contype = 'f'
  ),
  'c',
  'identity mapping foreign key cascades on profile deletion'
);

select * from finish();

rollback;
