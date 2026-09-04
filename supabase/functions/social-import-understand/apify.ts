import { fetchJSON } from "./http.ts";
import {
  asRecord,
  cleanMultilineString,
  cleanString,
  sourceValueMatches,
} from "./source.ts";
import { mayReceiveApifyAuthorization, validatedMediaURL } from "./media.ts";
import type {
  AcquiredMedia,
  AcquisitionEvidence,
  InstagramProfileAlias,
  InstagramTaggedProfile,
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

export const maximumInstagramProfileAliases = 20;
export const instagramProfileEnrichmentDeadlineMilliseconds = 24_000;
export const minimumProfileEnrichmentGlobalBudgetMilliseconds = 95_000;
export const maximumRestrictedInstagramMediaItems = 20;
export const restrictedInstagramMediaFallbackDeadlineMilliseconds = 60_000;
const minimumRestrictedInstagramFallbackBudgetMilliseconds = 5_000;

type ApifyRunConfiguration = {
  actor: string;
  input: Record<string, unknown>;
  timeoutSeconds: number;
  maxItems: number;
  maxTotalChargeUsd: string;
  startRequestTimeoutMilliseconds: number;
  pollRequestTimeoutMilliseconds: number;
  maximumPollAttempts: number;
  initialPollDelayMilliseconds: number;
  maximumPollDelayMilliseconds: number;
  acceptPartialResults?: boolean;
};

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
  // The general Instagram Scraper returns the caption and direct reel video
  // URL in one post record. In a real Ojai reel canary it completed in seven
  // seconds, while the dedicated Reel Scraper produced no dataset and was
  // still running after 105 seconds. The general actor also keeps reels and
  // posts on the same source-identity and normalization path.
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
  const actorRequest = apifyActorRequest(source);
  const run = await runApifyActor(
    {
      ...actorRequest,
      timeoutSeconds: 90,
      maxItems: 1,
      maxTotalChargeUsd: "1",
      startRequestTimeoutMilliseconds: 15_000,
      pollRequestTimeoutMilliseconds: 15_000,
      maximumPollAttempts: 24,
      initialPollDelayMilliseconds: 750,
      maximumPollDelayMilliseconds: 4_000,
    },
    token,
    deadline,
    dependencies,
    cancellationSignal,
  );
  const cancellableDependencies = dependenciesWithCancellation(
    dependencies,
    cancellationSignal,
  );

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
  if (isValidatedRestrictedInstagramItem(dataset.body, source)) {
    return await acquireRestrictedInstagramMedia(
      source,
      token,
      deadline,
      dependencies,
      cancellationSignal,
    );
  }
  return normalizeApifyDataset(dataset.body, source);
}

async function acquireRestrictedInstagramMedia(
  source: SocialSource,
  token: string,
  parentDeadline: Deadline,
  dependencies: RuntimeDependencies,
  cancellationSignal?: AbortSignal,
): Promise<AcquisitionEvidence> {
  assertNotCancelled(cancellationSignal);
  const availableMilliseconds = parentDeadline.remaining();
  if (
    availableMilliseconds < minimumRestrictedInstagramFallbackBudgetMilliseconds
  ) {
    throw new SocialImportError("deadline_exceeded");
  }
  const deadline = new Deadline(
    Math.min(
      restrictedInstagramMediaFallbackDeadlineMilliseconds,
      availableMilliseconds,
    ),
    dependencies.now,
  );
  const run = await runApifyActor(
    {
      actor: "crawlerbros/instagram-downloader-api",
      input: { postUrls: [source.url] },
      timeoutSeconds: 55,
      maxItems: maximumRestrictedInstagramMediaItems,
      maxTotalChargeUsd: "0.10",
      startRequestTimeoutMilliseconds: 5_000,
      pollRequestTimeoutMilliseconds: 4_000,
      maximumPollAttempts: 32,
      initialPollDelayMilliseconds: 500,
      maximumPollDelayMilliseconds: 2_000,
    },
    token,
    deadline,
    dependencies,
    cancellationSignal,
  );

  const datasetID = cleanString(run.defaultDatasetId, 160);
  if (!datasetID) throw new SocialImportError("apify_dataset_missing");
  const datasetURL = new URL(
    `https://api.apify.com/v2/datasets/${encodeURIComponent(datasetID)}/items`,
  );
  datasetURL.searchParams.set("clean", "true");
  datasetURL.searchParams.set("format", "json");
  datasetURL.searchParams.set(
    "fields",
    "post_url,type,download_status,download_url",
  );
  datasetURL.searchParams.set(
    "limit",
    String(maximumRestrictedInstagramMediaItems),
  );
  const dataset = await fetchJSON(
    datasetURL.toString(),
    { headers: providerHeaders(token) },
    512_000,
    5_000,
    deadline,
    dependenciesWithCancellation(dependencies, cancellationSignal),
  );
  if (!dataset.response.ok) {
    throw new SocialImportError("apify_dataset_http_error");
  }
  return normalizeRestrictedInstagramMediaDataset(dataset.body, source);
}

export async function acquireInstagramProfileAliases(
  usernames: string[],
  token: string,
  parentDeadline: Deadline,
  dependencies: RuntimeDependencies,
  cancellationSignal?: AbortSignal,
): Promise<InstagramProfileAlias[]> {
  const requested = normalizedRequestedUsernames(usernames);
  if (requested.length === 0) return [];
  assertNotCancelled(cancellationSignal);

  let globalRemaining: number;
  try {
    globalRemaining = parentDeadline.remaining();
  } catch {
    return [];
  }
  if (globalRemaining < minimumProfileEnrichmentGlobalBudgetMilliseconds) {
    return [];
  }

  const childDeadline = new Deadline(
    Math.min(
      instagramProfileEnrichmentDeadlineMilliseconds,
      globalRemaining,
    ),
    dependencies.now,
  );
  const run = await runApifyActor(
    {
      actor: "apify/instagram-profile-scraper",
      input: {
        usernames: requested,
        includeAboutSection: false,
      },
      timeoutSeconds: 18,
      maxItems: maximumInstagramProfileAliases,
      maxTotalChargeUsd: "0.10",
      startRequestTimeoutMilliseconds: 5_000,
      pollRequestTimeoutMilliseconds: 4_000,
      maximumPollAttempts: 28,
      initialPollDelayMilliseconds: 350,
      maximumPollDelayMilliseconds: 1_000,
      acceptPartialResults: true,
    },
    token,
    childDeadline,
    dependencies,
    cancellationSignal,
  );
  const datasetID = cleanString(run.defaultDatasetId, 160);
  if (!datasetID) throw new SocialImportError("apify_dataset_missing");

  const datasetURL = new URL(
    `https://api.apify.com/v2/datasets/${encodeURIComponent(datasetID)}/items`,
  );
  datasetURL.searchParams.set("clean", "true");
  datasetURL.searchParams.set("format", "json");
  datasetURL.searchParams.set(
    "fields",
    "username,fullName,businessCategoryName,isBusinessAccount",
  );
  datasetURL.searchParams.set(
    "limit",
    String(maximumInstagramProfileAliases),
  );
  const dataset = await fetchJSON(
    datasetURL.toString(),
    { headers: providerHeaders(token) },
    256_000,
    4_000,
    childDeadline,
    dependenciesWithCancellation(dependencies, cancellationSignal),
  );
  if (!dataset.response.ok) {
    throw new SocialImportError("apify_dataset_http_error");
  }
  return normalizeInstagramProfileAliases(dataset.body, requested);
}

export function normalizeInstagramProfileAliases(
  raw: unknown,
  requestedUsernames: string[],
): InstagramProfileAlias[] {
  const requested = new Set(normalizedRequestedUsernames(requestedUsernames));
  const aliases = new Map<string, InstagramProfileAlias>();
  const duplicated = new Set<string>();
  for (
    const record of recordsFrom(raw).slice(
      0,
      2 * maximumInstagramProfileAliases,
    )
  ) {
    const username = normalizedInstagramUsername(record.username);
    const fullName = cleanString(record.fullName, 160);
    if (!username || !requested.has(username) || !fullName) continue;
    if (aliases.has(username)) {
      aliases.delete(username);
      duplicated.add(username);
      continue;
    }
    if (duplicated.has(username)) continue;
    const businessCategoryName = cleanString(
      record.businessCategoryName,
      120,
    );
    aliases.set(username, {
      username,
      fullName,
      ...(businessCategoryName ? { businessCategoryName } : {}),
      ...(typeof record.isBusinessAccount === "boolean"
        ? { isBusinessAccount: record.isBusinessAccount }
        : {}),
    });
  }
  return [...aliases.values()];
}

async function runApifyActor(
  configuration: ApifyRunConfiguration,
  token: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
  cancellationSignal?: AbortSignal,
): Promise<Record<string, unknown>> {
  assertNotCancelled(cancellationSignal);
  const actorSlug = configuration.actor.replace("/", "~");
  const runURL = new URL(
    `https://api.apify.com/v2/actors/${encodeURIComponent(actorSlug)}/runs`,
  );
  runURL.searchParams.set("waitForFinish", "0");
  runURL.searchParams.set("timeout", String(configuration.timeoutSeconds));
  runURL.searchParams.set("maxItems", String(configuration.maxItems));
  runURL.searchParams.set(
    "maxTotalChargeUsd",
    configuration.maxTotalChargeUsd,
  );
  // Do not apply request cancellation to this first call. Once Apify accepts
  // paid work, its response is the only safe way to learn the exact run ID we
  // may need to abort. The call is still bounded by its own short timeout and
  // the supplied deadline.
  const started = await fetchJSON(
    runURL.toString(),
    {
      method: "POST",
      headers: providerHeaders(token),
      body: JSON.stringify(configuration.input),
    },
    1_000_000,
    configuration.startRequestTimeoutMilliseconds,
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
        if (attempt >= configuration.maximumPollAttempts) {
          throw new SocialImportError("apify_run_timeout");
        }
        const delay = Math.min(
          configuration.maximumPollDelayMilliseconds,
          configuration.initialPollDelayMilliseconds + attempt * 250,
          deadline.remaining(configuration.maximumPollDelayMilliseconds),
        );
        await cancellableSleep(delay, dependencies, cancellationSignal);
        deadline.assertAvailable();
        const polled = await fetchJSON(
          `https://api.apify.com/v2/actor-runs/${encodeURIComponent(runID)}`,
          { headers: providerHeaders(token) },
          1_000_000,
          configuration.pollRequestTimeoutMilliseconds,
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
  const partialDatasetAvailable = configuration.acceptPartialResults === true &&
    (status === "TIMED-OUT" || status === "TIMED_OUT") &&
    cleanString(run.defaultDatasetId, 160) !== null;
  if (status !== "SUCCEEDED" && !partialDatasetAvailable) {
    throw new SocialImportError("apify_run_failed");
  }
  return run;
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

function normalizedRequestedUsernames(values: string[]): string[] {
  const usernames: string[] = [];
  const seen = new Set<string>();
  for (const value of values) {
    const username = normalizedInstagramUsername(value);
    if (!username || seen.has(username)) continue;
    seen.add(username);
    usernames.push(username);
    if (usernames.length >= maximumInstagramProfileAliases) break;
  }
  return usernames;
}

function normalizedInstagramUsername(value: unknown): string | null {
  const username = cleanString(value, 64)?.toLocaleLowerCase("en-US") ?? null;
  return username &&
      /^[a-z0-9_](?:[a-z0-9_]|\.(?=[a-z0-9_])){0,29}$/u.test(username)
    ? username
    : null;
}

function isValidatedRestrictedInstagramItem(
  raw: unknown,
  source: SocialSource,
): boolean {
  if (source.platform !== "instagram") return false;
  const records = recordsFrom(raw);
  if (records.length !== 1) return false;
  const record = records[0];
  if (
    !sourceValues(record).some((value) => sourceValueMatches(value, source))
  ) return false;
  if (
    cleanString(record.error, 100)?.toLocaleLowerCase("en-US") !==
      "restricted_page"
  ) return false;
  return vendorErrorFields(record).every((field) =>
    field === "error" || field === "errorDescription" ||
    field === "error_description"
  );
}

function normalizeRestrictedInstagramMediaDataset(
  raw: unknown,
  source: SocialSource,
): AcquisitionEvidence {
  const records = recordsFrom(raw);
  if (records.length === 0) throw new SocialImportError("vendor_empty_dataset");
  if (records.length > maximumRestrictedInstagramMediaItems) {
    throw new SocialImportError("vendor_item_error");
  }
  if (records.some((record) => vendorErrorFields(record).length > 0)) {
    throw new SocialImportError("vendor_item_error");
  }

  const pending: Array<Omit<AcquiredMedia, "id">> = [];
  for (const [index, record] of records.entries()) {
    const identities = sourceValues(record);
    if (identities.length === 0) {
      throw new SocialImportError("vendor_source_unverified");
    }
    if (!identities.some((value) => sourceValueMatches(value, source))) {
      throw new SocialImportError("vendor_source_mismatch");
    }
    const status = cleanString(record.download_status, 40)
      ?.toLocaleLowerCase("en-US");
    const kind = cleanString(record.type, 40)?.toLocaleLowerCase("en-US");
    const url = restrictedInstagramDownloadURL(record.download_url);
    if (
      status !== "finished" || (kind !== "image" && kind !== "video") || !url
    ) {
      throw new SocialImportError("vendor_missing_media_assets");
    }
    addMedia(pending, {
      index,
      kind,
      url,
      thumbnailURL: null,
      altText: null,
    });
  }
  if (pending.length === 0) {
    throw new SocialImportError("vendor_missing_media_assets");
  }
  if (
    source.contentType === "reel" &&
    !pending.some((item) => item.kind === "video")
  ) {
    throw new SocialImportError("vendor_missing_video_asset");
  }
  return {
    title: null,
    caption: null,
    taggedLocations: [],
    media: pending.map((item, index) => ({ ...item, id: `media:${index}` })),
  };
}

function restrictedInstagramDownloadURL(value: unknown): string | null {
  const candidate = cleanString(value, 4_096);
  if (!candidate) return null;
  try {
    const url = validatedMediaURL(candidate);
    return mayReceiveApifyAuthorization(url) ? url.toString() : null;
  } catch {
    return null;
  }
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
  const orderedChildren = orderedChildMedia(record);
  const declaredChildren = declaredChildMediaCount(record);
  const childrenAreIncomplete = declaredChildren !== null &&
    orderedChildren.length < declaredChildren;
  const topLevelMedia = childrenAreIncomplete
    ? topLevelMediaForRecord(record)
    : [];
  if (
    orderedChildren.length > 0 &&
    (!childrenAreIncomplete || topLevelMedia.length <= orderedChildren.length)
  ) {
    pending.push(...orderedChildren);
  } else {
    pending.push(
      ...(topLevelMedia.length > 0
        ? topLevelMedia
        : topLevelMediaForRecord(record)),
    );
  }

  mergeChildMediaMetadata(pending, orderedChildren);
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

function topLevelMediaForRecord(
  record: Record<string, unknown>,
): Array<Omit<AcquiredMedia, "id">> {
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
      taggedProfiles: instagramTaggedProfiles(item),
    });
  }

  for (
    const values of [record.carouselImages, record.images, record.photos]
  ) {
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
  const videoURL = record.video_url ?? record.videoUrl ??
    record.downloadAddr ?? record.videoPlayUrl ??
    asRecord(record.video)?.url ??
    videoMeta.downloadAddr;
  const persistentVideo = record.downloadedVideo ??
    record.downloaded_video ?? record.videoDownloadURL ??
    (!slideshow ? downloaded[0] : null);
  if (cleanString(videoURL, 4_096) || cleanString(persistentVideo, 4_096)) {
    addMedia(pending, {
      index: pending.length,
      kind: "video",
      url: persistentVideo ?? videoURL,
      thumbnailURL: record.thumbnail_url ?? record.thumbnailUrl ??
        record.thumbnail ?? record.displayUrl ?? videoMeta.coverUrl,
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
  return pending;
}

function orderedChildMedia(
  record: Record<string, unknown>,
): Array<Omit<AcquiredMedia, "id">> {
  for (
    const children of [
      record.childPosts,
      record.child_posts,
      record.carousel_media,
    ].map(arrayValue)
  ) {
    const media: Array<Omit<AcquiredMedia, "id">> = [];
    for (const [index, value] of children.entries()) {
      const item = asRecord(value);
      if (!item) continue;
      const video = item.videoUrl ?? item.video_url ?? item.videoPlayUrl;
      const image = item.displayUrl ?? item.display_url ?? item.imageUrl ??
        item.image_url;
      addMedia(media, {
        index,
        kind: cleanString(video, 4_096) ? "video" : "image",
        url: video ?? image,
        thumbnailURL: cleanString(video, 4_096) ? image : null,
        altText: item.alt ?? item.altText ?? item.accessibility_caption,
        taggedProfiles: instagramTaggedProfiles(item),
      });
    }
    if (media.length > 0) return media;
  }
  return [];
}

function declaredChildMediaCount(
  record: Record<string, unknown>,
): number | null {
  const counts = [
    record.childPostsCount,
    record.child_posts_count,
    record.carouselImageCount,
    record.carouselMediaCount,
    record.carousel_media_count,
  ].map(numberValue).filter((value): value is number =>
    value !== null && Number.isInteger(value) && value > 0
  );
  for (
    const values of [
      record.post_content,
      record.postContent,
      record.carouselImages,
      record.images,
      record.photos,
      record.slideshowImageLinks,
    ]
  ) {
    const length = arrayValue(values).length;
    if (length > 0) counts.push(length);
  }
  return counts.length > 0 ? Math.max(...counts) : null;
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
  if (Array.isArray(value)) {
    const components = value
      .map((component) => cleanString(component, 200))
      .filter((component): component is string => component !== null)
      .slice(0, 4);
    return components.length > 0
      ? [{
        name: components[0],
        area: components.length > 1 ? components.slice(1).join(", ") : null,
      }]
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
    taggedProfiles?: InstagramTaggedProfile[];
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
    ...(value.taggedProfiles && value.taggedProfiles.length > 0
      ? { taggedProfiles: value.taggedProfiles }
      : {}),
  });
}

function mergeChildMediaMetadata(
  media: Array<Omit<AcquiredMedia, "id">>,
  children: Array<Omit<AcquiredMedia, "id">>,
): void {
  const childrenByURL = new Map(children.map((item) => [item.url, item]));
  for (const [index, item] of media.entries()) {
    const child = childrenByURL.get(item.url);
    if (!child) continue;
    media[index] = {
      ...item,
      altText: item.altText ?? child.altText,
      ...(child.taggedProfiles && child.taggedProfiles.length > 0
        ? { taggedProfiles: child.taggedProfiles }
        : {}),
    };
  }
}

function instagramTaggedProfiles(
  record: Record<string, unknown>,
): InstagramTaggedProfile[] {
  const profiles = new Map<string, InstagramTaggedProfile>();
  const conflictingNames = new Set<string>();
  for (
    const value of arrayValue(record.taggedUsers ?? record.tagged_users).slice(
      0,
      maximumInstagramProfileAliases,
    )
  ) {
    const profile = asRecord(value);
    const user = asRecord(profile?.user);
    const username = normalizedInstagramUsername(
      (typeof value === "string" ? value : null) ?? profile?.username ??
        profile?.userName ?? profile?.user_name ??
        user?.username ?? user?.userName ?? user?.user_name,
    );
    if (!username) continue;
    const fullName = cleanString(
      profile?.fullName ?? profile?.full_name ?? user?.fullName ??
        user?.full_name,
      160,
    );
    const existing = profiles.get(username);
    if (!existing) {
      profiles.set(username, { username, fullName });
      continue;
    }
    if (!existing.fullName && fullName && !conflictingNames.has(username)) {
      profiles.set(username, { username, fullName });
      continue;
    }
    if (
      existing.fullName && fullName &&
      normalizedProfileName(existing.fullName) !==
        normalizedProfileName(fullName)
    ) {
      conflictingNames.add(username);
      profiles.set(username, { username, fullName: null });
    }
  }
  return [...profiles.values()];
}

function normalizedProfileName(value: string): string {
  return value.normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase("en-US")
    .match(/[\p{L}\p{N}]+/gu)?.join("") ?? "";
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
