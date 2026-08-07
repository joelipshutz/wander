// Mirrors shared/place-taxonomy.json. Keep changes in sync with the Swift tests.
export const allowedPlaceCategories = [
  "restaurants_food",
  "coffee_tea_sweets",
  "bars_nightlife",
  "outdoors_nature",
  "things_to_do",
  "shopping",
  "wellness_fitness",
  "stays",
  "services_errands",
  "travel_transit",
  "work_education",
  "civic_faith",
  "areas_addresses",
  "facilities_other",
  "place",
] as const;

export type PlaceCategory = typeof allowedPlaceCategories[number];

const aliasRules: Array<{ category: PlaceCategory; patterns: RegExp[] }> = [
  {
    category: "restaurants_food",
    patterns: [
      /\b(restaurants\s+food|food\s+drink|restaurant|fast\s+food|fine\s+dining|diner|bistro|food\s+court|takeout|cafeteria|brunch|sandwich|deli|pizza|burger|barbecue|ramen|noodle|dumpling|bao(?:\s+buns?)?|baozi|dim\s+sum|hot\s+pot|taco|taqueria|thai\s+restaurant|sushi\s+restaurant|korean\s+bbq|japanese\s+curry)\b/,
    ],
  },
  {
    category: "coffee_tea_sweets",
    patterns: [
      /\b(coffee|cafe|espresso|roaster|roastery|tea\s+house|tea\s+store|bakery|dessert|ice\s+cream|gelato|juice|smoothie|acai|candy|chocolate|cat\s+cafe|dog\s+cafe)\b/,
    ],
  },
  {
    category: "bars_nightlife",
    patterns: [
      /\b(bar|nightlife|cocktail|pub|sports\s+bar|wine\s+bar|gastropub|bar\s+and\s+grill|dance\s+hall|club|disco|lounge|hookah|beer\s+garden|jazz\s+club|brewery|brewpub|distillery|winery|vineyard|nightclub|karaoke|live\s+music|comedy\s+club|casino)\b/,
    ],
  },
  {
    category: "outdoors_nature",
    patterns: [
      /\b(hike|hiking|trail|waterfall|hot\s+spring|canyon|mountain|park|playground|garden|beach|lake|campground|rv\s+park|marina|ski\s+resort|skate\s+park|wildlife)\b/,
    ],
  },
  {
    category: "things_to_do",
    patterns: [
      /\b(tourist\s+attraction|attraction|landmark|museum|gallery|theater|theatre|historic|monument|movie|cinema|concert|arena|arcade|bowling|zoo|aquarium|amusement|theme\s+park|event\s+venue|convention\s+center)\b/,
    ],
  },
  {
    category: "shopping",
    patterns: [
      /\b(shop|store|retail|mall|market|grocery|supermarket|book\s+store|bookstore|art\s+supply|craft\s+store|gift\s+shop|clothing|shoe\s+store|jewelry|cosmetics|hardware|furniture|thrift)\b/,
    ],
  },
  {
    category: "wellness_fitness",
    patterns: [
      /\b(health|wellness|fitness|gym|yoga|sports\s+club|sports\s+complex|hospital|medical|clinic|doctor|dentist|pharmacy|drugstore|spa|massage|sauna|therapy|veterinary)\b/,
    ],
  },
  {
    category: "stays",
    patterns: [
      /\b(stay|stays|lodging|hotel|motel|resort|inn|hostel|bed\s+and\s+breakfast|guest\s+house|airbnb|vrbo|extended\s+stay|cottage|cabin|campground|rv\s+park|star\s+hotel)\b/,
    ],
  },
  {
    category: "services_errands",
    patterns: [
      /\b(service|bank|atm|accounting|insurance|real\s+estate|lawyer|consultant|florist|catering|child\s+care|laundry|tailor|courier|shipping|storage|moving|electrician|plumber|locksmith|contractor|pet\s+care|beauty|salon|barber|nail\s+salon|tattoo)\b/,
    ],
  },
  {
    category: "travel_transit",
    patterns: [
      /\b(travel|transportation|transit|airport|train\s+station|subway|light\s+rail|tram|bus\s+stop|bus\s+station|ferry|taxi|bike\s+share|parking|garage|gas\s+station|ev\s+charging|car\s+rental|car\s+repair|car\s+wash|truck\s+stop)\b/,
    ],
  },
  {
    category: "work_education",
    patterns: [
      /\b(work|education|school|university|college|campus|preschool|library|research\s+institute|coworking|co\s+working|office|business\s+center|corporate\s+office|manufacturer|supplier|farm|ranch|television\s+studio)\b/,
    ],
  },
  {
    category: "civic_faith",
    patterns: [
      /\b(civic|faith|public\s+service|government|city\s+hall|courthouse|embassy|post\s+office|police|fire\s+station|worship|spiritual|church|mosque|synagogue|hindu\s+temple|buddhist\s+temple|shinto\s+shrine|place\s+of\s+worship)\b/,
    ],
  },
  {
    category: "areas_addresses",
    patterns: [
      /\b(area|address|home\s+neighborhood|apartment|condo|housing\s+complex|neighborhood|locality|city|postal\s+area|town|region|country|route|street|intersection|plus\s+code)\b/,
    ],
  },
  {
    category: "facilities_other",
    patterns: [
      /\b(facility|facilities|other|public\s+bathroom|public\s+bath|public\s+restroom|restroom|stable|generic\s+establishment|establishment|point\s+of\s+interest|unknown)\b/,
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
    .replace(/mkpoicategory/g, " ")
    .replace(/[_&/-]+/g, " ")
    .replace(/[^a-z0-9 ]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
