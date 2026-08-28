#!/usr/bin/env node

import { readFile, writeFile } from "node:fs/promises";
import { isAbsolute, join, resolve } from "node:path";

import {
  buildSummary,
  renderSummaryMarkdown,
  scorePredictions,
  writeJSON,
} from "./lib.mjs";

const value = process.argv[2];
if (!value || ["--help", "-h"].includes(value)) {
  process.stdout.write("Usage: node social-import-eval/rescore.mjs <existing-run-directory>\n");
  process.exitCode = value ? 0 : 1;
} else {
  const runDirectory = isAbsolute(value) ? value : resolve(process.cwd(), value);
  const resultsPath = join(runDirectory, "results.json");
  const results = JSON.parse(await readFile(resultsPath, "utf8"));
  for (const result of results) {
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
  await Promise.all([
    writeJSON(resultsPath, results),
    writeJSON(join(runDirectory, "summary.json"), summary),
    writeFile(join(runDirectory, "summary.md"), markdown + "\n"),
  ]);
  process.stdout.write(markdown + "\nRescored: " + runDirectory + "\n");
}
