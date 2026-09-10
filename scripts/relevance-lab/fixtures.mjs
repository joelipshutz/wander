const place = (
  id,
  name,
  category,
  neighborhood,
  description,
  {
    subcategory = "",
    tags = [],
    owner = "Community",
    relationship = "community",
    status = "been",
    rating = 4,
    visits = 1,
    communityRating = 4,
    communitySupport = 3,
    distanceKm = 3,
    freshnessDays = 30,
    price = 2,
    openTonight = true,
    vegetarianFriendly = false,
    groupFriendly = false,
    childFriendly = false,
  } = {},
) => ({
  id,
  name,
  category,
  subcategory,
  neighborhood,
  city: "New York",
  description,
  tags,
  owner,
  relationship,
  status,
  rating,
  visits,
  communityRating,
  communitySupport,
  distanceKm,
  freshnessDays,
  price,
  openTonight,
  vegetarianFriendly,
  groupFriendly,
  childFriendly,
});

// Entirely fictional records. They are deliberately small enough to inspect by
// hand while still exposing lexical, social, community, and semantic behavior.
export const places = [
  place("p01", "Juniper Desk", "coffee", "Williamsburg", "Calm espresso bar with long communal tables, outlets, and patient staff.", { tags: ["laptop", "quiet", "wifi"], owner: "Maya", relationship: "mutual", rating: 5, visits: 8, communityRating: 4.5, communitySupport: 18, distanceKm: 1.1 }),
  place("p02", "North Star Coffee", "coffee", "Williamsburg", "Bright neighborhood coffee counter known for citrusy pour-over and fast service.", { tags: ["pour over", "standing room"], owner: "Joe", relationship: "following", rating: 5, visits: 6, communityRating: 4.7, communitySupport: 35, distanceKm: 0.9 }),
  place("p03", "Paper Moon Cafe", "coffee", "Greenpoint", "Book-lined rooms, soft lamps, deep chairs, and pots of tea built for an unhurried afternoon.", { tags: ["cozy", "books", "tea"], owner: "Lena", relationship: "mutual", rating: 5, visits: 4, communityRating: 4.6, communitySupport: 14, distanceKm: 2.3 }),
  place("p04", "Signal Roasters", "coffee", "SoHo", "Minimal espresso lab with exceptional beans but few seats and no outlets.", { tags: ["espresso", "quick"], owner: "Community", communityRating: 4.8, communitySupport: 54, distanceKm: 4.8 }),
  place("p05", "Garden Cup", "coffee", "Park Slope", "Roomy cafe beside a small play garden, with high chairs and weekend breakfast plates.", { tags: ["brunch", "stroller", "patio"], owner: "Ana", relationship: "following", childFriendly: true, groupFriendly: true, communityRating: 4.4, communitySupport: 21, distanceKm: 5.2 }),
  place("p06", "Ember Window", "coffee", "East Village", "Tiny late-night coffee window serving strong espresso and sesame cookies.", { tags: ["late night", "dessert"], owner: "Joe", relationship: "following", rating: 4, visits: 3, communityRating: 4.1, communitySupport: 11, distanceKm: 3.4 }),

  place("p07", "Candle & Vine", "restaurant", "West Village", "Intimate candlelit dining room with shareable seasonal plates and gracious pacing.", { subcategory: "new american", tags: ["romantic", "date night", "wine"], owner: "Maya", relationship: "mutual", rating: 5, visits: 3, communityRating: 4.7, communitySupport: 29, distanceKm: 4.1, price: 3 }),
  place("p08", "Little Hearth", "restaurant", "West Village", "Warm corner restaurant for handmade pasta, low lighting, and quiet conversation.", { subcategory: "italian", tags: ["cozy", "pasta", "date night"], owner: "Joe", relationship: "following", rating: 5, visits: 5, communityRating: 4.5, communitySupport: 22, distanceKm: 4.3, price: 2 }),
  place("p09", "Marble Room", "restaurant", "West Village", "Polished tasting-menu room with formal service and a high fixed price.", { subcategory: "fine dining", tags: ["special occasion", "tasting menu"], communityRating: 4.8, communitySupport: 44, distanceKm: 4.5, price: 4 }),
  place("p10", "Orchard Table", "restaurant", "Lower East Side", "Lively vegetable-forward dining with big tables and dishes designed to share.", { subcategory: "mediterranean", tags: ["groups", "vegetarian", "sharing"], owner: "Nico", relationship: "mutual", rating: 5, visits: 4, vegetarianFriendly: true, groupFriendly: true, communityRating: 4.6, communitySupport: 26, distanceKm: 3.9, price: 2 }),
  place("p11", "Common Ground", "restaurant", "Flatiron", "Spacious all-day restaurant with flexible plates for mixed diets and groups.", { subcategory: "new american", tags: ["groups", "vegetarian", "reservations"], vegetarianFriendly: true, groupFriendly: true, communityRating: 4.3, communitySupport: 31, distanceKm: 5.1, price: 2 }),
  place("p12", "Copper Lantern", "restaurant", "East Village", "Noisy tavern with burgers, pitchers, and booths for a crowd.", { subcategory: "american", tags: ["groups", "burgers", "loud"], groupFriendly: true, communityRating: 4.2, communitySupport: 42, distanceKm: 3.1, price: 2 }),

  place("p13", "Midnight Crane", "restaurant", "East Village", "Steaming bowls of hand-pulled noodles served until 2 a.m.", { subcategory: "noodles", tags: ["late night", "spicy", "hand pulled"], owner: "Sam", relationship: "following", rating: 5, visits: 7, communityRating: 4.6, communitySupport: 38, distanceKm: 3.2, price: 1 }),
  place("p14", "Red Bowl", "restaurant", "East Village", "Compact counter for numbing chili noodles and dumplings after midnight.", { subcategory: "noodles", tags: ["late night", "dumplings", "spicy"], communityRating: 4.5, communitySupport: 47, distanceKm: 3, price: 1 }),
  place("p15", "Golden Broth", "restaurant", "Chinatown", "Slow-cooked noodle soups with a short menu and early closing time.", { subcategory: "noodles", tags: ["soup", "quiet"], owner: "Maya", relationship: "mutual", rating: 5, visits: 2, communityRating: 4.7, communitySupport: 19, distanceKm: 4.4, price: 1, openTonight: false }),
  place("p16", "Night Market Wok", "restaurant", "Lower East Side", "Fast wok noodles, neon lights, and counter seats open very late.", { subcategory: "noodles", tags: ["late night", "fast", "neon"], communityRating: 4.1, communitySupport: 63, distanceKm: 3.8, price: 1 }),

  place("p17", "Roof Fern", "bar", "Greenpoint", "Leafy roof deck with spritzes, skyline views, and relaxed daytime tables.", { subcategory: "cocktail bar", tags: ["outdoor", "rooftop", "sunny", "spritz"], owner: "Lena", relationship: "mutual", rating: 5, visits: 4, communityRating: 4.5, communitySupport: 25, distanceKm: 2.8, price: 2 }),
  place("p18", "Canal Patio", "bar", "SoHo", "Hidden courtyard bar for natural wine and small plates in the afternoon.", { subcategory: "wine bar", tags: ["outdoor", "patio", "daytime"], owner: "Joe", relationship: "following", rating: 4, visits: 3, communityRating: 4.4, communitySupport: 18, distanceKm: 4.5, price: 3 }),
  place("p19", "Highline Social", "bar", "Chelsea", "Large rooftop lounge with DJs, bottle service, and panoramic views.", { subcategory: "rooftop bar", tags: ["outdoor", "party", "views"], communityRating: 4.2, communitySupport: 88, distanceKm: 6.2, price: 4 }),
  place("p20", "Pocket Garden", "bar", "East Village", "Small backyard wine bar shaded by vines, good for an easy first drink.", { subcategory: "wine bar", tags: ["outdoor", "backyard", "date"], owner: "Maya", relationship: "mutual", rating: 5, visits: 5, communityRating: 4.3, communitySupport: 17, distanceKm: 3.2, price: 2 }),

  place("p21", "Flour Thief", "bakery", "Bedford-Stuyvesant", "Unmarked side-street bake shop with laminated cardamom buns that sell out early.", { tags: ["hidden gem", "pastry", "cardamom"], owner: "Nico", relationship: "mutual", rating: 5, visits: 6, communityRating: 4.8, communitySupport: 16, distanceKm: 4.8, price: 1 }),
  place("p22", "Daily Crumb", "bakery", "Williamsburg", "Popular all-day bakery with croissants, sandwiches, and a constant line.", { tags: ["croissant", "popular", "sandwich"], communityRating: 4.5, communitySupport: 91, distanceKm: 1.3, price: 2 }),
  place("p23", "Blue Apron Bakes", "bakery", "Park Slope", "Family bakery with excellent sourdough, cookies, and plenty of stroller space.", { tags: ["bread", "cookies", "family"], owner: "Ana", relationship: "following", rating: 5, visits: 9, childFriendly: true, communityRating: 4.6, communitySupport: 36, distanceKm: 5.1, price: 1 }),
  place("p24", "Pearl Oven", "bakery", "SoHo", "Designer pastry counter specializing in photogenic glazed cakes.", { tags: ["cake", "trendy", "dessert"], communityRating: 4.1, communitySupport: 72, distanceKm: 4.7, price: 3 }),

  place("p25", "Borough Slice", "restaurant", "Williamsburg", "Charred thin-crust pies, fast counter service, and a loyal neighborhood following.", { subcategory: "pizza", tags: ["pizza", "thin crust", "casual"], communityRating: 4.8, communitySupport: 112, distanceKm: 1.5, price: 1 }),
  place("p26", "Joe's Square", "restaurant", "East Village", "Crisp square slices with pepperoni cups and late hours.", { subcategory: "pizza", tags: ["pizza", "square", "late night"], owner: "Joe", relationship: "following", rating: 5, visits: 12, communityRating: 4.6, communitySupport: 67, distanceKm: 3.2, price: 1 }),
  place("p27", "Stone & Basil", "restaurant", "Park Slope", "Wood-fired pizza restaurant with large tables and a calm back room.", { subcategory: "pizza", tags: ["pizza", "wood fired", "groups"], groupFriendly: true, childFriendly: true, communityRating: 4.5, communitySupport: 48, distanceKm: 5.3, price: 2 }),
  place("p28", "Metro Pie", "restaurant", "Times Square", "High-volume slice shop convenient to theaters and tourist crowds.", { subcategory: "pizza", tags: ["pizza", "fast", "tourist"], communityRating: 3.9, communitySupport: 140, distanceKm: 7.4, price: 2 }),

  place("p29", "Mint & Grain", "restaurant", "SoHo", "Bright lunch counter for grain bowls, crisp salads, and house-made dressings.", { subcategory: "healthy", tags: ["lunch", "salad", "grain bowl"], owner: "Maya", relationship: "mutual", rating: 5, visits: 7, vegetarianFriendly: true, communityRating: 4.5, communitySupport: 24, distanceKm: 4.6, price: 2 }),
  place("p30", "Green Hour", "restaurant", "SoHo", "Quick plant-based cafe with protein bowls and fresh juices.", { subcategory: "healthy", tags: ["lunch", "vegan", "juice"], vegetarianFriendly: true, communityRating: 4.4, communitySupport: 57, distanceKm: 4.4, price: 2 }),
  place("p31", "Deli Standard", "restaurant", "SoHo", "Classic sandwich counter with oversized portions and no meaningful meat-free menu.", { subcategory: "deli", tags: ["lunch", "sandwich"], communityRating: 4.3, communitySupport: 83, distanceKm: 4.3, price: 2 }),
  place("p32", "Quiet Current", "restaurant", "Tribeca", "Serene daytime kitchen serving seasonal vegetable plates and nourishing soups.", { subcategory: "healthy", tags: ["lunch", "vegetables", "quiet"], owner: "Lena", relationship: "mutual", rating: 5, visits: 3, vegetarianFriendly: true, communityRating: 4.6, communitySupport: 20, distanceKm: 5.3, price: 3 }),

  place("p33", "Sora Counter", "restaurant", "East Village", "Twelve-seat chef's counter for a meticulous seasonal sushi progression.", { subcategory: "omakase", tags: ["special occasion", "sushi", "chef counter"], owner: "Joe", relationship: "following", rating: 5, visits: 2, communityRating: 4.9, communitySupport: 31, distanceKm: 3.3, price: 4 }),
  place("p34", "Kite Sushi", "restaurant", "SoHo", "Casual hand-roll bar with quick service and moderate prices.", { subcategory: "sushi", tags: ["hand rolls", "casual"], communityRating: 4.4, communitySupport: 52, distanceKm: 4.7, price: 2 }),
  place("p35", "Moon Gate", "restaurant", "Lower East Side", "Modern Japanese tasting experience with dramatic plating and sake pairings.", { subcategory: "omakase", tags: ["special occasion", "tasting menu", "sake"], communityRating: 4.7, communitySupport: 46, distanceKm: 3.8, price: 4 }),
  place("p36", "Harbor Sushi", "restaurant", "Financial District", "Reliable business-lunch sushi with many tables and efficient service.", { subcategory: "sushi", tags: ["lunch", "business"], communityRating: 4.2, communitySupport: 39, distanceKm: 7.1, price: 3 }),

  place("p37", "Sunday Seed", "restaurant", "Park Slope", "Cheerful brunch room with pancakes, crayons, high chairs, and forgiving acoustics.", { subcategory: "brunch", tags: ["brunch", "family", "pancakes"], owner: "Ana", relationship: "following", rating: 5, visits: 8, childFriendly: true, groupFriendly: true, communityRating: 4.5, communitySupport: 33, distanceKm: 5.2, price: 2 }),
  place("p38", "Bramble Brunch", "restaurant", "Park Slope", "Garden brunch restaurant with stroller parking and a broad children's menu.", { subcategory: "brunch", tags: ["brunch", "garden", "family"], childFriendly: true, groupFriendly: true, communityRating: 4.6, communitySupport: 45, distanceKm: 5.5, price: 2 }),
  place("p39", "Egg Assembly", "restaurant", "Williamsburg", "Trendy counter-service breakfast sandwiches with limited seating.", { subcategory: "brunch", tags: ["breakfast", "sandwich", "quick"], communityRating: 4.5, communitySupport: 79, distanceKm: 1.2, price: 2 }),
  place("p40", "Grand Mimosa", "restaurant", "Park Slope", "Bustling boozy brunch dining room with loud music and tightly packed tables.", { subcategory: "brunch", tags: ["brunch", "boozy", "loud"], communityRating: 4.2, communitySupport: 61, distanceKm: 5.4, price: 3 }),
];

const query = (id, text, intent, relevant, plan = {}) => ({
  id,
  text,
  intent,
  relevant,
  plan: {
    lexicalQuery: text,
    categories: [],
    neighborhoods: [],
    owner: null,
    maxPrice: null,
    openTonight: false,
    vegetarianFriendly: false,
    groupFriendly: false,
    childFriendly: false,
    personalization: 0.25,
    community: 0.25,
    ...plan,
  },
});

// Relevance grades: 3 = ideal, 2 = strong, 1 = acceptable. These judgments
// are fixed before running a model so the scorecard cannot move to fit results.
export const queries = [
  query("q01", "coffee shops", "lexical", { p02: 3, p01: 3, p03: 2, p04: 2, p05: 1, p06: 1 }, { categories: ["coffee"], lexicalQuery: "coffee" }),
  query("q02", "cool coffee shops based on what I like", "personal", { p01: 3, p03: 3, p02: 2, p06: 1 }, { categories: ["coffee"], lexicalQuery: "coffee", personalization: 0.8, community: 0.1 }),
  query("q03", "Joe's favorite coffee shops", "named-person", { p02: 3, p06: 3 }, { categories: ["coffee"], owner: "Joe", lexicalQuery: "coffee", personalization: 1, community: 0 }),
  query("q04", "quiet place to work on my laptop in Williamsburg", "semantic", { p01: 3, p02: 1 }, { categories: ["coffee"], neighborhoods: ["Williamsburg"], lexicalQuery: "quiet laptop" }),
  query("q05", "romantic dinner tonight in the West Village", "constraint", { p07: 3, p08: 3, p09: 1 }, { categories: ["restaurant"], neighborhoods: ["West Village"], lexicalQuery: "romantic dinner", openTonight: true, personalization: 0.4 }),
  query("q06", "late night noodles near the East Village", "constraint", { p13: 3, p14: 3, p16: 1 }, { categories: ["restaurant"], neighborhoods: ["East Village"], lexicalQuery: "late night noodles", openTonight: true }),
  query("q07", "group dinner where vegetarians won't be an afterthought", "semantic", { p10: 3, p11: 3 }, { categories: ["restaurant"], lexicalQuery: "group vegetarian", vegetarianFriendly: true, groupFriendly: true, personalization: 0.35 }),
  query("q08", "outdoor drinks for a sunny afternoon", "semantic", { p17: 3, p18: 3, p20: 2, p19: 1 }, { categories: ["bar"], lexicalQuery: "outdoor sunny", personalization: 0.35 }),
  query("q09", "an underrated bakery worth crossing town for", "semantic", { p21: 3, p23: 2 }, { categories: ["bakery"], lexicalQuery: "underrated bakery", personalization: 0.45, community: 0.15 }),
  query("q10", "the community's goated pizza spot", "community", { p25: 3, p26: 2, p27: 1 }, { categories: ["restaurant"], lexicalQuery: "pizza", personalization: 0.05, community: 0.9 }),
  query("q11", "cozy date night that isn't wildly expensive", "semantic", { p08: 3, p20: 2, p07: 1 }, { categories: ["restaurant", "bar"], lexicalQuery: "cozy date night", maxPrice: 2, personalization: 0.45 }),
  query("q12", "healthy lunch near SoHo", "constraint", { p29: 3, p30: 3, p31: 1 }, { categories: ["restaurant"], neighborhoods: ["SoHo"], lexicalQuery: "healthy lunch" }),
  query("q13", "special occasion omakase", "lexical", { p33: 3, p35: 3 }, { categories: ["restaurant"], lexicalQuery: "special occasion omakase", community: 0.4 }),
  query("q14", "kid friendly brunch in Park Slope", "constraint", { p37: 3, p38: 3 }, { categories: ["restaurant"], neighborhoods: ["Park Slope"], lexicalQuery: "kid friendly brunch", childFriendly: true }),
  query("q15", "a cozy bookish cafe for a rainy afternoon", "semantic", { p03: 3, p01: 1 }, { categories: ["coffee"], lexicalQuery: "bookish rainy cafe", personalization: 0.45 }),
];

// A compact, inspectable stand-in for behavioral personalization. The evaluator
// intentionally does not learn a people embedding from synthetic data.
export const viewerProfile = {
  preferredTags: ["books", "cozy", "hidden gem", "laptop", "outdoor", "quiet", "vegetarian"],
  avoidedTags: ["loud", "party", "tourist"],
  preferredNeighborhoods: ["Williamsburg", "Greenpoint", "West Village", "East Village"],
};

export const fixtureVersion = "2026-08-14-v1";
