begin;

-- Legacy SQL normalization removes the MapKit prefix but does not split the
-- compact `FoodMarket` suffix. Correct any surviving restaurant rows from that
-- provider type to the canonical grocery-store category.
update public.places
set
  category = 'shopping',
  primary_category = 'shopping',
  subcategory = 'Grocery store',
  category_source = 'deterministic',
  category_confidence = greatest(coalesce(category_confidence, 0), 0.99),
  updated_at = now()
where app.place_category_normalized(raw_provider_type) in ('foodmarket', 'food market')
  and coalesce(primary_category, category) = 'restaurants_food';

commit;
