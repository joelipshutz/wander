begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(1);

-- Isolated fictional viewport; all profiles, saves and notifications roll back.
insert into public.profiles(id, handle, display_name, is_private_profile) values
  ('user_rec550_viewer', 'rec550viewer', 'Taste Viewer', false),
  ('user_rec550_cold', 'rec550cold', 'Cold Viewer', false),
  ('user_rec550_owner', 'rec550owner', 'Community Owner', false),
  ('user_rec550_private', 'rec550private', 'Private Owner', true),
  ('user_rec550_blocked', 'rec550blocked', 'Blocked Owner', false);
insert into public.blocks(blocker_user_id, blocked_user_id)
values ('user_rec550_blocked', 'user_rec550_viewer');
insert into public.places(id, canonical_name, category, primary_category, subcategory,
  latitude, longitude, source_provider, source_provider_place_id)
select ('55000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
  'Taste Fixture ' || i, 'coffee_tea_sweets', 'coffee_tea_sweets',
  case when i <= 140 then 'Bakery' else 'Coffee shop' end,
  case when i = 221 then -40 else -45 end, 140, 'mapkit', 'rec550-' || i
from generate_series(1,224) i;
insert into public.user_places(id, user_id, place_id, status, visibility, rating_score, note, source_type)
select ('55010000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
  case i when 221 then 'user_rec550_viewer' when 222 then 'user_rec550_private'
    when 223 then 'user_rec550_blocked' else 'user_rec550_owner' end,
  ('55000000-0000-0000-0000-' || lpad(i::text,12,'0'))::uuid,
  case when i in (221,224) then 'wanna_go' else 'been' end,
  case when i = 221 then 'self' else 'followers' end,
  case when i in (221,224) then null when i <= 140 then 5 else 4 end,
  'Private fixture note', 'manual'
from generate_series(1,224) i;
-- The initial cold-start check has no active taste. Later the private Wanna
-- outside the viewport must still influence recall inside this viewport.
update public.user_places set deleted_at=now()
where user_id='user_rec550_viewer';

do $metadata$
begin
  if not exists(select 1 from pg_proc
    where oid='public.featured_places_in_view(double precision,double precision,double precision,double precision)'::regprocedure
      and prosecdef and provolatile='s'
      and 'search_path=public, app'=any(proconfig) and 'statement_timeout=3s'=any(proconfig))
    or has_function_privilege('anon','public.featured_places_in_view(double precision,double precision,double precision,double precision)','execute')
    or not has_function_privilege('authenticated','public.featured_places_in_view(double precision,double precision,double precision,double precision)','execute')
    or has_function_privilege('authenticated','app.featured_taste_subcategory(text,text)','execute') then
    raise exception 'Featured security metadata or grants changed';
  end if;
end
$metadata$;

set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.canonical_user_id','',true);
select set_config('request.jwt.claim.sub','user_rec550_viewer',true);
do $cold$
begin
  if (select count(distinct place_id) from public.featured_places_in_view(-46,139,-44,141)) <> 120
    or exists(select 1 from public.featured_places_in_view(-46,139,-44,141) where subcategory='Coffee shop') then
    raise exception 'Cold start must retain existing high-quality community ranking';
  end if;
end
$cold$;
reset role;
update public.user_places set deleted_at=null, category_override='coffee_tea_sweets',
  subcategory_override='Cafe', category_override_source='user'
where user_id='user_rec550_viewer';
set local role authenticated;
do $taste$
begin
  if (select count(distinct place_id) from public.featured_places_in_view(-46,139,-44,141) where subcategory='Coffee shop') <> 60
    or (select count(distinct place_id) from public.featured_places_in_view(-46,139,-44,141) where subcategory='Bakery') <> 60 then
    raise exception 'Cafe taste must recall 60 coffee places beyond the old shortlist and retain 60 discovery places';
  end if;
  if exists(select 1 from public.featured_places_in_view(-46,139,-44,141)
    where place_id in ('55000000-0000-0000-0000-000000000222','55000000-0000-0000-0000-000000000223','55000000-0000-0000-0000-000000000224')
      or note is not null or owner_user_id <> 'recme_featured_community'
      or category_override is not null or subcategory_override is not null
      or recommended_count <> 1 or community_save_count <> 1) then
    raise exception 'Taste bypassed eligibility, leaked private details or changed real support counts';
  end if;
end
$taste$;
select set_config('request.jwt.claim.sub','user_rec550_cold',true);
do $other_viewer$
begin
  if exists(select 1 from public.featured_places_in_view(-46,139,-44,141) where subcategory='Coffee shop') then
    raise exception 'Another viewer inherited private taste';
  end if;
end
$other_viewer$;
reset role;
update public.user_places set subcategory_override='Bakery' where user_id='user_rec550_viewer';
set local role authenticated;
select set_config('request.jwt.claim.sub','user_rec550_viewer',true);
do $own_override$
begin
  if exists(select 1 from public.featured_places_in_view(-46,139,-44,141) where subcategory='Coffee shop') then
    raise exception 'Recall ignored viewer personal taxonomy';
  end if;
end
$own_override$;
reset role;
update public.user_places set subcategory_override='Coffee shop',status='been',rating_score=2
where user_id='user_rec550_viewer';
set local role authenticated;
do $disliked$
begin
  if exists(select 1 from public.featured_places_in_view(-46,139,-44,141) where subcategory='Coffee shop') then
    raise exception 'Low-rated Been save became positive taste';
  end if;
end
$disliked$;
reset role;
update public.user_places set rating_score=5 where user_id='user_rec550_viewer';
set local role authenticated;
do $liked$
begin
  if (select count(*) from public.featured_places_in_view(-46,139,-44,141) where subcategory='Coffee shop') <> 60 then
    raise exception 'Highly rated Been save did not influence recall';
  end if;
end
$liked$;
reset role;
update public.user_places set deleted_at=now() where user_id='user_rec550_viewer';
set local role authenticated;
do $deleted$
begin
  if exists(select 1 from public.featured_places_in_view(-46,139,-44,141) where subcategory='Coffee shop') then
    raise exception 'Deleted taste continued to influence recall';
  end if;
end
$deleted$;
select pass('Featured taste recall, cold start, private taxonomy, privacy boundaries, real counts and limits passed');
select * from finish();
rollback;
