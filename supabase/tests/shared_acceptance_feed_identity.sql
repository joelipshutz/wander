begin;

-- Exercise the real notification acceptance RPC, not hand-authored Feed rows.
do $test$
declare
  owner_id text := 'rec686_accept_owner'; recipient_id text := 'rec686_accept_recipient';
  stranger_id text := 'rec686_accept_stranger';
  place_id uuid; owner_save uuid; recipient_save uuid; source_visit uuid; accepted_visit uuid;
  operation_id uuid; source_event uuid; accepted_event uuid; group_id uuid;
  invitation record; result jsonb; retried jsonb; rows_json jsonb; detail jsonb;
  original_time timestamptz; scenario text; proc record; duplicate_id uuid;
begin
  if exists(select 1 from public.profiles where id in(owner_id,recipient_id,stranger_id))
  then raise exception 'reserved REC-686 fixture exists'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claim.canonical_user_id','',true);
  insert into public.profiles(id,handle,display_name) values
    (owner_id,'rec686owner','Example owner'),(recipient_id,'rec686recipient','Example recipient'),
    (stranger_id,'rec686stranger','Example stranger');
  insert into public.follows(follower_user_id,followed_user_id,source) values
    (owner_id,recipient_id,'profile'),(recipient_id,owner_id,'profile');

  foreach scenario in array array['new','wanna','repeat'] loop
    place_id := gen_random_uuid(); owner_save := gen_random_uuid(); recipient_save := gen_random_uuid();
    source_visit := gen_random_uuid(); accepted_visit := gen_random_uuid(); operation_id := gen_random_uuid();
    insert into public.places(id,canonical_name,category,latitude,longitude,source_provider,source_provider_place_id)
      values(place_id,'Acceptance fixture '||scenario,'coffee',0,0,'manual','rec686-'||scenario);
    insert into public.user_places(id,user_id,place_id,status,visibility,source_type)
      values(owner_save,owner_id,place_id,'been','followers','manual');
    insert into public.place_visits(id,user_place_id,visited_at,note,rating_score)
      values(source_visit,owner_save,now()-interval '1 day','Owner fixture note',3.5);
    select id into source_event from public.feed_events where visit_id=source_visit and event_type='place_been';
    if scenario <> 'new' then
      insert into public.user_places(id,user_id,place_id,status,visibility,source_type,created_at)
        values(recipient_save,recipient_id,place_id,
          case when scenario='wanna' then 'wanna_go' else 'been' end,'followers','manual',now()-interval '2 days');
    end if;

    perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
    set local role authenticated;
    select * into invitation from public.create_shared_visit_invites(source_visit,array[recipient_id]);
    perform set_config('request.jwt.claims',jsonb_build_object('sub',recipient_id,'role','authenticated')::text,true);
    result := public.accept_shared_visit(invitation.participant_id,invitation.invitation_generation,1,
      operation_id,recipient_save,accepted_visit,'{"visibility":"followers"}'::jsonb,
      jsonb_build_object('visited_at',now()-interval '1 day','note','Recipient fixture note',
        'rating_score',4.5,'attribute_answers','[]'::jsonb),'[]'::jsonb,array[]::uuid[]);
    retried := public.accept_shared_visit(invitation.participant_id,invitation.invitation_generation,1,
      operation_id,recipient_save,accepted_visit,'{"visibility":"followers"}'::jsonb,
      jsonb_build_object('visited_at',now()-interval '1 day','note','Retry must not replace note',
        'rating_score',1,'attribute_answers','[]'::jsonb),'[]'::jsonb,array[]::uuid[]);
    if retried->>'visit_id' is distinct from result->>'visit_id'
    then raise exception 'accept retry changed identity: %',scenario; end if;
    reset role;
    select id,occurred_at into accepted_event,original_time from public.feed_events
      where visit_id=accepted_visit and event_type='place_been';
    if accepted_event is null or (select count(*) from public.feed_events where visit_id=accepted_visit)<>1
    then raise exception 'acceptance lacks one explicit check-in event: %',scenario; end if;
    if exists(select 1 from public.feed_events where user_place_id=recipient_save and event_type='place_saved')
    then raise exception 'acceptance left a duplicate social-save event: %',scenario; end if;

    set local role authenticated;
    select jsonb_agg(to_jsonb(c)) into rows_json
      from public.feed_shared_visit_context(array[source_event,accepted_event]) c;
    if jsonb_array_length(rows_json) is distinct from 2
      or (select count(distinct c->>'group_id') from jsonb_array_elements(rows_json) c)<>1
    then raise exception 'real acceptance did not group: %',scenario; end if;
    select jsonb_agg(activity) into rows_json from public.shared_visit_posts(accepted_event);
    if jsonb_array_length(rows_json) is distinct from 2
      or not exists(select 1 from jsonb_array_elements(rows_json) p
        where p->>'id'=accepted_event::text and (p->>'rating')::numeric=4.5 and p->>'note'='Recipient fixture note')
      or not exists(select 1 from jsonb_array_elements(rows_json) p
        where p->>'id'=source_event::text and (p->>'rating')::numeric=3.5 and p->>'note'='Owner fixture note')
    then raise exception 'shared posts lost independent notes or ratings: %',scenario; end if;
    detail := public.activity_detail(accepted_event);
    if detail->>'event_type'<>'place_been' or (detail->>'rating')::numeric is distinct from 4.5
    then raise exception 'activity detail lost accepted rating: %',scenario; end if;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger_id,'role','authenticated')::text,true);
    if exists(select 1 from public.feed_shared_visit_context(array[source_event,accepted_event]))
      or exists(select 1 from public.shared_visit_posts(accepted_event))
    then raise exception 'stranger gained shared content'; end if;
    reset role;

    if scenario='new' then
      -- Recreate the historically emitted envelope, retaining real receipt
      -- provenance, then exercise the same helper used by the migration.
      update public.feed_events set event_type='place_saved',visit_id=null where id=accepted_event;
      insert into public.activity_comments(activity_id,author_user_id,body)
        values(accepted_event,recipient_id,'Preserve fixture discussion');
      insert into public.activity_likes(activity_id,user_id) values(accepted_event,owner_id);
      perform app.repair_shared_acceptance_feed_event(operation_id);
      perform app.repair_shared_acceptance_feed_event(operation_id);
      if not exists(select 1 from public.feed_events where id=accepted_event
        and event_type='place_been' and visit_id=accepted_visit and occurred_at=original_time)
        or (select count(*) from public.activity_comments where activity_id=accepted_event)<>1
        or (select count(*) from public.activity_likes where activity_id=accepted_event)<>1
      then raise exception 'historical repair changed identity/time/engagement'; end if;

      update public.feed_events set event_type='place_saved',visit_id=null where id=accepted_event;
      duplicate_id:=gen_random_uuid();
      insert into public.feed_events(id,actor_user_id,event_type,user_place_id,place_id,occurred_at,created_at)
        values(duplicate_id,recipient_id,'place_saved',recipient_save,place_id,original_time,original_time);
      perform app.repair_shared_acceptance_feed_event(operation_id);
      if exists(select 1 from public.feed_events where id in(accepted_event,duplicate_id) and visit_id is not null)
      then raise exception 'ambiguous historical events were guessed'; end if;
      delete from public.feed_events where id=duplicate_id;
      update public.feed_events set created_at=created_at-interval '1 second' where id=accepted_event;
      perform app.repair_shared_acceptance_feed_event(operation_id);
      if exists(select 1 from public.feed_events where id=accepted_event and visit_id is not null)
      then raise exception 'unproven older social save was changed'; end if;
      update public.feed_events set created_at=original_time where id=accepted_event;
      perform app.repair_shared_acceptance_feed_event(operation_id);
    end if;
  end loop;

  for proc in select * from pg_proc where oid in
    ('app.repair_shared_acceptance_feed_event(uuid)'::regprocedure,
     'app.record_shared_acceptance_feed_identity()'::regprocedure)
  loop
    if not proc.prosecdef or proc.provolatile<>'v'
      or not ('search_path=pg_catalog, public, app'=any(proc.proconfig))
      or has_function_privilege('authenticated',proc.oid,'execute')
      or has_function_privilege('anon',proc.oid,'execute')
      or exists(select 1 from aclexplode(coalesce(proc.proacl,acldefault('f',proc.proowner)))
        where grantee=0 and privilege_type='EXECUTE')
    then raise exception 'private repair security metadata changed'; end if;
  end loop;
end;
$test$;

rollback;
