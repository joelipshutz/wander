import { fetchWithTimeout, handleRequest, type PlacePhotoDependencies } from "./handler.ts";

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
            "/render/image/sign/google-place-photo-cache/cache.img?token=test",
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
    provider_place_id: "google-woodcat",
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


Deno.test("place-photo batch preserves ready metadata when another provider request throws", async () => {
  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow,
    env: (name) => ({
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_ANON_KEY: "publishable-key",
      WANDER_GOOGLE_PLACES_API_KEY: "google-key",
    })[name],
    // deno-lint-ignore require-await
    fetch: async (input, init) => {
      const url = input.toString();
      if (url.endsWith("/rest/v1/rpc/current_profile")) return Response.json({ id: "profile" });
      if (url.endsWith("/places/ready")) {
        return Response.json({ id: "ready", currentOpeningHours: { openNow: true } });
      }
      if (url.includes("places.googleapis.com")) throw new Error("synthetic_provider_timeout");
      throw new Error(`unexpected method ${init?.method}`);
    },
  };
  const response = await handleRequest(providerTestRequest({ requests: [
    { name: "Ready", source_provider: "google", source_provider_place_id: "ready", requires_photo: false },
    { name: "Unavailable", source_provider: "google", source_provider_place_id: "unavailable", requires_photo: false },
  ] }), dependencies);
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.results[0].photo.provider_open_now, true);
  assertEquals(body.results[0].photo.photo_url, "");
  assertEquals(body.results[1].photo, null);
  assertEquals(body.results[1].error, "provider_unavailable");
});

Deno.test("metadata-only hours neither require a photo nor erase a concurrent image cache write", async () => {
  let cacheWrite: Record<string, unknown> | null = null;
  let mediaRequests = 0;
  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow,
    env: (name) => ({
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_ANON_KEY: "publishable-key",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
      WANDER_GOOGLE_PLACES_API_KEY: "google-key",
    })[name],
    // deno-lint-ignore require-await
    fetch: async (input, init) => {
      const url = input.toString();
      if (url.endsWith("/rest/v1/rpc/current_profile")) return Response.json({ id: "profile" });
      if (url.includes("/rest/v1/google_place_photo_cache")) {
        if ((init?.method ?? "GET") === "GET") return Response.json([]);
        cacheWrite = JSON.parse(String(init?.body));
        return new Response(null, { status: 201 });
      }
      if (url.endsWith("/places/photo-less")) {
        return Response.json({ id: "photo-less", displayName: { text: "Photo-less Cafe" },
          currentOpeningHours: { openNow: false, nextOpenTime: "2026-08-14T15:00:00Z" }, utcOffsetMinutes: -420 });
      }
      mediaRequests += 1;
      throw new Error("metadata_must_not_request_image");
    },
  };
  const response = await handleRequest(providerTestRequest({
    name: "Photo-less Cafe", source_provider: "google", source_provider_place_id: "photo-less", requires_photo: false,
  }), dependencies);
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(body.provider_open_now, false);
  assertEquals(body.provider_next_open_time, "2026-08-14T15:00:00Z");
  assertEquals(body.photo_url, "");
  assertEquals(mediaRequests, 0);
  const written = cacheWrite as Record<string, unknown> | null;
  assert(written !== null, "metadata write missing");
  assertEquals(written.provider_open_now, false);
  // All non-null columns are supplied, including those with defaults. Omitted
  // image fields and the retired expires_at column are nullable on insertion.
  for (const field of ["cache_key", "provider_place_id", "provider_types", "fetched_at", "last_accessed_at"]) {
    assert(written[field] !== undefined && written[field] !== null, `required column ${field} missing`);
  }
  for (const field of ["object_path", "content_type", "byte_size", "source_photo_url", "width", "height"]) {
    assert(!(field in written), `metadata must preserve concurrent image field ${field}`);
  }
});

Deno.test("stale metadata refresh preserves a concurrent image write after its cache read", async () => {
  let refreshed = false;
  let imageRow: Record<string, unknown> = {};
  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow,
    env: (name) => ({
      SUPABASE_URL: "https://example.supabase.co", SUPABASE_ANON_KEY: "publishable-key",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-key", WANDER_GOOGLE_PLACES_API_KEY: "google-key",
    })[name],
    // deno-lint-ignore require-await
    fetch: async (input, init) => {
      const url = input.toString();
      if (url.endsWith("/rest/v1/rpc/current_profile")) return Response.json({ id: "profile" });
      if (url.includes("/rest/v1/google_place_photo_cache")) {
        if ((init?.method ?? "GET") === "GET") {
          const keys = (new URL(url).searchParams.get("cache_key") ?? "").slice(4, -1).split(",");
          return Response.json(keys.map((cache_key) => ({
            cache_key, provider_place_id: "stale", object_path: null,
            provider_types: [], provider_open_now: true, fetched_at: "2026-08-13T01:00:00Z",
            content_type: null, byte_size: null, source_photo_url: null,
          })));
        }
        const body = JSON.parse(String(init?.body));
        for (const field of ["object_path", "content_type", "byte_size", "source_photo_url", "width", "height"]) {
          assert(!(field in body), `stale metadata must not overwrite concurrent image field ${field}`);
        }
        imageRow = { ...imageRow, ...body };
        refreshed = true;
        return new Response(null, { status: 201 });
      }
      if (url.endsWith("/places/stale")) {
        // The image request commits after metadata read the old metadata-only row.
        imageRow = { object_path: "new.img", content_type: "image/jpeg", byte_size: 100,
          source_photo_url: "https://www.google.com/maps/example", width: 640, height: 480 };
        return Response.json({ id: "stale", currentOpeningHours: { openNow: false } });
      }
      throw new Error("unexpected request");
    },
  };
  const response = await handleRequest(providerTestRequest({ requests: [
    { name: "Stale", source_provider: "google", source_provider_place_id: "stale", requires_photo: false },
  ] }), dependencies);
  const body = await response.json();
  assertEquals(body.results[0].photo.provider_open_now, false);
  assertEquals(refreshed, true);
  assertEquals(imageRow.object_path, "new.img");
  assertEquals(imageRow.byte_size, 100);
  assertEquals(imageRow.width, 640);
  assertEquals(imageRow.provider_open_now, false);
});

Deno.test("network deadline covers stalled response bodies and aborts upstream work", async () => {
  let signal: AbortSignal | null = null;
  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow, env: () => undefined,
    // deno-lint-ignore require-await
    fetch: async (_input, init) => {
      signal = init?.signal ?? null;
      return new Response(new ReadableStream({
        start(controller) {
          init?.signal?.addEventListener("abort", () => controller.error(new Error("aborted")), { once: true });
        },
      }));
    },
  };
  let timedOut = false;
  try {
    await fetchWithTimeout("https://example.com/slow-body", {}, 10, dependencies,
      async (response) => await response.arrayBuffer());
  } catch { timedOut = true; }
  assertEquals(timedOut, true);
  assertEquals((signal as AbortSignal | null)?.aborted, true);
});

Deno.test("network deadline bounds a request that never returns headers", async () => {
  let signal: AbortSignal | null = null;
  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow, env: () => undefined,
    fetch: (_input, init) => {
      signal = init?.signal ?? null;
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
      });
    },
  };
  let timedOut = false;
  try {
    await fetchWithTimeout("https://example.com/slow-headers", {}, 10, dependencies,
      async (response) => await response.json());
  } catch { timedOut = true; }
  assertEquals(timedOut, true);
  assertEquals((signal as AbortSignal | null)?.aborted, true);
});

Deno.test("a later photo with its own source link remains available when the first lacks one", async () => {
  let mediaCalls = 0;
  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow,
    env: (name) => ({ SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_ANON_KEY: "publishable-key", WANDER_GOOGLE_PLACES_API_KEY: "google-key" })[name],
    // deno-lint-ignore require-await
    fetch: async (input) => {
      const url = input.toString();
      if (url.endsWith("/rest/v1/rpc/current_profile")) return Response.json({ id: "profile" });
      if (url.endsWith("/places/venue")) return Response.json({
        id: "venue", photos: [
          { name: "places/venue/photos/missing-source", widthPx: 1000, heightPx: 1000,
            authorAttributions: [{ displayName: "First Author" }] },
          { name: "places/venue/photos/available", widthPx: 1600, heightPx: 1200,
            googleMapsUri: "//www.google.com/maps/photo/available",
            flagContentUri: "https://www.google.com/maps/report/available",
            authorAttributions: [{ displayName: "Available Author",
              uri: "https://www.google.com/maps/contrib/available",
              photoUri: "https://lh3.googleusercontent.com/available-avatar" }] },
        ],
      });
      if (url.includes("/photos/available/media?")) {
        mediaCalls += 1;
        return Response.json({ photoUri: "https://lh3.googleusercontent.com/available" });
      }
      throw new Error("unexpected request");
    },
  };
  const response = await handleRequest(providerTestRequest({
    name: "Venue", source_provider: "google", source_provider_place_id: "venue", requires_photo: true,
  }), dependencies);
  const body = await response.json();
  assertEquals(response.status, 200);
  assertEquals(mediaCalls, 1);
  assertEquals(body.photo_url, "https://lh3.googleusercontent.com/available");
  assertEquals(body.source_photo_url, "https://www.google.com/maps/photo/available");
  assertEquals(body.author_name, "Available Author");
  assertEquals(body.author_profile_url, "https://www.google.com/maps/contrib/available");
  assertEquals(body.author_avatar_url, "https://lh3.googleusercontent.com/available-avatar");
  assertEquals(body.flag_content_url, "https://www.google.com/maps/report/available");
});

Deno.test("a place or gallery link does not substitute for every photo missing its own source", async () => {
  let mediaCalls = 0;
  const dependencies: PlacePhotoDependencies = {
    now: () => fixedNow,
    env: (name) => ({ SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_ANON_KEY: "publishable-key", WANDER_GOOGLE_PLACES_API_KEY: "google-key" })[name],
    // deno-lint-ignore require-await
    fetch: async (input) => {
      const url = input.toString();
      if (url.endsWith("/rest/v1/rpc/current_profile")) return Response.json({ id: "profile" });
      if (url.endsWith("/places/venue")) return Response.json({
        id: "venue", googleMapsUri: "https://www.google.com/maps/place/venue",
        googleMapsLinks: { photosUri: "https://www.google.com/maps/gallery/venue" },
        photos: [{ name: "places/venue/photos/no-source", widthPx: 1000, heightPx: 1000,
          authorAttributions: [{ displayName: "Photo Author" }] }],
      });
      if (url.includes("/media?")) mediaCalls += 1;
      throw new Error("unexpected request");
    },
  };
  const response = await handleRequest(providerTestRequest({
    name: "Venue", source_provider: "google", source_provider_place_id: "venue", requires_photo: true,
  }), dependencies);
  const body = await response.json();
  assertEquals(response.status, 404);
  assertEquals(body.error, "photo_attribution_unavailable");
  assertEquals(mediaCalls, 0);
});

Deno.test("signed image paths retain the Storage route for every delivery variant", async () => {
  for (const render_variant of ["list_thumbnail", "card", "feed", "profile", "fullscreen"]) {
    for (const prefix of ["service-relative", "gateway-relative", "absolute"]) {
      const route = render_variant === "fullscreen" ? "object" : "render/image";
      const path = `/${route}/sign/google-place-photo-cache/cached.img?token=synthetic`;
      const expectedURL = `https://example.supabase.co/storage/v1${path}`;
      const signedURL = prefix === "absolute" ? expectedURL
        : prefix === "gateway-relative" ? `/storage/v1${path}` : path;
      const dependencies: PlacePhotoDependencies = {
        now: () => fixedNow,
        env: (name) => ({ SUPABASE_URL: "https://example.supabase.co",
          SUPABASE_ANON_KEY: "publishable-key", SUPABASE_SERVICE_ROLE_KEY: "service-role-key" })[name],
        // deno-lint-ignore require-await
        fetch: async (input, init) => {
          const url = input.toString();
          if (url.endsWith("/rest/v1/rpc/current_profile")) return Response.json({ id: "profile" });
          if (url.includes("/rest/v1/google_place_photo_cache")) return Response.json([{
            cache_key: "cached", provider_place_id: "venue", object_path: "cached.img",
            provider_types: [], fetched_at: fixedNow.toISOString(),
          }]);
          if (url.includes("/storage/v1/object/sign/")) {
            const body = JSON.parse(String(init?.body));
            assertEquals(Boolean(body.transform), render_variant !== "fullscreen");
            return Response.json({ signedURL });
          }
          throw new Error("unexpected request");
        },
      };
      const response = await handleRequest(providerTestRequest({
        name: "Venue", source_provider: "google", source_provider_place_id: "venue", render_variant,
      }), dependencies);
      const body = await response.json();
      assertEquals(response.status, 200);
      assertEquals(body.photo_url, expectedURL);
    }
  }
});

Deno.test("native sparse search enriches current hours through same-place Details", async () => {
  const fixture = providerEnrichmentFixture();
  fixture.searchPlace.currentOpeningHours = undefined;
  fixture.detailsPlace.currentOpeningHours = { openNow: false, nextOpenTime: "2026-08-14T15:00:00Z" };
  const response = await handleRequest(providerTestRequest(fixture.input), fixture.dependencies);
  const body = await response.json();
  assertEquals(body.provider_open_now, false);
  assertEquals(body.provider_next_open_time, "2026-08-14T15:00:00Z");
  assertEquals(fixture.calls.join(","), "search,details:provider-venue");
  assertEquals(fixture.writes[0].provider_open_now, false);
});

Deno.test("fresh native metadata with unknown hours validates its cached Google identity", async () => {
  const fixture = providerEnrichmentFixture();
  fixture.cache = { provider_place_id: "provider-venue", fetched_at: fixedNow.toISOString(),
    provider_open_now: null, provider_types: [], object_path: "cached.img" };
  const response = await handleRequest(providerTestRequest(fixture.input), fixture.dependencies);
  const body = await response.json();
  assertEquals(body.provider_open_now, true);
  assertEquals(fixture.calls.join(","), "details:provider-venue");
  assertEquals(fixture.writes[0].provider_open_now, true);
  assertEquals("object_path" in fixture.writes[0], false);
});

Deno.test("moved cached identity cannot attach its hours to a native place", async () => {
  const fixture = providerEnrichmentFixture();
  fixture.cache = { provider_place_id: "old-venue", fetched_at: "2026-08-01T00:00:00Z",
    provider_open_now: null, provider_types: [] };
  fixture.oldDetails = { ...fixture.detailsPlace, id: "old-venue", businessStatus: "CLOSED_PERMANENTLY",
    movedPlaceId: "distant-moved-venue", currentOpeningHours: { openNow: false } };
  const response = await handleRequest(providerTestRequest(fixture.input), fixture.dependencies);
  const body = await response.json();
  assertEquals(body.provider_place_id, "provider-venue");
  assertEquals(body.provider_open_now, true);
  assertEquals(fixture.calls.join(","), "details:old-venue,search,details:provider-venue");
  assertEquals(fixture.writes.length, 0);
  assert(fixture.diagnostics.some((event) => event.result === "stale_identity"), "stale identity diagnosis missing");
});

Deno.test("sparse search imagery can load from Details without changing venue identity", async () => {
  const fixture = providerEnrichmentFixture();
  fixture.input.requires_photo = true;
  fixture.detailsPlace.photos = [{ name: "places/provider-venue/photos/front", widthPx: 1600, heightPx: 1200,
    googleMapsUri: "https://www.google.com/maps/photo/front", authorAttributions: [{ displayName: "Author" }] }];
  const response = await handleRequest(providerTestRequest(fixture.input), fixture.dependencies);
  const body = await response.json();
  assertEquals(body.provider_place_id, "provider-venue");
  assertEquals(body.photo_url, "https://lh3.googleusercontent.com/front");
  assertEquals(body.source_photo_url, "https://www.google.com/maps/photo/front");
  assertEquals(fixture.calls.join(","), "search,details:provider-venue,media");
});

Deno.test("missing or failed Details hours stay unknown with content-free diagnostics", async () => {
  for (const failsDetails of [false, true]) {
    const fixture = providerEnrichmentFixture();
    fixture.detailsPlace.currentOpeningHours = undefined;
    fixture.failsDetails = failsDetails;
    const response = await handleRequest(providerTestRequest(fixture.input), fixture.dependencies);
    const body = await response.json();
    assertEquals(body.provider_open_now, null);
    assertEquals(body.provider_next_open_time, null);
    const resolution = fixture.diagnostics.find((event) => event.event === "place_photo_resolution");
    assertEquals(resolution?.has_current_hours, false);
    assertEquals(resolution?.request_kind, "metadata");
    if (failsDetails) assert(fixture.diagnostics.some((event) => event.result === "unavailable"), "failure diagnosis missing");
    const serialized = JSON.stringify(fixture.diagnostics);
    for (const content of ["Synthetic Cafe", "123 Fixture St", "provider-venue", "34.1", "https://"]) {
      assert(!serialized.includes(content), "provider diagnostics must not contain request/place content");
    }
  }
});

function providerEnrichmentFixture() {
  const basic = { id: "provider-venue", displayName: { text: "Synthetic Cafe" },
    formattedAddress: "123 Fixture St", location: { latitude: 34.1, longitude: -118.1 } };
  const fixture: {
    input: Record<string, unknown>;
    cache: Record<string, unknown> | null;
    searchPlace: Record<string, unknown>;
    detailsPlace: Record<string, unknown>;
    oldDetails: Record<string, unknown> | null;
    failsDetails: boolean;
    calls: string[];
    writes: Array<Record<string, unknown>>;
    diagnostics: Array<Record<string, string | boolean>>;
    dependencies: PlacePhotoDependencies;
  } = {
    input: { name: "Synthetic Cafe", address: "123 Fixture St", latitude: 34.1, longitude: -118.1,
      source_provider: "mapkit", source_provider_place_id: "native-alias", requires_photo: false },
    cache: null, searchPlace: { ...basic }, detailsPlace: { ...basic, currentOpeningHours: { openNow: true } },
    oldDetails: null, failsDetails: false, calls: [], writes: [], diagnostics: [],
    dependencies: {
      now: () => fixedNow,
      env: (name) => ({ SUPABASE_URL: "https://example.supabase.co", SUPABASE_ANON_KEY: "publishable-key",
        SUPABASE_SERVICE_ROLE_KEY: "service-role-key", WANDER_GOOGLE_PLACES_API_KEY: "google-key" })[name],
      diagnostic: (event) => fixture.diagnostics.push(event),
      // deno-lint-ignore require-await
      fetch: async (input, init) => {
        const url = input.toString();
        if (url.endsWith("/rest/v1/rpc/current_profile")) return Response.json({ id: "profile" });
        if (url.includes("/rest/v1/google_place_photo_cache")) {
          if ((init?.method ?? "GET") === "GET") return Response.json(fixture.cache ? [fixture.cache] : []);
          fixture.writes.push(JSON.parse(String(init?.body)));
          return new Response(null, { status: 201 });
        }
        if (url.endsWith("/places:searchText")) {
          fixture.calls.push("search");
          return Response.json({ places: [fixture.searchPlace] });
        }
        if (url.includes("/media?")) {
          fixture.calls.push("media");
          return Response.json({ photoUri: "https://lh3.googleusercontent.com/front" });
        }
        if (url.includes("places.googleapis.com/v1/places/")) {
          const id = url.split("/").at(-1) ?? "";
          fixture.calls.push(`details:${id}`);
          if (fixture.failsDetails) throw new Error("synthetic_unavailable");
          return Response.json(id === "old-venue" ? fixture.oldDetails : fixture.detailsPlace);
        }
        // Image caching may fail independently; use the legitimate provider URL.
        if (url.includes("googleusercontent.com")) return new Response(null, { status: 503 });
        throw new Error("unexpected request");
      },
    },
  };
  return fixture;
}

function providerTestRequest(body: Record<string, unknown>): Request {
  return new Request("https://example.supabase.co/functions/v1/place-photo", {
    method: "POST", headers: { Authorization: "Bearer test", "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}
