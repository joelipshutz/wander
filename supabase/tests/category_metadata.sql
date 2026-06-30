begin;

create extension if not exists pgtap;

select plan(10);

select is(
  app.place_primary_category('4-star hotel'),
  'hotel',
  'hotel provider subtypes normalize to hotel'
);

insert into public.profiles (id, handle, display_name)
values ('user_category_owner', 'categoryowner', 'Category Owner');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'user_category_owner', true);

select isnt_empty(
  $$
    select *
    from app.save_own_place(
      '{
        "canonical_name": "Jitlada Category Test",
        "category": "thai restaurant",
        "latitude": 34.098,
        "longitude": -118.306,
        "source_provider": "mapkit",
        "source_provider_place_id": "category-jitlada",
        "confidence": 0.9
      }'::jsonb,
      '{
        "status": "been",
        "visibility": "followers",
        "nearby_confirmed": true,
        "source_type": "manual",
        "rating_score": 5
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'legacy/provider subcategory save succeeds'
);

select is(
  (select category from public.places where source_provider_place_id = 'category-jitlada'),
  'restaurant',
  'legacy places.category is backfilled to primary category'
);

select is(
  (select primary_category from public.places where source_provider_place_id = 'category-jitlada'),
  'restaurant',
  'primary_category stores the filterable category'
);

select is(
  (select subcategory from public.places where source_provider_place_id = 'category-jitlada'),
  'Thai Restaurant',
  'subcategory stores the provider subtype'
);

select isnt_empty(
  $$
    select *
    from app.save_own_place(
      '{
        "canonical_name": "Corner Bodega Category Test",
        "category": "coffee",
        "primary_category": "coffee",
        "subcategory": "Coffee shop",
        "category_source": "user",
        "raw_provider_type": "coffee shop",
        "latitude": 34.08,
        "longitude": -118.28,
        "source_provider": "mapkit",
        "source_provider_place_id": "category-bodega",
        "confidence": 0.91
      }'::jsonb,
      '{
        "status": "wanna_go",
        "visibility": "followers",
        "nearby_confirmed": false,
        "source_type": "manual",
        "category_override": "shop",
        "subcategory_override": "Corner store",
        "category_override_source": "user",
        "category_override_confidence": 1
      }'::jsonb,
      '[]'::jsonb
    )
  $$,
  'user category override save succeeds'
);

select is(
  (select category from public.places where source_provider_place_id = 'category-bodega'),
  'coffee',
  'user override does not rewrite shared place category'
);

select is(
  (select category_source from public.places where source_provider_place_id = 'category-bodega'),
  'legacy',
  'user source is not stored as the shared place category source'
);

select is(
  (select category_override from public.user_places up join public.places p on p.id = up.place_id where p.source_provider_place_id = 'category-bodega'),
  'shop',
  'user override is stored on user_places'
);

select isnt_empty(
  $$
    select *
    from app.profile_visible_places('user_category_owner', null, array['shop'])
    where canonical_name = 'Corner Bodega Category Test'
  $$,
  'profile filters match effective user override category'
);

select * from finish();

rollback;
