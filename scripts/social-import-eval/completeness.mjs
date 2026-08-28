import { normalizeEvidence } from "./lib.mjs";
import { probeAcquiredMediaAsset } from "./media.mjs";

function hasText(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function hasURL(media, key) {
  return hasText(media?.[key]);
}

/**
 * Measures whether acquisition preserved the source modalities the labeled
 * case says are needed. This is deliberately separate from place accuracy: a
 * caption-only fallback must not look like complete reel/carousel acquisition.
 */
export function assessAcquisitionCompleteness(testCase, acquisition) {
  const evidence = normalizeEvidence(acquisition?.evidence);
  const expected = Array.isArray(testCase?.modalitiesExpected)
    ? [...new Set(testCase.modalitiesExpected)]
    : [];
  const videoAssets = evidence.media.filter((media) =>
    media?.type === "video" && (hasURL(media, "persistentURL") || hasURL(media, "url"))
  );
  const stillTextAssets = evidence.media.filter((media) =>
    (media?.type === "image" && (hasURL(media, "persistentURL") || hasURL(media, "url")))
      || (media?.type === "video" && hasURL(media, "thumbnailURL"))
  );
  const available = new Set();
  if (hasText(evidence.caption)) available.add("caption");
  if (evidence.taggedLocations.some((location) => hasText(location?.name))) {
    available.add("tagged_location");
  }
  if (stillTextAssets.length > 0) available.add("carousel_image_text");
  if (videoAssets.length > 0) {
    available.add("video_text");
    // A source video is sufficient acquisition for downstream speech-to-text;
    // a transcript is not required from the scraper itself.
    available.add("speech");
  }
  if (hasText(evidence.transcript?.text)) available.add("speech");

  const missing = expected.filter((modality) => !available.has(modality));
  const expectsImages = expected.includes("carousel_image_text");
  const expectsVideo = expected.some((item) => ["video_text", "speech"].includes(item));
  const genericMinimum = Number.isInteger(testCase?.minimumMediaAssets)
    ? Math.max(0, testCase.minimumMediaAssets)
    : 1;
  const requiredMediaByKind = {
    image: expectsImages
      ? Math.max(0, testCase?.minimumImageAssets ?? (expectsVideo ? 1 : genericMinimum))
      : 0,
    video: expectsVideo
      ? Math.max(0, testCase?.minimumVideoAssets ?? (expectsImages ? 1 : genericMinimum))
      : 0,
  };
  const declaredMediaByKind = {
    image: stillTextAssets.length,
    video: videoAssets.length,
  };
  const minimumMediaAssets = requiredMediaByKind.image + requiredMediaByKind.video;
  const acquiredRelevantMediaAssets = declaredMediaByKind.image + declaredMediaByKind.video;
  const missingMediaAssetCount = Math.max(0, requiredMediaByKind.image - declaredMediaByKind.image)
    + Math.max(0, requiredMediaByKind.video - declaredMediaByKind.video);
  const declaredComplete = missing.length === 0 && missingMediaAssetCount === 0;
  const modalityCoverage = {
    expected,
    available: [...available],
    missing,
    requiredMediaByKind,
    declaredMediaByKind,
    minimumMediaAssets,
    acquiredRelevantMediaAssets,
    missingMediaAssetCount,
    declaredComplete,
    // Media-bearing cases require an actual bounded fetch/MIME probe before
    // strict completeness can be known.
    complete: minimumMediaAssets === 0 ? declaredComplete : (declaredComplete ? null : false),
  };

  // Preserve transport/provider status so partial evidence still flows through
  // understanding and can be scored. Strict completeness is a separate gate.
  return { ...acquisition, modalityCoverage };
}

function probeDescriptors(testCase, evidence) {
  const expected = new Set(testCase?.modalitiesExpected ?? []);
  const descriptors = [];
  if (expected.has("carousel_image_text")) {
    descriptors.push(...evidence.media.flatMap((media, mediaIndex) => {
      const url = media?.type === "video" ? media.thumbnailURL : (media?.persistentURL ?? media?.url);
      if (!hasText(url)) return [];
      return [{
        mediaIndex,
        expectedKind: "image",
        descriptor: { url, privateRequestHeaders: media.privateRequestHeaders },
      }];
    }));
  }
  if (expected.has("video_text") || expected.has("speech")) {
    descriptors.push(...evidence.media.flatMap((media, mediaIndex) => {
      if (media?.type !== "video" || (!hasURL(media, "persistentURL") && !hasURL(media, "url"))) {
        return [];
      }
      return [{ mediaIndex, expectedKind: "video", descriptor: media }];
    }));
  }
  return descriptors;
}

export async function validateAcquisitionCompleteness(testCase, acquisition) {
  const started = performance.now();
  const assessed = assessAcquisitionCompleteness(testCase, acquisition);
  const coverage = assessed.modalityCoverage;
  if (coverage.minimumMediaAssets === 0 || acquisition?.status !== "ok") {
    const probeLatencyMs = Math.round(performance.now() - started);
    return {
      ...assessed,
      providerLatencyMs: acquisition?.providerLatencyMs ?? acquisition?.latencyMs ?? 0,
      latencyMs: (acquisition?.latencyMs ?? 0) + probeLatencyMs,
      modalityCoverage: {
        ...coverage,
        complete: acquisition?.status === "ok" && coverage.declaredComplete,
        assetChecks: [],
        fetchableRelevantMediaAssets: 0,
        probeLatencyMs,
      },
    };
  }
  const evidence = normalizeEvidence(acquisition.evidence);
  const descriptors = probeDescriptors(testCase, evidence);
  const checks = await Promise.all(descriptors.map(async (item) => {
    const result = await probeAcquiredMediaAsset(item.descriptor, {
      expectedKind: item.expectedKind,
      socialPageURL: testCase.url,
    });
    return {
      mediaIndex: item.mediaIndex,
      type: item.expectedKind,
      status: result.error ? "failed" : "ok",
      error: result.error ?? null,
      byteCount: result.byteCount ?? null,
      mimeType: result.mimeType ?? null,
      finalHost: result.finalHost ?? null,
      statusCode: result.statusCode ?? null,
    };
  }));
  const fetchable = checks.filter((item) => item.status === "ok").length;
  const fetchableMediaByKind = {
    image: checks.filter((item) => item.type === "image" && item.status === "ok").length,
    video: checks.filter((item) => item.type === "video" && item.status === "ok").length,
  };
  const enoughFetchableMedia = Object.entries(coverage.requiredMediaByKind).every(
    ([kind, count]) => fetchableMediaByKind[kind] >= count,
  );
  const probeLatencyMs = Math.round(performance.now() - started);
  return {
    ...assessed,
    providerLatencyMs: acquisition?.providerLatencyMs ?? acquisition?.latencyMs ?? 0,
    latencyMs: (acquisition?.latencyMs ?? 0) + probeLatencyMs,
    modalityCoverage: {
      ...coverage,
      assetChecks: checks,
      fetchableRelevantMediaAssets: fetchable,
      fetchableMediaByKind,
      complete: coverage.declaredComplete && enoughFetchableMedia,
      probeLatencyMs,
    },
  };
}
