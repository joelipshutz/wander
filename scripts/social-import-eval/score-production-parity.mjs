#!/usr/bin/env node

import { open, mkdir, readFile } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";

import { scorePredictions, stableHash } from "./lib.mjs";

const maximumCases = 200;
const maximumLabelsPerClass = 200;
const maximumAliasesPerLabel = 30;
const maximumPredictionsPerCase = 150;
const maximumNameLength = 160;
const maximumSummaryBytes = 5_000_000;
const safeIdentifierPattern = /^[A-Za-z0-9._-]{1,120}$/;
const safeCodePattern = /^[A-Za-z0-9._:-]{1,100}$/;
const URLPattern = /(?:https?:\/\/|www\.|api\.apify\.com\/v2\/key-value-stores\/)/iu;

class ScoreError extends Error {
  constructor(code) {
    super(code);
    this.name = "ScoreError";
    this.code = code;
  }
}

export function parseScoreArguments(args) {
  const values = {
    corpusPath: "",
    resultsPath: "",
    manifestPath: "",
    outputPath: "",
    help: false,
  };
  const names = new Map([
    ["--corpus", "corpusPath"],
    ["--results", "resultsPath"],
    ["--manifest", "manifestPath"],
    ["--out", "outputPath"],
  ]);
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--help" || argument === "-h") {
      values.help = true;
      continue;
    }
    const key = names.get(argument);
    if (!key) throw new ScoreError("unknown_argument");
    const next = args[index + 1];
    if (!next || next.startsWith("--")) {
      throw new ScoreError("missing_argument_value");
    }
    values[key] = next;
    index += 1;
  }
  if (
    !values.help &&
    (!values.corpusPath || !values.resultsPath || !values.manifestPath ||
      !values.outputPath)
  ) {
    throw new ScoreError("missing_required_argument");
  }
  return values;
}

export function buildProductionParityScore({
  corpusText,
  resultsText,
  manifestText,
}) {
  const corpus = parseJSONRecord(corpusText, "invalid_corpus_json");
  const manifest = parseJSONRecord(manifestText, "invalid_manifest_json");
  const results = parseJSONArray(resultsText, "invalid_results_json");
  const cases = validatedCases(corpus);
  const expectedCaseIDs = cases.map((item) => item.id);
  const corpusSHA256 = stableHash(corpusText);

  validateManifest(manifest, corpusSHA256, expectedCaseIDs);
  const resultsByCaseID = validatedResults(results, expectedCaseIDs);
  const scoredCases = cases.map((testCase) => {
    const result = resultsByCaseID.get(testCase.id);
    const predictions = finalPredictionNames(result);
    const score = scorePredictions(testCase.labels, predictions);
    if (!score.scorable) throw new ScoreError("unscorable_case_labels");
    return {
      caseID: testCase.id,
      pipelineStatus: result.status,
      failedStage: safeOptionalCode(result.failedStage),
      errorCode: safeOptionalCode(result.errorCode),
      fallback: fallbackSummary(result),
      score: boundedScore(score),
    };
  });

  const metrics = aggregateScores(scoredCases.map((item) => item.score));
  return {
    schemaVersion: 1,
    scorer: "production-parity-score-v1",
    scoringContract: "score-contract-v4",
    corpus: {
      sha256: corpusSHA256,
      caseCount: cases.length,
    },
    run: {
      runner: "production-parity-v1",
      acquisitionMode: safeAcquisitionMode(manifest.acquisitionMode),
      completedCaseCount: cases.length,
      failedCaseCount: scoredCases.filter((item) =>
        item.pipelineStatus === "failed"
      ).length,
      fallbackCaseCount: scoredCases.filter((item) => item.fallback.used).length,
    },
    metrics,
    cases: scoredCases,
  };
}

function validatedCases(corpus) {
  if (corpus.schemaVersion !== 1 || !Array.isArray(corpus.cases)) {
    throw new ScoreError("invalid_corpus");
  }
  if (corpus.cases.length === 0 || corpus.cases.length > maximumCases) {
    throw new ScoreError("invalid_corpus_case_count");
  }
  const seen = new Set();
  return corpus.cases.map((value) => {
    const item = asRecord(value);
    if (
      !item || typeof item.id !== "string" ||
      !safeIdentifierPattern.test(item.id) || seen.has(item.id)
    ) {
      throw new ScoreError("invalid_corpus_case");
    }
    seen.add(item.id);
    return {
      id: item.id,
      labels: validatedLabels(item.labels),
    };
  });
}

function validatedLabels(value) {
  const labels = asRecord(value);
  if (!labels || labels.status !== "labeled") {
    throw new ScoreError("unscorable_case_labels");
  }
  return {
    status: "labeled",
    required: validatedLabelClass(labels.required),
    acceptable: validatedLabelClass(labels.acceptable),
    forbidden: validatedLabelClass(labels.forbidden),
  };
}

function validatedLabelClass(value) {
  if (!Array.isArray(value) || value.length > maximumLabelsPerClass) {
    throw new ScoreError("invalid_corpus_labels");
  }
  return value.map((rawLabel) => {
    const label = asRecord(rawLabel);
    if (!label || !validCorpusName(label.name) || !Array.isArray(label.aliases) ||
      label.aliases.length > maximumAliasesPerLabel ||
      !label.aliases.every(validCorpusName)) {
      throw new ScoreError("invalid_corpus_labels");
    }
    return { name: cleanText(label.name), aliases: label.aliases.map(cleanText) };
  });
}

function validateManifest(manifest, corpusSHA256, expectedCaseIDs) {
  const corpus = asRecord(manifest.corpus);
  if (
    manifest.schemaVersion !== 1 || manifest.runner !== "production-parity-v1" ||
    !corpus || corpus.sha256 !== corpusSHA256
  ) {
    throw new ScoreError(
      corpus?.sha256 !== corpusSHA256
        ? "corpus_sha256_mismatch"
        : "invalid_manifest",
    );
  }
  if (!sameOrderedValues(corpus.selectedCaseIDs, expectedCaseIDs)) {
    throw new ScoreError("manifest_case_ids_mismatch");
  }
  if (
    manifest.caseCount !== expectedCaseIDs.length ||
    manifest.completedCaseCount !== expectedCaseIDs.length ||
    typeof manifest.completedAt !== "string" || !manifest.completedAt
  ) {
    throw new ScoreError("run_incomplete");
  }
}

function validatedResults(results, expectedCaseIDs) {
  if (results.length !== expectedCaseIDs.length) {
    throw new ScoreError("result_case_ids_mismatch");
  }
  const expected = new Set(expectedCaseIDs);
  const output = new Map();
  for (const value of results) {
    const result = asRecord(value);
    if (
      !result || result.schemaVersion !== 1 ||
      typeof result.caseID !== "string" ||
      !safeIdentifierPattern.test(result.caseID) ||
      !expected.has(result.caseID) || output.has(result.caseID) ||
      !["completed", "failed"].includes(result.status)
    ) {
      throw new ScoreError("result_case_ids_mismatch");
    }
    output.set(result.caseID, result);
  }
  if (output.size !== expected.size) {
    throw new ScoreError("result_case_ids_mismatch");
  }
  return output;
}

function finalPredictionNames(result) {
  if (result.grounding == null) {
    if (
      result.status === "completed" ||
      ["media", "understanding"].includes(result.failedStage)
    ) {
      throw new ScoreError("missing_final_hints");
    }
    return [];
  }
  const grounding = asRecord(result.grounding);
  if (!grounding || !Array.isArray(grounding.hints) ||
    grounding.hints.length > maximumPredictionsPerCase) {
    throw new ScoreError("invalid_final_hints");
  }
  if (["media", "understanding"].includes(result.failedStage)) {
    const fallback = asRecord(grounding.fallback);
    if (!fallback || fallback.triggerStage !== result.failedStage) {
      throw new ScoreError("missing_failure_fallback");
    }
  }
  return grounding.hints.map((value) => {
    const hint = asRecord(value);
    if (!hint || typeof hint.name !== "string") {
      throw new ScoreError("invalid_final_hints");
    }
    const name = safePredictionName(hint.name);
    if (!name) throw new ScoreError("invalid_final_hints");
    return name;
  });
}

function fallbackSummary(result) {
  const grounding = asRecord(result.grounding);
  const fallback = asRecord(grounding?.fallback);
  if (!fallback) {
    return {
      used: false,
      triggerStage: null,
      failureCategory: null,
      modelAttemptCount: 0,
    };
  }
  if (
    !["media", "understanding"].includes(fallback.triggerStage) ||
    typeof fallback.failureCategory !== "string" ||
    !safeCodePattern.test(fallback.failureCategory) ||
    !Number.isInteger(fallback.modelAttemptCount) ||
    fallback.modelAttemptCount < 0 || fallback.modelAttemptCount > 6
  ) {
    throw new ScoreError("invalid_fallback_summary");
  }
  return {
    used: true,
    triggerStage: fallback.triggerStage,
    failureCategory: fallback.failureCategory,
    modelAttemptCount: fallback.modelAttemptCount,
  };
}

function boundedScore(score) {
  return {
    scorable: true,
    labelStatus: "labeled",
    requiredCount: score.requiredCount,
    requiredHitCount: score.requiredHitCount,
    acceptableHitCount: score.acceptableHitCount,
    forbiddenHitCount: score.forbiddenHitCount,
    predictionCount: score.predictionCount,
    correctPredictionCount: score.predictionCount - score.falsePredictions.length,
    falsePredictionCount: score.falsePredictions.length,
    precision: score.precision,
    recall: score.recall,
    f1: score.f1,
    postSuccess: score.postSuccess,
    exactRequiredSet: score.exactRequiredSet,
    requiredMisses: score.requiredMisses.map(cleanText),
    forbiddenHits: score.forbiddenHits.map(cleanText),
  };
}

function aggregateScores(scores) {
  const totals = scores.reduce((output, score) => {
    output.requiredCount += score.requiredCount;
    output.requiredHitCount += score.requiredHitCount;
    output.predictionCount += score.predictionCount;
    output.correctPredictionCount += score.correctPredictionCount;
    output.falsePredictionCount += score.falsePredictionCount;
    output.forbiddenHitCount += score.forbiddenHitCount;
    output.exactSetCaseCount += score.exactRequiredSet ? 1 : 0;
    output.postSuccessCaseCount += score.postSuccess ? 1 : 0;
    return output;
  }, {
    requiredCount: 0,
    requiredHitCount: 0,
    predictionCount: 0,
    correctPredictionCount: 0,
    falsePredictionCount: 0,
    forbiddenHitCount: 0,
    exactSetCaseCount: 0,
    postSuccessCaseCount: 0,
  });
  const microPrecision = totals.predictionCount === 0
    ? (totals.requiredCount === 0 ? 1 : 0)
    : totals.correctPredictionCount / totals.predictionCount;
  const microRecall = totals.requiredCount === 0
    ? 1
    : totals.requiredHitCount / totals.requiredCount;
  return {
    labeledCaseCount: scores.length,
    ...totals,
    exactSetRate: totals.exactSetCaseCount / scores.length,
    postSuccessRate: totals.postSuccessCaseCount / scores.length,
    macroPrecision: average(scores.map((score) => score.precision)),
    macroRecall: average(scores.map((score) => score.recall)),
    macroF1: average(scores.map((score) => score.f1)),
    microPrecision,
    microRecall,
    microF1: f1(microPrecision, microRecall),
  };
}

function safePredictionName(value) {
  const cleaned = cleanText(value);
  if (!cleaned) return null;
  return URLPattern.test(cleaned) ? "[redacted_url]" : cleaned;
}

function validCorpusName(value) {
  if (typeof value !== "string" || URLPattern.test(value)) return false;
  const cleaned = normalizedText(value);
  return cleaned.length > 0 && cleaned.length <= maximumNameLength;
}

function cleanText(value) {
  return normalizedText(value).slice(0, maximumNameLength);
}

function normalizedText(value) {
  return String(value ?? "")
    .replace(/[\u0000-\u001f\u007f]/gu, " ")
    .replace(/\s+/gu, " ")
    .trim();
}

function safeOptionalCode(value) {
  if (value == null) return null;
  return typeof value === "string" && safeCodePattern.test(value)
    ? value
    : "redacted_error";
}

function safeAcquisitionMode(value) {
  return ["saved_apify_fixture", "live_apify"].includes(value)
    ? value
    : "unknown";
}

function average(values) {
  return values.reduce((sum, value) => sum + value, 0) / values.length;
}

function f1(precision, recall) {
  return precision + recall === 0
    ? 0
    : (2 * precision * recall) / (precision + recall);
}

function sameOrderedValues(value, expected) {
  return Array.isArray(value) && value.length === expected.length &&
    value.every((item, index) => item === expected[index]);
}

function asRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value
    : null;
}

function parseJSONRecord(text, errorCode) {
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    throw new ScoreError(errorCode);
  }
  const record = asRecord(value);
  if (!record) throw new ScoreError(errorCode);
  return record;
}

function parseJSONArray(text, errorCode) {
  let value;
  try {
    value = JSON.parse(text);
  } catch {
    throw new ScoreError(errorCode);
  }
  if (!Array.isArray(value)) throw new ScoreError(errorCode);
  return value;
}

async function writePrivateSummary(path, value) {
  const serialized = JSON.stringify(value, null, 2) + "\n";
  if (Buffer.byteLength(serialized) > maximumSummaryBytes) {
    throw new ScoreError("summary_too_large");
  }
  await mkdir(dirname(path), { recursive: true });
  let file;
  try {
    file = await open(path, "wx", 0o600);
    await file.writeFile(serialized, "utf8");
  } catch (error) {
    if (error?.code === "EEXIST") throw new ScoreError("output_file_exists");
    throw error;
  } finally {
    await file?.close();
  }
}

function absolutePath(value) {
  return isAbsolute(value) ? value : resolve(process.cwd(), value);
}

function usage() {
  return `Score a completed production-parity social-import run

Usage:
  node scripts/social-import-eval/score-production-parity.mjs \\
    --corpus <corpus.json> \\
    --results <results.json> \\
    --manifest <manifest.json> \\
    --out <new-summary.json>
`;
}

async function main() {
  let args;
  try {
    args = parseScoreArguments(process.argv.slice(2));
  } catch (error) {
    process.stderr.write(`production-parity-score: ${publicErrorCode(error)}\n`);
    process.exitCode = 1;
    return;
  }
  if (args.help) {
    process.stdout.write(usage());
    return;
  }
  try {
    const corpusPath = absolutePath(args.corpusPath);
    const resultsPath = absolutePath(args.resultsPath);
    const manifestPath = absolutePath(args.manifestPath);
    const outputPath = absolutePath(args.outputPath);
    if ([corpusPath, resultsPath, manifestPath].includes(outputPath)) {
      throw new ScoreError("output_conflicts_with_input");
    }
    const [corpusText, resultsText, manifestText] = await Promise.all([
      readFile(corpusPath, "utf8"),
      readFile(resultsPath, "utf8"),
      readFile(manifestPath, "utf8"),
    ]);
    const summary = buildProductionParityScore({
      corpusText,
      resultsText,
      manifestText,
    });
    await writePrivateSummary(outputPath, summary);
    process.stdout.write(JSON.stringify({
      outcome: "complete",
      caseCount: summary.corpus.caseCount,
      exactSetCaseCount: summary.metrics.exactSetCaseCount,
      exactSetRate: summary.metrics.exactSetRate,
    }) + "\n");
  } catch (error) {
    process.stderr.write(`production-parity-score: ${publicErrorCode(error)}\n`);
    process.exitCode = 1;
  }
}

function publicErrorCode(error) {
  return error instanceof ScoreError ? error.code : "unexpected_error";
}

if (import.meta.url === `file://${process.argv[1]}`) await main();
