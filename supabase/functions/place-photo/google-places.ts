export type PlacePhotoInput = {
  name: string;
  address: string | null;
  latitude: number | null;
  longitude: number | null;
  sourceProvider: string | null;
  sourceProviderPlaceID: string | null;
  requiresPhoto: boolean;
};

export type GoogleAuthorAttribution = {
  displayName?: string;
  uri?: string;
  photoUri?: string;
};

export type GooglePhoto = {
  name?: string;
  widthPx?: number;
  heightPx?: number;
  authorAttributions?: GoogleAuthorAttribution[];
  googleMapsUri?: string;
  flagContentUri?: string;
};

export type GooglePlace = {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  primaryType?: string;
  types?: string[];
  photos?: GooglePhoto[];
};

export function selectGooglePlace(
  places: GooglePlace[],
  input: PlacePhotoInput,
): GooglePlace | null {
  const requestedName = normalize(input.name);
  if (!requestedName) return null;

  const ranked = places
    .map((place) => ({ place, score: placeScore(place, input, requestedName) }))
    .filter((candidate) =>
      candidate.score >= 0 &&
      (!input.requiresPhoto || representativePhoto(candidate.place))
    )
    .sort((lhs, rhs) => rhs.score - lhs.score);

  return ranked[0]?.place ?? null;
}

export function representativePhoto(place: GooglePlace): GooglePhoto | null {
  return place.photos?.find((photo) => {
    if (!photo.name) return false;
    const width = photo.widthPx ?? 0;
    const height = photo.heightPx ?? 0;
    return width === 0 || height === 0 || Math.max(width, height) >= 400;
  }) ?? null;
}

export function isGoogleProvider(sourceProvider: string | null): boolean {
  const provider = normalize(sourceProvider ?? "");
  return provider === "google" || provider === "google maps" ||
    provider === "google places";
}

export function shouldUseGooglePlaces(input: PlacePhotoInput): boolean {
  const provider = normalize(input.sourceProvider ?? "");
  const providerPlaceID = normalize(input.sourceProviderPlaceID ?? "");
  const name = normalize(input.name);
  return provider !== "coordinate" &&
    !providerPlaceID.startsWith("coordinate ") &&
    name !== "dropped pin";
}

function placeScore(
  place: GooglePlace,
  input: PlacePhotoInput,
  requestedName: string,
): number {
  const candidateName = normalize(place.displayName?.text ?? "");
  if (!candidateName) return -1;

  const exactName = candidateName === requestedName;
  const nameSimilarity = tokenSimilarity(candidateName, requestedName);
  const includesName = candidateName.includes(requestedName) ||
    requestedName.includes(candidateName);
  const sharedDistinctiveTokens = sharedDistinctiveNameTokens(
    candidateName,
    requestedName,
  );
  const distance = distanceMeters(
    input.latitude,
    input.longitude,
    place.location?.latitude ?? null,
    place.location?.longitude ?? null,
  );
  const requestedAddress = normalize(input.address ?? "");
  const candidateAddress = normalize(place.formattedAddress ?? "");
  const addressSimilarity = requestedAddress && candidateAddress
    ? tokenContainment(requestedAddress, candidateAddress)
    : 0;
  const hasComparableAddresses = Boolean(requestedAddress && candidateAddress);
  const conflictingStreetNumbers = hasComparableAddresses &&
    haveConflictingAddressNumbers(requestedAddress, candidateAddress);
  const nearbyAlias = sharedDistinctiveTokens > 0 &&
    distance !== null &&
    !conflictingStreetNumbers &&
    (
      (distance <= 75 &&
        (!hasComparableAddresses || addressSimilarity >= 0.5)) ||
      (distance <= 250 && addressSimilarity >= 0.5)
    );

  const similarDistinctiveName = nameSimilarity >= 0.4 &&
    sharedDistinctiveTokens > 0;
  if (!exactName && !includesName && !similarDistinctiveName && !nearbyAlias) {
    return -1;
  }

  let score = exactName
    ? 120
    : includesName
    ? 72
    : Math.round(nameSimilarity * 52) + (nearbyAlias ? 40 : 0);

  if (distance !== null) {
    if (distance <= 75) score += 48;
    else if (distance <= 250) score += 32;
    else if (distance <= 1_000) score += 12;
    else if (distance > 5_000) return -1;
  }

  if (addressSimilarity > 0) {
    score += Math.round(addressSimilarity * 24);
  }

  // A coordinate-backed nearby result may have a shortened display name, but a
  // text-only result must still look like the requested venue.
  if (
    distance === null && !exactName && !includesName && nameSimilarity < 0.5
  ) return -1;
  if (
    distance !== null && distance > 1_000 && !exactName && nameSimilarity < 0.7
  ) return -1;

  return score;
}

const genericVenueNameTokens = new Set([
  "a",
  "an",
  "and",
  "at",
  "bakery",
  "bar",
  "bars",
  "cafe",
  "club",
  "coffee",
  "eatery",
  "food",
  "foods",
  "grill",
  "hotel",
  "house",
  "kitchen",
  "lounge",
  "market",
  "of",
  "pub",
  "restaurant",
  "restaurants",
  "shop",
  "store",
  "the",
]);

function sharedDistinctiveNameTokens(lhs: string, rhs: string): number {
  const lhsTokens = new Set(
    lhs.split(" ").filter((token) =>
      token && !genericVenueNameTokens.has(token)
    ),
  );
  const rhsTokens = new Set(
    rhs.split(" ").filter((token) =>
      token && !genericVenueNameTokens.has(token)
    ),
  );

  let overlap = 0;
  for (const token of lhsTokens) {
    if (rhsTokens.has(token)) overlap += 1;
  }
  return overlap;
}

function normalize(value: string): string {
  return value
    .toLocaleLowerCase("en-US")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function tokenSimilarity(lhs: string, rhs: string): number {
  const lhsTokens = new Set(lhs.split(" ").filter(Boolean));
  const rhsTokens = new Set(rhs.split(" ").filter(Boolean));
  if (!lhsTokens.size || !rhsTokens.size) return 0;

  let overlap = 0;
  for (const token of lhsTokens) {
    if (rhsTokens.has(token)) overlap += 1;
  }
  return overlap / Math.max(lhsTokens.size, rhsTokens.size);
}

function tokenContainment(lhs: string, rhs: string): number {
  const lhsTokens = new Set(lhs.split(" ").filter(Boolean));
  const rhsTokens = new Set(rhs.split(" ").filter(Boolean));
  if (!lhsTokens.size || !rhsTokens.size) return 0;

  let overlap = 0;
  for (const token of lhsTokens) {
    if (rhsTokens.has(token)) overlap += 1;
  }
  return overlap / Math.min(lhsTokens.size, rhsTokens.size);
}

function haveConflictingAddressNumbers(lhs: string, rhs: string): boolean {
  const lhsStreetNumber = lhs.split(" ").find((token) =>
    /^\d+[a-z]?$/.test(token)
  );
  const rhsStreetNumber = rhs.split(" ").find((token) =>
    /^\d+[a-z]?$/.test(token)
  );
  return Boolean(
    lhsStreetNumber && rhsStreetNumber && lhsStreetNumber !== rhsStreetNumber,
  );
}

function distanceMeters(
  latitudeA: number | null,
  longitudeA: number | null,
  latitudeB: number | null,
  longitudeB: number | null,
): number | null {
  if (
    latitudeA === null || longitudeA === null ||
    latitudeB === null || longitudeB === null
  ) return null;

  const radians = (degrees: number) => degrees * Math.PI / 180;
  const earthRadiusMeters = 6_371_000;
  const deltaLatitude = radians(latitudeB - latitudeA);
  const deltaLongitude = radians(longitudeB - longitudeA);
  const a = Math.sin(deltaLatitude / 2) ** 2 +
    Math.cos(radians(latitudeA)) * Math.cos(radians(latitudeB)) *
      Math.sin(deltaLongitude / 2) ** 2;
  return earthRadiusMeters * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}
