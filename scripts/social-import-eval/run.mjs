#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  buildSummary,
  defaultOutputDirectory,
  parseList,
  readJSON,
  renderSummaryMarkdown,
  safeSegment,
  scorePredictions,
  stableHash,
  writeJSON,
} from "./lib.mjs";
import { resolveWithMapKit } from "./mapkit.mjs";
import {
  assessAcquisitionCompleteness,
  validateAcquisitionCompleteness,
} from "./completeness.mjs";
import { runAcquisitionProvider, runUnderstandingProvider } from "./providers.mjs";

const moduleDirectory = dirname(fileURLToPath(import.meta.url));
const allowedProviders = new Set(["current", "current-improved", "brightdata", "apify"]);
const allowedUnderstanders = new Set([
  "deterministic", "apple-vision", "apple-vision-keyframes", "gemini", "google-video", "aws-rekognition-transcribe",
  "azure-video-indexer",
]);

function usage() {
  return `REC-120 Instagram/TikTok place importer evaluation

Usage:
  node social-import-eval/run.mjs [options]

Options:
  --cases <ids>            comma-separated corpus case IDs (default: all)
  --providers <names>      current,current-improved,brightdata,apify
  --understanders <names>  deterministic,apple-vision,apple-vision-keyframes,
                           gemini,google-video,
                           aws-rekognition-transcribe,azure-video-indexer
  --resolve <mode>         none or mapkit (default: none)
  --out <directory>        output directory (default: ignored timestamped run)
  --fixture-dir <path>     replay saved acquisition envelopes without network
  --help                   show this message
`;
}

function parseArguments(argv) {
  const options = {
    cases: [],
    providers: ["current", "current-improved"],
    understanders: ["deterministic"],
    resolver: "none",
    out: null,
    fixtureDirectory: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help" || argument === "-h") return { ...options, help: true };
    const next = argv[index + 1];
    if (!next || next.startsWith("--")) throw new Error("Missing value for " + argument);
    switch (argument) {
    case "--cases":
      options.cases = parseList(next);
      break;
    case "--providers":
      options.providers = parseList(next);
      break;
    case "--understanders":
      options.understanders = parseList(next);
      break;
    case "--resolve":
      options.resolver = next;
      break;
    case "--out":
      options.out = next;
      break;
    case "--fixture-dir":
      options.fixtureDirectory = next;
      break;
    default:
      throw new Error("Unknown option: " + argument);
    }
    index += 1;
  }
  if (options.providers.length === 0) throw new Error("At least one provider is required");
  if (options.understanders.length === 0) throw new Error("At least one understander is required");
  for (const provider of options.providers) {
    if (!allowedProviders.has(provider)) throw new Error("Unknown provider: " + provider);
  }
  for (const understander of options.understanders) {
    if (!allowedUnderstanders.has(understander)) {
      throw new Error("Unknown understander: " + understander);
    }
  }
  if (!["none", "mapkit"].includes(options.resolver)) {
    throw new Error("Unknown resolver: " + options.resolver);
  }
  return options;
}

function absoluteFromWorkingDirectory(value) {
  return isAbsolute(value) ? value : resolve(process.cwd(), value);
}

function publicConfiguration() {
  return {
    brightDataConfigured: Boolean(process.env.BRIGHTDATA_API_TOKEN),
    apifyConfigured: Boolean(process.env.APIFY_TOKEN),
    geminiConfigured: Boolean(process.env.GEMINI_API_KEY),
    googleVideoConfigured: Boolean(process.env.GOOGLE_CLOUD_ACCESS_TOKEN),
    geminiModel: process.env.GEMINI_MODEL ?? "gemini-3.5-flash",
  };
}

function acquisitionEnvelope(testCase, acquisition) {
  return {
    schemaVersion: 1,
    capturedAt: new Date().toISOString(),
    caseID: testCase.id,
    sourceURL: testCase.url,
    provider: acquisition.provider,
    status: acquisition.status,
    error: acquisition.error ?? null,
    latencyMs: acquisition.latencyMs,
    providerLatencyMs: acquisition.providerLatencyMs ?? acquisition.latencyMs,
    modalityCoverage: acquisition.modalityCoverage ?? null,
    cost: acquisition.cost ?? null,
    evidence: acquisition.evidence,
    raw: acquisition.raw,
  };
}

async function loadFixture(fixtureDirectory, testCase, provider) {
  const path = join(fixtureDirectory, safeSegment(testCase.id), safeSegment(provider) + ".json");
  const fixture = await readJSON(path);
  const value = fixture.acquisition ?? fixture;
  if (value.provider && value.provider !== provider) {
    throw new Error("Fixture provider mismatch at " + path);
  }
  return {
    provider,
    latencyMs: value.latencyMs ?? 0,
    providerLatencyMs: value.providerLatencyMs ?? value.latencyMs ?? 0,
    status: value.status ?? "ok",
    error: value.error ?? null,
    cost: value.cost ?? null,
    evidence: value.evidence,
    modalityCoverage: value.modalityCoverage ?? null,
    raw: value.raw ?? null,
    fixturePath: path,
  };
}

async function acquire(testCase, provider, fixtureDirectory) {
  if (fixtureDirectory) {
    const acquisition = await loadFixture(fixtureDirectory, testCase, provider);
    // Fixture replay is strictly offline. Reuse persisted probe diagnostics;
    // older fixtures remain explicitly unverified rather than touching live CDNs.
    return acquisition.modalityCoverage
      ? acquisition
      : assessAcquisitionCompleteness(testCase, acquisition);
  }
  const acquisition = await runAcquisitionProvider(provider, testCase);
  return await validateAcquisitionCompleteness(testCase, acquisition);
}

function serializableAcquisition(acquisition) {
  const { raw: _raw, ...rest } = acquisition;
  return rest;
}

function serializableUnderstanding(understanding) {
  const { raw: _raw, ...rest } = understanding;
  return rest;
}

function selectedMapKitNames(resolution) {
  // In MapKit mode, a process-level resolver failure means zero selected POIs.
  // Falling back to extracted hints here would silently turn a failed POI stage
  // into high end-to-end recall.
  if (!resolution) return [];
  const values = [];
  for (const result of resolution.results ?? []) {
    if (!result.selectedCandidateID) continue;
    const candidate = result.candidates?.find((item) => item.id === result.selectedCandidateID);
    if (candidate?.name) values.push(candidate.name);
  }
  return values;
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(usage());
    return;
  }
  const corpusPath = join(moduleDirectory, "corpus.json");
  const corpusBytes = await readFile(corpusPath);
  const corpus = JSON.parse(corpusBytes);
  const requestedCaseIDs = new Set(options.cases);
  const cases = requestedCaseIDs.size === 0
    ? corpus.cases
    : corpus.cases.filter((testCase) => requestedCaseIDs.has(testCase.id));
  const missingCases = [...requestedCaseIDs].filter((id) => !cases.some((testCase) => testCase.id === id));
  if (missingCases.length > 0) throw new Error("Unknown case IDs: " + missingCases.join(", "));
  if (cases.length === 0) throw new Error("No corpus cases selected");

  const outputDirectory = options.out
    ? absoluteFromWorkingDirectory(options.out)
    : defaultOutputDirectory(moduleDirectory);
  const fixtureDirectory = options.fixtureDirectory
    ? absoluteFromWorkingDirectory(options.fixtureDirectory)
    : null;
  const manifest = {
    schemaVersion: 1,
    startedAt: new Date().toISOString(),
    corpus: {
      path: corpusPath,
      sha256: stableHash(corpusBytes),
      schemaVersion: corpus.schemaVersion,
      selectedCaseIDs: cases.map((testCase) => testCase.id),
    },
    providers: options.providers,
    understanders: options.understanders,
    resolver: options.resolver,
    fixtureReplay: Boolean(fixtureDirectory),
    providerConfiguration: publicConfiguration(),
    runtime: { node: process.version, platform: process.platform, architecture: process.arch },
  };
  await writeJSON(join(outputDirectory, "manifest.json"), manifest);

  const acquisitions = new Map();
  for (const testCase of cases) {
    for (const provider of options.providers) {
      const key = testCase.id + "|" + provider;
      const acquisition = await acquire(testCase, provider, fixtureDirectory);
      acquisitions.set(key, acquisition);
      await writeJSON(
        join(outputDirectory, "raw", safeSegment(testCase.id), safeSegment(provider) + ".json"),
        acquisitionEnvelope(testCase, acquisition),
      );
    }
  }

  const results = [];
  for (const testCase of cases) {
    for (const provider of options.providers) {
      const acquisition = acquisitions.get(testCase.id + "|" + provider);
      for (const understander of options.understanders) {
        const started = performance.now();
        const understanding = await runUnderstandingProvider(
          understander,
          testCase,
          acquisition,
          { outputDirectory },
        );
        const variant = provider + "+" + understander + "+" + options.resolver;
        const rawUnderstandingPath = join(
          outputDirectory,
          "raw",
          safeSegment(testCase.id),
          safeSegment(provider + "+" + understander) + ".json",
        );
        await writeJSON(rawUnderstandingPath, {
          schemaVersion: 1,
          capturedAt: new Date().toISOString(),
          caseID: testCase.id,
          variant,
          status: understanding.status,
          error: understanding.error ?? null,
          latencyMs: understanding.latencyMs,
          cost: understanding.cost ?? null,
          raw: understanding.raw,
        });

        let resolution = null;
        let resolutionError = null;
        const resolutionStarted = performance.now();
        if (options.resolver === "mapkit" && understanding.hints?.length > 0) {
          try {
            resolution = await resolveWithMapKit(understanding.hints, outputDirectory);
          } catch (error) {
            resolutionError = {
              code: "mapkit_resolver_failed",
              message: error instanceof Error ? error.message : String(error),
            };
          }
        }
        const resolutionLatencyMs = options.resolver === "mapkit"
          ? Math.round(performance.now() - resolutionStarted)
          : 0;
        const extractionPredictions = (understanding.hints ?? []).map((hint) => hint.name);
        const endToEndPredictions = options.resolver === "mapkit"
          ? selectedMapKitNames(resolution)
          : extractionPredictions;
        results.push({
          schemaVersion: 1,
          case: testCase,
          variant,
          acquisition: serializableAcquisition(acquisition),
          understanding: serializableUnderstanding(understanding),
          poiResolution: {
            mode: options.resolver,
            status: resolutionError
              ? "failed"
              : (options.resolver === "none"
                ? "not_run"
                : ((understanding.hints?.length ?? 0) === 0 ? "not_run_no_hints" : "ok")),
            error: resolutionError,
            response: resolution,
            latencyMs: resolutionLatencyMs,
          },
          predictions: {
            extraction: extractionPredictions,
            endToEnd: endToEndPredictions,
          },
          scores: {
            extraction: scorePredictions(testCase.labels, extractionPredictions),
            endToEnd: scorePredictions(testCase.labels, endToEndPredictions),
            // Corpus labels currently ground names/aliases, not physical branch
            // identities. This score therefore measures selected MapKit names;
            // candidate IDs, addresses, and coordinates remain diagnostics and
            // must not be presented as physical-POI acceptance accuracy.
            endToEndStage: options.resolver === "mapkit"
              ? "selected_mapkit_names"
              : "unresolved_hints",
          },
          timing: {
            acquisitionMs: acquisition.latencyMs,
            understandingMs: understanding.latencyMs,
            resolutionMs: resolutionLatencyMs,
            totalMs: acquisition.latencyMs + Math.round(performance.now() - started),
          },
        });
        await writeJSON(join(outputDirectory, "results.json"), results);
      }
    }
  }

  const summary = buildSummary(results);
  const markdown = renderSummaryMarkdown(summary);
  const completedManifest = { ...manifest, completedAt: new Date().toISOString() };
  await Promise.all([
    writeJSON(join(outputDirectory, "manifest.json"), completedManifest),
    writeJSON(join(outputDirectory, "summary.json"), summary),
    writeFile(join(outputDirectory, "summary.md"), markdown + "\n"),
  ]);
  process.stdout.write(markdown + "\nOutput: " + outputDirectory + "\n");
}

main().catch((error) => {
  process.stderr.write("social-import-eval: " + (error instanceof Error ? error.message : String(error)) + "\n");
  process.exitCode = 1;
});
