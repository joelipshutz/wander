import { normalizeApifyDataset } from "./apify.ts";
import { fetchJSON } from "./http.ts";
import { cleanString } from "./source.ts";
import type {
  AcquisitionEvidence,
  RuntimeDependencies,
  SocialSource,
} from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

export const defaultBrightDataInstagramPostsDatasetID = "gd_lk5ns7kz21pck8jpis";
export const defaultBrightDataInstagramReelsDatasetID = "gd_lyclm20il4r5helnj";

const maximumSnapshotPollAttempts = 30;
const maximumResponseBytes = 10_000_000;

export async function acquireWithBrightData(
  source: SocialSource,
  token: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
  cancellationSignal?: AbortSignal,
): Promise<AcquisitionEvidence> {
  if (source.platform !== "instagram") {
    throw new SocialImportError("brightdata_platform_unsupported");
  }
  assertNotCancelled(cancellationSignal);
  const datasetID = brightDataDatasetID(source, dependencies);
  const scrapeURL = new URL(
    "https://api.brightdata.com/datasets/v3/scrape",
  );
  scrapeURL.searchParams.set("dataset_id", datasetID);
  scrapeURL.searchParams.set("include_errors", "true");

  // Do not apply caller cancellation to the trigger request. If Bright Data
  // accepts paid work, this response is the only way to learn the snapshot ID
  // needed for bounded polling. The shared deadline still caps the request.
  const started = await fetchJSON(
    scrapeURL.toString(),
    {
      method: "POST",
      headers: providerHeaders(token),
      body: JSON.stringify({ input: [{ url: source.url }] }),
    },
    maximumResponseBytes,
    25_000,
    deadline,
    dependencies,
  );
  if (!started.response.ok && started.response.status !== 202) {
    throw new SocialImportError("brightdata_scrape_http_error");
  }

  const snapshotID = brightDataSnapshotID(started.body);
  if (snapshotID) {
    return normalizeApifyDataset(
      await pollBrightDataSnapshot(
        snapshotID,
        token,
        deadline,
        dependencies,
        cancellationSignal,
      ),
      source,
    );
  }
  if (started.response.status === 202) {
    throw new SocialImportError("brightdata_snapshot_invalid");
  }
  return normalizeApifyDataset(started.body, source);
}

export function brightDataDatasetID(
  source: SocialSource,
  dependencies: RuntimeDependencies,
): string {
  const configured = cleanString(
    dependencies.env(
      source.contentType === "reel"
        ? "WANDER_BRIGHTDATA_INSTAGRAM_REELS_DATASET_ID"
        : "WANDER_BRIGHTDATA_INSTAGRAM_POSTS_DATASET_ID",
    ),
    120,
  );
  if (configured && !/^gd_[A-Za-z0-9_-]{5,100}$/.test(configured)) {
    throw new SocialImportError("brightdata_dataset_invalid");
  }
  return configured ??
    (source.contentType === "reel"
      ? defaultBrightDataInstagramReelsDatasetID
      : defaultBrightDataInstagramPostsDatasetID);
}

async function pollBrightDataSnapshot(
  snapshotID: string,
  token: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
  cancellationSignal?: AbortSignal,
): Promise<unknown> {
  const url = new URL(
    `https://api.brightdata.com/datasets/v3/snapshot/${
      encodeURIComponent(snapshotID)
    }`,
  );
  url.searchParams.set("format", "json");
  for (let attempt = 0; attempt < maximumSnapshotPollAttempts; attempt += 1) {
    assertNotCancelled(cancellationSignal);
    const result = await fetchJSON(
      url.toString(),
      { headers: providerHeaders(token), signal: cancellationSignal },
      maximumResponseBytes,
      25_000,
      deadline,
      dependencies,
    );
    if (result.response.status === 202) {
      const delay = Math.min(
        10_000,
        1_000 + attempt * 500,
        deadline.remaining(10_000),
      );
      await cancellableSleep(delay, dependencies, cancellationSignal);
      continue;
    }
    if (!result.response.ok) {
      throw new SocialImportError("brightdata_snapshot_http_error");
    }
    return result.body;
  }
  throw new SocialImportError("brightdata_snapshot_timeout");
}

function brightDataSnapshotID(value: unknown): string | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  const identifier = cleanString(record.snapshot_id ?? record.snapshotId, 160);
  return identifier && /^[A-Za-z0-9_-]+$/.test(identifier) ? identifier : null;
}

function providerHeaders(token: string): Record<string, string> {
  return {
    authorization: `Bearer ${token}`,
    accept: "application/json",
    "content-type": "application/json",
  };
}

function assertNotCancelled(signal?: AbortSignal): void {
  if (signal?.aborted) throw new SocialImportError("request_cancelled");
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
    onAbort = () => reject(new SocialImportError("request_cancelled"));
    signal.addEventListener("abort", onAbort, { once: true });
  });
  try {
    await Promise.race([dependencies.sleep(milliseconds), cancellation]);
  } finally {
    if (onAbort) signal.removeEventListener("abort", onAbort);
  }
  assertNotCancelled(signal);
}
