import { acquireWithApify } from "./apify.ts";
import { acquireWithBrightData } from "./brightdata.ts";
import type {
  AcquiredMedia,
  AcquisitionEvidence,
  InstagramTaggedProfile,
  RuntimeDependencies,
  SocialSource,
  TaggedLocation,
} from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

export type AcquisitionProvider = "apify" | "brightdata" | "brightdata_apify";

export type RoutedAcquisition = {
  evidence: AcquisitionEvidence;
  provider: AcquisitionProvider;
};

export type SocialAcquisitionConfiguration = {
  apifyToken: string | null;
  brightDataToken: string | null;
  instagramMode: "apify" | "brightdata_hybrid";
};

export async function acquireSocialEvidence(
  source: SocialSource,
  configuration: SocialAcquisitionConfiguration,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
  cancellationSignal?: AbortSignal,
): Promise<RoutedAcquisition> {
  if (
    source.platform === "tiktok" || configuration.instagramMode === "apify"
  ) {
    if (!configuration.apifyToken) {
      throw new SocialImportError("acquisition_configuration_unavailable");
    }
    return {
      evidence: await acquireWithApify(
        source,
        configuration.apifyToken,
        deadline,
        dependencies,
        cancellationSignal,
      ),
      provider: "apify",
    };
  }

  if (source.contentType === "reel") {
    if (configuration.brightDataToken) {
      try {
        return {
          evidence: await acquireWithBrightData(
            source,
            configuration.brightDataToken,
            deadline,
            dependencies,
            cancellationSignal,
          ),
          provider: "brightdata",
        };
      } catch (error) {
        if (!configuration.apifyToken || isCancellation(error)) throw error;
      }
    }
    if (!configuration.apifyToken) {
      throw new SocialImportError("acquisition_configuration_unavailable");
    }
    return {
      evidence: await acquireWithApify(
        source,
        configuration.apifyToken,
        deadline,
        dependencies,
        cancellationSignal,
      ),
      provider: "apify",
    };
  }

  const brightDataPromise = configuration.brightDataToken
    ? acquireWithBrightData(
      source,
      configuration.brightDataToken,
      deadline,
      dependencies,
      cancellationSignal,
    )
    : null;
  const apifyPromise = configuration.apifyToken
    ? acquireWithApify(
      source,
      configuration.apifyToken,
      deadline,
      dependencies,
      cancellationSignal,
    )
    : null;
  if (!brightDataPromise && !apifyPromise) {
    throw new SocialImportError("acquisition_configuration_unavailable");
  }
  const [brightDataResult, apifyResult] = await Promise.allSettled([
    brightDataPromise ?? Promise.reject(
      new SocialImportError("acquisition_provider_not_configured"),
    ),
    apifyPromise ?? Promise.reject(
      new SocialImportError("acquisition_provider_not_configured"),
    ),
  ]);
  if (
    brightDataResult.status === "rejected" &&
    isCancellation(brightDataResult.reason)
  ) throw brightDataResult.reason;
  if (apifyResult.status === "rejected" && isCancellation(apifyResult.reason)) {
    throw apifyResult.reason;
  }
  if (
    brightDataResult.status === "fulfilled" &&
    apifyResult.status === "fulfilled"
  ) {
    return {
      evidence: mergeInstagramEvidence(
        brightDataResult.value,
        apifyResult.value,
      ),
      provider: "brightdata_apify",
    };
  }
  if (brightDataResult.status === "fulfilled") {
    return { evidence: brightDataResult.value, provider: "brightdata" };
  }
  if (apifyResult.status === "fulfilled") {
    return { evidence: apifyResult.value, provider: "apify" };
  }
  throw brightDataPromise ? brightDataResult.reason : apifyResult.reason;
}

export function mergeInstagramEvidence(
  brightData: AcquisitionEvidence,
  apify: AcquisitionEvidence,
): AcquisitionEvidence {
  const brightByIndex = indexedMedia(brightData.media);
  const apifyByIndex = indexedMedia(apify.media);
  const indexes = [
    ...new Set([...brightByIndex.keys(), ...apifyByIndex.keys()]),
  ]
    .sort((left, right) => left - right)
    .slice(0, 150);
  const media = indexes.map((index, outputIndex) => {
    const bright = brightByIndex.get(index);
    const highResolution = apifyByIndex.get(index);
    const preferred = preferredMedia(bright, highResolution);
    const fallback = preferred === bright ? highResolution : bright;
    return {
      ...preferred,
      id: `media:${outputIndex}`,
      index: outputIndex,
      altText: bright?.altText ?? highResolution?.altText ?? null,
      taggedProfiles: mergeTaggedProfiles(
        bright?.taggedProfiles ?? [],
        highResolution?.taggedProfiles ?? [],
      ),
      thumbnailURL: preferred.thumbnailURL ?? fallback?.thumbnailURL ?? null,
    };
  });
  return {
    title: brightData.title ?? apify.title,
    caption: brightData.caption ?? apify.caption,
    taggedLocations: mergeTaggedLocations(
      brightData.taggedLocations,
      apify.taggedLocations,
    ),
    media,
  };
}

function preferredMedia(
  bright: AcquiredMedia | undefined,
  apify: AcquiredMedia | undefined,
): AcquiredMedia {
  if (!bright) return requiredMedia(apify);
  if (!apify) return bright;
  // Apify consistently returned the higher-resolution source for image slides
  // in REC-411. Bright Data remained the preferred transport for video, where
  // all shared reel byte streams were identical.
  return bright.kind === "video"
    ? bright
    : apify.kind === "image"
    ? apify
    : bright;
}

function requiredMedia(value: AcquiredMedia | undefined): AcquiredMedia {
  if (!value) throw new SocialImportError("vendor_missing_media_assets");
  return value;
}

function indexedMedia(media: AcquiredMedia[]): Map<number, AcquiredMedia> {
  const result = new Map<number, AcquiredMedia>();
  for (const item of media) {
    if (!result.has(item.index)) result.set(item.index, item);
  }
  return result;
}

function mergeTaggedProfiles(
  primary: InstagramTaggedProfile[],
  secondary: InstagramTaggedProfile[],
): InstagramTaggedProfile[] | undefined {
  const profiles = new Map<string, InstagramTaggedProfile>();
  for (const profile of [...primary, ...secondary]) {
    const existing = profiles.get(profile.username);
    if (!existing || (!existing.fullName && profile.fullName)) {
      profiles.set(profile.username, profile);
    }
  }
  return profiles.size > 0 ? [...profiles.values()].slice(0, 20) : undefined;
}

function mergeTaggedLocations(
  primary: TaggedLocation[],
  secondary: TaggedLocation[],
): TaggedLocation[] {
  const locations = new Map<string, TaggedLocation>();
  for (const location of [...primary, ...secondary]) {
    const key = `${location.name}\u0000${location.area ?? ""}`
      .toLocaleLowerCase(
        "en-US",
      );
    if (!locations.has(key)) locations.set(key, location);
  }
  return [...locations.values()].slice(0, 20);
}

function isCancellation(error: unknown): boolean {
  return error instanceof SocialImportError &&
    ["request_cancelled", "apify_run_cancelled"].includes(error.code);
}
