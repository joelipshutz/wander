#!/usr/bin/env node

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import { runExperiment } from "./core.mjs";
import { createEmbeddingMaps } from "./embeddings.mjs";
import { fixtureVersion, places, queries, viewerProfile } from "./fixtures.mjs";
import { withSupabaseProviders } from "./supabase.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");

function argumentValue(flag) {
  const index = process.argv.indexOf(flag);
  return index === -1 ? null : process.argv[index + 1] ?? null;
}

const percentage = (value) => `${(value * 100).toFixed(1)}%`;
const milliseconds = (value) => `${value.toFixed(1)} ms`;

function resultNames(results, placesById) {
  if (results.length === 0) return "—";
  return results.map((result) => placesById.get(result.id)?.name ?? result.id).join(" → ");
}

function renderReport({ experiment, embedding, totalLatencyMs }) {
  const placesById = new Map(places.map((place) => [place.id, place]));
  const generatedAt = new Date().toISOString();
  const pipelineLabel = {
    lexical: "Supabase lexical",
    reranked: "Lexical + explicit rerank",
    hybrid: "Hybrid vector + rerank",
  };
  const recommendation = experiment.decision.vectorDecision === "keep"
    ? "Vectors earned the next experiment: add pgvector behind the same candidate-source interface, then rerun this scorecard on anonymized real judgments before product integration."
    : "Do not add pgvector yet. Keep lexical retrieval plus explicit social/community reranking, improve the corpus and judgments, and rerun before paying the vector-system cost.";

  const lines = [
    "# rec.me relevance evaluator",
    "",
    `Generated: ${generatedAt}`,
    "",
    `Fixture: ${fixtureVersion}; ${places.length} fictional places; ${queries.length} fixed queries.`,
    "",
    "## Outcome",
    "",
    `Vector decision: **${experiment.decision.vectorDecision.toUpperCase()}**. ${recommendation}`,
    "",
    `People-vector decision: **${experiment.decision.peopleVectorDecision.toUpperCase()}**. ${experiment.decision.peopleVectorReason}`,
    "",
    experiment.decision.rule,
    "",
    `Observed semantic nDCG@5 gain over explicit reranking: ${percentage(experiment.decision.semanticGain)}. Named-person regression: ${percentage(experiment.decision.namedPersonRegression)}.`,
    "",
    "This is an architecture gate, not a production-quality claim: the dataset is fictional and intentionally small.",
    "",
    "## Aggregate scorecard",
    "",
    "| Pipeline | nDCG@5 | MRR | Semantic nDCG@5 | Named-person nDCG@5 | Community nDCG@5 | Constraint failures | Mean query time |",
    "|---|---:|---:|---:|---:|---:|---:|---:|",
  ];

  for (const [pipeline, metrics] of Object.entries(experiment.pipelines)) {
    lines.push(
      `| ${pipelineLabel[pipeline]} | ${percentage(metrics.ndcgAt5)} | ${percentage(metrics.mrr)} | ${percentage(metrics.semanticNdcgAt5)} | ${percentage(metrics.namedPersonNdcgAt5)} | ${percentage(metrics.communityNdcgAt5)} | ${metrics.constraintFailures} | ${milliseconds(metrics.meanLatencyMs)} |`,
    );
  }

  lines.push(
    "",
    "## Per-query results",
    "",
    "| Query | Intent | Lexical top 5 | Reranked top 5 | Hybrid top 5 | nDCG@5 (L / R / H) |",
    "|---|---|---|---|---|---:|",
  );

  for (const row of experiment.perQuery) {
    lines.push(
      `| ${row.text.replaceAll("|", "\\|")} | ${row.intent} | ${resultNames(row.pipelines.lexical.results, placesById)} | ${resultNames(row.pipelines.reranked.results, placesById)} | ${resultNames(row.pipelines.hybrid.results, placesById)} | ${percentage(row.pipelines.lexical.ndcgAt5)} / ${percentage(row.pipelines.reranked.ndcgAt5)} / ${percentage(row.pipelines.hybrid.ndcgAt5)} |`,
    );
  }

  lines.push(
    "",
    "## What ran",
    "",
    "- Supabase PostgreSQL held the fictional corpus in a temporary table inside one transaction.",
    "- PostgreSQL `simple` full-text search produced lexical candidates using the same weighted-field shape as REC-225.",
    "- OpenAI produced embeddings once; exact cosine retrieval ran in PostgreSQL over temporary arrays. No pgvector extension or persistent vector table was required.",
    "- A deterministic ranker blended lexical, semantic, explicit viewer-taste, trusted-person, community, and proximity features. Hard constraints were applied before candidate ranking.",
    "- The transaction rolled back and the database connection closed after evaluation. No production rows, functions, indexes, or schema objects persisted.",
    "",
    "## Cost and timing",
    "",
    `- Embedding model: \`${embedding.model}\``,
    `- Embedding cache: ${embedding.cacheHits} hits, ${embedding.cacheMisses} misses`,
    `- Embedding request/cache time: ${milliseconds(embedding.latencyMs)}`,
    `- Total evaluator time: ${milliseconds(totalLatencyMs)}`,
    "",
    "## Maintainable production boundary",
    "",
    "Keep four separable modules: query plan, candidate sources, deterministic ranker, and evaluation. The LLM may translate conversation into a typed query plan, but it does not rank places. Candidate sources can be enabled independently, and one set of weights controls the personal ↔ community dial.",
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
  const reportPath = argumentValue("--write-report");
  const jsonPath = argumentValue("--write-json");
  const startedAt = performance.now();
  const embedding = await createEmbeddingMaps({ places, queries });
  const experiment = await withSupabaseProviders(
    places,
    embedding.placeEmbeddings,
    embedding.queryEmbeddings,
    ({ lexicalProvider, semanticProvider }) => runExperiment({
      places,
      queries,
      lexicalProvider,
      semanticProvider,
      viewerProfile,
    }),
  );
  const totalLatencyMs = performance.now() - startedAt;
  const report = renderReport({ experiment, embedding, totalLatencyMs });

  if (reportPath) {
    const writtenPath = await writeArtifact(reportPath, report);
    process.stdout.write(`Report: ${writtenPath}\n`);
  } else {
    process.stdout.write(report);
  }

  if (jsonPath) {
    const writtenPath = await writeArtifact(
      jsonPath,
      `${JSON.stringify({ fixtureVersion, experiment, embedding: {
        model: embedding.model,
        cacheHits: embedding.cacheHits,
        cacheMisses: embedding.cacheMisses,
        latencyMs: embedding.latencyMs,
      }, totalLatencyMs }, null, 2)}\n`,
    );
    process.stdout.write(`JSON: ${writtenPath}\n`);
  }
}

main().catch((error) => {
  process.stderr.write(`Relevance evaluator failed: ${error.message}\n`);
  process.exitCode = 1;
});
