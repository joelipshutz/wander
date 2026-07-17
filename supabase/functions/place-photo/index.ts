import "@supabase/functions-js/edge-runtime.d.ts";

import {
  type GooglePlace,
  isGoogleProvider,
  type PlacePhotoInput,
  representativePhoto,
  selectGooglePlace,
  shouldUseGooglePlaces,
} from "./google-places.ts";

const googlePlacesBaseURL = "https://places.googleapis.com/v1";
const noStoreHeaders = { "Cache-Control": "private, no-store, max-age=0" };

Deno.serve(async (request) => {
  try {
    return await handleRequest(request);
  } catch (error) {
    console.error("place_photo_error", error instanceof Error ? error.message : "unknown_error");
    return Response.json({ error: "internal_error" }, { status: 500, headers: noStoreHeaders });
  }
});

async function handleRequest(request: Request): Promise<Response> {
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405, headers: noStoreHeaders });
  }
  const authorization = request.headers.get("authorization");
  if (!authorization) {
    return Response.json({ error: "missing_authorization" }, { status: 401, headers: noStoreHeaders });
  }
  if (!await hasValidSupabaseSession(authorization)) {
    return Response.json({ error: "invalid_authorization" }, { status: 401, headers: noStoreHeaders });
  }

  const input = placePhotoInput(await readBody(request));
  if (!input) {
    return Response.json({ error: "invalid_place" }, { status: 400, headers: noStoreHeaders });
  }
  if (!shouldUseGooglePlaces(input)) {
    return Response.json({ error: "photo_not_found" }, { status: 404, headers: noStoreHeaders });
  }
  if (!await consumePlacePhotoQuota(authorization)) {
    return Response.json({ error: "rate_limited" }, { status: 429, headers: noStoreHeaders });
  }

  const apiKey = googlePlacesAPIKey();
  if (!apiKey) {
    return Response.json({ error: "provider_unavailable" }, { status: 503, headers: noStoreHeaders });
  }

  const place = await resolvePlace(input, apiKey);
  const photo = place ? representativePhoto(place) : null;
  if (!place?.id || !photo?.name) {
    return Response.json({ error: "photo_not_found" }, { status: 404, headers: noStoreHeaders });
  }

  const media = await fetchJSON<{ photoUri?: string }>(
    `${googlePlacesBaseURL}/${photo.name}/media?maxWidthPx=1600&maxHeightPx=1200&skipHttpRedirect=true&key=${encodeURIComponent(apiKey)}`,
    { method: "GET" },
  );
  if (!media.photoUri) {
    throw new Error("google_photo_missing_uri");
  }

  const author = photo.authorAttributions?.[0];
  const sourcePhotoURL = absoluteGoogleURL(photo.googleMapsUri);
  if (!sourcePhotoURL) {
    return Response.json({ error: "photo_attribution_unavailable" }, { status: 404, headers: noStoreHeaders });
  }
  return Response.json({
    provider: "google_places",
    provider_place_id: place.id,
    provider_primary_type: cleanString(place.primaryType),
    provider_types: cleanStrings(place.types),
    photo_url: media.photoUri,
    width: finiteInteger(photo.widthPx),
    height: finiteInteger(photo.heightPx),
    author_name: cleanString(author?.displayName),
    author_profile_url: absoluteGoogleURL(author?.uri),
    author_avatar_url: absoluteGoogleURL(author?.photoUri),
    source_photo_url: sourcePhotoURL,
    flag_content_url: absoluteGoogleURL(photo.flagContentUri),
  }, { headers: noStoreHeaders });
}

async function resolvePlace(input: PlacePhotoInput, apiKey: string): Promise<GooglePlace | null> {
  if (isGoogleProvider(input.sourceProvider) && input.sourceProviderPlaceID) {
    try {
      const directPlace = await fetchJSON<GooglePlace>(
        `${googlePlacesBaseURL}/places/${encodeURIComponent(input.sourceProviderPlaceID)}`,
        {
          method: "GET",
          headers: googleHeaders(apiKey, "id,displayName,formattedAddress,location,primaryType,types,photos"),
        },
      );
      if (representativePhoto(directPlace)) return directPlace;
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
      headers: googleHeaders(
        apiKey,
        "places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.types,places.photos",
      ),
      body: JSON.stringify(searchBody),
    },
  );
  return selectGooglePlace(search.places ?? [], input);
}

async function fetchJSON<Value>(url: string, init: RequestInit): Promise<Value> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 6_000);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    if (!response.ok) throw new Error(`google_places_status_${response.status}`);
    return await response.json() as Value;
  } finally {
    clearTimeout(timeout);
  }
}

function googleHeaders(apiKey: string, fieldMask: string): Record<string, string> {
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

function placePhotoInput(body: Record<string, unknown>): PlacePhotoInput | null {
  const name = cleanString(body.name);
  if (!name) return null;
  return {
    name: name.slice(0, 180),
    address: cleanString(body.address)?.slice(0, 300) ?? null,
    latitude: coordinate(body.latitude, -90, 90),
    longitude: coordinate(body.longitude, -180, 180),
    sourceProvider: cleanString(body.source_provider)?.slice(0, 80) ?? null,
    sourceProviderPlaceID: cleanString(body.source_provider_place_id)?.slice(0, 300) ?? null,
  };
}

function googlePlacesAPIKey(): string | null {
  return cleanString(Deno.env.get("WANDER_GOOGLE_PLACES_API_KEY")) ??
    cleanString(Deno.env.get("GOOGLE_PLACES_API_KEY"));
}

async function hasValidSupabaseSession(authorization: string): Promise<boolean> {
  const supabaseURL = cleanString(Deno.env.get("SUPABASE_URL"));
  const publishableKey = cleanString(Deno.env.get("SUPABASE_ANON_KEY"));
  if (!supabaseURL || !publishableKey) return false;

  try {
    const response = await fetch(`${supabaseURL}/rest/v1/rpc/current_profile`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: publishableKey,
        Authorization: authorization,
      },
      body: "{}",
    });
    return response.ok;
  } catch {
    return false;
  }
}

async function consumePlacePhotoQuota(authorization: string): Promise<boolean> {
  const supabaseURL = cleanString(Deno.env.get("SUPABASE_URL"));
  const publishableKey = cleanString(Deno.env.get("SUPABASE_ANON_KEY"));
  if (!supabaseURL || !publishableKey) return false;

  try {
    const response = await fetch(`${supabaseURL}/rest/v1/rpc/consume_place_photo_quota`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: publishableKey,
        Authorization: authorization,
      },
      body: "{}",
    });
    if (!response.ok) return false;
    return await response.json() === true;
  } catch {
    return false;
  }
}

function coordinate(value: unknown, minimum: number, maximum: number): number | null {
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) && number >= minimum && number <= maximum ? number : null;
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
  return value
    .map(cleanString)
    .filter((item): item is string => item !== null)
    .slice(0, 32);
}

function absoluteGoogleURL(value: unknown): string | null {
  const string = cleanString(value);
  if (!string) return null;
  if (string.startsWith("//")) return `https:${string}`;
  return string;
}
