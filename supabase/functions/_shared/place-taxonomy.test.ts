import {
  allowedPlaceCategories,
  inferPlaceCategory,
} from "./place-taxonomy.ts";
import sharedTaxonomy from "../../../shared/place-taxonomy.json" with { type: "json" };

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

  if (JSON.stringify(allowedPlaceCategories) !== JSON.stringify(expected) ||
    JSON.stringify(allowedPlaceCategories) !== JSON.stringify(sharedTaxonomy.categories.map((category) => category.id))) {
    throw new Error("allowedPlaceCategories drifted from shared/place-taxonomy.json");
  }
});

Deno.test("specific fitness and coastal types beat broad beach and school aliases", () => {
  const cases: Array<[string, string]> = [
    ["Pilates studio", "wellness_fitness"],
    ["pilates", "wellness_fitness"],
    ["CrossFit gym", "wellness_fitness"],
    ["crossfit", "wellness_fitness"],
    ["Functional fitness studio", "wellness_fitness"],
    ["functional_fitness", "wellness_fitness"],
    ["Beach tennis", "wellness_fitness"],
    ["beach_tennis_court", "wellness_fitness"],
    ["Beach volleyball", "wellness_fitness"],
    ["beach_volleyball_court", "wellness_fitness"],
    ["Padel court", "wellness_fitness"],
    ["Climbing gym", "wellness_fitness"],
    ["rock_climbing_gym", "wellness_fitness"],
    ["Stadium", "things_to_do"],
    ["MKPOICategoryStadium", "things_to_do"],
    ["Arena", "things_to_do"],
    ["Surf", "outdoors_nature"],
    ["MKPOICategorySurfing", "outdoors_nature"],
    ["Surf break", "outdoors_nature"],
    ["Surf school", "wellness_fitness"],
    ["surf_school", "wellness_fitness"],
    ["Surf shop", "shopping"],
    ["Kayak/canoe rental", "outdoors_nature"],
    ["kayak_rental", "outdoors_nature"],
    ["canoe_rental", "outdoors_nature"],
    ["MKPOICategoryVolleyball", "wellness_fitness"],
    ["volleyball_court", "wellness_fitness"],
    ["Beach", "outdoors_nature"],
    ["School", "work_education"],
    ["surf_conditions", "place"],
    ["constructor", "place"],
  ];
  for (const [input, expected] of cases) {
    if (inferPlaceCategory(input) !== expected) {
      throw new Error(`${input} should resolve to ${expected}`);
    }
  }
});

Deno.test("shared taxonomy includes every added selectable fitness and coastal type", () => {
  const expected: Record<string, string[]> = {
    wellness_fitness: ["Pilates studio", "CrossFit gym", "Functional fitness studio", "Beach tennis", "Beach volleyball", "Padel court", "Climbing gym", "Surf school"],
    outdoors_nature: ["Surf", "Surf break", "Kayak/canoe rental"],
    things_to_do: ["Stadium", "Arena"],
    shopping: ["Surf shop"],
  };
  for (const [categoryID, subtypes] of Object.entries(expected)) {
    const category = sharedTaxonomy.categories.find((entry) => entry.id === categoryID);
    for (const subtype of subtypes) {
      if (category?.subcategories.filter((value) => value === subtype).length !== 1) {
        throw new Error(`${categoryID} is missing unique subtype ${subtype}`);
      }
      if (inferPlaceCategory(subtype) !== categoryID) {
        throw new Error(`${subtype} diverges from its shared category ${categoryID}`);
      }
    }
  }
});

Deno.test("place taxonomy normalizes provider subcategories to primary categories", () => {
  const cases: Array<[string, string]> = [
    ["thai restaurant", "restaurants_food"],
    ["bao bun shop", "restaurants_food"],
    ["baozi shop", "restaurants_food"],
    ["MKPOICategoryNightlife", "bars_nightlife"],
    ["coffee shop", "coffee_tea_sweets"],
    ["gelato shop", "coffee_tea_sweets"],
    ["4-star hotel", "stays"],
    ["art supply store", "shopping"],
    ["waterfall trail", "outdoors_nature"],
    ["train station", "travel_transit"],
    ["wellness studio", "wellness_fitness"],
    ["gym", "wellness_fitness"],
    ["craft distillery", "bars_nightlife"],
    ["cider bar", "bars_nightlife"],
    ["sake bar", "bars_nightlife"],
    ["game bar", "bars_nightlife"],
    ["beauty service", "services_errands"],
  ];

  for (const [input, expected] of cases) {
    const actual = inferPlaceCategory(input);
    if (actual !== expected) {
      throw new Error(`${input} normalized to ${actual}; expected ${expected}`);
    }
  }
});
