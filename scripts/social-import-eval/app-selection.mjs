import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runCredentialFreeProcess, secureTemporaryToolDirectory } from "./subprocess.mjs";

const directory = dirname(fileURLToPath(import.meta.url));
const repo = resolve(directory, "../..");
let compiler;

// Compile the app's implementation, not a copy of its scoring rules. The
// adapter supplies only the value fields consumed by that implementation.
async function compile() {
  const matcherPath = join(repo, "Wander/Services/PlaceImportCandidateMatcher.swift");
  const metadata = await readFile(join(repo, "Wander/Services/SocialPlaceImportMetadata.swift"), "utf8");
  const start = metadata.indexOf("enum SocialImportCountry {");
  const end = metadata.indexOf("\nenum SocialGuideTextParser {", start);
  if (start < 0 || end < start || metadata.indexOf("enum SocialImportCountry {", start + 1) >= 0) {
    throw new Error("Cannot isolate production country implementation");
  }
  const country = metadata.slice(start, end);
  const matcher = await readFile(matcherPath, "utf8");
  const temporary = await secureTemporaryToolDirectory("recme-app-selection-");
  const countryPath = join(temporary, "Country.swift");
  const binary = join(temporary, "app-selection");
  const moduleCache = join(temporary, "module-cache");
  await mkdir(moduleCache);
  await writeFile(countryPath, "import Foundation\n" + country, { mode: 0o600 });
  await runCredentialFreeProcess("/usr/bin/xcrun", [
    "swiftc", "-parse-as-library", "-module-cache-path", moduleCache,
    matcherPath, countryPath, join(directory, "app-selection-driver.swift"), "-o", binary,
  ]);
  const sha256 = value => createHash("sha256").update(value).digest("hex");
  return { binary, sourceHashes: { matcher: sha256(matcher), country: sha256(country) } };
}

/**
 * Offline production matcher decisions for server-returned Google candidates.
 * This is not the complete import store: no MapKit fallback, UI, persistence,
 * or independently verified POI truth. bestScore is NOT a probability.
 */
export async function appSelectionForHints(hints) {
  if (!Array.isArray(hints) || hints.length > 150) throw new Error("Invalid bounded hint list");
  const { binary, sourceHashes } = await (compiler ??= compile());
  const { output } = await runCredentialFreeProcess(binary, [], {
    input: JSON.stringify({ hints }), timeoutMs: 30_000,
  });
  return {
    evaluator: "production-swift-google-candidate-selection-v1",
    sourceHashes,
    scoringContract: "actual matcher; wire adapter; no MapKit fallback or full-store claims",
    ...JSON.parse(output),
  };
}
