import assert from "node:assert/strict";
import test from "node:test";
import { parseFeaturedScores, scoreFeaturedPool } from "./score-featured-real.mjs";

function pipelineRows(order) {
  return order.map((placeId, index) => ({
    placeId,
    rank: index + 1,
    source: index === 0 ? "network" : "community",
    contributorIds: index === 0 ? ["friend"] : [],
    latitude: 34 + index * 0.001,
    longitude: -118.25,
  }));
}

function scenario(id, slice, orders, options = {}) {
  const placeIds = [...new Set(Object.values(orders).flat())];
  return {
    id,
    title: "Area",
    slice,
    panGroup: options.panGroup ?? null,
    latencySamplesMs: [1, 2, 3],
    privacyFailures: options.privacyFailures ?? 0,
    duplicateFailures: 0,
    candidates: placeIds.map((placeId, index) => ({
      label: String.fromCharCode(65 + index),
      placeId,
      pipelines: Object.fromEntries(Object.entries(orders).map(([pipeline, order]) => [
        pipeline,
        order.indexOf(placeId) === -1 ? null : order.indexOf(placeId) + 1,
      ])),
    })),
    pipelineResults: Object.fromEntries(Object.entries(orders).map(([pipeline, order]) => [
      pipeline,
      pipelineRows(order),
    ])),
  };
}

const good = ["good", "okay", "bad"];
const better = ["good", "okay", "bad"];
const worse = ["bad", "okay", "good"];

function allOrders({ current = worse, density = better, semantic = better } = {}) {
  return {
    current,
    networkOnly: current,
    fixedBlend: density,
    densityAware: density,
    densitySemantic: semantic,
  };
}

test("Featured score parser requires stable scenario/label lines", () => {
  const parsed = parseFeaturedScores("featured-q01:A=3\nfeatured-q01:B=0\n");
  assert.equal(parsed.get("featured-q01:A"), 3);
  assert.throws(() => parseFeaturedScores("featured-qx:A=3"), /Invalid Featured score/);
});

test("Featured scorecard applies quality, privacy, latency, and pan gates", () => {
  const scenarios = [
    scenario("featured-q01", "dense", allOrders({ current: good, density: good, semantic: good })),
    scenario("featured-q02", "sparse", allOrders()),
    scenario("featured-q03", "empty", allOrders()),
    scenario("featured-q04", "pan", allOrders(), { panGroup: "p" }),
    scenario("featured-q05", "pan", allOrders(), { panGroup: "p" }),
  ];
  const lines = scenarios.flatMap((row) => row.candidates.map((candidate) => {
    const grade = { good: 3, okay: 2, bad: 0 }[candidate.placeId];
    return `${row.id}:${candidate.label}=${grade}`;
  }));
  const scorecard = scoreFeaturedPool({
    key: {
      judgedRank: 5,
      stats: {},
      preflight: { communityEvidenceReady: true },
      scenarios,
    },
    scores: parseFeaturedScores(lines.join("\n")),
  });
  assert.equal(scorecard.guardrails.privacyFailures, 0);
  assert.ok(scorecard.decision.densitySparseEmptyGain > 0.05);
  assert.equal(scorecard.decision.densityDecision, "keep");
  assert.equal(scorecard.decision.semanticDecision, "defer", "semantics must add its own five-point gain");

  const unsafe = structuredClone(scenarios);
  unsafe[0].privacyFailures = 1;
  const unsafeScorecard = scoreFeaturedPool({
    key: {
      judgedRank: 5,
      stats: {},
      preflight: { communityEvidenceReady: true },
      scenarios: unsafe,
    },
    scores: parseFeaturedScores(lines.join("\n")),
  });
  assert.equal(unsafeScorecard.decision.densityDecision, "defer");

  const thinCorpusScorecard = scoreFeaturedPool({
    key: {
      judgedRank: 5,
      stats: { communityOnlyPlaces: 6 },
      preflight: {
        communityEvidenceReady: false,
        communityOnlyRate: 0.067,
        actualSparseMixedSourceScenarios: 0,
      },
      scenarios,
    },
    scores: parseFeaturedScores(lines.join("\n")),
  });
  assert.equal(
    thinCorpusScorecard.decision.densityDecision,
    "defer",
    "simulated fallback slices cannot promote a policy without real community coverage",
  );
});
