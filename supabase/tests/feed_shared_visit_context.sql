begin;

do $test$
declare
  owner_id text := 'rec636_shared_feed_owner'; recipient_id text := 'rec636_shared_feed_recipient';
  viewer_id text := 'rec636_shared_feed_viewer'; pending_id text := 'rec636_shared_feed_pending';
  place_id uuid := gen_random_uuid(); owner_save uuid := gen_random_uuid(); recipient_save uuid := gen_random_uuid();
  source_visit uuid := gen_random_uuid(); accepted_visit uuid := gen_random_uuid(); independent_visit uuid := gen_random_uuid();
  source_event uuid := gen_random_uuid(); accepted_event uuid := gen_random_uuid(); independent_event uuid := gen_random_uuid();
  shared_group uuid := gen_random_uuid(); rows_json jsonb; proc record;
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

  update public.profiles set is_private_profile=true where id=recipient_id;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
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
  then raise exception 'declined invitation retained Feed grouping'; end if;
  reset role;
  update public.shared_visit_participants set status='accepted' where group_id=shared_group and user_id=recipient_id;
  update public.place_visits set deleted_at=now() where id=accepted_visit;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
  then raise exception 'deleted accepted visit retained attribution'; end if;
  reset role;
  update public.place_visits set deleted_at=null where id=accepted_visit;
  update public.profiles set is_private_profile=true where id=owner_id;
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
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
  then raise exception 'blocked participant leaked through companion metadata'; end if;
  reset role;
  update public.shared_visit_groups set cancelled_at=now() where id=shared_group;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
  set local role authenticated;
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
  then raise exception 'cancelled group retained Feed attribution'; end if;
  perform set_config('request.jwt.claims','{}',true);
  if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
  then raise exception 'missing authenticated viewer leaked attribution'; end if;
  reset role;
end
$test$;
rollback;
