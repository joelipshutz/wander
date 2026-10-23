begin;

do $test$
declare
  owner_id text := 'rec636_shared_feed_owner'; recipient_id text := 'rec636_shared_feed_recipient';
  viewer_id text := 'rec636_shared_feed_viewer'; pending_id text := 'rec636_shared_feed_pending';
  place_id uuid := gen_random_uuid(); owner_save uuid := gen_random_uuid(); recipient_save uuid := gen_random_uuid();
  source_visit uuid := gen_random_uuid(); accepted_visit uuid := gen_random_uuid(); independent_visit uuid := gen_random_uuid();
  source_event uuid := gen_random_uuid(); accepted_event uuid := gen_random_uuid(); independent_event uuid := gen_random_uuid();
  shared_group uuid := gen_random_uuid(); rows_json jsonb; proc record;
  source_alias uuid := gen_random_uuid(); competing_event uuid := gen_random_uuid();
  source_photo uuid := gen_random_uuid(); copied_photo uuid := gen_random_uuid(); own_photo uuid := gen_random_uuid();
begin
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  select * into proc from pg_proc where oid='public.feed_shared_visit_context(uuid[])'::regprocedure;
  if not proc.prosecdef or proc.provolatile<>'s'
    or not ('search_path=pg_catalog, public, app'=any(proc.proconfig))
    or not has_function_privilege('authenticated',proc.oid,'execute')
    or has_function_privilege('anon',proc.oid,'execute')
    or exists(select 1 from aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) where grantee=0 and privilege_type='EXECUTE')
  then raise exception 'shared Feed RPC security metadata changed'; end if;
  if has_table_privilege('authenticated','public.shared_visit_groups','select')
    or has_table_privilege('authenticated','public.shared_visit_participants','select')
  then raise exception 'shared Feed must not expose private group tables'; end if;

  if exists(select 1 from public.profiles where id in(owner_id,recipient_id,viewer_id,pending_id))
  then raise exception 'reserved shared Feed fixtures already exist'; end if;
  select * into proc from pg_proc where oid='public.shared_visit_posts(uuid)'::regprocedure;
  if not proc.prosecdef or proc.provolatile<>'s'
    or not ('search_path=pg_catalog, public, app'=any(proc.proconfig))
    or not has_function_privilege('authenticated',proc.oid,'execute')
    or has_function_privilege('anon',proc.oid,'execute')
    or exists(select 1 from aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner))) where grantee=0 and privilege_type='EXECUTE')
  then raise exception 'shared post RPC security metadata changed'; end if;
  if has_function_privilege('authenticated','app.feed_shared_visit_source(uuid)','execute')
    or has_function_privilege('anon','app.feed_shared_visit_source(uuid)','execute')
  then raise exception 'private historical resolver exposed'; end if;

  insert into public.profiles(id,handle,display_name,is_private_profile) values
    (owner_id,'rec636sfo','Owner',false),(recipient_id,'rec636sfr','Recipient',false),
    (viewer_id,'rec636sfv','Viewer',false),(pending_id,'rec636sfp','Pending',false);
  insert into public.follows(follower_user_id,followed_user_id,source) values
    (viewer_id,owner_id,'profile'),(viewer_id,recipient_id,'profile'),
    (owner_id,recipient_id,'profile'),(recipient_id,owner_id,'profile');
  insert into public.places(id,canonical_name,category,latitude,longitude,source_provider,source_provider_place_id)
    values(place_id,'Shared Feed fixture','coffee',0,0,'manual','rec636-shared-feed');
  insert into public.user_places(id,user_id,place_id,status,visibility,source_type) values
    (owner_save,owner_id,place_id,'been','followers','manual'),
    (recipient_save,recipient_id,place_id,'been','followers','manual');
  insert into public.place_visits(id,user_place_id,visited_at) values
    (source_visit,owner_save,now()),(accepted_visit,recipient_save,now()),(independent_visit,recipient_save,now());
  delete from public.feed_events where actor_user_id in(owner_id,recipient_id);
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,visit_id,occurred_at) values
    (source_event,owner_id,'place_been',owner_save,place_id,source_visit,now()),
    (accepted_event,recipient_id,'place_been',recipient_save,place_id,accepted_visit,now()),
    (independent_event,recipient_id,'place_been',recipient_save,place_id,independent_visit,now());
  insert into public.shared_visit_groups(id,source_visit_id,place_id,owner_user_id)
    values(shared_group,source_visit,place_id,owner_id);
  insert into public.shared_visit_participants(group_id,user_id,invited_by_user_id,status,visit_id) values
    (shared_group,owner_id,owner_id,'owner',source_visit),
    (shared_group,recipient_id,owner_id,'pending',null),
    (shared_group,pending_id,owner_id,'pending',null);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  select jsonb_agg(to_jsonb(c)) into rows_json from public.feed_shared_visit_context(array[source_event]) c;
  if jsonb_array_length(rows_json->0->'companions') is distinct from 2
    or exists(select 1 from jsonb_array_elements(rows_json->0->'companions') c where c->>'status'<>'pending')
  then raise exception 'owner pending companions must carry explicit status'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer_id,'role','authenticated')::text,true);
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event,independent_event]))
  then raise exception 'pending group identity or independent visit leaked to viewer'; end if;
  reset role;

  update public.shared_visit_participants set status='accepted',visit_id=accepted_visit
    where group_id=shared_group and user_id=recipient_id;
  set local role authenticated;
  select jsonb_agg(to_jsonb(c)) into rows_json from public.feed_shared_visit_context(array[source_event,accepted_event,independent_event]) c;
  if jsonb_array_length(rows_json) is distinct from 2
    or exists(select 1 from jsonb_array_elements(rows_json) c where (c->>'group_id')::uuid<>shared_group)
    or exists(select 1 from jsonb_array_elements(rows_json) c,
      jsonb_array_elements(c->'companions') companion where companion->>'status'='pending')
  then raise exception 'accepted co-visits must share exact group without pending or independent posts'; end if;
  if exists(select 1 from public.feed_shared_visit_context(array[independent_event]))
  then raise exception 'independent check-in at same place was falsely grouped'; end if;
  reset role;

  insert into public.visit_photos(id,visit_id,storage_bucket,storage_path,content_type,byte_size,width,height,sort_order,upload_state) values
    (source_photo,source_visit,'visit-photos',owner_id||'/'||source_visit||'/'||source_photo||'.jpg','image/jpeg',1200,100,80,0,'uploaded'),
    (copied_photo,accepted_visit,'visit-photos',recipient_id||'/'||accepted_visit||'/'||copied_photo||'.jpg','image/jpeg',1200,100,80,0,'uploaded'),
    (own_photo,accepted_visit,'visit-photos',recipient_id||'/'||accepted_visit||'/'||own_photo||'.jpg','image/jpeg',1200,100,80,1,'uploaded');
  insert into app.visit_photo_sources(photo_id,source_photo_id) values(copied_photo,source_photo);
  set local role authenticated;
  select jsonb_agg(to_jsonb(p)) into rows_json from public.shared_visit_posts(accepted_event) p;
  if jsonb_array_length(rows_json) is distinct from 2
    or exists(select 1 from jsonb_array_elements(rows_json) p where (p->>'comment_activity_id')::uuid<>source_event)
    or not exists(select 1 from jsonb_array_elements(rows_json) p where p->'activity'->>'id'=accepted_event::text
      and jsonb_array_length(p->'activity'->'media')=2)
  then raise exception 'participant-only request must include original group and authorized media'; end if;
  reset role;
  update public.visit_photos set deleted_at=now() where id=source_photo;
  set local role authenticated;
  select jsonb_agg(to_jsonb(p)) into rows_json from public.shared_visit_posts(accepted_event) p;
  if not exists(select 1 from jsonb_array_elements(rows_json) p where p->'activity'->>'id'=accepted_event::text
      and jsonb_array_length(p->'activity'->'media')=1
      and p->'activity'->'media'->0->>'id'=own_photo::text)
    or exists(select 1 from jsonb_array_elements(rows_json) p, jsonb_array_elements(p->'activity'->'media') photo
      where photo->>'id' in(source_photo::text,copied_photo::text))
  then raise exception 'copied photo source deletion must not hide independently authored content or leak revoked media'; end if;
  reset role;
  update public.visit_photos set deleted_at=null where id=source_photo;

  -- Historic root posts predate visit_id. Reuse a proven original backfill,
  -- retaining both the old requested alias and each canonical discussion ID.
  update public.place_visits set backfilled_from_user_place=false where user_place_id=owner_save;
  update public.place_visits set backfilled_from_user_place=true,note='Synthetic original note'
    where id=source_visit;
  update public.place_visits set note='Synthetic accepted note' where id=accepted_visit;
  update public.feed_events set visit_id=null where id=source_event;
  insert into app.activity_event_aliases(alias_id,activity_id) values(source_alias,source_event);
  set local role authenticated;
  select jsonb_agg(to_jsonb(c)) into rows_json from public.feed_shared_visit_context(array[source_alias,accepted_event]) c;
  if jsonb_array_length(rows_json) is distinct from 2
    or not exists(select 1 from jsonb_array_elements(rows_json) c where (c->>'activity_id')::uuid=source_alias)
  then raise exception 'legacy accepted group or alias identity lost'; end if;
  select jsonb_agg(to_jsonb(p)) into rows_json from public.shared_visit_posts(source_alias) p;
  if jsonb_array_length(rows_json) is distinct from 2
    or exists(select 1 from jsonb_array_elements(rows_json) p where (p->>'comment_activity_id')::uuid<>source_event)
    or not exists(select 1 from jsonb_array_elements(rows_json) p where p->'activity'->>'note'='Synthetic original note')
    or not exists(select 1 from jsonb_array_elements(rows_json) p where p->'activity'->>'note'='Synthetic accepted note')
  then raise exception 'complete legacy originals or stable comment target missing'; end if;
  if exists(select 1 from public.shared_visit_posts(independent_event))
  then raise exception 'unrelated check-in gained group posts'; end if;
  reset role;
  update public.feed_events set occurred_at=occurred_at+interval '1 second' where id=independent_event;
  update public.place_visits set backfilled_from_user_place=false where user_place_id=recipient_save;
  update public.place_visits set backfilled_from_user_place=true where id=accepted_visit;
  update public.feed_events set visit_id=null where id=accepted_event;
  set local role authenticated;
  if (select count(*) from public.shared_visit_posts(accepted_event)) <> 2
  then raise exception 'historical accepted original failed exact compatibility proof'; end if;
  reset role;
  update public.feed_events set visit_id=accepted_visit where id=accepted_event;
  -- Exact timestamp alone is insufficient: two candidate parent events must
  -- remain separate. No repair, guessed identity, or later visit borrowing.
  insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at)
    select competing_event,source.actor_user_id,source.event_type,source.user_place_id,source.place_id,source.occurred_at
    from public.feed_events source where source.id=source_event;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,competing_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'ambiguous historic root was guessed'; end if;
  reset role;
  delete from public.feed_events where id=competing_event;
  update public.feed_events set visit_id=source_visit where id=source_event;
  -- An explicit later independent visit wins over a coincident old timestamp.
  update public.feed_events set visit_id=null where id=independent_event;
  update public.feed_events set visit_id=independent_visit where id=source_event;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event]))
  then raise exception 'explicit identity borrowed the legacy shared visit'; end if;
  reset role;
  update public.feed_events set visit_id=source_visit where id=source_event;
  update public.feed_events set visit_id=independent_visit where id=independent_event;

  update public.profiles set is_private_profile=true where id=recipient_id;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'private companion or activity leaked'; end if;
  reset role;
  update public.profiles set is_private_profile=false where id=recipient_id;
  -- Privacy also cancels membership; restore only this synthetic fixture so
  -- the next assertion isolates self-only visit visibility.
  update public.shared_visit_participants set status='accepted',cancelled_at=null
    where group_id=shared_group and user_id=recipient_id;
  update public.user_places set visibility='self' where id=recipient_save;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'self-only accepted visit leaked'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',recipient_id,'role','authenticated')::text,true);
  if not exists(select 1 from public.feed_shared_visit_context(array[accepted_event]))
  then raise exception 'recipient lost their own accepted co-visit'; end if;
  reset role;
  update public.user_places set visibility='followers' where id=recipient_save;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',viewer_id,'role','authenticated')::text,true);

  update public.shared_visit_participants set status='declined' where group_id=shared_group and user_id=recipient_id;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'declined invitation retained Feed grouping'; end if;
  reset role;
  update public.shared_visit_participants set status='accepted' where group_id=shared_group and user_id=recipient_id;
  update public.place_visits set deleted_at=now() where id=accepted_visit;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'deleted accepted visit retained attribution'; end if;
  reset role;
  update public.place_visits set deleted_at=null where id=accepted_visit;
  update public.profiles set is_private_profile=true where id=owner_id;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'private source owner leaked through the accepted copy'; end if;
  reset role;
  update public.profiles set is_private_profile=false where id=owner_id;
  update public.user_places set visibility='followers' where id=owner_save;
  update public.shared_visit_groups set cancelled_at=null where id=shared_group;
  update public.shared_visit_participants set status='accepted',cancelled_at=null
    where group_id=shared_group and user_id=recipient_id;
  update public.shared_visit_participants set status='pending',cancelled_at=null
    where group_id=shared_group and user_id=pending_id;
  insert into public.blocks(blocker_user_id,blocked_user_id) values(viewer_id,recipient_id);
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'blocked participant leaked through companion metadata'; end if;
  reset role;
  update public.shared_visit_groups set cancelled_at=now() where id=shared_group;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'cancelled group retained Feed attribution'; end if;
  perform set_config('request.jwt.claims','{}',true);
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
    or exists(select 1 from public.shared_visit_posts(source_event))
  then raise exception 'missing authenticated viewer leaked attribution'; end if;
  reset role;
  set local role anon;
  begin
    perform public.shared_visit_posts(source_event);
    raise exception 'anonymous shared posts execution unexpectedly permitted';
  exception when insufficient_privilege then null;
  end;
  reset role;
end
$test$;
rollback;
