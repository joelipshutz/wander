import { handleRequest, type PlacePhotoDependencies } from "./handler.ts";

const fixedNow = new Date("2026-08-14T05:30:00.000Z");

Deno.test("place-photo stores a provider image once and reuses the private server cache", async () => {
  const calls: Array<{ url: string; method: string }> = [];
  let cachedRow: Record<string, unknown> | null = null;
  let googleSearchCount = 0;
  let googleMediaCount = 0;
  let googleImageCount = 0;
  let storageUploadCount = 0;
  let storageCacheControl: string | null = null;
  let signedURLExpirySeconds: number | null = null;
  let signedTransform: Record<string, unknown> | null = null;

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
            rating: 4.7,
            userRatingCount: 138,
            currentOpeningHours: {
              openNow: false,
              nextOpenTime: "2026-08-14T15:00:00Z",
            },
            utcOffsetMinutes: -420,
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
          (JSON.parse(String(init?.body)) as { expiresIn: number }).expiresIn;
        signedTransform = (JSON.parse(String(init?.body)) as {
          transform?: Record<string, unknown>;
        }).transform ?? null;
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
  assertEquals(firstPayload.provider_rating, 4.7);
  assertEquals(firstPayload.provider_user_rating_count, 138);
  assertEquals(firstPayload.provider_open_now, false);
  assertEquals(firstPayload.provider_next_open_time, "2026-08-14T15:00:00Z");
  assertEquals(firstPayload.provider_utc_offset_minutes, -420);
  assert(cachedRow !== null, "cache metadata was not written");
  const writtenRow = cachedRow as unknown as Record<string, unknown>;
  assertEquals(writtenRow.content_type, "image/jpeg");
  assertEquals(writtenRow.byte_size, 4);
  assertEquals(writtenRow.provider_rating, 4.7);
  assertEquals(writtenRow.provider_user_rating_count, 138);
  assertEquals(writtenRow.provider_open_now, false);
  assertEquals("expires_at" in writtenRow, false);
  assertEquals(storageCacheControl, "86400");
  assertEquals(signedURLExpirySeconds, 86_400);
  assert(signedTransform !== null, "signed profile transform was not requested");
  const profileTransform = signedTransform as unknown as Record<string, unknown>;
  assertEquals(profileTransform.width, 1_800);
  assertEquals(profileTransform.height, 1_800);
  assertEquals(profileTransform.resize, "contain");
  assertEquals(profileTransform.quality, 92);
  assert(
    calls.some(({ url }) => url.includes("maxWidthPx=3200&maxHeightPx=3200")),
    "provider cache stores a fullscreen-quality source",
  );

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

Deno.test("place-photo batches cached list manifests behind one auth and cache read", async () => {
  let authCount = 0;
  let cacheReadCount = 0;
  let signCount = 0;
  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow,
    env: (name) =>
      ({
        SUPABASE_URL: "https://example.supabase.co",
        SUPABASE_ANON_KEY: "publishable-key",
        SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
      })[name],
    // deno-lint-ignore require-await
    fetch: async (input, init) => {
      const url = typeof input === "string" ? input : input.toString();
      if (url.endsWith("/rest/v1/rpc/current_profile")) {
        authCount += 1;
        return Response.json({ id: "profile" });
      }
      if (url.includes("/rest/v1/google_place_photo_cache")) {
        cacheReadCount += 1;
        const filter = new URL(url).searchParams.get("cache_key") ?? "";
        const keys = filter.slice("in.(".length, -1).split(",");
        return Response.json(keys.map((key, index) => ({
          cache_key: key,
          object_path: `${key.slice(0, 2)}/${key}.img`,
          provider_place_id: `google-${index + 1}`,
          provider_primary_type: "restaurant",
          provider_types: ["restaurant"],
          provider_rating: 4.5,
          provider_user_rating_count: 100,
          provider_open_now: true,
          provider_next_open_time: null,
          provider_next_close_time: null,
          provider_utc_offset_minutes: -420,
          width: 3_200,
          height: 2_400,
          content_type: "image/jpeg",
          byte_size: 500_000,
          author_name: null,
          author_profile_url: null,
          author_avatar_url: null,
          source_photo_url: "https://www.google.com/maps/place/example",
          flag_content_url: null,
          fetched_at: fixedNow.toISOString(),
          last_accessed_at: fixedNow.toISOString(),
        })));
      }
      if (url.includes("/storage/v1/object/sign/google-place-photo-cache/")) {
        signCount += 1;
        const body = JSON.parse(String(init?.body)) as {
          transform?: { width?: number; height?: number; quality?: number };
        };
        assertEquals(body.transform?.width, 512);
        assertEquals(body.transform?.height, 512);
        assertEquals(body.transform?.quality, 84);
        return Response.json({
          signedURL:
            "/storage/v1/render/image/sign/google-place-photo-cache/cache.img?token=test",
        });
      }
      throw new Error(`unexpected request ${init?.method ?? "GET"} ${url}`);
    },
  };

  const request = new Request(
    "https://example.supabase.co/functions/v1/place-photo",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer user-token",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        requests: [
          {
            name: "One",
            source_provider: "google_places",
            source_provider_place_id: "google-1",
            requires_photo: true,
            render_variant: "list_thumbnail",
          },
          {
            name: "Two",
            source_provider: "google_places",
            source_provider_place_id: "google-2",
            requires_photo: true,
            render_variant: "list_thumbnail",
          },
        ],
      }),
    },
  );

  const response = await handleRequest(request, dependencies);
  assertEquals(response.status, 200);
  const payload = await response.json() as {
    results: Array<{ index: number; photo: PlacePhotoRecord | null }>;
  };
  assertEquals(payload.results.length, 2);
  assertEquals(payload.results[0].photo?.provider, "google_places");
  assertEquals(payload.results[1].photo?.provider, "google_places");
  assertEquals(authCount, 1);
  assertEquals(cacheReadCount, 1);
  assertEquals(signCount, 2);
});

type PlacePhotoRecord = {
  provider: string;
};

Deno.test("place-photo reuses legacy cache rows without applying their former expiry", async () => {
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
        url.includes("/storage/v1/object/sign/google-place-photo-cache/") &&
        method === "POST"
      ) {
        return Response.json({
          signedURL:
            "/storage/v1/object/sign/google-place-photo-cache/aa/cache.img?token=test",
        });
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

  const response = await handleRequest(photoRequest(), dependencies);
  assertEquals(response.status, 200);
  assertEquals(searchCount, 1);
  assertEquals(deletedStorageObject, false);
  assertEquals(deletedMetadata, false);
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
