import { apifyActorRequest, normalizeApifyDataset } from "./apify.ts";
import {
  deterministicFallbackHints,
  evidenceCatalog,
  groundedHints,
  maximumGroundingCandidateInputs,
  mergeInstagramProfileAliases,
  minimumGroundedConfidence,
  primaryCaptionProfileAliasHints,
  prioritizedCaptionProfileUsernames,
  prioritizedInstagramProfileUsernames,
  profileAliasCandidates,
  recommendedCaptionHandles,
  taggedProfileCandidates,
} from "./evidence.ts";
import { parseGeminiCandidates, parseGeminiUnderstanding } from "./gemini.ts";
import {
  handleRequest,
  maximumExtractionDurationMilliseconds,
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
  MediaIngestion,
  ModelCandidate,
  ModelMediaAssessment,
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
const seventeenHotelProfiles = [
  ["thebrandoresort", "The Brando"],
  ["shebararesort", "Shebara"],
  ["joalimaldives", "JOALI Maldives"],
  ["shintamaniwild", "Shinta Mani Wild"],
  ["bawahreserve", "Bawah Reserve"],
  ["nujumareserve", "Nujuma, a Ritz-Carlton Reserve"],
  ["songsaa", "Song Saa Private Island"],
  ["nayarabocas", "Nayara Bocas del Toro"],
  ["kudadoo", "Kudadoo Maldives Private Island"],
  ["arcticbath", "Arctic Bath"],
  ["pumphousepoint", "Pumphouse Point"],
  ["misoolresort", "Misool Resort"],
  ["bluelagoonretreat", "The Retreat at Blue Lagoon Iceland"],
  ["brindoslac", "Brindos, Lac & Château"],
  ["vfriverlodge", "Victoria Falls River Lodge"],
  ["nimmobayresort", "Nimmo Bay Resort"],
  ["jaocamp", "Jao Camp"],
] as const;

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
    actor: "apify/instagram-scraper",
    input: { directUrls: [reel.url], resultsType: "posts", resultsLimit: 1 },
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
  const observedSeventeenPlaceExtractionMilliseconds = 107_000;
  assert(
    maximumExtractionDurationMilliseconds -
        observedSeventeenPlaceExtractionMilliseconds >= 10_000,
  );
  assert(
    maximumHandlerDurationMilliseconds -
        maximumExtractionDurationMilliseconds >= 15_000,
  );
  assert(maximumHandlerDurationMilliseconds <= 140_000);
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
        ["postContext", "candidates", "mediaAssessments"],
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
      assertEquals(
        requestBody.generationConfig.responseFormat.text.schema.properties
          .candidates.items.required.includes("sourceMention"),
        true,
      );
      assertEquals(
        requestBody.generationConfig.responseFormat.text.schema.properties
          .candidates.items.properties.modality.enum.includes(
            "tagged_profile",
          ),
        false,
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
      assertEquals(headers.get("authorization"), "Bearer service-role-key");
      assertEquals(headers.get("apikey"), "service-role-key");
      assertEquals(headers.get("authorization")?.includes("user-token"), false);
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

Deno.test("handler inventories every caption handle and safely synthesizes a venue", async () => {
  const caption =
    "An Ojai lunch at @hvojai. Photo by @creator. Thanks to local guide @travelpal.";
  const profileStarts: Array<Record<string, unknown>> = [];
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      return Response.json({
        data: {
          id: "post-run",
          status: "SUCCEEDED",
          defaultDatasetId: "post-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/post-dataset/items")) {
      return Response.json([{
        inputUrl: instagramURL,
        description: caption,
        images: [mediaURL],
      }]);
    }
    if (
      url.includes("/v2/actors/apify~instagram-profile-scraper/runs")
    ) {
      profileStarts.push(JSON.parse(String(init?.body)));
      return Response.json({
        data: {
          id: "profile-run",
          status: "SUCCEEDED",
          defaultDatasetId: "profile-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/profile-dataset/items")) {
      const datasetURL = new URL(url);
      assertEquals(
        datasetURL.searchParams.get("fields"),
        "username,fullName,businessCategoryName,isBusinessAccount",
      );
      return Response.json([{
        username: "hvojai",
        fullName: "Hip Vegan",
        biography: "must not reach Gemini or the response",
      }]);
    }
    if (url === mediaURL) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      const body = JSON.parse(String(init?.body));
      const parts = body.contents[0].parts as Array<Record<string, unknown>>;
      const task = JSON.parse(String(parts.at(-1)?.text));
      if (task.task === "extract_grounded_destinations") {
        assertEquals(task.caption_handle_identity_aliases, [{
          source_mention: "@hvojai",
          profile_name: "Hip Vegan",
        }]);
        assertEquals(
          task.caption_mention_inventory
            .filter((mention: { kind: string }) => mention.kind === "handle")
            .map((mention: { source_mention: string }) =>
              mention.source_mention
            ),
          ["@hvojai", "@creator", "@travelpal"],
        );
        assertEquals(JSON.stringify(task).includes("biography"), false);
      } else {
        assertEquals(task.task, "reconcile_grounded_destinations");
      }
      return geminiResponse([]);
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const response = await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  );
  const payload = await response.json();

  assertEquals(profileStarts, [{
    usernames: ["hvojai", "creator", "travelpal"],
    includeAboutSection: false,
  }]);
  assertEquals(payload.outcome, "partial");
  assertEquals(payload.failure_category, "grounding_incomplete");
  assertEquals(payload.hints.map((hint: { name: string }) => hint.name), [
    "Hip Vegan",
  ]);
  assertEquals(JSON.stringify(payload).includes("biography"), false);
});

Deno.test("handler enriches slide tags and recovers a complete declared venue list", async () => {
  const imageURLs = [
    "https://images.cdninstagram.com/media/tag-cover.jpg",
    "https://images.cdninstagram.com/media/tag-alpha.jpg",
    "https://images.cdninstagram.com/media/tag-bravo.jpg",
  ];
  const profileStarts: Array<Record<string, unknown>> = [];
  let geminiCalls = 0;
  const context = postContext({
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["media:0"],
  });
  const assessments = [
    {
      mediaEvidenceId: "media:0",
      disposition: "no_place_mentions",
      candidateItemIndexes: [],
    },
    {
      mediaEvidenceId: "media:1",
      disposition: "place_mentions",
      candidateItemIndexes: [0],
    },
    {
      mediaEvidenceId: "media:2",
      disposition: "place_mentions",
      candidateItemIndexes: [1],
    },
  ];
  const modelCandidates = [{
    ...candidate({
      name: "Alpha H0tel",
      sourceMention: "Alpha H0tel",
      itemIndex: 0,
      modality: "image_text",
      evidenceIds: ["media:1"],
    }),
  }, {
    ...candidate({
      name: "Bravo H0tel",
      sourceMention: "Bravo H0tel",
      itemIndex: 1,
      modality: "image_text",
      evidenceIds: ["media:2"],
    }),
  }];
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      return Response.json({
        data: {
          id: "tag-post-run",
          status: "SUCCEEDED",
          defaultDatasetId: "tag-post-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/tag-post-dataset/items")) {
      return Response.json([{
        inputUrl: instagramURL,
        childPosts: [{
          displayUrl: imageURLs[0],
        }, {
          displayUrl: imageURLs[1],
          taggedUsers: [{ username: "alpha_hotel", fullName: "Alpha Hotel" }],
        }, {
          displayUrl: imageURLs[2],
          taggedUsers: [{ username: "bravo_hotel", fullName: "Bravo Hotel" }],
        }],
      }]);
    }
    if (url.includes("/v2/actors/apify~instagram-profile-scraper/runs")) {
      profileStarts.push(JSON.parse(String(init?.body)));
      return Response.json({
        data: {
          id: "tag-profile-run",
          status: "SUCCEEDED",
          defaultDatasetId: "tag-profile-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/tag-profile-dataset/items")) {
      return Response.json([{
        username: "alpha_hotel",
        fullName: "Alpha Hotel",
      }]);
    }
    if (imageURLs.includes(url)) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      geminiCalls += 1;
      const body = JSON.parse(String(init?.body ?? "{}"));
      const parts = body.contents?.[0]?.parts as Array<Record<string, unknown>>;
      const task = JSON.parse(String(parts?.at(-1)?.text ?? "{}"));
      if (task.task === "extract_grounded_destinations") {
        assertEquals(task.caption_handle_identity_aliases, []);
        assertEquals(
          task.text_evidence.filter((item: { modality: string }) =>
            item.modality === "tagged_profile"
          ).map((item: { id: string; media_id: string }) => ({
            id: item.id,
            media_id: item.media_id,
          })),
          [{ id: "profile_tag:1:0", media_id: "media:1" }, {
            id: "profile_tag:2:0",
            media_id: "media:2",
          }],
        );
      } else {
        assertEquals(task.task, "reconcile_grounded_destinations");
      }
      return Response.json(
        geminiPayload(modelCandidates, context, assessments),
      );
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const payload = await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json();

  assertEquals(profileStarts, [{
    usernames: ["alpha_hotel", "bravo_hotel"],
    includeAboutSection: false,
  }]);
  assertEquals(geminiCalls, 2);
  assertEquals(payload.outcome, "ok");
  assertEquals(payload.failure_category, null);
  assertEquals(
    payload.hints.map((hint: { name: string }) => hint.name),
    ["Alpha Hotel", "Bravo Hotel"],
  );
  assertEquals(
    payload.hints.map((hint: { evidence_ids: string[] }) => hint.evidence_ids),
    [["profile_tag:1:0", "media:1"], ["profile_tag:2:0", "media:2"]],
  );
});

Deno.test("tagged recovery never clears an incomplete media-assessment ledger", async () => {
  const payload = await runTaggedRecoveryCoverageScenario({
    assessments: [{
      mediaEvidenceId: "media:0",
      disposition: "no_place_mentions",
      candidateItemIndexes: [],
    }, {
      mediaEvidenceId: "media:1",
      disposition: "place_mentions",
      candidateItemIndexes: [0],
    }],
  });

  assertEquals(payload.outcome, "partial");
  assertEquals(payload.failure_category, "grounding_incomplete");
  assertEquals(
    (payload.hints as Array<{ name: string }>).map((hint) => hint.name),
    ["Alpha Hotel", "Bravo Hotel"],
  );
});

Deno.test("tagged recovery never clears unassessed caption mentions", async () => {
  const payload = await runTaggedRecoveryCoverageScenario({
    caption: "Two hotels worth a trip. Photo by @creator.",
    assessments: completeTaggedRecoveryAssessments(),
  });

  assertEquals(payload.outcome, "partial");
  assertEquals(payload.failure_category, "grounding_incomplete");
  assertEquals(
    (payload.hints as Array<{ name: string }>).map((hint) => hint.name),
    ["Alpha Hotel", "Bravo Hotel"],
  );
});

Deno.test("profile enrichment failure is nonfatal to media and Gemini extraction", async () => {
  const caption = "An Ojai lunch at @hvojai.";
  let geminiCalls = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      return Response.json({
        data: {
          id: "post-run",
          status: "SUCCEEDED",
          defaultDatasetId: "post-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/post-dataset/items")) {
      return Response.json([{
        inputUrl: instagramURL,
        description: caption,
        images: [mediaURL],
      }]);
    }
    if (
      url.includes("/v2/actors/apify~instagram-profile-scraper/runs")
    ) {
      return Response.json({ error: "private provider detail" }, {
        status: 503,
      });
    }
    if (url === mediaURL) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      geminiCalls += 1;
      return geminiResponse([candidate({
        name: "hvojai",
        sourceMention: "@hvojai",
        area: "",
        classification: "itinerary",
        modality: "caption",
        evidenceIds: ["caption:0"],
      })]);
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const response = await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  );
  const payload = await response.json();

  assertEquals(payload.outcome, "ok");
  assertEquals(payload.failure_category, null);
  assertEquals(payload.hints.map((hint: { name: string }) => hint.name), [
    "hvojai",
  ]);
  assertEquals(geminiCalls, 1);
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

Deno.test("Gemini deadline fallback reuses resolved primary-list aliases and excludes secondary sections", async () => {
  const caption = [
    "TOP 3 PIZZAS IN LA",
    "1. @alphapizza",
    "2. @bravopizza",
    "3. @charliepizza",
    "Hon. Mentions:",
    "1. @backuppizza",
    "Credits:",
    "1. @camera",
    "Partners:",
    "1. @sponsor",
  ].join("\n");
  let geminiCalls = 0;
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      return Response.json({
        data: {
          id: "post-run",
          status: "SUCCEEDED",
          defaultDatasetId: "post-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/post-dataset/items")) {
      return Response.json([{
        inputUrl: instagramURL,
        description: caption,
        images: [mediaURL],
      }]);
    }
    if (
      url.includes("/v2/actors/apify~instagram-profile-scraper/runs")
    ) {
      return Response.json({
        data: {
          id: "profile-run",
          status: "SUCCEEDED",
          defaultDatasetId: "profile-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/profile-dataset/items")) {
      return Response.json([
        { username: "alphapizza", fullName: "Alpha Pizza" },
        { username: "bravopizza", fullName: "Bravo Pizza" },
        { username: "charliepizza", fullName: "Charlie Pizza" },
        { username: "backuppizza", fullName: "Backup Pizza" },
        { username: "camera", fullName: "Camera Person" },
        { username: "sponsor", fullName: "Sponsor Brand" },
      ]);
    }
    if (url === mediaURL) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      geminiCalls += 1;
      const body = JSON.parse(String(init?.body ?? "{}"));
      const parts = body.contents?.[0]?.parts as Array<Record<string, unknown>>;
      const task = JSON.parse(String(parts?.at(-1)?.text ?? "{}"));
      assertEquals(task.caption_handle_identity_aliases, [
        { source_mention: "@alphapizza", profile_name: "Alpha Pizza" },
        { source_mention: "@bravopizza", profile_name: "Bravo Pizza" },
        { source_mention: "@charliepizza", profile_name: "Charlie Pizza" },
        { source_mention: "@backuppizza", profile_name: "Backup Pizza" },
        { source_mention: "@camera", profile_name: "Camera Person" },
        { source_mention: "@sponsor", profile_name: "Sponsor Brand" },
      ]);
      throw new SocialImportError("deadline_exceeded", 1);
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const payload = await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json();

  assertEquals(geminiCalls, 1);
  assertEquals(payload.outcome, "partial");
  assertEquals(payload.provider_path, "apify_deterministic");
  assertEquals(payload.failure_category, "deadline_exceeded");
  assertEquals(payload.model_attempt_count, 1);
  assertEquals(payload.hints.map((hint: { name: string }) => hint.name), [
    "Alpha Pizza",
    "Bravo Pizza",
    "Charlie Pizza",
  ]);
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

Deno.test("paid-work admission cleanup still runs after the main deadline expires", async () => {
  let now = 1_000;
  let finishCount = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      now += maximumHandlerDurationMilliseconds + 1;
      return Response.json({
        data: {
          id: "run-1",
          status: "SUCCEEDED",
          defaultDatasetId: "dataset-1",
        },
      });
    }
    throw new Error(`unexpected fetch ${url}`);
  }, {
    onFinish: () => finishCount += 1,
  });
  dependencies.now = () => now;

  const payload = await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json();

  assertEquals(payload.outcome, "fallback");
  assertEquals(payload.failure_category, "deadline_exceeded");
  assertEquals(finishCount, 1);
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

Deno.test("missing service cleanup credentials fail closed before paid admission", async () => {
  let admissionCalls = 0;
  let providerCalls = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    providerCalls += 1;
    throw new Error("paid provider must not run without cleanup credentials");
  }, {
    environment: { SUPABASE_SERVICE_ROLE_KEY: undefined },
    onBegin: () => admissionCalls += 1,
  });

  const payload = await (await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  )).json();

  assertEquals(payload.outcome, "fallback");
  assertEquals(payload.failure_category, "configuration_unavailable");
  assertEquals(admissionCalls, 0);
  assertEquals(providerCalls, 0);
});

Deno.test("modern Supabase secret cleanup uses apikey without a bearer", async () => {
  let finishCalls = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      return Response.json({
        data: {
          id: "secret-key-run",
          status: "FAILED",
        },
      });
    }
    throw new Error(`unexpected fetch ${url}`);
  }, {
    environment: {
      SUPABASE_SERVICE_ROLE_KEY: undefined,
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: "sb_secret_server" }),
    },
    onFinish: (headers) => {
      finishCalls += 1;
      assertEquals(headers.get("apikey"), "sb_secret_server");
      assertEquals(headers.has("authorization"), false);
    },
  });

  await handleRequest(
    jsonRequest(socialRequestBody(instagramURL)),
    dependencies,
  );

  assertEquals(finishCalls, 1);
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

  const unassessedCaption = await runOutcomeScenario(
    [],
    true,
    { description: "Lunch at @hvojai." },
  );
  assertEquals(unassessedCaption.outcome, "partial");
  assertEquals(unassessedCaption.hints, []);
  assertEquals(
    unassessedCaption.failure_category,
    "grounding_incomplete",
  );

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

  const declaredAndGroundedDespiteFailedMedia = await runOutcomeScenario(
    [candidate({
      name: "Hotel Bel-Air",
      area: "Los Angeles, California",
      modality: "caption",
      evidenceIds: ["caption:0"],
    })],
    false,
    { description: "Top 1 place to visit: Hotel Bel-Air" },
    postContext({
      intent: "place_list",
      declaredCount: 1,
      declaredCountEvidenceIds: ["caption:0"],
      globalArea: "Los Angeles, California",
      globalAreaEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(declaredAndGroundedDespiteFailedMedia.outcome, "partial");
  assertEquals(
    (declaredAndGroundedDespiteFailedMedia.hints as unknown[]).length,
    1,
  );
  assertEquals(
    declaredAndGroundedDespiteFailedMedia.failure_category,
    "grounding_incomplete",
  );
  assertEquals(
    declaredAndGroundedDespiteFailedMedia.declared_count_complete,
    true,
  );

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

  const declaredButEmpty = await runOutcomeScenario(
    [],
    true,
    { description: "Top 1 place to visit: Hotel Bel-Air" },
    postContext({
      intent: "place_list",
      declaredCount: 1,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(declaredButEmpty.outcome, "partial");
  assertEquals(declaredButEmpty.hints, []);
  assertEquals(declaredButEmpty.failure_category, "grounding_incomplete");
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

Deno.test("post context demotes city context and caps to the declared count", () => {
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

Deno.test("enumerated geography destinations outrank supporting itinerary venues", () => {
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
        name: "Coronado Central Beach",
        area: "San Diego",
        entityType: "locality",
        classification: "destination",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Miguel's Cocina",
        area: "Coronado",
        entityType: "poi",
        classification: "itinerary",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "La Jolla Village",
        area: "San Diego",
        entityType: "locality",
        classification: "destination",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 1,
      }),
      candidate({
        name: "El Pescador Fish Market",
        area: "La Jolla",
        entityType: "poi",
        classification: "itinerary",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 1,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 2,
      declaredCountEvidenceIds: ["media:0"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "Coronado Central Beach",
    "La Jolla Village",
  ]);
  assertEquals(result.excludedCount, 2);
});

Deno.test("a place list can consist of enumerated regions", () => {
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
        name: "Raja Ampat",
        area: "Indonesia",
        entityType: "region",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Exuma Cays",
        area: "Bahamas",
        entityType: "region",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 1,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 2,
      declaredCountEvidenceIds: ["media:0"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "Raja Ampat",
    "Exuma Cays",
  ]);
});

Deno.test("an uncounted place list excludes a supporting destination locality", () => {
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
        name: "The Shore Room",
        area: "Reno",
        entityType: "poi",
        classification: "destination",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Reno",
        area: "Nevada",
        entityType: "locality",
        classification: "destination",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints.map((hint) => hint.name), ["The Shore Room"]);
  assertEquals(result.excludedCount, 1);
});

Deno.test("an unknown city duplicate is collapsed into its POI area", () => {
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
        name: "The Stonehaus",
        area: "Westlake Village",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Westlake Village",
        area: "California",
        entityType: "unknown",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints.map((hint) => hint.name), ["The Stonehaus"]);
  assertEquals(result.hints[0].area, "Westlake Village");
  assertEquals(result.excludedCount, 1);
});

Deno.test("a same-item city mislabeled as a POI folds into the venue without a declared count", () => {
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
        name: "The Stonehaus",
        area: "Westlake Village",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Westlake Village",
        area: "California",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints.map((hint) => hint.name), ["The Stonehaus"]);
  assertEquals(result.hints[0].area, "Westlake Village");
  assertEquals(result.excludedCount, 1);
});

Deno.test("a city mistyped as a POI cannot displace later places at the declared count", () => {
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
        name: "Westlake Village",
        area: "California",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "The Stonehaus",
        area: "Westlake Village",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 1,
      }),
      candidate({
        name: "Malibu Pier",
        area: "Malibu",
        entityType: "poi",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 2,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 2,
      declaredCountEvidenceIds: ["media:0"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "The Stonehaus",
    "Malibu Pier",
  ]);
  assertEquals(result.excludedCount, 1);
});

Deno.test("a single itinerary step keeps every explicitly offered destination", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption:
      "Drive straight to Rory’s Other Place or Highly Likely or Farmer and the Cook in Ojai.",
    taggedLocations: [],
    media: [],
  };
  const result = groundedHints(
    [
      candidate({
        name: "Rory’s Other Place",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Highly Likely",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Farmer and the Cook",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Ojai",
        area: "California",
        entityType: "locality",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
    ],
    evidenceCatalog(evidence),
    [],
    150,
    postContext({
      intent: "place_list",
      globalArea: "Ojai",
      globalAreaEvidenceIds: ["caption:0"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "Rory’s Other Place",
    "Highly Likely",
    "Farmer and the Cook",
  ]);
});

Deno.test("an uncounted same-item singular/plural spelling variant collapses", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: null,
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
  const result = groundedHints(
    [
      candidate({
        name: "Lower Yosemite Fall",
        area: "Yosemite National Park",
        modality: "video_text",
        evidenceIds: ["media:0"],
        itemIndex: 3,
        confidence: 0.97,
      }),
      candidate({
        name: "Lower Yosemite Falls",
        area: "Yosemite National Park",
        modality: "video_text",
        evidenceIds: ["media:0"],
        itemIndex: 3,
        confidence: 0.93,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("video")],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "Lower Yosemite Fall",
  ]);
  assertEquals(result.excludedCount, 1);
  assertEquals(result.expectedCount, null);
  assertEquals(result.missingExpectedCount, 0);
});

Deno.test("uncounted nested same-item alternatives survive spelling-variant dedupe", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: null,
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
  const result = groundedHints(
    [
      candidate({
        name: "Rory's Place",
        area: "Ojai",
        modality: "video_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Rory's Other Place",
        area: "Ojai",
        modality: "video_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Gjusta",
        area: "Venice",
        modality: "video_text",
        evidenceIds: ["media:0"],
        itemIndex: 1,
      }),
      candidate({
        name: "Gjusta Goods",
        area: "Venice",
        modality: "video_text",
        evidenceIds: ["media:0"],
        itemIndex: 1,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("video")],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "Rory's Place",
    "Rory's Other Place",
    "Gjusta",
    "Gjusta Goods",
  ]);
  assertEquals(result.excludedCount, 0);
});

Deno.test("Ojai itinerary preserves canonical venue-handle names as distinct destinations", () => {
  const caption = [
    "A perfect 24 hours in Ojai!",
    "⭑ drive in in the morning straight to Rory’s Other Place or @itshighlylikely for caffeine and pastries OR breakfast at @farmerandthecookojai",
    "⭑ walk around the main street (stop at @bartsbooksojai), grab lunch at @thedutchessojai, @ojairotie or @hvojai",
    "⭑ check in at @caprihotel_ojai_official",
    "⭑ explore Ventura Riverhead Trailhead/Wheeler Gorge Nature Trail, swim in a swimming hole",
    "⭑ early dinner at @rorys_place_ojai so you can catch sunset at @meditationmount!!!",
    "#ojai #venturacounty #ojaicalifornia",
  ].join("\n");
  const expected = [
    "Rory’s Other Place",
    "Highly Likely",
    "Farmer and the Cook",
    "Bart’s Books",
    "The Dutchess",
    "Ojai Rôtie",
    "Hip Vegan",
    "Capri Hotel",
    "Ventura Riverhead Trailhead",
    "Wheeler Gorge Nature Trail",
    "Rory’s Place",
    "Meditation Mount",
  ];
  const sourceMentions = [
    "Rory’s Other Place",
    "@itshighlylikely",
    "@farmerandthecookojai",
    "@bartsbooksojai",
    "@thedutchessojai",
    "@ojairotie",
    "@hvojai",
    "@caprihotel_ojai_official",
    "Ventura Riverhead Trailhead",
    "Wheeler Gorge Nature Trail",
    "@rorys_place_ojai",
    "@meditationmount",
  ];
  const modeledCandidates = expected.map((name, itemIndex) =>
    candidate({
      name,
      sourceMention: sourceMentions[itemIndex],
      area: "",
      classification: sourceMentions[itemIndex].startsWith("@")
        ? "attribution"
        : "itinerary",
      modality: "caption",
      evidenceIds: ["caption:0"],
      itemIndex,
    })
  );
  modeledCandidates.push(candidate({
    name: "Unrelated Invented Cafe",
    sourceMention: "@bartsbooksojai",
    area: "",
    classification: "attribution",
    modality: "caption",
    evidenceIds: ["caption:0"],
    itemIndex: 12,
  }));
  const profileAliases = [
    { username: "itshighlylikely", fullName: "Highly Likely" },
    { username: "farmerandthecookojai", fullName: "Farmer and the Cook" },
    { username: "bartsbooksojai", fullName: "Bart’s Books" },
    { username: "thedutchessojai", fullName: "The Dutchess" },
    { username: "ojairotie", fullName: "Ojai Rôtie" },
    { username: "hvojai", fullName: "Hip Vegan" },
    { username: "caprihotel_ojai_official", fullName: "Capri Hotel" },
    { username: "rorys_place_ojai", fullName: "Rory’s Place" },
    { username: "meditationmount", fullName: "Meditation Mount" },
  ];
  const result = groundedHints(
    modeledCandidates,
    evidenceCatalog({
      title: null,
      caption,
      taggedLocations: [],
      media: [],
    }),
    [],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 24,
      declaredCountEvidenceIds: ["caption:0"],
      globalArea: "Ojai, California",
      globalAreaEvidenceIds: ["caption:0"],
    }),
    profileAliases,
  );

  assertEquals(result.hints.map((hint) => hint.name), expected);
  assertEquals(
    result.hints.map((hint) => hint.area),
    expected.map(() => "Ojai, California"),
  );
  assertEquals(result.rejectedCount, 0);
  assertEquals(result.excludedCount, 1);
});

Deno.test("caption creator handles fail venue grammar even when labeled destinations", () => {
  const result = groundedHints(
    [
      candidate({
        name: "Travel Pal",
        sourceMention: "@travelpal",
        area: "",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Creator",
        sourceMention: "@creator",
        area: "",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 1,
      }),
    ],
    evidenceCatalog({
      title: null,
      caption:
        "Visit Hotel Bel-Air. Thanks to our local guide @travelpal. Photo by @creator.",
      taggedLocations: [],
      media: [],
    }),
    [],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints, []);
  assertEquals(result.rejectedCount, 2);
});

Deno.test("profile aliases canonically synthesize recommended handles but never creator credits", () => {
  const caption =
    "An Ojai lunch at @hvojai or @bartsbooksojai. Photo by @creator. Thanks to local guide @travelpal. #ojaicalifornia";
  const catalog = evidenceCatalog({
    title: null,
    caption,
    taggedLocations: [],
    media: [],
  });
  const aliases = [
    { username: "hvojai", fullName: "Hip Vegan" },
    { username: "bartsbooksojai", fullName: "Bart’s Books" },
    { username: "creator", fullName: "Caption Creator" },
    { username: "travelpal", fullName: "Travel Pal" },
  ];

  assertEquals(recommendedCaptionHandles(caption), [
    "hvojai",
    "bartsbooksojai",
  ]);
  const synthetic = profileAliasCandidates(aliases, catalog);
  assertEquals(synthetic.map((candidate) => candidate.name), [
    "Hip Vegan",
    "Bart’s Books",
  ]);
  const result = groundedHints(
    [
      candidate({
        name: "hvojai",
        sourceMention: "@hvojai",
        area: "",
        classification: "itinerary",
        modality: "caption",
        evidenceIds: ["caption:0"],
        confidence: 0.99,
        itemIndex: 0,
      }),
      ...synthetic,
    ],
    catalog,
    [],
    150,
    postContext({
      intent: "place_list",
      globalArea: "Ojai, California",
      globalAreaEvidenceIds: ["caption:0"],
    }),
    aliases,
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "Hip Vegan",
    "Bart’s Books",
  ]);
  assertEquals(result.hints.map((hint) => hint.area), [
    "Ojai, California",
    "Ojai, California",
  ]);
});

Deno.test("primary caption alias fallback requires unique aliases and keeps source order", () => {
  const caption = [
    "TOP 4 PIZZAS IN LA",
    "1. @alphapizza",
    "2. @bravopizza",
    "3. @alphapizza",
    "4. @ambiguouspizza",
    "Hon. Mentions:",
    "1. @backuppizza",
    "Credits:",
    "1. @camera",
    "Partners:",
    "1. @sponsor",
  ].join("\n");
  const catalog = evidenceCatalog({
    title: null,
    caption,
    taggedLocations: [],
    media: [],
  });
  const hints = primaryCaptionProfileAliasHints(catalog, [
    { username: "alphapizza", fullName: "Alpha Pizza" },
    { username: "bravopizza", fullName: "Bravo Pizza" },
    { username: "ambiguouspizza", fullName: "Ambiguous Pizza" },
    { username: "ambiguouspizza", fullName: "Different Pizza" },
    { username: "backuppizza", fullName: "Backup Pizza" },
    { username: "camera", fullName: "Camera Person" },
    { username: "sponsor", fullName: "Sponsor Brand" },
  ]);

  assertEquals(hints.map((hint) => hint.name), [
    "Alpha Pizza",
    "Bravo Pizza",
  ]);
  assertEquals(hints.map((hint) => hint.evidence_ids), [
    ["caption:0"],
    ["caption:0"],
  ]);
});

Deno.test("deterministic fallback preserves tagged and numbered hints while merging primary aliases", () => {
  const catalog = evidenceCatalog({
    title: null,
    caption: [
      "TOP 3 PIZZAS IN LA",
      "1. @alphapizza",
      "2. Existing Named Place",
      "3. @bravopizza",
      "Hon. Mentions:",
      "1. @backuppizza",
      "Credits:",
      "1. @camera",
      "Partners:",
      "1. @sponsor",
    ].join("\n"),
    taggedLocations: [{ name: "Alpha Pizza", area: "Los Angeles" }],
    media: [],
  });
  const hints = deterministicFallbackHints(catalog, 150, [
    { username: "alphapizza", fullName: "Alpha Pizza" },
    { username: "bravopizza", fullName: "Bravo Pizza" },
    { username: "backuppizza", fullName: "Backup Pizza" },
    { username: "camera", fullName: "Camera Person" },
    { username: "sponsor", fullName: "Sponsor Brand" },
  ]);

  assertEquals(hints.map((hint) => hint.name), [
    "Alpha Pizza",
    "Existing Named Place",
    "Bravo Pizza",
  ]);
  assertEquals(hints.map((hint) => hint.classification), [
    "destination",
    "itinerary",
    "itinerary",
  ]);
  assertEquals(hints[0].area, "Los Angeles");
});

Deno.test("venue handles are prioritized ahead of early credits at the profile cap", () => {
  const credits = Array.from(
    { length: 20 },
    (_, index) => `Photo by @credit${index + 1}`,
  );
  const usernames = prioritizedCaptionProfileUsernames([
    ...credits,
    "Lunch at @actual_venue",
  ].join("\n"));

  assertEquals(usernames.length, 20);
  assertEquals(usernames[0], "actual_venue");
  assertEquals(usernames.includes("credit20"), false);
});

Deno.test("media profile tags stay scoped metadata and never become deterministic location fallbacks", () => {
  const evidence = taggedCarouselEvidence(seventeenHotelProfiles.slice(0, 2));
  const catalog = evidenceCatalog(evidence);
  const profileTexts = catalog.texts.filter((text) =>
    text.modality === "tagged_profile"
  );

  assertEquals(evidence.media[0].taggedProfiles, undefined);
  assertEquals(
    profileTexts.map((text) => ({
      id: text.id,
      text: text.text,
      mediaID: text.mediaID,
    })),
    [{
      id: "profile_tag:1:0",
      text: "The Brando (@thebrandoresort)",
      mediaID: "media:1",
    }, {
      id: "profile_tag:2:0",
      text: "Shebara (@shebararesort)",
      mediaID: "media:2",
    }],
  );
  assertEquals(deterministicFallbackHints(catalog), []);
});

Deno.test("slide tags take profile-cap priority and fresh aliases tolerate display-name changes", () => {
  const caption = [
    "Lunch at @captionvenue",
    "Photo by @creditone",
    "Thanks to @credittwo",
    "Partners: @creditthree",
  ].join("\n");
  const evidence = taggedCarouselEvidence(seventeenHotelProfiles, caption);
  const usernames = prioritizedInstagramProfileUsernames(evidence);

  assertEquals(
    usernames.slice(0, 17),
    seventeenHotelProfiles.map(([username]) => username),
  );
  assertEquals(usernames.length, 20);
  assertEquals(usernames[17], "captionvenue");

  const mergeEvidence = taggedCarouselEvidence([
    ["alpha", "Alpha Café"],
    ["bravo", "Bravo Hotel"],
    ["conflict", "Embedded Identity"],
  ]);
  assertEquals(
    mergeInstagramProfileAliases([{
      username: "alpha",
      fullName: "Alpha Cafe",
    }, {
      username: "conflict",
      fullName: "Different Identity",
    }], mergeEvidence),
    [{
      username: "alpha",
      fullName: "Alpha Cafe",
    }, {
      username: "bravo",
      fullName: "Bravo Hotel",
    }, {
      username: "conflict",
      fullName: "Different Identity",
    }],
  );
});

Deno.test("a cover plus seventeen uniquely tagged hotel slides recovers seventeen ordered hints", () => {
  const evidence = taggedCarouselEvidence(seventeenHotelProfiles);
  const catalog = evidenceCatalog(evidence);
  const ingestions = successfulCarouselIngestions(evidence);
  const aliases = mergeInstagramProfileAliases([], evidence);
  const context = postContext({
    intent: "place_list",
    declaredCount: 17,
    declaredCountEvidenceIds: ["media:0"],
  });
  const recovered = taggedProfileCandidates(
    aliases,
    catalog,
    ingestions,
    context,
    ...taggedRecoveryModelConclusions(evidence),
  );

  assertEquals(recovered.length, 17);
  assertEquals(
    recovered.map((item) => item.name),
    seventeenHotelProfiles.map(([, name]) => name),
  );
  assertEquals(
    recovered.map((item) => item.itemIndex),
    Array.from({ length: 17 }, (_, index) => index),
  );
  assertEquals(
    recovered.map((item) => item.evidenceIds),
    Array.from({ length: 17 }, (_, index) => [
      `profile_tag:${index + 1}:0`,
    ]),
  );
  assertEquals(
    recovered.every((item) => item.modality === "tagged_profile"),
    true,
  );

  const grounded = groundedHints(
    recovered,
    catalog,
    ingestions,
    150,
    context,
    aliases,
  );
  assertEquals(
    grounded.hints.map((hint) => hint.name),
    seventeenHotelProfiles.map(([, name]) => name),
  );
  assertEquals(
    grounded.hints.every((hint) => hint.modality === "image_text"),
    true,
  );
  assertEquals(grounded.expectedCount, 17);
  assertEquals(grounded.missingExpectedCount, 0);
});

Deno.test("trusted hotel tags replace five bad model rows without duplicates or filler", () => {
  const evidence = taggedCarouselEvidence(seventeenHotelProfiles);
  const catalog = evidenceCatalog(evidence);
  const ingestions = successfulCarouselIngestions(evidence);
  const aliases = mergeInstagramProfileAliases([], evidence);
  const context = postContext({
    intent: "place_list",
    declaredCount: 17,
    declaredCountEvidenceIds: ["media:0"],
  });
  const recovered = taggedProfileCandidates(
    aliases,
    catalog,
    ingestions,
    context,
    ...taggedRecoveryModelConclusions(evidence),
  );
  const badModelRows = [
    ["night", 0, "media:1"],
    ["Lake St Clair", 10, "media:11"],
    ["NIMMO BAY RESORT 1978 Broughton Blvd", 15, "media:16"],
    ["NIMMO BAY RESORT British Columbia", 15, "media:16"],
    ["Post Creator", 17, "media:17"],
  ] as const;
  const result = groundedHints(
    [
      ...recovered,
      ...badModelRows.map(([name, itemIndex, evidenceID]) =>
        candidate({
          name,
          sourceMention: name,
          area: "",
          itemIndex,
          modality: "image_text",
          evidenceIds: [evidenceID],
        })
      ),
    ],
    catalog,
    ingestions,
    150,
    context,
    aliases,
  );

  assertEquals(
    result.hints.map((hint) => hint.name),
    seventeenHotelProfiles.map(([, name]) => name),
  );
  assertEquals(
    result.hints.filter((hint) => hint.name === "Nimmo Bay Resort").length,
    1,
  );
  assertEquals(result.hints.some((hint) => hint.name === "night"), false);
  assertEquals(
    result.hints.some((hint) => hint.name === "Lake St Clair"),
    false,
  );
  assertEquals(
    result.hints.some((hint) => hint.name === "Pumphouse Point"),
    true,
  );
});

Deno.test("tagged recovery rejects an unrelated same-slide person tag", () => {
  const evidence = taggedCarouselEvidence([
    ["ava_stone", "Ava Stone"],
    ["bravo_hotel", "Bravo Hotel"],
  ]);
  const aliases = mergeInstagramProfileAliases([], evidence);
  const [candidates, assessments] = taggedRecoveryModelConclusions(evidence);
  candidates[0] = {
    ...candidates[0],
    name: "Actual OCR Venue",
    sourceMention: "Actual OCR Venue",
  };

  assertEquals(
    taggedProfileCandidates(
      aliases,
      evidenceCatalog(evidence),
      successfulCarouselIngestions(evidence),
      postContext({
        intent: "place_list",
        declaredCount: 2,
        declaredCountEvidenceIds: ["media:0"],
      }),
      candidates,
      assessments,
    ),
    [],
  );

  const matchingCandidates = taggedRecoveryModelConclusions(evidence)[0];
  const creatorAliases = aliases.map((alias, index) =>
    index === 0
      ? {
        ...alias,
        businessCategoryName: "Digital Creator",
        isBusinessAccount: true,
      }
      : alias
  );
  assertEquals(
    taggedProfileCandidates(
      creatorAliases,
      evidenceCatalog(evidence),
      successfulCarouselIngestions(evidence),
      postContext({
        intent: "place_list",
        declaredCount: 2,
        declaredCountEvidenceIds: ["media:0"],
      }),
      matchingCandidates,
      assessments,
    ),
    [],
  );
});

Deno.test("tagged recovery accepts bounded OCR and profile-name corrections", () => {
  const profiles = [
    ["alpha_hotel", "Alpha Hotel"],
    ["pumphousepoint", "Pumphouse Point"],
  ] as const;
  const evidence = taggedCarouselEvidence(profiles);
  const [candidates, assessments] = taggedRecoveryModelConclusions(evidence);
  candidates[0] = {
    ...candidates[0],
    name: "Alpha H0tel",
    sourceMention: "Alpha H0tel",
  };
  candidates[1] = {
    ...candidates[1],
    name: "Pumphouse Pt.",
    sourceMention: "Pumphouse Pt.",
  };

  const recovered = taggedProfileCandidates(
    mergeInstagramProfileAliases([], evidence),
    evidenceCatalog(evidence),
    successfulCarouselIngestions(evidence),
    postContext({
      intent: "place_list",
      declaredCount: 2,
      declaredCountEvidenceIds: ["media:0"],
    }),
    candidates,
    assessments,
  );

  assertEquals(recovered.map((item) => item.name), [
    "Alpha Hotel",
    "Pumphouse Point",
  ]);
});

Deno.test("tagged-profile recovery fails closed outside the exact declared-list shape", () => {
  const evidence = taggedCarouselEvidence(seventeenHotelProfiles);
  const catalog = evidenceCatalog(evidence);
  const ingestions = successfulCarouselIngestions(evidence);
  const aliases = mergeInstagramProfileAliases([], evidence);
  const validContext = postContext({
    intent: "place_list",
    declaredCount: 17,
    declaredCountEvidenceIds: ["media:0"],
  });
  const recover = (
    testEvidence: AcquisitionEvidence,
    testAliases = aliases,
    testIngestions = ingestions,
    context = validContext,
  ) =>
    taggedProfileCandidates(
      testAliases,
      evidenceCatalog(testEvidence),
      testIngestions,
      context,
      ...taggedRecoveryModelConclusions(testEvidence),
    );

  assertEquals(
    recover(
      evidence,
      aliases,
      ingestions,
      { ...validContext, intent: "unknown" },
    ),
    [],
  );
  assertEquals(
    recover(
      evidence,
      aliases,
      ingestions,
      { ...validContext, declaredCount: 16 },
    ),
    [],
  );
  assertEquals(
    recover(
      evidence,
      aliases,
      ingestions,
      { ...validContext, declaredCountEvidenceIds: ["profile_tag:1:0"] },
    ),
    [],
  );
  assertEquals(recover(evidence, aliases.slice(0, 16)), []);

  const [acceptedCandidates, acceptedAssessments] =
    taggedRecoveryModelConclusions(evidence);
  const noPlaceAssessments = acceptedAssessments.map((assessment) =>
    assessment.mediaEvidenceId === "media:1"
      ? {
        ...assessment,
        disposition: "no_place_mentions" as const,
        candidateItemIndexes: [],
      }
      : assessment
  );
  assertEquals(
    taggedProfileCandidates(
      aliases,
      catalog,
      ingestions,
      validContext,
      acceptedCandidates,
      noPlaceAssessments,
    ),
    [],
  );

  const attributionCandidates = acceptedCandidates.map((item, index) =>
    index === 0
      ? {
        ...item,
        sourceMention: `@${seventeenHotelProfiles[0][0]}`,
        evidenceIds: ["profile_tag:1:0"],
        classification: "attribution" as const,
      }
      : item
  );
  assertEquals(
    taggedProfileCandidates(
      aliases,
      catalog,
      ingestions,
      validContext,
      attributionCandidates,
      acceptedAssessments,
    ),
    [],
  );

  const photographerAliases = aliases.map((alias, index) =>
    index === 0 ? { ...alias, businessCategoryName: "Photographer" } : alias
  );
  assertEquals(
    taggedProfileCandidates(
      photographerAliases,
      catalog,
      ingestions,
      validContext,
      acceptedCandidates,
      acceptedAssessments,
    ),
    [],
  );

  const duplicateAliasNames = aliases.map((alias, index) =>
    index === 1 ? { ...alias, fullName: aliases[0].fullName } : alias
  );
  assertEquals(recover(evidence, duplicateAliasNames), []);

  const failedIngestions = ingestions.map((ingestion, index) =>
    index === 4
      ? { ...ingestion, status: "failed" as const, errorCode: "fetch_failed" }
      : ingestion
  );
  assertEquals(recover(evidence, aliases, failedIngestions), []);

  const multipleTags = structuredClone(evidence);
  multipleTags.media[1].taggedProfiles?.push({
    username: "second_profile",
    fullName: "Second Profile",
  });
  assertEquals(recover(multipleTags), []);

  const repeatedProfile = structuredClone(evidence);
  repeatedProfile.media[17].taggedProfiles = [{
    username: seventeenHotelProfiles[0][0],
    fullName: seventeenHotelProfiles[0][1],
  }];
  assertEquals(recover(repeatedProfile), []);

  const onePlace = taggedCarouselEvidence(seventeenHotelProfiles.slice(0, 1));
  assertEquals(
    taggedProfileCandidates(
      mergeInstagramProfileAliases([], onePlace),
      evidenceCatalog(onePlace),
      successfulCarouselIngestions(onePlace),
      postContext({
        intent: "place_list",
        declaredCount: 1,
        declaredCountEvidenceIds: ["media:0"],
      }),
      ...taggedRecoveryModelConclusions(onePlace),
    ),
    [],
  );
});

Deno.test("a profile alias and model venue dedupe across area and item-index differences", () => {
  const aliases = [{ username: "hvojai", fullName: "Hip Vegan" }];
  const catalog = evidenceCatalog({
    title: null,
    caption: "Lunch at @hvojai in Ojai, California.",
    taggedLocations: [],
    media: [],
  });
  const result = groundedHints(
    [
      candidate({
        name: "Hip Vegan",
        sourceMention: "@hvojai",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 5,
      }),
      ...profileAliasCandidates(aliases, catalog),
    ],
    catalog,
    [],
    150,
    postContext({
      intent: "place_list",
      globalArea: "Ojai, California",
      globalAreaEvidenceIds: ["caption:0"],
    }),
    aliases,
  );

  assertEquals(result.hints.map((hint) => hint.name), ["Hip Vegan"]);
  assertEquals(result.hints[0].area, "Ojai, California");
  assertEquals(result.excludedCount, 1);
});

Deno.test("caption handle grammar supports meal lists and dotted alternatives without credit false positives", () => {
  const aliases = [
    { username: "hvojai", fullName: "Hip Vegan" },
    { username: "bartsbooksojai", fullName: "Bart’s Books" },
    { username: "foo.bar", fullName: "Foo Bar Cafe" },
    { username: "baz", fullName: "Baz Bakery" },
    { username: "creator", fullName: "Caption Creator" },
  ];
  const mealCaption = "Lunch: @hvojai or @bartsbooksojai";
  assertEquals(recommendedCaptionHandles(mealCaption), [
    "hvojai",
    "bartsbooksojai",
  ]);
  assertEquals(
    profileAliasCandidates(
      aliases,
      evidenceCatalog({
        title: null,
        caption: mealCaption,
        taggedLocations: [],
        media: [],
      }),
    ).map((candidate) => candidate.name),
    ["Hip Vegan", "Bart’s Books"],
  );

  const dottedCaption = "Lunch at @foo.bar or @baz";
  assertEquals(recommendedCaptionHandles(dottedCaption), ["foo.bar", "baz"]);

  for (
    const creditCaption of [
      "Huge shoutout to @creator",
      "Credit goes to @creator",
      "Thanks so much to @creator",
    ]
  ) {
    assertEquals(recommendedCaptionHandles(creditCaption), []);
    assertEquals(
      profileAliasCandidates(
        aliases,
        evidenceCatalog({
          title: null,
          caption: creditCaption,
          taggedLocations: [],
          media: [],
        }),
      ),
      [],
    );
  }
});

Deno.test("caption handle grammar supports venue headings, standalone lists, and physical from phrases", () => {
  assertEquals(
    recommendedCaptionHandles("Restaurants: @alpha or @bravo"),
    ["alpha", "bravo"],
  );
  assertEquals(
    recommendedCaptionHandles([
      "Restaurants:",
      "• @alpha",
      "• @bravo",
    ].join("\n")),
    ["alpha", "bravo"],
  );
  assertEquals(
    recommendedCaptionHandles("Grab coffee from @cafe"),
    ["cafe"],
  );
  assertEquals(recommendedCaptionHandles("Photos from @creator"), []);
});

Deno.test("a digital creator call to action cannot become a synthetic venue", () => {
  const caption = "Visit @travelblog for more Ojai tips.";
  const catalog = evidenceCatalog({
    title: null,
    caption,
    taggedLocations: [],
    media: [],
  });
  const aliases = [{ username: "travelblog", fullName: "Travel Blog" }];

  assertEquals(recommendedCaptionHandles(caption), []);
  assertEquals(profileAliasCandidates(aliases, catalog), []);
  const result = groundedHints(
    [candidate({
      name: "Travel Blog",
      sourceMention: "@travelblog",
      area: "",
      classification: "destination",
      modality: "caption",
      evidenceIds: ["caption:0"],
      itemIndex: 0,
    })],
    catalog,
    [],
    150,
    postContext({ intent: "place_list" }),
    aliases,
  );

  assertEquals(result.hints, []);
  assertEquals(result.rejectedCount, 1);
});

Deno.test("model-accepted caption handles need exact evidence but not fallback venue grammar", () => {
  const caption = "This one blew me away: @hiddenjem. Photo by @creator.";
  const catalog = evidenceCatalog({
    title: null,
    caption,
    taggedLocations: [],
    media: [],
  });
  const aliases = [
    { username: "hiddenjem", fullName: "Hidden Jem Cafe" },
    { username: "creator", fullName: "Caption Creator" },
  ];

  // Neither handle is safe for deterministic synthesis: the first needs the
  // model's destination judgment and the second is an explicit credit.
  assertEquals(recommendedCaptionHandles(caption), []);
  assertEquals(profileAliasCandidates(aliases, catalog), []);
  const result = groundedHints(
    [
      candidate({
        name: "Hidden Jem Cafe",
        sourceMention: "@hiddenjem",
        area: "",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Caption Creator",
        sourceMention: "@creator",
        area: "",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 1,
      }),
    ],
    catalog,
    [],
    150,
    postContext({ intent: "place_list" }),
    aliases,
  );

  assertEquals(result.hints.map((hint) => hint.name), ["Hidden Jem Cafe"]);
  assertEquals(result.rejectedCount, 1);
});

Deno.test("a literal handle fallback cannot replace a human model name", () => {
  const caption = "• @oomoonlightbasin";
  const evidence: AcquisitionEvidence = {
    title: null,
    caption,
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
        name: "One&Only Moonlight Basin",
        sourceMention: "One&Only Moonlight Basin",
        area: "Big Sky, Montana",
        classification: "destination",
        modality: "image_text",
        evidenceIds: ["media:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "One&Only Moonlight Basin",
        sourceMention: "@oomoonlightbasin",
        area: "",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
    ],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 1,
      declaredCountEvidenceIds: ["media:0"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "One&Only Moonlight Basin",
  ]);
  assertEquals(result.excludedCount, 1);
});

Deno.test("media-attested caption handles preserve the model venue name and area", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: "• @oomoonlightbasin",
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
    [candidate({
      name: "One&Only Moonlight Basin",
      sourceMention: "@oomoonlightbasin",
      area: "Big Sky, Montana",
      classification: "destination",
      modality: "caption",
      evidenceIds: ["caption:0", "media:0"],
      itemIndex: 0,
    })],
    evidenceCatalog(evidence),
    [successfulMediaIngestion("image")],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints.map((hint) => [hint.name, hint.area]), [[
    "One&Only Moonlight Basin",
    "Big Sky, Montana",
  ]]);
});

Deno.test("model-accepted caption handles still reject compact creator-credit labels", () => {
  for (
    const caption of [
      "Photo: @creator",
      "Video: @creator",
      "Credit: @creator",
      "Photo credit — @creator",
      "📷 @creator",
      "📸 @creator",
      "🎥 @creator",
    ]
  ) {
    const result = groundedHints(
      [candidate({
        name: "Caption Creator",
        sourceMention: "@creator",
        area: "",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      })],
      evidenceCatalog({
        title: null,
        caption,
        taggedLocations: [],
        media: [],
      }),
      [],
      150,
      postContext({ intent: "place_list" }),
      [{ username: "creator", fullName: "Caption Creator" }],
    );

    assertEquals(result.hints, []);
    assertEquals(result.rejectedCount, 1);
  }
});

Deno.test("the same venue handle remains distinct when the caption names different areas", () => {
  const caption =
    "Dinner at @bluebird in Los Angeles or dinner at @bluebird in New York.";
  const aliases = [{ username: "bluebird", fullName: "Bluebird Cafe" }];
  const result = groundedHints(
    [
      candidate({
        name: "Bluebird Cafe",
        sourceMention: "@bluebird",
        area: "Los Angeles",
        classification: "itinerary",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Bluebird Cafe",
        sourceMention: "@bluebird",
        area: "New York",
        classification: "itinerary",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 1,
      }),
    ],
    evidenceCatalog({
      title: null,
      caption,
      taggedLocations: [],
      media: [],
    }),
    [],
    150,
    postContext({ intent: "place_list" }),
    aliases,
  );

  assertEquals(result.hints.map((hint) => [hint.name, hint.area]), [
    ["Bluebird Cafe", "Los Angeles"],
    ["Bluebird Cafe", "New York"],
  ]);
  assertEquals(result.excludedCount, 0);
});

Deno.test("caption venue-handle promotion is exact and never applies to alt text", () => {
  const result = groundedHints(
    [
      candidate({
        name: "Travel Pal",
        sourceMention: "@travelpal",
        area: "",
        classification: "attribution",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Ojai Guide",
        sourceMention: "@ojaiguide",
        area: "",
        classification: "attribution",
        modality: "alt_text",
        evidenceIds: ["alt_text:0"],
        itemIndex: 1,
      }),
    ],
    evidenceCatalog({
      title: null,
      caption: "Visit @travelpal_official.",
      taggedLocations: [],
      media: [{
        id: "media:0",
        index: 0,
        kind: "image",
        url: mediaURL,
        thumbnailURL: null,
        altText: "Visit @ojaiguide",
      }],
    }),
    [],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints, []);
  assertEquals(result.intentionalExcludedCount, 2);
});

Deno.test("unsupported handle expansions fall back to the exact provider query", () => {
  const result = groundedHints(
    [
      candidate({
        name: "Happy Valley",
        sourceMention: "@hvojai",
        area: "Ojai",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Bluebird",
        sourceMention: "@bluebird_pasadena",
        area: "Pasadena",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 1,
      }),
    ],
    evidenceCatalog({
      title: null,
      caption: "Lunch at @hvojai or @bluebird_pasadena in Ojai.",
      taggedLocations: [],
      media: [],
    }),
    [],
    150,
    postContext({
      intent: "place_list",
      globalArea: "Ojai",
      globalAreaEvidenceIds: ["caption:0"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "hvojai",
    "bluebird_pasadena",
  ]);
  assertEquals(
    result.hints.some((hint) => hint.name === "Happy Valley"),
    false,
  );
  assertEquals(result.hints.some((hint) => hint.name === "Bluebird"), false);
});

Deno.test("a bounded handle abbreviation supports only the equivalent venue name", () => {
  const caption = "Visit @SixthFlrMuseum.";
  const catalog = evidenceCatalog({
    title: null,
    caption,
    taggedLocations: [],
    media: [],
  });
  const grounded = groundedHints(
    [candidate({
      name: "The Sixth Floor Museum",
      sourceMention: "@SixthFlrMuseum",
      area: "Dallas",
      classification: "destination",
      modality: "caption",
      evidenceIds: ["caption:0"],
    })],
    catalog,
    [],
    150,
    postContext({ intent: "place_list" }),
  );
  const unsupported = groundedHints(
    [candidate({
      name: "The Sixth Flower Museum",
      sourceMention: "@SixthFlrMuseum",
      area: "Dallas",
      classification: "destination",
      modality: "caption",
      evidenceIds: ["caption:0"],
    })],
    catalog,
    [],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(grounded.hints.map((hint) => hint.name), [
    "The Sixth Floor Museum",
  ]);
  assertEquals(unsupported.hints.map((hint) => hint.name), [
    "SixthFlrMuseum",
  ]);
});

Deno.test("a profile alias preserves a bounded provider-ready canonical venue name", () => {
  const caption = "Visit @SixthFlrMuseum in Dallas.";
  const aliases = [{
    username: "sixthflrmuseum",
    fullName: "Sixth Floor Museum",
  }];
  const catalog = evidenceCatalog({
    title: null,
    caption,
    taggedLocations: [],
    media: [],
  });
  const result = groundedHints(
    [
      candidate({
        name: "The Sixth Floor Museum at Dealey Plaza",
        sourceMention: "@SixthFlrMuseum",
        area: "Dallas",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      ...profileAliasCandidates(aliases, catalog),
    ],
    catalog,
    [],
    150,
    postContext({ intent: "place_list" }),
    aliases,
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "The Sixth Floor Museum at Dealey Plaza",
  ]);
  assertEquals(result.excludedCount, 1);
});

Deno.test("a profile alias cannot ground unrelated or unbounded handle expansions", () => {
  const caption = "Visit @SixthFlrMuseum in Dallas.";
  const catalog = evidenceCatalog({
    title: null,
    caption,
    taggedLocations: [],
    media: [],
  });
  const aliases = [{
    username: "sixthflrmuseum",
    fullName: "Sixth Floor Museum",
  }];
  const run = (name: string) =>
    groundedHints(
      [candidate({
        name,
        sourceMention: "@SixthFlrMuseum",
        area: "Dallas",
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      })],
      catalog,
      [],
      150,
      postContext({ intent: "place_list" }),
      aliases,
    );

  for (
    const unsupportedName of [
      "The Perot Museum at Dealey Plaza",
      "Fake Sixth Floor Museum at Dealey Plaza",
      "The Sixth Floor Museum and Wizard Academy",
      "The Sixth Floor Museum Casino",
      "The Sixth Floor Museum at",
      "The Sixth Floor Museum at Dealey Plaza and Wizard Academy",
    ]
  ) {
    assertEquals(run(unsupportedName).hints.map((hint) => hint.name), [
      "SixthFlrMuseum",
    ]);
  }
});

Deno.test("abbreviated honorable mentions cannot promote caption handles", () => {
  const caption = "TOP 10 PIZZAS IN LA\nHon. Mentions to @parkpizzala";
  const result = groundedHints(
    [candidate({
      name: "Park Pizza",
      sourceMention: "@parkpizzala",
      area: "Los Angeles",
      classification: "destination",
      modality: "caption",
      evidenceIds: ["caption:0"],
    })],
    evidenceCatalog({
      title: null,
      caption,
      taggedLocations: [],
      media: [],
    }),
    [],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(recommendedCaptionHandles(caption), []);
  assertEquals(result.hints, []);
  assertEquals(result.rejectedCount, 1);
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

Deno.test("declared count caps extras and reports missing destinations", () => {
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
  assertEquals(result.expectedCount, 2);
  assertEquals(result.missingExpectedCount, 0);

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
  ]);
  assertEquals(mixed.expectedCount, 2);

  const unknownIntent = groundedHints(
    overCompleteCandidates,
    evidenceCatalog(evidence),
    [],
    150,
    postContext({
      intent: "unknown",
      declaredCount: 2,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );
  assertEquals(unknownIntent.hints.map((hint) => hint.name), [
    "Alpha Cafe",
    "Bravo Hotel",
  ]);
  assertEquals(unknownIntent.expectedCount, 2);

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
  assertEquals(underCount.expectedCount, 2);
  assertEquals(underCount.missingExpectedCount, 1);
});

Deno.test("declared primary counts exclude supporting itinerary rows", () => {
  const primaryNames = Array.from(
    { length: 6 },
    (_, index) => `Primary Venue ${index + 1}`,
  );
  const supportingNames = ["Hotel Restaurant", "Nearby Coffee Shop"];
  const allNames = [...primaryNames, ...supportingNames];
  const caption = ["8 PLACES", ...allNames].join("\n");
  const candidates = allNames.map((name, itemIndex) =>
    candidate({
      name,
      area: "",
      itemIndex,
      classification: itemIndex < primaryNames.length
        ? "destination"
        : "itinerary",
      modality: "caption",
      evidenceIds: ["caption:0"],
    })
  );
  const result = groundedHints(
    candidates,
    evidenceCatalog({
      title: null,
      caption,
      taggedLocations: [],
      media: [],
    }),
    [],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 8,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), primaryNames);
  assertEquals(result.expectedCount, 8);
  assertEquals(result.missingExpectedCount, 2);
  assertEquals(result.excludedCount, 2);
});

Deno.test("grounding inspects the complete bounded handler candidate composition", () => {
  const finalName = "Last Deterministic Alias";
  const catalog = evidenceCatalog({
    title: null,
    caption: finalName,
    taggedLocations: [],
    media: [],
  });
  const candidates = Array.from(
    { length: maximumGroundingCandidateInputs - 1 },
    (_, index) =>
      candidate({
        name: `Rejected ${index}`,
        sourceMention: `Rejected ${index}`,
        evidenceIds: ["missing:evidence"],
      }),
  );
  candidates.push(candidate({
    name: finalName,
    sourceMention: finalName,
    evidenceIds: ["caption:0"],
  }));

  const result = groundedHints(candidates, catalog, [], 150);

  assertEquals(result.hints.map((hint) => hint.name), [finalName]);
});

Deno.test("generic list titles ground counts but durations and slide counts do not", () => {
  const names = Array.from(
    { length: 11 },
    (_, index) => `Venue ${index + 1}`,
  );
  const candidates = names.map((name, itemIndex) =>
    candidate({
      name,
      area: "",
      modality: "caption",
      evidenceIds: ["caption:0"],
      itemIndex,
    })
  );
  const run = (title: string) => {
    const caption = [
      title,
      ...names.map((name, index) => `${index + 1}. ${name}`),
    ].join("\n");
    return groundedHints(
      candidates,
      evidenceCatalog({
        title: null,
        caption,
        taggedLocations: [],
        media: [],
      }),
      [],
      150,
      postContext({
        intent: "place_list",
        declaredCount: 10,
        declaredCountEvidenceIds: ["caption:0"],
      }),
    );
  };

  for (
    const title of [
      "10 RESTAURANTS",
      "10 TOTALLY TEXAS THINGS",
      "TOP 10 PIZZAS IN LOS ANGELES",
    ]
  ) {
    const result = run(title);
    assertEquals(result.expectedCount, 10);
    assertEquals(result.hints.length, 10);
  }

  for (
    const title of [
      "10 DAYS IN TEXAS",
      "10 INSTAGRAM SLIDES",
      "10 DAYS OF RESTAURANTS",
      "10 SLIDES OF RESTAURANTS",
    ]
  ) {
    const result = run(title);
    assertEquals(result.expectedCount, null);
    assertEquals(result.hints.length, 11);
  }
});

Deno.test("cross-source support for one indexed item cannot consume the final declared-count slot", () => {
  const names = Array.from(
    { length: 20 },
    (_, index) => `Venue ${index + 1}`,
  );
  const caption = [
    "20 PLACES",
    ...names.map((name, index) => `${index + 1}. ${name}`),
  ].join("\n");
  const captionCandidates = names.map((name, itemIndex) =>
    candidate({
      name,
      sourceMention: name,
      area: "",
      itemIndex,
      classification: "destination",
      modality: "caption",
      evidenceIds: ["caption:0"],
      confidence: 0.91,
    })
  );
  const videoSupport = candidate({
    name: names[4],
    sourceMention: names[4],
    area: "Los Angeles",
    itemIndex: 4,
    classification: "destination",
    modality: "video_text",
    evidenceIds: ["media:0"],
    confidence: 0.97,
    startMs: 1_000,
    endMs: 2_000,
  });
  const result = groundedHints(
    [
      ...captionCandidates.slice(0, 5),
      videoSupport,
      ...captionCandidates.slice(5),
    ],
    evidenceCatalog({
      title: null,
      caption,
      taggedLocations: [],
      media: [{
        id: "media:0",
        index: 0,
        kind: "video",
        url: mediaURL,
        thumbnailURL: null,
        altText: null,
      }],
    }),
    [successfulMediaIngestion("video")],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 20,
      declaredCountEvidenceIds: ["caption:0"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), names);
  assertEquals(result.hints.length, 20);
  assertEquals(result.hints.at(-1)?.name, "Venue 20");
  assertEquals([...result.hints[4].evidence_ids].sort(), [
    "caption:0",
    "media:0",
  ]);
  assertEquals(result.hints[4].area, "Los Angeles");
  assertEquals(result.hints[4].confidence, 0.97);
  assertEquals(result.hints[4].start_ms, 1_000);
  assertEquals(result.hints[4].end_ms, 2_000);
  assertEquals(result.excludedCount, 1);
  assertEquals(result.missingExpectedCount, 0);
});

Deno.test("timestamp-qualified video evidence IDs canonicalize to the exact media asset", () => {
  const catalog = evidenceCatalog({
    title: null,
    caption: null,
    taggedLocations: [],
    media: [{
      id: "media:0",
      index: 0,
      kind: "video",
      url: mediaURL,
      thumbnailURL: null,
      altText: null,
    }],
  });
  const result = groundedHints(
    [candidate({
      name: "Cafe Nido",
      sourceMention: "2. Cafe Nido",
      area: "Los Angeles",
      modality: "video_text",
      evidenceIds: ["media:0.00:02.500"],
      itemIndex: 0,
    })],
    catalog,
    [successfulMediaIngestion("video")],
    150,
    postContext({
      intent: "place_list",
      declaredCount: 1,
      declaredCountEvidenceIds: ["media:0.00:00.000"],
    }),
  );

  assertEquals(result.hints.map((hint) => hint.name), ["Cafe Nido"]);
  assertEquals(result.hints[0].evidence_ids, ["media:0"]);
  assertEquals(result.expectedCount, 1);
  assertEquals(result.missingExpectedCount, 0);

  const invalid = groundedHints(
    [candidate({
      name: "Invented Cafe",
      sourceMention: "Invented Cafe",
      modality: "video_text",
      evidenceIds: ["media:0.not-a-timestamp"],
    })],
    catalog,
    [successfulMediaIngestion("video")],
  );
  assertEquals(invalid.hints, []);
  assertEquals(invalid.rejectedCount, 1);
});

Deno.test("one caption handle can identify two explicitly distinct venues", () => {
  const caption =
    "Choose Rory's Place or Rory's Other Place @rorys_place_ojai in Ojai.";
  const result = groundedHints(
    [
      candidate({
        name: "Rory's Place",
        sourceMention: "@rorys_place_ojai",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Rory's Other Place",
        sourceMention: "@rorys_place_ojai",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 1,
      }),
    ],
    evidenceCatalog({
      title: null,
      caption,
      taggedLocations: [],
      media: [],
    }),
    [],
    150,
    postContext({ intent: "place_list" }),
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "Rory's Place",
    "Rory's Other Place",
  ]);
});

Deno.test("a literal handle fallback cannot erase a distinct venue sharing that handle", () => {
  const caption =
    "Choose Rory's Other Place @rorys_place_ojai or Rory's Place in Ojai.";
  const result = groundedHints(
    [
      candidate({
        name: "rorys_place_ojai",
        sourceMention: "@rorys_place_ojai",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
      candidate({
        name: "Rory's Other Place",
        sourceMention: "@rorys_place_ojai",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 1,
      }),
      candidate({
        name: "Rory's Place",
        sourceMention: "@rorys_place_ojai",
        area: "Ojai",
        modality: "caption",
        evidenceIds: ["caption:0"],
        itemIndex: 0,
      }),
    ],
    evidenceCatalog({
      title: null,
      caption,
      taggedLocations: [],
      media: [],
    }),
    [],
    150,
    postContext({ intent: "place_list" }),
    [{ username: "rorys_place_ojai", fullName: "Rory's Place" }],
  );

  assertEquals(result.hints.map((hint) => hint.name), [
    "Rory's Place",
    "Rory's Other Place",
  ]);
});

Deno.test("numbered itinerary steps do not cap multiple venue options", () => {
  const evidence: AcquisitionEvidence = {
    title: null,
    caption: [
      "1. Breakfast at Alpha Cafe or Bravo Hotel",
      "2. Dinner at Charlie Park or Delta Museum",
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

  const result = groundedHints(
    candidates,
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
    "Charlie Park",
    "Delta Museum",
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
  assertEquals(structured.candidates[0].sourceMention, "The Stonehaus");

  const legacyCandidate = candidate({
    name: "Legacy Place",
  }) as unknown as Record<string, unknown>;
  delete legacyCandidate.sourceMention;
  legacyCandidate.entityType = undefined;
  legacyCandidate.itemIndex = undefined;
  const legacy = parseGeminiUnderstanding(geminiPayload([legacyCandidate]));
  assertEquals(legacy.postContext, postContext());
  assertEquals(legacy.candidates[0].entityType, "unknown");
  assertEquals(legacy.candidates[0].itemIndex, -1);
  assertEquals(legacy.candidates[0].sourceMention, "Legacy Place");

  for (
    const missingField of ["sourceMention", "entityType", "itemIndex"] as const
  ) {
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

function completeTaggedRecoveryAssessments(): Array<Record<string, unknown>> {
  return [{
    mediaEvidenceId: "media:0",
    disposition: "no_place_mentions",
    candidateItemIndexes: [],
  }, {
    mediaEvidenceId: "media:1",
    disposition: "place_mentions",
    candidateItemIndexes: [0],
  }, {
    mediaEvidenceId: "media:2",
    disposition: "place_mentions",
    candidateItemIndexes: [1],
  }];
}

function taggedRecoveryModelConclusions(
  evidence: AcquisitionEvidence,
): [ModelCandidate[], ModelMediaAssessment[]] {
  const candidates: ModelCandidate[] = [];
  const assessments: ModelMediaAssessment[] = [];
  for (const media of evidence.media) {
    const profile = media.taggedProfiles?.length === 1
      ? media.taggedProfiles[0]
      : null;
    if (!profile) {
      assessments.push({
        mediaEvidenceId: media.id,
        disposition: "no_place_mentions",
        candidateItemIndexes: [],
      });
      continue;
    }
    const itemIndex = candidates.length;
    candidates.push(candidate({
      name: profile.fullName ?? profile.username,
      sourceMention: profile.fullName ?? `@${profile.username}`,
      itemIndex,
      modality: "image_text",
      evidenceIds: [media.id],
    }));
    assessments.push({
      mediaEvidenceId: media.id,
      disposition: "place_mentions",
      candidateItemIndexes: [itemIndex],
    });
  }
  return [candidates, assessments];
}

async function runTaggedRecoveryCoverageScenario(options: {
  assessments: Array<Record<string, unknown>>;
  caption?: string;
}): Promise<Record<string, unknown>> {
  const imageURLs = [
    "https://images.cdninstagram.com/media/coverage-cover.jpg",
    "https://images.cdninstagram.com/media/coverage-alpha.jpg",
    "https://images.cdninstagram.com/media/coverage-bravo.jpg",
  ];
  const context = postContext({
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["media:0"],
  });
  const modelCandidates = [
    candidate({
      name: "Alpha Hotel",
      sourceMention: "Alpha Hotel",
      itemIndex: 0,
      modality: "image_text",
      evidenceIds: ["media:1"],
    }),
    candidate({
      name: "Bravo Hotel",
      sourceMention: "Bravo Hotel",
      itemIndex: 1,
      modality: "image_text",
      evidenceIds: ["media:2"],
    }),
  ];
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      return Response.json({
        data: {
          id: "coverage-post-run",
          status: "SUCCEEDED",
          defaultDatasetId: "coverage-post-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/coverage-post-dataset/items")) {
      return Response.json([{
        inputUrl: instagramURL,
        ...(options.caption ? { description: options.caption } : {}),
        childPosts: [{
          displayUrl: imageURLs[0],
        }, {
          displayUrl: imageURLs[1],
          taggedUsers: [{ username: "alpha_hotel", fullName: "Alpha Hotel" }],
        }, {
          displayUrl: imageURLs[2],
          taggedUsers: [{ username: "bravo_hotel", fullName: "Bravo Hotel" }],
        }],
      }]);
    }
    if (url.includes("/v2/actors/apify~instagram-profile-scraper/runs")) {
      return Response.json({
        data: {
          id: "coverage-profile-run",
          status: "SUCCEEDED",
          defaultDatasetId: "coverage-profile-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/coverage-profile-dataset/items")) {
      return Response.json([]);
    }
    if (imageURLs.includes(url)) {
      return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      return Response.json(
        geminiPayload(modelCandidates, context, options.assessments),
      );
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
  environment?: Record<string, string | undefined>;
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
    SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
    WANDER_APIFY_TOKEN: "apify-secret",
    WANDER_GEMINI_API_KEY: "gemini-secret",
    WANDER_GOOGLE_PLACES_API_KEY: "google-secret",
  };
  for (const [name, value] of Object.entries(options.environment ?? {})) {
    if (value === undefined) delete values[name];
    else values[name] = value;
  }
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
      if (
        url.endsWith("/rest/v1/rpc/finish_social_import_paid_work_service")
      ) {
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

function taggedCarouselEvidence(
  profiles: ReadonlyArray<readonly [string, string]>,
  caption: string | null = null,
): AcquisitionEvidence {
  return {
    title: null,
    caption,
    taggedLocations: [],
    media: [
      {
        id: "media:0",
        index: 0,
        kind: "image",
        url: "https://images.cdninstagram.com/media/hotel-cover.jpg",
        thumbnailURL: null,
        altText: "17 hotels worth traveling for",
      },
      ...profiles.map(([username, fullName], index) => ({
        id: `media:${index + 1}`,
        index: index + 1,
        kind: "image" as const,
        url: `https://images.cdninstagram.com/media/hotel-slide-${
          index + 1
        }.jpg`,
        thumbnailURL: null,
        altText: null,
        taggedProfiles: [{ username, fullName }],
      })),
    ],
  };
}

function successfulCarouselIngestions(
  evidence: AcquisitionEvidence,
): MediaIngestion[] {
  return evidence.media.map((media) => ({
    mediaID: media.id,
    kind: media.kind,
    status: "ok" as const,
    byteCount: jpeg.byteLength,
    mimeType: media.kind === "image" ? "image/jpeg" : "video/mp4",
    errorCode: null,
  }));
}

function candidate(overrides: Partial<ModelCandidate> = {}): ModelCandidate {
  const name = overrides.name ?? "Carbon Beach Club";
  const sourceMention = overrides.sourceMention ?? name;
  return {
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
    name,
    sourceMention,
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
  return Response.json(geminiPayload(
    candidates,
    context ?? postContext(),
    [{
      mediaEvidenceId: "media:0",
      disposition: "no_place_mentions",
      candidateItemIndexes: [],
    }],
  ));
}

function geminiPayload(
  candidates: unknown[],
  context?: ModelPostContext,
  mediaAssessments?: unknown[],
): unknown {
  const payload = context === undefined
    ? { candidates }
    : mediaAssessments === undefined
    ? { postContext: context, candidates }
    : { postContext: context, candidates, mediaAssessments };
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
