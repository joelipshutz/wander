import { apifyActorRequest, normalizeApifyDataset } from "./apify.ts";
import {
  evidenceCatalog,
  groundedHints,
  minimumGroundedConfidence,
} from "./evidence.ts";
import { parseGeminiCandidates, parseGeminiUnderstanding } from "./gemini.ts";
import {
  handleRequest,
  maximumHandlerDurationMilliseconds,
} from "./handler.ts";
import {
  fetchMediaBytes,
  mayReceiveApifyAuthorization,
  validatedMediaURL,
} from "./media.ts";
import { parseSocialSource } from "./source.ts";
import type {
  AcquisitionEvidence,
  ModelCandidate,
  ModelPostContext,
  RuntimeDependencies,
  SocialSource,
} from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

const instagramURL = "https://www.instagram.com/p/DcAU9e5DYcH";
const instagramReelURL = "https://www.instagram.com/reel/DcAU9e5DYcH";
const tiktokURL = "https://www.tiktok.com/@creator/video/7451234567890123456";
const mediaURL = "https://images.cdninstagram.com/media/photo.jpg";
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xdb, 0x00, 0x01]);
const admissionID = "10000000-0000-4000-8000-000000000001";

Deno.test("handler enforces method and explicit current-profile authorization", async () => {
  let fetchCount = 0;
  const dependencies = runtime(() => {
    fetchCount += 1;
    return Response.json({ code: "PGRST301" }, { status: 401 });
  });

  const wrongMethod = await handleRequest(
    new Request("https://function.test", { method: "GET" }),
    dependencies,
  );
  const missing = await handleRequest(
    jsonRequest(socialRequestBody(instagramURL), null),
    dependencies,
  );
  const invalid = await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  );

  assertEquals(wrongMethod.status, 405);
  assertEquals(missing.status, 401);
  assertEquals(invalid.status, 401);
  assertEquals(fetchCount, 1);
});

Deno.test("handler rejects non-social, profile, credentialed, and non-JSON input", async () => {
  const dependencies = runtime(authenticatedOnly);
  const invalidURLs = [
    "http://www.instagram.com/p/DcAU9e5DYcH",
    "https://user:pass@www.instagram.com/p/DcAU9e5DYcH",
    "https://www.instagram.com/creator",
    "https://example.com/p/DcAU9e5DYcH",
  ];
  for (const url of invalidURLs) {
    const response = await handleRequest(
      jsonRequest(socialRequestBody(url)),
      dependencies,
    );
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "unsupported_social_url" });
  }
  const wrongType = await handleRequest(
    new Request("https://function.test", {
      method: "POST",
      headers: {
        authorization: "Bearer user-token",
        "content-type": "text/plain",
      },
      body: JSON.stringify(socialRequestBody(instagramURL)),
    }),
    dependencies,
  );
  assertEquals(wrongType.status, 415);

  for (
    const body of [
      { ...socialRequestBody(instagramURL), schema_version: 2 },
      {
        ...socialRequestBody(instagramURL),
        client_request_id: "x".repeat(161),
      },
      { ...socialRequestBody(instagramURL), extra: true },
    ]
  ) {
    const response = await handleRequest(jsonRequest(body), dependencies);
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "invalid_request" });
  }
  const mismatch = await handleRequest(
    jsonRequest(socialRequestBody(instagramURL, "tiktok")),
    dependencies,
  );
  assertEquals(mismatch.status, 400);
  assertEquals(await mismatch.json(), { error: "platform_mismatch" });
});

Deno.test("actor selection and inputs preserve the evaluated canary contract", () => {
  const post = requiredSource(instagramURL);
  const reel = requiredSource(instagramReelURL);
  const tiktok = requiredSource(tiktokURL);

  assertEquals(apifyActorRequest(post), {
    actor: "apify/instagram-scraper",
    input: { directUrls: [post.url], resultsType: "posts", resultsLimit: 1 },
  });
  assertEquals(apifyActorRequest(reel), {
    actor: "apify/instagram-reel-scraper",
    input: {
      username: [reel.url],
      resultsLimit: 1,
      includeDownloadedVideo: true,
    },
  });
  assertEquals(apifyActorRequest(tiktok), {
    actor: "clockworks/tiktok-scraper",
    input: {
      postURLs: [tiktok.url],
      resultsPerPage: 1,
      shouldDownloadVideos: true,
      shouldDownloadSlideshowImages: true,
      aiVideoDescription: false,
    },
  });
  assert(maximumHandlerDurationMilliseconds <= 115_000);
});

Deno.test("successful handler run authenticates, caps Apify, and returns grounded hints only", async () => {
  const calls: Array<{ url: string; headers: Headers; body: string }> = [];
  let beginCount = 0;
  let finishCount = 0;
  const caption =
    "A creator caption with private prose. Visit Carbon Beach Club in Malibu.";
  const dependencies = runtime((input, init) => {
    const url = String(input);
    const headers = new Headers(init?.headers);
    calls.push({ url, headers, body: String(init?.body ?? "") });
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      assertEquals(headers.get("authorization"), "Bearer user-token");
      assertEquals(headers.get("apikey"), "publishable-key");
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      return Response.json({
        data: {
          id: "run-1",
          status: "SUCCEEDED",
          defaultDatasetId: "dataset-1",
        },
      });
    }
    if (url.includes("/v2/datasets/dataset-1/items")) {
      return Response.json([{
        inputUrl: instagramURL,
        description: caption,
        images: [mediaURL],
      }]);
    }
    if (url === mediaURL) {
      assertEquals(headers.has("authorization"), false);
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      assertEquals(headers.get("x-goog-api-key"), "gemini-secret");
      const requestBody = JSON.parse(String(init?.body));
      assertEquals(
        requestBody.generationConfig.responseFormat.text.schema.properties
          .candidates.items
          .properties.evidenceIds.type,
        "array",
      );
      assertEquals(
        requestBody.generationConfig.responseFormat.text.schema.required,
        ["postContext", "candidates"],
      );
      assertEquals(
        requestBody.generationConfig.responseFormat.text.schema.properties
          .candidates.items.required.includes("entityType"),
        true,
      );
      assertEquals(
        requestBody.generationConfig.responseFormat.text.schema.properties
          .candidates.items.required.includes("itemIndex"),
        true,
      );
      return geminiResponse([candidate({
        name: "Carbon Beach Club",
        area: "Malibu",
        modality: "image_text",
        evidenceIds: ["media:0"],
      })]);
    }
    throw new Error(`unexpected fetch ${url}`);
  }, {
    onBegin: (headers, body) => {
      beginCount += 1;
      assertEquals(headers.get("authorization"), "Bearer user-token");
      assertEquals(headers.get("apikey"), "publishable-key");
      assertEquals(body, { input_client_request_id: "stable-request-id" });
    },
    onFinish: (headers, body) => {
      finishCount += 1;
      assertEquals(headers.get("authorization"), "Bearer user-token");
      assertEquals(headers.get("apikey"), "publishable-key");
      assertEquals(body, {
        input_client_request_id: "stable-request-id",
        input_admission_id: admissionID,
      });
    },
  });

  const response = await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  );
  assertEquals(response.status, 200);
  const payload = await response.json();
  assertEquals(payload.outcome, "ok");
  assertEquals(payload.provider_path, "apify_gemini");
  assertEquals(payload.media_count, 1);
  assertEquals(payload.model_attempt_count, 1);
  assertEquals(payload.failure_category, null);
  assertEquals(payload.hints, [{
    name: "Carbon Beach Club",
    area: "Malibu",
    classification: "destination",
    modality: "image_text",
    evidence_ids: ["media:0"],
    confidence: 0.91,
    start_ms: null,
    end_ms: null,
  }]);
  const actorCall = calls.find((call) => call.url.includes("/v2/actors/"));
  assert(actorCall?.url.includes("maxTotalChargeUsd=1"));
  assertEquals(JSON.parse(actorCall?.body ?? "{}"), {
    directUrls: [instagramURL],
    resultsType: "posts",
    resultsLimit: 1,
  });
  assertEquals(beginCount, 1);
  assertEquals(finishCount, 1);
  assertSafeResponse(payload, caption);
});

Deno.test("Gemini retries only retryable statuses then returns deterministic fallback", async () => {
  let geminiCalls = 0;
  const caption =
    "Unreturned caption prose that must never appear in the response.";
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/")) {
      return Response.json({
        data: {
          id: "run-1",
          status: "SUCCEEDED",
          defaultDatasetId: "dataset-1",
        },
      });
    }
    if (url.includes("/v2/datasets/")) {
      return Response.json([{
        inputUrl: instagramURL,
        description: caption,
        locationName: "Carbon Beach Club",
        address: "Malibu",
        images: [mediaURL],
      }]);
    }
    if (url === mediaURL) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      geminiCalls += 1;
      return new Response("provider detail must stay private", { status: 503 });
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const response = await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  );
  const payload = await response.json();
  assertEquals(geminiCalls, 3);
  assertEquals(payload.outcome, "partial");
  assertEquals(payload.provider_path, "apify_deterministic");
  assertEquals(payload.failure_category, "understanding_unavailable");
  assertEquals(payload.model_attempt_count, 3);
  assertEquals(payload.hints[0].name, "Carbon Beach Club");
  assertEquals(payload.hints[0].evidence_ids, ["tagged_location:0"]);
  assertSafeResponse(payload, caption);
});

Deno.test("nonretryable Gemini status is attempted once", async () => {
  let geminiCalls = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/")) {
      return Response.json({
        data: {
          id: "run-1",
          status: "SUCCEEDED",
          defaultDatasetId: "dataset-1",
        },
      });
    }
    if (url.includes("/v2/datasets/")) {
      return Response.json([{ inputUrl: instagramURL, images: [mediaURL] }]);
    }
    if (url === mediaURL) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      geminiCalls += 1;
      return Response.json({ error: {} }, { status: 400 });
    }
    throw new Error(`unexpected fetch ${url}`);
  });
  const payload = await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json();
  assertEquals(geminiCalls, 1);
  assertEquals(payload.outcome, "fallback");
  assertEquals(payload.model_attempt_count, 1);
});

Deno.test("Gemini transport failures retry within the same bounded policy", async () => {
  let geminiCalls = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/")) {
      return Response.json({
        data: {
          id: "run-1",
          status: "SUCCEEDED",
          defaultDatasetId: "dataset-1",
        },
      });
    }
    if (url.includes("/v2/datasets/")) {
      return Response.json([{
        inputUrl: instagramURL,
        description: "Visit Carbon Beach Club in Malibu.",
        images: [mediaURL],
      }]);
    }
    if (url === mediaURL) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      geminiCalls += 1;
      if (geminiCalls < 3) throw new TypeError("simulated transport failure");
      return geminiResponse([candidate({
        name: "Carbon Beach Club",
        modality: "caption",
        evidenceIds: ["caption:0"],
      })]);
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const payload = await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json();
  assertEquals(geminiCalls, 3);
  assertEquals(payload.outcome, "ok");
  assertEquals(payload.model_attempt_count, 3);
  assertEquals(payload.hints.map((hint: { name: string }) => hint.name), [
    "Carbon Beach Club",
  ]);
});

Deno.test("Apify failure returns a bounded acquisition fallback without raw payload", async () => {
  const rawDetail = "private-provider-debug-envelope";
  let finishCount = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    return Response.json({ error: rawDetail }, { status: 503 });
  }, {
    onFinish: () => finishCount += 1,
  });
  const payload = await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json();
  assertEquals(payload.outcome, "fallback");
  assertEquals(payload.provider_path, "apify_deterministic");
  assertEquals(payload.failure_category, "acquisition_unavailable");
  assertEquals(payload.hints, []);
  assertEquals(finishCount, 1);
  assert(!JSON.stringify(payload).includes(rawDetail));
  assertSafeResponse(payload, "unused-caption");
});

Deno.test("paid-work admission denials stop before Apify and return safe fallback categories", async () => {
  const cases = [
    ["disabled", "feature_disabled"],
    ["duplicate", "duplicate_request"],
    ["replay_required", "retry_required"],
    ["busy", "capacity_limited"],
    ["quota", "quota_exceeded"],
  ] as const;
  for (const [decision, failureCategory] of cases) {
    let providerCalls = 0;
    let finishCalls = 0;
    const dependencies = runtime((input) => {
      const url = String(input);
      if (url.endsWith("/rest/v1/rpc/current_profile")) {
        return Response.json([{ id: "user-1" }]);
      }
      providerCalls += 1;
      throw new Error(`paid provider called after ${decision} denial`);
    }, {
      admission: { admitted: false, decision, admission_id: null },
      onFinish: () => finishCalls += 1,
    });
    const payload = await (await handleRequest(
      jsonRequest(socialRequestBody(instagramURL)),
      dependencies,
    )).json();
    assertEquals(payload.outcome, "fallback");
    assertEquals(payload.provider_path, "apify_deterministic");
    assertEquals(payload.failure_category, failureCategory);
    assertEquals(providerCalls, 0);
    assertEquals(finishCalls, 0);
    assertSafeResponse(payload, "unused-caption");
  }
});

Deno.test("admission RPC failure fails closed before paid provider work", async () => {
  let providerCalls = 0;
  let finishCalls = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    providerCalls += 1;
    throw new Error("provider must not run when admission is unavailable");
  }, {
    beginStatus: 503,
    onFinish: () => finishCalls += 1,
  });
  const payload = await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json();
  assertEquals(payload.outcome, "fallback");
  assertEquals(payload.failure_category, "admission_unavailable");
  assertEquals(providerCalls, 0);
  assertEquals(finishCalls, 0);
});

Deno.test("streamed request bodies are rejected as soon as they exceed the limit", async () => {
  let admissionCalls = 0;
  const bytes = new TextEncoder().encode("x".repeat(9_000));
  const body = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(bytes);
      controller.enqueue(bytes);
      controller.close();
    },
  });
  const dependencies = runtime(authenticatedOnly, {
    onBegin: () => admissionCalls += 1,
  });
  const response = await handleRequest(
    new Request("https://function.test", {
      method: "POST",
      headers: {
        authorization: "Bearer user-token",
        "content-type": "application/json",
      },
      body,
    }),
    dependencies,
  );
  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "request_too_large" });
  assertEquals(admissionCalls, 0);
});

Deno.test("handler separates honest emptiness, uncertainty, and intentional exclusions", async () => {
  const complete = await runOutcomeScenario([], true);
  assertEquals(complete.outcome, "no_places");
  assertEquals(complete.failure_category, null);

  const rejected = await runOutcomeScenario([candidate({
    name: "Invented Place",
    modality: "caption",
    evidenceIds: ["caption:0"],
  })], true);
  assertEquals(rejected.outcome, "fallback");
  assertEquals(rejected.failure_category, "grounding_rejected");

  const ambiguous = await runOutcomeScenario([candidate({
    name: "An uncertain venue",
    classification: "ambiguous",
    modality: "caption",
    evidenceIds: ["caption:0"],
  })], true);
  assertEquals(ambiguous.outcome, "fallback");
  assertEquals(ambiguous.failure_category, "grounding_rejected");

  const incomplete = await runOutcomeScenario([], false);
  assertEquals(incomplete.outcome, "partial");
  assertEquals(incomplete.provider_path, "apify_gemini");
  assertEquals(incomplete.hints, []);
  assertEquals(incomplete.failure_category, "media_incomplete");

  const intentionalExclusions = await runOutcomeScenario([candidate({
    name: "Vital Links",
    area: "Texas",
    classification: "incidental",
    modality: "image_text",
    evidenceIds: ["media:0"],
  })], true);
  assertEquals(intentionalExclusions.outcome, "no_places");
  assertEquals(intentionalExclusions.hints, []);
  assertEquals(intentionalExclusions.failure_category, null);
});

Deno.test("intentional exclusions survive failed media and rejected candidates", async () => {
  const excludedLocation = candidate({
    name: "Los Angeles",
    area: "California",
    entityType: "locality",
    classification: "incidental",
    modality: "tagged_location",
    evidenceIds: ["tagged_location:0"],
  });
  const dataset = {
    description: "Los Angeles is context, not a destination.",
    locationName: "Los Angeles",
    address: "California",
  };

  const excludedWithFailedMedia = await runOutcomeScenario(
    [excludedLocation],
    false,
    dataset,
  );
  assertEquals(excludedWithFailedMedia.outcome, "partial");
  assertEquals(excludedWithFailedMedia.provider_path, "apify_gemini");
  assertEquals(excludedWithFailedMedia.hints, []);
  assertEquals(
    excludedWithFailedMedia.failure_category,
    "media_incomplete",
  );

  const excludedWithRejected = await runOutcomeScenario(
    [
      excludedLocation,
      candidate({
        name: "Invented Venue",
        area: "",
        modality: "caption",
        evidenceIds: ["caption:0"],
      }),
    ],
    true,
    dataset,
  );
  assertEquals(excludedWithRejected.outcome, "partial");
  assertEquals(excludedWithRejected.provider_path, "apify_gemini");
  assertEquals(excludedWithRejected.hints, []);
  assertEquals(excludedWithRejected.failure_category, "grounding_rejected");

  const groundedWithMixedFailures = await runOutcomeScenario(
    [
      candidate({
        name: "Carbon Beach Club",
        area: "",
        modality: "caption",
        evidenceIds: ["caption:0"],
      }),
      excludedLocation,
      candidate({
        name: "Invented Venue",
        area: "",
        modality: "caption",
        evidenceIds: ["caption:0"],
      }),
    ],
    true,
    {
      ...dataset,
      description:
        "Visit Carbon Beach Club. Los Angeles is context, not a destination.",
    },
  );
  assertEquals(groundedWithMixedFailures.outcome, "partial");
  assertEquals(
    (groundedWithMixedFailures.hints as Array<{ name: string }>).map((hint) =>
      hint.name
    ),
    ["Carbon Beach Club"],
  );
  assertEquals(
    groundedWithMixedFailures.failure_category,
    "grounding_rejected",
  );
});

Deno.test("dataset validation rejects item errors, source mismatch, and missing media", () => {
  const source = requiredSource(instagramURL);
  assertErrorCode(
    () =>
      normalizeApifyDataset(
        [{ inputUrl: instagramURL, error: "blocked" }],
        source,
      ),
    "vendor_item_error",
  );
  assertErrorCode(
    () =>
      normalizeApifyDataset([{
        inputUrl: "https://www.instagram.com/reel/OtherPost123",
        images: [mediaURL],
      }], source),
    "vendor_source_mismatch",
  );
  assertErrorCode(
    () =>
      normalizeApifyDataset([{
        inputUrl: instagramURL,
        description: "caption only",
      }], source),
    "vendor_missing_media_assets",
  );
});

Deno.test("grounding accepts cited source evidence and rejects distractors or unattested media", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: "Visit Hotel Bel-Air in Los Angeles. Photo by Tali.",
    taggedLocations: [],
    media: [{
      id: "media:0",
      index: 0,
      kind: "image",
      url: mediaURL,
      thumbnailURL: null,
      altText: null,
    }],
  };
  const result = groundedHints(
    [
      candidate({
        name: "Hotel Bel-Air",
        modality: "caption",
        evidenceIds: ["caption:0"],
      }),
      candidate({
        name: "Photo by Tali",
        classification: "attribution",
        modality: "caption",
        evidenceIds: ["caption:0"],
      }),
      candidate({
        name: "Invented Place",
        modality: "caption",
        evidenceIds: ["caption:0"],
      }),
      candidate({
        name: "Visible Venue",
        modality: "image_text",
        evidenceIds: ["media:0"],
      }),
    ],
    evidenceCatalog(evidence),
    [{
      mediaID: "media:0",
      kind: "image",
      status: "failed",
      byteCount: null,
      mimeType: null,
      errorCode: "media_http_error",
    }],
  );
  assertEquals(result.hints.map((hint) => hint.name), ["Hotel Bel-Air"]);
  assertEquals(result.hints[0].area, null);
  assertEquals(result.rejectedCount, 2);
  assertEquals(result.excludedCount, 1);
  assertEquals(result.intentionalExcludedCount, 1);

  const areaAndConfidence = groundedHints(
    [
      candidate({
        name: "Hotel Bel-Air",
        area: "Los Angeles",
        modality: "caption",
        evidenceIds: ["caption:0"],
      }),
      candidate({
        name: "Visible Venue",
        modality: "image_text",
        evidenceIds: ["media:0"],
        confidence: minimumGroundedConfidence - 0.01,
      }),
    ],
    evidenceCatalog(evidence),
    [{
      mediaID: "media:0",
      kind: "image",
      status: "ok",
      byteCount: jpeg.byteLength,
      mimeType: "image/jpeg",
      errorCode: null,
    }],
  );
  assertEquals(areaAndConfidence.hints.map((hint) => hint.name), [
    "Hotel Bel-Air",
  ]);
  assertEquals(areaAndConfidence.hints[0].area, "Los Angeles");
  assertEquals(areaAndConfidence.rejectedCount, 1);

  const strippedAreaDedup = groundedHints(
    [
      candidate({
        name: "Hotel Bel-Air",
        area: "Malibu",
        modality: "caption",
        evidenceIds: ["caption:0"],
      }),
      candidate({
        name: "Hotel Bel-Air",
        area: "Pasadena",
        modality: "caption",
        evidenceIds: ["caption:0"],
        confidence: 0.9,
      }),
    ],
    evidenceCatalog(evidence),
    [],
  );
  assertEquals(strippedAreaDedup.hints.length, 1);
  assertEquals(strippedAreaDedup.hints[0].area, null);
});

Deno.test("post context keeps one POI per item, demotes city context, and caps to the declared count", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: null,
    taggedLocations: [],
    media: [{
      id: "media:0",
      index: 0,
      kind: "image",
      url: mediaURL,
      thumbnailURL: null,
      altText: null,
    }],
  };
  const context = postContext({
    intent: "place_list",
    declaredCount: 8,
    declaredCountEvidenceIds: ["media:0"],
  });
  const places: Array<[string, string]> = [
    ["Carbon Beach Club", "Malibu"],
    ["Vasquez Rocks Natural Area and Nature Center", "Agua Dulce"],
    ["Naples Canal", "Long Beach"],
    ["Cafe on 27", "Topanga"],
    ["Hotel Bel-Air", "Los Angeles"],
    ["Storrier Stearns Japanese Garden", "Pasadena"],
    ["The Stonehaus", "Westlake Village"],
    ["Sunset Ranch Hollywood", "Los Angeles"],
  ];
  const candidates = places.flatMap(([name, area], itemIndex) => [
    candidate({
      name,
      area,
      modality: "image_text",
      evidenceIds: ["media:0"],
      itemIndex,
    }),
    candidate({
      name: area,
      area: "California",
      entityType: "locality",
      modality: "image_text",
      evidenceIds: ["media:0"],
      itemIndex,
    }),
  ]);

  const result = groundedHints(
    candidates,
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    context,
  );

  assertEquals(
    result.hints.map((hint) => hint.name),
    places.map(([name]) => name),
  );
  assertEquals(result.hints[6].area, "Westlake Village");
  assertEquals(result.rejectedCount, 0);
  assertEquals(result.excludedCount, 8);
});

Deno.test("grounded global area sharpens POIs without erasing a geography list", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: "Ten LA hikes. #losangeles",
    taggedLocations: [],
    media: [{
      id: "media:0",
      index: 0,
      kind: "video",
      url: mediaURL,
      thumbnailURL: null,
      altText: null,
    }],
  };
  const catalog = evidenceCatalog(evidence);
  const ingestions = [successfulMediaIngestion("video")];
  const placeResult = groundedHints(
    [
      candidate({
        name: "Vetter Mountain",
        area: "",
        modality: "video_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "losangeles",
        area: "California",
        entityType: "locality",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "LA",
        area: "",
        entityType: "unknown",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 1,
      }),
      candidate({
        name: "Los Angeles, California",
        area: "",
        entityType: "unknown",
        modality: "video_text",
        evidenceIds: ["media:0"],
        itemIndex: 2,
      }),
      candidate({
        name: "Vital Links",
        area: "Texas",
        classification: "incidental",
        modality: "video_text",
        evidenceIds: ["media:0"],
      }),
    ],
    catalog,
    ingestions,
    150,
    postContext({
      intent: "place_list",
      declaredCount: 10,
      declaredCountEvidenceIds: ["caption:0"],
      globalArea: "Los Angeles, California",
      globalAreaEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(placeResult.hints.map((hint) => [hint.name, hint.area]), [
    ["Vetter Mountain", "Los Angeles, California"],
  ]);
  assertEquals(placeResult.rejectedCount, 0);
  assertEquals(placeResult.excludedCount, 4);

  const geographyResult = groundedHints(
    [
      candidate({
        name: "Malibu",
        area: "California",
        entityType: "locality",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Pasadena",
        area: "California",
        entityType: "locality",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 1,
      }),
      candidate({
        name: "California",
        area: "",
        entityType: "region",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 2,
      }),
    ],
    evidenceCatalog({
      ...evidence,
      caption: "Three places: Malibu, Pasadena, and California.",
    }),
    ingestions,
    150,
    postContext({
      intent: "geography_list",
      declaredCount: 3,
      declaredCountEvidenceIds: ["caption:0"],
      globalArea: "California",
      globalAreaEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(geographyResult.hints.map((hint) => hint.name), [
    "Malibu",
    "Pasadena",
    "California",
  ]);
});

Deno.test("cross-hint area demotion only removes geography entities", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: null,
    taggedLocations: [],
    media: [{
      id: "media:0",
      index: 0,
      kind: "image",
      url: mediaURL,
      thumbnailURL: null,
      altText: null,
    }],
  };
  const result = groundedHints(
    [
      candidate({
        name: "San Diego Zoo",
        area: "San Diego",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Albert's Restaurant",
        area: "San Diego Zoo",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 1,
      }),
      candidate({
        name: "San Diego",
        area: "California",
        entityType: "locality",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 2,
      }),
      candidate({
        name: "Hotel del Coronado",
        area: "San Diego",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 3,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({ intent: "mixed" }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "San Diego Zoo",
    "Albert's Restaurant",
    "Hotel del Coronado",
  ]);
  assertEquals(result.excludedCount, 1);
});

Deno.test("declared count is an upper bound and never pads missing destinations", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: "Two places: Alpha Cafe, Bravo Hotel, and Charlie Park.",
    taggedLocations: [],
    media: [],
  };
  const overCompleteCandidates = [
    candidate({
      name: "Charlie Park",
      area: "",
      modality: "caption",
      evidenceIds: ["caption:0"],
      itemIndex: 2,
    }),
    candidate({
      name: "Alpha Cafe",
      area: "",
      modality: "caption",
      evidenceIds: ["caption:0"],
      itemIndex: 0,
    }),
    candidate({
      name: "Bravo Hotel",
      area: "",
      modality: "caption",
      evidenceIds: ["caption:0"],
      itemIndex: 1,
    }),
  ];
  const result = groundedHints(
    overCompleteCandidates,
    evidenceCatalog(evidence),
    [],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 2,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(result.hints.map((hint) => hint.name), [
    "Alpha Cafe",
    "Bravo Hotel",
  ]);
  assertEquals(result.excludedCount, 1);

  const mixed = groundedHints(
    overCompleteCandidates,
    evidenceCatalog(evidence),
    [],
    150,
    postContext({
      intent: "mixed",
      declaredCount: 2,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(mixed.hints.map((hint) => hint.name), [
    "Alpha Cafe",
    "Bravo Hotel",
    "Charlie Park",
  ]);

  const unindexed = groundedHints(
    overCompleteCandidates.map((value) => ({ ...value, itemIndex: -1 })),
    evidenceCatalog(evidence),
    [],
  );
  assertEquals(unindexed.hints.map((hint) => hint.name), [
    "Charlie Park",
    "Alpha Cafe",
    "Bravo Hotel",
  ]);

  const underCount = groundedHints(
    [candidate({
      name: "Alpha Cafe",
      area: "",
      modality: "caption",
      evidenceIds: ["caption:0"],
      itemIndex: 0,
    })],
    evidenceCatalog(evidence),
    [],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 2,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(underCount.hints.map((hint) => hint.name), ["Alpha Cafe"]);
});

Deno.test("declared count requires count semantics or the complete numbered list", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: [
      "1. Alpha Cafe",
      "2. Bravo Hotel",
      "3. Charlie Park",
      "Bonus: Delta Museum",
    ].join("\n"),
    taggedLocations: [],
    media: [],
  };
  const candidates = [
    ["Alpha Cafe", 0],
    ["Bravo Hotel", 1],
    ["Charlie Park", 2],
    ["Delta Museum", 3],
  ].map(([name, itemIndex]) =>
    candidate({
      name: String(name),
      area: "",
      modality: "caption",
      evidenceIds: ["caption:0"],
      itemIndex: Number(itemIndex),
    })
  );

  const bareMarker = groundedHints(
    candidates,
    evidenceCatalog(evidence),
    [],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 1,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(bareMarker.hints.map((hint) => hint.name), [
    "Alpha Cafe",
    "Bravo Hotel",
    "Charlie Park",
    "Delta Museum",
  ]);

  const completeNumberedList = groundedHints(
    candidates,
    evidenceCatalog(evidence),
    [],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 3,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(completeNumberedList.hints.map((hint) => hint.name), [
    "Alpha Cafe",
    "Bravo Hotel",
    "Charlie Park",
  ]);
});

Deno.test("Gemini response validation rejects missing fields and additional properties", () => {
  const valid = parseGeminiCandidates(
    geminiPayload([candidate({ name: "Hotel Bel-Air" })]),
  );
  assertEquals(valid.length, 1);
  assertErrorCode(
    () =>
      parseGeminiCandidates(geminiPayload([{ ...candidate({}), extra: "no" }])),
    "gemini_invalid_schema",
  );
  const missing = candidate({}) as unknown as Record<string, unknown>;
  delete missing.evidenceIds;
  assertErrorCode(
    () => parseGeminiCandidates(geminiPayload([missing])),
    "gemini_invalid_schema",
  );
});

Deno.test("Gemini parser accepts structured post context and defaults legacy test payloads safely", () => {
  const structured = parseGeminiUnderstanding(geminiPayload(
    [candidate({
      name: "The Stonehaus",
      area: "Westlake Village",
      itemIndex: 6,
    })],
    postContext({
      intent: "place_list",
      declaredCount: 8,
      declaredCountEvidenceIds: ["media:0"],
      globalArea: "Los Angeles",
      globalAreaEvidenceIds: ["caption:0"],
    }),
  ));
  assertEquals(structured.postContext.intent, "place_list");
  assertEquals(structured.postContext.declaredCount, 8);
  assertEquals(structured.candidates[0].entityType, "poi");
  assertEquals(structured.candidates[0].itemIndex, 6);

  const legacy = parseGeminiUnderstanding(geminiPayload([{
    ...candidate({ name: "Legacy Place" }),
    entityType: undefined,
    itemIndex: undefined,
  }]));
  assertEquals(legacy.postContext, postContext());
  assertEquals(legacy.candidates[0].entityType, "unknown");
  assertEquals(legacy.candidates[0].itemIndex, -1);

  for (const missingField of ["entityType", "itemIndex"] as const) {
    const missing = candidate({
      name: `Structured missing ${missingField}`,
    }) as unknown as Record<string, unknown>;
    delete missing[missingField];
    assertErrorCode(
      () =>
        parseGeminiUnderstanding(
          geminiPayload([missing], postContext()),
        ),
      "gemini_invalid_schema",
    );
  }
});

Deno.test("media URL policy blocks SSRF and strips Apify authorization on redirect", async () => {
  assertErrorCode(
    () => validatedMediaURL("https://127.0.0.1/image.jpg"),
    "unsafe_media_url",
  );
  assertErrorCode(
    () => validatedMediaURL("https://localhost/image.jpg"),
    "unsafe_media_url",
  );
  const privateURL =
    "https://api.apify.com/v2/key-value-stores/store-1/records/video.mp4";
  assert(mayReceiveApifyAuthorization(new URL(privateURL)));
  const observed: Array<{ url: string; authorization: string | null }> = [];
  const dependencies = runtime((input, init) => {
    const url = String(input);
    observed.push({
      url,
      authorization: new Headers(init?.headers).get("authorization"),
    });
    if (url === privateURL) {
      return new Response(null, {
        status: 302,
        headers: { location: mediaURL },
      });
    }
    if (url === mediaURL) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    throw new Error(`unexpected fetch ${url}`);
  });
  const result = await fetchMediaBytes(
    privateURL,
    "image",
    100,
    requiredSource(instagramURL),
    "apify-secret",
    new Deadline(10_000, dependencies.now),
    dependencies,
  );
  assertEquals(result.mimeType, "image/jpeg");
  assertEquals(observed, [
    { url: privateURL, authorization: "Bearer apify-secret" },
    { url: mediaURL, authorization: null },
  ]);
});

Deno.test("media policy rejects cross-host unsafe redirects and MIME masquerading", async () => {
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url === mediaURL) {
      return new Response(null, {
        status: 302,
        headers: { location: "https://evil.example/private" },
      });
    }
    throw new Error("unsafe redirect destination must never be fetched");
  });
  await assertRejectsCode(
    () =>
      fetchMediaBytes(
        mediaURL,
        "image",
        100,
        requiredSource(instagramURL),
        "apify-secret",
        new Deadline(10_000, dependencies.now),
        dependencies,
      ),
    "unsafe_media_url",
  );

  const htmlDependencies = runtime(() =>
    new Response("<html>not an image</html>", {
      headers: { "content-type": "image/jpeg" },
    })
  );
  await assertRejectsCode(
    () =>
      fetchMediaBytes(
        mediaURL,
        "image",
        100,
        requiredSource(instagramURL),
        "apify-secret",
        new Deadline(10_000, htmlDependencies.now),
        htmlDependencies,
      ),
    "unverified_media_type",
  );
});

async function runOutcomeScenario(
  candidates: ModelCandidate[],
  mediaSucceeds: boolean,
  datasetOverrides: Record<string, unknown> = {},
  context?: ModelPostContext,
): Promise<Record<string, unknown>> {
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/")) {
      return Response.json({
        data: {
          id: "run-1",
          status: "SUCCEEDED",
          defaultDatasetId: "dataset-1",
        },
      });
    }
    if (url.includes("/v2/datasets/")) {
      return Response.json([{
        inputUrl: instagramURL,
        description: "An ordinary caption without a destination name.",
        images: [mediaURL],
        ...datasetOverrides,
      }]);
    }
    if (url === mediaURL) {
      return mediaSucceeds
        ? new Response(jpeg, { headers: { "content-type": "image/jpeg" } })
        : new Response(null, { status: 503 });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      return geminiResponse(candidates, context);
    }
    throw new Error(`unexpected fetch ${url}`);
  });
  return await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json() as Record<string, unknown>;
}

type TestFetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Response | Promise<Response>;

type RuntimeOptions = {
  admission?: {
    admitted: boolean;
    decision:
      | "started"
      | "disabled"
      | "duplicate"
      | "replay_required"
      | "busy"
      | "quota";
    admission_id: string | null;
  };
  beginStatus?: number;
  finishStatus?: number;
  onBegin?: (headers: Headers, body: unknown) => void;
  onFinish?: (headers: Headers, body: unknown) => void;
};

function runtime(
  fetcher: TestFetcher,
  options: RuntimeOptions = {},
): RuntimeDependencies {
  const values: Record<string, string> = {
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_PUBLISHABLE_KEY: "publishable-key",
    WANDER_APIFY_TOKEN: "apify-secret",
    WANDER_GEMINI_API_KEY: "gemini-secret",
  };
  return {
    fetch: ((input, init) => {
      const url = String(input);
      const headers = new Headers(init?.headers);
      if (url.endsWith("/rest/v1/rpc/begin_social_import_paid_work")) {
        const body = JSON.parse(String(init?.body ?? "{}"));
        options.onBegin?.(headers, body);
        if (options.beginStatus && options.beginStatus !== 200) {
          return Promise.resolve(Response.json({}, {
            status: options.beginStatus,
          }));
        }
        return Promise.resolve(Response.json([
          options.admission ?? {
            admitted: true,
            decision: "started",
            admission_id: admissionID,
          },
        ]));
      }
      if (url.endsWith("/rest/v1/rpc/finish_social_import_paid_work")) {
        const body = JSON.parse(String(init?.body ?? "{}"));
        options.onFinish?.(headers, body);
        if (options.finishStatus && options.finishStatus !== 200) {
          return Promise.resolve(Response.json({}, {
            status: options.finishStatus,
          }));
        }
        return Promise.resolve(Response.json(true));
      }
      return Promise.resolve(fetcher(input, init));
    }) as typeof fetch,
    env: (name) => values[name],
    now: () => 1_000,
    sleep: async () => {},
    random: () => 0,
  };
}

function authenticatedOnly(input: RequestInfo | URL): Response {
  const url = String(input);
  if (url.endsWith("/rest/v1/rpc/current_profile")) {
    return Response.json([{ id: "user-1" }]);
  }
  throw new Error(`unexpected fetch ${url}`);
}

function jsonRequest(
  body: unknown,
  authorization: string | null = "Bearer user-token",
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (authorization) headers.set("authorization", authorization);
  return new Request("https://function.test", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function socialRequestBody(
  url: string,
  platform: "instagram" | "tiktok" = "instagram",
): Record<string, unknown> {
  return {
    schema_version: 1,
    platform,
    url,
    client_request_id: "stable-request-id",
  };
}

function requiredSource(value: string): SocialSource {
  const source = parseSocialSource(value);
  if (!source) throw new Error(`invalid fixture source ${value}`);
  return source;
}

function candidate(overrides: Partial<ModelCandidate> = {}): ModelCandidate {
  return {
    name: "Carbon Beach Club",
    area: "Malibu",
    entityType: "poi",
    itemIndex: -1,
    classification: "destination",
    modality: "caption",
    evidenceIds: ["caption:0"],
    confidence: 0.91,
    startMs: -1,
    endMs: -1,
    ...overrides,
  };
}

function postContext(
  overrides: Partial<ModelPostContext> = {},
): ModelPostContext {
  return {
    intent: "unknown",
    declaredCount: -1,
    declaredCountEvidenceIds: [],
    globalArea: "",
    globalAreaEvidenceIds: [],
    ...overrides,
  };
}

function successfulMediaIngestion(
  kind: "image" | "video",
): {
  mediaID: string;
  kind: "image" | "video";
  status: "ok";
  byteCount: number;
  mimeType: string;
  errorCode: null;
} {
  return {
    mediaID: "media:0",
    kind,
    status: "ok",
    byteCount: jpeg.byteLength,
    mimeType: kind === "image" ? "image/jpeg" : "video/mp4",
    errorCode: null,
  };
}

function geminiResponse(
  candidates: unknown[],
  context?: ModelPostContext,
): Response {
  return Response.json(geminiPayload(candidates, context));
}

function geminiPayload(
  candidates: unknown[],
  context?: ModelPostContext,
): unknown {
  const payload = context === undefined
    ? { candidates }
    : { postContext: context, candidates };
  return {
    candidates: [{
      content: { parts: [{ text: JSON.stringify(payload) }] },
    }],
  };
}

function assertSafeResponse(payload: unknown, rawCaption: string): void {
  const serialized = JSON.stringify(payload);
  for (
    const forbidden of [
      "apify-secret",
      "gemini-secret",
      instagramURL,
      mediaURL,
      rawCaption,
      "defaultDatasetId",
      "provider detail must stay private",
    ]
  ) {
    assert(!serialized.includes(forbidden), `response leaked ${forbidden}`);
  }
}

function assertErrorCode(operation: () => unknown, expectedCode: string): void {
  try {
    operation();
  } catch (error) {
    assertEquals(
      error instanceof SocialImportError ? error.code : null,
      expectedCode,
    );
    return;
  }
  throw new Error(`Expected ${expectedCode}`);
}

async function assertRejectsCode(
  operation: () => Promise<unknown>,
  expectedCode: string,
): Promise<void> {
  try {
    await operation();
  } catch (error) {
    assertEquals(
      error instanceof SocialImportError ? error.code : null,
      expectedCode,
    );
    return;
  }
  throw new Error(`Expected ${expectedCode}`);
}

function assert(
  value: unknown,
  message = "Expected condition to be true",
): asserts value {
  if (!value) throw new Error(message);
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
