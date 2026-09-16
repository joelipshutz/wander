# Check-in question inventory

This inventory covers every selectable place subtype. Each row is the starting set for an optional Check-in: exactly three questions, with no answers selected. People can customize their set. Leaving a question unanswered means unknown; it does not mean “no.”

The catalog has **590 selectable subcategories across 14 categories**, **236 questions available for new selections**, and **51 historical definitions retained for saved answers**. There are 287 definitions in total. The available library has 3 questions with 2 choices, 197 questions with 3 choices, 32 questions with 4 choices, 4 questions with 5 choices. Optional library questions do not lengthen the initial three-question set.

All 277 original definitions were reviewed for practical, concise wording. Ingredient, ordering and browsing-space trivia has been retired from new selections. Existing keys and all of their stored option values remain compatible. The 10 new questions describe new facts; an old Pilates apparatus answer is never converted into an answer about whether someone attended a reformer class.

Questions distinguish a visit from a lasting rule. “Booked ahead” records what the person did. “Booking guidance” records guidance explicitly given by staff or signs. A class being busy describes that visit; it does not establish a fixed class size. Posted dog rules can record leash requirements or no pet dogs. Indoor/outdoor dog access is used for venues with those areas; an outdoor-only route does not receive indoor-access choices. No sign found establishes no permission.

This table is generated from the Swift catalog definitions and selectable taxonomy. Change the source first, then regenerate. Source files: [taxonomy](../../Wander/Services/WanderPlaceCategory.swift), [catalog contract](../../Wander/Features/Add/PlaceCheckInQuestionCatalog.swift), [core questions](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+CoreQuestions.swift), [core profiles](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+CoreProfiles.swift), [everyday questions](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+EverydayQuestions.swift), [everyday profiles](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+EverydayProfiles.swift).

## Core examples

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Coffee shop | Laptops welcome? | Power outlets? | Dogs allowed? |
| Cafe | Laptops welcome? | Outdoor seating? | Dogs allowed? |
| Thai | Dogs allowed? | Could you choose the spice level? | Vegetarian meal options? |
| Pilates studio | Was it a reformer class? | Was the class busy? | Easy to book? |
| CrossFit gym | Were workout adaptations explained? | Coached WOD or open gym? | Day pass or members only? |
| Functional fitness studio | Coached circuits or individual training? | Did coaches give technique feedback? | Was it busy? |
| Volleyball court | Sand, grass or hard court? | Volleyball net ready to use? | Open play or book a court? |
| Beach tennis | Open play or book a court? | Equipment provided? | Court lights on for evening play? |
| Beach volleyball | Volleyball net ready to use? | Open play or book a court? | How much shade did you find? |
| Park | Posted dog rules? | How much shade did you find? | Bathroom access? |
| Beach | Posted dog rules? | How much shade did you find? | Rinse facilities? |
| Surf | Surfboard rental available? | Was it busy? | Posted dog rules? |
| Surf break | Crowded in the water? | Rinse facilities? | Posted dog rules? |
| Stadium | Was your seat covered? | Reserved seats or first come? | Bags checked or stored on entry? |
| Arena | How was the sound from your spot? | Reserved seats or first come? | Bags checked or stored on entry? |

Dogs, laptops and outlets lead the coffee-shop set. Pilates asks about reformer class, busyness and booking; CrossFit asks about workout adaptations, coached WOD/open gym and drop-in access. Parks receive dog rules, shade and bathrooms. Rinse facilities remain specific to beaches and surf breaks.

New types have one picker home: Beach tennis, Beach volleyball, Padel court, Climbing gym and Surf school in Wellness & Fitness; Stadium and Arena in Things To Do; Surf, Surf break and Kayak/canoe rental in Outdoors & Nature; Surf shop in Shopping. Exact provider type tokens preserve these distinctions. MapKit’s broad Surfing type maps to Surf, not to an inferred surf break or school. The existing Volleyball type remains Volleyball court.

## Fallback contract

Every selectable subtype must have an explicit catalog row. Exhaustive tests enumerate the actual picker and reject missing rows, duplicate scopes, retired defaults or references that do not resolve. A user-written or unrecognized subtype keeps its own name and customization scope and receives a category fallback. Fallback does not count as curation for a new selectable subtype.

For restaurants, the selected Food type can correct a culinary label such as Ramen to Thai. Explicit venue formats such as Taco truck and Food court retain their practical question set when paired with a cuisine; a newly selected venue format takes precedence. Legacy formats such as Buffet and Food truck retain a separate preference scope and use the category fallback if they have no curated row. This resolver changes question context only, not stored category data.

When no subtype is supplied, the category’s normal default subtype is used. Restaurant is an additional category default rather than a picker entry:

| Default | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Restaurant | Dogs allowed? | Outdoor seating? | What booking guidance did staff or signs give? |

An unrecognized primary category uses Place. These fallback sets also have no selected answers.

| Category fallback | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Restaurants & Food | Dogs allowed? | Outdoor seating? | What booking guidance did staff or signs give? |
| Coffee, Tea, & Sweets | Laptops welcome? | Power outlets? | Dogs allowed? |
| Bars & Nightlife | Easy to have a conversation? | Good alcohol-free options? | Outdoor seating? |
| Outdoors & Nature | Posted dog rules? | How much shade did you find? | Bathroom access? |
| Things To Do | Entry fee? | How much time would you allow? | Step-free entrance? |
| Shopping | Dogs allowed? | Help choosing available? | Card, cash or app? |
| Wellness & Fitness | Step-free entrance? | Long wait? | Bathroom access? |
| Stays | Quiet room when you rested? | Luggage storage? | Room temperature controls? |
| Services & Errands | Walk-in or appointment? | Long wait? | Clear prices before paying? |
| Travel & Transit | Easy to find your way? | Somewhere to sit? | Bathroom access? |
| Work & Education | How was the Wi-Fi? | Power outlets? | Easy to have a conversation? |
| Civic & Faith | How did visitor entry work? | Step-free entrance? | Clear visitor rules? |
| Areas & Addresses | How did you get around? | Seating without a purchase? | Easy to find your way? |
| Facilities & Other | Step-free entrance? | Somewhere to sit? | Bathroom access? |
| Place | Step-free entrance? | Somewhere to sit? | Bathroom access? |

## Shared sets and rationale

There are 57 repeated question sets within categories, treating different order as the same set. Shared defaults reflect overlapping practical needs, not identical places or guaranteed facilities. Broad national cuisine labels do not establish recipes, diet or service. Their defaults ask useful dining questions without manufacturing regional distinctions. Activity and service formats get specialized questions when the type provides that context.

Cabin, cottage, campground and RV-park defaults also stay consistent when those identical subtypes occur under both Outdoors and Stays. Every repeated within-category set is listed below.

| Category | Subcategories sharing a set | Rationale |
| --- | --- | --- |
| Areas & Addresses | Condominium complex; Address | Answers describe only the part the person explored, not conditions across the whole district or country. |
| Areas & Addresses | Locality/city; Region; Country | Answers describe only the part the person explored, not conditions across the whole district or country. |
| Bars & Nightlife | Club; Disco; Nightclub | Equivalent drinking, listening, dancing or entry needs justify the shared set; actual answers remain optional. |
| Bars & Nightlife | Jazz club; Live music | Equivalent drinking, listening, dancing or entry needs justify the shared set; actual answers remain optional. |
| Civic & Faith | Church; Mosque | Visitor logistics are shared; no beliefs, attendance purpose or religious practices are inferred. |
| Civic & Faith | Synagogue; Place of worship | Visitor logistics are shared; no beliefs, attendance purpose or religious practices are inferred. |
| Coffee, Tea, & Sweets | Acai; Bakery; Pastry shop | These formats share the selected dog-access, seating, work, dietary or take-home needs without assuming a specific recipe. |
| Coffee, Tea, & Sweets | Coffee shop; Coffee lounge | These formats share the selected dog-access, seating, work, dietary or take-home needs without assuming a specific recipe. |
| Coffee, Tea, & Sweets | Coffee stand; Smoothie shop | These formats share the selected dog-access, seating, work, dietary or take-home needs without assuming a specific recipe. |
| Coffee, Tea, & Sweets | Ice cream; Gelato | These formats share the selected dog-access, seating, work, dietary or take-home needs without assuming a specific recipe. |
| Coffee, Tea, & Sweets | Tea store; Candy store; Chocolate shop; Confectionery | These formats share the selected dog-access, seating, work, dietary or take-home needs without assuming a specific recipe. |
| Outdoors & Nature | City park; Garden; Fishing pier | These open-air visits share the selected dog-rule, route, shade or rest needs; no facilities are presumed present. |
| Outdoors & Nature | Hiking area; Trail; Hike | These open-air visits share the selected dog-rule, route, shade or rest needs; no facilities are presumed present. |
| Outdoors & Nature | Park; Lake | These open-air visits share the selected dog-rule, route, shade or rest needs; no facilities are presumed present. |
| Outdoors & Nature | Viewpoint; Overlook | These open-air visits share the selected dog-rule, route, shade or rest needs; no facilities are presumed present. |
| Outdoors & Nature | Wildlife refuge; Botanical garden | These open-air visits share the selected dog-rule, route, shade or rest needs; no facilities are presumed present. |
| Restaurants & Food | Asian fusion; Mediterranean; Greek; Burgers | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Australian; New Zealand; Fijian; Samoan; Tongan; Chicken | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Bao buns; Taco | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | British; Irish; Bistro | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Californian; Vegan | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Chinese; Cantonese | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Dutch; Belgian | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | German; Austrian; Bavarian; Swiss; American; Canadian | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Gyro; Fish & chips; Hot dogs; Taco stand | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Italian; Steakhouse | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Kebab; Caribbean; Jamaican; Puerto Rican; Dominican; Haitian; Panamanian; Cuban; Hawaiian | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Korean; Pakistani; Sri Lankan; Bangladeshi; Nepalese; Tibetan; Mongolian; Georgian; Armenian; Uzbek; Afghan; Middle Eastern; Lebanese; Persian; Turkish; Israeli; Palestinian; Syrian; Iraqi; Jordanian; Yemeni; Egyptian; Moroccan; Tunisian; Algerian; Ethiopian; Eritrean; Brazilian; Argentinian; Colombian; Chilean; Peruvian; Venezuelan; Ecuadorian; Bolivian; Uruguayan; Salvadoran; Guatemalan; South American; Latin American | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Malaysian; Singaporean; Indonesian; Filipino; Burmese; Cambodian; Laotian; Asian; Salad | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Noodles; Somali; Kenyan; Nigerian; Ghanaian; Senegalese; South African; African; Polish; Ukrainian; Russian; Czech; Slovak; Hungarian; Romanian; Croatian; Serbian; Bosnian; Bulgarian; Albanian; Slovenian; Lithuanian; European; Eastern European; Tex-Mex | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Portuguese; Basque | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Scandinavian; Swedish; Norwegian; Finnish; Danish | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Taco truck; Bagel | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Thai; Indian; North Indian; South Indian; Mexican; Southwestern; Cajun | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Vietnamese; Dumplings; Taiwanese; Burrito; Soup | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Restaurants & Food | Yakiniku; Japanese BBQ | Shared dining logistics or dietary questions remain useful across these labels; the cuisine name does not prove menu contents or access. |
| Services & Errands | Hair salon; Nail salon | Equivalent appointments or on-site services share scheduling, payment or estimate needs. |
| Services & Errands | Moving; Electrician; Plumber; Locksmith; Painter | Equivalent appointments or on-site services share scheduling, payment or estimate needs. |
| Shopping | Art supply store; Craft store | These stores share the selected access, shopping assistance, fitting or purchase needs; no service is presumed available. |
| Shopping | Asian grocery; Beauty supply | These stores share the selected access, shopping assistance, fitting or purchase needs; no service is presumed available. |
| Shopping | Cosmetics store; Cosmetics | These stores share the selected access, shopping assistance, fitting or purchase needs; no service is presumed available. |
| Shopping | General store; Pet store | These stores share the selected access, shopping assistance, fitting or purchase needs; no service is presumed available. |
| Stays | Airbnb; Vrbo | Equivalent rental formats share practical arrival, kitchen and room questions. |
| Things To Do | Amusement park; Roller coaster | Equivalent visitor or audience needs support the shared set; exhibits, access and services are still observed, not assumed. |
| Things To Do | Concert hall; Philharmonic hall | Equivalent visitor or audience needs support the shared set; exhibits, access and services are still observed, not assumed. |
| Things To Do | Historical place; Historical landmark | Equivalent visitor or audience needs support the shared set; exhibits, access and services are still observed, not assumed. |
| Things To Do | Plaza; Town square | Equivalent visitor or audience needs support the shared set; exhibits, access and services are still observed, not assumed. |
| Things To Do | Theater; Performing arts theater | Equivalent visitor or audience needs support the shared set; exhibits, access and services are still observed, not assumed. |
| Travel & Transit | Bus station; Transit station | Equivalent travel or vehicle-purchase settings share arrival and service needs. |
| Travel & Transit | Car dealer; Truck dealer | Equivalent travel or vehicle-purchase settings share arrival and service needs. |
| Wellness & Fitness | Dentist; Dental clinic; Ophthalmologist | Equivalent training or appointment logistics; questions do not claim medical effectiveness or prerequisite skills. |
| Wellness & Fitness | Doctor; Dermatologist; Foot care; Podiatrist; Mental health/therapy | Equivalent training or appointment logistics; questions do not claim medical effectiveness or prerequisite skills. |
| Wellness & Fitness | Gym; Fitness center | Equivalent training or appointment logistics; questions do not claim medical effectiveness or prerequisite skills. |
| Wellness & Fitness | Pharmacy; Drugstore | Equivalent training or appointment logistics; questions do not claim medical effectiveness or prerequisite skills. |
| Wellness & Fitness | Physiotherapist; Physical therapy | Equivalent training or appointment logistics; questions do not claim medical effectiveness or prerequisite skills. |
| Work & Education | Academic department; Educational institution | Equivalent learning or visitor settings share entry, directions and facility questions. |
| Work & Education | School; Secondary school | Equivalent learning or visitor settings share entry, directions and facility questions. |

## Complete selectable inventory

### Restaurants & Food (174)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Thai | Dogs allowed? | Could you choose the spice level? | Vegetarian meal options? |
| Vietnamese | Dogs allowed? | Vegetarian meal options? | Takeaway available? |
| Chinese | Dogs allowed? | Good for sharing? | Room for a group? |
| Korean | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Japanese | Dogs allowed? | Counter seating? | Vegetarian meal options? |
| Indian | Dogs allowed? | Could you choose the spice level? | Vegetarian meal options? |
| Asian fusion | Dogs allowed? | Outdoor seating? | Vegetarian meal options? |
| Sushi | Dogs allowed? | Counter seating? | What booking guidance did staff or signs give? |
| Ramen | Dogs allowed? | Vegetarian meal options? | Long wait? |
| Dumplings | Dogs allowed? | Vegetarian meal options? | Takeaway available? |
| Bao buns | Dogs allowed? | Vegetarian meal options? | Somewhere to sit? |
| Noodles | Dogs allowed? | Vegetarian meal options? | Meal or snack? |
| Dim sum | Dogs allowed? | Good for sharing? | Long wait? |
| Hot pot | Cook at the table? | Smoky inside? | Vegetarian meal options? |
| Cantonese | Dogs allowed? | Good for sharing? | Room for a group? |
| Taiwanese | Dogs allowed? | Vegetarian meal options? | Takeaway available? |
| Izakaya | Dogs allowed? | Easy to have a conversation? | What booking guidance did staff or signs give? |
| Yakitori | Dogs allowed? | Counter seating? | Smoky inside? |
| Yakiniku | Cook at the table? | Smoky inside? | What booking guidance did staff or signs give? |
| North Indian | Dogs allowed? | Could you choose the spice level? | Vegetarian meal options? |
| South Indian | Dogs allowed? | Could you choose the spice level? | Vegetarian meal options? |
| Pakistani | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Sri Lankan | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Bangladeshi | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Nepalese | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Malaysian | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Singaporean | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Indonesian | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Filipino | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Burmese | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Cambodian | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Laotian | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Asian | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Tibetan | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Mongolian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Georgian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Armenian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Uzbek | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Mongolian BBQ | Cook at the table? | Table or counter service? | Clear dietary information? |
| Korean BBQ | Cook at the table? | Smoky inside? | Room for a group? |
| Japanese BBQ | Cook at the table? | Smoky inside? | What booking guidance did staff or signs give? |
| Japanese curry | Dogs allowed? | Could you choose the spice level? | Counter seating? |
| Tonkatsu | Dogs allowed? | Long wait? | Counter seating? |
| Afghan | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Middle Eastern | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Lebanese | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Persian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Turkish | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Israeli | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Palestinian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Syrian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Iraqi | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Jordanian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Yemeni | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Egyptian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Moroccan | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Tunisian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Algerian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Ethiopian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Eritrean | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Somali | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Kenyan | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Nigerian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Ghanaian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Senegalese | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| South African | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| African | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Falafel | Dogs allowed? | Vegan meal options? | Takeaway available? |
| Gyro | Dogs allowed? | Takeaway available? | Somewhere to sit? |
| Kebab | Dogs allowed? | Meal or snack? | Takeaway available? |
| Shawarma | Dogs allowed? | Table or counter service? | Takeaway available? |
| Halal | Dogs allowed? | Clear halal information? | Room for a group? |
| Italian | Dogs allowed? | Wine by the glass? | What booking guidance did staff or signs give? |
| Mediterranean | Dogs allowed? | Vegetarian meal options? | Outdoor seating? |
| Greek | Dogs allowed? | Vegetarian meal options? | Outdoor seating? |
| French | Dogs allowed? | Easy to book? | Easy to have a conversation? |
| Spanish | Dogs allowed? | Good for sharing? | Wine by the glass? |
| Tapas | Dogs allowed? | Good for sharing? | Counter seating? |
| Portuguese | Dogs allowed? | Clear dietary information? | What booking guidance did staff or signs give? |
| Basque | Dogs allowed? | Clear dietary information? | What booking guidance did staff or signs give? |
| German | Dogs allowed? | Vegetarian meal options? | Room for a group? |
| Austrian | Dogs allowed? | Vegetarian meal options? | Room for a group? |
| Bavarian | Dogs allowed? | Vegetarian meal options? | Room for a group? |
| Swiss | Dogs allowed? | Vegetarian meal options? | Room for a group? |
| Dutch | Dogs allowed? | Quick lunch or take your time? | Vegetarian meal options? |
| Belgian | Dogs allowed? | Quick lunch or take your time? | Vegetarian meal options? |
| British | Dogs allowed? | Quick lunch or take your time? | Easy to have a conversation? |
| Irish | Dogs allowed? | Quick lunch or take your time? | Easy to have a conversation? |
| Scandinavian | Dogs allowed? | What booking guidance did staff or signs give? | Vegetarian meal options? |
| Swedish | Dogs allowed? | What booking guidance did staff or signs give? | Vegetarian meal options? |
| Norwegian | Dogs allowed? | What booking guidance did staff or signs give? | Vegetarian meal options? |
| Finnish | Dogs allowed? | What booking guidance did staff or signs give? | Vegetarian meal options? |
| Danish | Dogs allowed? | What booking guidance did staff or signs give? | Vegetarian meal options? |
| Polish | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Ukrainian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Russian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Czech | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Slovak | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Hungarian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Romanian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Croatian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Serbian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Bosnian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Bulgarian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Albanian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Slovenian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Lithuanian | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| European | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Eastern European | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Pizza | Dogs allowed? | Pizza by the slice? | Outdoor seating? |
| Fish & chips | Dogs allowed? | Takeaway available? | Somewhere to sit? |
| Fondue | Dogs allowed? | Good for sharing? | What booking guidance did staff or signs give? |
| American | Dogs allowed? | Vegetarian meal options? | Room for a group? |
| Canadian | Dogs allowed? | Vegetarian meal options? | Room for a group? |
| Mexican | Dogs allowed? | Could you choose the spice level? | Vegetarian meal options? |
| Tex-Mex | Dogs allowed? | Meal or snack? | Vegetarian meal options? |
| Caribbean | Dogs allowed? | Meal or snack? | Takeaway available? |
| Jamaican | Dogs allowed? | Meal or snack? | Takeaway available? |
| Puerto Rican | Dogs allowed? | Meal or snack? | Takeaway available? |
| Dominican | Dogs allowed? | Meal or snack? | Takeaway available? |
| Haitian | Dogs allowed? | Meal or snack? | Takeaway available? |
| Panamanian | Dogs allowed? | Meal or snack? | Takeaway available? |
| Cuban | Dogs allowed? | Meal or snack? | Takeaway available? |
| Brazilian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Argentinian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Colombian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Chilean | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Peruvian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Venezuelan | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Ecuadorian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Bolivian | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Uruguayan | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Salvadoran | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Guatemalan | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| South American | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Latin American | Dogs allowed? | Good for sharing? | Vegetarian meal options? |
| Southwestern | Dogs allowed? | Could you choose the spice level? | Vegetarian meal options? |
| Cajun | Dogs allowed? | Could you choose the spice level? | Vegetarian meal options? |
| Californian | Dogs allowed? | Clear dietary information? | Outdoor seating? |
| Hawaiian | Dogs allowed? | Meal or snack? | Takeaway available? |
| Poke | Dogs allowed? | Clear dietary information? | Takeaway available? |
| Australian | Dogs allowed? | Good for sharing? | Meal or snack? |
| New Zealand | Dogs allowed? | Good for sharing? | Meal or snack? |
| Fijian | Dogs allowed? | Good for sharing? | Meal or snack? |
| Samoan | Dogs allowed? | Good for sharing? | Meal or snack? |
| Tongan | Dogs allowed? | Good for sharing? | Meal or snack? |
| Burgers | Dogs allowed? | Vegetarian meal options? | Outdoor seating? |
| Diner | Dogs allowed? | When is breakfast served? | Counter seating? |
| Hot dogs | Dogs allowed? | Takeaway available? | Somewhere to sit? |
| Barbecue | Dogs allowed? | Good for sharing? | Outdoor seating? |
| Wings | Dogs allowed? | Could you choose the spice level? | Room for a group? |
| Steakhouse | Dogs allowed? | What booking guidance did staff or signs give? | Wine by the glass? |
| Bar & grill | Dogs allowed? | Good screens for watching sports? | Outdoor seating? |
| Taco stand | Dogs allowed? | Takeaway available? | Somewhere to sit? |
| Taco truck | Dogs allowed? | Long wait? | Somewhere to sit? |
| Burrito | Dogs allowed? | Vegetarian meal options? | Takeaway available? |
| Taco | Dogs allowed? | Vegetarian meal options? | Somewhere to sit? |
| Sandwich | Dogs allowed? | Long wait? | Takeaway available? |
| Bagel | Dogs allowed? | Long wait? | Somewhere to sit? |
| Deli | Dogs allowed? | Table or counter service? | Quick lunch or take your time? |
| Salad | Dogs allowed? | Clear dietary information? | Meal or snack? |
| Bistro | Dogs allowed? | Quick lunch or take your time? | Easy to have a conversation? |
| Food court | Dogs allowed? | Somewhere to sit? | Clear dietary information? |
| Breakfast | Dogs allowed? | When is breakfast served? | Long wait? |
| Brunch | Dogs allowed? | Long wait? | What booking guidance did staff or signs give? |
| Soup | Dogs allowed? | Vegetarian meal options? | Takeaway available? |
| Chicken | Dogs allowed? | Good for sharing? | Meal or snack? |
| Seafood | Dogs allowed? | What booking guidance did staff or signs give? | Outdoor seating? |
| Oyster bar | Dogs allowed? | Counter seating? | Wine by the glass? |
| Vegetarian | Dogs allowed? | Vegan meal options? | Outdoor seating? |
| Vegan | Dogs allowed? | Clear dietary information? | Outdoor seating? |
| Gluten-free | Dogs allowed? | Clear gluten-free information? | Outdoor seating? |
| Snack bar | Dogs allowed? | Somewhere to sit? | Table or counter service? |
| Gastropub | Dogs allowed? | What kind of beer selection? | Easy to have a conversation? |

### Coffee, Tea, & Sweets (26)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Coffee shop | Laptops welcome? | Power outlets? | Dogs allowed? |
| Cafe | Laptops welcome? | Outdoor seating? | Dogs allowed? |
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
| Cat cafe | Entry fee to visit the animals? | Easy to book? | Somewhere to sit? |
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
| Club | Cover charge or ticket? | Room to dance? | Coat storage? |
| Disco | Cover charge or ticket? | Room to dance? | Coat storage? |
| Lounge | Easy to have a conversation? | Easy to book? | Classic or house cocktails? |
| Hookah bar | Smoking areas separated? | Smoky inside? | Good alcohol-free options? |
| Beer garden | Outdoor seating? | How much shade did you find? | Dogs allowed? |
| Jazz club | Reserved seats or first come? | How was the sound from your spot? | Cover charge or ticket? |
| Hi-fi lounge | How was the sound from your spot? | Easy to have a conversation? | Easy to book? |
| Brewery | What kind of beer selection? | Samples or tastings? | Dogs allowed? |
| Brewpub | What kind of beer selection? | Food with drinks? | Dogs allowed? |
| Winery | Samples or tastings? | Easy to book? | Dogs allowed? |
| Vineyard | Can you explore the vineyard? | Samples or tastings? | Dogs allowed? |
| Nightclub | Cover charge or ticket? | Room to dance? | Coat storage? |
| Karaoke | Private rooms or open-stage karaoke? | Easy to book? | Easy to have a conversation? |
| Live music | How was the sound from your spot? | Reserved seats or first come? | Cover charge or ticket? |
| Comedy club | Reserved seats or first come? | Clear view from your spot? | Cover charge or ticket? |
| Casino | Smoking areas separated? | Food with drinks? | Coat storage? |
| Distillery | Tours or tastings? | Samples or tastings? | Easy to book? |

### Outdoors & Nature (45)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Park | Posted dog rules? | How much shade did you find? | Bathroom access? |
| City park | Posted dog rules? | How much shade did you find? | Somewhere to sit? |
| State park | Posted dog rules? | Bathroom access? | Entry fee? |
| National park | Posted dog rules? | Visitor information available? | Entry fee? |
| Hiking area | Posted dog rules? | How steep was your route? | Easy to follow the trail? |
| Trail | Posted dog rules? | How steep was your route? | Easy to follow the trail? |
| Hike | Posted dog rules? | How steep was your route? | Easy to follow the trail? |
| Beach | Posted dog rules? | How much shade did you find? | Rinse facilities? |
| Dog beach | Posted dog rules? | Rinse facilities? | Easy route down to the beach? |
| Lake | Posted dog rules? | How much shade did you find? | Bathroom access? |
| River | Posted dog rules? | How could you reach the water? | How much shade did you find? |
| Island | Posted dog rules? | Shelter from the weather? | How did you reach the island? |
| Woods/forest | Posted dog rules? | Easy to follow the trail? | What was the path surface? |
| Mountain peak | Posted dog rules? | How steep was your route? | Shelter from the weather? |
| Scenic spot | Posted dog rules? | How far was the walk to the view? | How much shade did you find? |
| Viewpoint | Posted dog rules? | How far was the walk to the view? | Somewhere to sit? |
| Overlook | Posted dog rules? | How far was the walk to the view? | Somewhere to sit? |
| Waterfall | Posted dog rules? | How far was the walk to the view? | How steep was your route? |
| Hot spring | Posted dog rules? | Natural or managed hot pools? | Changing rooms and showers? |
| Cave | Posted dog rules? | Guided or self-guided cave visit? | What booking guidance did staff or signs give? |
| Nature preserve | Posted dog rules? | Easy to follow the trail? | Where could you watch wildlife? |
| Wildlife refuge | Posted dog rules? | What was the path surface? | How much shade did you find? |
| Wildlife park | Posted dog rules? | How spread out were the exhibits? | Entry fee? |
| Botanical garden | Posted dog rules? | What was the path surface? | How much shade did you find? |
| Garden | Posted dog rules? | How much shade did you find? | Somewhere to sit? |
| Picnic area | Posted dog rules? | How much shade did you find? | Picnic spots? |
| Dog park | Was the play area fenced? | Posted dog rules? | Drinking-water refill? |
| Playground | Play equipment for which ages? | Was the play area fenced? | How much shade did you find? |
| Campground | Posted dog rules? | Campsite toilets? | How did you get a campsite? |
| RV park | Posted dog rules? | Water or power hookups? | Campsite toilets? |
| Dispersed camping | Posted dog rules? | Campsite toilets? | Posted vehicle requirements? |
| Cabin | Dogs allowed? | Guest cooking facilities? | Room temperature controls? |
| Cottage | Dogs allowed? | Guest cooking facilities? | Where could you park? |
| Marina | Posted dog rules? | Bathroom access? | Parking on arrival? |
| Fishing pier | Posted dog rules? | Somewhere to sit? | How much shade did you find? |
| Fishing pond | Posted dog rules? | Fishing gear provided? | How much shade did you find? |
| Fishing charter | Fishing gear provided? | Bathroom access? | Easy to book? |
| Ski resort | Posted dog rules? | Ski rental nearby? | What ski terrain did you find? |
| Cycling park | Posted dog rules? | Easy or technical riding? | Drinking-water refill? |
| Skate park | Posted dog rules? | Ramps or street features? | Lit for evening use on your visit? |
| Off-roading area | Posted dog rules? | Posted vehicle requirements? | Shelter from the weather? |
| Adventure sports | Guided or self-guided activity? | Equipment provided? | Easy to book? |
| Surf | Surfboard rental available? | Was it busy? | Posted dog rules? |
| Surf break | Crowded in the water? | Rinse facilities? | Posted dog rules? |
| Kayak/canoe rental | Equipment provided? | Easy to book? | Dogs allowed in the rental boats? |

### Things To Do (54)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Tourist attraction | Entry fee? | How much time would you allow? | Step-free entrance? |
| Landmark | Signs explaining the place? | How far was the walk to the view? | How much time would you allow? |
| Historical place | Signs explaining the place? | Guided tours available? | Step-free entrance? |
| Historical landmark | Signs explaining the place? | Guided tours available? | Step-free entrance? |
| Monument | Signs explaining the place? | How far was the walk to the view? | Somewhere to sit? |
| Sculpture | Signs explaining the place? | Posted photography rules? | Step-free entrance? |
| Fountain | Somewhere to sit? | How much shade did you find? | Posted photography rules? |
| Castle | Guided tours available? | How steep was your route? | Entry fee? |
| Plaza | Somewhere to sit? | How much shade did you find? | Bathroom access? |
| Town square | Somewhere to sit? | How much shade did you find? | Bathroom access? |
| Visitor center | Visitor information available? | Bathroom access? | Step-free entrance? |
| Museum | Permanent or temporary exhibitions? | How much time would you allow? | Entry fee? |
| Art museum | Permanent or temporary exhibitions? | Posted photography rules? | Somewhere to sit? |
| History museum | Signs explaining the place? | Guided tours available? | How much time would you allow? |
| Art gallery | Permanent or temporary exhibitions? | Posted photography rules? | Entry fee? |
| Art studio | Art activities or workshops? | Equipment provided? | Booked or walked in? |
| Cultural landmark | Signs explaining the place? | Guided tours available? | Posted photography rules? |
| Cultural center | Art activities or workshops? | Visitor information available? | Entry fee? |
| Theater | Clear view from your spot? | Reserved seats or first come? | Step-free entrance? |
| Performing arts theater | Clear view from your spot? | Reserved seats or first come? | Step-free entrance? |
| Concert hall | How was the sound from your spot? | Reserved seats or first come? | Coat storage? |
| Opera house | Clear view from your spot? | How was the sound from your spot? | Coat storage? |
| Philharmonic hall | How was the sound from your spot? | Reserved seats or first come? | Coat storage? |
| Amphitheater | Clear view from your spot? | How much shade did you find? | Reserved seats or first come? |
| Auditorium | How was the sound from your spot? | Clear view from your spot? | Step-free entrance? |
| Movie theater | Comfortable cinema seats? | Clear view from your spot? | Food sold for the film? |
| Planetarium | Reserved seats or first come? | Entry fee? | How much time would you allow? |
| Observation deck | Indoor or outdoor viewing? | Long wait? | How far was the walk to the view? |
| Aquarium | Hands-on activities? | How spread out were the exhibits? | Entry fee? |
| Zoo | How spread out were the exhibits? | How much shade did you find? | Bathroom access? |
| Amusement park | How were the ride queues? | Storage during the activity? | Clear height or age requirements? |
| Water park | Storage during the activity? | Changing rooms and showers? | Clear height or age requirements? |
| Ferris wheel | How were the ride queues? | Enclosed or open-air ride? | Entry fee? |
| Roller coaster | How were the ride queues? | Storage during the activity? | Clear height or age requirements? |
| Arcade | How did you pay to play? | Walk-in games or book ahead? | Easy to have a conversation? |
| Bowling | Booked or walked in? | Equipment provided? | How did you pay to play? |
| Mini golf | How did you pay to play? | How much shade did you find? | Equipment provided? |
| Billiards | Walk-in games or book ahead? | How did you pay to play? | Equipment provided? |
| Darts | Equipment provided? | Walk-in games or book ahead? | Room for a group? |
| Axe throwing | Introduction or lessons offered? | Equipment provided? | Booked or walked in? |
| Board game lounge | What kind of board games? | How did you pay to play? | Food with drinks? |
| Go-karting | Clear height or age requirements? | Equipment provided? | How were the ride queues? |
| Paintball | Equipment provided? | Introduction or lessons offered? | Changing rooms and showers? |
| Indoor playground | Separate play areas by age? | Somewhere to sit? | Bathroom access? |
| Event venue | Flexible event space? | Food or catering options? | Step-free entrance? |
| Convention center | Easy to find your way? | Phone charging? | Step-free entrance? |
| Banquet hall | Food or catering options? | Room for a group? | Step-free entrance? |
| Wedding venue | Flexible event space? | Food or catering options? | Outdoor seating? |
| Community center | Visitor information available? | Flexible event space? | Step-free entrance? |
| Internet cafe | How was the Wi-Fi? | Power outlets? | Easy to have a conversation? |
| Dance hall | Room to dance? | Group or private lessons? | Changing rooms and showers? |
| Barbecue area | Grills available? | Picnic spots? | How much shade did you find? |
| Stadium | Was your seat covered? | Reserved seats or first come? | Bags checked or stored on entry? |
| Arena | How was the sound from your spot? | Reserved seats or first come? | Bags checked or stored on entry? |

### Shopping (47)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Store | Dogs allowed? | Help choosing available? | Card, cash or app? |
| Market | Dogs allowed? | Card, cash or app? | Shelter while waiting? |
| Shopping mall | Easy to find your way? | Somewhere to sit? | Bathroom access? |
| Department store | Easy to find your way? | Somewhere to try things on? | Help choosing available? |
| General store | Dogs allowed? | Help choosing available? | Clear prices before paying? |
| Convenience store | Long wait? | Card, cash or app? | Step-free entrance? |
| Discount store | Step-free entrance? | Clear prices before paying? | Long wait? |
| Warehouse store | Space to load or unload? | Card, cash or app? | Where could you park? |
| Wholesaler | How did visitor entry work? | Space to load or unload? | Clear prices before paying? |
| Grocery store | Long wait? | Card, cash or app? | Refill your own containers? |
| Supermarket | Step-free entrance? | Long wait? | Where could you park? |
| Hypermarket | Easy to find your way? | Where could you park? | Space to load or unload? |
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
| Shoe store | Somewhere to try things on? | Help choosing available? | Long wait? |
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
| Gym | Day pass or members only? | What kind of gym equipment? | Changing rooms and showers? |
| Fitness center | Day pass or members only? | What kind of gym equipment? | Changing rooms and showers? |
| Yoga studio | Slow or energetic yoga? | Was the class busy? | Easy to book? |
| Pilates studio | Was it a reformer class? | Was the class busy? | Easy to book? |
| CrossFit gym | Were workout adaptations explained? | Coached WOD or open gym? | Day pass or members only? |
| Functional fitness studio | Coached circuits or individual training? | Did coaches give technique feedback? | Was it busy? |
| Wellness studio | Easy to book? | Equipment provided? | Private changing space? |
| Wellness center | Walk-in or appointment? | Private changing space? | Step-free entrance? |
| Sports club | Day pass or members only? | Open play or book a court? | Changing rooms and showers? |
| Sports complex | Open play or book a court? | Changing rooms and showers? | Visitor information available? |
| Sports coaching | Did coaches give technique feedback? | Group or private lessons? | Equipment provided? |
| Sports school | Group or private lessons? | Introduction or lessons offered? | Equipment provided? |
| Athletic field | Grass or artificial playing surface? | Lit for evening use on your visit? | Bathroom access? |
| Swimming pool | Lap lanes or open swim? | Indoor or outdoor pool? | Changing rooms and showers? |
| Tennis court | What was the tennis court surface? | Open play or book a court? | Court lights on for evening play? |
| Golf course | Full course or practice facilities? | Club rental available? | Booked or walked in? |
| Indoor golf | Simulator or indoor practice? | Club rental available? | Booked or walked in? |
| Ice skating rink | Drop-in or booked skating? | Equipment provided? | Storage during the activity? |
| Volleyball court | Sand, grass or hard court? | Volleyball net ready to use? | Open play or book a court? |
| Soccer field | Grass or artificial playing surface? | Goals already set up? | Lit for evening use on your visit? |
| Basketball court | Full or half basketball court? | Open play or book a court? | Court lights on for evening play? |
| Pickleball court | Dedicated or shared pickleball courts? | Open play or book a court? | Court lights on for evening play? |
| Spa | Walk-in or appointment? | Private changing space? | Dry sauna or steam room? |
| Massage | Choice of massage style or pressure? | Private appointment space? | Walk-in or appointment? |
| Massage spa | Choice of massage style or pressure? | Private changing space? | Walk-in or appointment? |
| Sauna | Dry sauna or steam room? | Private changing space? | Booked or walked in? |
| Chiropractor | Walk-in or appointment? | Clear instructions before the visit? | Private appointment space? |
| Dentist | Walk-in or appointment? | Clear instructions before the visit? | Step-free entrance? |
| Dental clinic | Walk-in or appointment? | Clear instructions before the visit? | Step-free entrance? |
| Optometrist | Eyewear to try on? | Walk-in or appointment? | Step-free entrance? |
| Ophthalmologist | Walk-in or appointment? | Clear instructions before the visit? | Step-free entrance? |
| Eye care center | Eyewear to try on? | Walk-in or appointment? | Long wait? |
| Doctor | Walk-in or appointment? | Private appointment space? | Step-free entrance? |
| Dermatologist | Walk-in or appointment? | Private appointment space? | Step-free entrance? |
| Pediatrician | Long wait? | Baby-changing table? | Step-free entrance? |
| Urgent care | Long wait? | Walk-in or appointment? | Parking on arrival? |
| Medical clinic | Walk-in or appointment? | Long wait? | Step-free entrance? |
| Medical center | Visitor information available? | Parking on arrival? | Step-free entrance? |
| Hospital | Visitor information available? | Parking on arrival? | Bathroom access? |
| Medical lab | Walk-in or booked lab visit? | Clear instructions before the visit? | Long wait? |
| Pharmacy | Prescription ready on arrival? | Long wait? | Step-free entrance? |
| Drugstore | Prescription ready on arrival? | Long wait? | Step-free entrance? |
| Physiotherapist | Space for guided exercises? | Private appointment space? | Step-free entrance? |
| Physical therapy | Space for guided exercises? | Private appointment space? | Step-free entrance? |
| Foot care | Walk-in or appointment? | Private appointment space? | Step-free entrance? |
| Podiatrist | Walk-in or appointment? | Private appointment space? | Step-free entrance? |
| Veterinary care | Separate animal waiting areas? | Walk-in or appointment? | Parking on arrival? |
| Mental health/therapy | Private appointment space? | Walk-in or appointment? | Step-free entrance? |
| Retreat | Scheduled or flexible retreat? | Clear dietary information? | Step-free entrance? |
| Beach tennis | Open play or book a court? | Equipment provided? | Court lights on for evening play? |
| Beach volleyball | Volleyball net ready to use? | Open play or book a court? | How much shade did you find? |
| Padel court | Open play or book a court? | Indoor or outdoor courts? | Equipment provided? |
| Climbing gym | Bouldering or ropes? | Equipment provided? | Was it busy? |
| Surf school | Equipment provided? | Was the class busy? | Easy to book? |

### Stays (18)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Hotel | Quiet room when you rested? | Luggage storage? | Room temperature controls? |
| Resort | Quiet room when you rested? | Breakfast included? | Step-free entrance? |
| Motel | Quiet room when you rested? | Where could you park? | Room temperature controls? |
| Hostel | Entire place or shared stay? | Lockers available? | Guest cooking facilities? |
| Inn | Quiet room when you rested? | Breakfast included? | Self check-in or staff welcome? |
| Bed & breakfast | Breakfast included? | Entire place or shared stay? | Self check-in or staff welcome? |
| Guest house | Entire place or shared stay? | Breakfast included? | Quiet room when you rested? |
| Private guest room | Entire place or shared stay? | Guest cooking facilities? | Self check-in or staff welcome? |
| Airbnb | Guest cooking facilities? | Self check-in or staff welcome? | Quiet room when you rested? |
| Vrbo | Guest cooking facilities? | Self check-in or staff welcome? | Quiet room when you rested? |
| Extended stay | Guest cooking facilities? | Laundry available? | Somewhere to work? |
| Cottage | Dogs allowed? | Guest cooking facilities? | Where could you park? |
| Cabin | Dogs allowed? | Guest cooking facilities? | Room temperature controls? |
| Campground | Posted dog rules? | Campsite toilets? | How did you get a campsite? |
| RV park | Posted dog rules? | Water or power hookups? | Campsite toilets? |
| Farm-stay | Entire place or shared stay? | Guest cooking facilities? | Dogs allowed? |
| Japanese inn | Entire place or shared stay? | Breakfast included? | Private or shared changing space? |
| Mobile home park | Laundry available? | Where could you park? | Entire place or shared stay? |

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
| Storage | How did visitor entry work? | Space to load or unload? | Where could you park? |
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
| Cemetery | Easy to find your way? | Seating without a purchase? | How much shade did you find? |
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
| Tanning studio | Walk-in or appointment? | Private or shared changing space? | Clear prices before paying? |
| Hair salon | Walk-in or appointment? | Long wait? | Card, cash or app? |
| Barber | Long wait? | Walk-in or appointment? | Clear prices before paying? |
| Nail salon | Walk-in or appointment? | Long wait? | Card, cash or app? |
| Makeup artist | Walk-in or appointment? | Where did the service happen? | Supplies provided? |
| Body art | Walk-in or appointment? | Clear prices before paying? | Clear visitor rules? |
| Tattoo/piercing | Walk-in or appointment? | Cost explained before work began? | Clear visitor rules? |

### Travel & Transit (38)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Airport | Easy to find your way? | How was the Wi-Fi? | Luggage storage? |
| International airport | Luggage storage? | Phone charging? | Showers available? |
| Airstrip | How did visitor entry work? | Somewhere to wait? | Where could you park? |
| Heliport | How did visitor entry work? | Step-free route to boarding? | Somewhere to wait? |
| Train station | Easy to find your way? | Step-free route to boarding? | Bathroom access? |
| Subway station | Step-free route to boarding? | Easy to find your way? | Was it busy? |
| Light rail | Step-free route to boarding? | Shelter while waiting? | Clear instructions? |
| Tram stop | Shelter while waiting? | Step-free route to boarding? | Somewhere to sit? |
| Bus stop | Shelter while waiting? | Somewhere to sit? | Clear instructions? |
| Bus station | Somewhere to wait? | Bathroom access? | Easy to find your way? |
| Ferry terminal | Step-free route to boarding? | Shelter while waiting? | Somewhere to wait? |
| Ferry service | Step-free route to boarding? | Somewhere to sit? | Bathroom access? |
| Transit station | Easy to find your way? | Bathroom access? | Somewhere to wait? |
| Transit stop | Shelter while waiting? | Somewhere to sit? | Easy to find your way? |
| Transit depot | How did visitor entry work? | Easy to find your way? | Somewhere to wait? |
| Taxi stand | Shelter while waiting? | Long wait? | Card, cash or app? |
| Taxi service | How did you book or contact them? | Long wait? | Card, cash or app? |
| Bike share station | How did you collect a bike? | Clear instructions? | Bikes available when you arrived? |
| Parking | Card, cash or app? | What was the parking surface? | Step-free entrance? |
| Parking lot | Card, cash or app? | What was the parking surface? | Easy to find your way? |
| Parking garage | Card, cash or app? | Step-free entrance? | Easy to find your way? |
| Park & ride | Card, cash or app? | Shelter while waiting? | Step-free route to boarding? |
| Gas station | Card, cash or app? | Bathroom access? | Tire air pump? |
| EV charging | Could you start charging? | Card or app to start charging? | Somewhere to wait? |
| E-bike charging | Could you start charging? | Card or app to start charging? | Shelter while waiting? |
| Rest stop | Bathroom access? | Seating without a purchase? | Water refill? |
| Truck stop | Showers available? | Bathroom access? | Where could you park? |
| Toll station | Card, cash or app? | Clear instructions? | Long wait? |
| Bridge | What was your walking route like? | Walking path separate from traffic? | How much shade did you find? |
| Car dealer | Walk-in or appointment? | Help choosing available? | Where could you park? |
| Car rental | Long wait? | How did collection work? | Clear prices before paying? |
| Car repair | Walk-in or appointment? | Cost explained before work began? | When was the work ready? |
| Car wash | Self-service or staffed? | Long wait? | Card, cash or app? |
| Tire shop | Long wait? | Cost explained before work began? | When was the work ready? |
| Truck dealer | Walk-in or appointment? | Where could you park? | Help choosing available? |
| Transportation service | Booked or walked in? | How did you book or contact them? | Long wait? |
| Dump station | Card, cash or app? | Clear instructions? | Supplies provided? |
| RV water refill | Water refill? | Card, cash or app? | Clear instructions? |

### Work & Education (17)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Co-working space | Day or session pass? | Quiet place to concentrate? | Power outlets? |
| Business center | Day or session pass? | Separate study or meeting rooms? | How was the Wi-Fi? |
| Corporate office | How did visitor entry work? | Easy to find your way? | Somewhere to wait? |
| Manufacturer | How did visitor entry work? | Walk-in or appointment? | Where could you park? |
| Supplier | How did visitor entry work? | How did collection work? | Space to load or unload? |
| Farm | How did visitor entry work? | What was your walking route like? | Where could you park? |
| Ranch | Clear visitor rules? | What was your walking route like? | Where could you park? |
| Television studio | How did visitor entry work? | Bags checked or stored on entry? | Clear visitor rules? |
| Library | Quiet place to concentrate? | Separate study or meeting rooms? | Visitor printing? |
| University | Easy to find your way? | How did visitor entry work? | Seating without a purchase? |
| School | How did visitor entry work? | Easy to find your way? | Walk-in or appointment? |
| Preschool | How did visitor entry work? | Walk-in or appointment? | Somewhere to wait? |
| Primary school | How did visitor entry work? | Walk-in or appointment? | Step-free entrance? |
| Secondary school | How did visitor entry work? | Walk-in or appointment? | Easy to find your way? |
| Academic department | Easy to find your way? | How did visitor entry work? | Step-free entrance? |
| Educational institution | How did visitor entry work? | Step-free entrance? | Easy to find your way? |
| Research institute | How did visitor entry work? | Walk-in or appointment? | Bags checked or stored on entry? |

### Civic & Faith (16)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| City hall | How did visitor entry work? | Easy to find your way? | Step-free entrance? |
| Government office | Walk-in or appointment? | Long wait? | Easy to find your way? |
| Local government office | Walk-in or appointment? | Long wait? | Step-free entrance? |
| Courthouse | Bags checked or stored on entry? | Easy to find your way? | Somewhere to wait? |
| Embassy | Walk-in or appointment? | Bags checked or stored on entry? | Somewhere to wait? |
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
| Apartment building | Easy to find your way? | Step-free entrance? | Where could you park? |
| Apartment complex | Easy to find your way? | Where could you park? | What was your walking route like? |
| Condominium complex | Easy to find your way? | Step-free entrance? | What was your walking route like? |
| Housing complex | Easy to find your way? | What was your walking route like? | Seating without a purchase? |
| Neighborhood | How did you get around? | Seating without a purchase? | How much shade did you find? |
| Locality/city | How did you get around? | What stood out where you explored? | How long did you spend exploring? |
| Postal area | How did you get around? | Easy to find your way? | How long did you spend exploring? |
| Town | How did you get around? | What stood out where you explored? | Seating without a purchase? |
| Region | How did you get around? | How long did you spend exploring? | What stood out where you explored? |
| Country | What stood out where you explored? | How did you get around? | How long did you spend exploring? |
| Route/street | What was your walking route like? | Seating without a purchase? | How much shade did you find? |
| Address | Easy to find your way? | Step-free entrance? | What was your walking route like? |
| Intersection | Marked crossing or bridge? | What was your walking route like? | Easy to find your way? |
| Landmark | Easy to find your way? | Seating without a purchase? | How long did you spend exploring? |
| Plus code | Easy to find your way? | How did you get around? | What was your walking route like? |

### Facilities & Other (7)

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Public bathroom | Toilet fee? | Handwashing facilities? | Step-free entrance? |
| Public bath | Private or shared changing space? | Lockers available? | Showers available? |
| Restroom | Toilet fee? | Handwashing facilities? | Baby-changing table? |
| Stable | Booked or walked in? | Riding equipment provided? | Clear visitor rules? |
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
