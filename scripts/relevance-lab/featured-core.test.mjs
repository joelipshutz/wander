import assert from "node:assert/strict";
import test from "node:test";
import {
  averageEmbedding,
  buildFeaturedTasteProfile,
  featuredNetworkConfidence,
  generateFeaturedScenarios,
  overlapAt,
  rankFeaturedScenario,
} from "./featured-core.mjs";

const candidate = (id, overrides = {}) => ({
  id,
  name: id,
  category: "restaurants_food",
  tags: [],
  locality: "Los Angeles",
  region: "CA",
  latitude: 34 + Number(id.replace(/\D/g, "") || 0) * 0.001,
  longitude: -118.25,
  includesSelf: false,
  trustedContributorIds: [],
  primaryTrustedContributorId: null,
  communitySupport: 1,
  communityRating: 3,
  freshnessDays: 90,
  semanticTasteScore: 0,
  ...overrides,
});

test("network confidence reacts to viewport density, contributor diversity, and empty mode", () => {
  const dense = Array.from({ length: 8 }, (_, index) => candidate(`p${index}`, {
    trustedContributorIds: [`u${index % 3}`],
    primaryTrustedContributorId: `u${index % 3}`,
  }));
  const sparse = [dense[0], ...Array.from({ length: 7 }, (_, index) => candidate(`c${index}`))];
  const scenario = { networkMode: "actual", tasteMode: "actual" };
  assert.ok(featuredNetworkConfidence(dense, scenario) > featuredNetworkConfidence(sparse, scenario));
  assert.equal(featuredNetworkConfidence(dense, { ...scenario, networkMode: "empty" }), 0);
});

test("density-aware ranking shifts toward community strength when the network is empty", () => {
  const network = candidate("network", {
    trustedContributorIds: ["friend"],
    primaryTrustedContributorId: "friend",
    communitySupport: 1,
    communityRating: 2,
  });
  const community = candidate("community", {
    communitySupport: 16,
    communityRating: 5,
  });
  const tasteProfile = buildFeaturedTasteProfile([]);
  const result = rankFeaturedScenario({
    candidates: [network, community],
    scenario: { networkMode: "empty", tasteMode: "none" },
    tasteProfile,
    limit: 2,
  });
  assert.equal(result.pipelines.densityAware[0].id, "community");
  assert.equal(result.pipelines.networkOnly.length, 0);
  assert.ok(result.pipelines.densityAware.every((row) => row.source === "community"));
  assert.ok(result.pipelines.densityAware.every((row) => row.contributorIds.length === 0));
});

test("simulated community candidates cannot retain self-only tags or relationship boosts", () => {
  const own = candidate("own", {
    includesSelf: true,
    canonicalTags: ["restaurants food"],
    tags: ["restaurants food", "private fit"],
  });
  const other = candidate("other", {
    canonicalTags: ["restaurants food"],
    tags: ["restaurants food"],
  });
  const tasteProfile = buildFeaturedTasteProfile([{
    category: "unrelated",
    tags: ["private fit"],
  }]);
  const actual = rankFeaturedScenario({
    candidates: [own, other],
    scenario: { networkMode: "actual", tasteMode: "actual" },
    tasteProfile,
    limit: 2,
  });
  const thin = rankFeaturedScenario({
    candidates: [own, other],
    scenario: { networkMode: "thin", tasteMode: "actual", trustedCandidateIds: [] },
    tasteProfile,
    limit: 2,
  });
  assert.equal(actual.pipelines.densityAware[0].id, "own");
  assert.equal(thin.pipelines.densityAware[0].id, "other");
  assert.ok(thin.pipelines.densityAware.every((row) => row.source === "community"));
});

test("semantic taste remains a bounded provider signal", () => {
  const weak = candidate("weak", { semanticTasteScore: 0.1, communitySupport: 3 });
  const fit = candidate("fit", { semanticTasteScore: 1, communitySupport: 3 });
  const result = rankFeaturedScenario({
    candidates: [weak, fit],
    scenario: { networkMode: "empty", tasteMode: "actual" },
    tasteProfile: buildFeaturedTasteProfile([]),
    limit: 2,
  });
  assert.equal(result.pipelines.densitySemantic[0].id, "fit");
  assert.equal(result.pipelines.densityAware[0].id, "fit", "stable id tie-break remains deterministic");
  assert.ok(result.pipelines.densitySemantic[0].score <= 1);
});

test("scenario generation includes dense, empty, pan, and cold-start slices", () => {
  const places = [
    ...Array.from({ length: 8 }, (_, index) => candidate(`la${index}`, {
      trustedContributorIds: [`friend${index % 3}`],
      primaryTrustedContributorId: `friend${index % 3}`,
    })),
    ...Array.from({ length: 5 }, (_, index) => candidate(`wa${index}`, {
      locality: "Bellingham",
      region: "WA",
      latitude: 48.75 + index * 0.002,
      longitude: -122.48,
      trustedContributorIds: index < 3 ? ["north"] : [],
      primaryTrustedContributorId: index < 3 ? "north" : null,
    })),
  ];
  const slices = new Set(generateFeaturedScenarios(places).map((scenario) => scenario.slice));
  assert.deepEqual(slices, new Set(["dense", "sparse", "empty", "pan", "cold-start"]));
});

test("embedding averages and pan overlap are deterministic", () => {
  assert.deepEqual(averageEmbedding([[1, 3], [3, 5]]), [2, 4]);
  assert.equal(overlapAt([{ id: "a" }, { id: "b" }], [{ id: "b" }, { id: "c" }]), 1 / 3);
});
