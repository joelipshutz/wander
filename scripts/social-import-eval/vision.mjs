import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { safeSegment, stableHash } from "./lib.mjs";
import { fetchAcquiredMediaBytes } from "./media.mjs";
import {
  runCredentialFreeProcess,
  secureTemporaryToolDirectory,
} from "./subprocess.mjs";

const moduleDirectory = dirname(fileURLToPath(import.meta.url));

let recognizerBinaryPromise;

async function compileRecognizer() {
  const toolDirectory = await secureTemporaryToolDirectory("recme-vision-ocr-");
  const sourcePath = join(moduleDirectory, "vision-ocr.swift");
  const binaryPath = join(toolDirectory, "vision-ocr");
  const moduleCachePath = join(toolDirectory, "swift-module-cache");
  await mkdir(moduleCachePath, { recursive: true });
  await runCredentialFreeProcess("/usr/bin/xcrun", [
    "swiftc",
    "-O",
    "-module-cache-path", moduleCachePath,
    "-parse-as-library",
    sourcePath,
    "-o", binaryPath,
  ], { timeoutMs: 180_000 });
  return binaryPath;
}

function recognizerBinary() {
  recognizerBinaryPromise ??= compileRecognizer();
  return recognizerBinaryPromise;
}

export async function recognizeWithAppleVision(
  media,
  outputDirectory,
  { includeVideo = false, socialPageURL = null } = {},
) {
  const toolDirectory = join(outputDirectory, ".tools");
  const downloadDirectory = join(toolDirectory, "media");
  await mkdir(downloadDirectory, { recursive: true });
  const downloads = [];
  for (const [index, item] of media.entries()) {
    const type = item.type === "video" && includeVideo ? "video" : "image";
    const sourceURL = type === "video" ? item.url : (item.type === "video" ? item.thumbnailURL : item.url);
    if (!sourceURL) {
      downloads.push({
        id: String(index),
        mediaIndex: index,
        type,
        error: { code: "no_supported_media_url", message: "No image or enabled video URL" },
      });
      continue;
    }
    const suffix = type === "video" ? ".mp4" : ".img";
    const path = join(
      downloadDirectory,
      safeSegment(String(index) + "-" + stableHash(sourceURL).slice(0, 12)) + suffix,
    );
    const maximumBytes = type === "video" ? 100_000_000 : 10_000_000;
    const download = await fetchAcquiredMediaBytes({
      url: sourceURL,
      privateRequestHeaders: item.privateRequestHeaders,
    }, {
      expectedKind: type,
      maximumBytes,
      socialPageURL,
    });
    if (download.error) {
      downloads.push({ id: String(index), mediaIndex: index, type, path, ...download });
      continue;
    }
    await writeFile(path, download.bytes);
    downloads.push({
      id: String(index),
      mediaIndex: index,
      type,
      path,
      byteCount: download.byteCount,
      contentType: download.mimeType,
      finalHost: download.finalHost,
    });
  }
  const ready = downloads.filter((item) => !item.error).map((item) => ({
    id: item.id,
    path: item.path,
    type: item.type,
    sampleIntervalMs: item.type === "video"
      ? Number(process.env.APPLE_VISION_VIDEO_INTERVAL_MS ?? 250)
      : null,
    maximumFrames: item.type === "video"
      ? Number(process.env.APPLE_VISION_VIDEO_MAX_FRAMES ?? 240)
      : null,
  }));
  let recognition = { engine: "apple-vision-production-settings-v1", results: [] };
  if (ready.length > 0) {
    const binaryPath = await recognizerBinary();
    const { output } = await runCredentialFreeProcess(binaryPath, [], {
      input: JSON.stringify({ items: ready }),
      timeoutMs: Math.max(600_000, ready.length * 120_000),
    });
    recognition = JSON.parse(output);
    if (recognition.fatalError) throw new Error(recognition.fatalError);
  }
  const resultsByID = new Map((recognition.results ?? []).map((item) => [item.id, item]));
  const results = downloads.map((download) => ({
    ...download,
    path: undefined,
    recognition: resultsByID.get(download.id) ?? null,
  }));
  return { engine: recognition.engine, results };
}
