begin;
savepoint rec590_source_authorization;
create extension if not exists pgtap;
set local search_path = public, extensions;
select plan(1);

-- Exact authenticated payloads and roles, with reserved identities only.
-- Assertions raise on failure so the same test works in the hosted smoke gate.
do $test$
declare
  owner_id text := 'user_codex_privacy_source';
  viewer_id text := 'user_codex_privacy_viewer';
  stranger_id text := 'user_codex_privacy_stranger';
  venue_id uuid := gen_random_uuid();
  source_save uuid := gen_random_uuid();
  source_visit uuid := gen_random_uuid();
  source_photo uuid := gen_random_uuid();
  own_photo uuid := gen_random_uuid();
  pending_photo uuid := gen_random_uuid();
  copied_photo uuid;
  copied_visit uuid := gen_random_uuid();
  copied_save uuid := gen_random_uuid();
  operation_id uuid := gen_random_uuid();
  participant_id uuid;
  invitation_generation integer;
  snapshot_revision integer;
  source_path text;
  copied_path text;
  own_path text;
  pending_path text;
  saved jsonb;
  accepted jsonb;
  payload jsonb;
  companion_id uuid;
  intentional_id uuid;
  repaired_id uuid;
  repaired_count integer;
  event_id uuid := gen_random_uuid();
  claim_id uuid := gen_random_uuid();
  import_visit uuid := gen_random_uuid();
  import_commit uuid := gen_random_uuid();
  import_event uuid := gen_random_uuid();
  import_claim uuid := gen_random_uuid();
  import_key text := 'rec590-smoke-' || gen_random_uuid();
  fn regprocedure;
begin
  foreach fn in array array[
    'public.can_read_visit_photo(text,text)'::regprocedure,
    'public.authorize_push_notification_delivery(uuid,uuid)'::regprocedure,
    'app.can_read_photo_source(text,uuid)'::regprocedure,
    'app.notification_source_readable(public.notification_events)'::regprocedure
  ] loop
    if not exists (select 1 from pg_proc where oid = fn and prosecdef
        and proconfig @> array['search_path=pg_catalog, public, app']) then
      raise exception 'source authorization RPC security posture mismatch: %', fn;
    end if;
    if has_function_privilege('anon', fn, 'execute') then
      raise exception 'anonymous source authorization access: %', fn;
    end if;
  end loop;
  if not has_function_privilege('authenticated', 'public.can_read_visit_photo(text,text)', 'execute')
    or has_function_privilege('authenticated', 'app.can_read_photo_source(text,uuid)', 'execute')
    or has_function_privilege('authenticated', 'public.authorize_push_notification_delivery(uuid,uuid)', 'execute')
    or not has_function_privilege('service_role', 'public.authorize_push_notification_delivery(uuid,uuid)', 'execute')
    or has_table_privilege('authenticated', 'app.visit_photo_sources', 'select')
    or has_table_privilege('authenticated', 'app.private_list_companion_origins', 'insert') then
    raise exception 'source authorization grants mismatch';
  end if;

  insert into public.profiles(id, handle, display_name, default_visibility, is_private_profile)
  values(owner_id, 'codex_privacy_source', 'Smoke source', 'followers', false),
        (viewer_id, 'codex_privacy_viewer', 'Smoke viewer', 'followers', false),
        (stranger_id, 'codex_privacy_stranger', 'Smoke stranger', 'followers', false);
  insert into public.follows(follower_user_id, followed_user_id, source)
  values(viewer_id, owner_id, 'profile'), (owner_id, viewer_id, 'profile');
  insert into public.places(id, canonical_name, category, latitude, longitude, source_provider)
  values(venue_id, 'Privacy smoke venue', 'coffee_tea_sweets', 0, 0, 'codex_smoke');
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type)
  values(source_save,owner_id,venue_id,'been','followers','manual');
  insert into public.place_visits(id,user_place_id,note,rating_score)
  values(source_visit,source_save,'Source note',4);
  source_path := owner_id || '/' || source_visit || '/' || source_photo || '.jpg';
  insert into public.visit_photos(id,visit_id,storage_path,content_type,upload_state)
  values(source_photo,source_visit,source_path,'image/jpeg','uploaded');
  insert into storage.objects(bucket_id,name) values('visit-photos',source_path);

  perform set_config('request.jwt.claims', jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',owner_id,true);
  set local role authenticated;
  -- Owner upload retries need metadata access, but must never grant signing.
  pending_path := owner_id || '/' || source_visit || '/' || pending_photo || '.jpg';
  insert into public.visit_photos(id,visit_id,storage_path,content_type,upload_state)
    values(pending_photo,source_visit,pending_path,'image/jpeg','pending_upload');
  perform set_config('storage.operation','storage.object.upload',true);
  insert into storage.objects(bucket_id,name) values('visit-photos',pending_path);
  perform set_config('storage.operation','storage.object.upload_update',true);
  update storage.objects set metadata='{}'::jsonb
    where bucket_id='visit-photos' and name=pending_path;
  if not found or not exists(select 1 from public.visit_photos where id=pending_photo) then
    raise exception 'owner pending upload retry lost metadata access';
  end if;
  perform set_config('storage.operation','storage.object.sign',true);
  if exists(select 1 from storage.objects where bucket_id='visit-photos' and name=pending_path) then
    raise exception 'owner management policy permits signed URLs';
  end if;
  perform set_config('storage.operation','storage.object.delete',true);
  -- Storage rejects direct SQL deletion even for synthetic metadata. Leave the
  -- row for transaction rollback; verify the owner-delete policy and its SELECT
  -- prerequisite without bypassing the Storage service's deletion guard.
  if not exists(select 1 from storage.objects where bucket_id='visit-photos' and name=pending_path)
    or not exists(select 1 from pg_policies where schemaname='storage' and tablename='objects'
      and policyname='visit photo objects owner delete' and cmd='DELETE'
      and roles @> array['authenticated']::name[] and qual like '%owns_place_visit%') then
    raise exception 'owner delete policy or metadata access is missing';
  end if;
  perform public.create_shared_visit_invites(source_visit,array[viewer_id]);
  reset role;
  select p.id,p.invitation_generation,p.snapshot_revision
  into participant_id,invitation_generation,snapshot_revision
  from public.shared_visit_participants p join public.shared_visit_groups g on g.id=p.group_id
  where g.source_visit_id=source_visit and p.user_id=viewer_id;
  if participant_id is null then raise exception 'missing shared fixture'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer_id,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',viewer_id,true);
  perform set_config('storage.operation','storage.object.get_authenticated',true);
  set local role authenticated;
  if not public.can_read_visit_photo('visit-photos',source_path)
    or not exists(select 1 from storage.objects where bucket_id='visit-photos' and name=source_path)
    or not exists(select 1 from public.get_shared_visit_context(participant_id,invitation_generation)) then
    raise exception 'authorized follower cannot read source';
  end if;
  perform set_config('storage.operation','storage.object.sign',true);
  if exists(select 1 from storage.objects where bucket_id='visit-photos' and name=source_path) then
    raise exception 'follower can mint a persistent signed URL';
  end if;
  reset role;
  update public.user_places set visibility='self' where id=source_save;
  set local role authenticated;
  if public.can_read_visit_photo('visit-photos',source_path)
    or exists(select 1 from public.get_shared_visit_context(participant_id,invitation_generation))
    or exists(select 1 from public.list_shared_visit_inbox() where source_visit_id=source_visit) then
    raise exception 'hidden source survives in photos or invitation snapshots';
  end if;
  reset role;
  update public.user_places set visibility='followers' where id=source_save;
  -- Hiding cancels the invitation. The owner must explicitly invite again;
  -- a cancelled generation must never become acceptable just by unhiding.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',owner_id,true);
  set local role authenticated;
  perform public.create_shared_visit_invites(source_visit,array[viewer_id]);
  reset role;
  select p.invitation_generation,p.snapshot_revision into invitation_generation,snapshot_revision
    from public.shared_visit_participants p where p.id=participant_id;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer_id,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',viewer_id,true);
  set local role authenticated;
  accepted := public.accept_shared_visit(participant_id,invitation_generation,snapshot_revision,
    operation_id,copied_save,copied_visit,'{"visibility":"followers"}',
    '{"visited_at":"2026-09-01T19:00:00Z","note":"Recipient independent note","rating_score":5,"attribute_answers":[]}',
    '[]',array[source_photo]);
  reset role;
  copied_photo := (accepted->'photo_copies'->0->>'destination_photo_id')::uuid;
  copied_path := accepted->'photo_copies'->0->>'destination_path';
  if copied_photo is null or not exists(select 1 from app.visit_photo_sources
      where photo_id=copied_photo and source_photo_id=source_photo) then
    raise exception 'accepted photo lost its immutable provenance';
  end if;
  update public.visit_photos set upload_state='uploaded' where id=copied_photo;
  own_path := viewer_id || '/' || copied_visit || '/' || own_photo || '.jpg';
  insert into public.visit_photos(id,visit_id,storage_path,content_type,upload_state)
  values(own_photo,copied_visit,own_path,'image/jpeg','uploaded');
  insert into storage.objects(bucket_id,name) values('visit-photos',copied_path),('visit-photos',own_path);
  update public.user_places set visibility='self' where id=source_save;
  set local role authenticated;
  if public.can_read_visit_photo('visit-photos',copied_path)
    or exists(select 1 from public.visit_photos where id=copied_photo) then
    raise exception 'copied photo survives revoked source access';
  end if;
  if not public.can_read_visit_photo('visit-photos',own_path)
    or not exists(select 1 from public.place_visits where id=copied_visit
      and note='Recipient independent note' and rating_score=5) then
    raise exception 'source revocation removed independent recipient content';
  end if;
  payload := public.accept_shared_visit(participant_id,invitation_generation,snapshot_revision,
    operation_id,copied_save,copied_visit,'{}','{}','[]',array[source_photo]);
  if jsonb_array_length(payload->'photo_copies') <> 0 then
    raise exception 'idempotent acceptance leaked a revoked copy manifest';
  end if;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger_id,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',stranger_id,true);
  set local role authenticated;
  begin
    perform public.accept_shared_visit(participant_id,invitation_generation,snapshot_revision,
      operation_id,copied_save,copied_visit,'{}','{}','[]',array[source_photo]);
    raise exception 'stranger replay exposed another recipient acceptance';
  exception when raise_exception then
    if sqlerrm <> 'shared_visit_invitation_not_found' then raise; end if;
  end;
  reset role;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer_id,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',viewer_id,true);

  -- Pending/claimed envelopes and inbox rows must obey the current source.
  perform app.ensure_notification_preferences(viewer_id);
  update public.notification_preferences set push_enabled=true,followed_activity_enabled=true where user_id=viewer_id;
  insert into public.notification_device_tokens(user_id,environment,device_token)
    values(viewer_id,'sandbox',repeat('e',64));
  insert into public.notification_events(id,recipient_user_id,actor_user_id,notification_type,
    title,body,data,status,claim_token,claim_expires_at,expires_at,latest_at)
  values(event_id,viewer_id,owner_id,'followed_place_visit','Private venue','Private note',
    jsonb_build_object('visit_id',source_visit,'private_note','Must not leave server'),
    'claimed',claim_id,now()+interval '5 minutes',now()+interval '1 hour',now()+interval '1 hour');
  set local role authenticated;
  if exists(select 1 from public.notification_events where id=event_id) then
    raise exception 'notification inbox leaked a hidden source';
  end if;
  reset role;
  set local role service_role;
  if public.authorize_push_notification_delivery(event_id,claim_id) is not null then
    raise exception 'post-claim source revocation still authorizes push';
  end if;
  reset role;
  if not exists(select 1 from public.notification_events where id=event_id
      and status='skipped' and claim_token is null) then
    raise exception 'denied delivery did not invalidate the claim';
  end if;
  update public.user_places set visibility='followers' where id=source_save;
  update public.notification_events set status='claimed',claim_token=claim_id,
    claim_expires_at=now()+interval '5 minutes' where id=event_id;
  set local role service_role;
  if public.authorize_push_notification_delivery(event_id,gen_random_uuid()) is not null then
    raise exception 'stale claim was accepted';
  end if;
  payload := public.authorize_push_notification_delivery(event_id,claim_id);
  if payload is null or payload->>'title' <> 'New activity on Astir'
    or payload->>'body' <> 'Open Astir to view.' or payload->'data' ? 'private_note'
    or jsonb_array_length(payload->'tokens') <> 1 then
    raise exception 'authorized push did not return a fresh minimal envelope';
  end if;
  reset role;

  -- A deployed REC-589 import envelope has no visit_id. Keep valid groups
  -- deliverable, but recheck their current source visibility before sending.
  if to_regprocedure('app.import_notification_content(text,text,text)') is not null then
    insert into public.place_visits(id,user_place_id,note,notification_silent,sender_import_id,sender_import_commit_id)
      values(import_visit,source_save,'Import smoke',true,import_key,import_commit);
    insert into app.import_notification_commits(owner_user_id,import_id,commit_id,silent,visit_ids,sealed_at)
      values(owner_id,import_key,import_commit,false,array[import_visit],now());
    insert into public.notification_events(id,recipient_user_id,actor_user_id,notification_type,
      title,body,data,status,claim_token,claim_expires_at,expires_at,latest_at)
      values(import_event,viewer_id,owner_id,'followed_place_visit','Import','Private venue',
        jsonb_build_object('sender_import_id',import_key,'place_id',venue_id),
        'claimed',import_claim,now()+interval '5 minutes',now()+interval '1 hour',now()+interval '1 hour');
    set local role service_role;
    payload := public.authorize_push_notification_delivery(import_event,import_claim);
    if payload is null or payload->>'body' <> 'Open Astir to view.' then
      raise exception 'authorized grouped import lost its delivery contract';
    end if;
    reset role;
    update public.user_places set visibility='self' where id=source_save;
    set local role service_role;
    if public.authorize_push_notification_delivery(import_event,import_claim) is not null then
      raise exception 'hidden grouped import remains deliverable';
    end if;
    reset role;
    update public.user_places set visibility='followers' where id=source_save;
  end if;

  -- A private account and either-direction block revoke inherited photo access.
  update public.profiles set is_private_profile=true where id=owner_id;
  set local role authenticated;
  if public.can_read_visit_photo('visit-photos',copied_path) then
    raise exception 'private source profile left its copied photo readable';
  end if;
  reset role;
  update public.profiles set is_private_profile=false where id=owner_id;
  -- Leaving private mode deliberately keeps previous saves self-only.
  -- Explicitly restore this fixture's audience before testing block revocation.
  update public.user_places set visibility='followers' where id=source_save;
  insert into public.blocks(blocker_user_id,blocked_user_id) values(owner_id,viewer_id);
  set local role authenticated;
  if public.can_read_visit_photo('visit-photos',source_path)
    or public.can_read_visit_photo('visit-photos',copied_path)
    or not public.can_read_visit_photo('visit-photos',own_path) then
    raise exception 'block did not revoke only source-derived photos';
  end if;
  reset role;
  delete from public.blocks where blocker_user_id=owner_id and blocked_user_id=viewer_id;
  insert into public.follows(follower_user_id,followed_user_id,source)
    values(viewer_id,owner_id,'profile') on conflict do nothing;
  set local role authenticated;
  if not public.can_read_visit_photo('visit-photos',copied_path) then
    raise exception 'source authorization did not recover before deletion test';
  end if;
  reset role;

  -- Removing source bytes cannot leave a previously accepted copy readable.
  delete from public.visit_photos where id=source_photo;
  set local role authenticated;
  if public.can_read_visit_photo('visit-photos',copied_path)
    or not public.can_read_visit_photo('visit-photos',own_path) then
    raise exception 'deleted source photo did not revoke only its copies';
  end if;
  reset role;

  -- New automatic saves start private even when an old client passes followers.
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  perform set_config('request.jwt.claim.sub',owner_id,true);
  set local role authenticated;
  saved := public.save_own_place(
    jsonb_build_object('canonical_name','Companion smoke','category','coffee_tea_sweets',
      'latitude',0,'longitude',0,'source_provider','codex_smoke',
      'source_provider_place_id','privacy-companion-'||gen_random_uuid()),
    '{"status":"wanna_go","visibility":"followers","source_type":"manual","is_private_list_companion":true}', '[]');
  companion_id := (saved->>'user_place_id')::uuid;
  reset role;
  if not exists(select 1 from public.user_places where id=companion_id and visibility='self')
    or not exists(select 1 from app.private_list_companion_origins where user_place_id=companion_id) then
    raise exception 'automatic companion not private at creation';
  end if;
  -- Explicitly widening later is an intentional audience choice, preserved by repair.
  update public.user_places set visibility='followers',note='Intentional note' where id=companion_id;
  perform app.repair_private_list_companions();
  if not exists(select 1 from public.user_places where id=companion_id and visibility='followers') then
    raise exception 'repair overwrote a later explicit audience choice';
  end if;
  set local role authenticated;
  saved := public.save_own_place((select to_jsonb(place) from public.places place join public.user_places own on own.place_id=place.id where own.id=companion_id),
    '{"status":"wanna_go","visibility":"self","note":"Overwrite","source_type":"manual","is_private_list_companion":true}', '[]');
  if not exists(select 1 from public.user_places where id=companion_id
      and visibility='followers' and note='Intentional note') then
    raise exception 'private list addition overwrote an existing intentional save';
  end if;
  reset role;
  -- Historical repair requires evidence; ambiguous public saves are not rewritten.
  insert into public.places(id,canonical_name,category,latitude,longitude,source_provider)
    values(gen_random_uuid(),'Repair smoke','coffee_tea_sweets',0,0,'codex_smoke') returning id into venue_id;
  insert into public.user_places(user_id,place_id,status,visibility,source_type)
    values(owner_id,venue_id,'wanna_go','followers','manual') returning id into repaired_id;
  insert into public.user_places(user_id,place_id,status,visibility,source_type)
    values(stranger_id,venue_id,'wanna_go','followers','manual') returning id into intentional_id;
  insert into app.private_list_companion_origins(user_place_id) values(repaired_id);
  repaired_count := app.repair_private_list_companions();
  if repaired_count <> 1
    or not exists(select 1 from public.user_places where id=repaired_id and visibility='self')
    or not exists(select 1 from public.user_places where id=intentional_id and visibility='followers') then
    raise exception 'evidence-only repair widened its scope or missed proven data';
  end if;
end;
$test$;

select pass('source authorization, copied photos, notification claims, and companion provenance');
select * from finish();
rollback to savepoint rec590_source_authorization;
release savepoint rec590_source_authorization;
rollback;
