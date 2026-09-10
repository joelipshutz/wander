import assert from "node:assert/strict";
import test from "node:test";
import { parseScores, scoreRealPool } from "./score-real.mjs";

const candidate = (label, placeId, lexical, reranked, hybrid) => ({
  label,
  placeId,
  pipelines: { lexical, reranked, hybrid },
});

test("real score parser accepts complete grades and rejects duplicates", () => {
  assert.deepEqual([...parseScores("real-q01:A=3\nreal-q01:B=0\n")], [
    ["real-q01:A", 3],
    ["real-q01:B", 0],
  ]);
  assert.throws(
    () => parseScores("real-q01:A=3\nreal-q01:A=2"),
    /Duplicate score/,
  );
});

test("real scorecard reconstructs hidden ranks and applies the vector gate", () => {
  const key = {
    queries: [
      {
        id: "real-q01",
        text: "semantic query",
        candidates: [
          candidate("A", "ideal", 2, 2, 1),
          candidate("B", "wrong", 1, 1, 2),
        ],
      },
      {
        id: "real-q02",
        text: "guardrail query",
        candidates: [
          candidate("A", "good", 1, 1, 1),
          candidate("B", "weak", 2, 2, 2),
        ],
      },
    ],
  };
  const scores = parseScores([
    "real-q01:A=3",
    "real-q01:B=0",
    "real-q02:A=2",
    "real-q02:B=1",
  ].join("\n"));
  const result = scoreRealPool({
    key,
    scores,
    queryIntents: [
      { id: "real-q01", intent: "semantic" },
      { id: "real-q02", intent: "constraint" },
    ],
  });

  assert.ok(result.slices.semantic.hybrid.ndcgAt5 > result.slices.semantic.reranked.ndcgAt5);
  assert.equal(result.decision.vectorDecision, "keep");
  assert.equal(result.pipelines.hybrid.idealAt1, 0.5);
  assert.equal(result.pipelines.hybrid.coverageAt5, 0.4);
  assert.equal(result.pipelines.hybrid.usefulRateAt5, 0.2);
});

test("real scorecard rejects an incomplete blind pool", () => {
  const key = {
    queries: [{
      id: "real-q01",
      text: "query",
      candidates: [candidate("A", "place", 1, 1, 1)],
    }],
  };
  assert.throws(
    () => scoreRealPool({ key, scores: new Map(), queryIntents: [] }),
    /missing real-q01:A/,
  );
});
