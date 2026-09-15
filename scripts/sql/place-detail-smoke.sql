-- Run inside the smoke tool's rolled-back transaction. Reserved synthetic users
-- and places only; never collect or return actual saved content.
reset role;
insert into public.profiles (id, handle, display_name, default_visibility, is_private_profile, deleted_at)
values
  ('user_codex_supabase_smoke', 'codex_smoke', 'Codex Smoke Test', 'followers', false, null),
  ('user_codex_supabase_smoke_collab', 'codex_smoke_collab', 'Codex Smoke Collaborator', 'followers', false, null),
  ('user_codex_supabase_smoke_stranger', 'codex_smoke_stranger', 'Codex Smoke Stranger', 'followers', false, null)
on conflict (id) do update set deleted_at = null, is_private_profile = false;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $smoke$
declare
  place_payload jsonb := '{"canonical_name":"Codex Smoke Place Details","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","subcategory":"Coffee shop","category_source":"user","latitude":34.0523,"longitude":-118.2437,"source_provider":"codex_smoke","source_provider_place_id":"subcategory-questions-contract","confidence":1}';
  save_payload jsonb := '{"status":"been","visibility":"followers","nearby_confirmed":false,"source_type":"manual","rating_score":4}';
  detail_payload jsonb := '[{"question_key":"place_detail_outlets","value_type":"single_choice","value":"None found"},{"question_key":"place_detail_dog_access","value_type":"single_choice","value":"Outside only"}]';
  saved jsonb;
  parent_id uuid;
  visit_id uuid := gen_random_uuid();
  answer_count integer;
begin
  saved := public.save_own_place(place_payload, save_payload, detail_payload);
  parent_id := (saved->>'user_place_id')::uuid;
  if parent_id is null then raise exception 'Detail save returned no parent'; end if;
  select count(*) into answer_count from public.place_attributes
  where user_place_id = parent_id and value_type = 'single_choice'
    and ((question_key = 'place_detail_outlets' and value = '"None found"'::jsonb)
      or (question_key = 'place_detail_dog_access' and value = '"Outside only"'::jsonb));
  if answer_count <> 2 then raise exception 'Explicit negative/qualified detail did not round-trip'; end if;

  saved := public.save_own_check_in(
    place_payload, save_payload, detail_payload,
    jsonb_build_object('id', visit_id, 'visited_at', now(), 'rating_score', 4,
      'attribute_answers', detail_payload), null
  );
  if (saved->>'visit_id')::uuid is distinct from visit_id then raise exception 'Detail visit returned wrong ID'; end if;
  if not exists (select 1 from public.own_place_visit_details(array[parent_id]) where id = visit_id and attribute_answers = detail_payload)
  then raise exception 'Detail visit did not preserve typed answers'; end if;

  -- Editing clears only the explicit answer removed from this ticket.
  saved := public.save_own_check_in(
    place_payload, save_payload, detail_payload - 0,
    jsonb_build_object('id', visit_id, 'visited_at', now(), 'rating_score', 4,
      'attribute_answers', detail_payload - 0), null
  );
  if not exists (select 1 from public.own_place_visit_details(array[parent_id]) where id = visit_id and attribute_answers = detail_payload - 0)
  then raise exception 'Cleared detail reappeared on visit edit'; end if;

  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_collab', true);
  -- The broader harness may have already established this synthetic follow.
  -- Do not invoke the existing upsert RPC for a relationship that already exists.
  if not exists (select 1 from public.follows
    where follower_user_id = 'user_codex_supabase_smoke_collab'
      and followed_user_id = 'user_codex_supabase_smoke') then
    perform public.follow_user('user_codex_supabase_smoke', 'profile');
  end if;
  if not exists (select 1 from public.place_attributes where user_place_id = parent_id
    and question_key = 'place_detail_dog_access' and value = '"Outside only"'::jsonb)
  then raise exception 'Authorized follower cannot read scoped detail'; end if;

  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_stranger', true);
  if exists (select 1 from public.place_attributes where user_place_id = parent_id)
  then raise exception 'Unrelated user can read private save details'; end if;

  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
  saved := public.save_own_place(place_payload, save_payload, '[]'::jsonb);
  if exists (select 1 from public.place_attributes where user_place_id = parent_id)
  then raise exception 'Cleared detail reappeared on parent edit'; end if;
end
$smoke$;
reset role;
