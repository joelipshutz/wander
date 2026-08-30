import { fetchJSON } from "./http.ts";
import {
  asRecord,
  cleanMultilineString,
  cleanString,
  sourceValueMatches,
} from "./source.ts";
import type {
  AcquiredMedia,
  AcquisitionEvidence,
  RuntimeDependencies,
  SocialSource,
  TaggedLocation,
} from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

const terminalRunStatuses = new Set([
  "SUCCEEDED",
  "FAILED",
  "ABORTED",
  "TIMED-OUT",
  "TIMED_OUT",
  "FINISHED",
]);

export type ApifyActorRequest = {
  actor: string;
  input: Record<string, unknown>;
};

export function apifyActorRequest(source: SocialSource): ApifyActorRequest {
  if (source.platform === "tiktok") {
    return {
      actor: "clockworks/tiktok-scraper",
      input: {
        postURLs: [source.url],
        resultsPerPage: 1,
        shouldDownloadVideos: true,
        shouldDownloadSlideshowImages: true,
        aiVideoDescription: false,
      },
    };
  }
  if (source.contentType === "reel") {
    return {
      actor: "apify/instagram-reel-scraper",
      input: {
        username: [source.url],
        resultsLimit: 1,
        includeDownloadedVideo: true,
      },
    };
  }
  return {
    actor: "apify/instagram-scraper",
    input: {
      directUrls: [source.url],
      resultsType: "posts",
      resultsLimit: 1,
    },
  };
}

export async function acquireWithApify(
  source: SocialSource,
  token: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
  cancellationSignal?: AbortSignal,
): Promise<AcquisitionEvidence> {
  assertNotCancelled(cancellationSignal);
  const actorRequest = apifyActorRequest(source);
  const actorSlug = actorRequest.actor.replace("/", "~");
  const runURL =
    `https://api.apify.com/v2/actors/${encodeURIComponent(actorSlug)}` +
    "/runs?waitForFinish=0&timeout=90&maxItems=1&maxTotalChargeUsd=1";
  // Do not apply request cancellation to this first call. Once Apify accepts
  // paid work, its response is the only safe way to learn the exact run ID we
  // may need to abort. The call is still bounded by its own short timeout and
  // the overall deadline.
  const started = await fetchJSON(
    runURL,
    {
      method: "POST",
      headers: providerHeaders(token),
      body: JSON.stringify(actorRequest.input),
    },
    1_000_000,
    15_000,
    deadline,
    dependencies,
  );
  if (!started.response.ok) throw new SocialImportError("apify_run_http_error");
  let run = asRecord(asRecord(started.body)?.data) ?? asRecord(started.body);
  if (!run) throw new SocialImportError("apify_run_invalid");
  const runID = apifyRunID(run.id);
  if (!runID) throw new SocialImportError("apify_run_invalid");
  let status = runStatus(run);
  const cancellableDependencies = dependenciesWithCancellation(
    dependencies,
    cancellationSignal,
  );

  if (!terminalRunStatuses.has(status)) {
    try {
      for (let attempt = 0; !terminalRunStatuses.has(status); attempt += 1) {
        assertNotCancelled(cancellationSignal);
        if (attempt >= 24) throw new SocialImportError("apify_run_timeout");
        const delay = Math.min(
          4_000,
          750 + attempt * 250,
          deadline.remaining(4_000),
        );
        await cancellableSleep(
          delay,
          dependencies,
          cancellationSignal,
        );
        deadline.assertAvailable();
        const polled = await fetchJSON(
          `https://api.apify.com/v2/actor-runs/${encodeURIComponent(runID)}`,
          { headers: providerHeaders(token) },
          1_000_000,
          15_000,
          deadline,
          cancellableDependencies,
        );
        if (!polled.response.ok) {
          throw new SocialImportError("apify_poll_http_error");
        }
        const nextRun = asRecord(asRecord(polled.body)?.data) ??
          asRecord(polled.body);
        if (!nextRun || apifyRunID(nextRun.id) !== runID) {
          throw new SocialImportError("apify_run_invalid");
        }
        run = nextRun;
        status = runStatus(run);
      }
    } catch (error) {
      if (!terminalRunStatuses.has(status)) {
        await abortApifyRun(runID, token, dependencies);
      }
      if (cancellationSignal?.aborted) {
        throw new SocialImportError("apify_run_cancelled");
      }
      throw error;
    }
  }
  if (status !== "SUCCEEDED") {
    throw new SocialImportError("apify_run_failed");
  }

  const datasetID = cleanString(run.defaultDatasetId, 160);
  if (!datasetID) throw new SocialImportError("apify_dataset_missing");
  const dataset = await fetchJSON(
    `https://api.apify.com/v2/datasets/${
      encodeURIComponent(datasetID)
    }/items?clean=true&format=json`,
    { headers: providerHeaders(token) },
    10_000_000,
    25_000,
    deadline,
    cancellableDependencies,
  );
  if (!dataset.response.ok) {
    throw new SocialImportError("apify_dataset_http_error");
  }
  return normalizeApifyDataset(dataset.body, source);
}

async function abortApifyRun(
  runID: string,
  token: string,
  dependencies: RuntimeDependencies,
): Promise<void> {
  try {
    const url = new URL(
      `https://api.apify.com/v2/actor-runs/${encodeURIComponent(runID)}/abort`,
    );
    url.searchParams.set("gracefully", "true");
    await fetchJSON(
      url.toString(),
      {
        method: "POST",
        headers: providerHeaders(token),
      },
      64_000,
      5_000,
      // Cleanup must still get a short, independent window when the import's
      // main deadline has already expired.
      new Deadline(5_000, dependencies.now),
      dependencies,
    );
  } catch {
    // This is best-effort cleanup. Never replace the bounded import failure
    // with provider details from an abort failure.
  }
}

function runStatus(run: Record<string, unknown>): string {
  return String(run.status ?? "").trim().toUpperCase();
}

function apifyRunID(value: unknown): string | null {
  const identifier = cleanString(value, 160);
  return identifier && /^[A-Za-z0-9_-]+$/.test(identifier) ? identifier : null;
}

function assertNotCancelled(signal?: AbortSignal): void {
  if (signal?.aborted) throw new SocialImportError("apify_run_cancelled");
}

async function cancellableSleep(
  milliseconds: number,
  dependencies: RuntimeDependencies,
  signal?: AbortSignal,
): Promise<void> {
  assertNotCancelled(signal);
  if (!signal) {
    await dependencies.sleep(milliseconds);
    return;
  }
  let onAbort: (() => void) | null = null;
  const cancellation = new Promise<never>((_resolve, reject) => {
    onAbort = () => reject(new SocialImportError("apify_run_cancelled"));
    signal.addEventListener("abort", onAbort, { once: true });
  });
  try {
    await Promise.race([dependencies.sleep(milliseconds), cancellation]);
  } finally {
    if (onAbort) signal.removeEventListener("abort", onAbort);
  }
  assertNotCancelled(signal);
}

function dependenciesWithCancellation(
  dependencies: RuntimeDependencies,
  cancellationSignal?: AbortSignal,
): RuntimeDependencies {
  if (!cancellationSignal) return dependencies;
  return {
    ...dependencies,
    fetch: (async (input, init) => {
      assertNotCancelled(cancellationSignal);
      const signals = [init?.signal, cancellationSignal].filter(
        (signal): signal is AbortSignal =>
          signal !== null && signal !== undefined,
      );
      return await dependencies.fetch(input, {
        ...init,
        signal: signals.length === 1 ? signals[0] : AbortSignal.any(signals),
      });
    }) as typeof fetch,
  };
}

export function normalizeApifyDataset(
  raw: unknown,
  source: SocialSource,
): AcquisitionEvidence {
  const records = recordsFrom(raw);
  if (records.length === 0) throw new SocialImportError("vendor_empty_dataset");
  if (records.some((record) => vendorErrorFields(record).length > 0)) {
    throw new SocialImportError("vendor_item_error");
  }
  const record = records.find((candidate) =>
    sourceValues(candidate)
      .some((value) => sourceValueMatches(value, source))
  );
  if (!record) {
    const hasIdentity = records.some((candidate) =>
      sourceValues(candidate).length > 0
    );
    throw new SocialImportError(
      hasIdentity ? "vendor_source_mismatch" : "vendor_source_unverified",
    );
  }

  const evidence = normalizeRecord(record);
  if (evidence.media.length === 0) {
    throw new SocialImportError("vendor_missing_media_assets");
  }
  if (
    source.contentType === "reel" &&
    !evidence.media.some((item) => item.kind === "video")
  ) {
    throw new SocialImportError("vendor_missing_video_asset");
  }
  if (
    source.platform === "tiktok" && !isSlideshow(record) &&
    !evidence.media.some((item) => item.kind === "video")
  ) {
    throw new SocialImportError("vendor_missing_video_asset");
  }
  return evidence;
}

function normalizeRecord(record: Record<string, unknown>): AcquisitionEvidence {
  const pending: Array<Omit<AcquiredMedia, "id">> = [];
  const postContent = arrayValue(record.post_content ?? record.postContent);
  for (const [index, value] of postContent.entries()) {
    const item = asRecord(value);
    if (!item) continue;
    addMedia(pending, {
      index: numberValue(item.index) ?? index,
      kind: String(item.type ?? "").toLowerCase().includes("video")
        ? "video"
        : "image",
      url: item.url ?? item.video_url ?? item.image_url,
      thumbnailURL: null,
      altText: item.alt_text ?? item.altText,
    });
  }

  const children = arrayValue(
    record.childPosts ?? record.child_posts ?? record.carousel_media,
  );
  for (const [index, value] of children.entries()) {
    const item = asRecord(value);
    if (!item) continue;
    const video = item.videoUrl ?? item.video_url ?? item.videoPlayUrl;
    const image = item.displayUrl ?? item.display_url ?? item.imageUrl ??
      item.image_url;
    addMedia(pending, {
      index,
      kind: cleanString(video, 4_096) ? "video" : "image",
      url: video ?? image,
      thumbnailURL: cleanString(video, 4_096) ? image : null,
      altText: item.alt ?? item.altText ?? item.accessibility_caption,
    });
  }

  for (const values of [record.images, record.photos]) {
    for (const [index, value] of arrayValue(values).entries()) {
      const item = asRecord(value);
      addMedia(pending, {
        index,
        kind: "image",
        url: typeof value === "string" ? value : item?.url ?? item?.image_url,
        thumbnailURL: null,
        altText: item?.alt_text ?? item?.altText,
      });
    }
  }

  for (
    const [index, value] of arrayValue(record.slideshowImageLinks).entries()
  ) {
    const item = asRecord(value);
    addMedia(pending, {
      index,
      kind: "image",
      url: typeof value === "string"
        ? value
        : item?.downloadLink ?? item?.tiktokLink ?? item?.url,
      thumbnailURL: null,
      altText: item?.alt_text ?? item?.altText,
    });
  }

  const slideshow = isSlideshow(record);
  const downloaded = arrayValue(record.mediaUrls)
    .map(mediaURL)
    .filter((value): value is string => value !== null);
  if (slideshow) {
    for (const [index, value] of downloaded.entries()) {
      addMedia(pending, {
        index,
        kind: "image",
        url: value,
        thumbnailURL: null,
        altText: null,
      });
    }
  }

  const videoMeta = asRecord(record.videoMeta) ?? {};
  const videoURL = record.video_url ?? record.videoUrl ?? record.downloadAddr ??
    record.videoPlayUrl ?? asRecord(record.video)?.url ??
    videoMeta.downloadAddr;
  const persistentVideo = record.downloadedVideo ?? record.downloaded_video ??
    record.videoDownloadURL ?? (!slideshow ? downloaded[0] : null);
  if (cleanString(videoURL, 4_096) || cleanString(persistentVideo, 4_096)) {
    addMedia(pending, {
      index: pending.length,
      kind: "video",
      url: persistentVideo ?? videoURL,
      thumbnailURL: record.thumbnail_url ?? record.thumbnailUrl ??
        record.thumbnail ??
        record.displayUrl ?? videoMeta.coverUrl,
      altText: null,
    });
  } else {
    addMedia(pending, {
      index: pending.length,
      kind: "image",
      url: record.displayUrl ?? record.display_url ?? record.imageUrl ??
        record.image_url,
      thumbnailURL: null,
      altText: record.alt ?? record.altText ?? record.accessibility_caption,
    });
  }

  pending.sort((left, right) => left.index - right.index);
  const media = pending.slice(0, 150).map((item, index) => ({
    ...item,
    id: `media:${index}`,
  }));
  return {
    title: cleanString(record.title, 500),
    caption: cleanMultilineString(
      record.description ?? record.caption ?? record.text ?? record.title,
      30_000,
    ),
    taggedLocations: taggedLocations(record),
    media,
  };
}

function taggedLocations(record: Record<string, unknown>): TaggedLocation[] {
  const metadata = asRecord(record.locationMeta);
  const value = metadata?.locationName ?? record.locationName ??
    record.location_name ?? record.location;
  if (typeof value === "string") {
    const name = cleanString(value, 200);
    return name
      ? [{ name, area: cleanString(metadata?.address ?? record.address, 300) }]
      : [];
  }
  const location = asRecord(value);
  const name = cleanString(location?.name, 200);
  return name
    ? [{ name, area: cleanString(location?.address ?? location?.city, 300) }]
    : [];
}

function addMedia(
  output: Array<Omit<AcquiredMedia, "id">>,
  value: {
    index: number;
    kind: "image" | "video";
    url: unknown;
    thumbnailURL: unknown;
    altText: unknown;
  },
): void {
  const url = mediaURL(value.url);
  if (!url || output.some((item) => item.url === url)) return;
  output.push({
    index: Number.isFinite(value.index) ? value.index : output.length,
    kind: value.kind,
    url,
    thumbnailURL: mediaURL(value.thumbnailURL),
    altText: cleanString(value.altText, 2_000),
  });
}

function sourceValues(record: Record<string, unknown>): string[] {
  const values: string[] = [];
  const add = (value: unknown) => {
    if (Array.isArray(value)) value.forEach(add);
    else if (typeof value === "string" || typeof value === "number") {
      const cleaned = cleanString(String(value), 4_096);
      if (cleaned) values.push(cleaned);
    }
  };
  [
    record.inputUrl,
    record.inputURL,
    record.input_url,
    record.url,
    record.postUrl,
    record.postURL,
    record.post_url,
    record.webVideoUrl,
    record.submittedVideoUrl,
    record.sourceUrl,
    record.source_url,
    record.shortCode,
    record.shortcode,
    record.code,
    record.id,
    record.videoId,
    record.videoID,
    record.awemeId,
  ].forEach(add);
  const input = asRecord(record.input);
  if (input) {
    [input.url, input.inputUrl, input.postUrl, input.postURLs, input.directUrls]
      .forEach(add);
  } else {
    add(record.input);
  }
  const videoMeta = asRecord(record.videoMeta);
  if (videoMeta) [videoMeta.id, videoMeta.videoId].forEach(add);
  return [...new Set(values)];
}

function vendorErrorFields(record: Record<string, unknown>): string[] {
  const fields = [
    "error",
    "errorCode",
    "error_code",
    "errorDescription",
    "error_description",
    "requestErrorMessages",
    "invalidUrls",
    "invalidURLs",
  ].filter((field) => meaningfulError(record[field]));
  if (["ERROR", "FAILED"].includes(String(record.status ?? "").toUpperCase())) {
    fields.push("status");
  }
  return fields;
}

function meaningfulError(value: unknown): boolean {
  if (value === null || value === undefined || value === false || value === 0) {
    return false;
  }
  if (typeof value === "string") return value.trim().length > 0;
  if (Array.isArray(value)) return value.length > 0;
  if (typeof value === "object") {
    return Object.keys(value as Record<string, unknown>).length > 0;
  }
  return true;
}

function isSlideshow(record: Record<string, unknown>): boolean {
  const type = String(
    record.type ?? record.contentType ?? record.postType ?? "",
  ).toLowerCase();
  return record.isSlideshow === true || record.isPhotoMode === true ||
    type.includes("slideshow") ||
    type.includes("photo_mode") ||
    arrayValue(record.slideshowImageLinks).length > 0;
}

function recordsFrom(value: unknown): Record<string, unknown>[] {
  if (Array.isArray(value)) return value.map(asRecord).filter(isRecord);
  const record = asRecord(value);
  if (!record) return [];
  for (const key of ["data", "results", "items"]) {
    if (Array.isArray(record[key])) {
      return (record[key] as unknown[]).map(asRecord).filter(isRecord);
    }
  }
  return [record];
}

function isRecord(
  value: Record<string, unknown> | null,
): value is Record<string, unknown> {
  return value !== null;
}

function arrayValue(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function numberValue(value: unknown): number | null {
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function mediaURL(value: unknown): string | null {
  if (typeof value === "string") return cleanString(value, 4_096);
  const record = asRecord(value);
  return cleanString(
    record?.url ?? record?.downloadLink ?? record?.downloadUrl,
    4_096,
  );
}

function providerHeaders(token: string): Record<string, string> {
  return {
    authorization: `Bearer ${token}`,
    accept: "application/json",
    "content-type": "application/json",
  };
}
