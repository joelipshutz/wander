begin;

create or replace function app.place_category_normalized(input_value text)
returns text
language sql
immutable
as $$
  select trim(
    regexp_replace(
      regexp_replace(
        regexp_replace(lower(coalesce(input_value, '')), 'mkpoicategory', ' ', 'g'),
        '[_&/-]+',
        ' ',
        'g'
      ),
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
    when normalized in ('restaurants food', 'restaurants and food', 'food drink', 'food and drink', 'restaurant') then 'restaurants_food'
    when normalized in ('coffee tea sweets', 'coffee tea and sweets', 'coffee', 'coffee shop', 'cafe', 'bakery') then 'coffee_tea_sweets'
    when normalized in ('bars nightlife', 'bars and nightlife', 'bar', 'nightlife') then 'bars_nightlife'
    when normalized in ('outdoors nature', 'outdoors and nature', 'outdoors') then 'outdoors_nature'
    when normalized in ('things to do', 'arts culture faith', 'arts culture and faith', 'entertainment') then 'things_to_do'
    when normalized = 'shopping' then 'shopping'
    when normalized in ('wellness fitness', 'wellness and fitness', 'health wellness', 'health and wellness', 'sports fitness', 'sports and fitness') then 'wellness_fitness'
    when normalized in ('stays', 'stay', 'lodging') then 'stays'
    when normalized in ('services errands', 'services and errands', 'services') then 'services_errands'
    when normalized in ('travel transit', 'travel and transit', 'transportation transit', 'transportation and transit', 'transportation', 'transit') then 'travel_transit'
    when normalized in ('work education', 'work and education', 'education', 'work venues', 'work and venues') then 'work_education'
    when normalized in ('civic faith', 'civic and faith', 'public services', 'public service') then 'civic_faith'
    when normalized in ('areas addresses', 'areas and addresses', 'home neighborhood', 'home and neighborhood') then 'areas_addresses'
    when normalized in ('facilities other', 'facilities and other', 'other') then 'facilities_other'
    when normalized similar to '%(coffee|cafe|espresso|roaster|roastery|tea house|tea store|bakery|dessert|ice cream|juice|smoothie|acai|candy|chocolate|cat cafe|dog cafe)%' then 'coffee_tea_sweets'
    when normalized similar to '%(nightlife|cocktail|pub|sports bar|wine bar|bar and grill|dance hall|club|disco|lounge|hookah|beer garden|jazz club|brewery|brewpub|winery|vineyard|nightclub|karaoke|live music|comedy club|casino)%' then 'bars_nightlife'
    when normalized similar to '%(restaurant|fast food|fine dining|diner|bistro|buffet|food court|takeout|cafeteria|breakfast|brunch|sandwich|deli|salad|soup|pizza|burger|hot dog|barbecue|chicken|wings|seafood|oyster|fish chips|steakhouse|vegetarian|vegan|halal|ramen|noodle|dumpling|dim sum|hot pot|fondue|burrito|taco|falafel|gyro|kebab|shawarma|snack bar|gastropub|american|mexican|thai|vietnamese|chinese|korean|japanese|sushi|indian|italian|mediterranean|greek|french|spanish|cuban|brazilian|peruvian|asian fusion|japanese curry|tonkatsu)%' then 'restaurants_food'
    when normalized similar to '%(hike|hiking|trail|waterfall|hot spring|canyon|mountain|park|playground|garden|beach|lake|river|island|forest|nature preserve|wildlife|campground|rv park|marina|ski resort|skate park|off roading)%' then 'outdoors_nature'
    when normalized similar to '%(tourist attraction|attraction|landmark|museum|gallery|theater|theatre|historic|monument|sculpture|fountain|castle|plaza|visitor center|cultural center|movie|cinema|concert|opera|amphitheater|planetarium|observation deck|zoo|aquarium|amusement|water park|arcade|bowling|mini golf|billiards|darts|axe throwing|go kart|paintball|event venue|convention center|banquet hall|wedding venue|community center|internet cafe|barbecue area)%' then 'things_to_do'
    when normalized similar to '%(shop|store|retail|mall|market|grocery|supermarket|book store|bookstore|art supply|craft store|gift shop|clothing|shoe store|jewelry|cosmetics|beauty supply|sporting goods|bicycle store|electronics|cell phone|home goods|home improvement|hardware|building materials|furniture|garden center|pet store|auto parts|thrift)%' then 'shopping'
    when normalized similar to '%(health|wellness|fitness|gym|yoga|sports club|sports complex|sports coaching|athletic field|swimming pool|tennis court|golf course|ice skating|volleyball|soccer|basketball|pickleball|spa|massage|sauna|chiropractor|dentist|doctor|medical|hospital|pharmacy|drugstore|physiotherapist|foot care|veterinary|mental health|therapy|retreat)%' then 'wellness_fitness'
    when normalized similar to '%(hotel|motel|resort|inn|hostel|bed and breakfast|guest house|private guest room|airbnb|vrbo|extended stay|farm stay|japanese inn|mobile home park|[2345][ ]?star hotel)%' then 'stays'
    when normalized similar to '%(bank|atm|accounting|insurance|real estate|lawyer|consultant|employment agency|nonprofit|association|florist|catering|food delivery|child care|summer camp|laundry|tailor|courier|shipping|storage|moving|electrician|plumber|locksmith|painter|roofing|general contractor|pet care|pet boarding|funeral home|cemetery|astrologer|psychic|tour agency|travel agency|tourist information|chauffeur|aircraft rental|telecommunications|skin care|tanning|hair salon|barber|nail salon|makeup artist|body art|tattoo|piercing)%' then 'services_errands'
    when normalized similar to '%(airport|airstrip|heliport|train station|subway|light rail|tram|bus stop|bus station|ferry|transit station|transit stop|taxi|bike share|parking|garage|park ride|gas station|ev charging|e bike charging|rest stop|truck stop|toll station|bridge|car dealer|car rental|car repair|car wash|tire shop|truck dealer|transportation service|dump station|rv water refill)%' then 'travel_transit'
    when normalized similar to '%(coworking|co working|business center|corporate office|manufacturer|supplier|farm|ranch|television studio|library|university|school|preschool|primary school|secondary school|academic department|educational institution|research institute)%' then 'work_education'
    when normalized similar to '%(city hall|government|courthouse|embassy|post office|police|fire station|faith|worship|spiritual|church|mosque|synagogue|hindu temple|buddhist temple|shinto shrine|place of worship|temple|shrine)%' then 'civic_faith'
    when normalized similar to '%(apartment|condominium|housing complex|neighborhood|locality|city|postal area|town|region|country|route|street|address|intersection|plus code)%' then 'areas_addresses'
    when normalized similar to '%(facility|facilities|public bathroom|public bath|public restroom|restroom|stable|generic establishment|establishment|point of interest|unknown)%' then 'facilities_other'
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
    when 'fast food restaurant' then 'Fast food'
    when 'bar' then 'Bar'
    when 'nightlife' then 'Bar'
    when 'hike' then 'Hike'
    when 'trail' then 'Trail'
    when 'park' then 'Park'
    when 'gym' then 'Gym'
    when 'fitness center' then 'Fitness center'
    when 'wellness studio' then 'Wellness studio'
    when 'spiritual' then 'Place of worship'
    when 'hospital' then 'Hospital'
    when 'pharmacy' then 'Pharmacy'
    when 'veterinarian' then 'Veterinary care'
    when 'hotel' then 'Hotel'
    when '2 star hotel' then 'Hotel'
    when '3 star hotel' then 'Hotel'
    when '4 star hotel' then 'Hotel'
    when '5 star hotel' then 'Hotel'
    when 'shop' then 'Store'
    when 'transportation' then 'Transit stop'
    else case app.place_primary_category(primary_category)
      when 'restaurants_food' then 'Restaurant'
      when 'coffee_tea_sweets' then 'Coffee shop'
      when 'bars_nightlife' then 'Bar'
      when 'outdoors_nature' then 'Park'
      when 'things_to_do' then 'Tourist attraction'
      when 'shopping' then 'Store'
      when 'wellness_fitness' then 'Gym'
      when 'stays' then 'Hotel'
      when 'services_errands' then 'Consultant'
      when 'travel_transit' then 'Transit stop'
      when 'work_education' then 'Co-working space'
      when 'civic_faith' then 'Government office'
      when 'areas_addresses' then 'Address'
      when 'facilities_other' then 'Point of interest'
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
      'restaurants food',
      'restaurants and food',
      'food drink',
      'food and drink',
      'coffee tea sweets',
      'coffee tea and sweets',
      'bars nightlife',
      'bars and nightlife',
      'outdoors nature',
      'outdoors and nature',
      'things to do',
      'arts culture faith',
      'arts culture and faith',
      'entertainment',
      'wellness fitness',
      'wellness and fitness',
      'health wellness',
      'health and wellness',
      'sports fitness',
      'sports and fitness',
      'shopping',
      'stays',
      'lodging',
      'services errands',
      'services and errands',
      'services',
      'travel transit',
      'travel and transit',
      'transportation transit',
      'transportation and transit',
      'work education',
      'work and education',
      'education',
      'work venues',
      'work and venues',
      'civic faith',
      'civic and faith',
      'public services',
      'public service',
      'areas addresses',
      'areas and addresses',
      'home neighborhood',
      'home and neighborhood',
      'facilities other',
      'facilities and other',
      'place'
    ) then app.place_default_subcategory(primary_category)
    when normalized in ('2 star hotel', '3 star hotel', '4 star hotel', '5 star hotel') then 'Hotel'
    when app.place_primary_category(primary_category) = 'restaurants_food'
      and normalized in ('fast food restaurant', 'fast food') then 'Fast food'
    when app.place_primary_category(primary_category) = 'restaurants_food'
      and normalized in ('fine dining restaurant', 'fine dining') then 'Fine dining'
    when app.place_primary_category(primary_category) = 'restaurants_food'
      and normalized in ('thai restaurant', 'sushi restaurant', 'mexican restaurant', 'italian restaurant', 'chinese restaurant', 'japanese restaurant', 'korean restaurant', 'indian restaurant') then 'Restaurant'
    when app.place_primary_category(primary_category) = 'restaurants_food'
      and normalized like '% restaurant' then 'Restaurant'
    when normalized in (
      'coffee',
      'coffee shop',
      'cafe',
      'bakery',
      'restaurant',
      'bar',
      'nightlife',
      'hike',
      'trail',
      'park',
      'gym',
      'fitness center',
      'wellness studio',
      'spiritual',
      'hospital',
      'pharmacy',
      'veterinarian',
      'hotel',
      'shop',
      'transportation',
      'public restroom',
      'unknown'
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
  subcategory = app.place_subcategory(
    coalesce(nullif(subcategory, ''), nullif(raw_provider_type, ''), category, primary_category, 'place'),
    app.place_primary_category(coalesce(nullif(subcategory, ''), nullif(raw_provider_type, ''), category, primary_category, 'place'))
  ),
  primary_category = app.place_primary_category(coalesce(nullif(subcategory, ''), nullif(raw_provider_type, ''), category, primary_category, 'place')),
  category = app.place_primary_category(coalesce(nullif(subcategory, ''), nullif(raw_provider_type, ''), category, primary_category, 'place'))
where true;

update public.user_places
set
  subcategory_override = case
    when category_override is null then null
    else coalesce(
      subcategory_override,
      app.place_subcategory(category_override, app.place_primary_category(category_override))
    )
  end,
  category_override = case
    when category_override is null then null
    else app.place_primary_category(coalesce(nullif(subcategory_override, ''), category_override))
  end
where category_override is not null;

alter table public.places
  add constraint places_primary_category_allowed
  check (primary_category in (
    'restaurants_food',
    'coffee_tea_sweets',
    'bars_nightlife',
    'outdoors_nature',
    'things_to_do',
    'shopping',
    'wellness_fitness',
    'stays',
    'services_errands',
    'travel_transit',
    'work_education',
    'civic_faith',
    'areas_addresses',
    'facilities_other',
    'place'
  ));

alter table public.user_places
  add constraint user_places_category_override_allowed
  check (
    category_override is null
    or category_override in (
      'restaurants_food',
      'coffee_tea_sweets',
      'bars_nightlife',
      'outdoors_nature',
      'things_to_do',
      'shopping',
      'wellness_fitness',
      'stays',
      'services_errands',
      'travel_transit',
      'work_education',
      'civic_faith',
      'areas_addresses',
      'facilities_other',
      'place'
    )
  );

commit;
