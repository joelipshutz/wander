import {
  allowedPlaceCategories,
  inferPlaceCategory,
} from "./place-taxonomy.ts";

Deno.test("place taxonomy includes the app category framework", () => {
  const expected = [
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
  ];

  if (JSON.stringify(allowedPlaceCategories) !== JSON.stringify(expected)) {
    throw new Error("allowedPlaceCategories drifted from shared/place-taxonomy.json");
  }
});

Deno.test("place taxonomy normalizes provider subcategories to primary categories", () => {
  const cases: Array<[string, string]> = [
    ["thai restaurant", "restaurant"],
    ["4-star hotel", "hotel"],
    ["art supply store", "shop"],
    ["waterfall trail", "hike"],
    ["train station", "transportation"],
  ];

  for (const [input, expected] of cases) {
    const actual = inferPlaceCategory(input);
    if (actual !== expected) {
      throw new Error(`${input} normalized to ${actual}; expected ${expected}`);
    }
  }
});
