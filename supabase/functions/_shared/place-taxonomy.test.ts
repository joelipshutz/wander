import {
  allowedPlaceCategories,
  inferPlaceCategory,
} from "./place-taxonomy.ts";

Deno.test("place taxonomy includes the app category framework", () => {
  const expected = [
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
  ];

  if (JSON.stringify(allowedPlaceCategories) !== JSON.stringify(expected)) {
    throw new Error("allowedPlaceCategories drifted from shared/place-taxonomy.json");
  }
});

Deno.test("place taxonomy normalizes provider subcategories to primary categories", () => {
  const cases: Array<[string, string]> = [
    ["thai restaurant", "restaurants_food"],
    ["MKPOICategoryNightlife", "bars_nightlife"],
    ["coffee shop", "coffee_tea_sweets"],
    ["4-star hotel", "stays"],
    ["art supply store", "shopping"],
    ["waterfall trail", "outdoors_nature"],
    ["train station", "travel_transit"],
    ["wellness studio", "wellness_fitness"],
    ["gym", "wellness_fitness"],
    ["craft distillery", "bars_nightlife"],
    ["beauty service", "services_errands"],
  ];

  for (const [input, expected] of cases) {
    const actual = inferPlaceCategory(input);
    if (actual !== expected) {
      throw new Error(`${input} normalized to ${actual}; expected ${expected}`);
    }
  }
});
