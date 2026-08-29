#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { isAbsolute, join, resolve } from "node:path";

import {
  buildSummary,
  renderSummaryMarkdown,
  scorePredictions,
  writeJSON,
} from "./lib.mjs";
import { mapKitResolverID, resolveWithMapKit } from "./mapkit.mjs";

const value = process.argv[2];
const reresolveMapKit = process.argv.includes("--reresolve-mapkit");
const unknownOptions = process.argv.slice(3).filter((item) => item !== "--reresolve-mapkit");
if (!value || ["--help", "-h"].includes(value)) {
  process.stdout.write(
    "Usage: node social-import-eval/rescore.mjs <existing-run-directory> [--reresolve-mapkit]\n",
  );
  process.exitCode = value ? 0 : 1;
} else if (unknownOptions.length > 0) {
  process.stderr.write("Unknown options: " + unknownOptions.join(", ") + "\n");
  process.exitCode = 1;
} else {
  const runDirectory = isAbsolute(value) ? value : resolve(process.cwd(), value);
  const resultsPath = join(runDirectory, "results.json");
  const manifestPath = join(runDirectory, "manifest.json");
  const results = JSON.parse(await readFile(resultsPath, "utf8"));
  if (reresolveMapKit && results.some((result) => result.poiResolution?.mode !== "mapkit")) {
    throw new Error(
      "--reresolve-mapkit requires a run originally created with --resolve mapkit",
    );
  }
  for (const result of results) {
    if (reresolveMapKit && result.poiResolution?.mode === "mapkit") {
      const hints = result.understanding?.hints ?? [];
      const previousLatencyMs = result.poiResolution?.latencyMs ?? 0;
      const started = performance.now();
      let response = null;
      let error = null;
      if (hints.length > 0) {
        try {
          response = await resolveWithMapKit(hints, runDirectory);
        } catch (caught) {
          error = {
            code: "mapkit_resolver_failed",
            message: caught instanceof Error ? caught.message : String(caught),
          };
        }
      }
      const latencyMs = hints.length > 0 ? Math.round(performance.now() - started) : 0;
      result.poiResolution = {
        mode: "mapkit",
        status: error ? "failed" : (hints.length === 0 ? "not_run_no_hints" : "ok"),
        error,
        response,
        latencyMs,
      };
      result.predictions.endToEnd = (response?.results ?? []).flatMap((lookup) => {
        if (!lookup.selectedCandidateID) return [];
        const candidate = lookup.candidates?.find(
          (item) => item.id === lookup.selectedCandidateID,
        );
        return candidate?.name ? [candidate.name] : [];
      });
      if (result.timing) {
        result.timing.resolutionMs = latencyMs;
        result.timing.totalMs = Math.max(
          0,
          (result.timing.totalMs ?? 0) - previousLatencyMs + latencyMs,
        );
      }
    }
    result.scores = {
      extraction: scorePredictions(result.case.labels, result.predictions.extraction),
      endToEnd: scorePredictions(result.case.labels, result.predictions.endToEnd),
      endToEndStage: result.poiResolution?.mode === "mapkit"
        ? "selected_mapkit_names"
        : "unresolved_hints",
    };
  }
  const summary = buildSummary(results);
  const markdown = renderSummaryMarkdown(summary);
  const writes = [
    writeJSON(resultsPath, results),
    writeJSON(join(runDirectory, "summary.json"), summary),
    writeFile(join(runDirectory, "summary.md"), markdown + "\n"),
  ];
  if (reresolveMapKit) {
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    writes.push(writeJSON(manifestPath, {
      ...manifest,
      lastRescoredAt: new Date().toISOString(),
      mapKitResolutionRerun: {
        resolver: mapKitResolverID,
        source: "saved_understanding_hints",
        paidAcquisitionOrUnderstandingCalls: false,
      },
    }));
  }
  await Promise.all(writes);
  process.stdout.write(markdown + "\nRescored: " + runDirectory + "\n");
  if (reresolveMapKit) process.stdout.write("MapKit resolution rerun: yes\n");
}
