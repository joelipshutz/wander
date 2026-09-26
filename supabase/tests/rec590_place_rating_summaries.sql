begin;
savepoint rec590_ratings;

-- Reserved smoke identities only; every fixture and policy change rolls back.
insert into public.profiles(id, handle, display_name, default_visibility, is_private_profile, deleted_at)
values
  ('user_codex_supabase_smoke', 'codex_smoke', 'Smoke owner', 'followers', false, null),
  ('user_codex_supabase_smoke_collab', 'codex_smoke_collab', 'Smoke followed', 'followers', false, null),
  ('user_codex_supabase_smoke_stranger', 'codex_smoke_stranger', 'Smoke hidden', 'followers', false, null)
on conflict (id) do update set deleted_at = null, is_private_profile = false;

delete from public.blocks
where blocker_user_id in ('user_codex_supabase_smoke', 'user_codex_supabase_smoke_collab', 'user_codex_supabase_smoke_stranger')
  and blocked_user_id in ('user_codex_supabase_smoke', 'user_codex_supabase_smoke_collab', 'user_codex_supabase_smoke_stranger');
insert into public.follows(follower_user_id, followed_user_id, source)
values ('user_codex_supabase_smoke', 'user_codex_supabase_smoke_collab', 'profile'),
       ('user_codex_supabase_smoke', 'user_codex_supabase_smoke_stranger', 'profile')
on conflict (follower_user_id, followed_user_id) do nothing;

create temporary table rec590_rating_ids (
  place_id uuid default gen_random_uuid(),
  owner_save uuid default gen_random_uuid(),
  friend_save uuid default gen_random_uuid(),
  hidden_save uuid default gen_random_uuid(),
  deleted_visit uuid default gen_random_uuid()
) on commit drop;
insert into rec590_rating_ids default values;
grant select on rec590_rating_ids to authenticated, anon;

insert into public.places(id, canonical_name, category, latitude, longitude, source_provider, source_provider_place_id)
select place_id, 'Rating aggregate smoke', 'coffee_tea_sweets', 0, 0, 'codex_smoke', place_id::text from rec590_rating_ids;
insert into public.user_places(id, user_id, place_id, status, visibility, source_type)
select owner_save, 'user_codex_supabase_smoke', place_id, 'been', 'followers', 'manual' from rec590_rating_ids
union all select friend_save, 'user_codex_supabase_smoke_collab', place_id, 'been', 'followers', 'manual' from rec590_rating_ids
union all select hidden_save, 'user_codex_supabase_smoke_stranger', place_id, 'been', 'self', 'manual' from rec590_rating_ids;
insert into public.place_visits(user_place_id, rating_score)
select owner_save, 2 from rec590_rating_ids
union all select owner_save, 4 from rec590_rating_ids
union all select friend_save, 5 from rec590_rating_ids
union all select friend_save, 3 from rec590_rating_ids
union all select hidden_save, 1 from rec590_rating_ids;
insert into public.place_visits(id, user_place_id, rating_score, deleted_at)
select deleted_visit, owner_save, 5, now() from rec590_rating_ids;
update public.profiles set is_private_profile = true where id = 'user_codex_supabase_smoke_stranger';

do $$
begin
  if not exists (select 1 from pg_proc where oid = 'public.place_rating_summaries(uuid,text,text)'::regprocedure
      and prosecdef and provolatile = 's' and proconfig @> array['search_path=pg_catalog, public, app'])
    or not exists (select 1 from pg_proc where oid = 'app.place_rating_summaries(uuid,text,text)'::regprocedure
      and prosecdef and provolatile = 's' and proconfig @> array['search_path=pg_catalog, public, app'])
    or has_function_privilege('anon', 'public.place_rating_summaries(uuid,text,text)', 'execute')
    or has_function_privilege('authenticated', 'app.place_rating_summaries(uuid,text,text)', 'execute')
    or not has_function_privilege('authenticated', 'public.place_rating_summaries(uuid,text,text)', 'execute') then
    raise exception 'rating RPC security metadata mismatch';
  end if;
end $$;

set local role authenticated;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
select set_config('request.jwt.claim.role', 'authenticated', true);
do $$
declare result jsonb;
begin
  select public.place_rating_summaries(place_id) into result from rec590_rating_ids;
  if result <> '{"own":{"score":3,"count":2},"friends":{"score":4,"count":1},"astir":{"score":3,"count":5}}'::jsonb then
    raise exception 'independent rating aggregates mismatch: %', result;
  end if;
  if exists (select 1 from public.place_visits where user_place_id = (select hidden_save from rec590_rating_ids)) then
    raise exception 'hidden raw rating rows were exposed';
  end if;
  if (select public.place_rating_summaries(null, 'codex_smoke', place_id::text) from rec590_rating_ids) <> result then
    raise exception 'provider lookup must preserve hidden global contributions';
  end if;
  if public.place_rating_summaries(gen_random_uuid()) <>
      '{"own":{"score":null,"count":0},"friends":{"score":null,"count":0},"astir":{"score":null,"count":0}}'::jsonb then
    raise exception 'empty ratings must not invent a score';
  end if;
end $$;

reset role;
update public.profiles set is_private_profile = true where id = 'user_codex_supabase_smoke_collab';
set local role authenticated;
do $$
declare result jsonb;
begin
  select public.place_rating_summaries(place_id) into result from rec590_rating_ids;
  if result->'friends' <> '{"score":null,"count":0}'::jsonb
    or result->'astir' <> '{"score":3,"count":5}'::jsonb then
    raise exception 'legacy private-profile activity must not leak through Friends';
  end if;
end $$;
reset role;
update public.profiles set is_private_profile = false where id = 'user_codex_supabase_smoke_collab';
insert into public.blocks(blocker_user_id, blocked_user_id)
values ('user_codex_supabase_smoke_collab', 'user_codex_supabase_smoke');
set local role authenticated;
do $$
declare result jsonb;
begin
  select public.place_rating_summaries(place_id) into result from rec590_rating_ids;
  if result->'friends' <> '{"score":null,"count":0}'::jsonb
    or result->'astir' <> '{"score":3,"count":5}'::jsonb then
    raise exception 'a block must remove the friend score and count without changing Astir';
  end if;
end $$;
reset role;
delete from public.blocks where blocker_user_id = 'user_codex_supabase_smoke_collab'
  and blocked_user_id = 'user_codex_supabase_smoke';
update public.user_places set visibility = 'self' where id = (select friend_save from rec590_rating_ids);
set local role authenticated;
do $$
declare result jsonb;
begin
  select public.place_rating_summaries(place_id) into result from rec590_rating_ids;
  if result->'friends' <> '{"score":null,"count":0}'::jsonb
    or result->'astir' <> '{"score":3,"count":5}'::jsonb then
    raise exception 'hiding the last followed rating must empty Friends and preserve Astir';
  end if;
  if (select public.place_rating_summaries(null, 'codex_smoke', place_id::text) from rec590_rating_ids) <> result then
    raise exception 'provider lookup must work without a visible followed rating';
  end if;
end $$;

reset role;
update public.profiles set deleted_at = now() where id = 'user_codex_supabase_smoke_stranger';
set local role authenticated;
do $$
declare result jsonb;
begin
  select public.place_rating_summaries(place_id) into result from rec590_rating_ids;
  if result->'astir' <> '{"score":3.5,"count":4}'::jsonb then
    raise exception 'deleted accounts must leave the global denominator';
  end if;
end $$;

select set_config('request.jwt.claim.sub', '', true);
do $$
begin
  perform public.place_rating_summaries((select place_id from rec590_rating_ids));
  raise exception 'missing identity was accepted';
exception when insufficient_privilege then null;
end $$;
reset role;
set local role anon;
do $$
begin
  perform public.place_rating_summaries((select place_id from rec590_rating_ids));
  raise exception 'anonymous execution was accepted';
exception when insufficient_privilege then null;
end $$;
reset role;

rollback to savepoint rec590_ratings;
release savepoint rec590_ratings;
rollback;
