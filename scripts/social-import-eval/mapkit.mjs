import { spawn } from "node:child_process";
import { mkdir, stat } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const moduleDirectory = dirname(fileURLToPath(import.meta.url));

async function exists(path) {
  try {
    await stat(path);
    return true;
  } catch (error) {
    if (error?.code === "ENOENT") return false;
    throw error;
  }
}

function runProcess(command, args, { input = null, timeoutMs = 120_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      env: process.env,
      stdio: ["pipe", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      child.kill("SIGTERM");
      reject(new Error(command + " timed out after " + timeoutMs + " ms"));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      const output = Buffer.concat(stdout).toString("utf8");
      const diagnostics = Buffer.concat(stderr).toString("utf8");
      if (code === 0) {
        resolve({ output, diagnostics });
      } else {
        reject(new Error(
          command + " exited " + code + (diagnostics ? ": " + diagnostics.slice(0, 4_000) : ""),
        ));
      }
    });
    if (input != null) child.stdin.end(input);
    else child.stdin.end();
  });
}

async function compileResolver(toolDirectory) {
  await mkdir(toolDirectory, { recursive: true });
  const binaryPath = join(toolDirectory, "mapkit-resolver");
  const sourcePath = join(moduleDirectory, "mapkit-resolver.swift");
  const moduleCachePath = join(toolDirectory, "swift-module-cache");
  const [binaryPresent, sourceStats, binaryStats] = await Promise.all([
    exists(binaryPath),
    stat(sourcePath),
    stat(binaryPath).catch(() => null),
  ]);
  if (binaryPresent && binaryStats?.mtimeMs >= sourceStats.mtimeMs) return binaryPath;
  await mkdir(moduleCachePath, { recursive: true });
  await runProcess("xcrun", [
    "swiftc",
    "-module-cache-path", moduleCachePath,
    "-parse-as-library",
    sourcePath,
    "-o", binaryPath,
  ], { timeoutMs: 120_000 });
  return binaryPath;
}

export async function resolveWithMapKit(hints, outputDirectory) {
  const toolDirectory = join(outputDirectory, ".tools");
  const binaryPath = await compileResolver(toolDirectory);
  const requests = hints.map((hint, index) => ({
    id: String(index),
    name: hint.name,
    area: hint.area ?? null,
    allowNearSpellingMatch: [
      "ocr", "video_text", "accessibility_text", "image_text",
    ].includes(hint.modality),
  }));
  if (requests.length === 0) {
    return { resolver: "mapkit-production-query-and-threshold-mirror-v3", results: [] };
  }
  const { output } = await runProcess(binaryPath, [], {
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
  const toolDirectory = join(outputDirectory, ".tools");
  const binaryPath = await compileResolver(toolDirectory);
  const { output } = await runProcess(binaryPath, [], {
    input: JSON.stringify({ requests: [], geographyProbes }),
    timeoutMs: 120_000,
  });
  const response = JSON.parse(output);
  if (response.fatalError) throw new Error(response.fatalError);
  return response.geographyProbes ?? [];
}
