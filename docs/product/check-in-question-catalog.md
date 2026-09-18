# Check-in question inventory

This inventory covers every selectable place subtype. Each row is the starting set for an optional Check-in: exactly three questions, with no answers selected. People can customize their set. Leaving a question unanswered means unknown; it does not mean “no.”

The catalog has **590 selectable subcategories across 14 categories**, **238 questions available for new selections**, and **51 historical definitions retained for saved answers**. There are 289 definitions in total; **149 available questions use Yes/No**. Meaningful exceptions retain a few choices. Dietary options is multi-select: Vegan, Vegetarian, Gluten free. Nothing is selected by default.

All 277 original definitions were reviewed for practical, concise wording. Ingredient, ordering and browsing-space trivia has been retired from new selections. Existing keys and all of their stored option values remain compatible. The 12 newer questions describe new facts; an old Pilates apparatus answer is never converted into an answer about whether someone attended a reformer class.

The binary prompt layer simplifies new inputs while retaining every original option as an accepted historical value. No old answer is converted into Yes or No. Questions distinguish a visit from a lasting rule. “Booked ahead” records what the person did. “Reservation required?” asks about an observed requirement. A class being busy describes that visit; it does not establish a fixed class size. Posted dog rules can record leash requirements or no pet dogs. “Dogs allowed?” is binary for venues, including every coffee, tea and sweets subtype. A Yes does not imply indoor access. Historical inside/outside answers retain their qualified meaning. No sign found establishes no permission.

This table follows the Swift catalog definitions and selectable taxonomy. Change the source first, then regenerate. Source files: [taxonomy](../../Wander/Services/WanderPlaceCategory.swift), [catalog contract](../../Wander/Features/Add/PlaceCheckInQuestionCatalog.swift), [binary prompts](../../Wander/Features/Add/PlaceCheckInBinaryPrompts.swift), [core questions](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+CoreQuestions.swift), [core profiles](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+CoreProfiles.swift), [everyday questions](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+EverydayQuestions.swift), [everyday profiles](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+EverydayProfiles.swift).

## Core examples

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Coffee shop | Laptops welcome? | Power outlets? | Dogs allowed? |
| Cafe | Laptops welcome? | Power outlets? | Dogs allowed? |
| Thai | Easy to find parking? | Outdoor seating? | Dietary options? |
| Pilates studio | Was it a reformer class? | Was the class busy? | Easy to book? |
| CrossFit gym | Were workout adaptations explained? | Coached WOD or open gym? | Day pass available? |
| Functional fitness studio | Coached circuits or individual training? | Did coaches give technique feedback? | Was it busy? |
| Volleyball court | Sand, grass or hard court? | Volleyball net ready to use? | Open play or book a court? |
| Beach tennis | Open play or book a court? | Equipment available? | Court lights on for evening play? |
| Beach volleyball | Volleyball net ready to use? | Open play or book a court? | Shaded areas? |
| Park | Posted dog rules? | Shaded areas? | Bathroom available? |
| Beach | Posted dog rules? | Shaded areas? | Rinse-off showers? |
| Surf | Surfboard rental available? | Was it busy? | Posted dog rules? |
| Surf break | Crowded in the water? | Rinse-off showers? | Posted dog rules? |
| Stadium | Was your seat covered? | Reserved seats or first come? | Bag checks on entry? |
| Arena | Was the sound good? | Reserved seats or first come? | Bag checks on entry? |

Dogs, laptops and outlets lead the coffee-shop set. Pilates asks about reformer class, busyness and booking; CrossFit asks about workout adaptations, coached WOD/open gym and drop-in access. Parks receive dog rules, shade and bathrooms. Rinse facilities remain specific to beaches and surf breaks.

New types have one picker home: Beach tennis, Beach volleyball, Padel court, Climbing gym and Surf school in Wellness & Fitness; Stadium and Arena in Things To Do; Surf, Surf break and Kayak/canoe rental in Outdoors & Nature; Surf shop in Shopping. Exact provider type tokens preserve these distinctions. MapKit’s broad Surfing type maps to Surf, not to an inferred surf break or school. The existing Volleyball type remains Volleyball court.

## Fallback contract

Every selectable subtype must have an explicit catalog row. Exhaustive tests enumerate the actual picker and reject missing rows, duplicate scopes, retired defaults or references that do not resolve. A user-written or unrecognized subtype keeps its own name and customization scope and receives a category fallback. Fallback does not count as curation for a new selectable subtype.

For restaurants, the selected Food type can correct a culinary label such as Ramen to Thai. Explicit venue formats such as Taco truck and Food court retain their practical question set when paired with a cuisine; a newly selected venue format takes precedence. Legacy formats such as Buffet, Food truck and Fine dining have explicit format profiles while retaining their own preference scope. This resolver changes question context only, not stored category data.

When no subtype is supplied, the category’s normal default subtype is used. Restaurant is an additional category default rather than a picker entry:

| Default | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Restaurant | Easy to find parking? | Outdoor seating? | Dietary options? |

An unrecognized primary category uses Place. These fallback sets also have no selected answers.

| Category fallback | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Restaurants & Food | Easy to find parking? | Outdoor seating? | Dietary options? |
| Coffee, Tea, & Sweets | Laptops welcome? | Power outlets? | Dogs allowed? |
| Bars & Nightlife | Easy to have a conversation? | Good alcohol-free options? | Outdoor seating? |
| Outdoors & Nature | Posted dog rules? | Shaded areas? | Bathroom available? |
| Things To Do | Entry fee? | How much time would you allow? | Step-free entrance? |
| Shopping | Dogs allowed? | Help choosing available? | Card, cash or app? |
| Wellness & Fitness | Step-free entrance? | Long wait? | Bathroom available? |
| Stays | Quiet room when you rested? | Luggage storage? | Room temperature controls? |
| Services & Errands | Walk-in or appointment? | Long wait? | Clear prices before paying? |
| Travel & Transit | Easy to find your way? | Somewhere to sit? | Bathroom available? |
| Work & Education | Did the Wi-Fi work well? | Power outlets? | Easy to have a conversation? |
| Civic & Faith | How did visitor entry work? | Step-free entrance? | Clear visitor rules? |
| Areas & Addresses | How did you get around? | Seating without a purchase? | Easy to find your way? |
| Facilities & Other | Step-free entrance? | Somewhere to sit? | Bathroom available? |
| Place | Step-free entrance? | Somewhere to sit? | Bathroom available? |

## Shared sets and rationale

Split by the experience, not a cuisine name. Italian, Chinese, Thai, ramen and sushi share parking, outdoor seating and dietary options. Vegan restaurants replace the redundant vegan question with gluten-free options; vegetarian restaurants ask about vegan meals. Gluten-free venues ask about clear dietary information. Takeaway formats prioritize waits; food courts prioritize seating and bathrooms; fine dining prioritizes reservations; tabletop cooking prioritizes smoke and reservations.

Coffee shop, cafe and coffee lounge share laptop, outlet and dog questions. All 26 coffee, tea and sweets types include dogs. Park and garden visits can share dog rules, shade and bathrooms; beaches retain rinse-off showers and trails retain terrain. Gym and fitness center share equipment needs, while Pilates, CrossFit, coached circuits and beach courts remain distinct. Hotels, motels and inns share room comfort and luggage needs; hostels retain privacy, lockers and cooking. Rail, subway and bus stations share wayfinding, step-free boarding and bathrooms; exposed bus stops retain shelter. Clothing and shoe shops share trying-on space, staff help and dog access.

Question sets can be shared while customization remains account- and subtype-specific. Not useful hides the prompt on future saves and edits without deleting previous answers; Undo reverses it in the current form. Re-add or confirmed Restore revives a prompt. Existing customized lists do not silently change when suggested defaults are revised. Inline eye buttons change Stealth without navigation; private dietary values preserve the whole selection.

## Complete selectable inventory

### Restaurants & Food (174)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Thai | Easy to find parking? | Outdoor seating? | Dietary options? |
| Vietnamese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Chinese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Korean | Easy to find parking? | Outdoor seating? | Dietary options? |
| Japanese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Indian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Asian fusion | Easy to find parking? | Outdoor seating? | Dietary options? |
| Sushi | Easy to find parking? | Outdoor seating? | Dietary options? |
| Ramen | Easy to find parking? | Outdoor seating? | Dietary options? |
| Dumplings | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bao buns | Easy to find parking? | Outdoor seating? | Dietary options? |
| Noodles | Easy to find parking? | Outdoor seating? | Dietary options? |
| Dim sum | Easy to find parking? | Outdoor seating? | Dietary options? |
| Hot pot | Smoky inside? | Reservation required? | Dietary options? |
| Cantonese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Taiwanese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Izakaya | Easy to find parking? | Outdoor seating? | Dietary options? |
| Yakitori | Easy to find parking? | Outdoor seating? | Dietary options? |
| Yakiniku | Smoky inside? | Reservation required? | Dietary options? |
| North Indian | Easy to find parking? | Outdoor seating? | Dietary options? |
| South Indian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Pakistani | Easy to find parking? | Outdoor seating? | Dietary options? |
| Sri Lankan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bangladeshi | Easy to find parking? | Outdoor seating? | Dietary options? |
| Nepalese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Malaysian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Singaporean | Easy to find parking? | Outdoor seating? | Dietary options? |
| Indonesian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Filipino | Easy to find parking? | Outdoor seating? | Dietary options? |
| Burmese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Cambodian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Laotian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Asian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Tibetan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Mongolian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Georgian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Armenian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Uzbek | Easy to find parking? | Outdoor seating? | Dietary options? |
| Mongolian BBQ | Easy to find parking? | Outdoor seating? | Dietary options? |
| Korean BBQ | Smoky inside? | Reservation required? | Dietary options? |
| Japanese BBQ | Smoky inside? | Reservation required? | Dietary options? |
| Japanese curry | Easy to find parking? | Outdoor seating? | Dietary options? |
| Tonkatsu | Easy to find parking? | Outdoor seating? | Dietary options? |
| Afghan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Middle Eastern | Easy to find parking? | Outdoor seating? | Dietary options? |
| Lebanese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Persian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Turkish | Easy to find parking? | Outdoor seating? | Dietary options? |
| Israeli | Easy to find parking? | Outdoor seating? | Dietary options? |
| Palestinian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Syrian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Iraqi | Easy to find parking? | Outdoor seating? | Dietary options? |
| Jordanian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Yemeni | Easy to find parking? | Outdoor seating? | Dietary options? |
| Egyptian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Moroccan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Tunisian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Algerian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Ethiopian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Eritrean | Easy to find parking? | Outdoor seating? | Dietary options? |
| Somali | Easy to find parking? | Outdoor seating? | Dietary options? |
| Kenyan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Nigerian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Ghanaian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Senegalese | Easy to find parking? | Outdoor seating? | Dietary options? |
| South African | Easy to find parking? | Outdoor seating? | Dietary options? |
| African | Easy to find parking? | Outdoor seating? | Dietary options? |
| Falafel | Easy to find parking? | Outdoor seating? | Dietary options? |
| Gyro | Easy to find parking? | Outdoor seating? | Dietary options? |
| Kebab | Easy to find parking? | Outdoor seating? | Dietary options? |
| Shawarma | Easy to find parking? | Outdoor seating? | Dietary options? |
| Halal | Easy to find parking? | Outdoor seating? | Dietary options? |
| Italian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Mediterranean | Easy to find parking? | Outdoor seating? | Dietary options? |
| Greek | Easy to find parking? | Outdoor seating? | Dietary options? |
| French | Easy to find parking? | Outdoor seating? | Dietary options? |
| Spanish | Easy to find parking? | Outdoor seating? | Dietary options? |
| Tapas | Easy to find parking? | Outdoor seating? | Dietary options? |
| Portuguese | Easy to find parking? | Outdoor seating? | Dietary options? |
| Basque | Easy to find parking? | Outdoor seating? | Dietary options? |
| German | Easy to find parking? | Outdoor seating? | Dietary options? |
| Austrian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bavarian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Swiss | Easy to find parking? | Outdoor seating? | Dietary options? |
| Dutch | Easy to find parking? | Outdoor seating? | Dietary options? |
| Belgian | Easy to find parking? | Outdoor seating? | Dietary options? |
| British | Easy to find parking? | Outdoor seating? | Dietary options? |
| Irish | Easy to find parking? | Outdoor seating? | Dietary options? |
| Scandinavian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Swedish | Easy to find parking? | Outdoor seating? | Dietary options? |
| Norwegian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Finnish | Easy to find parking? | Outdoor seating? | Dietary options? |
| Danish | Easy to find parking? | Outdoor seating? | Dietary options? |
| Polish | Easy to find parking? | Outdoor seating? | Dietary options? |
| Ukrainian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Russian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Czech | Easy to find parking? | Outdoor seating? | Dietary options? |
| Slovak | Easy to find parking? | Outdoor seating? | Dietary options? |
| Hungarian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Romanian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Croatian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Serbian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bosnian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bulgarian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Albanian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Slovenian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Lithuanian | Easy to find parking? | Outdoor seating? | Dietary options? |
| European | Easy to find parking? | Outdoor seating? | Dietary options? |
| Eastern European | Easy to find parking? | Outdoor seating? | Dietary options? |
| Pizza | Easy to find parking? | Outdoor seating? | Dietary options? |
| Fish & chips | Easy to find parking? | Outdoor seating? | Dietary options? |
| Fondue | Easy to find parking? | Outdoor seating? | Dietary options? |
| American | Easy to find parking? | Outdoor seating? | Dietary options? |
| Canadian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Mexican | Easy to find parking? | Outdoor seating? | Dietary options? |
| Tex-Mex | Easy to find parking? | Outdoor seating? | Dietary options? |
| Caribbean | Easy to find parking? | Outdoor seating? | Dietary options? |
| Jamaican | Easy to find parking? | Outdoor seating? | Dietary options? |
| Puerto Rican | Easy to find parking? | Outdoor seating? | Dietary options? |
| Dominican | Easy to find parking? | Outdoor seating? | Dietary options? |
| Haitian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Panamanian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Cuban | Easy to find parking? | Outdoor seating? | Dietary options? |
| Brazilian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Argentinian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Colombian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Chilean | Easy to find parking? | Outdoor seating? | Dietary options? |
| Peruvian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Venezuelan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Ecuadorian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bolivian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Uruguayan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Salvadoran | Easy to find parking? | Outdoor seating? | Dietary options? |
| Guatemalan | Easy to find parking? | Outdoor seating? | Dietary options? |
| South American | Easy to find parking? | Outdoor seating? | Dietary options? |
| Latin American | Easy to find parking? | Outdoor seating? | Dietary options? |
| Southwestern | Easy to find parking? | Outdoor seating? | Dietary options? |
| Cajun | Easy to find parking? | Outdoor seating? | Dietary options? |
| Californian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Hawaiian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Poke | Easy to find parking? | Outdoor seating? | Dietary options? |
| Australian | Easy to find parking? | Outdoor seating? | Dietary options? |
| New Zealand | Easy to find parking? | Outdoor seating? | Dietary options? |
| Fijian | Easy to find parking? | Outdoor seating? | Dietary options? |
| Samoan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Tongan | Easy to find parking? | Outdoor seating? | Dietary options? |
| Burgers | Easy to find parking? | Outdoor seating? | Dietary options? |
| Diner | Easy to find parking? | Outdoor seating? | Dietary options? |
| Hot dogs | Easy to find parking? | Outdoor seating? | Dietary options? |
| Barbecue | Easy to find parking? | Outdoor seating? | Dietary options? |
| Wings | Easy to find parking? | Outdoor seating? | Dietary options? |
| Steakhouse | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bar & grill | Easy to find parking? | Outdoor seating? | Dietary options? |
| Taco stand | Easy to find parking? | Long wait? | Dietary options? |
| Taco truck | Easy to find parking? | Long wait? | Dietary options? |
| Burrito | Easy to find parking? | Outdoor seating? | Dietary options? |
| Taco | Easy to find parking? | Outdoor seating? | Dietary options? |
| Sandwich | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bagel | Easy to find parking? | Outdoor seating? | Dietary options? |
| Deli | Easy to find parking? | Outdoor seating? | Dietary options? |
| Salad | Easy to find parking? | Outdoor seating? | Dietary options? |
| Bistro | Easy to find parking? | Outdoor seating? | Dietary options? |
| Food court | Somewhere to sit? | Bathroom available? | Dietary options? |
| Breakfast | Easy to find parking? | Outdoor seating? | Dietary options? |
| Brunch | Easy to find parking? | Outdoor seating? | Dietary options? |
| Soup | Easy to find parking? | Outdoor seating? | Dietary options? |
| Chicken | Easy to find parking? | Outdoor seating? | Dietary options? |
| Seafood | Easy to find parking? | Outdoor seating? | Dietary options? |
| Oyster bar | Easy to find parking? | Outdoor seating? | Dietary options? |
| Vegetarian | Easy to find parking? | Outdoor seating? | Vegan meal options? |
| Vegan | Easy to find parking? | Outdoor seating? | Gluten-free options? |
| Gluten-free | Easy to find parking? | Outdoor seating? | Clear dietary information? |
| Snack bar | Easy to find parking? | Long wait? | Dietary options? |
| Gastropub | Easy to find parking? | Outdoor seating? | Dietary options? |

### Coffee, Tea, & Sweets (26)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Coffee shop | Laptops welcome? | Power outlets? | Dogs allowed? |
| Cafe | Laptops welcome? | Power outlets? | Dogs allowed? |
| Coffee stand | Long wait? | Milk alternatives? | Dogs allowed? |
| Coffee lounge | Laptops welcome? | Power outlets? | Dogs allowed? |
| Roastery | Beans to take home? | Samples or tastings? | Dogs allowed? |
| Tea house | Easy to have a conversation? | Outdoor seating? | Dogs allowed? |
| Tea store | Samples or tastings? | Gift packaging? | Dogs allowed? |
| Juice shop | Made-to-order juice? | Dogs allowed? | Long wait? |
| Smoothie shop | Milk alternatives? | Dogs allowed? | Long wait? |
| Acai | Clear dietary information? | Dogs allowed? | Somewhere to sit? |
| Bakery | Dogs allowed? | Clear dietary information? | Somewhere to sit? |
| Bagel shop | Dogs allowed? | Somewhere to sit? | Long wait? |
| Donut shop | Dogs allowed? | Long wait? | Clear dietary information? |
| Cake shop | Dogs allowed? | Gift packaging? | Help choosing available? |
| Pastry shop | Dogs allowed? | Somewhere to sit? | Clear dietary information? |
| Dessert shop | Dogs allowed? | Takeaway available? | Clear dietary information? |
| Dessert restaurant | Dogs allowed? | Good for sharing? | Easy to book? |
| Ice cream | Dogs allowed? | Dairy-free frozen treats? | Somewhere to sit? |
| Gelato | Dogs allowed? | Dairy-free frozen treats? | Somewhere to sit? |
| Candy store | Dogs allowed? | Samples or tastings? | Gift packaging? |
| Chocolate shop | Dogs allowed? | Samples or tastings? | Gift packaging? |
| Chocolate factory | Guided tours available? | Samples or tastings? | Dogs allowed? |
| Chocolate lounge | Samples or tastings? | Somewhere to sit? | Dogs allowed? |
| Confectionery | Dogs allowed? | Samples or tastings? | Gift packaging? |
| Cat cafe | Entry fee to visit the animals? | Easy to book? | Dogs allowed? |
| Dog cafe | Dogs allowed? | Outdoor seating? | Entry fee to visit the animals? |

### Bars & Nightlife (30)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Bar | Easy to have a conversation? | Good alcohol-free options? | Dogs allowed? |
| Cocktail bar | Classic or house cocktails? | Good alcohol-free options? | Easy to book? |
| Pub | Dogs allowed? | Food with drinks? | Easy to have a conversation? |
| Irish pub | Live music on your visit? | Food with drinks? | Dogs allowed? |
| Billiards | Walk-in games or book ahead? | How did you pay to play? | Easy to have a conversation? |
| Sports bar | Good screens for watching sports? | Easy to book? | Food with drinks? |
| Wine bar | Wine by the glass? | Dogs allowed? | Easy to have a conversation? |
| Cider bar | Cider flights or individual drinks? | Easy to have a conversation? | Food with drinks? |
| Sake bar | Sake flights or by the glass? | Food with drinks? | Easy to have a conversation? |
| Game bar | Walk-in games or book ahead? | How did you pay to play? | Good alcohol-free options? |
| Gastropub | Dogs allowed? | What kind of beer selection? | Easy to have a conversation? |
| Bar & grill | Dogs allowed? | Good screens for watching sports? | Outdoor seating? |
| Dance hall | Room to dance? | Live music on your visit? | Coat storage? |
| Club | Cover charge or ticket required? | Room to dance? | Coat storage? |
| Disco | Cover charge or ticket required? | Room to dance? | Coat storage? |
| Lounge | Easy to have a conversation? | Easy to book? | Classic or house cocktails? |
| Hookah bar | Separate smoking area? | Smoky inside? | Good alcohol-free options? |
| Beer garden | Outdoor seating? | Shaded areas? | Dogs allowed? |
| Jazz club | Reserved seats or first come? | Was the sound good? | Cover charge or ticket required? |
| Hi-fi lounge | Was the sound good? | Easy to have a conversation? | Easy to book? |
| Brewery | What kind of beer selection? | Samples or tastings? | Dogs allowed? |
| Brewpub | What kind of beer selection? | Food with drinks? | Dogs allowed? |
| Winery | Samples or tastings? | Easy to book? | Dogs allowed? |
| Vineyard | Can you explore the vineyard? | Samples or tastings? | Dogs allowed? |
| Nightclub | Cover charge or ticket required? | Room to dance? | Coat storage? |
| Karaoke | Private rooms or open-stage karaoke? | Easy to book? | Easy to have a conversation? |
| Live music | Was the sound good? | Reserved seats or first come? | Cover charge or ticket required? |
| Comedy club | Reserved seats or first come? | Clear view from your spot? | Cover charge or ticket required? |
| Casino | Separate smoking area? | Food with drinks? | Coat storage? |
| Distillery | Tours or tastings? | Samples or tastings? | Easy to book? |

### Outdoors & Nature (45)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Park | Posted dog rules? | Shaded areas? | Bathroom available? |
| City park | Posted dog rules? | Shaded areas? | Somewhere to sit? |
| State park | Posted dog rules? | Bathroom available? | Entry fee? |
| National park | Posted dog rules? | Visitor information available? | Entry fee? |
| Hiking area | Posted dog rules? | How steep was your route? | Easy to follow the trail? |
| Trail | Posted dog rules? | How steep was your route? | Easy to follow the trail? |
| Hike | Posted dog rules? | How steep was your route? | Easy to follow the trail? |
| Beach | Posted dog rules? | Shaded areas? | Rinse-off showers? |
| Dog beach | Posted dog rules? | Rinse-off showers? | Easy route down to the beach? |
| Lake | Posted dog rules? | Shaded areas? | Bathroom available? |
| River | Posted dog rules? | How could you reach the water? | Shaded areas? |
| Island | Posted dog rules? | Shelter from the weather? | How did you reach the island? |
| Woods/forest | Posted dog rules? | Easy to follow the trail? | What was the path surface? |
| Mountain peak | Posted dog rules? | How steep was your route? | Shelter from the weather? |
| Scenic spot | Posted dog rules? | How far was the walk to the view? | Shaded areas? |
| Viewpoint | Posted dog rules? | How far was the walk to the view? | Somewhere to sit? |
| Overlook | Posted dog rules? | How far was the walk to the view? | Somewhere to sit? |
| Waterfall | Posted dog rules? | How far was the walk to the view? | How steep was your route? |
| Hot spring | Posted dog rules? | Natural or managed hot pools? | Showers available? |
| Cave | Posted dog rules? | Guided or self-guided cave visit? | Reservation required? |
| Nature preserve | Posted dog rules? | Easy to follow the trail? | Where could you watch wildlife? |
| Wildlife refuge | Posted dog rules? | What was the path surface? | Shaded areas? |
| Wildlife park | Posted dog rules? | How spread out were the exhibits? | Entry fee? |
| Botanical garden | Posted dog rules? | What was the path surface? | Shaded areas? |
| Garden | Posted dog rules? | Shaded areas? | Bathroom available? |
| Picnic area | Posted dog rules? | Shaded areas? | Picnic spots? |
| Dog park | Was the play area fully fenced? | Posted dog rules? | Drinking-water refill? |
| Playground | Play equipment for which ages? | Was the play area fully fenced? | Shaded areas? |
| Campground | Posted dog rules? | Campsite toilets? | How did you get a campsite? |
| RV park | Posted dog rules? | Water or power hookups? | Campsite toilets? |
| Dispersed camping | Posted dog rules? | Campsite toilets? | Posted vehicle requirements? |
| Cabin | Dogs allowed? | Guest cooking facilities? | Room temperature controls? |
| Cottage | Dogs allowed? | Guest cooking facilities? | Easy to find parking? |
| Marina | Posted dog rules? | Bathroom available? | Easy to find parking? |
| Fishing pier | Posted dog rules? | Somewhere to sit? | Shaded areas? |
| Fishing pond | Posted dog rules? | Fishing gear available? | Shaded areas? |
| Fishing charter | Fishing gear available? | Bathroom available? | Easy to book? |
| Ski resort | Posted dog rules? | Ski rental nearby? | What ski terrain did you find? |
| Cycling park | Posted dog rules? | Easy or technical riding? | Drinking-water refill? |
| Skate park | Posted dog rules? | Ramps or street features? | Lit for evening use on your visit? |
| Off-roading area | Posted dog rules? | Posted vehicle requirements? | Shelter from the weather? |
| Adventure sports | Guided or self-guided activity? | Equipment available? | Easy to book? |
| Surf | Surfboard rental available? | Was it busy? | Posted dog rules? |
| Surf break | Crowded in the water? | Rinse-off showers? | Posted dog rules? |
| Kayak/canoe rental | Equipment available? | Easy to book? | Dogs allowed in the rental boats? |

### Things To Do (54)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Tourist attraction | Entry fee? | How much time would you allow? | Step-free entrance? |
| Landmark | Signs explaining the place? | How far was the walk to the view? | How much time would you allow? |
| Historical place | Signs explaining the place? | Guided tours available? | Step-free entrance? |
| Historical landmark | Signs explaining the place? | Guided tours available? | Step-free entrance? |
| Monument | Signs explaining the place? | How far was the walk to the view? | Somewhere to sit? |
| Sculpture | Signs explaining the place? | Posted photography rules? | Step-free entrance? |
| Fountain | Somewhere to sit? | Shaded areas? | Posted photography rules? |
| Castle | Guided tours available? | How steep was your route? | Entry fee? |
| Plaza | Somewhere to sit? | Shaded areas? | Bathroom available? |
| Town square | Somewhere to sit? | Shaded areas? | Bathroom available? |
| Visitor center | Visitor information available? | Bathroom available? | Step-free entrance? |
| Museum | Permanent or temporary exhibitions? | How much time would you allow? | Entry fee? |
| Art museum | Permanent or temporary exhibitions? | Posted photography rules? | Somewhere to sit? |
| History museum | Signs explaining the place? | Guided tours available? | How much time would you allow? |
| Art gallery | Permanent or temporary exhibitions? | Posted photography rules? | Entry fee? |
| Art studio | Art activities or workshops? | Equipment available? | Booked or walked in? |
| Cultural landmark | Signs explaining the place? | Guided tours available? | Posted photography rules? |
| Cultural center | Art activities or workshops? | Visitor information available? | Entry fee? |
| Theater | Clear view from your spot? | Reserved seats or first come? | Step-free entrance? |
| Performing arts theater | Clear view from your spot? | Reserved seats or first come? | Step-free entrance? |
| Concert hall | Was the sound good? | Reserved seats or first come? | Coat storage? |
| Opera house | Clear view from your spot? | Was the sound good? | Coat storage? |
| Philharmonic hall | Was the sound good? | Reserved seats or first come? | Coat storage? |
| Amphitheater | Clear view from your spot? | Shaded areas? | Reserved seats or first come? |
| Auditorium | Was the sound good? | Clear view from your spot? | Step-free entrance? |
| Movie theater | Comfortable cinema seats? | Clear view from your spot? | Food sold for the film? |
| Planetarium | Reserved seats or first come? | Entry fee? | How much time would you allow? |
| Observation deck | Indoor or outdoor viewing? | Long wait? | How far was the walk to the view? |
| Aquarium | Hands-on activities? | How spread out were the exhibits? | Entry fee? |
| Zoo | How spread out were the exhibits? | Shaded areas? | Bathroom available? |
| Amusement park | Long waits for rides? | Storage during the activity? | Clear height or age requirements? |
| Water park | Storage during the activity? | Showers available? | Clear height or age requirements? |
| Ferris wheel | Long waits for rides? | Enclosed or open-air ride? | Entry fee? |
| Roller coaster | Long waits for rides? | Storage during the activity? | Clear height or age requirements? |
| Arcade | How did you pay to play? | Walk-in games or book ahead? | Easy to have a conversation? |
| Bowling | Booked or walked in? | Equipment available? | How did you pay to play? |
| Mini golf | How did you pay to play? | Shaded areas? | Equipment available? |
| Billiards | Walk-in games or book ahead? | How did you pay to play? | Equipment available? |
| Darts | Equipment available? | Walk-in games or book ahead? | Room for a group? |
| Axe throwing | Lessons or instruction available? | Equipment available? | Booked or walked in? |
| Board game lounge | What kind of board games? | How did you pay to play? | Food with drinks? |
| Go-karting | Clear height or age requirements? | Equipment available? | Long waits for rides? |
| Paintball | Equipment available? | Lessons or instruction available? | Showers available? |
| Indoor playground | Separate play areas by age? | Somewhere to sit? | Bathroom available? |
| Event venue | Flexible event space? | Food or catering options? | Step-free entrance? |
| Convention center | Easy to find your way? | Phone charging? | Step-free entrance? |
| Banquet hall | Food or catering options? | Room for a group? | Step-free entrance? |
| Wedding venue | Flexible event space? | Food or catering options? | Outdoor seating? |
| Community center | Visitor information available? | Flexible event space? | Step-free entrance? |
| Internet cafe | Did the Wi-Fi work well? | Power outlets? | Easy to have a conversation? |
| Dance hall | Room to dance? | Group or private lessons? | Showers available? |
| Barbecue area | Grills available? | Picnic spots? | Shaded areas? |
| Stadium | Was your seat covered? | Reserved seats or first come? | Bag checks on entry? |
| Arena | Was the sound good? | Reserved seats or first come? | Bag checks on entry? |

### Shopping (47)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Store | Dogs allowed? | Help choosing available? | Card, cash or app? |
| Market | Dogs allowed? | Card, cash or app? | Shelter while waiting? |
| Shopping mall | Easy to find your way? | Somewhere to sit? | Bathroom available? |
| Department store | Easy to find your way? | Somewhere to try things on? | Help choosing available? |
| General store | Dogs allowed? | Help choosing available? | Clear prices before paying? |
| Convenience store | Long wait? | Card, cash or app? | Step-free entrance? |
| Discount store | Step-free entrance? | Clear prices before paying? | Long wait? |
| Warehouse store | Space to load or unload? | Card, cash or app? | Easy to find parking? |
| Wholesaler | How did visitor entry work? | Space to load or unload? | Clear prices before paying? |
| Grocery store | Long wait? | Card, cash or app? | Refill your own containers? |
| Supermarket | Step-free entrance? | Long wait? | Easy to find parking? |
| Hypermarket | Easy to find your way? | Easy to find parking? | Space to load or unload? |
| Food store | Help choosing available? | Card, cash or app? | Long wait? |
| Farmers market | Card, cash or app? | Shelter while waiting? | Seating without a purchase? |
| Flea market | Dogs allowed? | Card, cash or app? | Seating without a purchase? |
| Asian grocery | Help choosing available? | Step-free entrance? | Card, cash or app? |
| Butcher | Help choosing available? | Long wait? | How did collection work? |
| Health food store | Refill your own containers? | Help choosing available? | Clear prices before paying? |
| Liquor store | Help choosing available? | Clear prices before paying? | Card, cash or app? |
| Book store | Dogs allowed? | Somewhere to sit? | Help choosing available? |
| Art supply store | Help choosing available? | Step-free entrance? | Clear prices before paying? |
| Craft store | Step-free entrance? | Clear prices before paying? | Help choosing available? |
| Gift shop | Gift wrapping offered? | Help choosing available? | Card, cash or app? |
| Toy store | Step-free entrance? | Gift wrapping offered? | Help choosing available? |
| Clothing store | Somewhere to try things on? | Help choosing available? | Dogs allowed? |
| Women's clothing | Somewhere to try things on? | Help choosing available? | Clear prices before paying? |
| Shoe store | Somewhere to try things on? | Help choosing available? | Dogs allowed? |
| Jewelry store | Help choosing available? | Repairs offered? | Walk-in or appointment? |
| Cosmetics store | Help choosing available? | Testers or samples available? | Clear prices before paying? |
| Beauty supply | Help choosing available? | Step-free entrance? | Card, cash or app? |
| Sporting goods | Help choosing available? | Repairs offered? | Somewhere to try things on? |
| Sportswear | Somewhere to try things on? | Help choosing available? | Card, cash or app? |
| Bicycle store | Repairs offered? | Help choosing available? | When was the work ready? |
| Electronics | Help choosing available? | Repairs offered? | Long wait? |
| Cell phone store | Long wait? | Clear instructions? | Repairs offered? |
| Home goods | Dogs allowed? | Space to load or unload? | Gift wrapping offered? |
| Home improvement | Help choosing available? | Space to load or unload? | How did collection work? |
| Hardware | Help choosing available? | Repairs offered? | Space to load or unload? |
| Building materials | Space to load or unload? | How did collection work? | Clear prices before paying? |
| Furniture | Step-free entrance? | Space to load or unload? | How did collection work? |
| Garden center | Dogs allowed? | Help choosing available? | Space to load or unload? |
| Pet store | Help choosing available? | Clear prices before paying? | Dogs allowed? |
| Auto parts | Help choosing available? | How did collection work? | Repairs offered? |
| Thrift store | Dogs allowed? | Somewhere to try things on? | Card, cash or app? |
| Discount supermarket | Long wait? | Card, cash or app? | Clear prices before paying? |
| Cosmetics | Help choosing available? | Testers or samples available? | Clear prices before paying? |
| Surf shop | Surfboard rental available? | Repairs offered? | Dogs allowed? |

### Wellness & Fitness (54)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Gym | Day pass available? | What kind of gym equipment? | Showers available? |
| Fitness center | Day pass available? | What kind of gym equipment? | Showers available? |
| Yoga studio | Slow or energetic yoga? | Was the class busy? | Easy to book? |
| Pilates studio | Was it a reformer class? | Was the class busy? | Easy to book? |
| CrossFit gym | Were workout adaptations explained? | Coached WOD or open gym? | Day pass available? |
| Functional fitness studio | Coached circuits or individual training? | Did coaches give technique feedback? | Was it busy? |
| Wellness studio | Easy to book? | Equipment available? | Private changing space? |
| Wellness center | Walk-in or appointment? | Private changing space? | Step-free entrance? |
| Sports club | Day pass available? | Open play or book a court? | Showers available? |
| Sports complex | Open play or book a court? | Showers available? | Visitor information available? |
| Sports coaching | Did coaches give technique feedback? | Group or private lessons? | Equipment available? |
| Sports school | Group or private lessons? | Lessons or instruction available? | Equipment available? |
| Athletic field | Grass or artificial playing surface? | Lit for evening use on your visit? | Bathroom available? |
| Swimming pool | Lap lanes or open swim? | Indoor or outdoor pool? | Showers available? |
| Tennis court | What was the tennis court surface? | Open play or book a court? | Court lights on for evening play? |
| Golf course | Full course or practice facilities? | Club rental available? | Booked or walked in? |
| Indoor golf | Simulator or indoor practice? | Club rental available? | Booked or walked in? |
| Ice skating rink | Drop-in or booked skating? | Equipment available? | Storage during the activity? |
| Volleyball court | Sand, grass or hard court? | Volleyball net ready to use? | Open play or book a court? |
| Soccer field | Grass or artificial playing surface? | Goals already set up? | Lit for evening use on your visit? |
| Basketball court | Full or half basketball court? | Open play or book a court? | Court lights on for evening play? |
| Pickleball court | Dedicated pickleball courts? | Open play or book a court? | Court lights on for evening play? |
| Spa | Walk-in or appointment? | Private changing space? | Dry sauna or steam room? |
| Massage | Could you choose the massage pressure? | Private appointment room? | Walk-in or appointment? |
| Massage spa | Could you choose the massage pressure? | Private changing space? | Walk-in or appointment? |
| Sauna | Dry sauna or steam room? | Private changing space? | Booked or walked in? |
| Chiropractor | Walk-in or appointment? | Clear instructions before the visit? | Private appointment room? |
| Dentist | Walk-in or appointment? | Clear instructions before the visit? | Step-free entrance? |
| Dental clinic | Walk-in or appointment? | Clear instructions before the visit? | Step-free entrance? |
| Optometrist | Eyewear to try on? | Walk-in or appointment? | Step-free entrance? |
| Ophthalmologist | Walk-in or appointment? | Clear instructions before the visit? | Step-free entrance? |
| Eye care center | Eyewear to try on? | Walk-in or appointment? | Long wait? |
| Doctor | Walk-in or appointment? | Private appointment room? | Step-free entrance? |
| Dermatologist | Walk-in or appointment? | Private appointment room? | Step-free entrance? |
| Pediatrician | Long wait? | Baby-changing table? | Step-free entrance? |
| Urgent care | Long wait? | Walk-in or appointment? | Easy to find parking? |
| Medical clinic | Walk-in or appointment? | Long wait? | Step-free entrance? |
| Medical center | Visitor information available? | Easy to find parking? | Step-free entrance? |
| Hospital | Visitor information available? | Easy to find parking? | Bathroom available? |
| Medical lab | Walk-in or booked lab visit? | Clear instructions before the visit? | Long wait? |
| Pharmacy | Prescription ready on arrival? | Long wait? | Step-free entrance? |
| Drugstore | Prescription ready on arrival? | Long wait? | Step-free entrance? |
| Physiotherapist | Space for guided exercises? | Private appointment room? | Step-free entrance? |
| Physical therapy | Space for guided exercises? | Private appointment room? | Step-free entrance? |
| Foot care | Walk-in or appointment? | Private appointment room? | Step-free entrance? |
| Podiatrist | Walk-in or appointment? | Private appointment room? | Step-free entrance? |
| Veterinary care | Separate animal waiting areas? | Walk-in or appointment? | Easy to find parking? |
| Mental health/therapy | Private appointment room? | Walk-in or appointment? | Step-free entrance? |
| Retreat | Scheduled or flexible retreat? | Clear dietary information? | Step-free entrance? |
| Beach tennis | Open play or book a court? | Equipment available? | Court lights on for evening play? |
| Beach volleyball | Volleyball net ready to use? | Open play or book a court? | Shaded areas? |
| Padel court | Open play or book a court? | Indoor or outdoor courts? | Equipment available? |
| Climbing gym | Bouldering or ropes? | Equipment available? | Was it busy? |
| Surf school | Equipment available? | Was the class busy? | Easy to book? |

### Stays (18)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Hotel | Quiet room when you rested? | Luggage storage? | Room temperature controls? |
| Resort | Quiet room when you rested? | Breakfast included? | Step-free entrance? |
| Motel | Quiet room when you rested? | Luggage storage? | Room temperature controls? |
| Hostel | Entire place or shared stay? | Lockers available? | Guest cooking facilities? |
| Inn | Quiet room when you rested? | Luggage storage? | Room temperature controls? |
| Bed & breakfast | Breakfast included? | Entire place or shared stay? | Self check-in or staff welcome? |
| Guest house | Entire place or shared stay? | Breakfast included? | Quiet room when you rested? |
| Private guest room | Entire place or shared stay? | Guest cooking facilities? | Self check-in or staff welcome? |
| Airbnb | Guest cooking facilities? | Self check-in or staff welcome? | Quiet room when you rested? |
| Vrbo | Guest cooking facilities? | Self check-in or staff welcome? | Quiet room when you rested? |
| Extended stay | Guest cooking facilities? | Laundry available? | Somewhere to work? |
| Cottage | Dogs allowed? | Guest cooking facilities? | Easy to find parking? |
| Cabin | Dogs allowed? | Guest cooking facilities? | Room temperature controls? |
| Campground | Posted dog rules? | Campsite toilets? | How did you get a campsite? |
| RV park | Posted dog rules? | Water or power hookups? | Campsite toilets? |
| Farm-stay | Entire place or shared stay? | Guest cooking facilities? | Dogs allowed? |
| Japanese inn | Entire place or shared stay? | Breakfast included? | Private changing space? |
| Mobile home park | Laundry available? | Easy to find parking? | Entire place or shared stay? |

### Services & Errands (49)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Bank | Long wait? | Walk-in or appointment? | Step-free entrance? |
| ATM | Could you withdraw cash? | Was the withdrawal fee clear? | Step-free entrance? |
| Accounting | Walk-in or appointment? | Cost explained before work began? | Where did the service happen? |
| Insurance | Clear instructions? | How did you book or contact them? | Cost explained before work began? |
| Real estate | Walk-in or appointment? | How did you book or contact them? | Where did the service happen? |
| Lawyer | Walk-in or appointment? | Cost explained before work began? | Somewhere to wait? |
| Consultant | Walk-in or appointment? | Cost explained before work began? | How did you book or contact them? |
| Marketing consultant | Cost explained before work began? | How did you book or contact them? | Where did the service happen? |
| Employment agency | Walk-in or appointment? | Long wait? | How did visitor entry work? |
| Nonprofit | How did visitor entry work? | How did you book or contact them? | Step-free entrance? |
| Association | How did visitor entry work? | How did you book or contact them? | Easy to find your way? |
| Florist | Help choosing available? | How did collection work? | Gift wrapping offered? |
| Catering | Cost explained before work began? | How did collection work? | How did you book or contact them? |
| Food delivery | How did you book or contact them? | Clear prices before paying? | Clear instructions? |
| Child care | How did visitor entry work? | Walk-in or appointment? | Easy to find your way? |
| Summer camp | Walk-in or appointment? | Clear visitor rules? | Counter or self-service drop-off? |
| Laundry | Self-service or staffed? | Machines available on arrival? | Card, cash or app? |
| Tailor | Somewhere to try things on? | When was the work ready? | Cost explained before work began? |
| Courier | Counter or self-service drop-off? | Long wait? | Card, cash or app? |
| Shipping | Counter or self-service drop-off? | Supplies provided? | Long wait? |
| Storage | How did visitor entry work? | Space to load or unload? | Easy to find parking? |
| Moving | Cost explained before work began? | Did the service start on time? | How did you book or contact them? |
| Electrician | Cost explained before work began? | How did you book or contact them? | Did the service start on time? |
| Plumber | Cost explained before work began? | How did you book or contact them? | Did the service start on time? |
| Locksmith | Did the service start on time? | Cost explained before work began? | How did you book or contact them? |
| Painter | Cost explained before work began? | How did you book or contact them? | Did the service start on time? |
| Roofing contractor | Cost explained before work began? | Did the service start on time? | Where did the service happen? |
| General contractor | Cost explained before work began? | Walk-in or appointment? | Did the service start on time? |
| Pet care | Walk-in or appointment? | Counter or self-service drop-off? | Cost explained before work began? |
| Pet boarding | Booked or walked in? | Counter or self-service drop-off? | Clear visitor rules? |
| Funeral home | How did visitor entry work? | Somewhere to wait? | Step-free entrance? |
| Cemetery | Easy to find your way? | Seating without a purchase? | Shaded areas? |
| Astrologer | Walk-in or appointment? | Clear prices before paying? | Where did the service happen? |
| Psychic | Walk-in or appointment? | Clear prices before paying? | Somewhere to wait? |
| Tour agency | Booked or walked in? | Clear instructions? | How did you book or contact them? |
| Travel agency | Walk-in or appointment? | Help choosing available? | Clear prices before paying? |
| Tourist information | Clear visitor rules? | Help choosing available? | Long wait? |
| Chauffeur | Booked or walked in? | How did you book or contact them? | Clear prices before paying? |
| Aircraft rental | Booked or walked in? | Clear visitor rules? | Clear prices before paying? |
| Telecommunications | Long wait? | Walk-in or appointment? | Where did the service happen? |
| Beauty service | Walk-in or appointment? | Clear prices before paying? | Step-free entrance? |
| Skin care clinic | Walk-in or appointment? | Clear instructions? | Somewhere to wait? |
| Tanning studio | Walk-in or appointment? | Private changing space? | Clear prices before paying? |
| Hair salon | Walk-in or appointment? | Long wait? | Card, cash or app? |
| Barber | Long wait? | Walk-in or appointment? | Clear prices before paying? |
| Nail salon | Walk-in or appointment? | Long wait? | Card, cash or app? |
| Makeup artist | Walk-in or appointment? | Where did the service happen? | Supplies provided? |
| Body art | Walk-in or appointment? | Clear prices before paying? | Clear visitor rules? |
| Tattoo/piercing | Walk-in or appointment? | Cost explained before work began? | Clear visitor rules? |

### Travel & Transit (38)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Airport | Easy to find your way? | Did the Wi-Fi work well? | Luggage storage? |
| International airport | Luggage storage? | Phone charging? | Showers available? |
| Airstrip | How did visitor entry work? | Somewhere to wait? | Easy to find parking? |
| Heliport | How did visitor entry work? | Step-free route to boarding? | Somewhere to wait? |
| Train station | Easy to find your way? | Step-free route to boarding? | Bathroom available? |
| Subway station | Easy to find your way? | Step-free route to boarding? | Bathroom available? |
| Light rail | Step-free route to boarding? | Shelter while waiting? | Clear instructions? |
| Tram stop | Shelter while waiting? | Step-free route to boarding? | Somewhere to sit? |
| Bus stop | Shelter while waiting? | Somewhere to sit? | Clear instructions? |
| Bus station | Easy to find your way? | Step-free route to boarding? | Bathroom available? |
| Ferry terminal | Step-free route to boarding? | Shelter while waiting? | Somewhere to wait? |
| Ferry service | Step-free route to boarding? | Somewhere to sit? | Bathroom available? |
| Transit station | Easy to find your way? | Bathroom available? | Somewhere to wait? |
| Transit stop | Shelter while waiting? | Somewhere to sit? | Easy to find your way? |
| Transit depot | How did visitor entry work? | Easy to find your way? | Somewhere to wait? |
| Taxi stand | Shelter while waiting? | Long wait? | Card, cash or app? |
| Taxi service | How did you book or contact them? | Long wait? | Card, cash or app? |
| Bike share station | How did you collect a bike? | Clear instructions? | Bikes available when you arrived? |
| Parking | Card, cash or app? | What was the parking surface? | Step-free entrance? |
| Parking lot | Card, cash or app? | What was the parking surface? | Easy to find your way? |
| Parking garage | Card, cash or app? | Step-free entrance? | Easy to find your way? |
| Park & ride | Card, cash or app? | Shelter while waiting? | Step-free route to boarding? |
| Gas station | Card, cash or app? | Bathroom available? | Tire air pump? |
| EV charging | Could you start charging? | Card or app to start charging? | Somewhere to wait? |
| E-bike charging | Could you start charging? | Card or app to start charging? | Shelter while waiting? |
| Rest stop | Bathroom available? | Seating without a purchase? | Water refill? |
| Truck stop | Showers available? | Bathroom available? | Easy to find parking? |
| Toll station | Card, cash or app? | Clear instructions? | Long wait? |
| Bridge | What was your walking route like? | Walking path separate from traffic? | Shaded areas? |
| Car dealer | Walk-in or appointment? | Help choosing available? | Easy to find parking? |
| Car rental | Long wait? | How did collection work? | Clear prices before paying? |
| Car repair | Walk-in or appointment? | Cost explained before work began? | When was the work ready? |
| Car wash | Self-service or staffed? | Long wait? | Card, cash or app? |
| Tire shop | Long wait? | Cost explained before work began? | When was the work ready? |
| Truck dealer | Walk-in or appointment? | Easy to find parking? | Help choosing available? |
| Transportation service | Booked or walked in? | How did you book or contact them? | Long wait? |
| Dump station | Card, cash or app? | Clear instructions? | Supplies provided? |
| RV water refill | Water refill? | Card, cash or app? | Clear instructions? |

### Work & Education (17)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Co-working space | Day or session pass? | Quiet place to concentrate? | Power outlets? |
| Business center | Day or session pass? | Separate study or meeting rooms? | Did the Wi-Fi work well? |
| Corporate office | How did visitor entry work? | Easy to find your way? | Somewhere to wait? |
| Manufacturer | How did visitor entry work? | Walk-in or appointment? | Easy to find parking? |
| Supplier | How did visitor entry work? | How did collection work? | Space to load or unload? |
| Farm | How did visitor entry work? | What was your walking route like? | Easy to find parking? |
| Ranch | Clear visitor rules? | What was your walking route like? | Easy to find parking? |
| Television studio | How did visitor entry work? | Bag checks on entry? | Clear visitor rules? |
| Library | Quiet place to concentrate? | Separate study or meeting rooms? | Visitor printing? |
| University | Easy to find your way? | How did visitor entry work? | Seating without a purchase? |
| School | How did visitor entry work? | Easy to find your way? | Walk-in or appointment? |
| Preschool | How did visitor entry work? | Walk-in or appointment? | Somewhere to wait? |
| Primary school | How did visitor entry work? | Walk-in or appointment? | Step-free entrance? |
| Secondary school | How did visitor entry work? | Walk-in or appointment? | Easy to find your way? |
| Academic department | Easy to find your way? | How did visitor entry work? | Step-free entrance? |
| Educational institution | How did visitor entry work? | Step-free entrance? | Easy to find your way? |
| Research institute | How did visitor entry work? | Walk-in or appointment? | Bag checks on entry? |

### Civic & Faith (16)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| City hall | How did visitor entry work? | Easy to find your way? | Step-free entrance? |
| Government office | Walk-in or appointment? | Long wait? | Easy to find your way? |
| Local government office | Walk-in or appointment? | Long wait? | Step-free entrance? |
| Courthouse | Bag checks on entry? | Easy to find your way? | Somewhere to wait? |
| Embassy | Walk-in or appointment? | Bag checks on entry? | Somewhere to wait? |
| Post office | Long wait? | Counter or self-service drop-off? | Supplies provided? |
| Police | How did visitor entry work? | Easy to find your way? | Somewhere to wait? |
| Neighborhood police station | How did visitor entry work? | Somewhere to wait? | Step-free entrance? |
| Fire station | How did visitor entry work? | Clear visitor rules? | Easy to find your way? |
| Church | Clear visitor rules? | Step-free entrance? | Somewhere to sit? |
| Mosque | Clear visitor rules? | Step-free entrance? | Somewhere to sit? |
| Synagogue | How did visitor entry work? | Clear visitor rules? | Step-free entrance? |
| Hindu temple | Clear visitor rules? | What did staff or signs say about photos? | Step-free entrance? |
| Buddhist temple | Clear visitor rules? | What did staff or signs say about photos? | Somewhere to sit? |
| Shinto shrine | Clear visitor rules? | What was your walking route like? | What did staff or signs say about photos? |
| Place of worship | Clear visitor rules? | How did visitor entry work? | Step-free entrance? |

### Areas & Addresses (15)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Apartment building | Easy to find your way? | Step-free entrance? | Easy to find parking? |
| Apartment complex | Easy to find your way? | Easy to find parking? | What was your walking route like? |
| Condominium complex | Easy to find your way? | Step-free entrance? | What was your walking route like? |
| Housing complex | Easy to find your way? | What was your walking route like? | Seating without a purchase? |
| Neighborhood | How did you get around? | Seating without a purchase? | Shaded areas? |
| Locality/city | How did you get around? | What stood out where you explored? | How long did you spend exploring? |
| Postal area | How did you get around? | Easy to find your way? | How long did you spend exploring? |
| Town | How did you get around? | What stood out where you explored? | Seating without a purchase? |
| Region | How did you get around? | How long did you spend exploring? | What stood out where you explored? |
| Country | What stood out where you explored? | How did you get around? | How long did you spend exploring? |
| Route/street | What was your walking route like? | Seating without a purchase? | Shaded areas? |
| Address | Easy to find your way? | Step-free entrance? | What was your walking route like? |
| Intersection | Marked crossing or bridge? | What was your walking route like? | Easy to find your way? |
| Landmark | Easy to find your way? | Seating without a purchase? | How long did you spend exploring? |
| Plus code | Easy to find your way? | How did you get around? | What was your walking route like? |

### Facilities & Other (7)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Public bathroom | Toilet fee? | Handwashing facilities? | Step-free entrance? |
| Public bath | Private changing space? | Lockers available? | Showers available? |
| Restroom | Toilet fee? | Handwashing facilities? | Baby-changing table? |
| Stable | Booked or walked in? | Riding equipment available? | Clear visitor rules? |
| Generic establishment | How did visitor entry work? | Step-free entrance? | Card, cash or app? |
| Point of interest | Easy to find your way? | Somewhere to sit? | How long did you spend exploring? |
| Unknown | Easy to find your way? | How did visitor entry work? | Step-free entrance? |

## Historical compatibility

`allQuestions` and `question(id:)` retain every historical definition. `availableQuestions` excludes the explicit `retiredQuestionIDs` set for new selections. Previously saved answers retain their original key and options; they are not migrated to superficially similar new questions. Retired definitions are retained below as an audit of the smaller library, not as new defaults.

| Historical key | Original subject |
| --- | --- |
| `place_detail_bao` | Bao |
| `place_detail_barbecue` | Barbecue availability |
| `place_detail_bowl` | Bowls |
| `place_detail_bread` | Bread to buy |
| `place_detail_broth` | Broth choices |
| `place_detail_burger` | Burger alternatives |
| `place_detail_cake` | Cake orders |
| `place_detail_class_size` | Session size |
| `place_detail_coffee_after` | After-meal coffee |
| `place_detail_crispy_takeaway` | Takeaway texture |
| `place_detail_curry` | Curry portions |
| `place_detail_dessert` | Dessert portions |
| `place_detail_dim_sum` | Dim sum service |
| `place_detail_dips` | Dips & sides |
| `place_detail_dumplings` | Dumplings |
| `place_detail_everyday_barrier` | Access area |
| `place_detail_everyday_browsing` | Browsing space |
| `place_detail_fishing_pier_setup` | Pier facilities |
| `place_detail_flatbread` | Flatbreads |
| `place_detail_fondue` | Fondue |
| `place_detail_fresh_herbs` | Herbs & extras |
| `place_detail_garden_labels` | Plant labels |
| `place_detail_grilled` | Grilled dishes |
| `place_detail_hotpot` | Hot-pot broth |
| `place_detail_karaoke_charge` | Karaoke payment |
| `place_detail_menu_guidance` | Menu help |
| `place_detail_noodles` | Noodles |
| `place_detail_oysters` | Oysters |
| `place_detail_pasta` | Pasta portions |
| `place_detail_pastry` | Pastry availability |
| `place_detail_pilates_format` | Pilates format |
| `place_detail_pilates_intro` | Pilates introduction |
| `place_detail_rice` | Rice dishes |
| `place_detail_roast_meats` | Roast dishes |
| `place_detail_salsa` | Salsa |
| `place_detail_sandwich` | Sandwiches |
| `place_detail_seafood` | Seafood choices |
| `place_detail_shared_platter` | Shared platters |
| `place_detail_skewers` | Skewers |
| `place_detail_small_plates` | Small plates |
| `place_detail_smoothie` | Smoothie changes |
| `place_detail_soup` | Soup meal |
| `place_detail_steak` | Steak sides |
| `place_detail_stew` | Stews & slow cooking |
| `place_detail_sushi_menu` | Sushi ordering |
| `place_detail_tacos` | Taco ordering |
| `place_detail_tapas` | Tapas pace |
| `place_detail_tea` | Tea service |
| `place_detail_tea_shop` | Tea to take home |
| `place_detail_toppings` | Toppings |
| `place_detail_wings` | Wing flavors |
