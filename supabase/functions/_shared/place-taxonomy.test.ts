import {
  allowedPlaceCategories,
  inferPlaceCategory,
} from "./place-taxonomy.ts";

Deno.test("place taxonomy includes the app category framework", () => {
  const expected = [
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
  ];

  if (JSON.stringify(allowedPlaceCategories) !== JSON.stringify(expected)) {
    throw new Error("allowedPlaceCategories drifted from shared/place-taxonomy.json");
  }
});

Deno.test("place taxonomy normalizes provider subcategories to primary categories", () => {
  const cases: Array<[string, string]> = [
    ["thai restaurant", "food_drink"],
    ["4-star hotel", "lodging"],
    ["art supply store", "shopping"],
    ["waterfall trail", "outdoors_nature"],
    ["train station", "transportation_transit"],
    ["wellness studio", "health_wellness"],
    ["gym", "sports_fitness"],
  ];

  for (const [input, expected] of cases) {
    const actual = inferPlaceCategory(input);
    if (actual !== expected) {
      throw new Error(`${input} normalized to ${actual}; expected ${expected}`);
    }
  }
});
