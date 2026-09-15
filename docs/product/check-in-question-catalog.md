# Check-in question inventory

This inventory covers every selectable place subtype. Each row is the starting set for an optional Check-in: exactly three questions, with no answers selected. People can customize their set. Leaving a question unanswered means unknown; it does not mean “no.”

The current catalog has **579 selectable subcategories across 14 categories**, **277 reusable questions**, and **47 shared question sets within categories**. There are 234 questions with three choices, 39 with four, and 4 with five. The extra question definitions are available in the optional library; they do not lengthen the initial three-question set.

Questions distinguish the visit from a lasting rule. “Booked ahead” records what the person did. The separate optional “Booking guidance” question records guidance explicitly given by staff or signs. Missing an introduction does not imply that prior experience is required. Descriptions such as outdoor dog access do not assert indoor access or the existence of a patio.

This table is generated from the Swift catalog definitions and the selectable taxonomy, in picker order. Change the source catalog first, then regenerate the inventory. Source files: [taxonomy](../../Wander/Services/WanderPlaceCategory.swift), [catalog contract](../../Wander/Features/Add/PlaceCheckInQuestionCatalog.swift), [core questions](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+CoreQuestions.swift), [core profiles](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+CoreProfiles.swift), [everyday questions](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+EverydayQuestions.swift), [everyday profiles](../../Wander/Features/Add/PlaceCheckInQuestionCatalog+EverydayProfiles.swift).

## Core examples

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Pilates studio | What Pilates equipment did the session use? | How were first-timers introduced to the session? | How many people trained together? |
| CrossFit gym | Were scaled versions of the workout explained? | How was training structured? | Could a visitor train here? |
| Functional fitness studio | How was the session organized? | How was technique feedback offered? | How many people trained together? |
| Volleyball court | What surface did you play on? | Was a net ready to use? | How did you get time on a court? |
| Park | How much shade did you find? | What bathroom access did you find? | What surface did you use most? |
| Beach | Could you rinse sand off? | How much shade did you find? | What was the route down to the beach like? |
| Trail | How easy was the route to follow? | How steep was the route you took? | What surface did you use most? |

A park receives shade, bathroom and path questions. Rinse facilities are specific to beaches. Pilates asks about apparatus and introduction; CrossFit asks about workout scaling and session structure; unbranded functional training has its own set. Volleyball asks about surface, net and court access.

## Fallback contract

Every selectable subtype must have an explicit catalog row. The exhaustive catalog test checks the actual picker and rejects missing rows, duplicate scopes or question references that do not resolve. Runtime fallback is resilience for a user-written or unrecognized subtype; it does not count as curation for a newly added selectable subtype.

When no subtype is supplied, the category’s normal default subtype is used. “Restaurant” is an additional category default rather than a picker entry:

| Default | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Restaurant | How did you arrange this visit? | How easy was it to talk? | How were the vegetarian meal choices? |

A custom subtype keeps its own name and customization scope, while starting with the following category fallback. An unrecognized primary category uses the final Place row. These fallbacks also have no selected answers.

| Category fallback | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Restaurants & Food | How did you arrange this visit? | How easy was it to talk? | How were the vegetarian meal choices? |
| Coffee, Tea, & Sweets | What was the laptop setup? | Could you plug in? | Where were pet dogs allowed? |
| Bars & Nightlife | How easy was it to talk? | What were the alcohol-free choices like? | What outdoor seating was there? |
| Outdoors & Nature | How much shade did you find? | What bathroom access did you find? | What surface did you use most? |
| Things To Do | Was there an admission charge? | How much time would you set aside? | Was there a step-free way in? |
| Shopping | How much room was there to browse? | Could you get help choosing? | How could you pay? |
| Wellness & Fitness | Was there a step-free way in? | How long did you wait? | What bathroom access did you find? |
| Stays | How quiet was your room when you rested? | Was luggage storage available? | Could you adjust your room temperature? |
| Services & Errands | How did you arrange the visit? | How long did you wait? | Were prices clear before you paid? |
| Travel & Transit | Was it easy to find the right entrance or area? | Somewhere to sit? | What bathroom access did you find? |
| Work & Education | How did the Wi-Fi work? | Could you plug in? | How easy was it to talk? |
| Civic & Faith | How did visitor entry work? | Was there a step-free way in? | Were visiting rules clearly explained? |
| Areas & Addresses | How did you get around the part you explored? | Could you sit down without buying anything? | Was it easy to find the right entrance or area? |
| Facilities & Other | Was there a step-free way in? | Somewhere to sit? | What bathroom access did you find? |
| Place | Was there a step-free way in? | Somewhere to sit? | What bathroom access did you find? |


## Shared sets and rationale

Sharing questions is deliberate when labels describe equivalent practical needs. It does not assert that the places themselves have the same features. Broad national cuisines often do not provide enough information to justify different facilities or service assumptions. A specific format—ramen, hot pot, a taco truck, Pilates, or a volleyball court—provides firmer context for specialized questions.

The following lists every repeated set within a category, treating different question order as the same set. Cabin, cottage, campground and RV-park defaults also remain consistent when those identical subtypes occur under both Outdoors and Stays.

| Category | Subcategories sharing a set | Rationale |
| --- | --- | --- |
| Areas & Addresses | Locality/city; Region; Country | Answers describe only the area the person visited or explored, not conditions across an entire district or country. |
| Areas & Addresses | Condominium complex; Address | Answers describe only the area the person visited or explored, not conditions across an entire district or country. |
| Bars & Nightlife | Jazz club; Live music | Shared venue format and practical needs: sound, entry, show seating. |
| Bars & Nightlife | Pub; Gastropub | Shared venue format and practical needs: beer selection, food, conversation. |
| Bars & Nightlife | Club; Disco; Nightclub | Shared venue format and practical needs: coat storage, dancing, entry. |
| Civic & Faith | Synagogue; Place of worship | Visitor logistics apply across these labels without assuming a visitor’s identity or a venue’s rules. |
| Civic & Faith | Church; Mosque | Visitor logistics apply across these labels without assuming a visitor’s identity or a venue’s rules. |
| Coffee, Tea, & Sweets | Candy store; Chocolate shop; Confectionery | Equivalent product and visit needs: dietary information, gifts, samples & tastings. |
| Coffee, Tea, & Sweets | Ice cream; Gelato | Equivalent product and visit needs: frozen treats, seating, toppings. |
| Outdoors & Nature | Trail; Hike | Alternative names for the same route or viewing-stop needs. |
| Outdoors & Nature | Viewpoint; Overlook | Alternative names for the same route or viewing-stop needs. |
| Restaurants & Food | Portuguese; Basque | A broad cuisine name does not establish a narrower service format. Shared practical questions cover arranging the visit, dietary information, menu help. |
| Restaurants & Food | Yakiniku; Japanese BBQ | Equivalent table-cooking formats share visit arrangement, smoke and cooking setup. |
| Restaurants & Food | Malaysian; Singaporean; Indonesian; Filipino; Burmese; Cambodian; Laotian; Asian | A broad cuisine name does not establish a narrower service format. Shared practical questions cover dietary information, menu help, portions. |
| Restaurants & Food | Chinese; Cantonese | A broad cuisine name does not establish a narrower service format. Shared practical questions cover group seating, menu help, sharing. |
| Restaurants & Food | German; Austrian; Bavarian; Swiss; American; Canadian | A broad cuisine name does not establish a narrower service format. Shared practical questions cover group seating, portions, vegetarian choices. |
| Restaurants & Food | Dutch; Belgian | A broad cuisine name does not establish a narrower service format. Shared practical questions cover lunch, menu help, vegetarian choices. |
| Restaurants & Food | British; Irish | A broad cuisine name does not establish a narrower service format. Shared practical questions cover lunch, conversation, vegetarian choices. |
| Restaurants & Food | Australian; New Zealand; Fijian; Samoan; Tongan | A broad cuisine name does not establish a narrower service format. Shared practical questions cover menu help, portions, sharing. |
| Restaurants & Food | Caribbean; Jamaican; Puerto Rican; Dominican; Haitian; Panamanian; Cuban; Hawaiian | A broad cuisine name does not establish a narrower service format. Shared practical questions cover menu help, portions, takeaway. |
| Restaurants & Food | Somali; Kenyan; Nigerian; Ghanaian; Senegalese; South African; African; Polish; Ukrainian; Russian; Czech; Slovak; Hungarian; Romanian; Croatian; Serbian; Bosnian; Bulgarian; Albanian; Slovenian; Lithuanian; European; Eastern European | A broad cuisine name does not establish a narrower service format. Shared practical questions cover menu help, portions, vegetarian choices. |
| Restaurants & Food | Scandinavian; Swedish; Norwegian; Finnish; Danish | A broad cuisine name does not establish a narrower service format. Shared practical questions cover menu help, menu format, vegetarian choices. |
| Restaurants & Food | Afghan; Middle Eastern; Lebanese; Persian; Turkish; Israeli; Palestinian; Syrian; Iraqi; Jordanian; Yemeni | A broad cuisine name does not establish a narrower service format. Shared practical questions cover menu help, shared platters, vegetarian choices. |
| Restaurants & Food | Korean; Pakistani; Sri Lankan; Bangladeshi; Nepalese; Tibetan; Mongolian; Georgian; Armenian; Uzbek; Egyptian; Moroccan; Tunisian; Algerian; Brazilian; Argentinian; Colombian; Chilean; Peruvian; Venezuelan; Ecuadorian; Bolivian; Uruguayan; Salvadoran; Guatemalan; South American; Latin American | A broad cuisine name does not establish a narrower service format. Shared practical questions cover menu help, sharing, vegetarian choices. |
| Restaurants & Food | Mediterranean; Greek | A broad cuisine name does not establish a narrower service format. Shared practical questions cover outdoor seating, sharing, vegetarian choices. |
| Restaurants & Food | Southwestern; Cajun | A broad cuisine name does not establish a narrower service format. Shared practical questions cover portions, spice, vegetarian choices. |
| Restaurants & Food | Ethiopian; Eritrean | A broad cuisine name does not establish a narrower service format. Shared practical questions cover ordering, shared platters, vegetarian choices. |
| Restaurants & Food | Thai; Indian; North Indian; South Indian; Mexican | A broad cuisine name does not establish a narrower service format. Shared practical questions cover sharing, spice, vegetarian choices. |
| Services & Errands | Hair salon; Nail salon | Equivalent service logistics: appointments, payment, wait. Different trade labels do not justify invented answers or irrelevant collection questions. |
| Services & Errands | Moving; Electrician; Plumber; Painter | Equivalent service logistics: booking channel, cost estimate, service timing. Different trade labels do not justify invented answers or irrelevant collection questions. |
| Shopping | Store; Asian grocery; Beauty supply | Equivalent shopping needs: browsing space, payment, staff help. The subtype does not establish extra services. |
| Shopping | General store; Art supply store; Craft store | Equivalent shopping needs: browsing space, prices, staff help. The subtype does not establish extra services. |
| Shopping | Cosmetics store; Cosmetics | Equivalent shopping needs: prices, testers and samples, staff help. The subtype does not establish extra services. |
| Stays | Airbnb; Vrbo | Rental platform names do not establish different accommodation amenities. |
| Things To Do | Concert hall; Philharmonic hall | Shared visitor format and practical needs: sound, coat storage, show seating. |
| Things To Do | Historical place; Historical landmark | Shared visitor format and practical needs: tours, context, entrance. |
| Things To Do | Plaza; Town square | Shared visitor format and practical needs: bathroom, seating, shade. |
| Things To Do | Amusement park; Roller coaster | Shared visitor format and practical needs: ride queues, participation rules, belongings. |
| Things To Do | Theater; Performing arts theater | Shared visitor format and practical needs: show seating, sightlines, entrance. |
| Travel & Transit | Car dealer; Truck dealer | Equivalent dealership visit logistics: appointments, parking, staff help. |
| Wellness & Fitness | Gym; Fitness center | These broad gym labels do not establish that coached classes exist. Studio formats have separate questions. |
| Wellness & Fitness | Pharmacy; Drugstore | Shared facility or appointment logistics; no invented distinction about treatment, diagnosis or effectiveness. |
| Wellness & Fitness | Physiotherapist; Physical therapy | Shared facility or appointment logistics; no invented distinction about treatment, diagnosis or effectiveness. |
| Wellness & Fitness | Doctor; Dermatologist; Foot care; Podiatrist; Mental health/therapy | Shared facility or appointment logistics; no invented distinction about treatment, diagnosis or effectiveness. |
| Wellness & Fitness | Dentist; Dental clinic; Ophthalmologist | Shared facility or appointment logistics; no invented distinction about treatment, diagnosis or effectiveness. |
| Work & Education | School; Secondary school | The same visitor-arrival needs apply; no student or institutional affiliation is requested. |
| Work & Education | Academic department; Educational institution | The same visitor-arrival needs apply; no student or institutional affiliation is requested. |

## Complete selectable inventory

### Restaurants & Food

174 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Thai | Could you choose the heat level? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| Vietnamese | Could you adjust herbs or toppings? | How were the vegetarian meal choices? | Could you get food to take away? |
| Chinese | Did the food work well for sharing? | How did seating a group work? | Was it easy to choose what to order? |
| Korean | Did the food work well for sharing? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Japanese | What menu format was available? | Could you eat at a counter? | How were the vegetarian meal choices? |
| Indian | Could you choose the heat level? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| Asian fusion | Could you make a meal of small plates? | How clearly were ingredients or dietary options labeled? | How easy was it to talk? |
| Sushi | How could you order sushi? | Could you eat at a counter? | How did you arrange this visit? |
| Ramen | What broth choices were there? | Could you choose your noodles? | How long did you wait? |
| Dumplings | How could you try the dumplings? | How were the vegetarian meal choices? | Could you get food to take away? |
| Bao buns | Could you mix bao fillings? | How were the vegetarian meal choices? | Somewhere to sit? |
| Noodles | Could you choose your noodles? | How were the vegetarian meal choices? | What kind of meal did a usual order make? |
| Dim sum | How was dim sum ordered? | Did the food work well for sharing? | How long did you wait? |
| Hot pot | Could you choose more than one broth? | What broth choices were there? | How smoky did the space feel? |
| Cantonese | Did the food work well for sharing? | How did seating a group work? | Was it easy to choose what to order? |
| Taiwanese | Was it easy to choose what to order? | How were the vegetarian meal choices? | Could you get food to take away? |
| Izakaya | Could you make a meal of small plates? | How easy was it to talk? | How did you arrange this visit? |
| Yakitori | How were skewers ordered? | Could you eat at a counter? | How smoky did the space feel? |
| Yakiniku | Was anything cooked at your table? | How smoky did the space feel? | How did you arrange this visit? |
| North Indian | Could you choose the heat level? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| South Indian | Could you choose the heat level? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| Pakistani | Was it easy to choose what to order? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| Sri Lankan | Was it easy to choose what to order? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| Bangladeshi | Was it easy to choose what to order? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| Nepalese | Was it easy to choose what to order? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| Malaysian | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Singaporean | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Indonesian | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Filipino | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Burmese | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Cambodian | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Laotian | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Asian | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Tibetan | Did the food work well for sharing? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Mongolian | Did the food work well for sharing? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Georgian | Did the food work well for sharing? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Armenian | Did the food work well for sharing? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Uzbek | Did the food work well for sharing? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Mongolian BBQ | Was anything cooked at your table? | How did you order? | How clearly were ingredients or dietary options labeled? |
| Korean BBQ | Was anything cooked at your table? | How smoky did the space feel? | How did seating a group work? |
| Japanese BBQ | Was anything cooked at your table? | How smoky did the space feel? | How did you arrange this visit? |
| Japanese curry | How did curry orders come? | Could you choose the heat level? | Could you eat at a counter? |
| Tonkatsu | What menu format was available? | How did fried food hold up to takeaway? | Could you eat at a counter? |
| Afghan | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Middle Eastern | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Lebanese | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Persian | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Turkish | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Israeli | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Palestinian | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Syrian | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Iraqi | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Jordanian | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Yemeni | Could you order a platter for the table? | How were the vegetarian meal choices? | Was it easy to choose what to order? |
| Egyptian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Moroccan | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Tunisian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Algerian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Ethiopian | Could you order a platter for the table? | How were the vegetarian meal choices? | How did you order? |
| Eritrean | Could you order a platter for the table? | How were the vegetarian meal choices? | How did you order? |
| Somali | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Kenyan | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Nigerian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Ghanaian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Senegalese | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| South African | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| African | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Falafel | How were the vegan meal choices? | Could you try several dips or sides? | Could you get food to take away? |
| Gyro | What kind of meal did a usual order make? | Could you get food to take away? | Somewhere to sit? |
| Kebab | What was the grilled-food selection like? | What kind of meal did a usual order make? | Could you get food to take away? |
| Shawarma | What kind of meal did a usual order make? | How did you order? | Could you get food to take away? |
| Halal | How was halal information provided? | How were the vegetarian meal choices? | How did seating a group work? |
| Italian | What menu format was available? | How was the by-the-glass selection? | How did you arrange this visit? |
| Mediterranean | How were the vegetarian meal choices? | Did the food work well for sharing? | What outdoor seating was there? |
| Greek | Did the food work well for sharing? | How were the vegetarian meal choices? | What outdoor seating was there? |
| French | What menu format was available? | How was the by-the-glass selection? | How did the meal unfold? |
| Spanish | Could you make a meal of small plates? | How was the by-the-glass selection? | How did the meal unfold? |
| Tapas | Could you order small plates as you went? | Did the food work well for sharing? | Could you eat at a counter? |
| Portuguese | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | How did you arrange this visit? |
| Basque | Was it easy to choose what to order? | How clearly were ingredients or dietary options labeled? | How did you arrange this visit? |
| German | What kind of meal did a usual order make? | How were the vegetarian meal choices? | How did seating a group work? |
| Austrian | What kind of meal did a usual order make? | How were the vegetarian meal choices? | How did seating a group work? |
| Bavarian | What kind of meal did a usual order make? | How were the vegetarian meal choices? | How did seating a group work? |
| Swiss | What kind of meal did a usual order make? | How were the vegetarian meal choices? | How did seating a group work? |
| Dutch | Was it easy to choose what to order? | How did it work for lunch? | How were the vegetarian meal choices? |
| Belgian | Was it easy to choose what to order? | How did it work for lunch? | How were the vegetarian meal choices? |
| British | How did it work for lunch? | How were the vegetarian meal choices? | How easy was it to talk? |
| Irish | How did it work for lunch? | How were the vegetarian meal choices? | How easy was it to talk? |
| Scandinavian | Was it easy to choose what to order? | What menu format was available? | How were the vegetarian meal choices? |
| Swedish | Was it easy to choose what to order? | What menu format was available? | How were the vegetarian meal choices? |
| Norwegian | Was it easy to choose what to order? | What menu format was available? | How were the vegetarian meal choices? |
| Finnish | Was it easy to choose what to order? | What menu format was available? | How were the vegetarian meal choices? |
| Danish | Was it easy to choose what to order? | What menu format was available? | How were the vegetarian meal choices? |
| Polish | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Ukrainian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Russian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Czech | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Slovak | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Hungarian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Romanian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Croatian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Serbian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Bosnian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Bulgarian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Albanian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Slovenian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Lithuanian | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| European | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Eastern European | Was it easy to choose what to order? | What kind of meal did a usual order make? | How were the vegetarian meal choices? |
| Pizza | How was pizza sold? | How long did you wait? | What outdoor seating was there? |
| Fish & chips | How did fried food hold up to takeaway? | What kind of meal did a usual order make? | Somewhere to sit? |
| Fondue | How were fondue portions arranged? | How clearly were ingredients or dietary options labeled? | How did you arrange this visit? |
| American | What kind of meal did a usual order make? | How were the vegetarian meal choices? | How did seating a group work? |
| Canadian | What kind of meal did a usual order make? | How were the vegetarian meal choices? | How did seating a group work? |
| Mexican | Could you choose the heat level? | How were the vegetarian meal choices? | Did the food work well for sharing? |
| Tex-Mex | What kind of meal did a usual order make? | How were the vegetarian meal choices? | How did you choose salsa? |
| Caribbean | Was it easy to choose what to order? | What kind of meal did a usual order make? | Could you get food to take away? |
| Jamaican | Was it easy to choose what to order? | What kind of meal did a usual order make? | Could you get food to take away? |
| Puerto Rican | Was it easy to choose what to order? | What kind of meal did a usual order make? | Could you get food to take away? |
| Dominican | Was it easy to choose what to order? | What kind of meal did a usual order make? | Could you get food to take away? |
| Haitian | Was it easy to choose what to order? | What kind of meal did a usual order make? | Could you get food to take away? |
| Panamanian | Was it easy to choose what to order? | What kind of meal did a usual order make? | Could you get food to take away? |
| Cuban | Was it easy to choose what to order? | What kind of meal did a usual order make? | Could you get food to take away? |
| Brazilian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Argentinian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Colombian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Chilean | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Peruvian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Venezuelan | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Ecuadorian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Bolivian | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Uruguayan | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Salvadoran | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Guatemalan | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| South American | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Latin American | Was it easy to choose what to order? | Did the food work well for sharing? | How were the vegetarian meal choices? |
| Southwestern | Could you choose the heat level? | How were the vegetarian meal choices? | What kind of meal did a usual order make? |
| Cajun | Could you choose the heat level? | How were the vegetarian meal choices? | What kind of meal did a usual order make? |
| Californian | How clearly were ingredients or dietary options labeled? | What outdoor seating was there? | How did it work for lunch? |
| Hawaiian | What kind of meal did a usual order make? | Could you get food to take away? | Was it easy to choose what to order? |
| Poke | Could you build your own bowl? | How clearly were ingredients or dietary options labeled? | Could you get food to take away? |
| Australian | Was it easy to choose what to order? | What kind of meal did a usual order make? | Did the food work well for sharing? |
| New Zealand | Was it easy to choose what to order? | What kind of meal did a usual order make? | Did the food work well for sharing? |
| Fijian | Was it easy to choose what to order? | What kind of meal did a usual order make? | Did the food work well for sharing? |
| Samoan | Was it easy to choose what to order? | What kind of meal did a usual order make? | Did the food work well for sharing? |
| Tongan | Was it easy to choose what to order? | What kind of meal did a usual order make? | Did the food work well for sharing? |
| Burgers | Were non-meat burgers offered? | How long did you wait? | What outdoor seating was there? |
| Diner | When was breakfast served? | Could you eat at a counter? | What kind of meal did a usual order make? |
| Hot dogs | Could you choose toppings? | Somewhere to sit? | Could you get food to take away? |
| Barbecue | How was the barbecue availability? | Did the food work well for sharing? | What outdoor seating was there? |
| Wings | Could you mix sauces in an order? | Could you choose the heat level? | How did seating a group work? |
| Steakhouse | How were sides ordered? | How did you arrange this visit? | How was the by-the-glass selection? |
| Bar & grill | Was food available with drinks? | Could you comfortably watch a game? | What outdoor seating was there? |
| Taco stand | Could you mix taco fillings? | How did you choose salsa? | Somewhere to sit? |
| Taco truck | Could you mix taco fillings? | How long did you wait? | Somewhere to sit? |
| Burrito | What kind of meal did a usual order make? | How were the vegetarian meal choices? | Could you get food to take away? |
| Taco | Could you mix taco fillings? | How did you choose salsa? | How were the vegetarian meal choices? |
| Sandwich | Could you adjust your sandwich? | How long did you wait? | Could you get food to take away? |
| Bagel | Could you adjust your sandwich? | How long did you wait? | Somewhere to sit? |
| Deli | Could you adjust your sandwich? | How did you order? | How did it work for lunch? |
| Salad | Could you build your own bowl? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Bistro | What menu format was available? | How did it work for lunch? | How easy was it to talk? |
| Food court | Somewhere to sit? | How clearly were ingredients or dietary options labeled? | How long did you wait? |
| Breakfast | When was breakfast served? | Could you eat at a counter? | How long did you wait? |
| Brunch | How long did you wait? | How did you arrange this visit? | What outdoor seating was there? |
| Soup | What could you pair with soup? | How were the vegetarian meal choices? | Could you get food to take away? |
| Chicken | Did the food work well for sharing? | What kind of meal did a usual order make? | How did fried food hold up to takeaway? |
| Seafood | How was seafood presented? | How did you arrange this visit? | What outdoor seating was there? |
| Oyster bar | How were oysters ordered? | Could you eat at a counter? | How was the by-the-glass selection? |
| Vegetarian | How were the vegan meal choices? | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? |
| Vegan | How clearly were ingredients or dietary options labeled? | What kind of meal did a usual order make? | Could you get food to take away? |
| Gluten-free | How were gluten-free choices identified? | How clearly were ingredients or dietary options labeled? | Could you get food to take away? |
| Snack bar | What kind of meal did a usual order make? | Somewhere to sit? | How did you order? |
| Gastropub | Was food available with drinks? | What was the beer selection like? | How easy was it to talk? |

### Coffee, Tea, & Sweets

26 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Coffee shop | What was the laptop setup? | Could you plug in? | Where were pet dogs allowed? |
| Cafe | What was the laptop setup? | What outdoor seating was there? | Where were pet dogs allowed? |
| Coffee stand | How long did you wait? | What milk alternatives were offered? | Somewhere to sit? |
| Coffee lounge | Could you plug in? | How easy was it to talk? | Somewhere to sit? |
| Roastery | Could you buy beans to take home? | Could you sample or taste before choosing? | Somewhere to sit? |
| Tea house | How was tea served? | How easy was it to talk? | Somewhere to sit? |
| Tea store | How could you buy tea? | Could you sample or taste before choosing? | Could you get items packaged as a gift? |
| Juice shop | How was juice prepared? | How long did you wait? | Somewhere to sit? |
| Smoothie shop | Could you adjust smoothie ingredients? | What milk alternatives were offered? | How long did you wait? |
| Acai | Could you choose toppings? | What kind of meal did a usual order make? | Somewhere to sit? |
| Bakery | What bread could you buy? | What pastry choice was left when you arrived? | Somewhere to sit? |
| Bagel shop | Could you adjust your sandwich? | How long did you wait? | Somewhere to sit? |
| Donut shop | What pastry choice was left when you arrived? | How long did you wait? | How clearly were ingredients or dietary options labeled? |
| Cake shop | How did cake ordering work? | Could you get items packaged as a gift? | Could you get food to take away? |
| Pastry shop | What pastry choice was left when you arrived? | Somewhere to sit? | Could you get food to take away? |
| Dessert shop | How were desserts served? | Could you get food to take away? | How clearly were ingredients or dietary options labeled? |
| Dessert restaurant | How were desserts served? | Did the food work well for sharing? | How did you arrange this visit? |
| Ice cream | Were dairy-free choices available? | Could you choose toppings? | Somewhere to sit? |
| Gelato | Were dairy-free choices available? | Could you choose toppings? | Somewhere to sit? |
| Candy store | Could you get items packaged as a gift? | How clearly were ingredients or dietary options labeled? | Could you sample or taste before choosing? |
| Chocolate shop | Could you get items packaged as a gift? | Could you sample or taste before choosing? | How clearly were ingredients or dietary options labeled? |
| Chocolate factory | Could you join a guided tour? | Could you sample or taste before choosing? | Could you get items packaged as a gift? |
| Chocolate lounge | Could you sample or taste before choosing? | How were desserts served? | Somewhere to sit? |
| Confectionery | Could you get items packaged as a gift? | Could you sample or taste before choosing? | How clearly were ingredients or dietary options labeled? |
| Cat cafe | Was there a charge to spend time with the animals? | How did you arrange this visit? | How easy was it to talk? |
| Dog cafe | Was there a charge to spend time with the animals? | Where were pet dogs allowed? | What outdoor seating was there? |

### Bars & Nightlife

30 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Bar | How easy was it to talk? | What were the alcohol-free choices like? | What outdoor seating was there? |
| Cocktail bar | How did the cocktail menu work? | What were the alcohol-free choices like? | How did you arrange this visit? |
| Pub | Was food available with drinks? | What was the beer selection like? | How easy was it to talk? |
| Irish pub | Was there live music during your visit? | Was food available with drinks? | What was the beer selection like? |
| Billiards | How did getting a game work? | How did you pay to play? | How easy was it to talk? |
| Sports bar | Could you comfortably watch a game? | How did you arrange this visit? | Was food available with drinks? |
| Wine bar | How was the by-the-glass selection? | Could you make a meal of small plates? | How easy was it to talk? |
| Cider bar | Could you compare ciders? | How easy was it to talk? | Was food available with drinks? |
| Sake bar | Could you try smaller sake pours? | Could you make a meal of small plates? | How easy was it to talk? |
| Game bar | How did getting a game work? | How did you pay to play? | What were the alcohol-free choices like? |
| Gastropub | Was food available with drinks? | What was the beer selection like? | How easy was it to talk? |
| Bar & grill | Was food available with drinks? | Could you comfortably watch a game? | What outdoor seating was there? |
| Dance hall | Was there room to dance? | Was there live music during your visit? | Was there somewhere to leave a coat? |
| Club | How did entry work for your visit? | Was there room to dance? | Was there somewhere to leave a coat? |
| Disco | How did entry work for your visit? | Was there room to dance? | Was there somewhere to leave a coat? |
| Lounge | How easy was it to talk? | How did you arrange this visit? | How did the cocktail menu work? |
| Hookah bar | How were smoking and smoke-free areas arranged? | How smoky did the space feel? | What were the alcohol-free choices like? |
| Beer garden | What outdoor seating was there? | How much shade did you find? | Where were pet dogs allowed? |
| Jazz club | How was show seating arranged? | How was the sound from your spot? | How did entry work for your visit? |
| Hi-fi lounge | How was the sound from your spot? | How easy was it to talk? | How did you arrange this visit? |
| Brewery | What was the beer selection like? | Could you sample or taste before choosing? | What outdoor seating was there? |
| Brewpub | What was the beer selection like? | Was food available with drinks? | What outdoor seating was there? |
| Winery | Could you sample or taste before choosing? | How did you arrange this visit? | What outdoor seating was there? |
| Vineyard | Could you explore outside the tasting room? | Could you sample or taste before choosing? | How much shade did you find? |
| Nightclub | How did entry work for your visit? | Was there room to dance? | Was there somewhere to leave a coat? |
| Karaoke | What was the karaoke setup? | How did you arrange this visit? | How was karaoke charged? |
| Live music | How was the sound from your spot? | How was show seating arranged? | How did entry work for your visit? |
| Comedy club | How was show seating arranged? | How was the view from your spot? | How did entry work for your visit? |
| Casino | How were smoking and smoke-free areas arranged? | Was food available with drinks? | Was there somewhere to leave a coat? |
| Distillery | Could you see how it is made? | Could you sample or taste before choosing? | How did you arrange this visit? |

### Outdoors & Nature

42 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Park | How much shade did you find? | What bathroom access did you find? | What surface did you use most? |
| City park | How much shade did you find? | Somewhere to sit? | What picnic setup did you find? |
| State park | Was there an admission charge? | How easy was the route to follow? | What bathroom access did you find? |
| National park | Was there an admission charge? | How easy was the route to follow? | Could you get practical visitor information? |
| Hiking area | How easy was the route to follow? | How steep was the route you took? | Could you refill drinking water? |
| Trail | How easy was the route to follow? | How steep was the route you took? | What surface did you use most? |
| Hike | How easy was the route to follow? | How steep was the route you took? | What surface did you use most? |
| Beach | Could you rinse sand off? | How much shade did you find? | What was the route down to the beach like? |
| Dog beach | What pet-dog rule was posted for this area? | Could you rinse sand off? | What was the route down to the beach like? |
| Lake | How could you reach the water? | What picnic setup did you find? | What bathroom access did you find? |
| River | How could you reach the water? | What surface did you use most? | How much shade did you find? |
| Island | How did you get onto the island? | Was there shelter on the route or grounds? | Could you refill drinking water? |
| Woods/forest | How easy was the route to follow? | What surface did you use most? | Was there shelter on the route or grounds? |
| Mountain peak | How steep was the route you took? | How easy was the route to follow? | Was there shelter on the route or grounds? |
| Scenic spot | How much walking to reach the view? | Somewhere to sit? | How much shade did you find? |
| Viewpoint | How much walking to reach the view? | What surface did you use most? | Somewhere to sit? |
| Overlook | How much walking to reach the view? | What surface did you use most? | Somewhere to sit? |
| Waterfall | How close could you get to the falls? | What surface did you use most? | How steep was the route you took? |
| Hot spring | How was the hot-spring access arranged? | What changing facilities were there? | Was there an admission charge? |
| Cave | What was the visit format? | What surface did you use most? | How did you arrange this visit? |
| Nature preserve | How easy was the route to follow? | What viewing setup was available? | What pet-dog rule was posted for this area? |
| Wildlife refuge | What viewing setup was available? | What surface did you use most? | How much shade did you find? |
| Wildlife park | What viewing setup was available? | How much walking between exhibits? | Was there an admission charge? |
| Botanical garden | Were plants identified along the way? | What surface did you use most? | How much shade did you find? |
| Garden | Somewhere to sit? | How much shade did you find? | What surface did you use most? |
| Picnic area | What picnic setup did you find? | How much shade did you find? | What bathroom access did you find? |
| Dog park | Was the play area fenced? | What pet-dog rule was posted for this area? | Could you refill drinking water? |
| Playground | Who did the play equipment seem designed for? | Was the play area fenced? | How much shade did you find? |
| Campground | How did you secure your campsite? | What toilet facilities were there? | How level was your pitch? |
| RV park | What hookups were offered? | What toilet facilities were there? | How did you secure your campsite? |
| Dispersed camping | What toilet facilities were there? | How level was your pitch? | What did the signed route require? |
| Cabin | Could you adjust your room temperature? | What cooking facilities could you use? | Could you refill water here? |
| Cottage | What cooking facilities could you use? | Could you adjust your room temperature? | Where could you park? |
| Marina | Was there a launch or dock? | What bathroom access did you find? | How was parking on arrival? |
| Fishing pier | What was provided for fishing on the pier? | Somewhere to sit? | How much shade did you find? |
| Fishing pond | Was fishing gear available? | How could you fish here? | Somewhere to sit? |
| Fishing charter | Was fishing gear available? | How did you arrange this visit? | What bathroom access did you find? |
| Ski resort | What terrain did you find? | Where was rental equipment available? | Where could you put belongings for the activity? |
| Cycling park | What type of riding was it set up for? | Could you refill drinking water? | How easy was the route to follow? |
| Skate park | What was the skate setup? | Was the activity area lit for evening use? | Could you refill drinking water? |
| Off-roading area | What did the signed route require? | How easy was the route to follow? | Was there shelter on the route or grounds? |
| Adventure sports | How was the activity supervised? | How was equipment provided? | How did you arrange this visit? |

### Things To Do

52 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Tourist attraction | Was there an admission charge? | How much time would you set aside? | Was there a step-free way in? |
| Landmark | Was the place's story explained? | How much walking to reach the view? | How much time would you set aside? |
| Historical place | Was the place's story explained? | Could you join a guided tour? | Was there a step-free way in? |
| Historical landmark | Was the place's story explained? | Could you join a guided tour? | Was there a step-free way in? |
| Monument | Was the place's story explained? | How much walking to reach the view? | Somewhere to sit? |
| Sculpture | Was the place's story explained? | What photography rule was posted? | Was there a step-free way in? |
| Fountain | Somewhere to sit? | How much shade did you find? | What photography rule was posted? |
| Castle | Could you join a guided tour? | How steep was the route you took? | Was there an admission charge? |
| Plaza | Somewhere to sit? | How much shade did you find? | What bathroom access did you find? |
| Town square | Somewhere to sit? | How much shade did you find? | What bathroom access did you find? |
| Visitor center | Could you get practical visitor information? | What bathroom access did you find? | Was there a step-free way in? |
| Museum | What kind of exhibitions were on? | How much time would you set aside? | Was there an admission charge? |
| Art museum | What kind of exhibitions were on? | What photography rule was posted? | Somewhere to sit? |
| History museum | Was the place's story explained? | Could you join a guided tour? | How much time would you set aside? |
| Art gallery | What kind of exhibitions were on? | What photography rule was posted? | Was there an admission charge? |
| Art studio | Could visitors make something? | How was equipment provided? | How did you arrange this visit? |
| Cultural landmark | Was the place's story explained? | Could you join a guided tour? | What photography rule was posted? |
| Cultural center | Could visitors make something? | Could you get practical visitor information? | Was there an admission charge? |
| Theater | How was the view from your spot? | How was show seating arranged? | Was there a step-free way in? |
| Performing arts theater | How was the view from your spot? | How was show seating arranged? | Was there a step-free way in? |
| Concert hall | How was the sound from your spot? | How was show seating arranged? | Was there somewhere to leave a coat? |
| Opera house | How was the view from your spot? | How was the sound from your spot? | Was there somewhere to leave a coat? |
| Philharmonic hall | How was the sound from your spot? | How was show seating arranged? | Was there somewhere to leave a coat? |
| Amphitheater | How was the view from your spot? | How much shade did you find? | How was show seating arranged? |
| Auditorium | How was the sound from your spot? | How was the view from your spot? | Was there a step-free way in? |
| Movie theater | What were the cinema seats like? | How was the view from your spot? | What food was available for the film? |
| Planetarium | How was show seating arranged? | Was there an admission charge? | How much time would you set aside? |
| Observation deck | Was the main viewing area indoors or out? | How long did you wait? | How much walking to reach the view? |
| Aquarium | Were there activities to try yourself? | How much walking between exhibits? | Was there an admission charge? |
| Zoo | How much walking between exhibits? | How much shade did you find? | What bathroom access did you find? |
| Amusement park | How did ride queues work? | Where could you put belongings for the activity? | Were height or age requirements easy to find? |
| Water park | Where could you put belongings for the activity? | What changing facilities were there? | Were height or age requirements easy to find? |
| Ferris wheel | How did ride queues work? | What was your seat or cabin like? | Was there an admission charge? |
| Roller coaster | How did ride queues work? | Where could you put belongings for the activity? | Were height or age requirements easy to find? |
| Arcade | How did you pay to play? | How did getting a game work? | How easy was it to talk? |
| Bowling | How did you arrange this visit? | How was equipment provided? | How did you pay to play? |
| Mini golf | How did you pay to play? | How much shade did you find? | How was equipment provided? |
| Billiards | How did getting a game work? | How did you pay to play? | How did you arrange this visit? |
| Darts | How was equipment provided? | How did getting a game work? | How did seating a group work? |
| Axe throwing | What introduction was offered to first-timers? | How was equipment provided? | How did you arrange this visit? |
| Board game lounge | What was the board-game selection like? | How did you pay to play? | Was food available with drinks? |
| Go-karting | Were height or age requirements easy to find? | How was equipment provided? | How did ride queues work? |
| Paintball | How was equipment provided? | What introduction was offered to first-timers? | What changing facilities were there? |
| Indoor playground | How were play ages separated? | Somewhere to sit? | What bathroom access did you find? |
| Event venue | How flexible was the space? | What food arrangements were possible? | Was there a step-free way in? |
| Convention center | Was it easy to find the right entrance or area? | Could you charge a phone? | Was there a step-free way in? |
| Banquet hall | What food arrangements were possible? | How did seating a group work? | Was there a step-free way in? |
| Wedding venue | How flexible was the space? | What food arrangements were possible? | What outdoor seating was there? |
| Community center | Could you get practical visitor information? | How flexible was the space? | Was there a step-free way in? |
| Internet cafe | How did the Wi-Fi work? | Could you plug in? | How easy was it to talk? |
| Dance hall | Was there room to dance? | How were lessons arranged? | What changing facilities were there? |
| Barbecue area | What cooking facilities were there? | What picnic setup did you find? | How much shade did you find? |

### Shopping

46 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Store | How much room was there to browse? | Could you get help choosing? | How could you pay? |
| Market | How much room was there to browse? | How could you pay? | Was there shelter while you waited? |
| Shopping mall | Was it easy to find the right entrance or area? | Somewhere to sit? | What bathroom access did you find? |
| Department store | Was it easy to find the right entrance or area? | Could you try things on? | Could you get help choosing? |
| General store | How much room was there to browse? | Could you get help choosing? | Were prices clear before you paid? |
| Convenience store | How long did you wait? | How could you pay? | Was there a step-free way in? |
| Discount store | How much room was there to browse? | Were prices clear before you paid? | How long did you wait? |
| Warehouse store | Was there somewhere to load or unload items? | How could you pay? | How much room was there to browse? |
| Wholesaler | How did visitor entry work? | Was there somewhere to load or unload items? | Were prices clear before you paid? |
| Grocery store | How long did you wait? | How could you pay? | Could you refill your own containers? |
| Supermarket | How much room was there to browse? | How long did you wait? | Where could you park? |
| Hypermarket | Was it easy to find the right entrance or area? | Where could you park? | Was there somewhere to load or unload items? |
| Food store | Could you get help choosing? | How could you pay? | How long did you wait? |
| Farmers market | How could you pay? | Was there shelter while you waited? | Could you sit down without buying anything? |
| Flea market | How much room was there to browse? | How could you pay? | Could you sit down without buying anything? |
| Asian grocery | Could you get help choosing? | How much room was there to browse? | How could you pay? |
| Butcher | Could you get help choosing? | How long did you wait? | How did collection work? |
| Health food store | Could you refill your own containers? | Could you get help choosing? | Were prices clear before you paid? |
| Liquor store | Could you get help choosing? | Were prices clear before you paid? | How could you pay? |
| Book store | How much room was there to browse? | Somewhere to sit? | Could you get help choosing? |
| Art supply store | Could you get help choosing? | How much room was there to browse? | Were prices clear before you paid? |
| Craft store | How much room was there to browse? | Were prices clear before you paid? | Could you get help choosing? |
| Gift shop | Was gift wrapping offered? | Could you get help choosing? | How could you pay? |
| Toy store | How much room was there to browse? | Was gift wrapping offered? | Could you get help choosing? |
| Clothing store | Could you try things on? | Could you get help choosing? | How much room was there to browse? |
| Women's clothing | Could you try things on? | Could you get help choosing? | Were prices clear before you paid? |
| Shoe store | Could you try things on? | Could you get help choosing? | How long did you wait? |
| Jewelry store | Could you get help choosing? | Were repair services offered? | How did you arrange the visit? |
| Cosmetics store | Could you get help choosing? | Could you try a tester or take a sample? | Were prices clear before you paid? |
| Beauty supply | Could you get help choosing? | How much room was there to browse? | How could you pay? |
| Sporting goods | Could you get help choosing? | Were repair services offered? | Could you try things on? |
| Sportswear | Could you try things on? | Could you get help choosing? | How could you pay? |
| Bicycle store | Were repair services offered? | Could you get help choosing? | When was the work ready? |
| Electronics | Could you get help choosing? | Were repair services offered? | How long did you wait? |
| Cell phone store | How long did you wait? | Were the instructions easy to follow? | Were repair services offered? |
| Home goods | How much room was there to browse? | Was there somewhere to load or unload items? | Was gift wrapping offered? |
| Home improvement | Could you get help choosing? | Was there somewhere to load or unload items? | How did collection work? |
| Hardware | Could you get help choosing? | Were repair services offered? | Was there somewhere to load or unload items? |
| Building materials | Was there somewhere to load or unload items? | How did collection work? | Were prices clear before you paid? |
| Furniture | How much room was there to browse? | Was there somewhere to load or unload items? | How did collection work? |
| Garden center | How much room was there to browse? | Could you get help choosing? | Was there somewhere to load or unload items? |
| Pet store | Could you get help choosing? | How much room was there to browse? | Where were pet dogs allowed? |
| Auto parts | Could you get help choosing? | How did collection work? | Were repair services offered? |
| Thrift store | How much room was there to browse? | Could you try things on? | How could you pay? |
| Discount supermarket | How long did you wait? | How could you pay? | Were prices clear before you paid? |
| Cosmetics | Could you get help choosing? | Could you try a tester or take a sample? | Were prices clear before you paid? |

### Wellness & Fitness

49 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Gym | Could a visitor train here? | What was the equipment focus? | What changing facilities were there? |
| Fitness center | Could a visitor train here? | What was the equipment focus? | What changing facilities were there? |
| Yoga studio | How did the class move? | How was equipment provided? | How many people trained together? |
| Pilates studio | What Pilates equipment did the session use? | How were first-timers introduced to the session? | How many people trained together? |
| CrossFit gym | Were scaled versions of the workout explained? | How was training structured? | Could a visitor train here? |
| Functional fitness studio | How was the session organized? | How was technique feedback offered? | How many people trained together? |
| Wellness studio | How many people trained together? | How was equipment provided? | How was changing arranged? |
| Wellness center | How did you arrange this visit? | How was changing arranged? | Was there a step-free way in? |
| Sports club | Could a visitor train here? | How did you get time on a court? | What changing facilities were there? |
| Sports complex | How did you get time on a court? | What changing facilities were there? | Could you get practical visitor information? |
| Sports coaching | How was technique feedback offered? | How were lessons arranged? | How was equipment provided? |
| Sports school | How were lessons arranged? | What introduction was offered to first-timers? | How was equipment provided? |
| Athletic field | What was the playing surface? | Was the activity area lit for evening use? | What bathroom access did you find? |
| Swimming pool | How was swimming organized? | Was the pool indoors or outdoors? | What changing facilities were there? |
| Tennis court | What was the court surface? | How did you get time on a court? | Were court lights available? |
| Golf course | What kind of golf could you play? | Could you hire clubs? | How did you arrange this visit? |
| Indoor golf | What was the indoor-golf setup? | Could you hire clubs? | How did you arrange this visit? |
| Ice skating rink | How did public skating work? | How was equipment provided? | Where could you put belongings for the activity? |
| Volleyball court | What surface did you play on? | Was a net ready to use? | How did you get time on a court? |
| Soccer field | What was the playing surface? | Were goals already set up? | Was the activity area lit for evening use? |
| Basketball court | What court setup was available? | How did you get time on a court? | Were court lights available? |
| Pickleball court | How was the pickleball court set up? | How did you get time on a court? | Were court lights available? |
| Spa | How did you arrange this visit? | How was changing arranged? | What heat facilities were available? |
| Massage | Could you choose the massage style or pressure? | How private was the appointment space? | How did you arrange this visit? |
| Massage spa | Could you choose the massage style or pressure? | How was changing arranged? | How did you arrange this visit? |
| Sauna | What heat facilities were available? | How was changing arranged? | How did you arrange this visit? |
| Chiropractor | How did you arrange this visit? | Were preparation instructions clear? | How private was the appointment space? |
| Dentist | How did you arrange this visit? | Were preparation instructions clear? | Was there a step-free way in? |
| Dental clinic | How did you arrange this visit? | Were preparation instructions clear? | Was there a step-free way in? |
| Optometrist | Could you try eyewear at the same place? | How did you arrange this visit? | Was there a step-free way in? |
| Ophthalmologist | How did you arrange this visit? | Were preparation instructions clear? | Was there a step-free way in? |
| Eye care center | Could you try eyewear at the same place? | How did you arrange this visit? | How long did you wait? |
| Doctor | How did you arrange this visit? | How private was the appointment space? | Was there a step-free way in? |
| Dermatologist | How did you arrange this visit? | How private was the appointment space? | Was there a step-free way in? |
| Pediatrician | How long did you wait? | Was a baby-changing table available? | Was there a step-free way in? |
| Urgent care | How long did you wait? | How did you arrange this visit? | How was parking on arrival? |
| Medical clinic | How did you arrange this visit? | How long did you wait? | Was there a step-free way in? |
| Medical center | Could you get practical visitor information? | How was parking on arrival? | Was there a step-free way in? |
| Hospital | Could you get practical visitor information? | How was parking on arrival? | What bathroom access did you find? |
| Medical lab | How were tests scheduled? | Were preparation instructions clear? | How long did you wait? |
| Pharmacy | How did collecting a prescription work? | How long did you wait? | Was there a step-free way in? |
| Drugstore | How did collecting a prescription work? | How long did you wait? | Was there a step-free way in? |
| Physiotherapist | Was there space for guided exercises? | How private was the appointment space? | Was there a step-free way in? |
| Physical therapy | Was there space for guided exercises? | How private was the appointment space? | Was there a step-free way in? |
| Foot care | How did you arrange this visit? | How private was the appointment space? | Was there a step-free way in? |
| Podiatrist | How did you arrange this visit? | How private was the appointment space? | Was there a step-free way in? |
| Veterinary care | How were animals separated while waiting? | How did you arrange this visit? | How was parking on arrival? |
| Mental health/therapy | How private was the appointment space? | How did you arrange this visit? | Was there a step-free way in? |
| Retreat | How structured was the day? | How clearly were ingredients or dietary options labeled? | Was there a step-free way in? |

### Stays

18 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Hotel | How quiet was your room when you rested? | Was luggage storage available? | Could you adjust your room temperature? |
| Resort | How quiet was your room when you rested? | How did breakfast work? | Was there a step-free way in? |
| Motel | How quiet was your room when you rested? | Where could you park? | Could you adjust your room temperature? |
| Hostel | What space did you stay in? | Were lockers available? | What cooking facilities could you use? |
| Inn | How quiet was your room when you rested? | How did breakfast work? | How did you get in when you arrived? |
| Bed & breakfast | How did breakfast work? | What space did you stay in? | How did you get in when you arrived? |
| Guest house | What space did you stay in? | How did breakfast work? | How quiet was your room when you rested? |
| Private guest room | What space did you stay in? | What cooking facilities could you use? | How did you get in when you arrived? |
| Airbnb | What cooking facilities could you use? | How did you get in when you arrived? | How quiet was your room when you rested? |
| Vrbo | What cooking facilities could you use? | How did you get in when you arrived? | How quiet was your room when you rested? |
| Extended stay | What cooking facilities could you use? | Was laundry available? | Was there a useful surface to work at? |
| Cottage | What cooking facilities could you use? | Could you adjust your room temperature? | Where could you park? |
| Cabin | Could you adjust your room temperature? | What cooking facilities could you use? | Could you refill water here? |
| Campground | How did you secure your campsite? | What toilet facilities were there? | How level was your pitch? |
| RV park | What hookups were offered? | What toilet facilities were there? | How did you secure your campsite? |
| Farm-stay | What space did you stay in? | What cooking facilities could you use? | Where were pet dogs allowed? |
| Japanese inn | What space did you stay in? | How did breakfast work? | What changing space was available? |
| Mobile home park | Was laundry available? | Where could you park? | What space did you stay in? |

### Services & Errands

49 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Bank | How long did you wait? | How did you arrange the visit? | Was there a step-free way in? |
| ATM | Could you withdraw cash? | Was any withdrawal fee clear before confirmation? | Was there a step-free way in? |
| Accounting | How did you arrange the visit? | Was the cost explained before work began? | Where did the service happen? |
| Insurance | Were the instructions easy to follow? | How did you contact or book with them? | Was the cost explained before work began? |
| Real estate | How did you arrange the visit? | How did you contact or book with them? | Where did the service happen? |
| Lawyer | How did you arrange the visit? | Was the cost explained before work began? | Was there a place to wait? |
| Consultant | How did you arrange the visit? | Was the cost explained before work began? | How did you contact or book with them? |
| Marketing consultant | Was the cost explained before work began? | How did you contact or book with them? | Where did the service happen? |
| Employment agency | How did you arrange the visit? | How long did you wait? | How did visitor entry work? |
| Nonprofit | How did visitor entry work? | How did you contact or book with them? | Was there a step-free way in? |
| Association | How did visitor entry work? | How did you contact or book with them? | Was it easy to find the right entrance or area? |
| Florist | Could you get help choosing? | How did collection work? | Was gift wrapping offered? |
| Catering | Was the cost explained before work began? | How did collection work? | How did you contact or book with them? |
| Food delivery | How did you contact or book with them? | Were prices clear before you paid? | Were the instructions easy to follow? |
| Child care | How did visitor entry work? | How did you arrange the visit? | Was it easy to find the right entrance or area? |
| Summer camp | How did you arrange the visit? | Were visiting rules clearly explained? | How did drop-off work? |
| Laundry | Was it self-service or staffed? | Were machines available when you arrived? | How could you pay? |
| Tailor | Could you try things on? | When was the work ready? | Was the cost explained before work began? |
| Courier | How did drop-off work? | How long did you wait? | How could you pay? |
| Shipping | How did drop-off work? | Were the supplies you needed provided? | How long did you wait? |
| Storage | How did visitor entry work? | Was there somewhere to load or unload items? | Where could you park? |
| Moving | Was the cost explained before work began? | Did the service happen at the arranged time? | How did you contact or book with them? |
| Electrician | Was the cost explained before work began? | How did you contact or book with them? | Did the service happen at the arranged time? |
| Plumber | Was the cost explained before work began? | How did you contact or book with them? | Did the service happen at the arranged time? |
| Locksmith | When was the work ready? | Was the cost explained before work began? | How did you contact or book with them? |
| Painter | Was the cost explained before work began? | How did you contact or book with them? | Did the service happen at the arranged time? |
| Roofing contractor | Was the cost explained before work began? | Did the service happen at the arranged time? | Where did the service happen? |
| General contractor | Was the cost explained before work began? | How did you arrange the visit? | Did the service happen at the arranged time? |
| Pet care | How did you arrange the visit? | How did drop-off work? | Was the cost explained before work began? |
| Pet boarding | How did you arrange this visit? | How did drop-off work? | Were visiting rules clearly explained? |
| Funeral home | How did visitor entry work? | Was there a place to wait? | Was there a step-free way in? |
| Cemetery | Was it easy to find the right entrance or area? | Could you sit down without buying anything? | How much shade did you find? |
| Astrologer | How did you arrange the visit? | Were prices clear before you paid? | Where did the service happen? |
| Psychic | How did you arrange the visit? | Were prices clear before you paid? | Was there a place to wait? |
| Tour agency | How did you arrange this visit? | Were the instructions easy to follow? | How did you contact or book with them? |
| Travel agency | How did you arrange the visit? | Could you get help choosing? | Were prices clear before you paid? |
| Tourist information | Were visiting rules clearly explained? | Could you get help choosing? | How long did you wait? |
| Chauffeur | How did you arrange this visit? | How did you contact or book with them? | Were prices clear before you paid? |
| Aircraft rental | How did you arrange this visit? | Were visiting rules clearly explained? | Were prices clear before you paid? |
| Telecommunications | How long did you wait? | How did you arrange the visit? | Where did the service happen? |
| Beauty service | How did you arrange the visit? | Were prices clear before you paid? | Was there a step-free way in? |
| Skin care clinic | How did you arrange the visit? | Were the instructions easy to follow? | Was there a place to wait? |
| Tanning studio | How did you arrange the visit? | What changing space was available? | Were prices clear before you paid? |
| Hair salon | How did you arrange the visit? | How long did you wait? | How could you pay? |
| Barber | How long did you wait? | How did you arrange the visit? | Were prices clear before you paid? |
| Nail salon | How did you arrange the visit? | How long did you wait? | How could you pay? |
| Makeup artist | How did you arrange the visit? | Where did the service happen? | Were the supplies you needed provided? |
| Body art | How did you arrange the visit? | Were prices clear before you paid? | Were visiting rules clearly explained? |
| Tattoo/piercing | How did you arrange the visit? | Was the cost explained before work began? | Were visiting rules clearly explained? |

### Travel & Transit

38 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Airport | Was it easy to find the right entrance or area? | Where was the area you used? | Was luggage storage available? |
| International airport | Where was the area you used? | Could you charge a phone? | Were showers available? |
| Airstrip | How did visitor entry work? | Was there a place to wait? | Where could you park? |
| Heliport | How did visitor entry work? | What was your route to boarding like? | Was there a place to wait? |
| Train station | Was it easy to find the right entrance or area? | What was your route to boarding like? | What bathroom access did you find? |
| Subway station | What was your route to boarding like? | Was it easy to find the right entrance or area? | Where was the area you used? |
| Light rail | What was your route to boarding like? | Was there shelter while you waited? | Were the instructions easy to follow? |
| Tram stop | Was there shelter while you waited? | What was your route to boarding like? | Somewhere to sit? |
| Bus stop | Was there shelter while you waited? | Somewhere to sit? | Were the instructions easy to follow? |
| Bus station | Was there a place to wait? | What bathroom access did you find? | Was it easy to find the right entrance or area? |
| Ferry terminal | What was your route to boarding like? | Was there shelter while you waited? | Was there a place to wait? |
| Ferry service | What was your route to boarding like? | Somewhere to sit? | What bathroom access did you find? |
| Transit station | Was it easy to find the right entrance or area? | What bathroom access did you find? | Where was the area you used? |
| Transit stop | Was there shelter while you waited? | Somewhere to sit? | Was it easy to find the right entrance or area? |
| Transit depot | How did visitor entry work? | Was it easy to find the right entrance or area? | Was there a place to wait? |
| Taxi stand | Was there shelter while you waited? | How long did you wait? | How could you pay? |
| Taxi service | How did you contact or book with them? | How long did you wait? | How could you pay? |
| Bike share station | How did collecting a bike work? | Were the instructions easy to follow? | Was there a bike available when you arrived? |
| Parking | How could you pay? | What was the parking surface like? | Was there a step-free way in? |
| Parking lot | How could you pay? | What was the parking surface like? | Was it easy to find the right entrance or area? |
| Parking garage | How could you pay? | Was there a step-free way in? | Was it easy to find the right entrance or area? |
| Park & ride | How could you pay? | Was there shelter while you waited? | What was your route to boarding like? |
| Gas station | How could you pay? | What bathroom access did you find? | Was there an air pump for tires? |
| EV charging | Could you start charging? | What did you need to start charging? | Was there a place to wait? |
| E-bike charging | Could you start charging? | What did you need to start charging? | Was there shelter while you waited? |
| Rest stop | What bathroom access did you find? | Could you sit down without buying anything? | Could you refill water here? |
| Truck stop | Were showers available? | What bathroom access did you find? | Where could you park? |
| Toll station | How could you pay? | Were the instructions easy to follow? | How long did you wait? |
| Bridge | What was the part you walked like? | How was walking space separated from vehicles? | How much shade did you find? |
| Car dealer | How did you arrange the visit? | Could you get help choosing? | Where could you park? |
| Car rental | How long did you wait? | How did collection work? | Were prices clear before you paid? |
| Car repair | How did you arrange the visit? | Was the cost explained before work began? | When was the work ready? |
| Car wash | Was it self-service or staffed? | How long did you wait? | How could you pay? |
| Tire shop | How long did you wait? | Was the cost explained before work began? | When was the work ready? |
| Truck dealer | How did you arrange the visit? | Where could you park? | Could you get help choosing? |
| Transportation service | How did you arrange this visit? | How did you contact or book with them? | How long did you wait? |
| Dump station | How could you pay? | Were the instructions easy to follow? | Were the supplies you needed provided? |
| RV water refill | Could you refill water here? | How could you pay? | Were the instructions easy to follow? |

### Work & Education

17 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Co-working space | Could you use it for a single day or session? | Could you find a quiet place to concentrate? | Could you plug in? |
| Business center | Could you use it for a single day or session? | Could you use a separate study or meeting room? | How did the Wi-Fi work? |
| Corporate office | How did visitor entry work? | Was it easy to find the right entrance or area? | Was there a place to wait? |
| Manufacturer | How did visitor entry work? | How did you arrange the visit? | Where could you park? |
| Supplier | How did visitor entry work? | How did collection work? | Was there somewhere to load or unload items? |
| Farm | How did visitor entry work? | What was the part you walked like? | Where could you park? |
| Ranch | Were visiting rules clearly explained? | What was the part you walked like? | Where could you park? |
| Television studio | How did visitor entry work? | What happened with bags on entry? | Were visiting rules clearly explained? |
| Library | Could you find a quiet place to concentrate? | Could you use a separate study or meeting room? | Could visitors print documents? |
| University | Was it easy to find the right entrance or area? | How did visitor entry work? | Could you sit down without buying anything? |
| School | How did visitor entry work? | Was it easy to find the right entrance or area? | How did you arrange the visit? |
| Preschool | How did visitor entry work? | How did you arrange the visit? | Was there a place to wait? |
| Primary school | How did visitor entry work? | How did you arrange the visit? | Was there a step-free way in? |
| Secondary school | How did visitor entry work? | How did you arrange the visit? | Was it easy to find the right entrance or area? |
| Academic department | Was it easy to find the right entrance or area? | How did visitor entry work? | Was there a step-free way in? |
| Educational institution | How did visitor entry work? | Was there a step-free way in? | Was it easy to find the right entrance or area? |
| Research institute | How did visitor entry work? | How did you arrange the visit? | What happened with bags on entry? |

### Civic & Faith

16 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| City hall | How did visitor entry work? | Was it easy to find the right entrance or area? | Was there a step-free way in? |
| Government office | How did you arrange the visit? | How long did you wait? | Was it easy to find the right entrance or area? |
| Local government office | How did you arrange the visit? | How long did you wait? | Was there a step-free way in? |
| Courthouse | What happened with bags on entry? | Was it easy to find the right entrance or area? | Was there a place to wait? |
| Embassy | How did you arrange the visit? | What happened with bags on entry? | Was there a place to wait? |
| Post office | How long did you wait? | How did drop-off work? | Were the supplies you needed provided? |
| Police | How did visitor entry work? | Was it easy to find the right entrance or area? | Was there a place to wait? |
| Neighborhood police station | How did visitor entry work? | Was there a place to wait? | Was there a step-free way in? |
| Fire station | How did visitor entry work? | Were visiting rules clearly explained? | Was it easy to find the right entrance or area? |
| Church | Were visiting rules clearly explained? | Was there a step-free way in? | Somewhere to sit? |
| Mosque | Were visiting rules clearly explained? | Was there a step-free way in? | Somewhere to sit? |
| Synagogue | How did visitor entry work? | Were visiting rules clearly explained? | Was there a step-free way in? |
| Hindu temple | Were visiting rules clearly explained? | What did posted rules or staff say about photos? | Was there a step-free way in? |
| Buddhist temple | Were visiting rules clearly explained? | What did posted rules or staff say about photos? | Somewhere to sit? |
| Shinto shrine | Were visiting rules clearly explained? | What was the part you walked like? | What did posted rules or staff say about photos? |
| Place of worship | Were visiting rules clearly explained? | How did visitor entry work? | Was there a step-free way in? |

### Areas & Addresses

15 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Apartment building | Was it easy to find the right entrance or area? | Was there a step-free way in? | Where could you park? |
| Apartment complex | Was it easy to find the right entrance or area? | Where could you park? | What was the part you walked like? |
| Condominium complex | Was it easy to find the right entrance or area? | Was there a step-free way in? | What was the part you walked like? |
| Housing complex | Was it easy to find the right entrance or area? | What was the part you walked like? | Could you sit down without buying anything? |
| Neighborhood | How did you get around the part you explored? | Could you sit down without buying anything? | How much shade did you find? |
| Locality/city | How did you get around the part you explored? | What stood out in the part you explored? | How much time did you spend exploring? |
| Postal area | How did you get around the part you explored? | Was it easy to find the right entrance or area? | How much time did you spend exploring? |
| Town | How did you get around the part you explored? | What stood out in the part you explored? | Could you sit down without buying anything? |
| Region | How did you get around the part you explored? | How much time did you spend exploring? | What stood out in the part you explored? |
| Country | What stood out in the part you explored? | How did you get around the part you explored? | How much time did you spend exploring? |
| Route/street | What was the part you walked like? | Could you sit down without buying anything? | How much shade did you find? |
| Address | Was it easy to find the right entrance or area? | Was there a step-free way in? | What was the part you walked like? |
| Intersection | How did you cross here? | What was the part you walked like? | Was it easy to find the right entrance or area? |
| Landmark | Was it easy to find the right entrance or area? | Could you sit down without buying anything? | How much time did you spend exploring? |
| Plus code | Was it easy to find the right entrance or area? | How did you get around the part you explored? | What was the part you walked like? |

### Facilities & Other

7 selectable subcategories.

| Subcategory | Question 1 | Question 2 | Question 3 |
| --- | --- | --- | --- |
| Public bathroom | Was there a charge to use the toilet? | Was there a place to wash your hands? | Was there a step-free way in? |
| Public bath | What changing space was available? | Were lockers available? | Were showers available? |
| Restroom | Was there a charge to use the toilet? | Was there a place to wash your hands? | Was a baby-changing table available? |
| Stable | How did you arrange this visit? | Could you borrow or hire riding equipment? | Were visiting rules clearly explained? |
| Generic establishment | How did visitor entry work? | Was there a step-free way in? | How could you pay? |
| Point of interest | Was it easy to find the right entrance or area? | Somewhere to sit? | How much time did you spend exploring? |
| Unknown | Was it easy to find the right entrance or area? | How did visitor entry work? | Was there a step-free way in? |
