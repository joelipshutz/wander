import { performance } from "node:perf_hooks";
import { cosineSimilarity } from "./core.mjs";

export const featuredPipelineNames = [
  "current",
  "networkOnly",
  "fixedBlend",
  "densityAware",
  "densitySemantic",
];

const clamp = (value, minimum = 0, maximum = 1) =>
  Math.min(maximum, Math.max(minimum, value));

const normalized = (value) => String(value ?? "").trim().toLocaleLowerCase();

const unique = (values) => [...new Set(values)];

function normalizedRating(value) {
  return value == null ? 0.4 : clamp((Number(value) - 1) / 4);
}

function recencyScore(days) {
  return Math.exp(-Math.max(0, Number(days) || 0) / 365);
}

function communitySupportScore(count) {
  return clamp(Math.log1p(Math.max(0, Number(count) || 0)) / Math.log1p(20));
}

export function buildFeaturedTasteProfile(tastePlaces) {
  const categoryCounts = new Map();
  const tagCounts = new Map();

  for (const place of tastePlaces) {
    const category = normalized(place.category);
    if (category) categoryCounts.set(category, (categoryCounts.get(category) ?? 0) + 1);
    for (const tag of unique(place.tags.map(normalized).filter(Boolean))) {
      tagCounts.set(tag, (tagCounts.get(tag) ?? 0) + 1);
    }
  }

  return {
    likedPlaceCount: tastePlaces.length,
    categoryCounts,
    tagCounts,
  };
}

export function averageEmbedding(vectors) {
  const usable = vectors.filter((vector) => Array.isArray(vector) && vector.length > 0);
  if (usable.length === 0) return null;
  const length = usable[0].length;
  if (usable.some((vector) => vector.length !== length)) {
    throw new Error("Featured taste embeddings must have one dimension.");
  }
  const result = Array.from({ length }, () => 0);
  for (const vector of usable) {
    vector.forEach((value, index) => { result[index] += Number(value); });
  }
  return result.map((value) => value / usable.length);
}

export function attachSemanticTasteScores(candidates, placeEmbeddings, tasteEmbedding) {
  return candidates.map((candidate) => ({
    ...candidate,
    semanticTasteScore: tasteEmbedding
      ? clamp((cosineSimilarity(placeEmbeddings.get(candidate.id), tasteEmbedding) + 1) / 2)
      : 0,
  }));
}

function isTrusted(candidate, scenario) {
  return scenario.networkMode !== "empty"
    && (candidate.includesSelf || candidate.trustedContributorIds.length > 0);
}

function relationshipScore(candidate, scenario) {
  if (scenario.networkMode === "empty") return 0;
  if (candidate.includesSelf) return 1;
  return candidate.trustedContributorIds.length > 0 ? 0.75 : 0;
}

function tasteScore(candidate, tasteProfile, scenario) {
  if (scenario.tasteMode === "none" || tasteProfile.likedPlaceCount === 0) return 0;
  const categoryCount = tasteProfile.categoryCounts.get(normalized(candidate.category)) ?? 0;
  const categoryFit = categoryCount === 0
    ? 0
    : clamp(0.35 + categoryCount / tasteProfile.likedPlaceCount);
  const matchingTags = unique(candidate.tags.map(normalized)).filter(
    (tag) => (tasteProfile.tagCounts.get(tag) ?? 0) > 0,
  ).length;
  return clamp(0.72 * categoryFit + Math.min(0.28, matchingTags * 0.14));
}

function currentTasteScore(candidate, tasteProfile, scenario) {
  if (scenario.tasteMode === "none" || tasteProfile.likedPlaceCount === 0) return 0;
  const categoryCount = tasteProfile.categoryCounts.get(normalized(candidate.category)) ?? 0;
  const categoryAffinity = categoryCount === 0
    ? 0
    : 1.1 * Math.min(1, 0.35 + categoryCount / tasteProfile.likedPlaceCount);
  const matchingTags = unique(candidate.tags.map(normalized)).filter(
    (tag) => (tasteProfile.tagCounts.get(tag) ?? 0) > 0,
  ).length;
  return categoryAffinity + Math.min(0.75, matchingTags * 0.25);
}

function communityScore(candidate) {
  return 0.55 * communitySupportScore(candidate.communitySupport)
    + 0.35 * normalizedRating(candidate.communityRating)
    + 0.1 * recencyScore(candidate.freshnessDays);
}

function currentScore(candidate, tasteProfile, scenario) {
  const relationshipBoost = scenario.networkMode === "empty"
    ? 0
    : candidate.includesSelf
      ? 1.8
      : candidate.trustedContributorIds.length > 0
        ? 1.35
        : 0;
  const support = Math.min(2.4, Math.log2(candidate.communitySupport + 1) * 0.95);
  const rating = candidate.communityRating == null
    ? 0
    : Math.min(1.25, Math.max(0, candidate.communityRating / 5) * 1.25);
  return relationshipBoost + currentTasteScore(candidate, tasteProfile, scenario) + support + rating;
}

export function featuredNetworkConfidence(candidates, scenario) {
  if (scenario.networkMode === "empty" || candidates.length === 0) return 0;
  const trusted = candidates.filter((candidate) => isTrusted(candidate, scenario));
  const contributors = unique(trusted.flatMap((candidate) => candidate.trustedContributorIds));
  const contributorCounts = new Map();
  for (const candidate of trusted) {
    for (const contributor of candidate.trustedContributorIds) {
      contributorCounts.set(contributor, (contributorCounts.get(contributor) ?? 0) + 1);
    }
  }
  const maximumContributorShare = trusted.length === 0
    ? 1
    : Math.max(0, ...contributorCounts.values()) / trusted.length;
  const concentrationDiversity = contributors.length <= 1 ? 0 : 1 - maximumContributorShare;

  return clamp(
    0.4 * clamp(trusted.length / 8)
    + 0.25 * clamp(contributors.length / 3)
    + 0.2 * clamp(trusted.length / candidates.length)
    + 0.15 * clamp(concentrationDiversity),
  );
}

function stableRanksBefore(left, right) {
  return right.score - left.score
    || Number(left.candidate.freshnessDays) - Number(right.candidate.freshnessDays)
    || left.candidate.id.localeCompare(right.candidate.id);
}

function applyDiversity(ranked, limit) {
  const selected = [];
  const deferred = [];
  const categoryCounts = new Map();
  const contributorCounts = new Map();
  const categoryCap = Math.max(2, Math.ceil(limit * 0.42));
  const contributorCap = Math.max(2, Math.ceil(limit * 0.34));

  for (const row of ranked) {
    const category = normalized(row.candidate.category) || "place";
    const primaryContributor = row.primaryContributor;
    const exceedsCategory = (categoryCounts.get(category) ?? 0) >= categoryCap;
    const exceedsContributor = primaryContributor
      ? (contributorCounts.get(primaryContributor) ?? 0) >= contributorCap
      : false;
    if (exceedsCategory || exceedsContributor) {
      deferred.push(row);
      continue;
    }
    selected.push(row);
    categoryCounts.set(category, (categoryCounts.get(category) ?? 0) + 1);
    if (primaryContributor) {
      contributorCounts.set(
        primaryContributor,
        (contributorCounts.get(primaryContributor) ?? 0) + 1,
      );
    }
    if (selected.length === limit) break;
  }
  if (selected.length < limit) {
    selected.push(...deferred.slice(0, limit - selected.length));
  }
  return selected;
}

function rankedRows(candidates, score, limit, diversify, scenario) {
  const ranked = candidates
    .map((candidate) => ({
      candidate,
      score: score(candidate),
      primaryContributor: scenario.networkMode === "empty"
        ? null
        : candidate.primaryTrustedContributorId,
    }))
    .sort(stableRanksBefore);
  const limited = diversify ? applyDiversity(ranked, limit) : ranked.slice(0, limit);
  return limited.map(({ candidate, score: value }) => ({
    id: candidate.id,
    score: value,
    source: isTrusted(candidate, scenario)
      ? "network"
      : "community",
    contributorIds: scenario.networkMode === "empty" ? [] : candidate.trustedContributorIds,
    latitude: candidate.latitude,
    longitude: candidate.longitude,
  }));
}

export function rankFeaturedScenario({ candidates, scenario, tasteProfile, limit = 24 }) {
  const confidence = featuredNetworkConfidence(candidates, scenario);
  const startedAt = performance.now();
  const personalScore = (candidate) => (
    0.55 * relationshipScore(candidate, scenario)
    + 0.45 * tasteScore(candidate, tasteProfile, scenario)
  );
  const fixedScore = (candidate) => (
    0.4 * personalScore(candidate)
    + 0.5 * communityScore(candidate)
    + 0.1 * recencyScore(candidate.freshnessDays)
  );
  const densityScore = (candidate) => {
    const relationshipWeight = 0.4 * confidence;
    const tasteWeight = 0.3;
    const communityWeight = 0.6 - 0.3 * confidence;
    const recencyWeight = 0.1 - 0.1 * confidence;
    return relationshipWeight * relationshipScore(candidate, scenario)
      + tasteWeight * tasteScore(candidate, tasteProfile, scenario)
      + communityWeight * communityScore(candidate)
      + recencyWeight * recencyScore(candidate.freshnessDays);
  };

  const pipelines = {
    current: rankedRows(
      candidates,
      (candidate) => currentScore(candidate, tasteProfile, scenario),
      limit,
      false,
      scenario,
    ),
    networkOnly: rankedRows(
      candidates.filter((candidate) => isTrusted(candidate, scenario)),
      (candidate) => currentScore(candidate, tasteProfile, scenario),
      limit,
      false,
      scenario,
    ),
    fixedBlend: rankedRows(candidates, fixedScore, limit, true, scenario),
    densityAware: rankedRows(candidates, densityScore, limit, true, scenario),
    densitySemantic: rankedRows(
      candidates,
      (candidate) => 0.8 * densityScore(candidate)
        + 0.2 * (scenario.tasteMode === "none" ? 0 : candidate.semanticTasteScore),
      limit,
      true,
      scenario,
    ),
  };

  return {
    confidence,
    latencyMs: performance.now() - startedAt,
    pipelines,
  };
}

function viewportForPlaces(places, minimumSpan = 0.08) {
  const latitudes = places.map((place) => place.latitude);
  const longitudes = places.map((place) => place.longitude);
  const minLatitude = Math.min(...latitudes);
  const maxLatitude = Math.max(...latitudes);
  const minLongitude = Math.min(...longitudes);
  const maxLongitude = Math.max(...longitudes);
  const centerLatitude = (minLatitude + maxLatitude) / 2;
  const centerLongitude = (minLongitude + maxLongitude) / 2;
  const latitudeSpan = clamp((maxLatitude - minLatitude) * 1.2 + 0.02, minimumSpan, 0.4);
  const longitudeSpan = clamp((maxLongitude - minLongitude) * 1.2 + 0.02, minimumSpan, 0.5);
  return {
    minLatitude: centerLatitude - latitudeSpan / 2,
    maxLatitude: centerLatitude + latitudeSpan / 2,
    minLongitude: centerLongitude - longitudeSpan / 2,
    maxLongitude: centerLongitude + longitudeSpan / 2,
  };
}

export function candidatesInViewport(candidates, viewport) {
  return candidates.filter((candidate) => (
    candidate.latitude >= viewport.minLatitude
    && candidate.latitude <= viewport.maxLatitude
    && candidate.longitude >= viewport.minLongitude
    && candidate.longitude <= viewport.maxLongitude
  ));
}

function areaLabel(candidate) {
  return [candidate.locality, candidate.region].filter(Boolean).join(", ") || "Mapped area";
}

function areaRows(candidates) {
  const grouped = new Map();
  for (const candidate of candidates) {
    const label = areaLabel(candidate);
    if (!grouped.has(label)) grouped.set(label, []);
    grouped.get(label).push(candidate);
  }
  return [...grouped.entries()].map(([label, places]) => {
    const trusted = places.filter((candidate) => (
      candidate.includesSelf || candidate.trustedContributorIds.length > 0
    ));
    return {
      label,
      places,
      viewport: viewportForPlaces(places),
      trustedPlaceCount: trusted.length,
      trustedContributorCount: unique(trusted.flatMap((place) => place.trustedContributorIds)).length,
    };
  });
}

function shiftedViewport(viewport, longitudeFraction) {
  const width = viewport.maxLongitude - viewport.minLongitude;
  return {
    ...viewport,
    minLongitude: viewport.minLongitude + width * longitudeFraction,
    maxLongitude: viewport.maxLongitude + width * longitudeFraction,
  };
}

export function generateFeaturedScenarios(candidates) {
  const areas = areaRows(candidates).filter((area) => area.places.length >= 3);
  if (areas.length < 2) throw new Error("Featured benchmark needs at least two real mapped areas.");

  const dense = [...areas]
    .filter((area) => area.trustedPlaceCount >= 6 && area.trustedContributorCount >= 2)
    .sort((left, right) => right.trustedPlaceCount - left.trustedPlaceCount)
    .slice(0, 2);
  const denseFallback = [...areas]
    .sort((left, right) => right.trustedPlaceCount - left.trustedPlaceCount)
    .filter((area) => !dense.includes(area));
  while (dense.length < 2 && denseFallback.length > 0) dense.push(denseFallback.shift());

  const sparse = [...areas]
    .filter((area) => area.trustedPlaceCount >= 1 && area.trustedPlaceCount <= 5)
    .sort((left, right) => right.places.length - left.places.length)
    .slice(0, 2);
  const sparseFallback = [...areas]
    .filter((area) => !dense.includes(area) && !sparse.includes(area))
    .sort((left, right) => left.trustedPlaceCount - right.trustedPlaceCount);
  while (sparse.length < 2 && sparseFallback.length > 0) sparse.push(sparseFallback.shift());

  const scenarios = [
    ...dense.map((area) => ({
      title: area.label,
      slice: "dense",
      networkMode: "actual",
      tasteMode: "actual",
      viewport: area.viewport,
    })),
    ...sparse.map((area) => ({
      title: area.label,
      slice: "sparse",
      networkMode: "actual",
      tasteMode: "actual",
      viewport: area.viewport,
    })),
    ...dense.slice(0, 2).map((area) => ({
      title: area.label,
      slice: "empty",
      networkMode: "empty",
      tasteMode: "actual",
      viewport: area.viewport,
    })),
  ];

  const panBase = dense[0];
  if (panBase) {
    const baseViewport = panBase.viewport;
    scenarios.push(
      {
        title: panBase.label,
        slice: "pan",
        networkMode: "actual",
        tasteMode: "actual",
        viewport: shiftedViewport(baseViewport, -0.12),
        panGroup: "pan-1",
      },
      {
        title: panBase.label,
        slice: "pan",
        networkMode: "actual",
        tasteMode: "actual",
        viewport: shiftedViewport(baseViewport, 0.12),
        panGroup: "pan-1",
      },
    );
  }

  const coldStartArea = dense[1] ?? dense[0];
  if (coldStartArea) {
    scenarios.push({
      title: coldStartArea.label,
      slice: "cold-start",
      networkMode: "empty",
      tasteMode: "none",
      viewport: coldStartArea.viewport,
    });
  }

  return scenarios
    .map((scenario) => ({
      ...scenario,
      candidateCount: candidatesInViewport(candidates, scenario.viewport).length,
    }))
    .filter((scenario) => scenario.candidateCount >= 3)
    .map((scenario, index) => ({ ...scenario, id: `featured-q${String(index + 1).padStart(2, "0")}` }));
}

export function overlapAt(left, right, at = 10) {
  const leftIds = new Set(left.slice(0, at).map((row) => row.id));
  const rightIds = new Set(right.slice(0, at).map((row) => row.id));
  const union = new Set([...leftIds, ...rightIds]);
  if (union.size === 0) return 1;
  return [...leftIds].filter((id) => rightIds.has(id)).length / union.size;
}
