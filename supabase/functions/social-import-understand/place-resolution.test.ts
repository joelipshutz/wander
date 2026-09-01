import {
  googlePlacesAPIKey,
  resolvePlaceHintsWithGoogle,
} from "./place-resolution.ts";
import type { PlaceHint, RuntimeDependencies } from "./types.ts";
import { Deadline } from "./types.ts";

const hint: PlaceHint = {
  name: "Nayara Bocas del Toro",
  area: "Bocas del Toro, Panama",
  classification: "destination",
  modality: "caption",
  evidence_ids: ["caption:0"],
  confidence: 0.99,
  start_ms: null,
  end_ms: null,
};

Deno.test("Google resolution keeps real POIs and rejects a matching locality", async () => {
  const dependencies = runtime(async (url, init) => {
    assertEquals(url, "https://places.googleapis.com/v1/places:searchText");
    assertEquals(init?.method, "POST");
    assertEquals(
      (init?.headers as Record<string, string>)["X-Goog-Api-Key"],
      "google-key",
    );
    return Response.json({
      places: [
        googlePlace({
          id: "bocas-locality",
          name: "Bocas del Toro",
          primaryType: "locality",
        }),
        googlePlace({
          id: "nayara",
          name: "Nayara Bocas del Toro",
          primaryType: "resort_hotel",
        }),
      ],
    });
  });

  const resolved = await resolvePlaceHintsWithGoogle(
    [hint],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );

  assertEquals(resolved[0].resolved_places, [{
    provider: "google_places",
    provider_place_id: "nayara",
    name: "Nayara Bocas del Toro",
    formatted_address: "Bocas del Toro Province, Panama",
    locality: "Bocas del Toro",
    region: "BT",
    country: "PA",
    latitude: 9.35,
    longitude: -82.25,
    primary_type: "resort_hotel",
    types: ["resort_hotel", "lodging", "point_of_interest"],
  }]);
});

Deno.test("Google resolution keeps strong official-name variants and caps alternatives", async () => {
  const variantHint: PlaceHint = {
    ...hint,
    name: "The Retreat at Blue Lagoon Iceland",
    area: "Reykjanes Peninsula, Iceland",
  };
  const dependencies = runtime(async () =>
    Response.json({
      places: [
        googlePlace({ id: "retreat", name: "The Retreat - Blue Lagoon" }),
        googlePlace({ id: "retreat-spa", name: "Retreat Spa Blue Lagoon" }),
        googlePlace({ id: "blue-lagoon", name: "Blue Lagoon" }),
        googlePlace({ id: "unrelated", name: "Reykjanes Guesthouse" }),
      ],
    })
  );

  const resolved = await resolvePlaceHintsWithGoogle(
    [variantHint],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );

  assertEquals(
    resolved[0].resolved_places?.map((place) => place.provider_place_id),
    ["retreat", "blue-lagoon", "retreat-spa"],
  );
});

Deno.test("Google resolution rejects natural features that share a resort brand", async () => {
  const resortHint: PlaceHint = {
    ...hint,
    name: "Nimmo Bay Resort",
    area: "British Columbia, Canada",
  };
  const dependencies = runtime(async () =>
    Response.json({
      places: [
        googlePlace({
          id: "nimmo-bay-feature",
          name: "Nimmo Bay",
          primaryType: "natural_feature",
        }),
        googlePlace({
          id: "nimmo-bay-resort",
          name: "Nimmo Bay Wilderness Resort",
          primaryType: "resort_hotel",
        }),
        googlePlace({
          id: "bawah-island",
          name: "Nimmo Bay Island",
          primaryType: "island",
        }),
      ],
    })
  );

  const resolved = await resolvePlaceHintsWithGoogle(
    [resortHint],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );

  assertEquals(
    resolved[0].resolved_places?.map((place) => place.provider_place_id),
    ["nimmo-bay-resort"],
  );
});

Deno.test("Google resolution preserves named natural destinations", async () => {
  const mountainHint: PlaceHint = {
    ...hint,
    name: "Vetter Mountain",
    area: "Los Angeles County, California",
  };
  const dependencies = runtime(async () =>
    Response.json({
      places: [
        googlePlace({
          id: "vetter-mountain",
          name: "Vetter Mountain",
          primaryType: "mountain_peak",
        }),
      ],
    })
  );

  const resolved = await resolvePlaceHintsWithGoogle(
    [mountainHint],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );

  assertEquals(
    resolved[0].resolved_places?.map((place) => place.provider_place_id),
    ["vetter-mountain"],
  );
});

Deno.test("Google resolution fails open to grounded hints without fabricating candidates", async () => {
  const dependencies = runtime(async () =>
    Response.json({ error: "quota" }, { status: 429 })
  );
  const resolved = await resolvePlaceHintsWithGoogle(
    [hint],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );
  assertEquals(resolved, [hint]);
  assertEquals(googlePlacesAPIKey(dependencies), "configured-key");
});

function googlePlace(
  values: { id: string; name: string; primaryType?: string },
): unknown {
  return {
    id: values.id,
    displayName: { text: values.name },
    formattedAddress: "Bocas del Toro Province, Panama",
    addressComponents: [
      {
        longText: "Bocas del Toro",
        shortText: "Bocas del Toro",
        types: ["locality"],
      },
      {
        longText: "Bocas del Toro Province",
        shortText: "BT",
        types: ["administrative_area_level_1"],
      },
      { longText: "Panama", shortText: "PA", types: ["country"] },
    ],
    location: { latitude: 9.35, longitude: -82.25 },
    primaryType: values.primaryType ?? "resort_hotel",
    types: ["resort_hotel", "lodging", "point_of_interest"],
  };
}

function runtime(fetcher: typeof fetch): RuntimeDependencies {
  return {
    fetch: fetcher,
    env: (name) =>
      name === "WANDER_GOOGLE_PLACES_API_KEY" ? "configured-key" : undefined,
    now: () => 0,
    sleep: async () => undefined,
    random: () => 0.5,
  };
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
