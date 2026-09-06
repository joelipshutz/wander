#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ndcgAt, reciprocalRank } from "./core.mjs";
import { featuredPipelineNames, overlapAt } from "./featured-core.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

function argumentValue(flag) {
  const index = process.argv.indexOf(flag);
  return index === -1 ? null : process.argv[index + 1] ?? null;
}

const average = (values) => values.length === 0
  ? null
  : values.reduce((sum, value) => sum + value, 0) / values.length;

const percentage = (value) => value == null ? "—" : `${(value * 100).toFixed(1)}%`;

const milliseconds = (value) => value == null ? "—" : `${value.toFixed(2)} ms`;

function percentile(values, fraction) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)];
}

function haversineKilometers(left, right) {
  const radians = (value) => value * Math.PI / 180;
  const earthRadius = 6371;
  const latitudeDelta = radians(right.latitude - left.latitude);
  const longitudeDelta = radians(right.longitude - left.longitude);
  const a = Math.sin(latitudeDelta / 2) ** 2
    + Math.cos(radians(left.latitude)) * Math.cos(radians(right.latitude))
    * Math.sin(longitudeDelta / 2) ** 2;
  return 2 * earthRadius * Math.asin(Math.sqrt(a));
}

export function parseFeaturedScores(contents) {
  const scores = new Map();
  for (const [index, rawLine] of contents.split(/\r?\n/).entries()) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const match = /^(featured-q\d+):([A-L])=([0-3Xx])$/.exec(line);
    if (!match) throw new Error(`Invalid Featured score on line ${index + 1}: ${rawLine}`);
    const key = `${match[1]}:${match[2]}`;
    if (scores.has(key)) throw new Error(`Duplicate Featured score: ${key}`);
    scores.set(key, match[3].toUpperCase() === "X" ? null : Number(match[3]));
  }
  return scores;
}

function validateScores(key, scores) {
  const expected = new Set();
  for (const scenario of key.scenarios ?? []) {
    for (const candidate of scenario.candidates ?? []) {
      expected.add(`${scenario.id}:${candidate.label}`);
    }
  }
  const missing = [...expected].filter((name) => !scores.has(name));
  const unexpected = [...scores.keys()].filter((name) => !expected.has(name));
  if (missing.length > 0 || unexpected.length > 0) {
    const details = [
      missing.length > 0 ? `missing ${missing.join(", ")}` : null,
      unexpected.length > 0 ? `unexpected ${unexpected.join(", ")}` : null,
    ].filter(Boolean).join("; ");
    throw new Error(`Scores do not match the Featured blind pool: ${details}`);
  }
}

function judgedPipelineResults(scenario, pipeline, at) {
  return scenario.candidates
    .filter((candidate) => (
      candidate.pipelines[pipeline] != null && candidate.pipelines[pipeline] <= at
    ))
    .sort((left, right) => left.pipelines[pipeline] - right.pipelines[pipeline])
    .map((candidate) => ({ id: candidate.placeId }));
}

function scoreRanking(results, relevance, at) {
  const grades = results.map((result) => relevance[result.id] ?? 0);
  return {
    ndcgAt5: ndcgAt(results, relevance, at),
    reciprocalRank: reciprocalRank(results, relevance),
    meanTopGrade: grades.length === 0 ? 0 : grades[0],
    idealAt1: grades[0] === 3 ? 1 : 0,
    coverageAt5: Math.min(results.length, at) / at,
    usefulRateAt5: grades.filter((grade) => grade >= 2).length / at,
    wrongRateAmongReturned: grades.length === 0
      ? 0
      : grades.filter((grade) => grade === 0).length / grades.length,
  };
}

function sourceMetrics(rows) {
  const top = rows.slice(0, 24);
  const contributors = new Set(top.flatMap((row) => row.contributorIds));
  const pairDistances = [];
  for (let left = 0; left < top.length; left += 1) {
    for (let right = left + 1; right < top.length; right += 1) {
      pairDistances.push(haversineKilometers(top[left], top[right]));
    }
  }
  return {
    networkRateAt24: top.length === 0
      ? 0
      : top.filter((row) => row.source === "network").length / top.length,
    communityRateAt24: top.length === 0
      ? 0
      : top.filter((row) => row.source === "community").length / top.length,
    distinctTrustedContributorsAt24: contributors.size,
    meanPairDistanceKmAt24: average(pairDistances) ?? 0,
  };
}

function aggregateRows(rows) {
  return {
    ndcgAt5: average(rows.map((row) => row.ndcgAt5)),
    reciprocalRank: average(rows.map((row) => row.reciprocalRank)),
    meanTopGrade: average(rows.map((row) => row.meanTopGrade)),
    idealAt1: average(rows.map((row) => row.idealAt1)),
    coverageAt5: average(rows.map((row) => row.coverageAt5)),
    usefulRateAt5: average(rows.map((row) => row.usefulRateAt5)),
    wrongRateAmongReturned: average(rows.map((row) => row.wrongRateAmongReturned)),
    networkRateAt24: average(rows.map((row) => row.networkRateAt24)),
    communityRateAt24: average(rows.map((row) => row.communityRateAt24)),
    distinctTrustedContributorsAt24: average(rows.map((row) => row.distinctTrustedContributorsAt24)),
    meanPairDistanceKmAt24: average(rows.map((row) => row.meanPairDistanceKmAt24)),
  };
}

function panOverlapByPipeline(scenarios) {
  const groups = new Map();
  for (const scenario of scenarios.filter(({ panGroup }) => panGroup)) {
    if (!groups.has(scenario.panGroup)) groups.set(scenario.panGroup, []);
    groups.get(scenario.panGroup).push(scenario);
  }
  return Object.fromEntries(featuredPipelineNames.map((pipeline) => {
    const overlaps = [...groups.values()]
      .filter((group) => group.length === 2)
      .map(([left, right]) => overlapAt(
        left.pipelineResults[pipeline],
        right.pipelineResults[pipeline],
        10,
      ));
    return [pipeline, average(overlaps)];
  }));
}

export function scoreFeaturedPool({ key, scores }) {
  validateScores(key, scores);
  const judgedRank = Number(key.judgedRank ?? 5);
  const excludedScenarios = key.scenarios.flatMap((scenario) => {
    const unknownCandidates = scenario.candidates
      .filter((candidate) => scores.get(`${scenario.id}:${candidate.label}`) == null)
      .map((candidate) => candidate.label);
    return unknownCandidates.length === 0 ? [] : [{ id: scenario.id, unknownCandidates }];
  });
  const excludedScenarioIds = new Set(excludedScenarios.map(({ id }) => id));
  const scoredScenarios = key.scenarios.filter(({ id }) => !excludedScenarioIds.has(id));
  if (scoredScenarios.length === 0) {
    throw new Error("Featured scores do not contain one fully judged scenario.");
  }
  const perScenario = scoredScenarios.map((scenario) => {
    const relevance = Object.fromEntries(scenario.candidates.map((candidate) => [
      candidate.placeId,
      scores.get(`${scenario.id}:${candidate.label}`),
    ]));
    return {
      ...scenario,
      pipelines: Object.fromEntries(featuredPipelineNames.map((pipeline) => {
        const results = judgedPipelineResults(scenario, pipeline, judgedRank);
        return [pipeline, {
          results,
          ...scoreRanking(results, relevance, judgedRank),
          ...sourceMetrics(scenario.pipelineResults[pipeline]),
        }];
      })),
    };
  });

  const pipelines = Object.fromEntries(featuredPipelineNames.map((pipeline) => [
    pipeline,
    aggregateRows(perScenario.map((scenario) => scenario.pipelines[pipeline])),
  ]));
  const slices = Object.fromEntries([...new Set(perScenario.map(({ slice }) => slice))].map((slice) => [
    slice,
    Object.fromEntries(featuredPipelineNames.map((pipeline) => [
      pipeline,
      aggregateRows(
        perScenario.filter((scenario) => scenario.slice === slice).map((scenario) => scenario.pipelines[pipeline]),
      ),
    ])),
  ]));
  const sparseEmpty = perScenario.filter((scenario) => (
    scenario.slice === "sparse" || scenario.slice === "empty" || scenario.slice === "cold-start"
  ));
  const dense = perScenario.filter((scenario) => scenario.slice === "dense");
  const aggregateFor = (rows, pipeline) => aggregateRows(rows.map((row) => row.pipelines[pipeline]));
  const currentSparseEmpty = aggregateFor(sparseEmpty, "current");
  const densitySparseEmpty = aggregateFor(sparseEmpty, "densityAware");
  const semanticSparseEmpty = aggregateFor(sparseEmpty, "densitySemantic");
  const currentDense = aggregateFor(dense, "current");
  const densityDense = aggregateFor(dense, "densityAware");
  const semanticDense = aggregateFor(dense, "densitySemantic");
  const panOverlap = panOverlapByPipeline(key.scenarios);
  const privacyFailures = key.scenarios.reduce(
    (sum, scenario) => sum + Number(scenario.privacyFailures ?? 0),
    0,
  );
  const duplicateFailures = key.scenarios.reduce(
    (sum, scenario) => sum + Number(scenario.duplicateFailures ?? 0),
    0,
  );
  const rankLatencyP95Ms = percentile(
    key.scenarios.flatMap((scenario) => scenario.latencySamplesMs ?? []),
    0.95,
  );
  const densitySparseEmptyGain = densitySparseEmpty.ndcgAt5 - currentSparseEmpty.ndcgAt5;
  const densityDenseRegression = currentDense.ndcgAt5 - densityDense.ndcgAt5;
  const densityPanRegression = panOverlap.current == null || panOverlap.densityAware == null
    ? null
    : panOverlap.current - panOverlap.densityAware;
  const semanticSparseEmptyGain = semanticSparseEmpty.ndcgAt5 - densitySparseEmpty.ndcgAt5;
  const semanticDenseRegression = densityDense.ndcgAt5 - semanticDense.ndcgAt5;
  const semanticPanRegression = panOverlap.densityAware == null || panOverlap.densitySemantic == null
    ? null
    : panOverlap.densityAware - panOverlap.densitySemantic;
  const communityEvidenceReady = key.preflight?.communityEvidenceReady ?? true;
  const judgmentCoverageReady = excludedScenarios.length === 0;
  const sharedGate = privacyFailures === 0
    && duplicateFailures === 0
    && rankLatencyP95Ms != null
    && rankLatencyP95Ms < 50
    && communityEvidenceReady
    && judgmentCoverageReady;
  const densityDecision = sharedGate
    && densitySparseEmptyGain >= 0.05
    && densityDenseRegression <= 0.02
    && densityPanRegression != null
    && densityPanRegression <= 0.1
    ? "keep"
    : "defer";
  const semanticDecision = sharedGate
    && semanticSparseEmptyGain >= 0.05
    && semanticDenseRegression <= 0.02
    && semanticPanRegression != null
    && semanticPanRegression <= 0.1
    ? "keep"
    : "defer";

  return {
    judgmentCount: [...scores.values()].filter((score) => score != null).length,
    unknownJudgmentCount: [...scores.values()].filter((score) => score == null).length,
    scenarioCount: key.scenarios.length,
    scoredScenarioCount: perScenario.length,
    excludedScenarios,
    pipelines,
    slices,
    perScenario,
    panOverlapAt10: panOverlap,
    guardrails: {
      privacyFailures,
      duplicateFailures,
      rankLatencyP95Ms,
      communityEvidenceReady,
      judgmentCoverageReady,
      communityOnlyPlaces: Number(key.stats?.communityOnlyPlaces ?? 0),
      communityOnlyRate: key.preflight?.communityOnlyRate ?? null,
      actualSparseMixedSourceScenarios:
        Number(key.preflight?.actualSparseMixedSourceScenarios ?? 0),
    },
    decision: {
      densityDecision,
      semanticDecision,
      peopleVectorDecision: "defer",
      densitySparseEmptyGain,
      densityDenseRegression,
      densityPanRegression,
      semanticSparseEmptyGain,
      semanticDenseRegression,
      semanticPanRegression,
      rule: "Keep a new Featured policy only with promotion-ready real community evidence, zero privacy/duplicate failures, local rank p95 below 50 ms, at least +0.05 sparse/empty nDCG@5, no more than 0.02 dense nDCG@5 regression, and no more than 0.10 pan-overlap regression.",
    },
  };
}

export function renderFeaturedScorecard({ key, scorecard }) {
  const labels = {
    current: "Current explicit baseline",
    networkOnly: "Trusted network only",
    fixedBlend: "Fixed network/community blend",
    densityAware: "Density-aware blend",
    densitySemantic: "Density-aware + place semantics",
  };
  const lines = [
    "# Real rec.me Featured relevance scorecard",
    "",
    `Generated: ${new Date().toISOString()}`,
    "",
    `Blind pool: ${scorecard.judgmentCount} numeric judgments and ${scorecard.unknownJudgmentCount} explicit unknown${scorecard.unknownJudgmentCount === 1 ? "" : "s"}. Scored ${scorecard.scoredScenarioCount} of ${scorecard.scenarioCount} real viewer-plus-viewport scenarios. Snapshot: ${key.stats.candidatePlaces} eligible places, ${key.stats.candidateSaves} privacy-eligible Been saves, and ${key.stats.tastePlaces} positive/Wanna taste places.`,
    "",
    "## Outcome",
    "",
    `Density-aware policy: **${scorecard.decision.densityDecision.toUpperCase()}**. Place-semantic provider for Featured: **${scorecard.decision.semanticDecision.toUpperCase()}**.`,
    "",
    scorecard.decision.rule,
    "",
    `Density-aware sparse/empty gain: ${percentage(scorecard.decision.densitySparseEmptyGain)}; dense regression: ${percentage(scorecard.decision.densityDenseRegression)}; pan-overlap regression: ${percentage(scorecard.decision.densityPanRegression)}.`,
    "",
    `Semantic sparse/empty gain over density-aware: ${percentage(scorecard.decision.semanticSparseEmptyGain)}; dense regression: ${percentage(scorecard.decision.semanticDenseRegression)}; pan-overlap regression: ${percentage(scorecard.decision.semanticPanRegression)}.`,
    "",
    `Guardrails: ${scorecard.guardrails.privacyFailures} privacy failures, ${scorecard.guardrails.duplicateFailures} duplicate failures, local ranking p95 ${milliseconds(scorecard.guardrails.rankLatencyP95Ms)}.`,
    "",
    `Community evidence: **${scorecard.guardrails.communityEvidenceReady ? "READY" : "INSUFFICIENT"}** — ${scorecard.guardrails.communityOnlyPlaces} real community-only places (${percentage(scorecard.guardrails.communityOnlyRate)}) and ${scorecard.guardrails.actualSparseMixedSourceScenarios} actual sparse mixed-source scenarios. Simulated thin/empty slices are directional and cannot independently earn KEEP.`,
    "",
    `Judgment coverage: **${scorecard.guardrails.judgmentCoverageReady ? "COMPLETE" : "INCOMPLETE"}**${scorecard.excludedScenarios.length === 0 ? "." : ` — excluded ${scorecard.excludedScenarios.map(({ id, unknownCandidates }) => `${id} (${unknownCandidates.join(", ")})`).join("; ")} rather than treating unknown places as irrelevant.`}`,
    "",
    "People-vector decision remains **DEFER**. This benchmark uses explicit graph and taste evidence, not learned people embeddings.",
    "",
    "## Aggregate scorecard",
    "",
    "| Policy | nDCG@5 | Ideal at #1 | Useful top-5 | Wrong among returned | Network share @24 | Community share @24 | Trusted contributors @24 |",
    "|---|---:|---:|---:|---:|---:|---:|---:|",
  ];
  for (const pipeline of featuredPipelineNames) {
    const metrics = scorecard.pipelines[pipeline];
    lines.push(`| ${labels[pipeline]} | ${percentage(metrics.ndcgAt5)} | ${percentage(metrics.idealAt1)} | ${percentage(metrics.usefulRateAt5)} | ${percentage(metrics.wrongRateAmongReturned)} | ${percentage(metrics.networkRateAt24)} | ${percentage(metrics.communityRateAt24)} | ${metrics.distinctTrustedContributorsAt24.toFixed(1)} |`);
  }
  lines.push(
    "",
    "## Scenario slices",
    "",
    "| Slice | Scenarios | Current | Network only | Fixed blend | Density-aware | Density + semantics |",
    "|---|---:|---:|---:|---:|---:|---:|",
  );
  for (const [slice, pipelines] of Object.entries(scorecard.slices)) {
    const count = scorecard.perScenario.filter((scenario) => scenario.slice === slice).length;
    lines.push(`| ${slice} | ${count} | ${percentage(pipelines.current.ndcgAt5)} | ${percentage(pipelines.networkOnly.ndcgAt5)} | ${percentage(pipelines.fixedBlend.ndcgAt5)} | ${percentage(pipelines.densityAware.ndcgAt5)} | ${percentage(pipelines.densitySemantic.ndcgAt5)} |`);
  }
  lines.push(
    "",
    "## Pan stability",
    "",
    "| Policy | Top-10 overlap across the small pan |",
    "|---|---:|",
  );
  for (const pipeline of featuredPipelineNames) {
    lines.push(`| ${labels[pipeline]} | ${percentage(scorecard.panOverlapAt10[pipeline])} |`);
  }
  lines.push(
    "",
    "## Limits",
    "",
    "- This is one viewer/judge and a small real corpus. It is an architecture promotion gate, not a population-level recommendation benchmark.",
    "- Every top-five candidate from every policy was pooled. A scenario with any explicit unknown judgment is excluded from judged ranking metrics rather than converting missing knowledge into a false relevance grade; incomplete coverage blocks policy promotion.",
    "- Source-mix, contributor-diversity, geographic-dispersion, latency, privacy, duplicate, and pan metrics use the full bounded top-24 output.",
    "- Empty-network and cold-start slices intentionally mask the real viewer's network, while retaining the same privacy-eligible canonical corpus. They test fallback behavior without inventing places or stranger content.",
    "- Offline ranking latency excludes mobile networking and rendering. Production implementation still needs RPC p50/p95 and no-flicker map instrumentation.",
    "- A KEEP result approves only a bounded implementation trial behind a policy/provider flag. It does not approve people embeddings, LLM ranking, or an unconditional production rollout.",
  );
  return `${lines.join("\n")}\n`;
}

async function writeArtifact(path, contents) {
  const absolutePath = resolve(repositoryRoot, path);
  await mkdir(dirname(absolutePath), { recursive: true });
  await writeFile(absolutePath, contents, "utf8");
  return absolutePath;
}

async function main() {
  const keyPath = argumentValue("--key") ?? "scripts/relevance-lab/output/featured-pool-key.json";
  const scoresPath = argumentValue("--scores") ?? "scripts/relevance-lab/output/featured-scores.txt";
  const reportPath = argumentValue("--write-report");
  const jsonPath = argumentValue("--write-json");
  const [keyContents, scoreContents] = await Promise.all([
    readFile(resolve(repositoryRoot, keyPath), "utf8"),
    readFile(resolve(repositoryRoot, scoresPath), "utf8"),
  ]);
  const key = JSON.parse(keyContents);
  const scores = parseFeaturedScores(scoreContents);
  const scorecard = scoreFeaturedPool({ key, scores });
  const report = renderFeaturedScorecard({ key, scorecard });

  if (reportPath) {
    process.stdout.write(`Report: ${await writeArtifact(reportPath, report)}\n`);
  } else {
    process.stdout.write(report);
  }
  if (jsonPath) {
    process.stdout.write(`JSON: ${await writeArtifact(jsonPath, `${JSON.stringify(scorecard, null, 2)}\n`)}\n`);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    process.stderr.write(`Featured relevance scoring failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
