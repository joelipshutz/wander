import { fetchJSON } from "./http.ts";
import { asRecord, cleanString } from "./source.ts";
import type { PlaceHint, ResolvedPlace, RuntimeDependencies } from "./types.ts";
import { Deadline } from "./types.ts";

const googlePlacesSearchURL =
  "https://places.googleapis.com/v1/places:searchText";
const maximumLookups = 30;
const maximumCandidatesPerHint = 3;
// Run the bounded set as one wave so candidate enrichment still completes
// when acquisition and multimodal understanding consume most of the shared
// Edge Function deadline.
const lookupConcurrency = maximumLookups;
const lookupTimeoutMilliseconds = 7_000;
const maximumResponseBytes = 192_000;
const fieldMask = [
  "places.id",
  "places.displayName",
  "places.formattedAddress",
  "places.addressComponents",
  "places.location",
  "places.primaryType",
  "places.types",
].join(",");

type ParsedGooglePlace = {
  resolved: ResolvedPlace;
  normalizedName: string;
  normalizedAddress: string;
  primaryType: string;
};

/**
 * Adds bounded Google Places candidates to grounded model hints. A provider
 * outage never discards the evidence: the iOS client can still fall back to
 * MapKit for hints without candidates.
 */
export async function resolvePlaceHintsWithGoogle(
  hints: PlaceHint[],
  apiKey: string | null,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
  signal: AbortSignal,
): Promise<PlaceHint[]> {
  if (!apiKey || hints.length === 0) return hints;

  const output = [...hints];
  const lookupCount = Math.min(hints.length, maximumLookups);
  let nextIndex = 0;
  const worker = async () => {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= lookupCount) return;
      try {
        const resolvedPlaces = await resolveHint(
          hints[index],
          apiKey,
          deadline,
          dependencies,
          signal,
        );
        if (resolvedPlaces.length > 0) {
          output[index] = {
            ...hints[index],
            resolved_places: resolvedPlaces,
          };
        }
      } catch {
        // Grounded extraction remains useful when Places is unavailable. Do
        // not log queries, provider payloads, or any user-supplied evidence.
      }
    }
  };

  await Promise.all(
    Array.from(
      { length: Math.min(lookupConcurrency, lookupCount) },
      worker,
    ),
  );
  return output;
}

async function resolveHint(
  hint: PlaceHint,
  apiKey: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
  signal: AbortSignal,
): Promise<ResolvedPlace[]> {
  const textQuery = [hint.name, hint.area].filter(Boolean).join(", ");
  const result = await fetchJSON(
    googlePlacesSearchURL,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": fieldMask,
      },
      body: JSON.stringify({ textQuery, pageSize: 5, languageCode: "en" }),
      signal,
    },
    maximumResponseBytes,
    lookupTimeoutMilliseconds,
    deadline,
    dependencies,
  );
  if (!result.response.ok) return [];
  const body = asRecord(result.body);
  const places = Array.isArray(body?.places) ? body.places : [];
  return places
    .map(parseGooglePlace)
    .filter((place): place is ParsedGooglePlace => place !== null)
    .map((place, index) => ({
      place,
      index,
      score: candidateScore(place, hint),
    }))
    .filter((candidate) => candidate.score >= 0)
    .sort((lhs, rhs) =>
      lhs.score === rhs.score ? lhs.index - rhs.index : rhs.score - lhs.score
    )
    .slice(0, maximumCandidatesPerHint)
    .map((candidate) => candidate.place.resolved);
}

function parseGooglePlace(value: unknown): ParsedGooglePlace | null {
  const place = asRecord(value);
  const displayName = asRecord(place?.displayName);
  const location = asRecord(place?.location);
  const id = cleanString(place?.id, 300);
  const name = cleanString(displayName?.text, 200);
  const latitude = finiteCoordinate(location?.latitude, -90, 90);
  const longitude = finiteCoordinate(location?.longitude, -180, 180);
  if (!id || !name || latitude === null || longitude === null) return null;

  const formattedAddress = cleanString(place?.formattedAddress, 500);
  const components = Array.isArray(place?.addressComponents)
    ? place.addressComponents.map(asRecord).filter((item) => item !== null)
    : [];
  const primaryType = cleanString(place?.primaryType, 100);
  const types = Array.isArray(place?.types)
    ? place.types.map((type) => cleanString(type, 100)).filter(
      (type): type is string => type !== null,
    ).slice(0, 32)
    : [];

  return {
    resolved: {
      provider: "google_places",
      provider_place_id: id,
      name,
      formatted_address: formattedAddress,
      locality: addressComponent(components, [
        "locality",
        "postal_town",
        "administrative_area_level_2",
      ], false),
      region: addressComponent(
        components,
        ["administrative_area_level_1"],
        true,
      ),
      country: addressComponent(components, ["country"], true),
      latitude,
      longitude,
      primary_type: primaryType,
      types,
    },
    normalizedName: normalize(name),
    normalizedAddress: normalize(
      [
        formattedAddress,
        ...components.flatMap((component) => [
          cleanString(component.longText, 160),
          cleanString(component.shortText, 40),
        ]),
      ].filter(Boolean).join(" "),
    ),
    primaryType: normalize(primaryType ?? ""),
  };
}

function candidateScore(place: ParsedGooglePlace, hint: PlaceHint): number {
  if (administrativePrimaryTypes.has(place.primaryType)) return -1;
  const requestedName = normalize(hint.name);
  if (!requestedName) return -1;
  const exactName = place.normalizedName === requestedName;
  const requestedTokens = tokens(requestedName);
  if (
    naturalFeaturePrimaryTypes.has(place.primaryType) &&
    requestedTokens.some((token) => venueIntentTokens.has(token))
  ) {
    return -1;
  }
  const candidateTokens = tokens(place.normalizedName);
  const areaTokens = tokens(normalize(hint.area ?? ""));
  const requestedAnchors = requestedTokens.filter((token) =>
    !areaTokens.includes(token) && !genericNameTokens.has(token)
  );
  const sharedAnchors =
    requestedAnchors.filter((token) => candidateTokens.includes(token)).length;
  if (!exactName && requestedAnchors.length > 0 && sharedAnchors === 0) {
    return -1;
  }

  const intersection =
    requestedTokens.filter((token) => candidateTokens.includes(token)).length;
  const union = new Set([...requestedTokens, ...candidateTokens]).size;
  const similarity = union === 0 ? 0 : intersection / union;
  const containment =
    Math.min(requestedTokens.length, candidateTokens.length) ===
        0
      ? 0
      : intersection / Math.min(requestedTokens.length, candidateTokens.length);
  const containsName = place.normalizedName.includes(requestedName) ||
    requestedName.includes(place.normalizedName);
  if (!exactName && !containsName && similarity < 0.5 && containment < 0.75) {
    return -1;
  }

  let score = exactName
    ? 120
    : containsName
    ? 82
    : Math.round(similarity * 70 + containment * 30);
  if (requestedAnchors.length > 0) {
    score += Math.round(sharedAnchors / requestedAnchors.length * 30);
  }
  const normalizedArea = normalize(hint.area ?? "");
  if (normalizedArea) {
    const requestedAreaTokens = tokens(normalizedArea);
    const addressTokens = tokens(place.normalizedAddress);
    const overlap = requestedAreaTokens.filter((token) =>
      addressTokens.includes(token)
    ).length;
    score += Math.round(overlap / Math.max(1, requestedAreaTokens.length) * 24);
  }
  return score;
}

function addressComponent(
  components: Record<string, unknown>[],
  wantedTypes: string[],
  preferShortText: boolean,
): string | null {
  for (const wantedType of wantedTypes) {
    const component = components.find((item) =>
      Array.isArray(item.types) && item.types.includes(wantedType)
    );
    if (!component) continue;
    return preferShortText
      ? cleanString(component.shortText, 160) ??
        cleanString(component.longText, 160)
      : cleanString(component.longText, 160) ??
        cleanString(component.shortText, 160);
  }
  return null;
}

function finiteCoordinate(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  return typeof value === "number" && Number.isFinite(value) &&
      value >= minimum && value <= maximum
    ? value
    : null;
}

function normalize(value: string): string {
  return value.toLocaleLowerCase("en-US")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function tokens(value: string): string[] {
  return [...new Set(value.split(" ").filter(Boolean))];
}

const administrativePrimaryTypes = new Set([
  "administrative area level 1",
  "administrative area level 2",
  "administrative area level 3",
  "administrative area level 4",
  "administrative area level 5",
  "administrative area level 6",
  "administrative area level 7",
  "colloquial area",
  "country",
  "locality",
  "neighborhood",
  "postal code",
  "postal town",
  "route",
  "sublocality",
]);

const naturalFeaturePrimaryTypes = new Set([
  "archipelago",
  "island",
  "lake",
  "mountain peak",
  "natural feature",
  "nature preserve",
  "river",
  "scenic spot",
  "woods",
]);

const venueIntentTokens = new Set([
  "camp",
  "hotel",
  "inn",
  "lodge",
  "private",
  "resort",
  "retreat",
  "spa",
  "suite",
  "suites",
]);

const genericNameTokens = new Set([
  "a",
  "an",
  "and",
  "at",
  "by",
  "camp",
  "hotel",
  "inn",
  "island",
  "lodge",
  "of",
  "on",
  "resort",
  "spa",
  "the",
]);

export function googlePlacesAPIKey(
  dependencies: RuntimeDependencies,
): string | null {
  return cleanString(
    dependencies.env("WANDER_GOOGLE_PLACES_API_KEY") ??
      dependencies.env("GOOGLE_PLACES_API_KEY"),
    4_096,
  );
}
