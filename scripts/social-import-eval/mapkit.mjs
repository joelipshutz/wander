import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  runCredentialFreeProcess,
  secureTemporaryToolDirectory,
} from "./subprocess.mjs";

const moduleDirectory = dirname(fileURLToPath(import.meta.url));
export const mapKitResolverID = "mapkit-production-query-ranking-and-threshold-mirror-v4";

let resolverBinaryPromise;

async function compileResolver() {
  const toolDirectory = await secureTemporaryToolDirectory("recme-mapkit-resolver-");
  const binaryPath = join(toolDirectory, "mapkit-resolver");
  const sourcePath = join(moduleDirectory, "mapkit-resolver.swift");
  const moduleCachePath = join(toolDirectory, "swift-module-cache");
  await mkdir(moduleCachePath, { recursive: true });
  await runCredentialFreeProcess("/usr/bin/xcrun", [
    "swiftc",
    "-module-cache-path", moduleCachePath,
    "-parse-as-library",
    sourcePath,
    "-o", binaryPath,
  ], { timeoutMs: 120_000 });
  return binaryPath;
}

function resolverBinary() {
  resolverBinaryPromise ??= compileResolver();
  return resolverBinaryPromise;
}

export async function resolveWithMapKit(hints, outputDirectory) {
  void outputDirectory;
  const binaryPath = await resolverBinary();
  const requests = hints.map((hint, index) => ({
    id: String(index),
    name: hint.name,
    area: hint.area ?? null,
    allowNearSpellingMatch: [
      "ocr", "video_text", "accessibility_text", "image_text",
    ].includes(hint.modality),
  }));
  if (requests.length === 0) {
    return { resolver: mapKitResolverID, results: [] };
  }
  const { output } = await runCredentialFreeProcess(binaryPath, [], {
    input: JSON.stringify({ requests }),
    timeoutMs: Math.max(120_000, requests.length * 15_000),
  });
  let response;
  try {
    response = JSON.parse(output);
  } catch {
    throw new Error("MapKit resolver returned invalid JSON");
  }
  if (response.fatalError) throw new Error(response.fatalError);
  return response;
}

export async function inspectMapKitGeography(geographyProbes, outputDirectory) {
  void outputDirectory;
  const binaryPath = await resolverBinary();
  const { output } = await runCredentialFreeProcess(binaryPath, [], {
    input: JSON.stringify({ requests: [], geographyProbes }),
    timeoutMs: 120_000,
  });
  const response = JSON.parse(output);
  if (response.fatalError) throw new Error(response.fatalError);
  return response.geographyProbes ?? [];
}

export async function inspectMapKitRanking(rankingProbes, outputDirectory) {
  void outputDirectory;
  const binaryPath = await resolverBinary();
  const { output } = await runCredentialFreeProcess(binaryPath, [], {
    input: JSON.stringify({ requests: [], rankingProbes }),
    timeoutMs: 120_000,
  });
  const response = JSON.parse(output);
  if (response.fatalError) throw new Error(response.fatalError);
  return response.rankingProbes ?? [];
}

export async function inspectMapKitQueryLimits(queryLimitProbes, outputDirectory) {
  void outputDirectory;
  const binaryPath = await resolverBinary();
  const { output } = await runCredentialFreeProcess(binaryPath, [], {
    input: JSON.stringify({ requests: [], queryLimitProbes }),
    timeoutMs: 120_000,
  });
  const response = JSON.parse(output);
  if (response.fatalError) throw new Error(response.fatalError);
  return response.queryLimitProbes ?? [];
}
