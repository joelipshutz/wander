import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, stat, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { test } from "node:test";

import { stableHash } from "./lib.mjs";
import {
  buildProductionParityScore,
  parseScoreArguments,
} from "./score-production-parity.mjs";

const execFileAsync = promisify(execFile);

function fixture() {
  const corpus = {
    schemaVersion: 1,
    cases: [
      {
        id: "rory-case",
        url: "https://www.instagram.com/reel/public-source/",
        labels: {
          status: "labeled",
          required: [
            { name: "Rory's Place", aliases: ["Rorys Place"] },
            { name: "Rory's Other Place", aliases: [] },
          ],
          acceptable: [],
          forbidden: [{ name: "Ojai", aliases: ["City of Ojai"] }],
        },
      },
      {
        id: "books-case",
        url: "https://www.instagram.com/reel/another-public-source/",
        labels: {
          status: "labeled",
          required: [{ name: "Bart's Books", aliases: ["Bart Books"] }],
          acceptable: [],
          forbidden: [],
        },
      },
    ],
  };
  const corpusText = JSON.stringify(corpus);
  const results = [
    {
      schemaVersion: 1,
      caseID: "books-case",
      status: "failed",
      failedStage: "understanding",
      errorCode: "gemini_http_503",
      source: { url: "https://must-not-be-copied.example/source" },
      rawEvidence: "private-caption-and-secret-token",
      grounding: {
        fallback: {
          triggerStage: "understanding",
          failureCategory: "understanding_unavailable",
          modelAttemptCount: 2,
        },
        hints: [{ name: "Bart Books", evidence_ids: ["private-caption"] }],
      },
    },
    {
      schemaVersion: 1,
      caseID: "rory-case",
      status: "completed",
      failedStage: null,
      errorCode: null,
      providerPayload: {
        signedURL: "https://must-not-be-copied.example/media?token=secret",
      },
      grounding: {
        fallback: null,
        hints: [
          { name: "Rorys Place" },
          { name: "Rory's Other Place" },
          { name: "Ojai" },
        ],
      },
    },
  ];
  const manifest = {
    schemaVersion: 1,
    runner: "production-parity-v1",
    corpus: {
      sha256: stableHash(corpusText),
      selectedCaseIDs: ["rory-case", "books-case"],
    },
    caseCount: 2,
    acquisitionMode: "saved_apify_fixture",
    completedAt: "2026-08-31T12:00:00.000Z",
    completedCaseCount: 2,
    failedCaseCount: 1,
  };
  return {
    corpusText,
    resultsText: JSON.stringify(results),
    manifestText: JSON.stringify(manifest),
  };
}

test("score-production-parity arguments require every explicit input and output", () => {
  assert.deepEqual(parseScoreArguments([
    "--corpus",
    "/private/corpus.json",
    "--results",
    "/private/results.json",
    "--manifest",
    "/private/manifest.json",
    "--out",
    "/private/summary.json",
  ]), {
    corpusPath: "/private/corpus.json",
    resultsPath: "/private/results.json",
    manifestPath: "/private/manifest.json",
    outputPath: "/private/summary.json",
    help: false,
  });
  assert.throws(
    () => parseScoreArguments(["--corpus", "/private/corpus.json"]),
    /missing_required_argument/,
  );
  assert.throws(
    () => parseScoreArguments(["--token", "must-not-be-supported"]),
    /unknown_argument/,
  );
});

test("scores final hints by case ID with aliases, forbidden labels, and fallback cases", () => {
  const summary = buildProductionParityScore(fixture());

  assert.equal(summary.scoringContract, "score-contract-v5-review-rows");
  assert.deepEqual(summary.corpus, {
    sha256: stableHash(fixture().corpusText),
    caseCount: 2,
  });
  assert.equal(summary.run.failedCaseCount, 1);
  assert.equal(summary.run.fallbackCaseCount, 1);
  assert.equal(summary.metrics.requiredCount, 3);
  assert.equal(summary.metrics.requiredHitCount, 3);
  assert.equal(summary.metrics.predictionCount, 4);
  assert.equal(summary.metrics.correctPredictionCount, 3);
  assert.equal(summary.metrics.falsePredictionCount, 1);
  assert.equal(summary.metrics.forbiddenHitCount, 1);
  assert.equal(summary.metrics.microPrecision, 0.75);
  assert.equal(summary.metrics.microRecall, 1);
  assert.equal(summary.metrics.exactSetCaseCount, 1);
  assert.equal(summary.metrics.exactSetRate, 0.5);

  const rory = summary.cases.find((item) => item.caseID === "rory-case");
  assert.equal(rory.score.requiredHitCount, 2);
  assert.equal(rory.score.forbiddenHitCount, 1);
  assert.equal(rory.score.falsePredictionCount, 1);
  assert.equal(rory.score.exactRequiredSet, false);
  assert.deepEqual(rory.score.forbiddenHits, ["Ojai"]);
  const books = summary.cases.find((item) => item.caseID === "books-case");
  assert.equal(books.score.exactRequiredSet, true);
  assert.deepEqual(books.fallback, {
    used: true,
    triggerStage: "understanding",
    failureCategory: "understanding_unavailable",
    modelAttemptCount: 2,
  });

  const serialized = JSON.stringify(summary);
  for (const forbidden of [
    "https://",
    "public-source",
    "private-caption",
    "secret-token",
    "providerPayload",
    "rawEvidence",
    "evidence_ids",
    "falsePredictions",
  ]) assert.equal(serialized.includes(forbidden), false, forbidden);
});

test("duplicate review rows reduce precision and cannot pass the exact-set gate", () => {
  const valid = fixture();
  const results = JSON.parse(valid.resultsText);
  results[0].grounding.hints.push({ name: "bart books" });
  const summary = buildProductionParityScore({ ...valid, resultsText: JSON.stringify(results) });
  const books = summary.cases.find((item) => item.caseID === "books-case");
  assert.equal(books.score.requiredHitCount, 1);
  assert.equal(books.score.predictionCount, 2);
  assert.equal(books.score.duplicateNameRowCount, 1);
  assert.equal(books.score.correctPredictionCount, 1);
  assert.equal(books.score.falsePredictionCount, 1);
  assert.equal(books.score.precision, 0.5);
  assert.equal(books.score.recall, 1);
  assert.equal(books.score.exactRequiredSet, false);
  assert.equal(summary.metrics.duplicateNameRowCount, 1);
  assert.equal(summary.metrics.predictionCount, 5);
  assert.equal(summary.metrics.microPrecision, 0.6);
  assert.equal(summary.metrics.exactSetRate, 0);
});

test("fails closed on corpus hash, manifest completion, result IDs, and old missing fallbacks", () => {
  const valid = fixture();
  const badHash = JSON.parse(valid.manifestText);
  badHash.corpus.sha256 = "0".repeat(64);
  assert.throws(
    () => buildProductionParityScore({
      ...valid,
      manifestText: JSON.stringify(badHash),
    }),
    /corpus_sha256_mismatch/,
  );

  const incomplete = JSON.parse(valid.manifestText);
  delete incomplete.completedAt;
  assert.throws(
    () => buildProductionParityScore({
      ...valid,
      manifestText: JSON.stringify(incomplete),
    }),
    /run_incomplete/,
  );

  const duplicateResults = JSON.parse(valid.resultsText);
  duplicateResults[1] = duplicateResults[0];
  assert.throws(
    () => buildProductionParityScore({
      ...valid,
      resultsText: JSON.stringify(duplicateResults),
    }),
    /result_case_ids_mismatch/,
  );

  const oldFailure = JSON.parse(valid.resultsText);
  oldFailure[0].grounding = null;
  assert.throws(
    () => buildProductionParityScore({
      ...valid,
      resultsText: JSON.stringify(oldFailure),
    }),
    /missing_final_hints/,
  );
});

test("CLI writes one private bounded summary and refuses to overwrite it", async () => {
  const directory = await mkdtemp(join(tmpdir(), "rec120-parity-score-"));
  const corpusPath = join(directory, "corpus.json");
  const resultsPath = join(directory, "results.json");
  const manifestPath = join(directory, "manifest.json");
  const outputPath = join(directory, "score-summary.json");
  const valid = fixture();
  await Promise.all([
    writeFile(corpusPath, valid.corpusText),
    writeFile(resultsPath, valid.resultsText),
    writeFile(manifestPath, valid.manifestText),
  ]);
  const script = new URL("./score-production-parity.mjs", import.meta.url);
  const argumentsList = [
    script.pathname,
    "--corpus",
    corpusPath,
    "--results",
    resultsPath,
    "--manifest",
    manifestPath,
    "--out",
    outputPath,
  ];

  const first = await execFileAsync(process.execPath, argumentsList);
  assert.match(first.stdout, /"exactSetRate":0\.5/);
  const summary = JSON.parse(await readFile(outputPath, "utf8"));
  assert.equal(summary.metrics.exactSetRate, 0.5);
  assert.equal((await stat(outputPath)).mode & 0o077, 0);
  await assert.rejects(
    execFileAsync(process.execPath, argumentsList),
    (error) => {
      assert.match(error.stderr, /output_file_exists/);
      return true;
    },
  );
});
