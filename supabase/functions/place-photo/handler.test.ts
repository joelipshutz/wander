import { handleRequest, type PlacePhotoDependencies } from "./handler.ts";

const fixedNow = new Date("2026-08-31T05:30:00.000Z");

Deno.test("place-photo stores a provider image once and reuses the private server cache", async () => {
  const calls: Array<{ url: string; method: string }> = [];
  let cachedRow: Record<string, unknown> | null = null;
  let googleSearchCount = 0;
  let googleMediaCount = 0;
  let googleImageCount = 0;
  let storageUploadCount = 0;
  let storageCacheControl: string | null = null;
  let signedURLExpirySeconds: number | null = null;

  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow,
    env: (name) =>
      ({
        SUPABASE_URL: "https://example.supabase.co",
        SUPABASE_ANON_KEY: "publishable-key",
        SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
        WANDER_GOOGLE_PLACES_API_KEY: "google-key",
      })[name],
    // The mock preserves the native fetch Promise signature without I/O.
    // deno-lint-ignore require-await
    fetch: async (input, init) => {
      const url = typeof input === "string" ? input : input.toString();
      const method = init?.method ?? "GET";
      calls.push({ url, method });

      if (url.endsWith("/rest/v1/rpc/current_profile")) {
        return Response.json({ id: "profile" });
      }
      if (url.includes("/rest/v1/google_place_photo_cache")) {
        if (method === "GET") {
          return Response.json(cachedRow ? [cachedRow] : []);
        }
        if (method === "POST") {
          cachedRow = JSON.parse(String(init?.body)) as Record<string, unknown>;
          return new Response(null, { status: 201 });
        }
      }
      if (url === "https://places.googleapis.com/v1/places:searchText") {
        googleSearchCount += 1;
        return Response.json({
          places: [{
            id: "google-woodcat",
            displayName: { text: "Woodcat Coffee" },
            formattedAddress: "1532 Sunset Blvd, Los Angeles, CA",
            location: { latitude: 34.0777, longitude: -118.2588 },
            primaryType: "coffee_shop",
            types: ["coffee_shop", "cafe"],
            photos: [{
              name: "places/google-woodcat/photos/storefront",
              widthPx: 1_600,
              heightPx: 1_200,
              googleMapsUri:
                "https://www.google.com/maps/place/?q=place_id:google-woodcat",
              authorAttributions: [{
                displayName: "Photo Author",
                uri: "https://www.google.com/maps/contrib/author",
              }],
            }],
          }],
        });
      }
      if (url.includes("/places/google-woodcat/photos/storefront/media?")) {
        googleMediaCount += 1;
        return Response.json({
          photoUri: "https://lh3.googleusercontent.com/place-photo",
        });
      }
      if (url === "https://lh3.googleusercontent.com/place-photo") {
        googleImageCount += 1;
        return new Response(new Uint8Array([0xff, 0xd8, 0xff, 0xd9]), {
          headers: { "Content-Type": "image/jpeg", "Content-Length": "4" },
        });
      }
      if (url.includes("/storage/v1/object/google-place-photo-cache/")) {
        storageUploadCount += 1;
        storageCacheControl = new Headers(init?.headers).get("Cache-Control");
        return Response.json({ Key: "cached" });
      }
      if (url.includes("/storage/v1/object/sign/google-place-photo-cache/")) {
        signedURLExpirySeconds =
          (JSON.parse(String(init?.body)) as { expiresIn: number })
            .expiresIn;
        return Response.json({
          signedURL:
            "/storage/v1/object/sign/google-place-photo-cache/cache.img?token=test",
        });
      }
      throw new Error(`unexpected request ${method} ${url}`);
    },
  };

  const first = await handleRequest(photoRequest(), dependencies);
  assertEquals(first.status, 200);
  const firstPayload = await first.json() as Record<string, unknown>;
  assertEquals(firstPayload.provider, "google_places");
  assertEquals(firstPayload.provider_place_id, "google-woodcat");
  assertStartsWith(
    String(firstPayload.photo_url),
    "https://example.supabase.co/storage/v1/object/sign/",
  );
  assertEquals(firstPayload.author_name, "Photo Author");
  assert(cachedRow !== null, "cache metadata was not written");
  const writtenRow = cachedRow as unknown as Record<string, unknown>;
  assertEquals(writtenRow.content_type, "image/jpeg");
  assertEquals(writtenRow.byte_size, 4);
  assertEquals(writtenRow.expires_at, "2027-02-28T05:30:00.000Z");
  assertEquals(storageCacheControl, "86400");
  assertEquals(signedURLExpirySeconds, 86_400);

  const second = await handleRequest(photoRequest(), dependencies);
  assertEquals(second.status, 200);
  const secondPayload = await second.json() as Record<string, unknown>;
  assertStartsWith(
    String(secondPayload.photo_url),
    "https://example.supabase.co/storage/v1/object/sign/",
  );
  assertEquals(googleSearchCount, 1);
  assertEquals(googleMediaCount, 1);
  assertEquals(googleImageCount, 1);
  assertEquals(storageUploadCount, 1);
  assert(
    calls.every(({ url }) => !url.includes("consume_place_photo_quota")),
    "the removed quota RPC was called",
  );
});

Deno.test("place-photo deletes an expired cached image before refreshing it", async () => {
  let deletedStorageObject = false;
  let deletedMetadata = false;
  let searchCount = 0;
  const expiredRow = {
    cache_key: "a".repeat(64),
    object_path: `aa/${"a".repeat(64)}.img`,
    provider_place_id: "google-old",
    provider_primary_type: "restaurant",
    provider_types: ["restaurant"],
    width: 800,
    height: 600,
    content_type: "image/jpeg",
    byte_size: 4,
    author_name: null,
    author_profile_url: null,
    author_avatar_url: null,
    source_photo_url: "https://www.google.com/maps/place/old",
    flag_content_url: null,
    fetched_at: "2026-07-01T00:00:00.000Z",
    expires_at: "2026-07-31T00:00:00.000Z",
    last_accessed_at: "2026-07-01T00:00:00.000Z",
  };

  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow,
    env: (name) =>
      ({
        SUPABASE_URL: "https://example.supabase.co",
        SUPABASE_ANON_KEY: "publishable-key",
        SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
        WANDER_GOOGLE_PLACES_API_KEY: "google-key",
      })[name],
    // The mock preserves the native fetch Promise signature without I/O.
    // deno-lint-ignore require-await
    fetch: async (input, init) => {
      const url = typeof input === "string" ? input : input.toString();
      const method = init?.method ?? "GET";
      if (url.endsWith("/rest/v1/rpc/current_profile")) {
        return Response.json({ id: "profile" });
      }
      if (url.includes("/rest/v1/google_place_photo_cache")) {
        if (method === "GET") return Response.json([expiredRow]);
        if (method === "DELETE") {
          deletedMetadata = true;
          return new Response(null, { status: 204 });
        }
        if (method === "POST") return new Response(null, { status: 201 });
      }
      if (
        url.includes("/storage/v1/object/google-place-photo-cache/") &&
        method === "DELETE"
      ) {
        deletedStorageObject = true;
        return new Response(null, { status: 200 });
      }
      if (url === "https://places.googleapis.com/v1/places:searchText") {
        searchCount += 1;
        return Response.json({
          places: [{
            id: "google-woodcat",
            displayName: { text: "Woodcat Coffee" },
            formattedAddress: "1532 Sunset Blvd, Los Angeles, CA",
            location: { latitude: 34.0777, longitude: -118.2588 },
            primaryType: "coffee_shop",
            types: ["coffee_shop"],
          }],
        });
      }
      throw new Error(`unexpected request ${method} ${url}`);
    },
  };

  const response = await handleRequest(metadataRequest(), dependencies);
  assertEquals(response.status, 200);
  assertEquals(searchCount, 1);
  assert(deletedStorageObject, "expired Storage object was not deleted");
  assert(deletedMetadata, "expired cache metadata was not deleted");
});

function photoRequest(): Request {
  return new Request("https://example.supabase.co/functions/v1/place-photo", {
    method: "POST",
    headers: {
      Authorization: "Bearer user-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      name: "Woodcat Coffee",
      address: "1532 Sunset Blvd, Los Angeles, CA",
      latitude: 34.0777,
      longitude: -118.2588,
      source_provider: "mapkit",
      source_provider_place_id: "mapkit-woodcat",
      requires_photo: true,
    }),
  });
}

function metadataRequest(): Request {
  const request = photoRequest();
  return new Request(request.url, {
    method: request.method,
    headers: request.headers,
    body: JSON.stringify({
      name: "Woodcat Coffee",
      address: "1532 Sunset Blvd, Los Angeles, CA",
      latitude: 34.0777,
      longitude: -118.2588,
      source_provider: "mapkit",
      source_provider_place_id: "mapkit-woodcat",
      requires_photo: false,
    }),
  });
}

function assert(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (actual !== expected) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

function assertStartsWith(actual: string, expectedPrefix: string): void {
  if (!actual.startsWith(expectedPrefix)) {
    throw new Error(`expected ${actual} to start with ${expectedPrefix}`);
  }
}
