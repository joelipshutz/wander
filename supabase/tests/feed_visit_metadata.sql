begin;
create extension if not exists pgtap;
select no_plan();
create temporary table visit_feed_results(message text) on commit drop;
grant select, insert on visit_feed_results to authenticated, anon;
create temporary table visit_feed_fixture(
  sequence integer, parent_id uuid, visit_id uuid, event_id uuid,
  expected_note text, expected_rating numeric, expected_date timestamptz,
  expected_answers jsonb
) on commit drop;
grant select, insert on visit_feed_fixture to authenticated;
insert into public.profiles(id,handle,display_name,is_private_profile) values
('rec614_visit_owner','rec614visitowner','Visit Owner',false),
('rec614_visit_viewer','rec614visitviewer','Visit Viewer',false),
('rec614_visit_stranger','rec614visitstranger','Visit Stranger',false);
insert into public.follows(follower_user_id,followed_user_id,source)
values ('rec614_visit_viewer','rec614_visit_owner','profile');

-- Actual authenticated save RPCs create three separate check-ins at one place.
select set_config('request.jwt.claim.sub','rec614_visit_owner',true);
select set_config('request.jwt.claims','{"sub":"rec614_visit_owner","role":"authenticated"}',true);
set local role authenticated;
do $fixtures$
declare
  i integer;
  visit uuid;
  parent uuid;
  saved jsonb;
  note text;
  rating numeric;
  visited timestamptz;
  answers jsonb;
begin
  for i in 1..3 loop
    visit := gen_random_uuid();
    note := case when i < 3 then 'Visit ' || i else null end;
    rating := case when i < 3 then i + 1 else null end;
    visited := '2026-09-01T12:00:00Z'::timestamptz + (i - 1) * interval '1 day';
    answers := case when i < 3 then jsonb_build_array(jsonb_build_object(
      'question_key','coffee_tags','value_type','multi_tag','value',jsonb_build_array('visit-' || i)))
      else '[]'::jsonb end;
    saved := public.save_own_check_in(
      '{"canonical_name":"Per Visit Regression","category":"coffee","latitude":0,"longitude":0,"source_provider":"manual","source_provider_place_id":"rec614-visit-metadata"}',
      jsonb_build_object('id',parent,'status','been','visibility','followers','source_type','manual'),
      answers,
      jsonb_build_object('id',visit,'visited_at',visited,'note',note,'rating_score',rating,'attribute_answers',answers),
      null);
    parent := (saved->>'user_place_id')::uuid;
    insert into visit_feed_fixture values (i,parent,visit,null,note,rating,visited,answers);
  end loop;
end;
$fixtures$;
reset role;
update visit_feed_fixture f set event_id=e.id from public.feed_events e where e.visit_id=f.visit_id;
insert into visit_feed_results select is((select count(distinct parent_id)::integer from visit_feed_fixture),1,'repeat saves share one venue parent');
insert into visit_feed_results select is((select count(distinct event_id)::integer from visit_feed_fixture),3,'each check-in has its own event');
insert into visit_feed_results select is((select count(distinct visit_id)::integer from visit_feed_fixture),3,'each check-in has its own visit');

-- Force a stale parent summary, as seen in the reported empty repeat check-in.
update public.user_places set note='Parent summary from another visit', rating_score=5,
  rating_signal='love', saved_at='2026-01-01T00:00:00Z', created_at='2026-01-01T00:00:00Z'
where id=(select parent_id from visit_feed_fixture limit 1);
insert into public.visit_photos(id,visit_id,storage_path,content_type,upload_state)
select gen_random_uuid(),visit_id,'rec614_visit_owner/' || visit_id || '/photo.jpg','image/jpeg','uploaded'
from visit_feed_fixture where sequence < 3;

set local role authenticated;
insert into visit_feed_results select is(d.attribute_answers,f.expected_answers,'owner answers stay on visit ' || f.sequence)
from visit_feed_fixture f join public.own_place_visit_details(array[f.parent_id]) d on d.id=f.visit_id;
select set_config('request.jwt.claim.sub','rec614_visit_viewer',true);
select set_config('request.jwt.claims','{"sub":"rec614_visit_viewer","role":"authenticated"}',true);
create temporary table visit_feed_rendered as
select f.*,public.activity_detail(f.event_id) as detail,
  (select a from jsonb_array_elements(public.activity_feed('everyone',null,50)->'activity') a
    where a->>'id'=f.event_id::text) as card
from visit_feed_fixture f;
insert into visit_feed_results select is(detail->>'note',expected_note,'detail preserves visit note including null ' || sequence) from visit_feed_rendered;
insert into visit_feed_results select is(card->>'note',expected_note,'Feed preserves visit note including null ' || sequence) from visit_feed_rendered;
insert into visit_feed_results select is((detail->>'rating')::numeric,expected_rating,'detail preserves visit rating including null ' || sequence) from visit_feed_rendered;
insert into visit_feed_results select is((card->>'rating')::numeric,expected_rating,'Feed preserves visit rating including null ' || sequence) from visit_feed_rendered;
insert into visit_feed_results select is((detail->'place'->>'visited_at')::timestamptz,expected_date,'visit date belongs to this check-in ' || sequence) from visit_feed_rendered;
insert into visit_feed_results select is(detail->'place'->>'rating_signal',null::text,'parent rating signal cannot leak into visit ' || sequence) from visit_feed_rendered;
insert into visit_feed_results select is(detail->'place'->>'status','been','explicit visit retains check-in status ' || sequence) from visit_feed_rendered;
insert into visit_feed_results select is(card->'place',detail->'place','Feed/detail have the same visit metadata ' || sequence) from visit_feed_rendered;
insert into visit_feed_results select is(jsonb_array_length(m.media),case when f.sequence < 3 then 1 else 0 end,
  'activity media contains only its own visit photos ' || f.sequence)
from visit_feed_fixture f join public.activity_media(array[f.event_id]) m on m.activity_id=f.event_id;
insert into visit_feed_results select ok(not exists(
  select 1 from visit_feed_fixture f join public.activity_media(array[f.event_id]) m on m.activity_id=f.event_id,
    jsonb_array_elements(m.media) p
  where not exists(select 1 from public.visit_photos ph where ph.id=(p->>'id')::uuid and ph.visit_id=f.visit_id)),
  'no activity borrows another visit photo');
select public.set_activity_like(event_id,true) from visit_feed_fixture where sequence=1;
insert into visit_feed_results select is((public.activity_engagement_summaries(array[event_id])->0->>'like_count')::integer,
  case when sequence=1 then 1 else 0 end,'engagement remains per event ' || sequence) from visit_feed_fixture;
reset role;
insert into visit_feed_results select is((r.detail->'place'->>'created_at')::timestamptz,v.created_at,'created timestamp belongs to visit ' || r.sequence)
from visit_feed_rendered r join public.place_visits v on v.id=r.visit_id;
insert into visit_feed_results select is((r.detail->'place'->>'saved_at')::timestamptz,v.created_at,'saved timestamp belongs to visit ' || r.sequence)
from visit_feed_rendered r join public.place_visits v on v.id=r.visit_id;
insert into visit_feed_results select is((r.detail->'place'->>'updated_at')::timestamptz,v.updated_at,'updated timestamp belongs to visit ' || r.sequence)
from visit_feed_rendered r join public.place_visits v on v.id=r.visit_id;
insert into visit_feed_results select is(app.feed_place_projection(parent_id,null)->>'note','Parent summary from another visit',
  'visit-less legacy events retain parent projection') from visit_feed_fixture where sequence=1;
insert into visit_feed_results select is(app.feed_place_projection(parent_id,gen_random_uuid()),null::jsonb,
  'unknown explicit visit cannot fall back to parent') from visit_feed_fixture where sequence=1;

-- Editing one visit must not rewrite another, including a deliberately empty one.
update public.place_visits set note='Edited first visit',rating_score=4 where id=(select visit_id from visit_feed_fixture where sequence=1);
set local role authenticated;
insert into visit_feed_results select is(public.activity_detail(event_id)->>'note',expected_note,'editing another visit preserves note ' || sequence)
from visit_feed_fixture where sequence>1;
insert into visit_feed_results select is((public.activity_detail(event_id)->>'rating')::numeric,expected_rating,'editing another visit preserves rating ' || sequence)
from visit_feed_fixture where sequence>1;
reset role;

-- Existing source visibility gates remain authoritative for all entry points.
select set_config('request.jwt.claim.sub','rec614_visit_stranger',true);
select set_config('request.jwt.claims','{"sub":"rec614_visit_stranger","role":"authenticated"}',true);
set local role authenticated;
insert into visit_feed_results select throws_ok($$select public.activity_detail(event_id) from visit_feed_fixture where sequence=1$$,
  'P0001','activity_not_visible','stranger cannot read another person check-in');
insert into visit_feed_results select is((select count(*)::integer from public.activity_media((select array_agg(event_id) from visit_feed_fixture))),0,'stranger cannot read visit media');
reset role;
insert into public.blocks(blocker_user_id,blocked_user_id) values ('rec614_visit_owner','rec614_visit_viewer');
select set_config('request.jwt.claim.sub','rec614_visit_viewer',true);
select set_config('request.jwt.claims','{"sub":"rec614_visit_viewer","role":"authenticated"}',true);
set local role authenticated;
insert into visit_feed_results select throws_ok($$select public.activity_detail(event_id) from visit_feed_fixture where sequence=1$$,
  'P0001','activity_not_visible','block hides visit detail');
insert into visit_feed_results select is((select count(*)::integer
  from jsonb_array_elements(public.activity_feed('everyone',null,50)->'activity') a
  where a->>'id' in (select event_id::text from visit_feed_fixture)),0,'block hides these Feed cards');
reset role;
delete from public.blocks where blocker_user_id='rec614_visit_owner' and blocked_user_id='rec614_visit_viewer';
update public.place_visits set deleted_at=now() where id=(select visit_id from visit_feed_fixture where sequence=3);
set local role authenticated;
insert into visit_feed_results select throws_ok($$select public.activity_detail(event_id) from visit_feed_fixture where sequence=3$$,
  'P0001','activity_not_visible','deleted visit cannot fall back to a live parent');
reset role;
insert into visit_feed_results select ok((select prosecdef and provolatile='s' and prorettype='jsonb'::regtype
  and 'search_path=public, app'=any(proconfig) from pg_proc where oid='app.feed_place_projection(uuid,uuid)'::regprocedure),
  'projection preserves stable definer return type and search path');
insert into visit_feed_results select ok(not has_function_privilege('authenticated','app.feed_place_projection(uuid,uuid)','execute')
  and not has_function_privilege('anon','app.feed_place_projection(uuid,uuid)','execute'), 'projection remains private');
insert into visit_feed_results select ok(has_function_privilege('authenticated',signature,'execute')
  and not has_function_privilege('anon',signature,'execute'),signature || ' preserves authenticated-only access')
from (values ('public.activity_detail(uuid)'),('public.activity_media(uuid[])')) f(signature);
insert into visit_feed_results select ok((select prosecdef and provolatile='s' and proretset
  and prorettype='record'::regtype and 'search_path=pg_catalog, public, app'=any(proconfig)
  from pg_proc where oid='public.activity_media(uuid[])'::regprocedure),
  'media preserves stable definer return type and search path');
insert into visit_feed_results select ok(
  position('app.canonical_activity_id(requested.id)' in pg_get_functiondef('public.activity_media(uuid[])'::regprocedure))>0,
  'media retains canonical aliases and requested cache keys');
insert into visit_feed_results select ok(to_regprocedure('app.can_read_photo_source(text,uuid)') is null
  or position('app.can_read_photo_source(app.current_user_id(), photo.id)' in pg_get_functiondef('public.activity_media(uuid[])'::regprocedure))>0,
  'media preserves installed source-photo privacy gate');
do $strict_pgtap$
declare diagnostics text;
begin
  select string_agg(message,E'\n') into diagnostics from visit_feed_results where message like 'not ok%';
  if diagnostics is not null then raise exception 'Visit Feed assertions failed: %',diagnostics; end if;
  select string_agg(result.message,E'\n') into diagnostics from finish() as result(message);
  if diagnostics is not null and diagnostics like '%failed%' then raise exception 'Visit Feed plan failed: %',diagnostics; end if;
end;
$strict_pgtap$;
select count(*) as visit_feed_assertions_passed from visit_feed_results;
rollback;
