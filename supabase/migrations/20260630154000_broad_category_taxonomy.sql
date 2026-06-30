begin;

create or replace function app.place_category_normalized(input_value text)
returns text
language sql
immutable
as $$
  select trim(
    regexp_replace(
      regexp_replace(lower(coalesce(input_value, '')), '[_&/-]+', ' ', 'g'),
      '[^a-z0-9 ]+',
      ' ',
      'g'
    )
  );
$$;

create or replace function app.place_primary_category(input_value text)
returns text
language sql
immutable
as $$
  select case
    when normalized in ('food drink', 'food and drink') then 'food_drink'
    when normalized in ('outdoors nature', 'outdoors and nature') then 'outdoors_nature'
    when normalized in ('arts culture faith', 'arts culture and faith') then 'arts_culture_faith'
    when normalized = 'entertainment' then 'entertainment'
    when normalized in ('health wellness', 'health and wellness') then 'health_wellness'
    when normalized in ('sports fitness', 'sports and fitness') then 'sports_fitness'
    when normalized = 'shopping' then 'shopping'
    when normalized = 'services' then 'services'
    when normalized = 'lodging' then 'lodging'
    when normalized in ('transportation transit', 'transportation and transit') then 'transportation_transit'
    when normalized = 'education' then 'education'
    when normalized in ('work venues', 'work and venues') then 'work_venues'
    when normalized in ('home neighborhood', 'home and neighborhood') then 'home_neighborhood'
    when normalized in ('public services', 'public service') then 'public_services'
    when normalized similar to '%(coffee|cafe|espresso|roaster|bakery|tea shop|restaurant|taqueria|ramen|sushi|pizza|diner|kitchen|grill|noodle|taco|food market|fast food|food truck|brunch|bar|brewery|winery|cocktail|pub|nightlife)%' then 'food_drink'
    when normalized similar to '%(hike|hiking|trail|trailhead|waterfall|hot spring|canyon|mountain|observatory|park|playground|garden|plaza|beach|lake|national park|campground|picnic area|marina)%' then 'outdoors_nature'
    when normalized similar to '%(museum|gallery|art gallery|public art|historic|landmark|monument|cultural center|spiritual|church|temple|shrine|mosque|synagogue|chapel|cathedral|meditation)%' then 'arts_culture_faith'
    when normalized similar to '%(tourist attraction|attraction|movie|cinema|concert|music venue|arena|stadium|arcade|bowling|zoo|aquarium|amusement|theme park|comedy|escape room)%' then 'entertainment'
    when normalized similar to '%(hospital|urgent care|medical center|health center|clinic|doctor|dentist|pharmacy|drugstore|wellness studio|spa|massage|sauna|bathhouse|therapy|chiropractor|acupuncture|physical therapy|recovery studio)%' then 'health_wellness'
    when normalized similar to '%(gym|fitness center|training|strength|workout|climbing gym|boxing gym|pilates|reformer|lagree|yoga|barre|spin studio|dance studio|tennis court|basketball court|soccer field|golf course|pool|skate park|ski|surf)%' then 'sports_fitness'
    when normalized similar to '%(shop|store|retail|art supply store|mall|boutique|market|grocery|bookstore|flower shop|hardware|furniture|electronics|vintage|thrift)%' then 'shopping'
    when normalized similar to '%(salon|barber|nail salon|laundry|dry cleaner|tailor|repair|bank|atm|post office|shipping center|car wash|veterinarian|veterinary|animal hospital|animal service|pet clinic|pet hospital|pet groomer)%' then 'services'
    when normalized similar to '%(hotel|motel|resort|lodging|inn|hostel|bed and breakfast|boutique hotel|[345][ ]?star hotel|vacation rental|cabin)%' then 'lodging'
    when normalized similar to '%(transportation|transit|airport|train station|bus station|ferry|subway|station|parking|garage|rental car|gas station|ev charging|bike share|car share|rest stop)%' then 'transportation_transit'
    when normalized similar to '%(school|university|college|campus|preschool|daycare|tutor|academy|class|workshop|library|study spot)%' then 'education'
    when normalized similar to '%(coworking|co working|office|meeting room|conference|event space|production studio|photo studio|warehouse|convention center|business center)%' then 'work_venues'
    when normalized similar to '%(home|apartment|condo|house|neighborhood|block|courtyard|community garden|local spot|meetup spot|lobby)%' then 'home_neighborhood'
    when normalized similar to '%(government|city hall|courthouse|police|fire station|embassy|consulate|dmv|public restroom|recycling center|utility|civic building)%' then 'public_services'
    else 'place'
  end
  from (select app.place_category_normalized(input_value) as normalized) normalized_input;
$$;

create or replace function app.place_default_subcategory(primary_category text)
returns text
language sql
immutable
as $$
  select case app.place_category_normalized(primary_category)
    when 'coffee' then 'Coffee shop'
    when 'coffee shop' then 'Coffee shop'
    when 'cafe' then 'Cafe'
    when 'bakery' then 'Bakery'
    when 'restaurant' then 'Restaurant'
    when 'bar' then 'Bar'
    when 'hike' then 'Hike or trail'
    when 'trail' then 'Trail'
    when 'park' then 'Park'
    when 'gym' then 'Gym'
    when 'fitness studio' then 'Fitness studio'
    when 'pilates studio' then 'Pilates studio'
    when 'spiritual' then 'Spiritual place'
    when 'hospital' then 'Hospital'
    when 'pharmacy' then 'Pharmacy'
    when 'veterinarian' then 'Veterinarian'
    when 'hotel' then 'Hotel'
    when 'shop' then 'Shop'
    when 'transportation' then 'Transit stop'
    else case app.place_primary_category(primary_category)
      when 'food_drink' then 'Restaurant'
      when 'outdoors_nature' then 'Park'
      when 'arts_culture_faith' then 'Museum'
      when 'entertainment' then 'Entertainment venue'
      when 'health_wellness' then 'Wellness studio'
      when 'sports_fitness' then 'Gym'
      when 'shopping' then 'Shop'
      when 'services' then 'Service business'
      when 'lodging' then 'Hotel'
      when 'transportation_transit' then 'Transit stop'
      when 'education' then 'School'
      when 'work_venues' then 'Coworking space'
      when 'home_neighborhood' then 'Neighborhood spot'
      when 'public_services' then 'Public service'
      else null
    end
  end;
$$;

create or replace function app.place_subcategory(input_value text, primary_category text)
returns text
language sql
immutable
as $$
  select case
    when app.place_primary_category(primary_category) = 'place' then null
    when nullif(trim(coalesce(input_value, '')), '') is null then app.place_default_subcategory(primary_category)
    when normalized in (
      'food drink',
      'food and drink',
      'outdoors nature',
      'outdoors and nature',
      'arts culture faith',
      'arts culture and faith',
      'entertainment',
      'health wellness',
      'health and wellness',
      'sports fitness',
      'sports and fitness',
      'shopping',
      'services',
      'lodging',
      'transportation transit',
      'transportation and transit',
      'education',
      'work venues',
      'work and venues',
      'home neighborhood',
      'home and neighborhood',
      'public services',
      'public service'
    ) then app.place_default_subcategory(primary_category)
    when normalized in (
      'coffee',
      'coffee shop',
      'cafe',
      'bakery',
      'restaurant',
      'bar',
      'hike',
      'trail',
      'park',
      'gym',
      'fitness studio',
      'pilates studio',
      'spiritual',
      'hospital',
      'pharmacy',
      'veterinarian',
      'hotel',
      'shop',
      'transportation'
    ) then app.place_default_subcategory(input_value)
    else initcap(trim(regexp_replace(input_value, '\s+', ' ', 'g')))
  end
  from (select app.place_category_normalized(input_value) as normalized) normalized_input;
$$;

alter table public.places
  drop constraint if exists places_primary_category_allowed;

alter table public.user_places
  drop constraint if exists user_places_category_override_allowed;

update public.places
set
  raw_provider_type = coalesce(nullif(raw_provider_type, ''), category, primary_category, 'place'),
  subcategory = coalesce(
    subcategory,
    app.place_subcategory(
      coalesce(nullif(raw_provider_type, ''), category, primary_category, 'place'),
      app.place_primary_category(coalesce(nullif(raw_provider_type, ''), category, primary_category, 'place'))
    )
  ),
  primary_category = app.place_primary_category(coalesce(primary_category, category, raw_provider_type, 'place')),
  category = app.place_primary_category(coalesce(primary_category, category, raw_provider_type, 'place'))
where true;

update public.user_places
set
  subcategory_override = case
    when category_override is null then null
    else coalesce(subcategory_override, app.place_subcategory(category_override, app.place_primary_category(category_override)))
  end,
  category_override = case
    when category_override is null then null
    else app.place_primary_category(category_override)
  end
where category_override is not null;

alter table public.places
  add constraint places_primary_category_allowed
  check (primary_category in (
    'food_drink',
    'outdoors_nature',
    'arts_culture_faith',
    'entertainment',
    'health_wellness',
    'sports_fitness',
    'shopping',
    'services',
    'lodging',
    'transportation_transit',
    'education',
    'work_venues',
    'home_neighborhood',
    'public_services',
    'place'
  ));

alter table public.user_places
  add constraint user_places_category_override_allowed
  check (
    category_override is null
    or category_override in (
      'food_drink',
      'outdoors_nature',
      'arts_culture_faith',
      'entertainment',
      'health_wellness',
      'sports_fitness',
      'shopping',
      'services',
      'lodging',
      'transportation_transit',
      'education',
      'work_venues',
      'home_neighborhood',
      'public_services',
      'place'
    )
  );

commit;
