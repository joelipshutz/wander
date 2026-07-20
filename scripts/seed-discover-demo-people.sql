-- REC-90 operational seed for the linked rec.me project.
--
-- This is intentionally not a migration: it removes only the exact verified
-- Codex smoke fixtures currently present in the hosted project, then upserts a
-- small set of clearly synthetic demo profiles and their reviews of existing
-- places. Re-running it updates the demo copy without creating duplicates.

begin;

do $$
declare
  unexpected_smoke_profile_count integer;
  required_place_count integer;
  joe_profile_count integer;
begin
  select count(*)
  into unexpected_smoke_profile_count
  from public.profiles profile
  join (
    values
      ('user_codex_rpc_1780434967523', 'codex_rpc_test'),
      ('user_codex_direct_1780434985782', 'codex_direct_test'),
      ('user_3Eb6hVABCXRiZ3tcbdvlu2NAh2j', 'joelipshutz'),
      ('user_codex_redeploy_1780435290696', 'codex_redeploy_test'),
      ('user_3Ebv9C5tCX5vxdZSLYOPfZ6Q17h', 'codex_viewer_1780459929610_9555448a03857'),
      ('user_3Ebv9JJBvbu8WfUPY5hlmX5Prjh', 'codex_owner_1780459929610_9555448a03857'),
      ('user_3EbvHmyxp32m8amP4TLoJ5uKmp7', 'codex_viewer_1780459996787_47f4ff1b9581e'),
      ('user_3EbvHj0jGwThKtEe6wLtHGj9KRT', 'codex_owner_1780459996787_47f4ff1b9581e'),
      ('user_3EbvOdZZlK2GtmXB8yDuIBD4yBL', 'codex_viewer_1780460052614_295cb193ba933'),
      ('user_3EbvOohQtFkkf1e4tFBIP5wu08C', 'codex_owner_1780460052614_295cb193ba933'),
      ('user_3Eg3nOzkSaPXX9yYjE22OzQml6O', 'codex_check_1780586550991_c5e735e81bbc8'),
      ('user_3Eg3wXnMQF06nKGD4g2UfV2RtXf', 'codex_check_1780586623202_42a337beb92d'),
      ('user_3Eg8MSNAa0sBTCWsmBtEYdCRW99', 'codex_owner_1780588803013_cc91f4bf0e1b2'),
      ('user_3Eg8MVEliZN75pi4bmjHG5NLyWG', 'codex_viewer_1780588803013_cc91f4bf0e1b2'),
      ('user_codex_supabase_smoke', 'codex_smoke'),
      ('user_codex_supabase_smoke_collab', 'codex_smoke_collab')
  ) expected(id, handle) on expected.id = profile.id
  where profile.handle <> expected.handle;

  if unexpected_smoke_profile_count > 0 then
    raise exception 'A targeted smoke id now belongs to an unexpected handle; refusing cleanup';
  end if;

  select count(*)
  into required_place_count
  from public.places
  where id = any(array[
    'dde724d3-a62e-41f8-af8c-103c30b2a259'::uuid,
    'ba68d6b5-c6d6-4e18-a3d9-e26b24044ecb'::uuid,
    '57303890-c046-4cba-8452-f7aa51f0dc36'::uuid,
    '615752ad-be5b-475a-aba8-878b525778c0'::uuid,
    'f3772fd2-dc86-4ab3-a6bc-86ba4b2344e0'::uuid,
    'd3e34f76-2811-4a32-b177-0307d6023f74'::uuid,
    'ba6d5946-7162-4ca2-8578-2dcbb83e748c'::uuid,
    '3053f0c2-7613-4c1f-b62d-1879a78b4201'::uuid,
    '491fcf0e-1843-4f9a-93a1-c7a86a995115'::uuid,
    '9bdb8477-9065-40b4-be8c-0a41cb5e62ec'::uuid,
    'f279dd41-a4cb-4814-ba39-2a53ccb83c18'::uuid,
    '231ff142-ed25-4113-9923-412e4d62c4fb'::uuid,
    '095694ee-b69f-41c4-85a3-0566ae81409a'::uuid,
    '6157a3a4-c973-431f-b6af-c1da94da4945'::uuid,
    '681f0071-edd2-4335-a677-9f4eb9eed0ac'::uuid,
    'a6c2019b-376e-4420-8cd1-873068f0d9bc'::uuid,
    '5fe153a7-d7ee-454f-874b-7e084121fd5b'::uuid,
    '8cc66a40-dec5-4abe-9a86-e02611011cc3'::uuid
  ]);

  if required_place_count <> 18 then
    raise exception 'Expected 18 existing seed places, found %; refusing partial seed', required_place_count;
  end if;

  select count(*)
  into joe_profile_count
  from public.profiles
  where id = 'user_3EhATWssjvHxwGiUaoWR5VTgeoy'
    and handle = 'jolipshutz'
    and deleted_at is null
    and not is_private_profile;

  if joe_profile_count <> 1 then
    raise exception 'Expected exact public Joe test profile; refusing follow seed';
  end if;
end
$$;

delete from public.profiles
where id = any(array[
  'user_codex_rpc_1780434967523',
  'user_codex_direct_1780434985782',
  'user_3Eb6hVABCXRiZ3tcbdvlu2NAh2j',
  'user_codex_redeploy_1780435290696',
  'user_3Ebv9C5tCX5vxdZSLYOPfZ6Q17h',
  'user_3Ebv9JJBvbu8WfUPY5hlmX5Prjh',
  'user_3EbvHmyxp32m8amP4TLoJ5uKmp7',
  'user_3EbvHj0jGwThKtEe6wLtHGj9KRT',
  'user_3EbvOdZZlK2GtmXB8yDuIBD4yBL',
  'user_3EbvOohQtFkkf1e4tFBIP5wu08C',
  'user_3Eg3nOzkSaPXX9yYjE22OzQml6O',
  'user_3Eg3wXnMQF06nKGD4g2UfV2RtXf',
  'user_3Eg8MSNAa0sBTCWsmBtEYdCRW99',
  'user_3Eg8MVEliZN75pi4bmjHG5NLyWG',
  'user_codex_supabase_smoke',
  'user_codex_supabase_smoke_collab'
]::text[]);

delete from public.places place
where place.id = '9f0108ee-aaf4-4f1b-af43-7396e1b16e43'::uuid
  and place.source_provider = 'codex_smoke'
  and not exists (
    select 1 from public.user_places user_place where user_place.place_id = place.id
  );

insert into public.profiles (
  id,
  handle,
  display_name,
  bio,
  home_area,
  default_visibility,
  is_private_profile,
  created_at,
  updated_at,
  deleted_at
)
values
  ('user_recme_demo_maya_chen', 'mayachen', 'Maya Chen', 'Coffee, noodles, bookstores, and low-key corners worth returning to.', 'Los Feliz, Los Angeles', 'followers', false, '2026-07-18 20:06:00+00', now(), null),
  ('user_recme_demo_elena_torres', 'elenaeatsla', 'Elena Torres', 'Eastside dinners, neighborhood bakeries, and patios made for a long catch-up.', 'Silver Lake, Los Angeles', 'followers', false, '2026-07-18 20:05:00+00', now(), null),
  ('user_recme_demo_marcus_reed', 'marcusreed', 'Marcus Reed', 'Weekend hikes, neighborhood bars, and anywhere with a great sandwich.', 'Culver City, California', 'followers', false, '2026-07-18 20:04:00+00', now(), null),
  ('user_recme_demo_priya_shah', 'priyapicks', 'Priya Shah', 'Design-friendly cafes, vegetarian spots, and quiet places to linger.', 'Santa Monica, California', 'followers', false, '2026-07-18 20:03:00+00', now(), null),
  ('user_recme_demo_theo_brooks', 'theobrooks', 'Theo Brooks', 'Tacos, pizza, sake, and the late-night places that are actually worth it.', 'Mar Vista, Los Angeles', 'followers', false, '2026-07-18 20:02:00+00', now(), null),
  ('user_recme_demo_samira_patel', 'samirapatel', 'Samira Patel', 'Dessert, celebratory dinners, and places worth crossing town for.', 'West Hollywood, California', 'followers', false, '2026-07-18 20:01:00+00', now(), null)
on conflict (id) do update set
  handle = excluded.handle,
  display_name = excluded.display_name,
  bio = excluded.bio,
  home_area = excluded.home_area,
  default_visibility = excluded.default_visibility,
  is_private_profile = excluded.is_private_profile,
  updated_at = now(),
  deleted_at = null;

insert into public.user_places (
  id,
  user_id,
  place_id,
  status,
  note,
  visibility,
  nearby_confirmed,
  visited_at,
  saved_at,
  source_type,
  created_at,
  updated_at,
  deleted_at,
  rating_score
)
values
  ('de900001-0000-4000-8000-000000000001', 'user_recme_demo_maya_chen', 'dde724d3-a62e-41f8-af8c-103c30b2a259', 'been', 'Best when I can grab a patio seat early. The espresso is excellent; weekend lines move slower than they look.', 'followers', true, '2026-07-12 16:30:00+00', '2026-07-12 16:30:00+00', 'manual', '2026-07-12 16:30:00+00', now(), null, 4.0),
  ('de900001-0000-4000-8000-000000000002', 'user_recme_demo_maya_chen', 'ba68d6b5-c6d6-4e18-a3d9-e26b24044ecb', 'been', 'The curry ramen is rich without being heavy. Add the egg and go before 7 if you do not want to wait.', 'followers', true, '2026-07-06 02:15:00+00', '2026-07-06 02:15:00+00', 'manual', '2026-07-06 02:15:00+00', now(), null, 4.5),
  ('de900001-0000-4000-8000-000000000003', 'user_recme_demo_maya_chen', '57303890-c046-4cba-8452-f7aa51f0dc36', 'been', 'Quiet enough to read on a weekday afternoon, with genuinely good pour-over. I stay longer than I mean to.', 'followers', true, '2026-06-28 21:00:00+00', '2026-06-28 21:00:00+00', 'manual', '2026-06-28 21:00:00+00', now(), null, 4.5),
  ('de900001-0000-4000-8000-000000000004', 'user_recme_demo_maya_chen', '615752ad-be5b-475a-aba8-878b525778c0', 'been', 'No-frills room, sharp fish, and fast service. Sit at the counter and order from the specials board.', 'followers', true, '2026-06-20 02:00:00+00', '2026-06-20 02:00:00+00', 'manual', '2026-06-20 02:00:00+00', now(), null, 4.5),

  ('de900002-0000-4000-8000-000000000001', 'user_recme_demo_elena_torres', 'f3772fd2-dc86-4ab3-a6bc-86ba4b2344e0', 'been', 'The fried chicken and spicy cabbage are the move. Book ahead; the patio gets loud, but in a fun way.', 'followers', true, '2026-07-14 03:00:00+00', '2026-07-14 03:00:00+00', 'manual', '2026-07-14 03:00:00+00', now(), null, 5.0),
  ('de900002-0000-4000-8000-000000000002', 'user_recme_demo_elena_torres', 'd3e34f76-2811-4a32-b177-0307d6023f74', 'been', 'Great casual dinner when everyone wants something different. The mushroom pita and potatoes never miss.', 'followers', true, '2026-07-08 02:30:00+00', '2026-07-08 02:30:00+00', 'manual', '2026-07-08 02:30:00+00', now(), null, 4.5),
  ('de900002-0000-4000-8000-000000000003', 'user_recme_demo_elena_torres', 'ba6d5946-7162-4ca2-8578-2dcbb83e748c', 'been', 'Crispy, blistered pizza with a wine list that makes a weeknight feel special. The patio is the best seat.', 'followers', true, '2026-06-30 02:45:00+00', '2026-06-30 02:45:00+00', 'manual', '2026-06-30 02:45:00+00', now(), null, 4.5),
  ('de900002-0000-4000-8000-000000000004', 'user_recme_demo_elena_torres', '3053f0c2-7613-4c1f-b62d-1879a78b4201', 'been', 'Excellent breakfast sandwich and a mellow sidewalk setup. Coffee is solid; parking is the only headache.', 'followers', true, '2026-06-22 17:15:00+00', '2026-06-22 17:15:00+00', 'manual', '2026-06-22 17:15:00+00', now(), null, 4.0),

  ('de900003-0000-4000-8000-000000000001', 'user_recme_demo_marcus_reed', '491fcf0e-1843-4f9a-93a1-c7a86a995115', 'been', 'Start early and bring more water than you think. The misty stretch is stunning, but the stone steps get slick.', 'followers', true, '2026-07-10 15:30:00+00', '2026-07-10 15:30:00+00', 'manual', '2026-07-10 15:30:00+00', now(), null, 4.5),
  ('de900003-0000-4000-8000-000000000002', 'user_recme_demo_marcus_reed', '9bdb8477-9065-40b4-be8c-0a41cb5e62ec', 'been', 'Still one of the easiest low-key group hangs on the westside. The beer list and Kogi menu save late nights.', 'followers', true, '2026-07-04 04:00:00+00', '2026-07-04 04:00:00+00', 'manual', '2026-07-04 04:00:00+00', now(), null, 4.0),
  ('de900003-0000-4000-8000-000000000003', 'user_recme_demo_marcus_reed', 'f279dd41-a4cb-4814-ba39-2a53ccb83c18', 'been', 'Tiny, dark, and actually good for conversation before 9. The Thug is sweet, strong, and worth trying once.', 'followers', true, '2026-06-26 03:30:00+00', '2026-06-26 03:30:00+00', 'manual', '2026-06-26 03:30:00+00', now(), null, 4.0),
  ('de900003-0000-4000-8000-000000000004', 'user_recme_demo_marcus_reed', '231ff142-ed25-4113-9923-412e4d62c4fb', 'been', 'The short-rib burger is messy in the right way. Split the fries and eat outside before the evening rush.', 'followers', true, '2026-06-18 02:00:00+00', '2026-06-18 02:00:00+00', 'manual', '2026-06-18 02:00:00+00', now(), null, 4.0),

  ('de900004-0000-4000-8000-000000000001', 'user_recme_demo_priya_shah', '095694ee-b69f-41c4-85a3-0566ae81409a', 'been', 'Beautiful pastries that taste as good as they look. Go early for the seasonal buns and expect a short line.', 'followers', true, '2026-07-13 17:00:00+00', '2026-07-13 17:00:00+00', 'manual', '2026-07-13 17:00:00+00', now(), null, 4.5),
  ('de900004-0000-4000-8000-000000000002', 'user_recme_demo_priya_shah', '6157a3a4-c973-431f-b6af-c1da94da4945', 'been', 'Reliable for a long catch-up when nobody can decide what to eat. Busy, but the patio turnover is quick.', 'followers', true, '2026-07-07 19:30:00+00', '2026-07-07 19:30:00+00', 'manual', '2026-07-07 19:30:00+00', now(), null, 3.5),
  ('de900004-0000-4000-8000-000000000003', 'user_recme_demo_priya_shah', '681f0071-edd2-4335-a677-9f4eb9eed0ac', 'been', 'A bright neighborhood stop with a calm morning crowd. I like it for a quick cappuccino, not a laptop marathon.', 'followers', true, '2026-06-29 16:00:00+00', '2026-06-29 16:00:00+00', 'manual', '2026-06-29 16:00:00+00', now(), null, 4.0),
  ('de900004-0000-4000-8000-000000000004', 'user_recme_demo_priya_shah', 'a6c2019b-376e-4420-8cd1-873068f0d9bc', 'been', 'Friendly baristas and one of the better cold brews near the beach. Limited seating, so plan to walk.', 'followers', true, '2026-06-21 18:45:00+00', '2026-06-21 18:45:00+00', 'manual', '2026-06-21 18:45:00+00', now(), null, 4.0),

  ('de900005-0000-4000-8000-000000000001', 'user_recme_demo_theo_brooks', '5fe153a7-d7ee-454f-874b-7e084121fd5b', 'been', 'Al pastor straight off the spit is the reason to come. Cash moves fastest and the line is worth it after 10.', 'followers', true, '2026-07-11 05:30:00+00', '2026-07-11 05:30:00+00', 'manual', '2026-07-11 05:30:00+00', now(), null, 4.5),
  ('de900005-0000-4000-8000-000000000002', 'user_recme_demo_theo_brooks', '231ff142-ed25-4113-9923-412e4d62c4fb', 'been', 'Order the burger spicy and eat it immediately. The edges stay crisp even under all that sauce.', 'followers', true, '2026-07-03 01:30:00+00', '2026-07-03 01:30:00+00', 'manual', '2026-07-03 01:30:00+00', now(), null, 4.5),
  ('de900005-0000-4000-8000-000000000003', 'user_recme_demo_theo_brooks', 'ba6d5946-7162-4ca2-8578-2dcbb83e748c', 'been', 'The crust has real char and the toppings stay balanced. Best as a group so you can try two pies.', 'followers', true, '2026-06-25 02:30:00+00', '2026-06-25 02:30:00+00', 'manual', '2026-06-25 02:30:00+00', now(), null, 4.5),
  ('de900005-0000-4000-8000-000000000004', 'user_recme_demo_theo_brooks', '8cc66a40-dec5-4abe-9a86-e02611011cc3', 'been', 'Cozy sake bar with staff who make ordering easy. Ask for a flight and add whatever small plate they recommend.', 'followers', true, '2026-06-17 03:00:00+00', '2026-06-17 03:00:00+00', 'manual', '2026-06-17 03:00:00+00', now(), null, 4.5),

  ('de900006-0000-4000-8000-000000000001', 'user_recme_demo_samira_patel', 'f3772fd2-dc86-4ab3-a6bc-86ba4b2344e0', 'been', 'Worth planning around. The menu rewards sharing, and the desserts are every bit as good as the savory plates.', 'followers', true, '2026-07-09 03:00:00+00', '2026-07-09 03:00:00+00', 'manual', '2026-07-09 03:00:00+00', now(), null, 5.0),
  ('de900006-0000-4000-8000-000000000002', 'user_recme_demo_samira_patel', '615752ad-be5b-475a-aba8-878b525778c0', 'been', 'Sit at the bar, trust the specials, and keep the order focused. It is busy but never feels fussy.', 'followers', true, '2026-07-01 02:00:00+00', '2026-07-01 02:00:00+00', 'manual', '2026-07-01 02:00:00+00', now(), null, 4.5),
  ('de900006-0000-4000-8000-000000000003', 'user_recme_demo_samira_patel', '9bdb8477-9065-40b4-be8c-0a41cb5e62ec', 'been', 'A dependable last stop when the night needs food and one more drink. The back patio is better with a group.', 'followers', true, '2026-06-24 04:30:00+00', '2026-06-24 04:30:00+00', 'manual', '2026-06-24 04:30:00+00', now(), null, 4.0),
  ('de900006-0000-4000-8000-000000000004', 'user_recme_demo_samira_patel', 'f279dd41-a4cb-4814-ba39-2a53ccb83c18', 'been', 'A polished little room without the velvet-rope energy. Go early, sit at the bar, and ask for something spirit-forward.', 'followers', true, '2026-06-16 03:15:00+00', '2026-06-16 03:15:00+00', 'manual', '2026-06-16 03:15:00+00', now(), null, 4.5)
on conflict (user_id, place_id) do update set
  status = excluded.status,
  note = excluded.note,
  visibility = excluded.visibility,
  nearby_confirmed = excluded.nearby_confirmed,
  visited_at = excluded.visited_at,
  saved_at = excluded.saved_at,
  source_type = excluded.source_type,
  rating_score = excluded.rating_score,
  updated_at = now(),
  deleted_at = null;

-- Populate Joe's existing-follow shelf without changing Ryan or any other
-- tester's graph. The demo-to-demo edges give the remaining profiles honest,
-- deterministic shared-follow/popularity signals for the recommendation shelf.
insert into public.follows (
  follower_user_id,
  followed_user_id,
  source,
  created_at,
  updated_at
)
values
  ('user_3EhATWssjvHxwGiUaoWR5VTgeoy', 'user_recme_demo_maya_chen', 'profile', '2026-07-20 17:20:00+00', now()),
  ('user_3EhATWssjvHxwGiUaoWR5VTgeoy', 'user_recme_demo_marcus_reed', 'profile', '2026-07-20 17:19:00+00', now()),
  ('user_3EhATWssjvHxwGiUaoWR5VTgeoy', 'user_recme_demo_priya_shah', 'profile', '2026-07-20 17:18:00+00', now()),
  ('user_recme_demo_maya_chen', 'user_recme_demo_elena_torres', 'profile', '2026-07-20 17:17:00+00', now()),
  ('user_recme_demo_marcus_reed', 'user_recme_demo_elena_torres', 'profile', '2026-07-20 17:16:00+00', now()),
  ('user_recme_demo_priya_shah', 'user_recme_demo_elena_torres', 'profile', '2026-07-20 17:15:00+00', now()),
  ('user_recme_demo_maya_chen', 'user_recme_demo_theo_brooks', 'profile', '2026-07-20 17:14:00+00', now()),
  ('user_recme_demo_priya_shah', 'user_recme_demo_theo_brooks', 'profile', '2026-07-20 17:13:00+00', now()),
  ('user_recme_demo_marcus_reed', 'user_recme_demo_samira_patel', 'profile', '2026-07-20 17:12:00+00', now()),
  ('user_recme_demo_priya_shah', 'user_recme_demo_samira_patel', 'profile', '2026-07-20 17:11:00+00', now())
on conflict (follower_user_id, followed_user_id) do nothing;

do $$
declare
  remaining_codex_profiles integer;
  seeded_profiles integer;
  seeded_reviews integer;
  joe_demo_follows integer;
  seeded_graph_edges integer;
begin
  select count(*) into remaining_codex_profiles
  from public.profiles
  where lower(id) like '%codex%'
     or lower(handle) like '%codex%'
     or lower(display_name) like '%codex%'
     or lower(handle) like '%smoke%'
     or lower(display_name) like '%smoke%';

  select count(*) into seeded_profiles
  from public.profiles
  where id in (
    'user_recme_demo_maya_chen',
    'user_recme_demo_elena_torres',
    'user_recme_demo_marcus_reed',
    'user_recme_demo_priya_shah',
    'user_recme_demo_theo_brooks',
    'user_recme_demo_samira_patel'
  );

  select count(*) into seeded_reviews
  from public.user_places
  where user_id in (
    'user_recme_demo_maya_chen',
    'user_recme_demo_elena_torres',
    'user_recme_demo_marcus_reed',
    'user_recme_demo_priya_shah',
    'user_recme_demo_theo_brooks',
    'user_recme_demo_samira_patel'
  )
    and deleted_at is null;

  select count(*) into joe_demo_follows
  from public.follows
  where follower_user_id = 'user_3EhATWssjvHxwGiUaoWR5VTgeoy'
    and followed_user_id in (
      'user_recme_demo_maya_chen',
      'user_recme_demo_marcus_reed',
      'user_recme_demo_priya_shah'
    );

  select count(*) into seeded_graph_edges
  from public.follows
  where (follower_user_id, followed_user_id) in (
    ('user_recme_demo_maya_chen', 'user_recme_demo_elena_torres'),
    ('user_recme_demo_marcus_reed', 'user_recme_demo_elena_torres'),
    ('user_recme_demo_priya_shah', 'user_recme_demo_elena_torres'),
    ('user_recme_demo_maya_chen', 'user_recme_demo_theo_brooks'),
    ('user_recme_demo_priya_shah', 'user_recme_demo_theo_brooks'),
    ('user_recme_demo_marcus_reed', 'user_recme_demo_samira_patel'),
    ('user_recme_demo_priya_shah', 'user_recme_demo_samira_patel')
  );

  if remaining_codex_profiles <> 0
     or seeded_profiles <> 6
     or seeded_reviews <> 24
     or joe_demo_follows <> 3
     or seeded_graph_edges <> 7 then
    raise exception 'Postcondition failed: codex=%, demo_profiles=%, demo_reviews=%, joe_follows=%, graph_edges=%', remaining_codex_profiles, seeded_profiles, seeded_reviews, joe_demo_follows, seeded_graph_edges;
  end if;
end
$$;

commit;

select
  profile.id,
  profile.handle,
  profile.display_name,
  count(distinct user_place.id) filter (where user_place.deleted_at is null) as review_count,
  count(distinct follow.follower_user_id) as follower_count
from public.profiles profile
left join public.user_places user_place on user_place.user_id = profile.id
left join public.follows follow on follow.followed_user_id = profile.id
where profile.id in (
  'user_recme_demo_maya_chen',
  'user_recme_demo_elena_torres',
  'user_recme_demo_marcus_reed',
  'user_recme_demo_priya_shah',
  'user_recme_demo_theo_brooks',
  'user_recme_demo_samira_patel'
)
group by profile.id, profile.handle, profile.display_name
order by profile.created_at desc;
