#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const defaultPricingPath = path.join(scriptDirectory, "model-pricing.json");

export function compareModelCosts(usage, pricing) {
  const inputTokens = boundedCount(usage.inputTokens, "inputTokens");
  const outputTokens = boundedCount(usage.outputTokens, "outputTokens");
  const importCount = boundedCount(usage.importCount, "importCount", 1);
  if (!pricing || pricing.schemaVersion !== 1 || !Array.isArray(pricing.models)) {
    throw new Error("invalid_pricing");
  }
  return pricing.models.map((model) => {
    if (
      !model || typeof model.id !== "string" ||
      !Number.isFinite(model.input) || model.input < 0 ||
      !Number.isFinite(model.outputIncludingReasoning) ||
      model.outputIncludingReasoning < 0
    ) throw new Error("invalid_model_pricing");
    const inputCost = inputTokens / 1_000_000 * model.input;
    const outputCost = outputTokens / 1_000_000 *
      model.outputIncludingReasoning;
    const totalCost = inputCost + outputCost;
    return {
      model: model.id,
      provider: model.provider,
      nativeVideoInput: model.nativeVideoInput === true,
      usdPerMillionInputTokens: model.input,
      usdPerMillionOutputIncludingReasoningTokens:
        model.outputIncludingReasoning,
      inputCostUSD: roundedUSD(inputCost),
      outputCostUSD: roundedUSD(outputCost),
      totalCostUSD: roundedUSD(totalCost),
      costPerImportUSD: roundedUSD(totalCost / importCount),
      ...(model.priceNote ? { priceNote: model.priceNote } : {}),
      source: model.source,
    };
  });
}

function boundedCount(value, name, minimum = 0) {
  if (
    !Number.isSafeInteger(value) || value < minimum || value > 1_000_000_000_000
  ) throw new Error(`invalid_${name}`);
  return value;
}

function roundedUSD(value) {
  return Number(value.toFixed(8));
}

function parseArguments(args) {
  const values = {
    inputTokens: null,
    outputTokens: null,
    importCount: null,
    pricingPath: defaultPricingPath,
    outputPath: null,
  };
  const mapping = new Map([
    ["--input-tokens", "inputTokens"],
    ["--output-tokens", "outputTokens"],
    ["--imports", "importCount"],
    ["--pricing", "pricingPath"],
    ["--out", "outputPath"],
  ]);
  for (let index = 0; index < args.length; index += 2) {
    const key = mapping.get(args[index]);
    const value = args[index + 1];
    if (!key || !value) throw new Error("invalid_arguments");
    values[key] = key.endsWith("Tokens") || key === "importCount"
      ? Number(value)
      : value;
  }
  if (
    values.inputTokens === null || values.outputTokens === null ||
    values.importCount === null
  ) throw new Error("missing_usage");
  return values;
}

function writeExclusiveJSON(destination, value) {
  const descriptor = fs.openSync(destination, "wx", 0o600);
  try {
    fs.writeFileSync(descriptor, JSON.stringify(value, null, 2) + "\n");
  } finally {
    fs.closeSync(descriptor);
  }
}

function main() {
  const args = parseArguments(process.argv.slice(2));
  const pricing = JSON.parse(fs.readFileSync(args.pricingPath, "utf8"));
  const usage = {
    inputTokens: args.inputTokens,
    outputTokens: args.outputTokens,
    importCount: args.importCount,
  };
  const report = {
    schemaVersion: 1,
    pricingCheckedAt: pricing.checkedAt,
    usage,
    warning:
      "Same-token comparison only. Image/video tokenization, retries, preprocessing, scraper calls, map resolution, and provider-specific caching are excluded.",
    comparisons: compareModelCosts(usage, pricing),
  };
  if (args.outputPath) writeExclusiveJSON(args.outputPath, report);
  else process.stdout.write(JSON.stringify(report, null, 2) + "\n");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(
      `model-cost-comparison: ${error instanceof Error ? error.message : "failed"}\n`,
    );
    process.exitCode = 1;
  }
}
