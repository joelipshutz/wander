-- Run only inside the smoke harness's rolled-back transaction. All writes are
-- synthetic fixtures; every answer assertion uses the authenticated owner RPC.
-- Run after place-detail-smoke.sql, which establishes the synthetic follower.
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
  saved jsonb;
  parent_id uuid;
  visit_id uuid := gen_random_uuid();
  place_payload jsonb := '{"canonical_name":"Codex Smoke Own Visit Details","category":"coffee_tea_sweets","primary_category":"coffee_tea_sweets","subcategory":"Coffee shop","category_source":"user","latitude":34.0523,"longitude":-118.2437,"source_provider":"codex_smoke","source_provider_place_id":"own-visit-details-contract","confidence":1}';
  save_payload jsonb := '{"status":"been","visibility":"followers","nearby_confirmed":false,"source_type":"manual"}';
  details jsonb := '[{"question_key":"place_detail_outlets","value_type":"single_choice","value":"None found"},{"question_key":"place_detail_dog_access","value_type":"single_choice","value":"Outside only"}]';
  full_answers jsonb;
begin
  if has_column_privilege('authenticated', 'public.place_visits', 'attribute_answers', 'select')
    or has_function_privilege('anon', 'public.own_place_visit_details(uuid[])', 'execute')
    or not has_function_privilege('authenticated', 'public.own_place_visit_details(uuid[])', 'execute') then
    raise exception 'Owner visit detail grants differ from contract';
  end if;
  if not exists (select 1 from pg_proc where oid = 'public.own_place_visit_details(uuid[])'::regprocedure
    and prosecdef and provolatile = 's' and 'search_path=public, app' = any(proconfig)) then
    raise exception 'Owner visit detail security metadata differs from contract';
  end if;
  full_answers := details || '[{"question_key":"restaurant_cuisine","value_type":"restaurant_cuisine","value":"Thai"},{"question_key":"custom_question_legacy","value_type":"text","value":{"preserved":true}}]'::jsonb;
  saved := public.save_own_check_in(place_payload, save_payload, details,
    jsonb_build_object('id', visit_id, 'visited_at', '2026-09-01T12:00:00Z', 'attribute_answers', full_answers), null);
  parent_id := (saved->>'user_place_id')::uuid;
  if parent_id is null or (saved->>'visit_id')::uuid is distinct from visit_id then
    raise exception 'Owner detail fixture did not save';
  end if;
  if not exists (select 1 from public.own_place_visit_details(array[parent_id]) row
    where row.id = visit_id and row.attribute_answers = full_answers and row.created_at is not null and row.updated_at is not null) then
    raise exception 'Owner visit did not retain typed, private, and unknown answers';
  end if;
  if (select count(*) from public.own_place_visit_details(array[parent_id,parent_id])) <>
     (select count(*) from public.own_place_visit_details(array[parent_id])) then
    raise exception 'Duplicate owner parent IDs duplicate rows';
  end if;

  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_collab', true);
  if not exists (select 1 from public.follows
    where follower_user_id = 'user_codex_supabase_smoke_collab'
      and followed_user_id = 'user_codex_supabase_smoke') then
    raise exception 'Owner detail smoke requires the preceding synthetic follower fixture';
  end if;
  if exists (select 1 from public.own_place_visit_details(array[parent_id])) then
    raise exception 'Follower received owner-only answer history';
  end if;
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_stranger', true);
  if exists (select 1 from public.own_place_visit_details(array[parent_id])) then
    raise exception 'Stranger received owner-only answer history';
  end if;

  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
  saved := public.save_own_check_in(place_payload, save_payload, '[]'::jsonb,
    jsonb_build_object('id', visit_id, 'visited_at', '2026-09-01T12:00:00Z', 'attribute_answers', '[]'::jsonb), null);
  if not exists (select 1 from public.own_place_visit_details(array[parent_id]) row
    where row.id = visit_id and row.attribute_answers = '[]'::jsonb) then
    raise exception 'Explicitly cleared owner answers did not round-trip';
  end if;
  perform public.delete_own_check_in(visit_id);
  if exists (select 1 from public.own_place_visit_details(array[parent_id]) row where row.id = visit_id) then
    raise exception 'Deleted visit remained in owner answer history';
  end if;
end
$smoke$;

-- Explicitly shared custom answers use existing text values. Private answers
-- are omitted by the client; a question never overrides its Check-in audience.
do $custom_question_smoke$
declare
  place_payload jsonb := '{"canonical_name":"Codex Smoke Shared Custom Questions","category":"coffee_tea_sweets","latitude":34.0523,"longitude":-118.2437,"source_provider":"codex_smoke","source_provider_place_id":"shared-custom-question-contract"}';
  save_payload jsonb := '{"status":"been","visibility":"followers","source_type":"manual"}';
  custom_key text := 'place_detail_custom_5ebaaf58-4c10-4faa-a021-09b357aa461d';
  custom_value jsonb := '{"schema_version":1,"prompt":"Can I bring a dog?","answer":"no"}';
  ordinary jsonb := '[{"question_key":"coffee_tags","value_type":"multi_tag","value":["Quiet"]}]';
  shared_answers jsonb;
  saved jsonb;
  parent_id uuid;
  visit_id uuid := gen_random_uuid();
begin
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
  shared_answers := ordinary || jsonb_build_array(jsonb_build_object(
    'question_key', custom_key, 'value_type', 'text', 'value', custom_value
  )) || '[{"question_key":"place_detail_outlets","value_type":"single_choice","value":"A few"}]'::jsonb;
  saved := public.save_own_place(place_payload, save_payload, shared_answers);
  parent_id := (saved->>'user_place_id')::uuid;
  if not exists (select 1 from public.place_attributes where user_place_id = parent_id
    and question_key = custom_key and value_type = 'text' and value = custom_value) then
    raise exception 'Structured custom question did not round-trip through save_own_place';
  end if;
  saved := public.save_own_check_in(place_payload, save_payload, shared_answers,
    jsonb_build_object('id', visit_id, 'visited_at', '2026-09-02T12:00:00Z', 'attribute_answers', shared_answers), null);
  if not exists (select 1 from public.own_place_visit_details(array[parent_id]) details
    where details.id = visit_id and details.attribute_answers = shared_answers) then
    raise exception 'Structured custom question did not survive visit hydration';
  end if;
  if exists (select 1 from public.place_visits where id = visit_id and tags <> array['quiet']::text[]) then
    raise exception 'Custom Yes/No answer became a derived tag';
  end if;
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_collab', true);
  if not exists (select 1 from public.place_attributes where user_place_id = parent_id
    and question_key = custom_key and value = custom_value) then
    raise exception 'Authorized follower cannot read shared prompt and answer';
  end if;
  if exists (select 1 from public.own_place_visit_details(array[parent_id])) then
    raise exception 'Shared custom question widened owner history access';
  end if;
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_stranger', true);
  if exists (select 1 from public.place_attributes where user_place_id = parent_id) then
    raise exception 'Shared custom question widened parent visibility';
  end if;
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
  saved := public.save_own_check_in(place_payload, save_payload || '{"visibility":"self"}'::jsonb,
    shared_answers, jsonb_build_object('id', visit_id, 'visited_at', '2026-09-02T12:00:00Z', 'attribute_answers', shared_answers), null);
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_collab', true);
  if exists (select 1 from public.place_attributes where user_place_id = parent_id) then
    raise exception 'Non-Stealth question published a private Check-in';
  end if;
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
  saved := public.save_own_check_in(place_payload, save_payload, ordinary,
    jsonb_build_object('id', visit_id, 'visited_at', '2026-09-02T12:00:00Z', 'attribute_answers', ordinary), null);
  if not exists (select 1 from public.own_place_visit_details(array[parent_id]) details
    where details.id = visit_id and details.attribute_answers = ordinary) then
    raise exception 'Shared-to-private edit retained old remote answers';
  end if;
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke_collab', true);
  if exists (select 1 from public.place_attributes where user_place_id = parent_id
    and (left(question_key, 13) = 'place_detail_' or left(question_key, 16) = 'custom_question_')) then
    raise exception 'Shared-to-private edit retained a shared question or prompt';
  end if;
  if not exists (select 1 from public.place_attributes where user_place_id = parent_id and question_key = 'coffee_tags') then
    raise exception 'Question privacy edit removed unrelated metadata';
  end if;
  perform set_config('request.jwt.claim.sub', 'user_codex_supabase_smoke', true);
  perform public.delete_own_check_in(visit_id);
  if exists (select 1 from public.own_place_visit_details(array[parent_id]) where id = visit_id) then
    raise exception 'Deleted custom question ticket remained readable';
  end if;
end
$custom_question_smoke$;
reset role;
