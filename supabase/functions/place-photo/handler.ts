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
const maximumCachedImageBytes = 10 * 1_024 * 1_024;
const noStoreHeaders = { "Cache-Control": "private, no-store, max-age=0" };

export type PlacePhotoDependencies = {
  fetch: typeof fetch;
  env: (name: string) => string | undefined;
  now: () => Date;
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
  photo_url: string;
  width: number | null;
  height: number | null;
  author_name: string | null;
  author_profile_url: string | null;
  author_avatar_url: string | null;
  source_photo_url: string | null;
  flag_content_url: string | null;
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

  const input = placePhotoInput(await readBody(request));
  if (!input) {
    return jsonResponse({ error: "invalid_place" }, 400);
  }
  if (!shouldUseGooglePlaces(input)) {
    return jsonResponse({ error: "photo_not_found" }, 404);
  }

  const cacheKey = await placePhotoCacheKey(input);
  if (supabase.serviceRoleKey) {
    const cached = await readCachedPhoto(cacheKey, supabase, dependencies);
    if (cached) {
      const payload = await cachedPayload(
        cached,
        input,
        supabase,
        dependencies,
      );
      if (payload) {
        console.log("place_photo_cache_hit");
        return Response.json(payload, { headers: noStoreHeaders });
      }
    }
  }

  console.log("place_photo_cache_miss");
  const apiKey = googlePlacesAPIKey(dependencies);
  if (!apiKey) {
    return jsonResponse({ error: "provider_unavailable" }, 503);
  }

  const place = await resolvePlace(input, apiKey, dependencies);
  const photo = place ? representativePhoto(place) : null;
  if (!place?.id) {
    return jsonResponse({ error: "photo_not_found" }, 404);
  }

  const basePayload = placePayload(place);
  if (!input.requiresPhoto) {
    if (supabase.serviceRoleKey) {
      await writeCachedMetadata(cacheKey, basePayload, supabase, dependencies);
    }
    return Response.json(basePayload, { headers: noStoreHeaders });
  }
  if (!photo?.name) {
    return jsonResponse({ error: "photo_not_found" }, 404);
  }

  const media = await fetchJSON<{ photoUri?: string }>(
    `${googlePlacesBaseURL}/${photo.name}/media?maxWidthPx=1600&maxHeightPx=1200&skipHttpRedirect=true&key=${
      encodeURIComponent(apiKey)
    }`,
    { method: "GET" },
    dependencies,
  );
  if (!media.photoUri) {
    throw new Error("google_photo_missing_uri");
  }

  const author = photo.authorAttributions?.[0];
  const sourcePhotoURL = absoluteGoogleURL(photo.googleMapsUri);
  if (!sourcePhotoURL) {
    return jsonResponse({ error: "photo_attribution_unavailable" }, 404);
  }
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
      supabase,
      dependencies,
    );
    if (cachedPayload) {
      return Response.json(cachedPayload, { headers: noStoreHeaders });
    }
  }

  // Keep the app working if Storage is temporarily unavailable. The provider
  // URL is never persisted by the client and the next request retries caching.
  return Response.json(providerPayload, { headers: noStoreHeaders });
}

async function resolvePlace(
  input: PlacePhotoInput,
  apiKey: string,
  dependencies: PlacePhotoDependencies,
): Promise<GooglePlace | null> {
  const directFieldMask = input.requiresPhoto
    ? "id,displayName,formattedAddress,location,primaryType,types,photos"
    : "id,displayName,formattedAddress,location,primaryType,types";
  const searchFieldMask = input.requiresPhoto
    ? "places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.types,places.photos"
    : "places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.types";

  if (isGoogleProvider(input.sourceProvider) && input.sourceProviderPlaceID) {
    try {
      const directPlace = await fetchJSON<GooglePlace>(
        `${googlePlacesBaseURL}/places/${
          encodeURIComponent(input.sourceProviderPlaceID)
        }`,
        { method: "GET", headers: googleHeaders(apiKey, directFieldMask) },
        dependencies,
      );
      if (!input.requiresPhoto || representativePhoto(directPlace)) {
        return directPlace;
      }
    } catch (error) {
      console.warn(
        "place_photo_direct_lookup_failed",
        error instanceof Error ? error.message : "unknown_error",
      );
    }
  }

  const searchBody: Record<string, unknown> = {
    textQuery: [input.name, input.address].filter(Boolean).join(" "),
    pageSize: 5,
  };
  if (input.latitude !== null && input.longitude !== null) {
    searchBody.locationBias = {
      circle: {
        center: { latitude: input.latitude, longitude: input.longitude },
        radius: 1_000,
      },
    };
  }

  const search = await fetchJSON<{ places?: GooglePlace[] }>(
    `${googlePlacesBaseURL}/places:searchText`,
    {
      method: "POST",
      headers: googleHeaders(apiKey, searchFieldMask),
      body: JSON.stringify(searchBody),
    },
    dependencies,
  );
  return selectGooglePlace(search.places ?? [], input);
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
    const response = await dependencies.fetch(endpoint, {
      headers: serviceHeaders(supabase),
    });
    if (!response.ok) throw new Error(`cache_read_status_${response.status}`);
    const rows = await response.json() as CachedPhotoRow[];
    return rows[0] ?? null;
  } catch (error) {
    console.warn(
      "place_photo_cache_read_failed",
      error instanceof Error ? error.message : "unknown_error",
    );
    return null;
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
    photoURL =
      await signedStorageURL(row.object_path, supabase, dependencies) ?? "";
    if (!photoURL) return null;
  }
  return {
    provider: "google_places",
    provider_place_id: row.provider_place_id,
    provider_primary_type: row.provider_primary_type,
    provider_types: row.provider_types,
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
    const photoURL = await signedStorageURL(objectPath, supabase, dependencies);
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
    await upsertCacheRow(
      cacheRow(cacheKey, payload, dependencies.now()),
      supabase,
      dependencies,
    );
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

async function upsertCacheRow(
  row: CachedPhotoRow,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<void> {
  const endpoint = new URL(`${supabase.url}/rest/v1/google_place_photo_cache`);
  endpoint.searchParams.set("on_conflict", "cache_key");
  const response = await dependencies.fetch(endpoint, {
    method: "POST",
    headers: {
      ...serviceHeaders(supabase),
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates,return=minimal",
    },
    body: JSON.stringify(row),
  });
  if (!response.ok) throw new Error(`cache_write_status_${response.status}`);
}

async function downloadCacheableImage(
  url: string,
  dependencies: PlacePhotoDependencies,
): Promise<{ bytes: Uint8Array; contentType: string } | null> {
  const response = await fetchWithTimeout(
    url,
    {
      method: "GET",
      headers: { Accept: "image/jpeg,image/png,image/webp" },
    },
    10_000,
    dependencies,
  );
  if (!response.ok) {
    throw new Error(`google_photo_download_status_${response.status}`);
  }

  const contentLength = Number(response.headers.get("content-length"));
  if (
    Number.isFinite(contentLength) && contentLength > maximumCachedImageBytes
  ) {
    throw new Error("google_photo_too_large");
  }
  const contentType = response.headers.get("content-type")?.split(";", 1)[0]
    ?.trim().toLowerCase();
  if (
    !contentType ||
    !["image/jpeg", "image/png", "image/webp"].includes(contentType)
  ) {
    throw new Error("google_photo_unsupported_content_type");
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  if (!bytes.byteLength || bytes.byteLength > maximumCachedImageBytes) {
    throw new Error("google_photo_invalid_size");
  }
  return { bytes, contentType };
}

async function uploadCachedImage(
  objectPath: string,
  image: { bytes: Uint8Array; contentType: string },
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<void> {
  const response = await dependencies.fetch(
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
  );
  if (!response.ok) throw new Error(`cache_upload_status_${response.status}`);
}

async function signedStorageURL(
  objectPath: string,
  supabase: SupabaseConfiguration,
  dependencies: PlacePhotoDependencies,
): Promise<string | null> {
  try {
    const response = await dependencies.fetch(
      `${supabase.url}/storage/v1/object/sign/${cacheBucket}/${
        encodeStoragePath(objectPath)
      }`,
      {
        method: "POST",
        headers: {
          ...serviceHeaders(supabase),
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ expiresIn: signedURLLifetimeSeconds }),
      },
    );
    if (!response.ok) throw new Error(`cache_sign_status_${response.status}`);
    const body = await response.json() as {
      signedURL?: string;
      signedUrl?: string;
    };
    const signedURL = cleanString(body.signedURL) ??
      cleanString(body.signedUrl);
    if (!signedURL) throw new Error("cache_sign_missing_url");
    const normalizedURL = signedURL.startsWith("/object/")
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

async function fetchJSON<Value>(
  url: string,
  init: RequestInit,
  dependencies: PlacePhotoDependencies,
): Promise<Value> {
  const response = await fetchWithTimeout(url, init, 6_000, dependencies);
  if (!response.ok) throw new Error(`google_places_status_${response.status}`);
  return await response.json() as Value;
}

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMilliseconds: number,
  dependencies: PlacePhotoDependencies,
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds);
  try {
    return await dependencies.fetch(url, {
      ...init,
      signal: controller.signal,
    });
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
    const response = await dependencies.fetch(
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
    );
    return response.ok;
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
  };
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
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number) : null;
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
