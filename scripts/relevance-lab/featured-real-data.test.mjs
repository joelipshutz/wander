import assert from "node:assert/strict";
import test from "node:test";
import { sanitizeFeaturedRows, sanitizeTasteRows } from "./featured-real-data.mjs";

const row = (overrides = {}) => ({
  place_id: "place-1",
  canonical_name: "Cafe One",
  category: "coffee_tea_sweets",
  subcategory: "cafe",
  locality: "Santa Monica",
  region: "CA",
  country: "US",
  latitude: 34.01,
  longitude: -118.49,
  source_provider: "mapkit",
  source_provider_place_id: "provider-1",
  contributor_id: "private-user-id",
  is_self: false,
  is_trusted: false,
  rating_score: 5,
  freshness_days: 20,
  trusted_attributes: [{ question_key: "coffee_tags", value: ["quiet"] }],
  ...overrides,
});

test("community-only rows become anonymous aggregates without private attributes", () => {
  const [place] = sanitizeFeaturedRows([row()]);
  assert.equal(place.communitySupport, 1);
  assert.equal(place.communityRating, 5);
  assert.deepEqual(place.trustedContributorIds, []);
  assert.equal(place.tags.includes("quiet"), false);
  assert.equal(JSON.stringify(place).includes("private-user-id"), false);
});

test("trusted rows contribute only opaque relationship while own rows may add structured taste", () => {
  const [place] = sanitizeFeaturedRows([
    row({ is_trusted: true, trusted_attributes: [] }),
    row({ contributor_id: "viewer-id", is_self: true, is_trusted: true }),
    row({ contributor_id: "second-private-id", rating_score: 3, freshness_days: 10 }),
  ]);
  assert.equal(place.communitySupport, 3);
  assert.ok(place.communityRating > 4);
  assert.equal(place.trustedContributorIds.length, 1);
  assert.ok(place.trustedContributorIds[0].startsWith("contributor-"));
  assert.ok(place.tags.includes("quiet"));
  assert.equal(place.canonicalTags.includes("quiet"), false);
  assert.equal(JSON.stringify(place).includes("private-user-id"), false);
});

test("taste rows use only canonical facts and approved non-text attributes", () => {
  const [place] = sanitizeTasteRows([{
    place_id: "taste-1",
    canonical_name: "Taste Cafe",
    category: "coffee_tea_sweets",
    subcategory: "cafe",
    locality: "Santa Monica",
    region: "CA",
    country: "US",
    attributes: [
      { question_key: "coffee_tags", value: ["cozy"] },
      { question_key: "private_note", value: "secret prose" },
    ],
  }]);
  assert.ok(place.tags.includes("cozy"));
  assert.equal(place.tags.includes("secret prose"), false);
});
