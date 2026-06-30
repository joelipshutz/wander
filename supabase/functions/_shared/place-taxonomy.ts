// Mirrors shared/place-taxonomy.json. Keep changes in sync with the Swift tests.
export const allowedPlaceCategories = [
  "coffee",
  "restaurant",
  "bar",
  "hike",
  "park",
  "gym",
  "fitness studio",
  "pilates studio",
  "spiritual",
  "hospital",
  "pharmacy",
  "veterinarian",
  "hotel",
  "shop",
  "transportation",
  "place",
] as const;

export type PlaceCategory = typeof allowedPlaceCategories[number];

const aliasRules: Array<{ category: PlaceCategory; patterns: RegExp[] }> = [
  {
    category: "coffee",
    patterns: [/\b(coffee|cafe|espresso|roaster|bakery|tea shop)\b/],
  },
  {
    category: "restaurant",
    patterns: [
      /\b(restaurant|taqueria|ramen|sushi|pizza|diner|kitchen|grill|noodle|taco|food market|fast food)\b/,
    ],
  },
  {
    category: "bar",
    patterns: [/\b(bar|brewery|winery|cocktail|pub|nightlife)\b/],
  },
  {
    category: "hike",
    patterns: [/\b(hike|trail|waterfall|hot spring|canyon|mountain|observatory)\b/],
  },
  {
    category: "park",
    patterns: [/\b(park|playground|garden|plaza|beach|lake|national park)\b/],
  },
  {
    category: "gym",
    patterns: [/\b(gym|fitness center|training|strength|workout|climbing gym|boxing gym)\b/],
  },
  {
    category: "pilates studio",
    patterns: [/\b(pilates|reformer|lagree)\b/],
  },
  {
    category: "fitness studio",
    patterns: [/\b(fitness studio|yoga|barre|wellness studio|stretch studio)\b/],
  },
  {
    category: "spiritual",
    patterns: [/\b(spiritual|church|temple|shrine|mosque|synagogue|chapel|cathedral|meditation)\b/],
  },
  {
    category: "hospital",
    patterns: [/\b(hospital|urgent care|medical center|health center|clinic)\b/],
  },
  {
    category: "pharmacy",
    patterns: [/\b(pharmacy|drugstore)\b/],
  },
  {
    category: "veterinarian",
    patterns: [/\b(veterinarian|veterinary|animal hospital|animal service|pet clinic|pet hospital)\b/],
  },
  {
    category: "hotel",
    patterns: [/\b(hotel|motel|resort|lodging|boutique hotel|[345][ -]?star hotel)\b/],
  },
  {
    category: "transportation",
    patterns: [/\b(transportation|transit|airport|train station|bus station|ferry|subway|station)\b/],
  },
  {
    category: "shop",
    patterns: [/\b(shop|store|art supply store|mall|boutique|market)\b/],
  },
];

export function isPlaceCategory(value: string): value is PlaceCategory {
  return (allowedPlaceCategories as readonly string[]).includes(value);
}

export function inferPlaceCategory(value: string | null | undefined): PlaceCategory {
  const normalized = normalizeCategoryText(value);
  if (!normalized) return "place";
  if (isPlaceCategory(normalized)) return normalized;

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
    .replace(/[^a-z0-9&/ -]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
