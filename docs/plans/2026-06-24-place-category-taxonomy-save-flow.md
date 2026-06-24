# Place Category Taxonomy And Save Flow

Date: 2026-06-24
Status: Planning, ready for implementation ticket
Owner: Product/Design/Engineering

## Decision

Use a Rec.me-owned taxonomy for place organization. Provider types from Apple MapKit, Google Maps links, Google Places, web metadata, OCR, or future providers are inputs into our taxonomy, not the canonical user-facing model.

The saved place model should separate:

1. Canonical category: a stable Rec.me bucket for filtering, iconography, and category-aware prompts.
2. Subcategory: a more specific provider-derived or user-adjusted place type.
3. Personal labels: user-owned memory/use-case tags that do not alter global taxonomy.

Example mappings:

| Source signal | Canonical category | Subcategory | Notes |
|---|---|---|---|
| MapKit `.restaurant` | Food & Drink | Restaurant | Current iOS default path. |
| Google `thai_restaurant` | Food & Drink | Thai | Future Google Places path. |
| Google `coffee_shop` or MapKit `.cafe` | Coffee & Sweets | Coffee Shop | Coffee deserves first-class scanability. |
| Google `tourist_attraction` plus name "Eaton Canyon Falls" | Outdoors & Nature | Waterfall | Generic attraction should be refined by other signals. |
| MapKit `.fitnessCenter` | Wellness & Fitness | Gym | User can adjust to Fitness Studio, Pilates, Yoga, etc. |
| Google `4-star hotel` | Stays | Hotel | Star rating is metadata, not a category. |

## Canonical Categories

Use this order in save and filter surfaces:

1. Food & Drink
2. Coffee & Sweets
3. Bars & Nightlife
4. Outdoors & Nature
5. Things To Do
6. Shopping
7. Wellness & Fitness
8. Stays
9. Services & Errands
10. Transportation & Transit
11. Work & Learning
12. Civic & Worship
13. Home & Areas
14. Other

Rationale:

- Put the most common save intents first: food, coffee, bars, outdoors, activities.
- Keep `Transportation & Transit` broad enough for both movement infrastructure and transit hubs.
- Keep `Home & Areas` available for neighborhoods, addresses, and regions, but avoid over-promoting it when the saved object is a venue.
- Keep `Other` as a fallback, not a user-visible default when we have better evidence.

## Exhaustive UX Taxonomy

This list is intentionally broader than the v0.1 UI needs. Implementation can start with the categories/subcategories that map cleanly from MapKit and expand as provider coverage improves.

### Food & Drink

Restaurant, fast food, fine dining, casual restaurant, family restaurant, diner, bistro, buffet, food court, takeout, delivery, breakfast, brunch, sandwich shop, deli, salad, soup, pizza, burgers, hot dogs, barbecue, chicken, wings, seafood, oyster bar, fish and chips, steakhouse, vegetarian, vegan, halal, ramen, noodles, dumplings, dim sum, hot pot, fondue.

Cuisine subcategories: American, Mexican, Thai, Vietnamese, Chinese, Cantonese, Taiwanese, Korean, Japanese, sushi, izakaya, yakitori, yakiniku, Indian, North Indian, South Indian, Pakistani, Sri Lankan, Bangladeshi, Afghan, Middle Eastern, Lebanese, Persian, Turkish, Israeli, Moroccan, Mediterranean, Greek, Italian, French, Spanish, tapas, Portuguese, Basque, German, Austrian, Bavarian, Swiss, Dutch, Belgian, British, Irish, Scandinavian, Polish, Ukrainian, Russian, Czech, Hungarian, Romanian, Croatian, Ethiopian, African, Caribbean, Cuban, Brazilian, Argentinian, Colombian, Chilean, Peruvian, South American, Latin American, Tex-Mex, Southwestern, Cajun, Californian, Hawaiian, Australian, Malaysian, Indonesian, Filipino, Burmese, Cambodian, Asian, Asian fusion.

### Coffee & Sweets

Coffee shop, cafe, coffee stand, roastery, tea house, tea store, juice shop, smoothie shop, acai, bakery, bagel shop, donut shop, cake shop, pastry shop, dessert shop, dessert restaurant, ice cream, frozen yogurt, candy store, chocolate shop, chocolate factory, confectionery, cat cafe, dog cafe.

### Bars & Nightlife

Bar, cocktail bar, pub, Irish pub, sports bar, wine bar, lounge, hookah bar, beer garden, brewery, brewpub, winery, vineyard, nightclub, karaoke, live music, comedy club, casino.

### Outdoors & Nature

Park, city park, state park, national park, hiking area, trail, hike, beach, lake, river, island, woods, forest, mountain peak, scenic spot, viewpoint, overlook, waterfall, hot spring, cave, nature preserve, wildlife refuge, wildlife park, botanical garden, garden, picnic area, dog park, playground, campground, RV park, cabin, cottage, marina, fishing pier, fishing pond, fishing charter, ski resort, cycling park, skate park, off-roading area, adventure sports.

### Things To Do

Tourist attraction, landmark, historical place, historical landmark, monument, sculpture, fountain, castle, plaza, town square, visitor center, museum, art museum, history museum, art gallery, art studio, cultural landmark, cultural center, theater, performing arts theater, concert hall, opera house, philharmonic hall, amphitheater, auditorium, movie theater, planetarium, observation deck, aquarium, zoo, amusement park, water park, ferris wheel, roller coaster, arcade, bowling, mini golf, go-karting, paintball, indoor playground, event venue, convention center, banquet hall, wedding venue, community center, internet cafe.

### Shopping

Store, market, shopping mall, department store, general store, convenience store, discount store, warehouse store, wholesaler, grocery store, supermarket, hypermarket, food store, farmers market, flea market, Asian grocery, butcher, health food store, liquor store, book store, art supply store, craft store, gift shop, toy store, clothing store, women's clothing, shoe store, jewelry store, cosmetics store, beauty supply, sporting goods, sportswear, bicycle store, electronics, cell phone store, home goods, home improvement, hardware, building materials, furniture, garden center, pet store, auto parts, thrift store.

### Wellness & Fitness

Gym, fitness center, yoga studio, wellness studio, wellness center, sports club, sports complex, sports coaching, sports school, athletic field, swimming pool, tennis court, golf course, indoor golf, ice skating rink, spa, massage, massage spa, sauna, skin care clinic, tanning studio, hair salon, barber, nail salon, makeup artist, body art, tattoo, piercing, chiropractor, dentist, dental clinic, doctor, medical clinic, medical center, hospital, medical lab, pharmacy, drugstore, physiotherapist, foot care, veterinary care, mental health, therapy.

### Stays

Hotel, resort hotel, motel, hostel, inn, bed and breakfast, guest house, private guest room, extended stay, cottage, cabin, campground, RV park, farmstay, Japanese inn, budget Japanese inn, mobile home park.

Hotel class values like 3-star hotel or 4-star hotel should be stored as provider metadata when available. They should not create separate subcategories.

### Services & Errands

Bank, ATM, accounting, insurance, real estate, lawyer, consultant, marketing consultant, employment agency, nonprofit, association, florist, catering, food delivery, child care, summer camp, laundry, tailor, courier, shipping, storage, moving, electrician, plumber, locksmith, painter, roofing contractor, general contractor, pet care, pet boarding, funeral home, cemetery, astrologer, psychic, tour agency, travel agency, tourist information, chauffeur, aircraft rental, telecommunications.

### Transportation & Transit

Airport, international airport, airstrip, heliport, train station, subway station, light rail station, tram stop, bus stop, bus station, ferry terminal, ferry service, transit station, transit stop, transit depot, taxi stand, taxi service, bike share, parking, parking lot, parking garage, park and ride, gas station, EV charging, e-bike charging, rest stop, truck stop, toll station, bridge, car dealer, car rental, car repair, car wash, tire shop, truck dealer, transportation service.

### Work & Learning

Coworking space, business center, corporate office, manufacturer, supplier, farm, ranch, television studio, library, university, school, preschool, primary school, secondary school, academic department, educational institution, research institute.

### Civic & Worship

City hall, government office, local government office, courthouse, embassy, post office, police, neighborhood police station, fire station, church, mosque, synagogue, Hindu temple, Buddhist temple, Shinto shrine, place of worship.

### Home & Areas

Apartment building, apartment complex, condominium complex, housing complex, neighborhood, locality, city, postal area, region, country, route, street, address, intersection, landmark, plus code.

### Other

Public bathroom, public bath, restroom, stable, generic establishment, point of interest, unknown.

## Defaulting Rules

1. Preserve raw provider data separately from Rec.me taxonomy values.
2. Prefer the most specific provider type when it maps cleanly to a subcategory.
3. Suppress generic provider types like `point_of_interest`, `establishment`, `food`, `store`, and usually `tourist_attraction` when better signals exist.
4. Use the current MapKit category as a default signal in v0.1, but map it into Rec.me canonical categories and subcategories.
5. Treat Google Maps and Apple Maps links as source hints unless/until a richer places provider returns authoritative place types.
6. When confidence is low, prefill the best guess and make correction one tap away.
7. Allow a user-created personal subcategory only after the standard list and search fail to match their intent.
8. Keep personal labels separate from category. Labels capture why the user cares, not what the place objectively is.

## Save This Place Presentation

The save flow should usually show the suggested category without making the user classify the place manually.

```text
+-------------------------------------+
| Save this place                  X  |
+-------------------------------------+
| Courage Bagels                       |
| 777 N Virgil Ave, Los Angeles        |
|                                     |
| +-------------+ +---------------+   |
| | Want to go  | | I've been     |   |
| +-------------+ +---------------+   |
|                                     |
| Place type                          |
| +---------------------------------+ |
| | Coffee & Sweets                 | |
| | Bagel Shop                  >   | |
| +---------------------------------+ |
|                                     |
| Good for                            |
| +------------+ +--------------+     |
| | breakfast  | | bring friends |     |
| +------------+ +--------------+     |
| +------------+ +--------------+     |
| | quick bite | | + add label   |     |
| +------------+ +--------------+     |
|                                     |
| Note                                |
| +---------------------------------+ |
| | Worth the line if we go early...| |
| +---------------------------------+ |
|                                     |
| Visibility                          |
| Everyone   Friends   Self           |
|                                     |
| +---------------------------------+ |
| | Save place                      | |
| +---------------------------------+ |
+-------------------------------------+
```

Content behavior:

- `Place type` shows canonical category on the first line and subcategory on the second line.
- Suggested labels should be derived from category, status, and existing prompt templates.
- Users can save without touching type or labels.
- If category is `Other` or confidence is low, show a softer prompt: "What kind of place is this?"

## Place Type Picker

Use search first, suggestions second, then top-level categories. Do not show the full taxonomy as one long list.

```text
+-------------------------------------+
| Place type                       X  |
+-------------------------------------+
| Search categories or types           |
| +---------------------------------+ |
| | coffee, thai, hike, hotel...    | |
| +---------------------------------+ |
|                                     |
| Suggested                           |
| * Coffee & Sweets / Bagel Shop      |
|   Food & Drink / Bakery             |
|   Food & Drink / Breakfast          |
|                                     |
| Categories                          |
| Food & Drink                    >   |
| Coffee & Sweets                 >   |
| Bars & Nightlife                >   |
| Outdoors & Nature               >   |
| Things To Do                    >   |
| Shopping                        >   |
| Wellness & Fitness              >   |
| Stays                           >   |
| Services & Errands              >   |
| Transportation & Transit        >   |
| Work & Learning                 >   |
| Civic & Worship                 >   |
| Home & Areas                    >   |
| Other                           >   |
+-------------------------------------+
```

Category drill-in:

```text
+-------------------------------------+
| Coffee & Sweets                  <  |
+-------------------------------------+
| * Bagel Shop                         |
| Coffee Shop                          |
| Cafe                                 |
| Bakery                               |
| Donut Shop                           |
| Dessert Shop                         |
| Ice Cream                            |
| Tea House                            |
| Juice Shop                           |
| Chocolate Shop                       |
| Candy Store                          |
| + Create personal subcategory        |
+-------------------------------------+
```

## Implementation Notes

- Add explicit fields for `canonicalCategory`, `subcategory`, and `personalLabels` when the persistence model is ready to evolve. Until then, `LocalPlace.category` can continue holding the old narrow value, but new implementation should migrate toward the three-layer model.
- Keep `sourceProvider` and `sourceProviderPlaceID` unchanged.
- Add raw provider type fields when integrating Google Places or richer Apple metadata, for example `providerPrimaryType`, `providerTypes`, and `providerTypeDisplayName`.
- Category-aware add questions should key off canonical category first, then subcategory when useful.
- Map filters should start with canonical categories. Place cards and details can show subcategory for specificity.
- Personal labels should be per-user/per-save, not global place metadata.

## Open Questions

- Should `Coffee & Sweets` remain separate from `Food & Drink` in map filters, or should it visually group under Food while staying first-class in save?
- Should user-created personal subcategories be private to the user, or can repeated creations graduate into the shared taxonomy after review?
- How much provider raw data should be visible in internal diagnostics for debugging mismatches?
