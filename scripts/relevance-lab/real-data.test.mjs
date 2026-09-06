import assert from "node:assert/strict";
import test from "node:test";
import { deduplicateRealPlaces, realQueries, sanitizeRealPlaceRow } from "./real-data.mjs";

test("real queries cover lexical, semantic, constraint, and community slices", () => {
  assert.equal(realQueries.length, 12);
  assert.deepEqual(
    new Set(realQueries.map(({ intent }) => intent)),
    new Set(["lexical", "semantic", "constraint", "community"]),
  );
  assert.ok(realQueries.every((query) => Object.keys(query.relevant).length === 0));
});

test("real place sanitization keeps approved structure and rejects private/free text", () => {
  const place = sanitizeRealPlaceRow({
    id: "place-1",
    canonical_name: "Real Cafe",
    category: "coffee_tea_sweets",
    subcategory: "Coffee_shop",
    locality: "Santa Monica",
    region: "CA",
    country: "US",
    community_support: 4,
    been_count: 3,
    wanna_count: 1,
    rating_count: 2,
    community_rating: 4.5,
    freshness_days: 7,
    attributes: [
      { question_key: "coffee_tags", value_type: "multi_tag", value: ["Quiet", "Good WiFi"] },
      { question_key: "personal_labels", value_type: "personal_label", value: ["Secret client spot"] },
      { question_key: "occasion", value_type: "multi_tag", value: ["Date night"] },
      { question_key: "restaurant_tags", value_type: "text", value: "private@example.com" },
    ],
  });

  assert.equal(place.name, "Real Cafe");
  assert.equal(place.neighborhood, "Santa Monica");
  assert.ok(place.tags.includes("coffee tea sweets"));
  assert.ok(place.tags.includes("Coffee shop"));
  assert.ok(place.tags.includes("Quiet"));
  assert.ok(place.tags.includes("Date night"));
  assert.ok(!place.tags.includes("Secret client spot"));
  assert.ok(!place.tags.some((tag) => tag.includes("@")));
  assert.equal(place.communityRating, 4.5);
  assert.equal(place.communitySupport, 4);
});

test("real place deduplication merges canonical duplicates without exposing addresses", () => {
  const base = {
    id: "b",
    name: "Gnarwhal Coffee Co.",
    category: "coffee_tea_sweets",
    subcategory: "Cafe",
    neighborhood: "Santa Monica",
    city: "CA",
    country: "US",
    description: "",
    tags: ["Quiet"],
    owner: "Community",
    relationship: "community",
    status: "been",
    rating: 4,
    visits: 1,
    communityRating: 4,
    communitySupport: 1,
    ratingCount: 1,
    distanceKm: 0,
    freshnessDays: 10,
    price: 2,
    openTonight: true,
    vegetarianFriendly: false,
    groupFriendly: false,
    childFriendly: false,
  };
  const duplicate = {
    ...base,
    id: "a",
    tags: ["Good WiFi"],
    communityRating: 5,
    communitySupport: 2,
    ratingCount: 1,
    visits: 2,
    freshnessDays: 3,
  };
  const deduplicated = deduplicateRealPlaces([base, duplicate]);

  assert.equal(deduplicated.length, 1);
  assert.equal(deduplicated[0].id, "a");
  assert.equal(deduplicated[0].communitySupport, 3);
  assert.equal(deduplicated[0].communityRating, 4.5);
  assert.deepEqual(deduplicated[0].tags, ["Quiet", "Good WiFi"]);
  assert.equal(deduplicated[0].freshnessDays, 3);
});
