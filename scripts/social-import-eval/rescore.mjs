#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { isAbsolute, join, resolve } from "node:path";

import {
  buildRescoreProvenance,
  buildSummary,
  extractDeterministicHints,
  extractGroundedModelHints,
  renderSummaryMarkdown,
  scorePredictions,
  writeJSON,
} from "./lib.mjs";
import { mapKitResolverID, resolveWithMapKit } from "./mapkit.mjs";

const value = process.argv[2];
const rescoreStartedAt = new Date().toISOString();
const sha256 = (valueToHash) => createHash("sha256").update(valueToHash).digest("hex");
const reresolveMapKit = process.argv.includes("--reresolve-mapkit");
const rebuildUnderstandingHints = process.argv.includes("--rebuild-understanding-hints");
const supportedOptions = new Set(["--reresolve-mapkit", "--rebuild-understanding-hints"]);
const unknownOptions = process.argv.slice(3).filter((item) => !supportedOptions.has(item));
if (!value || ["--help", "-h"].includes(value)) {
  process.stdout.write(
    "Usage: node social-import-eval/rescore.mjs <existing-run-directory> [--rebuild-understanding-hints] [--reresolve-mapkit]\n",
  );
  process.exitCode = value ? 0 : 1;
} else if (unknownOptions.length > 0) {
  process.stderr.write("Unknown options: " + unknownOptions.join(", ") + "\n");
  process.exitCode = 1;
} else {
  const runDirectory = isAbsolute(value) ? value : resolve(process.cwd(), value);
  const resultsPath = join(runDirectory, "results.json");
  const manifestPath = join(runDirectory, "manifest.json");
  const inputResultsText = await readFile(resultsPath, "utf8");
  const inputResultsSHA256 = sha256(inputResultsText);
  const results = JSON.parse(inputResultsText);
  if (reresolveMapKit && results.some((result) => result.poiResolution?.mode !== "mapkit")) {
    throw new Error(
      "--reresolve-mapkit requires a run originally created with --resolve mapkit",
    );
  }
  if (rebuildUnderstandingHints
      && results.some((result) => result.poiResolution?.mode === "mapkit")
      && !reresolveMapKit) {
    throw new Error(
      "A MapKit-backed run requires --reresolve-mapkit when understanding hints are rebuilt",
    );
  }
  if (rebuildUnderstandingHints
      && !results.some((result) => result.variant?.includes("+gemini+"))) {
    throw new Error("--rebuild-understanding-hints requires at least one Gemini result");
  }
  for (const result of results) {
    if (rebuildUnderstandingHints && result.variant?.includes("+gemini+")) {
      let hints;
      if (["ok", "partial"].includes(result.understanding?.status)) {
        const selection = extractGroundedModelHints(
          result.understanding.evidence,
          150,
          { mediaIngestion: result.understanding.mediaIngestion ?? [] },
        );
        hints = selection.hints;
        result.understanding.modelCandidateValidation = selection.validation;
        result.understanding.fallback = { used: false };
      } else if (result.understanding?.status === "failed") {
        hints = extractDeterministicHints(
          result.understanding.evidence ?? result.acquisition?.evidence,
        );
        result.understanding.fallback = {
          used: true,
          strategy: "deterministic_evidence",
          reason: result.understanding.error?.code ?? "gemini_failed",
        };
      } else {
        hints = [];
      }
      result.understanding.hints = hints;
      result.predictions.extraction = hints.map((hint) => hint.name);
      if (result.poiResolution?.mode !== "mapkit") {
        result.predictions.endToEnd = [...result.predictions.extraction];
      }
    }
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
  const outputResultsSHA256 = sha256(JSON.stringify(results, null, 2) + "\n");
  const writes = [
    writeJSON(resultsPath, results),
    writeJSON(join(runDirectory, "summary.json"), summary),
    writeFile(join(runDirectory, "summary.md"), markdown + "\n"),
  ];
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  const provenance = buildRescoreProvenance({
    rebuildUnderstandingHints,
    reresolveMapKit,
    mapKitResolverID,
  });
  const updatedManifest = {
    ...manifest,
    lastRescoredAt: new Date().toISOString(),
    rescoreHistory: [
      ...(Array.isArray(manifest.rescoreHistory) ? manifest.rescoreHistory : []),
      {
        startedAt: rescoreStartedAt,
        appliedTransforms: provenance.appliedTransforms,
        rebuildUnderstandingHints,
        reresolveMapKit,
        inputResultsSHA256,
        outputResultsSHA256,
        paidAcquisitionOrUnderstandingCalls: false,
      },
    ],
  };
  if (reresolveMapKit) {
    updatedManifest.mapKitResolutionRerun = {
      resolver: mapKitResolverID,
      source: provenance.mapKitHintSource,
      paidAcquisitionOrUnderstandingCalls: false,
    };
  }
  if (rebuildUnderstandingHints) {
    updatedManifest.understandingHintRebuild = {
      strategy: "validated_model_candidates_with_explicit_media_attestation_and_deterministic_failure_fallback",
      source: "saved_model_candidates_and_acquisition_evidence",
      transformRevision: "grounded-hints-v3",
      fallbackAssistedCaseCount: results.filter((result) =>
        result.understanding?.fallback?.used === true
      ).length,
      paidAcquisitionOrUnderstandingCalls: false,
    };
  }
  writes.push(writeJSON(manifestPath, updatedManifest));
  await Promise.all(writes);
  process.stdout.write(markdown + "\nRescored: " + runDirectory + "\n");
  if (reresolveMapKit) process.stdout.write("MapKit resolution rerun: yes\n");
  if (rebuildUnderstandingHints) process.stdout.write("Understanding hints rebuilt: yes\n");
}
