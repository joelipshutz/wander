#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import {
  attachSemanticTasteScores,
  averageEmbedding,
  buildFeaturedTasteProfile,
  candidatesInViewport,
  featuredPipelineNames,
  generateFeaturedScenarios,
  rankFeaturedScenario,
} from "./featured-core.mjs";
import { loadFeaturedRealData } from "./featured-real-data.mjs";
import { createEmbeddingMaps } from "./embeddings.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const defaultJudgmentsPath = "scripts/relevance-lab/output/featured-judgments.md";
const defaultHtmlPath = "scripts/relevance-lab/output/featured-judgments.html";
const defaultKeyPath = "scripts/relevance-lab/output/featured-pool-key.json";
const judgedRank = 5;
const maximumPooledCandidates = 12;

function argumentValue(flag, fallback = null) {
  const index = process.argv.indexOf(flag);
  return index === -1 ? fallback : process.argv[index + 1] ?? fallback;
}

function stableNumber(value) {
  return Number.parseInt(createHash("sha256").update(value).digest("hex").slice(0, 12), 16);
}

function pooledCandidateIds(experiment, limit = maximumPooledCandidates) {
  const selected = [];
  for (let rank = 0; rank < judgedRank && selected.length < limit; rank += 1) {
    for (const pipeline of featuredPipelineNames) {
      const id = experiment.pipelines[pipeline][rank]?.id;
      if (id && !selected.includes(id)) selected.push(id);
      if (selected.length === limit) break;
    }
  }
  return selected.sort(
    (left, right) => stableNumber(`${experiment.id}:${left}`) - stableNumber(`${experiment.id}:${right}`),
  );
}

function percentile(values, fraction) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  return sorted[Math.min(sorted.length - 1, Math.ceil(sorted.length * fraction) - 1)];
}

function benchmarkScenario({ candidates, scenario, tasteProfile }) {
  for (let index = 0; index < 5; index += 1) {
    rankFeaturedScenario({ candidates, scenario, tasteProfile });
  }
  const samples = [];
  let result = null;
  for (let index = 0; index < 30; index += 1) {
    result = rankFeaturedScenario({ candidates, scenario, tasteProfile });
    samples.push(result.latencyMs);
  }
  return {
    ...result,
    latencySamplesMs: samples,
    latencyP95Ms: percentile(samples, 0.95),
  };
}

function embeddingPlace(place) {
  return {
    ...place,
    neighborhood: place.neighborhood ?? place.locality ?? "",
    city: place.city ?? place.region ?? "",
    description: "",
  };
}

function mapsUrl(place) {
  const query = [place.name, place.locality, place.region].filter(Boolean).join(", ");
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}

function escapeTable(value) {
  return String(value).replaceAll("|", "\\|");
}

function candidateContext(place) {
  return [place.subcategory || place.category.replaceAll("_", " "), place.locality, place.region]
    .filter(Boolean)
    .join(" · ");
}

function safePipelineRows(rows) {
  return rows.map((row, index) => ({
    placeId: row.id,
    rank: index + 1,
    source: row.source,
    contributorIds: row.contributorIds,
    latitude: row.latitude,
    longitude: row.longitude,
  }));
}

function renderJudgments({ experiments, candidates, stats, embedding }) {
  const placesById = new Map(candidates.map((place) => [place.id, place]));
  const lines = [
    "# Real rec.me Featured judgments",
    "",
    "Replace each `?` with one grade:",
    "",
    "- `3` — ideal Featured pin for you in this map area",
    "- `2` — good and useful Featured pin",
    "- `1` — weak filler but defensible",
    "- `0` — wrong, unhelpful, or misleading",
    "",
    "Judge according to your taste and the map area, not retrieval source or general fame. There is no text query. Candidate order is randomized and every retrieval policy is hidden.",
    "",
    `Snapshot: ${stats.candidatePlaces} eligible canonical places from ${stats.candidateSaves} privacy-eligible Been saves; viewer taste uses ${stats.tastePlaces} positive/Wanna places.`,
    "",
  ];
  const key = {
    generatedAt: new Date().toISOString(),
    policyVersion: "featured-offline-v1",
    judgedRank,
    stats,
    embedding: {
      model: embedding.model,
      cacheHits: embedding.cacheHits,
      cacheMisses: embedding.cacheMisses,
    },
    scenarios: [],
  };

  experiments.forEach((experiment, scenarioIndex) => {
    const ids = pooledCandidateIds(experiment);
    if (ids.length < 3) {
      throw new Error(`${experiment.id} produced only ${ids.length} unique Featured candidates.`);
    }
    const scenarioCandidates = ids.map((id, candidateIndex) => {
      const place = placesById.get(id);
      const label = String.fromCharCode(65 + candidateIndex);
      const pipelines = Object.fromEntries(featuredPipelineNames.map((pipeline) => {
        const rank = experiment.pipelines[pipeline].findIndex((result) => result.id === id);
        return [pipeline, rank === -1 ? null : rank + 1];
      }));
      return { label, place, pipelines };
    });

    lines.push(
      `## ${scenarioIndex + 1}. Featured pins around ${experiment.title}`,
      "",
      "| Candidate | Place | Context | Grade |",
      "|---|---|---|---:|",
    );
    for (const candidate of scenarioCandidates) {
      lines.push(
        `| ${candidate.label} | [${escapeTable(candidate.place.name)}](${mapsUrl(candidate.place)}) | ${escapeTable(candidateContext(candidate.place))} | ? |`,
      );
    }
    lines.push("");

    key.scenarios.push({
      id: experiment.id,
      title: experiment.title,
      slice: experiment.slice,
      networkMode: experiment.networkMode,
      tasteMode: experiment.tasteMode,
      panGroup: experiment.panGroup ?? null,
      viewport: experiment.viewport,
      candidateCount: experiment.candidateCount,
      networkConfidence: experiment.confidence,
      latencySamplesMs: experiment.latencySamplesMs,
      latencyP95Ms: experiment.latencyP95Ms,
      privacyFailures: experiment.privacyFailures,
      duplicateFailures: experiment.duplicateFailures,
      pipelineResults: Object.fromEntries(featuredPipelineNames.map((pipeline) => [
        pipeline,
        safePipelineRows(experiment.pipelines[pipeline]),
      ])),
      candidates: scenarioCandidates.map(({ label, place, pipelines }) => ({
        label,
        placeId: place.id,
        pipelines,
      })),
    });
  });

  return { markdown: `${lines.join("\n")}\n`, key };
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function renderHtml({ key, candidates }) {
  const placesById = new Map(candidates.map((place) => [place.id, place]));
  const cards = key.scenarios.map((scenario, scenarioIndex) => {
    const rows = scenario.candidates.map((candidate) => {
      const place = placesById.get(candidate.placeId);
      const name = `${scenario.id}:${candidate.label}`;
      const buttons = [0, 1, 2, 3].map((grade) => `
        <label class="grade grade-${grade}">
          <input type="radio" name="${escapeHtml(name)}" value="${grade}" data-judgment>
          <span>${grade}</span>
        </label>`).join("");
      return `
        <div class="candidate">
          <div class="place">
            <span class="letter">${candidate.label}</span>
            <div><a href="${mapsUrl(place)}" target="_blank" rel="noreferrer">${escapeHtml(place.name)}</a><small>${escapeHtml(candidateContext(place))}</small></div>
          </div>
          <div class="grades">${buttons}</div>
        </div>`;
    }).join("");
    return `
      <section class="scenario">
        <h2>${scenarioIndex + 1}. Featured pins around ${escapeHtml(scenario.title)}</h2>
        ${rows}
      </section>`;
  }).join("");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Real rec.me Featured judgments</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f4efe7; color: #2c211b; }
    body { margin: 0 auto; max-width: 880px; padding: 24px 16px 120px; }
    header { background: #fffaf2; border: 1px solid #dfd3c4; border-radius: 18px; padding: 20px; margin-bottom: 18px; }
    h1 { margin: 0 0 10px; font-size: 28px; }
    p { line-height: 1.45; margin: 6px 0; }
    .rubric { font-size: 14px; color: #65584e; }
    .scenario { background: white; border: 1px solid #e4d9cc; border-radius: 18px; margin: 14px 0; padding: 18px; }
    h2 { font-size: 19px; margin: 0 0 12px; }
    .candidate { display: flex; align-items: center; justify-content: space-between; gap: 12px; border-top: 1px solid #eee5dc; padding: 12px 0; }
    .place { display: flex; align-items: center; gap: 10px; min-width: 0; }
    .letter { width: 28px; height: 28px; border-radius: 8px; display: grid; place-items: center; flex: 0 0 auto; background: #f2e4d7; font-weight: 700; }
    a { color: #7d3f2c; font-weight: 650; text-decoration: none; }
    small { display: block; color: #74675e; margin-top: 3px; }
    .grades { display: flex; gap: 5px; flex: 0 0 auto; }
    .grade input { position: absolute; opacity: 0; pointer-events: none; }
    .grade span { width: 34px; height: 34px; border: 1px solid #d7c8b9; border-radius: 9px; display: grid; place-items: center; cursor: pointer; font-weight: 650; }
    .grade input:checked + span { color: white; border-color: #9b4e37; background: #9b4e37; }
    .bar { position: fixed; z-index: 2; left: 0; right: 0; bottom: 0; padding: 12px 16px calc(12px + env(safe-area-inset-bottom)); background: rgba(255,250,242,.96); border-top: 1px solid #d8cbbd; backdrop-filter: blur(10px); }
    .bar-inner { max-width: 880px; margin: auto; display: flex; align-items: center; justify-content: space-between; gap: 12px; }
    button { border: 0; border-radius: 11px; padding: 11px 16px; background: #9b4e37; color: white; font-size: 15px; font-weight: 700; cursor: pointer; }
    #status { font-size: 14px; color: #65584e; }
    @media (max-width: 620px) { .candidate { align-items: flex-start; flex-direction: column; } .grades { margin-left: 38px; } }
  </style>
</head>
<body>
  <header>
    <h1>Real rec.me Featured judgments</h1>
    <p>Grade how useful each place would be as a Featured pin for you in the shown map area. There is no query.</p>
    <p>Use your taste and the place's genuine usefulness. Do not reward fame by itself. Candidate order is randomized and every retrieval policy is hidden.</p>
    <p class="rubric"><strong>3</strong> ideal · <strong>2</strong> good · <strong>1</strong> weak filler · <strong>0</strong> wrong</p>
  </header>
  ${cards}
  <div class="bar"><div class="bar-inner"><span id="status">0 complete</span><button id="copy" type="button">Copy completed scores</button></div></div>
  <script>
    const inputs = [...document.querySelectorAll('[data-judgment]')];
    const groups = [...new Set(inputs.map(input => input.name))];
    const storageKey = 'recme-featured-relevance-v1';
    const saved = JSON.parse(localStorage.getItem(storageKey) || '{}');
    for (const input of inputs) if (saved[input.name] === input.value) input.checked = true;
    const update = () => {
      const answers = Object.fromEntries(inputs.filter(input => input.checked).map(input => [input.name, input.value]));
      localStorage.setItem(storageKey, JSON.stringify(answers));
      document.getElementById('status').textContent = groups.filter(name => answers[name] != null).length + ' of ' + groups.length + ' complete';
      return answers;
    };
    for (const input of inputs) input.addEventListener('change', update);
    document.getElementById('copy').addEventListener('click', async () => {
      const answers = update();
      if (Object.keys(answers).length !== groups.length) { alert('Grade every candidate first.'); return; }
      const text = groups.map(name => name + '=' + answers[name]).join('\n');
      try {
        await navigator.clipboard.writeText(text);
      } catch {
        const fallback = document.createElement('textarea');
        fallback.value = text;
        document.body.appendChild(fallback);
        fallback.select();
        document.execCommand('copy');
        fallback.remove();
      }
      document.getElementById('copy').textContent = 'Copied — paste into Codex';
    });
    update();
  </script>
</body>
</html>\n`;
}

async function writeArtifact(path, contents) {
  const absolutePath = resolve(repositoryRoot, path);
  await mkdir(dirname(absolutePath), { recursive: true });
  await writeFile(absolutePath, contents, "utf8");
  return absolutePath;
}

async function main() {
  const viewerHandle = argumentValue("--viewer-handle", process.env.RECME_FEATURED_VIEWER_HANDLE);
  const judgmentsPath = argumentValue("--judgments", defaultJudgmentsPath);
  const htmlPath = argumentValue("--html", defaultHtmlPath);
  const keyPath = argumentValue("--key", defaultKeyPath);
  const { candidates, tastePlaces, stats } = await loadFeaturedRealData(viewerHandle);
  if (candidates.length < 20) {
    throw new Error(`Featured corpus is too small: expected at least 20 places, found ${candidates.length}.`);
  }
  if (tastePlaces.length < 5) {
    throw new Error(`Featured viewer taste is too sparse: expected at least 5 positive/Wanna places, found ${tastePlaces.length}.`);
  }

  const embeddingPlaces = [
    ...candidates.map(embeddingPlace),
    ...tastePlaces.map(embeddingPlace),
  ];
  const embedding = await createEmbeddingMaps({ places: embeddingPlaces, queries: [] });
  const tasteEmbedding = averageEmbedding(
    tastePlaces.map((place) => embedding.placeEmbeddings.get(place.id)),
  );
  const scoredCandidates = attachSemanticTasteScores(
    candidates,
    embedding.placeEmbeddings,
    tasteEmbedding,
  );
  const tasteProfile = buildFeaturedTasteProfile(tastePlaces);
  const scenarios = generateFeaturedScenarios(scoredCandidates);
  if (scenarios.length < 6) {
    throw new Error(`Featured benchmark generated only ${scenarios.length} usable scenarios.`);
  }

  const experiments = scenarios.map((scenario) => {
    const viewportCandidates = candidatesInViewport(scoredCandidates, scenario.viewport);
    const result = benchmarkScenario({ candidates: viewportCandidates, scenario, tasteProfile });
    return {
      ...scenario,
      ...result,
      privacyFailures: viewportCandidates.filter((candidate) => (
        !candidate.privacyEligible || candidate.status !== "been"
      )).length,
      duplicateFailures: viewportCandidates.length - new Set(viewportCandidates.map(({ id }) => id)).size,
    };
  });
  const { markdown, key } = renderJudgments({
    experiments,
    candidates: scoredCandidates,
    stats,
    embedding,
  });

  const judgmentsAbsolutePath = await writeArtifact(judgmentsPath, markdown);
  const htmlAbsolutePath = await writeArtifact(htmlPath, renderHtml({ key, candidates: scoredCandidates }));
  const keyAbsolutePath = await writeArtifact(keyPath, `${JSON.stringify(key, null, 2)}\n`);

  process.stdout.write(`Featured corpus: ${stats.candidatePlaces} places / ${stats.candidateSaves} eligible saves\n`);
  process.stdout.write(`Viewer taste: ${stats.tastePlaces} positive or Wanna places\n`);
  process.stdout.write(`Scenarios: ${experiments.length}\n`);
  process.stdout.write(`Judgments: ${judgmentsAbsolutePath}\n`);
  process.stdout.write(`Judgment UI: ${htmlAbsolutePath}\n`);
  process.stdout.write(`Scoring key: ${keyAbsolutePath}\n`);
  process.stdout.write(`Embedding cache: ${embedding.cacheHits} hits, ${embedding.cacheMisses} misses\n`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main().catch((error) => {
    process.stderr.write(`Featured relevance pool failed: ${error.message}\n`);
    process.exitCode = 1;
  });
}
