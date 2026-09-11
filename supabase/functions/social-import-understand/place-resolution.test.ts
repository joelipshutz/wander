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

Deno.test("Google neighborhood evidence survives resolution without becoming a street or country alias", async () => {
  const dependencies = runtime(async () =>
    Response.json({
      places: [{
        ...(googlePlace({
          id: "bookstore",
          name: "Fixture Bookstore",
        }) as Record<string, unknown>),
        addressComponents: [
          {
            longText: "Downtown Example City",
            shortText: "DEC",
            types: ["neighborhood", "political"],
          },
          {
            longText: "Central District",
            types: ["sublocality_level_1", "political"],
          },
          {
            longText: "Downtown Example City",
            types: ["sublocality", "political"],
          },
          { longText: "Wrong Neighborhood Street", types: ["route"] },
          { longText: "United States", shortText: "US", types: ["country"] },
        ],
      }],
    })
  );
  const resolved = await resolvePlaceHintsWithGoogle(
    [{ ...hint, name: "Fixture Bookstore", area: "Downtown Example City" }],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );
  assertEquals(
    Reflect.get(resolved[0].resolved_places![0], "area_components"),
    [
      "Downtown Example City",
      "Central District",
    ],
  );
});

Deno.test("Google neighborhood evidence is bounded and ignores malformed components", async () => {
  const dependencies = runtime(async () =>
    Response.json({
      places: [{
        ...(googlePlace({ id: "bounded", name: "Fixture Bookstore" }) as Record<
          string,
          unknown
        >),
        addressComponents: [
          null,
          42,
          {},
          { longText: "x".repeat(161), types: ["neighborhood"] },
          { longText: "Wrong", types: "neighborhood" },
          { shortText: "LA", types: ["neighborhood"] },
          ...Array.from({ length: 12 }, (_, i) => ({
            longText: `District ${i}`,
            types: ["neighborhood"],
          })),
        ],
      }],
    })
  );
  const resolved = await resolvePlaceHintsWithGoogle(
    [{ ...hint, name: "Fixture Bookstore", area: null }],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );
  assertEquals(
    resolved[0].resolved_places![0].area_components,
    Array.from({ length: 8 }, (_, i) => `District ${i}`),
  );
});

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
    area_components: ["Bocas del Toro Province"],
    latitude: 9.35,
    longitude: -82.25,
    primary_type: "resort_hotel",
    types: ["resort_hotel", "lodging", "point_of_interest"],
  }]);
});

Deno.test("Google resolution preserves exact spacing variants and full province evidence", async () => {
  const dependencies = runtime(async () =>
    Response.json({
      places: [
        {
          ...(googlePlace({ id: "exact", name: "Moon Beam" }) as Record<
            string,
            unknown
          >),
          addressComponents: [
            {
              longText: "British Columbia",
              shortText: "BC",
              types: ["administrative_area_level_1", "political"],
            },
            {
              longText: "Canada",
              shortText: "CA",
              types: ["country", "political"],
            },
          ],
        },
        googlePlace({ id: "different-business", name: "Moon Beam Bakehouse" }),
      ],
    })
  );
  const resolved = await resolvePlaceHintsWithGoogle(
    [{ ...hint, name: "Moonbeam", area: "Vancouver, British Columbia" }],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );
  assertEquals(
    resolved[0].resolved_places?.map((place) => place.provider_place_id),
    ["exact"],
  );
  assertEquals(resolved[0].resolved_places?.[0].area_components, [
    "British Columbia",
  ]);
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

Deno.test("Google resolution returns coordinate-backed candidates for all 17 acceptance hotels", async () => {
  const acceptanceHotels = [
    ["Nayara Bocas del Toro", "Bocas del Toro, Panama"],
    ["The Retreat at Blue Lagoon Iceland", "Reykjanes Peninsula, Iceland"],
    ["Nimmo Bay Resort", "British Columbia, Canada"],
    ["Jao Camp", "Okavango Delta, Botswana"],
    ["The Brando", "Tetiaroa, French Polynesia"],
    ["Shebara", "Sheybarah Island, Red Sea, Saudi Arabia"],
    ["Joali Maldives", "Muravandhoo Island, Raa Atoll, Maldives"],
    ["Shinta Mani Wild", "Cardamom Mountains, Cambodia"],
    ["Bawah Reserve", "Anambas Archipelago, Indonesia"],
    [
      "Nujuma, a Ritz-Carlton Reserve",
      "Ummahat Islands, Red Sea, Saudi Arabia",
    ],
    ["Song Saa Private Island", "Koh Rong Archipelago, Cambodia"],
    ["Kudadoo Maldives Private Island", "Lhaviyani Atoll, Maldives"],
    ["Arctic Bath", "Lule River, Swedish Lapland, Sweden"],
    ["Pumphouse Point", "Lake St Clair, Tasmania, Australia"],
    ["Misool Resort", "Raja Ampat, Indonesia"],
    ["Brindos, Lac & Château", "Anglet, France"],
    [
      "Victoria Falls River Lodge: Island Treehouse Suites",
      "Kandahar Island, Zambezi River, Zimbabwe",
    ],
  ] as const;
  const expectedQueries = new Map(
    acceptanceHotels.map(([name, area], index) => [
      `${name}, ${area}`,
      { name, id: `acceptance-hotel-${index + 1}` },
    ]),
  );
  const receivedQueries: string[] = [];
  const dependencies = runtime(async (_url, init) => {
    const body = JSON.parse(String(init?.body));
    const query = String(body.textQuery);
    receivedQueries.push(query);
    const expected = expectedQueries.get(query);
    if (!expected) throw new Error(`Unexpected Google query: ${query}`);
    return Response.json({
      places: [googlePlace({
        id: expected.id,
        name: expected.name,
        primaryType: "resort_hotel",
      })],
    });
  });
  const hints = acceptanceHotels.map(([name, area], index): PlaceHint => ({
    name,
    area,
    classification: "destination",
    modality: "image_text",
    evidence_ids: [`media:${index}`],
    confidence: 0.99,
    start_ms: null,
    end_ms: null,
  }));

  const resolved = await resolvePlaceHintsWithGoogle(
    hints,
    "google-key",
    new Deadline(30_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );

  assertEquals(receivedQueries, [...expectedQueries.keys()]);
  assertEquals(resolved.length, 17);
  assertEquals(
    resolved.map((item) => item.resolved_places?.[0]?.provider_place_id),
    acceptanceHotels.map((_, index) => `acceptance-hotel-${index + 1}`),
  );
  assertEquals(
    resolved.every((item) =>
      item.resolved_places?.[0]?.latitude === 9.35 &&
      item.resolved_places?.[0]?.longitude === -82.25
    ),
    true,
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

Deno.test("Google resolution retries a transient provider failure once", async () => {
  let attemptCount = 0;
  const dependencies = runtime(async () => {
    attemptCount += 1;
    if (attemptCount === 1) {
      return Response.json({ error: "temporary" }, { status: 429 });
    }
    return Response.json({
      places: [googlePlace({
        id: "nayara-after-retry",
        name: "Nayara Bocas del Toro",
      })],
    });
  });

  const resolved = await resolvePlaceHintsWithGoogle(
    [hint],
    "google-key",
    new Deadline(10_000, dependencies.now),
    dependencies,
    new AbortController().signal,
  );

  assertEquals(attemptCount, 2);
  assertEquals(
    resolved[0].resolved_places?.[0]?.provider_place_id,
    "nayara-after-retry",
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
