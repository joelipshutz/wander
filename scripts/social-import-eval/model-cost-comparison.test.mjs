import assert from "node:assert/strict";
import { test } from "node:test";

import { compareModelCosts } from "./model-cost-comparison.mjs";

test("model cost comparison prices input and reasoning-inclusive output", () => {
  const comparisons = compareModelCosts(
    { inputTokens: 44_348, outputTokens: 22_548, importCount: 8 },
    {
      schemaVersion: 1,
      models: [{
        id: "gemini-3.5-flash",
        provider: "google",
        input: 1.5,
        outputIncludingReasoning: 9,
        nativeVideoInput: true,
        source: "https://example.test/pricing",
      }],
    },
  );
  assert.deepEqual(comparisons[0], {
    model: "gemini-3.5-flash",
    provider: "google",
    nativeVideoInput: true,
    usdPerMillionInputTokens: 1.5,
    usdPerMillionOutputIncludingReasoningTokens: 9,
    inputCostUSD: 0.066522,
    outputCostUSD: 0.202932,
    totalCostUSD: 0.269454,
    costPerImportUSD: 0.03368175,
    source: "https://example.test/pricing",
  });
});

test("model cost comparison rejects malformed usage and prices", () => {
  assert.throws(
    () => compareModelCosts(
      { inputTokens: -1, outputTokens: 1, importCount: 1 },
      { schemaVersion: 1, models: [] },
    ),
    /invalid_inputTokens/,
  );
  assert.throws(
    () => compareModelCosts(
      { inputTokens: 1, outputTokens: 1, importCount: 1 },
      { schemaVersion: 1, models: [{ id: "bad", input: -1 }] },
    ),
    /invalid_model_pricing/,
  );
});
