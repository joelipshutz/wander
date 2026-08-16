import { createHash } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import { buildPlaceDocument } from "./core.mjs";

const currentDirectory = dirname(fileURLToPath(import.meta.url));
const defaultEnvPath = join(homedir(), ".openclaw", "workspace", ".env.keys");
const defaultCachePath = join(currentDirectory, ".cache", "embeddings.json");

function unquote(value) {
  if (
    (value.startsWith('"') && value.endsWith('"'))
    || (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function loadOpenAiKey(envPath = defaultEnvPath) {
  if (process.env.OPENAI_API_KEY) return;
  if (!existsSync(envPath)) return;
  const line = requireLine(readFileSync(envPath, "utf8"), "OPENAI_API_KEY");
  if (line !== null) process.env.OPENAI_API_KEY = unquote(line);
}

function requireLine(contents, key) {
  for (const line of contents.split(/\r?\n/)) {
    const match = line.match(/^\s*(?:export\s+)?([A-Z0-9_]+)=(.*)$/);
    if (match?.[1] === key) return match[2].trim();
  }
  return null;
}

const fingerprint = (text) => createHash("sha256").update(text).digest("hex");

async function readCache(cachePath, model) {
  try {
    const parsed = JSON.parse(await readFile(cachePath, "utf8"));
    if (parsed.model === model && parsed.entries && typeof parsed.entries === "object") {
      return parsed;
    }
  } catch {
    // A missing or stale cache is a normal first-run state.
  }
  return { model, entries: {} };
}

async function requestEmbeddings(inputs, model) {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error(`Missing OPENAI_API_KEY. Add it to ${defaultEnvPath} or the current environment.`);
  }
  const response = await fetch("https://api.openai.com/v1/embeddings", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model, input: inputs, encoding_format: "float" }),
  });
  if (!response.ok) {
    throw new Error(`OpenAI embeddings request failed with HTTP ${response.status}.`);
  }
  const payload = await response.json();
  return payload.data
    .sort((left, right) => left.index - right.index)
    .map((item) => item.embedding);
}

export async function createEmbeddingMaps({
  places,
  queries,
  model = process.env.RELEVANCE_EMBEDDING_MODEL ?? "text-embedding-3-small",
  cachePath = defaultCachePath,
}) {
  loadOpenAiKey();
  const startedAt = performance.now();
  const records = [
    ...places.map((place) => ({ key: `place:${place.id}`, text: buildPlaceDocument(place) })),
    ...queries.map((query) => ({ key: `query:${query.id}`, text: query.text })),
  ];
  const cache = await readCache(cachePath, model);
  const missing = records.filter((record) => {
    const entry = cache.entries[record.key];
    return !entry || entry.fingerprint !== fingerprint(record.text) || !Array.isArray(entry.vector);
  });

  if (missing.length > 0) {
    const vectors = await requestEmbeddings(missing.map((record) => record.text), model);
    if (vectors.length !== missing.length) {
      throw new Error("OpenAI returned an unexpected number of embeddings.");
    }
    missing.forEach((record, index) => {
      cache.entries[record.key] = {
        fingerprint: fingerprint(record.text),
        vector: vectors[index],
      };
    });
    await mkdir(dirname(cachePath), { recursive: true });
    await writeFile(cachePath, `${JSON.stringify(cache)}\n`, "utf8");
  }

  return {
    model,
    cacheHits: records.length - missing.length,
    cacheMisses: missing.length,
    latencyMs: performance.now() - startedAt,
    placeEmbeddings: new Map(
      places.map((place) => [place.id, cache.entries[`place:${place.id}`].vector]),
    ),
    queryEmbeddings: new Map(
      queries.map((query) => [query.id, cache.entries[`query:${query.id}`].vector]),
    ),
  };
}
