#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { featuredPipelineNames, overlapAt } from "./featured-core.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

function percentile(values, fraction) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)];
}

function topIDs(scenario, pipeline, at) {
  return (scenario.pipelineResults[pipeline] ?? []).slice(0, at).map((row) => row.placeId);
}

function sameOrder(left, right) {
  return left.length === right.length && left.every((value, index) => value === right[index]);
}

function hasMixedSources(rows) {
  const sources = new Set(rows.map((row) => row.source));
  return sources.has("network") && sources.has("community");
}

function groupBy(values, key) {
  const groups = {};
  for (const value of values) {
    const name = key(value);
    if (!groups[name]) groups[name] = [];
    groups[name].push(value);
  }
  return groups;
}

export function inspectFeaturedKey(key) {
  const scenarios = key.scenarios ?? [];
  const judgedRank = Number(key.judgedRank ?? 5);
  const errors = [];
  const warnings = [];
  const bySlice = groupBy(scenarios, (scenario) => scenario.slice);
  const dense = bySlice.dense ?? [];
  const sparse = bySlice.sparse ?? [];
  const empty = bySlice.empty ?? [];
  const pan = bySlice.pan ?? [];
  const coldStart = bySlice["cold-start"] ?? [];

  if (dense.length === 0) errors.push("missing a dense-network scenario");
  if (sparse.length < 2) errors.push("needs at least two sparse-network scenarios");
  if (!sparse.some((scenario) => scenario.networkMode === "actual")) {
    errors.push("needs at least one real sparse-network viewport");
  }
  if (empty.length === 0) errors.push("missing an empty-network scenario");
  if (coldStart.length === 0) errors.push("missing a cold-start scenario");

  for (const scenario of dense) {
    if (scenario.networkMode !== "actual" || scenario.networkConfidence < 0.65) {
      errors.push(`${scenario.id} is labeled dense with confidence ${scenario.networkConfidence}`);
    }
  }
  for (const scenario of sparse) {
    if (scenario.networkConfidence <= 0 || scenario.networkConfidence >= 0.65) {
      errors.push(`${scenario.id} is labeled sparse with confidence ${scenario.networkConfidence}`);
    }
  }
  for (const scenario of [...empty, ...coldStart]) {
    if (scenario.networkConfidence !== 0) {
      errors.push(`${scenario.id} must have zero network confidence`);
    }
  }

  const panGroups = groupBy(pan, (scenario) => scenario.panGroup ?? "missing");
  if (pan.length === 0 || Object.values(panGroups).some((group) => group.length !== 2)) {
    errors.push("pan coverage must contain complete two-viewport pairs");
  }

  let privacyFailures = 0;
  let duplicateFailures = 0;
  let blindCoverageFailures = 0;
  for (const scenario of scenarios) {
    privacyFailures += Number(scenario.privacyFailures ?? 0);
    duplicateFailures += Number(scenario.duplicateFailures ?? 0);
    const judgedIDs = new Set((scenario.candidates ?? []).map((candidate) => candidate.placeId));
    const labels = (scenario.candidates ?? []).map((candidate) => candidate.label);
    if (new Set(labels).size !== labels.length) errors.push(`${scenario.id} repeats a blind label`);
    for (const pipeline of featuredPipelineNames) {
      for (const id of topIDs(scenario, pipeline, judgedRank)) {
        if (!judgedIDs.has(id)) blindCoverageFailures += 1;
      }
    }
  }
  if (privacyFailures > 0) errors.push(`${privacyFailures} privacy eligibility failures`);
  if (duplicateFailures > 0) errors.push(`${duplicateFailures} canonical duplicate failures`);
  if (blindCoverageFailures > 0) {
    errors.push(`${blindCoverageFailures} top-${judgedRank} results are absent from the blind pool`);
  }

  const rankLatencyP95Ms = percentile(
    scenarios.flatMap((scenario) => scenario.latencySamplesMs ?? []),
    0.95,
  );
  if (rankLatencyP95Ms == null || rankLatencyP95Ms >= 50) {
    errors.push(`local ranking p95 must be below 50 ms; found ${rankLatencyP95Ms}`);
  }

  const densityOrderChanged = scenarios.some((scenario) => !sameOrder(
    topIDs(scenario, "current", judgedRank),
    topIDs(scenario, "densityAware", judgedRank),
  ));
  const semanticOrderChanged = scenarios.some((scenario) => !sameOrder(
    topIDs(scenario, "densityAware", judgedRank),
    topIDs(scenario, "densitySemantic", judgedRank),
  ));
  if (!densityOrderChanged) errors.push("density-aware policy never changes a judged ranking");
  if (!semanticOrderChanged) errors.push("semantic provider never changes a judged ranking");

  const sparseMixedSourceScenarios = sparse.filter((scenario) => (
    hasMixedSources((scenario.pipelineResults.densityAware ?? []).slice(0, 24))
  )).length;
  if (sparseMixedSourceScenarios === 0) {
    errors.push("sparse coverage never exercises a network/community result blend");
  }

  const communityOnlyRate = key.stats?.candidatePlaces > 0
    ? Number(key.stats.communityOnlyPlaces ?? 0) / Number(key.stats.candidatePlaces)
    : 0;
  const actualSparseMixedSourceScenarios = sparse.filter((scenario) => (
    scenario.networkMode === "actual"
    && hasMixedSources((scenario.pipelineResults.densityAware ?? []).slice(0, 24))
  )).length;
  const minimumCommunityOnlyPlaces = 20;
  const minimumCommunityOnlyRate = 0.2;
  const communityEvidenceReady = Number(key.stats?.communityOnlyPlaces ?? 0) >= minimumCommunityOnlyPlaces
    && communityOnlyRate >= minimumCommunityOnlyRate
    && actualSparseMixedSourceScenarios >= 1;
  if (!communityEvidenceReady) {
    warnings.push(
      `Community evidence is not promotion-ready: ${key.stats?.communityOnlyPlaces ?? 0} real community-only places (${(communityOnlyRate * 100).toFixed(1)}%) and ${actualSparseMixedSourceScenarios} actual sparse mixed-source scenarios. Simulated thin/empty slices are directional.`,
    );
  }

  const panOverlapAt10 = Object.fromEntries(featuredPipelineNames.map((pipeline) => {
    const overlaps = Object.values(panGroups)
      .filter((group) => group.length === 2)
      .map(([left, right]) => overlapAt(
        left.pipelineResults[pipeline] ?? [],
        right.pipelineResults[pipeline] ?? [],
        10,
      ));
    return [pipeline, overlaps.length === 0
      ? null
      : overlaps.reduce((sum, value) => sum + value, 0) / overlaps.length];
  }));

  return {
    status: errors.length === 0 ? "pass" : "fail",
    errors,
    warnings,
    scenarioCount: scenarios.length,
    sliceCounts: Object.fromEntries(
      Object.entries(bySlice).map(([slice, rows]) => [slice, rows.length]),
    ),
    actualSparseScenarios: sparse.filter((scenario) => scenario.networkMode === "actual").length,
    simulatedThinScenarios: sparse.filter((scenario) => scenario.networkMode === "thin").length,
    sparseMixedSourceScenarios,
    actualSparseMixedSourceScenarios,
    densityOrderChanged,
    semanticOrderChanged,
    privacyFailures,
    duplicateFailures,
    blindCoverageFailures,
    rankLatencyP95Ms,
    communityOnlyRate,
    communityEvidenceReady,
    communityEvidenceThresholds: {
      minimumCommunityOnlyPlaces,
      minimumCommunityOnlyRate,
      minimumActualSparseMixedSourceScenarios: 1,
    },
    panOverlapAt10,
  };
}

export function assertFeaturedPreflight(key) {
  const preflight = inspectFeaturedKey(key);
  if (preflight.errors.length > 0) {
    throw new Error(`Featured preflight failed: ${preflight.errors.join("; ")}`);
  }
  return preflight;
}

async function main() {
  const keyPath = process.argv[2] ?? "scripts/relevance-lab/output/featured-pool-key.json";
  const key = JSON.parse(await readFile(resolve(repositoryRoot, keyPath), "utf8"));
  const preflight = inspectFeaturedKey(key);
  process.stdout.write(`${JSON.stringify(preflight, null, 2)}\n`);
  if (preflight.errors.length > 0) process.exitCode = 1;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    process.stderr.write(`Featured preflight failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
