import assert from "node:assert/strict";
import test from "node:test";
import { featuredPipelineNames } from "./featured-core.mjs";
import { inspectFeaturedKey } from "./featured-preflight.mjs";

const result = (placeId, source = "community") => ({
  placeId,
  source,
  contributorIds: source === "network" ? ["friend"] : [],
  latitude: 34,
  longitude: -118,
});

function scenario(id, slice, networkMode, confidence, overrides = {}) {
  const base = [result("a", "network"), result("b"), result("c"), result("d"), result("e")];
  const density = [base[1], base[0], ...base.slice(2)];
  const semantic = [base[1], base[2], base[0], ...base.slice(3)];
  return {
    id,
    slice,
    networkMode,
    networkConfidence: confidence,
    panGroup: null,
    latencySamplesMs: [0.2, 0.3],
    privacyFailures: 0,
    duplicateFailures: 0,
    candidates: base.map((row, index) => ({
      label: String.fromCharCode(65 + index),
      placeId: row.placeId,
    })),
    pipelineResults: Object.fromEntries(featuredPipelineNames.map((pipeline) => [
      pipeline,
      pipeline === "densityAware" ? density : pipeline === "densitySemantic" ? semantic : base,
    ])),
    ...overrides,
  };
}

function validKey() {
  return {
    judgedRank: 5,
    stats: { candidatePlaces: 30, communityOnlyPlaces: 20 },
    scenarios: [
      scenario("featured-q01", "dense", "actual", 0.8),
      scenario("featured-q02", "sparse", "actual", 0.4),
      scenario("featured-q03", "sparse", "thin", 0.3),
      scenario("featured-q04", "empty", "empty", 0),
      scenario("featured-q05", "pan", "actual", 0.8, { panGroup: "pan-1" }),
      scenario("featured-q06", "pan", "actual", 0.8, { panGroup: "pan-1" }),
      scenario("featured-q07", "cold-start", "empty", 0),
    ],
  };
}

test("Featured preflight accepts honest slices, complete blind coverage, and policy separation", () => {
  const preflight = inspectFeaturedKey(validKey());
  assert.equal(preflight.status, "pass");
  assert.equal(preflight.actualSparseScenarios, 1);
  assert.equal(preflight.simulatedThinScenarios, 1);
  assert.equal(preflight.sparseMixedSourceScenarios, 2);
  assert.equal(preflight.actualSparseMixedSourceScenarios, 1);
  assert.equal(preflight.communityEvidenceReady, true);
  assert.equal(preflight.blindCoverageFailures, 0);
});

test("Featured preflight rejects a dense viewport mislabeled as sparse", () => {
  const key = validKey();
  key.scenarios[1].networkConfidence = 0.9;
  const preflight = inspectFeaturedKey(key);
  assert.equal(preflight.status, "fail");
  assert.ok(preflight.errors.some((error) => error.includes("labeled sparse")));
});

test("Featured preflight rejects missing top-five judgments", () => {
  const key = validKey();
  key.scenarios[0].candidates.pop();
  const preflight = inspectFeaturedKey(key);
  assert.equal(preflight.status, "fail");
  assert.equal(preflight.blindCoverageFailures, featuredPipelineNames.length);
});
