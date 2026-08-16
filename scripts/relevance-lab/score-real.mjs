#!/usr/bin/env node

import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ndcgAt, reciprocalRank } from "./core.mjs";
import { realQueries } from "./real-data.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const pipelineNames = ["lexical", "reranked", "hybrid"];

function argumentValue(flag) {
  const index = process.argv.indexOf(flag);
  return index === -1 ? null : process.argv[index + 1] ?? null;
}

const average = (values) => values.length === 0
  ? null
  : values.reduce((sum, value) => sum + value, 0) / values.length;

const percentage = (value) => value == null ? "—" : `${(value * 100).toFixed(1)}%`;

export function parseScores(contents) {
  const scores = new Map();
  for (const [index, rawLine] of contents.split(/\r?\n/).entries()) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) continue;
    const match = /^(real-q\d+):([A-Z])=([0-3])$/.exec(line);
    if (!match) throw new Error(`Invalid score on line ${index + 1}: ${rawLine}`);
    const key = `${match[1]}:${match[2]}`;
    if (scores.has(key)) throw new Error(`Duplicate score: ${key}`);
    scores.set(key, Number(match[3]));
  }
  return scores;
}

function validateScores(key, scores) {
  const expected = new Set();
  for (const query of key.queries ?? []) {
    for (const candidate of query.candidates ?? []) {
      expected.add(`${query.id}:${candidate.label}`);
    }
  }
  const missing = [...expected].filter((name) => !scores.has(name));
  const unexpected = [...scores.keys()].filter((name) => !expected.has(name));
  if (missing.length > 0 || unexpected.length > 0) {
    const details = [
      missing.length > 0 ? `missing ${missing.join(", ")}` : null,
      unexpected.length > 0 ? `unexpected ${unexpected.join(", ")}` : null,
    ].filter(Boolean).join("; ");
    throw new Error(`Scores do not match the blind pool: ${details}`);
  }
}

function pipelineResults(query, pipeline) {
  return query.candidates
    .filter((candidate) => candidate.pipelines[pipeline] != null)
    .sort((left, right) => left.pipelines[pipeline] - right.pipelines[pipeline])
    .map((candidate) => ({ id: candidate.placeId }));
}

function scorePipeline(results, relevance) {
  const grades = results.map((result) => relevance[result.id] ?? 0);
  return {
    ndcgAt5: ndcgAt(results, relevance),
    reciprocalRank: reciprocalRank(results, relevance),
    meanTopGrade: grades.length === 0 ? 0 : grades[0],
    idealAt1: grades[0] === 3 ? 1 : 0,
    coverageAt5: Math.min(results.length, 5) / 5,
    usefulRateAt5: grades.filter((grade) => grade >= 2).length / 5,
    wrongRateAmongReturned: grades.length === 0
      ? 0
      : grades.filter((grade) => grade === 0).length / grades.length,
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
  };
}

export function scoreRealPool({ key, scores, queryIntents }) {
  validateScores(key, scores);
  const intentById = new Map(queryIntents.map(({ id, intent }) => [id, intent]));
  const perQuery = key.queries.map((query) => {
    const relevance = Object.fromEntries(query.candidates.map((candidate) => [
      candidate.placeId,
      scores.get(`${query.id}:${candidate.label}`),
    ]));
    return {
      id: query.id,
      text: query.text,
      intent: intentById.get(query.id) ?? "unknown",
      pipelines: Object.fromEntries(pipelineNames.map((pipeline) => {
        const results = pipelineResults(query, pipeline);
        return [pipeline, { results, ...scorePipeline(results, relevance) }];
      })),
    };
  });

  const pipelines = Object.fromEntries(pipelineNames.map((pipeline) => [
    pipeline,
    aggregateRows(perQuery.map((row) => row.pipelines[pipeline])),
  ]));
  const intents = [...new Set(perQuery.map(({ intent }) => intent))];
  const slices = Object.fromEntries(intents.map((intent) => [
    intent,
    Object.fromEntries(pipelineNames.map((pipeline) => [
      pipeline,
      aggregateRows(
        perQuery.filter((row) => row.intent === intent).map((row) => row.pipelines[pipeline]),
      ),
    ])),
  ]));

  const semanticGain = slices.semantic
    ? slices.semantic.hybrid.ndcgAt5 - slices.semantic.reranked.ndcgAt5
    : null;
  const guardrailRows = perQuery.filter((row) => row.intent !== "semantic");
  const rerankedGuardrail = average(guardrailRows.map((row) => row.pipelines.reranked.ndcgAt5));
  const hybridGuardrail = average(guardrailRows.map((row) => row.pipelines.hybrid.ndcgAt5));
  const guardrailRegression = rerankedGuardrail == null || hybridGuardrail == null
    ? null
    : rerankedGuardrail - hybridGuardrail;
  const vectorDecision = semanticGain != null
    && semanticGain >= 0.05
    && guardrailRegression != null
    && guardrailRegression <= 0.02
    ? "keep"
    : "defer";

  return {
    judgmentCount: scores.size,
    queryCount: perQuery.length,
    pipelines,
    slices,
    perQuery,
    decision: {
      vectorDecision,
      peopleVectorDecision: "defer",
      semanticGain,
      guardrailRegression,
      rule: "Keep place vectors only if semantic-query nDCG@5 improves by at least 0.05 and non-semantic nDCG@5 regresses by no more than 0.02.",
    },
  };
}

export function renderRealScorecard({ key, scorecard }) {
  const label = {
    lexical: "Supabase lexical",
    reranked: "Lexical + explicit rerank",
    hybrid: "Hybrid vector + rerank",
  };
  const recommendation = scorecard.decision.vectorDecision === "keep"
    ? "Place vectors earned a bounded pgvector follow-up behind the existing candidate-source interface."
    : "Do not add pgvector to the product path yet; ship lexical retrieval plus explicit reranking and keep vectors behind the offline gate.";
  const deltas = scorecard.perQuery
    .map((row) => ({
      text: row.text,
      delta: row.pipelines.hybrid.ndcgAt5 - row.pipelines.reranked.ndcgAt5,
    }))
    .sort((left, right) => right.delta - left.delta);
  const largestGain = deltas[0];
  const largestRegression = deltas.at(-1);
  const lines = [
    "# Real rec.me relevance scorecard",
    "",
    `Generated: ${new Date().toISOString()}`,
    "",
    `Blind pool: ${scorecard.judgmentCount} judgments across ${scorecard.queryCount} real-corpus queries. Source snapshot: ${key.stats.active_saves} active saves and ${key.stats.rated_saves} ratings.`,
    "",
    "## Outcome",
    "",
    `Place-vector decision: **${scorecard.decision.vectorDecision.toUpperCase()}**. ${recommendation}`,
    "",
    `People-vector decision: **${scorecard.decision.peopleVectorDecision.toUpperCase()}**. Only ${key.stats.profiles_with_5_ratings} profiles have five or more ratings, so learned person affinity is not yet an honest experiment.`,
    "",
    scorecard.decision.rule,
    "",
    `Observed semantic nDCG@5 gain over explicit reranking: ${percentage(scorecard.decision.semanticGain)}. Non-semantic guardrail regression: ${percentage(scorecard.decision.guardrailRegression)}.`,
    "",
    "This gate keeps vectors as an optional candidate source; it does not approve the current fixed hybrid weights for production.",
    "",
    "## Aggregate scorecard",
    "",
    "| Pipeline | nDCG@5 | MRR | Ideal result at #1 | Top-5 filled | Useful top-5 slots | Wrong among returned |",
    "|---|---:|---:|---:|---:|---:|---:|",
  ];
  for (const pipeline of pipelineNames) {
    const metrics = scorecard.pipelines[pipeline];
    lines.push(`| ${label[pipeline]} | ${percentage(metrics.ndcgAt5)} | ${percentage(metrics.reciprocalRank)} | ${percentage(metrics.idealAt1)} | ${percentage(metrics.coverageAt5)} | ${percentage(metrics.usefulRateAt5)} | ${percentage(metrics.wrongRateAmongReturned)} |`);
  }
  lines.push(
    "",
    "## Intent slices",
    "",
    "| Intent | Queries | Lexical nDCG@5 | Reranked nDCG@5 | Hybrid nDCG@5 | Hybrid vs reranked |",
    "|---|---:|---:|---:|---:|---:|",
  );
  for (const [intent, pipelines] of Object.entries(scorecard.slices)) {
    const count = scorecard.perQuery.filter((row) => row.intent === intent).length;
    const gain = pipelines.hybrid.ndcgAt5 - pipelines.reranked.ndcgAt5;
    lines.push(`| ${intent} | ${count} | ${percentage(pipelines.lexical.ndcgAt5)} | ${percentage(pipelines.reranked.ndcgAt5)} | ${percentage(pipelines.hybrid.ndcgAt5)} | ${percentage(gain)} |`);
  }
  lines.push(
    "",
    "## Per-query nDCG@5",
    "",
    "| Query | Intent | Lexical | Reranked | Hybrid |",
    "|---|---|---:|---:|---:|",
  );
  for (const row of scorecard.perQuery) {
    lines.push(`| ${row.text.replaceAll("|", "\\|")} | ${row.intent} | ${percentage(row.pipelines.lexical.ndcgAt5)} | ${percentage(row.pipelines.reranked.ndcgAt5)} | ${percentage(row.pipelines.hybrid.ndcgAt5)} |`);
  }
  lines.push(
    "",
    "## Architecture read",
    "",
    `- The largest hybrid gain was **${largestGain.text}** (${percentage(largestGain.delta)} versus explicit reranking).`,
    `- The largest hybrid regression was **${largestRegression.text}** (${percentage(largestRegression.delta)}). The production ranker needs intent-dependent source weights and must preserve strong lexical evidence.`,
    "- Keep lexical, semantic, explicit taste/social, and community retrieval as separate bounded candidate providers. Hard filters run before their union; one deterministic ranker owns the final order and the personal ↔ community dial.",
    "- Let the conversational LLM produce a typed query plan. Do not put an LLM in the synchronous ranking loop.",
    "- Add pgvector only behind the semantic provider seam and feature flag, then rerun this same blind scorecard after weight changes.",
    "",
    "## Limits",
    "",
    "- This is one judge and 12 queries, so it is a directional architecture gate, not a statistically stable relevance benchmark.",
    "- Every top-five result from every pipeline was judged, but results outside that pooled candidate set were not. This compares ordering and candidate recovery inside the tested pool; it does not establish absolute corpus recall.",
    "- The scorecard tests place/query embeddings. It does not test learned people embeddings or an LLM ranker.",
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
  const keyPath = argumentValue("--key") ?? "scripts/relevance-lab/output/real-pool-key.json";
  const scoresPath = argumentValue("--scores") ?? "scripts/relevance-lab/output/real-scores.txt";
  const reportPath = argumentValue("--write-report");
  const jsonPath = argumentValue("--write-json");
  const [keyContents, scoreContents] = await Promise.all([
    readFile(resolve(repositoryRoot, keyPath), "utf8"),
    readFile(resolve(repositoryRoot, scoresPath), "utf8"),
  ]);
  const key = JSON.parse(keyContents);
  const scores = parseScores(scoreContents);
  const scorecard = scoreRealPool({ key, scores, queryIntents: realQueries });
  const report = renderRealScorecard({ key, scorecard });

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
    process.stderr.write(`Real relevance scoring failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
