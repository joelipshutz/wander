import {
  type GooglePlace,
  isGoogleProvider,
  type PlacePhotoInput,
  representativePhoto,
  selectGooglePlace,
  shouldUseGooglePlaces,
} from "./google-places.ts";

const googlePlacesBaseURL = "https://places.googleapis.com/v1";
const cacheBucket = "google-place-photo-cache";
const signedURLLifetimeSeconds = 24 * 60 * 60;
const businessMetadataFreshnessMilliseconds = 15 * 60 * 1_000;
const maximumCachedImageBytes = 16 * 1_024 * 1_024;
const providerSourceMaximumPixels = 3_200;
const maximumBatchSize = 32;
const noStoreHeaders = { "Cache-Control": "private, no-store, max-age=0" };

export type PlacePhotoDependencies = {
  fetch: typeof fetch;
  env: (name: string) => string | undefined;
  now: () => Date;
  diagnostic?: (event: Record<string, string | boolean>) => void;
};

type SupabaseConfiguration = {
  url: string;
  publishableKey: string;
  serviceRoleKey: string | null;
};

type CachedPhotoRow = {
  cache_key: string;
  object_path: string | null;
  provider_place_id: string;
  provider_primary_type: string | null;
  provider_types: string[];
  provider_rating: number | null;
  provider_user_rating_count: number | null;
  provider_open_now: boolean | null;
  provider_next_open_time: string | null;
  provider_next_close_time: string | null;
  provider_utc_offset_minutes: number | null;
  width: number | null;
  height: number | null;
  content_type: string | null;
  byte_size: number | null;
  author_name: string | null;
  author_profile_url: string | null;
  author_avatar_url: string | null;
  source_photo_url: string | null;
  flag_content_url: string | null;
  fetched_at: string;
  last_accessed_at: string;
};

type PlacePhotoPayload = {
  provider: "google_places";
  provider_place_id: string;
  provider_primary_type: string | null;
  provider_types: string[];
  provider_rating: number | null;
  provider_user_rating_count: number | null;
  provider_open_now: boolean | null;
  provider_next_open_time: string | null;
  provider_next_close_time: string | null;
  provider_utc_offset_minutes: number | null;
  photo_url: string;
  width: number | null;
  height: number | null;
  author_name: string | null;
  author_profile_url: string | null;
  author_avatar_url: string | null;
  source_photo_url: string | null;
  flag_content_url: string | null;
};

type PlacePhotoResolution = {
  status: number;
  payload?: PlacePhotoPayload;
  error?: string;
};

const defaultDependencies: PlacePhotoDependencies = {
  fetch,
  env: (name) => Deno.env.get(name),
  now: () => new Date(),
};

export async function handleRequest(
  request: Request,
  dependencies: PlacePhotoDependencies = defaultDependencies,
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return jsonResponse({ error: "missing_authorization" }, 401);
  }

  const supabase = supabaseConfiguration(dependencies);
  if (
    !supabase ||
    !await hasValidSupabaseSession(authorization, supabase, dependencies)
  ) {
    return jsonResponse({ error: "invalid_authorization" }, 401);
  }

  const body = await readBody(request);
  if (Array.isArray(body.requests)) {
    return handleBatchRequest(body.requests, supabase, dependencies);
  }

  const input = placePhotoInput(body);
  if (!input) {
    return jsonResponse({ error: "invalid_place" }, 400);
  }
  const resolution = await resolvePhotoPayload(
    input,
    supabase,
    dependencies,
  );
  reportResolution(input, resolution, dependencies);
  return resolutionResponse(resolution);
}

async function handleBatchRequest(
  values: unknown[],
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<Response> {
  if (!values.length || values.length > maximumBatchSize) {
    return jsonResponse({ error: "invalid_batch" }, 400);
  }

  const inputs = values.map((value, index) => ({
    index,
    input: value && typeof value === "object" && !Array.isArray(value)
      ? placePhotoInput(value as Record<string, unknown>)
      : null,
  }));
  const validInputs = inputs.filter(
    (item): item is { index: number; input: PlacePhotoInput } =>
      item.input !== null && shouldUseGooglePlaces(item.input),
  );
  const keyedInputs = await Promise.all(validInputs.map(async (item) => ({
    ...item,
    cacheKey: await placePhotoCacheKey(item.input),
  })));
  const cachedRows = supabase.serviceRoleKey
    ? await readCachedPhotos(
      keyedInputs.map((item) => item.cacheKey),
      supabase,
      dependencies,
    )
    : new Map<string, CachedPhotoRow>();

  const resolved = await mapWithConcurrency(keyedInputs, 4, async (item) => {
    let resolution: PlacePhotoResolution;
    try {
      resolution = await resolvePhotoPayload(
        item.input, supabase, dependencies, item.cacheKey,
        cachedRows.get(item.cacheKey) ?? null, item.input.requiresPhoto,
      );
    } catch {
      // One provider timeout must not discard successful sibling manifests.
      console.warn("place_photo_batch_item_failed");
      resolution = { status: 503, error: "provider_unavailable" };
    }
    reportResolution(item.input, resolution, dependencies);
    return { index: item.index, resolution };
  });
  const resolutionsByIndex = new Map(
    resolved.map((item) => [item.index, item.resolution]),
  );
  return Response.json({
    results: inputs.map(({ index }) => {
      const resolution = resolutionsByIndex.get(index);
      return {
        index,
        photo: resolution?.status === 200 ? resolution.payload ?? null : null,
        error: resolution?.status === 200
          ? null
          : resolution?.error ?? "invalid_place",
      };
    }),
  }, { headers: noStoreHeaders });
}

async function resolvePhotoPayload(
  input: PlacePhotoInput,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
  resolvedCacheKey?: string,
  resolvedCachedRow?: CachedPhotoRow | null,
  skipsStaleBusinessRefresh = false,
): Promise<PlacePhotoResolution> {
  if (!shouldUseGooglePlaces(input)) {
    return { status: 404, error: "photo_not_found" };
  }

  const cacheKey = resolvedCacheKey ?? await placePhotoCacheKey(input);
  const cached = typeof resolvedCachedRow !== "undefined"
    ? resolvedCachedRow
    : supabase.serviceRoleKey
    ? await readCachedPhoto(cacheKey, supabase, dependencies)
    : null;
  if (cached && businessMetadataIsFresh(cached, dependencies.now()) &&
      (input.requiresPhoto || typeof cached.provider_open_now === "boolean")) {
    const payload = await cachedPayload(
      cached,
      input,
      supabase,
      dependencies,
    );
    if (payload) {
      console.log("place_photo_cache_hit");
      return { status: 200, payload };
    }
  }

  const apiKey = googlePlacesAPIKey(dependencies);
  if (cached) {
    let canReuseCachedImage = true;
    if (!skipsStaleBusinessRefresh && apiKey && supabase.serviceRoleKey) {
      try {
        const refreshedPlace = await resolvePlace(
          { ...input, requiresPhoto: false },
          apiKey,
          dependencies,
          cached.provider_place_id,
        );
        if (refreshedPlace?.id) {
          const refreshedPayload = placePayload(refreshedPlace);
          if (refreshedPlace.id !== cached.provider_place_id) {
            // Do not relabel the old provider's image when a native alias now
            // matches a different provider identity. Photo requests must load
            // that identity's own image before replacing the cache row.
            canReuseCachedImage = false;
            if (!input.requiresPhoto) return { status: 200, payload: refreshedPayload };
          } else {
            const refreshedRow = refreshingBusinessMetadata(cached, refreshedPayload, dependencies.now());
            await writeCachedMetadata(cacheKey, refreshedPayload, supabase, dependencies);
            const payload = await cachedPayload(refreshedRow, input, supabase, dependencies);
            if (payload) {
              console.log("place_photo_business_metadata_refreshed");
              return { status: 200, payload };
            }
          }
        }
      } catch (error) {
        console.warn(
          "place_photo_business_metadata_refresh_failed",
          error instanceof Error ? error.message : "unknown_error",
        );
      }
    }

    const payload = canReuseCachedImage ? await cachedPayload(
      omittingStaleOpeningHours(cached), input, supabase, dependencies,
    ) : null;
    if (payload) {
      console.log("place_photo_cache_hit_without_current_hours");
      return { status: 200, payload };
    }
  }

  console.log("place_photo_cache_miss");
  if (!apiKey) {
    return { status: 503, error: "provider_unavailable" };
  }

  const place = await resolvePlace(input, apiKey, dependencies);
  if (!place?.id) {
    return { status: 404, error: "photo_not_found" };
  }

  const basePayload = placePayload(place);
  if (!input.requiresPhoto) {
    if (supabase.serviceRoleKey) {
      await writeCachedMetadata(cacheKey, basePayload, supabase, dependencies);
    }
    return { status: 200, payload: basePayload };
  }
  // A venue can have usable photos after a first item with missing source
  // attribution. Keep provider order, but require each chosen image's own
  // Maps link; a place/gallery URL does not identify the individual photo.
  const photo = representativePhoto({
    ...place,
    photos: place.photos?.filter((item) => absoluteGoogleURL(item.googleMapsUri)),
  });
  const sourcePhotoURL = absoluteGoogleURL(photo?.googleMapsUri);
  if (!photo?.name || !sourcePhotoURL) {
    return { status: 404, error: representativePhoto(place)
      ? "photo_attribution_unavailable" : "photo_not_found" };
  }

  const media = await fetchJSON<{ photoUri?: string }>(
    `${googlePlacesBaseURL}/${photo.name}/media?maxWidthPx=${providerSourceMaximumPixels}&maxHeightPx=${providerSourceMaximumPixels}&skipHttpRedirect=true&key=${
      encodeURIComponent(apiKey)
    }`,
    { method: "GET" },
    dependencies,
  );
  if (!media.photoUri) {
    throw new Error("google_photo_missing_uri");
  }

  const author = photo.authorAttributions?.[0];
  const providerPayload: PlacePhotoPayload = {
    ...basePayload,
    photo_url: media.photoUri,
    width: finiteInteger(photo.widthPx),
    height: finiteInteger(photo.heightPx),
    author_name: cleanString(author?.displayName),
    author_profile_url: absoluteGoogleURL(author?.uri),
    author_avatar_url: absoluteGoogleURL(author?.photoUri),
    source_photo_url: sourcePhotoURL,
    flag_content_url: absoluteGoogleURL(photo.flagContentUri),
  };

  if (supabase.serviceRoleKey) {
    const cachedPayload = await cacheProviderPhoto(
      cacheKey,
      media.photoUri,
      providerPayload,
      input,
      supabase,
      dependencies,
    );
    if (cachedPayload) {
      return { status: 200, payload: cachedPayload };
    }
  }

  // Keep the app working if Storage is temporarily unavailable. The provider
  // URL is never persisted by the client and the next request retries caching.
  return { status: 200, payload: providerPayload };
}

function resolutionResponse(resolution: PlacePhotoResolution): Response {
  if (resolution.status === 200 && resolution.payload) {
    return Response.json(resolution.payload, { headers: noStoreHeaders });
  }
  return jsonResponse(
    { error: resolution.error ?? "internal_error" },
    resolution.status,
  );
}

async function resolvePlace(
  input: PlacePhotoInput,
  apiKey: string,
  dependencies: PlacePhotoDependencies,
  cachedProviderPlaceID?: string,
): Promise<GooglePlace | null> {
  const commonFields = "id,displayName,formattedAddress,location,primaryType,types,rating,userRatingCount,currentOpeningHours,utcOffsetMinutes,businessStatus,movedPlaceId";
  const directFieldMask = input.requiresPhoto ? `${commonFields},photos` : commonFields;
  const searchFieldMask = directFieldMask.split(",").map((field) => `places.${field}`).join(",");
  const details = (id: string) => fetchJSON<GooglePlace>(
    `${googlePlacesBaseURL}/places/${encodeURIComponent(id)}`,
    { method: "GET", headers: googleHeaders(apiKey, directFieldMask) }, dependencies,
  );
  const requestedGoogleID = isGoogleProvider(input.sourceProvider) ? input.sourceProviderPlaceID : null;
  const directID = requestedGoogleID ?? cleanString(cachedProviderPlaceID);
  let directFallback: GooglePlace | null = null;
  if (directID) {
    try {
      const directPlace = await details(directID);
      // A previously matched native alias can move or be repurposed. Validate
      // its current identity before reusing it; current search handles changes.
      const accepted = requestedGoogleID || (
        directPlace.businessStatus !== "CLOSED_PERMANENTLY" && !directPlace.movedPlaceId &&
        selectGooglePlace([directPlace], { ...input, requiresPhoto: false }) !== null
      );
      reportProviderLookup(requestedGoogleID ? "provider_details" : "cached_details",
        accepted ? "matched" : "stale_identity", directPlace, dependencies);
      if (accepted && directPlace.id) {
        if (!input.requiresPhoto || representativePhoto(directPlace)) return directPlace;
        directFallback = directPlace;
      }
    } catch {
      reportProviderLookup(requestedGoogleID ? "provider_details" : "cached_details",
        "unavailable", null, dependencies);
    }
  }

  const searchBody: Record<string, unknown> = {
    textQuery: [input.name, input.address].filter(Boolean).join(" "), pageSize: 5,
  };
  if (input.latitude !== null && input.longitude !== null) {
    searchBody.locationBias = {
      circle: { center: { latitude: input.latitude, longitude: input.longitude }, radius: 1_000 },
    };
  }
  const search = await fetchJSON<{ places?: GooglePlace[] }>(
    `${googlePlacesBaseURL}/places:searchText`,
    { method: "POST", headers: googleHeaders(apiKey, searchFieldMask), body: JSON.stringify(searchBody) },
    dependencies,
  );
  // Match identity before requiring imagery; a sparse search result can omit
  // hours/photos that Place Details supplies for that same provider ID.
  const matched = selectGooglePlace(search.places ?? [], { ...input, requiresPhoto: false });
  reportProviderLookup("search", matched ? "matched" : "no_match", matched, dependencies);
  if (!matched?.id) return directFallback;
  const needsDetails = typeof matched.currentOpeningHours?.openNow !== "boolean" ||
    (input.requiresPhoto && !representativePhoto({
      ...matched, photos: matched.photos?.filter((photo) => absoluteGoogleURL(photo.googleMapsUri)),
    }));
  if (needsDetails) {
    try {
      const enriched = await details(matched.id);
      // Details must belong to the selected provider identity. Do not attach
      // another venue's hours or image to this place after an ID redirect.
      if (enriched.id === matched.id && !enriched.movedPlaceId) {
        const resolved = { ...matched, ...enriched };
        reportProviderLookup("search_details", "matched", resolved, dependencies);
        return resolved;
      }
      reportProviderLookup("search_details", "stale_identity", enriched, dependencies);
    } catch {
      reportProviderLookup("search_details", "unavailable", null, dependencies);
    }
  }
  return matched;
}

function reportProviderLookup(
  lookup: "provider_details" | "cached_details" | "search" | "search_details",
  result: "matched" | "no_match" | "stale_identity" | "unavailable",
  place: GooglePlace | null,
  dependencies: PlacePhotoDependencies,
): void {
  const event = {
    event: "place_photo_provider_lookup", lookup, result,
    has_current_hours: typeof place?.currentOpeningHours?.openNow === "boolean",
    has_photo: Boolean(place && representativePhoto(place)),
    has_moved_place: Boolean(place?.movedPlaceId),
  };
  if (dependencies.diagnostic) dependencies.diagnostic(event);
  else console.log(JSON.stringify(event));
}

function reportResolution(
  input: PlacePhotoInput,
  resolution: PlacePhotoResolution,
  dependencies: PlacePhotoDependencies,
): void {
  const photo = resolution.payload;
  const event = {
    event: "place_photo_resolution",
    request_kind: input.requiresPhoto ? "photo" : "metadata",
    result_kind: photo ? (photo.photo_url ? "photo_ready" : "metadata_ready")
      : resolution.status === 404 ? "not_found" : "unavailable",
    failure_kind: resolution.error ?? "none",
    has_current_hours: typeof photo?.provider_open_now === "boolean",
    has_image_url: Boolean(photo?.photo_url),
    has_source_link: Boolean(photo?.source_photo_url),
  };
  if (dependencies.diagnostic) dependencies.diagnostic(event);
  else console.log(JSON.stringify(event));
}

async function readCachedPhoto(
  cacheKey: string,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<CachedPhotoRow | null> {
  try {
    const endpoint = new URL(
      `${supabase.url}/rest/v1/google_place_photo_cache`,
    );
    endpoint.searchParams.set("cache_key", `eq.${cacheKey}`);
    endpoint.searchParams.set("select", "*");
    endpoint.searchParams.set("limit", "1");
    const rows = await fetchWithTimeout(endpoint, {
      headers: serviceHeaders(supabase),
    }, 6_000, dependencies, async (response) => {
      if (!response.ok) throw new Error(`cache_read_status_${response.status}`);
      return await response.json() as CachedPhotoRow[];
    });
    return rows[0] ?? null;
  } catch (error) {
    console.warn(
      "place_photo_cache_read_failed",
      error instanceof Error ? error.message : "unknown_error",
    );
    return null;
  }
}

async function readCachedPhotos(
  cacheKeys: string[],
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<Map<string, CachedPhotoRow>> {
  const uniqueKeys = [...new Set(cacheKeys)].filter((key) =>
    /^[0-9a-f]{64}$/.test(key)
  );
  if (!uniqueKeys.length) return new Map();
  try {
    const endpoint = new URL(
      `${supabase.url}/rest/v1/google_place_photo_cache`,
    );
    endpoint.searchParams.set("cache_key", `in.(${uniqueKeys.join(",")})`);
    endpoint.searchParams.set("select", "*");
    const rows = await fetchWithTimeout(endpoint, {
      headers: serviceHeaders(supabase),
    }, 6_000, dependencies, async (response) => {
      if (!response.ok) throw new Error(`cache_batch_read_status_${response.status}`);
      return await response.json() as CachedPhotoRow[];
    });
    return new Map(rows.map((row) => [row.cache_key, row]));
  } catch (error) {
    console.warn(
      "place_photo_cache_batch_read_failed",
      error instanceof Error ? error.message : "unknown_error",
    );
    return new Map();
  }
}

async function cachedPayload(
  row: CachedPhotoRow,
  input: PlacePhotoInput,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<PlacePhotoPayload | null> {
  let photoURL = "";
  if (input.requiresPhoto) {
    if (!row.object_path) return null;
    photoURL = await signedStorageURL(
      row.object_path,
      input.renderVariant ?? "profile",
      supabase,
      dependencies,
    ) ?? "";
    if (!photoURL) return null;
  }
  return {
    provider: "google_places",
    provider_place_id: row.provider_place_id,
    provider_primary_type: row.provider_primary_type,
    provider_types: row.provider_types,
    provider_rating: row.provider_rating,
    provider_user_rating_count: row.provider_user_rating_count,
    provider_open_now: row.provider_open_now,
    provider_next_open_time: row.provider_next_open_time,
    provider_next_close_time: row.provider_next_close_time,
    provider_utc_offset_minutes: row.provider_utc_offset_minutes,
    photo_url: photoURL,
    width: row.width,
    height: row.height,
    author_name: row.author_name,
    author_profile_url: row.author_profile_url,
    author_avatar_url: row.author_avatar_url,
    source_photo_url: row.source_photo_url,
    flag_content_url: row.flag_content_url,
  };
}

async function cacheProviderPhoto(
  cacheKey: string,
  providerURL: string,
  payload: PlacePhotoPayload,
  input: PlacePhotoInput,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<PlacePhotoPayload | null> {
  try {
    const image = await downloadCacheableImage(providerURL, dependencies);
    if (!image) return null;
    const objectPath = `${cacheKey.slice(0, 2)}/${cacheKey}.img`;
    await uploadCachedImage(objectPath, image, supabase, dependencies);
    await upsertCacheRow(
      {
        ...cacheRow(cacheKey, payload, dependencies.now()),
        object_path: objectPath,
        content_type: image.contentType,
        byte_size: image.bytes.byteLength,
      },
      supabase,
      dependencies,
    );
    const photoURL = await signedStorageURL(
      objectPath,
      input.renderVariant ?? "profile",
      supabase,
      dependencies,
    );
    if (!photoURL) return null;
    console.log("place_photo_cache_stored");
    return { ...payload, photo_url: photoURL };
  } catch (error) {
    console.warn(
      "place_photo_cache_store_failed",
      error instanceof Error ? error.message : "unknown_error",
    );
    return null;
  }
}

async function writeCachedMetadata(
  cacheKey: string,
  payload: PlacePhotoPayload,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<void> {
  try {
    // Metadata and image requests can finish concurrently. Updating only
    // these columns preserves any image that the other request just cached.
    await upsertCacheRow({
      cache_key: cacheKey,
      provider_place_id: payload.provider_place_id,
      provider_primary_type: payload.provider_primary_type,
      provider_types: payload.provider_types,
      provider_rating: payload.provider_rating,
      provider_user_rating_count: payload.provider_user_rating_count,
      provider_open_now: payload.provider_open_now,
      provider_next_open_time: payload.provider_next_open_time,
      provider_next_close_time: payload.provider_next_close_time,
      provider_utc_offset_minutes: payload.provider_utc_offset_minutes,
      fetched_at: dependencies.now().toISOString(),
      last_accessed_at: dependencies.now().toISOString(),
    }, supabase, dependencies);
    console.log("place_photo_metadata_cache_stored");
  } catch (error) {
    console.warn(
      "place_photo_metadata_cache_store_failed",
      error instanceof Error ? error.message : "unknown_error",
    );
  }
}

function cacheRow(
  cacheKey: string,
  payload: PlacePhotoPayload,
  fetchedAt: Date,
): CachedPhotoRow {
  return {
    cache_key: cacheKey,
    object_path: null,
    provider_place_id: payload.provider_place_id,
    provider_primary_type: payload.provider_primary_type,
    provider_types: payload.provider_types,
    provider_rating: payload.provider_rating,
    provider_user_rating_count: payload.provider_user_rating_count,
    provider_open_now: payload.provider_open_now,
    provider_next_open_time: payload.provider_next_open_time,
    provider_next_close_time: payload.provider_next_close_time,
    provider_utc_offset_minutes: payload.provider_utc_offset_minutes,
    width: payload.width,
    height: payload.height,
    content_type: null,
    byte_size: null,
    author_name: payload.author_name,
    author_profile_url: payload.author_profile_url,
    author_avatar_url: payload.author_avatar_url,
    source_photo_url: payload.source_photo_url,
    flag_content_url: payload.flag_content_url,
    fetched_at: fetchedAt.toISOString(),
    last_accessed_at: fetchedAt.toISOString(),
  };
}

function businessMetadataIsFresh(row: CachedPhotoRow, now: Date): boolean {
  const fetchedAt = Date.parse(row.fetched_at);
  const age = now.getTime() - fetchedAt;
  return Number.isFinite(fetchedAt) && age >= 0 &&
    age <= businessMetadataFreshnessMilliseconds;
}

function refreshingBusinessMetadata(
  row: CachedPhotoRow,
  payload: PlacePhotoPayload,
  fetchedAt: Date,
): CachedPhotoRow {
  return {
    ...row,
    provider_place_id: payload.provider_place_id,
    provider_primary_type: payload.provider_primary_type,
    provider_types: payload.provider_types,
    provider_rating: payload.provider_rating,
    provider_user_rating_count: payload.provider_user_rating_count,
    provider_open_now: payload.provider_open_now,
    provider_next_open_time: payload.provider_next_open_time,
    provider_next_close_time: payload.provider_next_close_time,
    provider_utc_offset_minutes: payload.provider_utc_offset_minutes,
    fetched_at: fetchedAt.toISOString(),
    last_accessed_at: fetchedAt.toISOString(),
  };
}

function omittingStaleOpeningHours(row: CachedPhotoRow): CachedPhotoRow {
  return {
    ...row,
    provider_open_now: null,
    provider_next_open_time: null,
    provider_next_close_time: null,
  };
}

async function upsertCacheRow(
  row: Pick<CachedPhotoRow, "cache_key" | "provider_place_id" | "fetched_at"> & Partial<CachedPhotoRow>,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<void> {
  const endpoint = new URL(`${supabase.url}/rest/v1/google_place_photo_cache`);
  endpoint.searchParams.set("on_conflict", "cache_key");
  await fetchWithTimeout(endpoint, {
    method: "POST",
    headers: {
      ...serviceHeaders(supabase),
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify(row),
  }, 6_000, dependencies, async (response) => {
    await response.body?.cancel();
    if (!response.ok) throw new Error(`cache_write_status_${response.status}`);
  });
}

async function downloadCacheableImage(
  url: string,
  dependencies: PlacePhotoDependencies,
): Promise<{ bytes: Uint8Array; contentType: string } | null> {
  return await fetchWithTimeout(
    url,
    {
      method: "GET",
      headers: { Accept: "image/jpeg,image/png,image/webp" },
    },
    10_000,
    dependencies,
    async (response) => {
      if (!response.ok) throw new Error(`google_photo_download_status_${response.status}`);
      const contentLength = Number(response.headers.get("content-length"));
      if (Number.isFinite(contentLength) && contentLength > maximumCachedImageBytes) {
        throw new Error("google_photo_too_large");
      }
      const contentType = response.headers.get("content-type")?.split(";", 1)[0]
        ?.trim().toLowerCase();
      if (!contentType || !["image/jpeg", "image/png", "image/webp"].includes(contentType)) {
        throw new Error("google_photo_unsupported_content_type");
      }
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (!bytes.byteLength || bytes.byteLength > maximumCachedImageBytes) {
        throw new Error("google_photo_invalid_size");
      }
      return { bytes, contentType };
    },
  );
}

async function uploadCachedImage(
  objectPath: string,
  image: { bytes: Uint8Array; contentType: string },
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<void> {
  await fetchWithTimeout(
    `${supabase.url}/storage/v1/object/${cacheBucket}/${
      encodeStoragePath(objectPath)
    }`,
    {
      method: "POST",
      headers: {
        ...serviceHeaders(supabase),
        "Content-Type": image.contentType,
        "Cache-Control": String(signedURLLifetimeSeconds),
        "x-upsert": "true",
      },
      body: new Blob([image.bytes.buffer as ArrayBuffer], {
        type: image.contentType,
      }),
    },
    10_000,
    dependencies,
    async (response) => {
      await response.body?.cancel();
      if (!response.ok) throw new Error(`cache_upload_status_${response.status}`);
    },
  );
}

async function signedStorageURL(
  objectPath: string,
  renderVariant: NonNullable<PlacePhotoInput["renderVariant"]>,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<string | null> {
  try {
    const body = await fetchWithTimeout(
      `${supabase.url}/storage/v1/object/sign/${cacheBucket}/${
        encodeStoragePath(objectPath)
      }`,
      {
        method: "POST",
        headers: {
          ...serviceHeaders(supabase),
          "Content-Type": "application/json",
        },
        body: JSON.stringify(signedURLRequestBody(renderVariant)),
      },
      6_000,
      dependencies,
      async (response) => {
        if (!response.ok) throw new Error(`cache_sign_status_${response.status}`);
        return await response.json() as { signedURL?: string; signedUrl?: string };
      },
    );
    const signedURL = cleanString(body.signedURL) ??
      cleanString(body.signedUrl);
    if (!signedURL) throw new Error("cache_sign_missing_url");
    // Storage returns service-relative paths for both originals and image
    // transforms. Resolving /render/image directly against the project origin
    // drops /storage/v1 and creates a manifest whose image always 404s.
    const normalizedURL = signedURL.startsWith("/object/") || signedURL.startsWith("/render/image/")
      ? `/storage/v1${signedURL}`
      : signedURL;
    return new URL(normalizedURL, `${supabase.url}/`).toString();
  } catch (error) {
    console.warn(
      "place_photo_cache_sign_failed",
      error instanceof Error ? error.message : "unknown_error",
    );
    return null;
  }
}

function signedURLRequestBody(
  renderVariant: NonNullable<PlacePhotoInput["renderVariant"]>,
): Record<string, unknown> {
  const expiresIn = signedURLLifetimeSeconds;
  if (renderVariant === "fullscreen") return { expiresIn };
  const dimensions: Record<
    Exclude<NonNullable<PlacePhotoInput["renderVariant"]>, "fullscreen">,
    number
  > = {
    list_thumbnail: 512,
    feed: 1_440,
    card: 1_440,
    profile: 1_800,
  };
  const qualities: Record<
    Exclude<NonNullable<PlacePhotoInput["renderVariant"]>, "fullscreen">,
    number
  > = {
    list_thumbnail: 84,
    feed: 90,
    card: 90,
    profile: 92,
  };
  return {
    expiresIn,
    transform: {
      width: dimensions[renderVariant],
      height: dimensions[renderVariant],
      resize: "contain",
      quality: qualities[renderVariant],
    },
  };
}

async function mapWithConcurrency<Input, Output>(
  inputs: Input[],
  concurrency: number,
  operation: (input: Input) => Promise<Output>,
): Promise<Output[]> {
  const results = new Array<Output>(inputs.length);
  let nextIndex = 0;
  const worker = async () => {
    while (true) {
      const index = nextIndex;
      nextIndex += 1;
      if (index >= inputs.length) return;
      results[index] = await operation(inputs[index]);
    }
  };
  await Promise.all(
    Array.from(
      { length: Math.min(Math.max(1, concurrency), inputs.length) },
      worker,
    ),
  );
  return results;
}

async function fetchJSON<Value>(
  url: string,
  init: RequestInit,
  dependencies: PlacePhotoDependencies,
): Promise<Value> {
  return await fetchWithTimeout(url, init, 6_000, dependencies, async (response) => {
    if (!response.ok) throw new Error(`google_places_status_${response.status}`);
    return await response.json() as Value;
  });
}

export async function fetchWithTimeout<Value>(
  url: string | URL,
  init: RequestInit,
  timeoutMilliseconds: number,
  dependencies: PlacePhotoDependencies,
  consume: (response: Response) => Promise<Value>,
): Promise<Value> {
  const controller = new AbortController();
  let timeout: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<never>((_, reject) => {
    timeout = setTimeout(() => {
      controller.abort();
      reject(new Error("network_timeout"));
    }, timeoutMilliseconds);
  });
  try {
    // Keep the deadline active through JSON/image body consumption, not just
    // response headers. An upstream stall must release the caller's slot.
    return await Promise.race([
      (async () => consume(await dependencies.fetch(url, {
        ...init,
        signal: controller.signal,
      })))(),
      deadline,
    ]);
  } finally {
    clearTimeout(timeout);
  }
}

async function hasValidSupabaseSession(
  authorization: string,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<boolean> {
  try {
    return await fetchWithTimeout(
      `${supabase.url}/rest/v1/rpc/current_profile`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: supabase.publishableKey,
          Authorization: authorization,
        },
        body: "{}",
      },
      6_000,
      dependencies,
      async (response) => {
        await response.body?.cancel();
        return response.ok;
      },
    );
  } catch {
    return false;
  }
}

async function placePhotoCacheKey(input: PlacePhotoInput): Promise<string> {
  const normalizedProvider = normalize(input.sourceProvider ?? "");
  const normalizedProviderID = normalize(input.sourceProviderPlaceID ?? "");
  const identity =
    isGoogleProvider(input.sourceProvider) && normalizedProviderID
      ? `google:${normalizedProviderID}`
      : [
        normalizedProvider,
        normalizedProviderID,
        normalize(input.name),
        normalize(input.address ?? ""),
        input.latitude === null ? "" : input.latitude.toFixed(5),
        input.longitude === null ? "" : input.longitude.toFixed(5),
      ].join("|");
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(identity),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function placePayload(place: GooglePlace): PlacePhotoPayload {
  return {
    provider: "google_places",
    provider_place_id: place.id ?? "",
    provider_primary_type: cleanString(place.primaryType),
    provider_types: cleanStrings(place.types),
    provider_rating: finiteNumber(place.rating),
    provider_user_rating_count: finiteInteger(place.userRatingCount),
    provider_open_now: place.currentOpeningHours?.openNow ?? null,
    provider_next_open_time: cleanString(
      place.currentOpeningHours?.nextOpenTime,
    ),
    provider_next_close_time: cleanString(
      place.currentOpeningHours?.nextCloseTime,
    ),
    provider_utc_offset_minutes: finiteInteger(place.utcOffsetMinutes),
    photo_url: "",
    width: null,
    height: null,
    author_name: null,
    author_profile_url: null,
    author_avatar_url: null,
    source_photo_url: null,
    flag_content_url: null,
  };
}

function supabaseConfiguration(
  dependencies: PlacePhotoDependencies,
): SupabaseConfiguration | null {
  const url = cleanString(dependencies.env("WANDER_SUPABASE_URL")) ??
    cleanString(dependencies.env("SUPABASE_URL"));
  const publishableKey =
    cleanString(dependencies.env("WANDER_SUPABASE_ANON_KEY")) ??
      cleanString(dependencies.env("SUPABASE_ANON_KEY"));
  if (!url || !publishableKey) return null;
  return {
    url: url.replace(/\/$/, ""),
    publishableKey,
    serviceRoleKey: supabaseServiceRoleKey(dependencies),
  };
}

function supabaseServiceRoleKey(
  dependencies: PlacePhotoDependencies,
): string | null {
  const direct =
    cleanString(dependencies.env("WANDER_SUPABASE_SERVICE_ROLE_KEY")) ??
      cleanString(dependencies.env("SUPABASE_SERVICE_ROLE_KEY"));
  if (direct) return direct;
  const secretKeys = cleanString(dependencies.env("SUPABASE_SECRET_KEYS"));
  if (!secretKeys) return null;
  try {
    const parsed = JSON.parse(secretKeys) as Record<string, unknown>;
    return cleanString(parsed.default) ??
      Object.values(parsed).map(cleanString).find((value) => value !== null) ??
      null;
  } catch {
    return null;
  }
}

function serviceHeaders(
  supabase: SupabaseConfiguration,
): Record<string, string> {
  if (!supabase.serviceRoleKey) throw new Error("missing_service_role_key");
  return {
    apikey: supabase.serviceRoleKey,
    Authorization: `Bearer ${supabase.serviceRoleKey}`,
  };
}

function googlePlacesAPIKey(
  dependencies: PlacePhotoDependencies,
): string | null {
  return cleanString(dependencies.env("WANDER_GOOGLE_PLACES_API_KEY")) ??
    cleanString(dependencies.env("GOOGLE_PLACES_API_KEY"));
}

function googleHeaders(
  apiKey: string,
  fieldMask: string,
): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "X-Goog-Api-Key": apiKey,
    "X-Goog-FieldMask": fieldMask,
  };
}

async function readBody(request: Request): Promise<Record<string, unknown>> {
  const text = await request.text();
  if (!text.trim()) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function placePhotoInput(
  body: Record<string, unknown>,
): PlacePhotoInput | null {
  const name = cleanString(body.name);
  if (!name) return null;
  return {
    name: name.slice(0, 180),
    address: cleanString(body.address)?.slice(0, 300) ?? null,
    latitude: coordinate(body.latitude, -90, 90),
    longitude: coordinate(body.longitude, -180, 180),
    sourceProvider: cleanString(body.source_provider)?.slice(0, 80) ?? null,
    sourceProviderPlaceID:
      cleanString(body.source_provider_place_id)?.slice(0, 300) ?? null,
    requiresPhoto: body.requires_photo !== false,
    renderVariant: renderVariant(body.render_variant),
  };
}

function renderVariant(
  value: unknown,
): NonNullable<PlacePhotoInput["renderVariant"]> {
  switch (value) {
    case "list_thumbnail":
    case "feed":
    case "card":
    case "profile":
    case "fullscreen":
      return value;
    default:
      return "profile";
  }
}

function jsonResponse(body: Record<string, unknown>, status: number): Response {
  return Response.json(body, { status, headers: noStoreHeaders });
}

function coordinate(
  value: unknown,
  minimum: number,
  maximum: number,
): number | null {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) && number >= minimum && number <= maximum
    ? number
    : null;
}

function finiteInteger(value: unknown): number | null {
  if (value === null || typeof value === "undefined" || value === "") {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number) : null;
}

function finiteNumber(value: unknown): number | null {
  if (value === null || typeof value === "undefined" || value === "") {
    return null;
  }
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function cleanString(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed || null;
}

function cleanStrings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map(cleanString).filter((item): item is string => item !== null)
    .slice(0, 32);
}

function absoluteGoogleURL(value: unknown): string | null {
  const string = cleanString(value);
  if (!string) return null;
  if (string.startsWith("//")) return `https:${string}`;
  return string;
}

function normalize(value: string): string {
  return value
    .toLocaleLowerCase("en-US")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function encodeStoragePath(path: string): string {
  return path.split("/").map(encodeURIComponent).join("/");
}
