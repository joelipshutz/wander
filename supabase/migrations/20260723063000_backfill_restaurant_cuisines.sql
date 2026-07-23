begin;

create or replace function app.restaurant_cuisine_guess(
  input_raw_provider_type text,
  input_subcategory text,
  input_category text,
  input_name text,
  input_website_url text default null
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  with evidence(value, priority) as (
    values
      (input_raw_provider_type, 1),
      (input_subcategory, 2),
      (input_category, 3),
      (input_name, 4),
      (input_website_url, 5)
  ),
  normalized_evidence as (
    select
      regexp_replace(app.place_category_normalized(value), '\s+', ' ', 'g') as value,
      priority
    from evidence
    where nullif(trim(coalesce(value, '')), '') is not null
  ),
  cuisines(cuisine) as (
    select unnest(array[
      'American', 'Mexican', 'Thai', 'Vietnamese', 'Chinese', 'Korean', 'Japanese', 'Indian',
      'Italian', 'Mediterranean', 'Greek', 'French', 'Spanish', 'Tex-Mex', 'Asian fusion',
      'Sushi', 'Ramen', 'Dumplings', 'Noodles', 'Dim sum', 'Hot pot', 'Cantonese',
      'Taiwanese', 'Izakaya', 'Yakitori', 'Yakiniku', 'North Indian', 'South Indian',
      'Malaysian', 'Indonesian', 'Filipino', 'Burmese', 'Cambodian', 'Asian', 'Tibetan',
      'Mongolian BBQ', 'Korean BBQ', 'Japanese BBQ', 'Japanese curry', 'Tonkatsu',
      'Pakistani', 'Sri Lankan', 'Bangladeshi', 'Afghan', 'Middle Eastern', 'Lebanese',
      'Persian', 'Turkish', 'Israeli', 'Moroccan', 'Ethiopian', 'African', 'Falafel', 'Gyro',
      'Kebab', 'Shawarma', 'Halal', 'Tapas', 'Portuguese', 'Basque', 'German', 'Austrian',
      'Bavarian', 'Swiss', 'Dutch', 'Belgian', 'British', 'Irish', 'Scandinavian', 'Polish',
      'Ukrainian', 'Russian', 'Czech', 'Hungarian', 'Romanian', 'Croatian', 'European',
      'Eastern European', 'Danish', 'Pizza', 'Fish & chips', 'Fondue', 'Caribbean', 'Jamaican',
      'Panamanian', 'Cuban', 'Brazilian', 'Argentinian', 'Colombian', 'Chilean', 'Peruvian',
      'South American', 'Latin American', 'Southwestern', 'Cajun', 'Californian', 'Hawaiian',
      'Australian', 'Burgers', 'Diner', 'Hot dogs', 'Barbecue', 'Wings', 'Steakhouse',
      'Bar & grill', 'Taco stand', 'Taco truck', 'Burrito', 'Taco', 'Sandwich', 'Bagel',
      'Deli', 'Salad', 'Bistro', 'Food court', 'Breakfast', 'Brunch', 'Soup', 'Chicken',
      'Seafood', 'Oyster bar', 'Vegetarian', 'Vegan', 'Gluten-free', 'Snack bar', 'Gastropub'
    ]::text[])
  ),
  normalized_cuisines as (
    select
      cuisine,
      regexp_replace(app.place_category_normalized(cuisine), '\s+', ' ', 'g') as value
    from cuisines
  ),
  aliases(alias, cuisine) as (
    values
      ('taqueria', 'Mexican'),
      ('tortilleria', 'Mexican'),
      ('trattoria', 'Italian'),
      ('osteria', 'Italian'),
      ('ristorante', 'Italian'),
      ('cafeugo', 'Italian'),
      ('pizzeria', 'Pizza'),
      ('udon', 'Japanese'),
      ('soba', 'Japanese'),
      ('teppanyaki', 'Japanese'),
      ('banh mi', 'Vietnamese'),
      ('tandoor', 'Indian'),
      ('tandoori', 'Indian'),
      ('masala', 'Indian'),
      ('mezze', 'Middle Eastern'),
      ('mediterranean grill', 'Mediterranean')
  ),
  matches as (
    select
      cuisine,
      e.priority,
      length(c.value) as specificity,
      0 as alias_penalty
    from normalized_evidence e
    cross join normalized_cuisines c
    where e.value = c.value
       or (' ' || e.value || ' ') like ('% ' || c.value || ' %')

    union all

    select
      a.cuisine,
      e.priority,
      length(a.alias) as specificity,
      1 as alias_penalty
    from normalized_evidence e
    cross join aliases a
    where (' ' || e.value || ' ') like ('% ' || a.alias || ' %')
  )
  select cuisine
  from matches
  order by priority, alias_penalty, specificity desc, cuisine
  limit 1
$$;

revoke all on function app.restaurant_cuisine_guess(text, text, text, text, text)
  from public, anon, authenticated;

comment on function app.restaurant_cuisine_guess(text, text, text, text, text) is
  'Internal deterministic restaurant cuisine inference. Evidence priority is provider type, subtype, category, name, then website; it never guesses from locality.';

-- Correct two known generic MapKit restaurant classifications before cuisine
-- backfill so coffee and grocery saves do not receive fabricated cuisines.
update public.places
set
  category = 'coffee_tea_sweets',
  primary_category = 'coffee_tea_sweets',
  subcategory = 'Coffee shop',
  category_source = 'deterministic',
  category_confidence = greatest(coalesce(category_confidence, 0), 0.99),
  updated_at = now()
where app.place_category_normalized(canonical_name) = 'caffenio'
  and coalesce(primary_category, category) = 'restaurants_food'
  and app.place_category_normalized(raw_provider_type) in ('', 'restaurant');

update public.places
set
  category = 'shopping',
  primary_category = 'shopping',
  subcategory = 'Grocery store',
  category_source = 'deterministic',
  category_confidence = greatest(coalesce(category_confidence, 0), 0.99),
  updated_at = now()
where (
    app.place_category_normalized(canonical_name) = 'whole foods market'
    or app.place_category_normalized(canonical_name) like 'whole foods market %'
  )
  and coalesce(primary_category, category) = 'restaurants_food'
  and app.place_category_normalized(raw_provider_type) in ('', 'restaurant', 'foodmarket', 'food market');

with missing_cuisine as (
  select
    up.id as user_place_id,
    case
      when app.place_category_normalized(p.canonical_name) = 'ugo'
        and app.place_category_normalized(p.locality) = 'culver city'
        then 'Italian'
      else app.restaurant_cuisine_guess(
        p.raw_provider_type,
        coalesce(up.subcategory_override, p.subcategory),
        coalesce(up.category_override, p.primary_category, p.category),
        p.canonical_name,
        null
      )
    end as cuisine
  from public.user_places up
  join public.places p on p.id = up.place_id
  where up.deleted_at is null
    and coalesce(up.category_override, p.primary_category, p.category) = 'restaurants_food'
    and not exists (
      select 1
      from public.place_attributes pa
      where pa.user_place_id = up.id
        and pa.question_key = 'restaurant_cuisine'
    )
)
insert into public.place_attributes (
  user_place_id,
  question_definition_id,
  question_key,
  value_type,
  value
)
select
  user_place_id,
  null,
  'restaurant_cuisine',
  'restaurant_cuisine',
  to_jsonb(cuisine)
from missing_cuisine
where cuisine is not null
on conflict (user_place_id, question_key) do nothing;

commit;
