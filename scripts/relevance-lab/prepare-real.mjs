#!/usr/bin/env node

import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runExperiment } from "./core.mjs";
import { createEmbeddingMaps } from "./embeddings.mjs";
import { loadSanitizedRealCorpus, realQueries } from "./real-data.mjs";
import { withSupabaseProviders } from "./supabase.mjs";

const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const defaultJudgmentsPath = "scripts/relevance-lab/output/real-judgments.md";
const defaultHtmlPath = "scripts/relevance-lab/output/real-judgments.html";
const defaultKeyPath = "scripts/relevance-lab/output/real-pool-key.json";
const pipelineNames = ["lexical", "reranked", "hybrid"];

function argumentValue(flag, fallback) {
  const index = process.argv.indexOf(flag);
  return index === -1 ? fallback : process.argv[index + 1] ?? fallback;
}

function stableNumber(value) {
  return Number.parseInt(createHash("sha256").update(value).digest("hex").slice(0, 12), 16);
}

function pooledCandidateIds(row, limit = 10) {
  const selected = [];
  for (let rank = 0; rank < 5 && selected.length < limit; rank += 1) {
    for (const pipeline of pipelineNames) {
      const id = row.pipelines[pipeline].results[rank]?.id;
      if (id && !selected.includes(id)) selected.push(id);
      if (selected.length === limit) break;
    }
  }
  return selected.sort(
    (left, right) => stableNumber(`${row.id}:${left}`) - stableNumber(`${row.id}:${right}`),
  );
}

function mapsUrl(place) {
  const query = [place.name, place.neighborhood, place.city].filter(Boolean).join(", ");
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}

function escapeTable(value) {
  return String(value).replaceAll("|", "\\|");
}

function candidateContext(place) {
  return [place.subcategory || place.category.replaceAll("_", " "), place.neighborhood, place.city]
    .filter(Boolean)
    .join(" · ");
}

function renderJudgments({ experiment, places, stats }) {
  const placesById = new Map(places.map((place) => [place.id, place]));
  const lines = [
    "# Real rec.me relevance judgments",
    "",
    "Replace each `?` with one grade:",
    "",
    "- `3` — ideal result",
    "- `2` — good result",
    "- `1` — weak but defensible",
    "- `0` — wrong for the query",
    "",
    "Judge relevance to the query, not whether the place is generally good. Candidate order is randomized and the retrieval source is hidden.",
    "",
    `Corpus snapshot: ${places.length} real saved places from ${stats.active_saves} active saves and ${stats.rated_saves} ratings.`,
    "",
    `People-vector evaluation is not included: only ${stats.profiles_with_5_ratings} profiles currently have five or more ratings, which is not enough for a credible learned-affinity result.`,
    "",
  ];
  const key = {
    generatedAt: new Date().toISOString(),
    stats,
    queries: [],
  };

  experiment.perQuery.forEach((row, queryIndex) => {
    const ids = pooledCandidateIds(row);
    if (ids.length < 3) {
      throw new Error(`${row.id} produced only ${ids.length} unique candidates.`);
    }
    const candidates = ids.map((id, candidateIndex) => {
      const place = placesById.get(id);
      const label = String.fromCharCode(65 + candidateIndex);
      const pipelines = Object.fromEntries(pipelineNames.map((pipeline) => {
        const rank = row.pipelines[pipeline].results.findIndex((result) => result.id === id);
        return [pipeline, rank === -1 ? null : rank + 1];
      }));
      return { label, place, pipelines };
    });

    lines.push(
      `## ${queryIndex + 1}. ${row.text}`,
      "",
      "| Candidate | Place | Context | Grade |",
      "|---|---|---|---:|",
    );
    for (const candidate of candidates) {
      lines.push(
        `| ${candidate.label} | [${escapeTable(candidate.place.name)}](${mapsUrl(candidate.place)}) | ${escapeTable(candidateContext(candidate.place))} | ? |`,
      );
    }
    lines.push("");

    key.queries.push({
      id: row.id,
      text: row.text,
      candidates: candidates.map(({ label, place, pipelines }) => ({
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

function renderHtml({ key, places }) {
  const placesById = new Map(places.map((place) => [place.id, place]));
  const queryCards = key.queries.map((query, queryIndex) => {
    const candidates = query.candidates.map((candidate) => {
      const place = placesById.get(candidate.placeId);
      const name = `${query.id}:${candidate.label}`;
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
      <section class="query">
        <h2>${queryIndex + 1}. ${escapeHtml(query.text)}</h2>
        ${candidates}
      </section>`;
  }).join("");

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Real rec.me relevance judgments</title>
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #f4efe7; color: #2c211b; }
    body { margin: 0 auto; max-width: 880px; padding: 24px 16px 120px; }
    header { background: #fffaf2; border: 1px solid #dfd3c4; border-radius: 18px; padding: 20px; margin-bottom: 18px; }
    h1 { margin: 0 0 10px; font-size: 28px; }
    p { line-height: 1.45; margin: 6px 0; }
    .rubric { font-size: 14px; color: #65584e; }
    .query { background: white; border: 1px solid #e4d9cc; border-radius: 18px; margin: 14px 0; padding: 18px; }
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
    <h1>Real rec.me relevance judgments</h1>
    <p>Grade each place for the query. Candidate order is randomized; the retrieval system is hidden.</p>
    <p class="rubric"><strong>3</strong> ideal · <strong>2</strong> good · <strong>1</strong> weak but defensible · <strong>0</strong> wrong</p>
  </header>
  ${queryCards}
  <div class="bar"><div class="bar-inner"><span id="status">0 complete</span><button id="copy" type="button">Copy completed scores</button></div></div>
  <script>
    const inputs = [...document.querySelectorAll('[data-judgment]')];
    const groups = [...new Set(inputs.map(input => input.name))];
    const storageKey = 'recme-real-relevance-v1';
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

async function writeArtifact(relativePath, contents) {
  const absolutePath = resolve(repositoryRoot, relativePath);
  await mkdir(dirname(absolutePath), { recursive: true });
  await writeFile(absolutePath, contents, "utf8");
  return absolutePath;
}

async function main() {
  const judgmentsPath = argumentValue("--judgments", defaultJudgmentsPath);
  const htmlPath = argumentValue("--html", defaultHtmlPath);
  const keyPath = argumentValue("--key", defaultKeyPath);
  const { places, stats } = await loadSanitizedRealCorpus();
  if (places.length < 20) {
    throw new Error(`Real corpus is too small: expected at least 20 saved places, found ${places.length}.`);
  }

  const embedding = await createEmbeddingMaps({ places, queries: realQueries });
  const experiment = await withSupabaseProviders(
    places,
    embedding.placeEmbeddings,
    embedding.queryEmbeddings,
    ({ lexicalProvider, semanticProvider }) => runExperiment({
      places,
      queries: realQueries,
      lexicalProvider,
      semanticProvider,
    }),
  );
  const { markdown, key } = renderJudgments({ experiment, places, stats });
  const judgmentsAbsolutePath = await writeArtifact(judgmentsPath, markdown);
  const htmlAbsolutePath = await writeArtifact(htmlPath, renderHtml({ key, places }));
  const keyAbsolutePath = await writeArtifact(keyPath, `${JSON.stringify(key, null, 2)}\n`);

  process.stdout.write(`Real corpus: ${places.length} saved places\n`);
  process.stdout.write(`Judgments: ${judgmentsAbsolutePath}\n`);
  process.stdout.write(`Judgment UI: ${htmlAbsolutePath}\n`);
  process.stdout.write(`Scoring key: ${keyAbsolutePath}\n`);
  process.stdout.write(`Embedding cache: ${embedding.cacheHits} hits, ${embedding.cacheMisses} misses\n`);
}

main().catch((error) => {
  process.stderr.write(`Real relevance pool failed: ${error.message}\n`);
  process.exitCode = 1;
});
