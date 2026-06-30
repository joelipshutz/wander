// Mirrors shared/place-taxonomy.json. Keep changes in sync with the Swift tests.
export const allowedPlaceCategories = [
  "food_drink",
  "outdoors_nature",
  "arts_culture_faith",
  "entertainment",
  "health_wellness",
  "sports_fitness",
  "shopping",
  "services",
  "lodging",
  "transportation_transit",
  "education",
  "work_venues",
  "home_neighborhood",
  "public_services",
  "place",
] as const;

export type PlaceCategory = typeof allowedPlaceCategories[number];

const aliasRules: Array<{ category: PlaceCategory; patterns: RegExp[] }> = [
  {
    category: "food_drink",
    patterns: [
      /\b(coffee|cafe|espresso|roaster|bakery|tea shop)\b/,
      /\b(restaurant|taqueria|ramen|sushi|pizza|diner|kitchen|grill|noodle|taco|food market|fast food|food truck|brunch)\b/,
      /\b(bar|brewery|winery|cocktail|pub|nightlife)\b/,
    ],
  },
  {
    category: "outdoors_nature",
    patterns: [
      /\b(hike|hiking|trail|trailhead|waterfall|hot spring|canyon|mountain|observatory)\b/,
      /\b(park|playground|garden|plaza|beach|lake|national park|campground|picnic area|marina)\b/,
    ],
  },
  {
    category: "arts_culture_faith",
    patterns: [
      /\b(museum|gallery|art gallery|public art|historic|landmark|monument|cultural center)\b/,
      /\b(spiritual|church|temple|shrine|mosque|synagogue|chapel|cathedral|meditation)\b/,
    ],
  },
  {
    category: "entertainment",
    patterns: [
      /\b(tourist attraction|attraction|movie|cinema|concert|music venue|arena|stadium|arcade|bowling|zoo|aquarium|amusement|theme park|comedy|escape room)\b/,
    ],
  },
  {
    category: "health_wellness",
    patterns: [
      /\b(hospital|urgent care|medical center|health center|clinic|doctor|dentist|pharmacy|drugstore)\b/,
      /\b(wellness studio|spa|massage|sauna|bathhouse|therapy|chiropractor|acupuncture|physical therapy|recovery studio)\b/,
    ],
  },
  {
    category: "sports_fitness",
    patterns: [
      /\b(gym|fitness center|training|strength|workout|climbing gym|boxing gym)\b/,
      /\b(pilates|reformer|lagree|yoga|barre|spin studio|dance studio|tennis court|basketball court|soccer field|golf course|pool|skate park|ski|surf)\b/,
    ],
  },
  {
    category: "shopping",
    patterns: [
      /\b(shop|store|retail|art supply store|mall|boutique|market|grocery|bookstore|flower shop|hardware|furniture|electronics|vintage|thrift)\b/,
    ],
  },
  {
    category: "services",
    patterns: [
      /\b(salon|barber|nail salon|laundry|dry cleaner|tailor|repair|bank|atm|post office|shipping center|car wash)\b/,
      /\b(veterinarian|veterinary|animal hospital|animal service|pet clinic|pet hospital|pet groomer)\b/,
    ],
  },
  {
    category: "lodging",
    patterns: [
      /\b(hotel|motel|resort|lodging|inn|hostel|bed and breakfast|boutique hotel|[345][ -]?star hotel|vacation rental|cabin)\b/,
    ],
  },
  {
    category: "transportation_transit",
    patterns: [
      /\b(transportation|transit|airport|train station|bus station|ferry|subway|station|parking|garage|rental car|gas station|ev charging|bike share|car share|rest stop)\b/,
    ],
  },
  {
    category: "education",
    patterns: [
      /\b(school|university|college|campus|preschool|daycare|tutor|academy|class|workshop|library|study spot)\b/,
    ],
  },
  {
    category: "work_venues",
    patterns: [
      /\b(coworking|co working|office|meeting room|conference|event space|production studio|photo studio|warehouse|convention center|business center)\b/,
    ],
  },
  {
    category: "home_neighborhood",
    patterns: [
      /\b(home|apartment|condo|house|neighborhood|block|courtyard|community garden|local spot|meetup spot|lobby)\b/,
    ],
  },
  {
    category: "public_services",
    patterns: [
      /\b(public service|government|city hall|courthouse|police|fire station|embassy|consulate|dmv|public restroom|recycling center|utility|civic building)\b/,
    ],
  },
];

export function isPlaceCategory(value: string): value is PlaceCategory {
  return (allowedPlaceCategories as readonly string[]).includes(value);
}

export function inferPlaceCategory(value: string | null | undefined): PlaceCategory {
  const normalized = normalizeCategoryText(value);
  if (!normalized) return "place";

  const byID = allowedPlaceCategories.find((category) =>
    normalizeCategoryText(category) === normalized
  );
  if (byID) return byID;

  for (const rule of aliasRules) {
    if (rule.patterns.some((pattern) => pattern.test(normalized))) {
      return rule.category;
    }
  }

  return "place";
}

export function normalizeCategoryText(value: string | null | undefined): string {
  return (value ?? "")
    .toLowerCase()
    .replace(/[_&/-]+/g, " ")
    .replace(/[^a-z0-9 ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
