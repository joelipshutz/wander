import {
  maximumConcurrentGeminiImageUploads,
  maximumGeminiFileUploadTimeoutMilliseconds,
  maximumGeminiSemanticPasses,
  maximumInlineImageBytes,
  selectInlineImageIngestions,
  understandWithGemini,
  validatedGeminiUploadURL,
} from "./gemini.ts";
import type {
  EvidenceCatalog,
  MediaIngestion,
  ModelMediaAssessment,
  RuntimeDependencies,
  SocialSource,
} from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

const geminiOrigin = "https://generativelanguage.googleapis.com";
const uploadURL =
  `${geminiOrigin}/upload/v1beta/files?upload_id=session-123&upload_protocol=resumable`;
const fileName = "files/video-123";
const fileURI = `${geminiOrigin}/v1beta/${fileName}`;

Deno.test("Gemini gives bounded large video uploads a full network minute", () => {
  assertEquals(maximumGeminiFileUploadTimeoutMilliseconds, 60_000);
});

Deno.test("Gemini uploads and polls videos, references fileData, then deletes the file", async () => {
  const calls: string[] = [];
  const generatedBodies: Record<string, unknown>[] = [];
  const dependencies = runtime((input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const headers = new Headers(init?.headers);
    if (url === `${geminiOrigin}/upload/v1beta/files`) {
      calls.push("start");
      assertEquals(method, "POST");
      assertEquals(init?.redirect, "error");
      assertEquals(headers.get("x-goog-api-key"), "gemini-secret");
      assertEquals(headers.get("x-goog-upload-command"), "start");
      assertEquals(
        headers.get("x-goog-upload-header-content-type"),
        "video/mp4",
      );
      return new Response(null, {
        headers: { "x-goog-upload-url": uploadURL },
      });
    }
    if (url === uploadURL) {
      calls.push("upload");
      assertEquals(method, "POST");
      assertEquals(init?.redirect, "error");
      assertEquals(headers.get("x-goog-upload-command"), "upload, finalize");
      assert(init?.body instanceof Uint8Array);
      return Response.json({
        file: {
          name: fileName,
          uri: fileURI,
          state: "PROCESSING",
        },
      });
    }
    if (url === fileURI && method === "GET") {
      calls.push("poll");
      assertEquals(init?.redirect, "error");
      assertEquals(headers.get("x-goog-api-key"), "gemini-secret");
      return Response.json({
        name: fileName,
        uri: fileURI,
        state: "ACTIVE",
      });
    }
    if (url.includes(":generateContent")) {
      calls.push("generate");
      assertEquals(init?.redirect, "error");
      generatedBodies.push(JSON.parse(String(init?.body)));
      return geminiUnderstandingResponse(
        {
          intent: "unknown",
          declaredCount: -1,
          declaredCountEvidenceIds: [],
          globalArea: "",
          globalAreaEvidenceIds: [],
        },
        [],
        [mediaAssessment("media:0")],
        {
          promptTokenCount: 100,
          cachedContentTokenCount: 10,
          candidatesTokenCount: 20,
          thoughtsTokenCount: 5,
          totalTokenCount: 125,
        },
      );
    }
    if (url === fileURI && method === "DELETE") {
      calls.push("delete");
      assertEquals(init?.redirect, "error");
      assertEquals(headers.get("x-goog-api-key"), "gemini-secret");
      return new Response(null, { status: 204 });
    }
    throw new Error(`unexpected fetch ${method} ${url}`);
  });
  const ingestion = videoIngestion();

  const result = await understandWithGemini(
    source,
    emptyCatalog,
    [ingestion],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result, {
    candidates: [],
    mediaAssessments: [mediaAssessment("media:0")],
    postContext: {
      intent: "unknown",
      declaredCount: -1,
      declaredCountEvidenceIds: [],
      globalArea: "",
      globalAreaEvidenceIds: [],
    },
    attemptCount: 2,
    tokenUsage: {
      promptTokens: 200,
      cachedPromptTokens: 20,
      responseTokens: 40,
      thinkingTokens: 10,
      totalTokens: 250,
    },
  });
  assertEquals(maximumGeminiSemanticPasses, 2);
  assertEquals(calls, [
    "start",
    "upload",
    "poll",
    "generate",
    "generate",
    "delete",
  ]);
  assertEquals(ingestion.status, "ok");
  assertEquals(ingestion.bytes, undefined);
  const generateBody = generatedBodies[0] ?? null;
  const generationConfig = asRecord(generateBody?.generationConfig);
  assertEquals(generationConfig?.maxOutputTokens, 16_384);
  assertEquals(generationConfig?.thinkingConfig, { thinkingLevel: "LOW" });
  const reconciliationConfig = asRecord(
    generatedBodies[1]?.generationConfig,
  );
  assertEquals(reconciliationConfig?.thinkingConfig, {
    thinkingLevel: "MEDIUM",
  });
  assertEquals(generationConfig?.mediaResolution, "MEDIA_RESOLUTION_HIGH");
  const parts = requestParts(generateBody);
  assertEquals(parts[1], {
    fileData: { mimeType: "video/mp4", fileUri: fileURI },
    videoMetadata: { fps: 2 },
  });
  const evidence = JSON.parse(String(asRecord(parts.at(-1))?.text));
  assertEquals(evidence.allowed_media_evidence_ids, ["media:0"]);
  const reconciliation = JSON.parse(
    String(asRecord(requestParts(generatedBodies[1]).at(-1))?.text),
  );
  assertEquals(reconciliation.task, "reconcile_grounded_destinations");
  assertEquals(
    reconciliation.coverage_requirements.audit_every_media_asset,
    true,
  );
});

Deno.test("Gemini reconciles an underfilled declared list and returns a full replacement", async () => {
  const generatedBodies: Record<string, unknown>[] = [];
  const alpha = {
    ...modelCandidate("Alpha Cafe", "@alpha", 0),
    classification: "destination",
  };
  const bravo = {
    ...modelCandidate("Bravo Books", "@bravo", 1),
    classification: "destination",
  };
  const context = {
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "",
    globalAreaEvidenceIds: [],
  };
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generatedBodies.push(JSON.parse(String(init?.body)));
    return generatedBodies.length === 1
      ? geminiUnderstandingResponse(context, [alpha])
      : geminiUnderstandingResponse(context, [alpha, bravo]);
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Top 2:\n1. @alpha\n2. @bravo",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.attemptCount, 2);
  assertEquals(result.coverageIncomplete, undefined);
  assertEquals(result.candidates.map((candidate) => candidate.name), [
    "Alpha Cafe",
    "Bravo Books",
  ]);
  assertEquals(generatedBodies.length, 2);
  const firstTask = JSON.parse(
    String(asRecord(requestParts(generatedBodies[0]).at(-1))?.text),
  );
  assertEquals(
    firstTask.caption_mention_inventory
      .filter((mention: Record<string, unknown>) => mention.kind === "handle")
      .map((mention: Record<string, unknown>) => mention.source_mention),
    ["@alpha", "@bravo"],
  );
  const reconciliation = JSON.parse(
    String(asRecord(requestParts(generatedBodies[1]).at(-1))?.text),
  );
  assertEquals(reconciliation.coverage_requirements, {
    unassessed_caption_handles: ["@bravo"],
    declared_destination_count: 2,
    accepted_primary_count: 1,
    declared_count_gap: 1,
    audit_every_media_asset: false,
    media_evidence_ids: [],
  });
});

Deno.test("Gemini declared-count reconciliation ignores supporting itinerary rows", async () => {
  const generatedBodies: Record<string, unknown>[] = [];
  const destinations = Array.from({ length: 6 }, (_, itemIndex) => ({
    ...modelCandidate(
      `Primary ${itemIndex + 1}`,
      `Primary ${itemIndex + 1}`,
      itemIndex,
    ),
    classification: "destination",
  }));
  const supporting = Array.from({ length: 2 }, (_, offset) => ({
    ...modelCandidate(
      `Supporting ${offset + 1}`,
      `Supporting ${offset + 1}`,
      destinations.length + offset,
    ),
    classification: "itinerary",
  }));
  const candidates = [...destinations, ...supporting];
  const context = {
    intent: "place_list",
    declaredCount: 8,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "",
    globalAreaEvidenceIds: [],
  };
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generatedBodies.push(JSON.parse(String(init?.body)));
    return geminiUnderstandingResponse(context, candidates);
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "8 places with six primary destinations and two supporting stops",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.attemptCount, 2);
  assertEquals(result.coverageIncomplete, true);
  assertEquals(result.candidates.length, 8);
  assertEquals(generatedBodies.length, 2);
  const reconciliation = JSON.parse(
    String(asRecord(requestParts(generatedBodies[1]).at(-1))?.text),
  );
  assertEquals(reconciliation.coverage_requirements, {
    unassessed_caption_handles: [],
    declared_destination_count: 8,
    accepted_primary_count: 6,
    declared_count_gap: 2,
    audit_every_media_asset: false,
    media_evidence_ids: [],
  });
});

Deno.test("Gemini preserves a valid first pass when reconciliation fails", async () => {
  let generateCount = 0;
  const alpha = modelCandidate("Alpha Cafe", "@alpha", 0);
  const context = {
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "",
    globalAreaEvidenceIds: [],
  };
  const dependencies = runtime((input) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    return generateCount === 1
      ? geminiUnderstandingResponse(context, [alpha])
      : Response.json(
        { error: { status: "INVALID_ARGUMENT" } },
        { status: 400 },
      );
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Top 2:\n1. @alpha\n2. @bravo",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.candidates.map((candidate) => candidate.name), [
    "Alpha Cafe",
  ]);
  assertEquals(result.attemptCount, 2);
  assertEquals(result.coverageIncomplete, true);
  assertEquals(generateCount, 2);
});

Deno.test("Gemini marks a still-underfilled reconciliation as incomplete", async () => {
  let generateCount = 0;
  const alpha = modelCandidate("Alpha Cafe", "@alpha", 0);
  const context = {
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "",
    globalAreaEvidenceIds: [],
  };
  const dependencies = runtime((input) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    return geminiUnderstandingResponse(context, [alpha]);
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Top 2:\n1. @alpha\n2. @bravo",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.candidates.map((candidate) => candidate.name), [
    "Alpha Cafe",
  ]);
  assertEquals(result.coverageIncomplete, true);
  assertEquals(result.mediaCoverageIncomplete, undefined);
  assertEquals(result.captionCoverageIncomplete, true);
  assertEquals(result.declaredCountCoverageIncomplete, true);
  assertEquals(generateCount, 2);
});

Deno.test("Gemini reconciliation cannot drop a distinct first-pass venue", async () => {
  let generateCount = 0;
  const alpha = {
    ...modelCandidate("Alpha Cafe", "Alpha Cafe", 0),
    classification: "destination",
  };
  const bravo = {
    ...modelCandidate("Bravo Books", "Bravo Books", 1),
    classification: "destination",
  };
  const context = {
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "",
    globalAreaEvidenceIds: [],
  };
  const dependencies = runtime((input) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    return geminiUnderstandingResponse(
      context,
      generateCount === 1 ? [alpha] : [bravo],
    );
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Top 2: Alpha Cafe and Bravo Books",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.candidates.map((candidate) => candidate.name), [
    "Bravo Books",
    "Alpha Cafe",
  ]);
  assertEquals(result.coverageIncomplete, undefined);
  assertEquals(generateCount, 2);
});

Deno.test("Gemini reconciliation explicit non-destinations suppress the same evidenced first-pass destination", async () => {
  const reclassifications = [
    "itinerary",
    "ambiguous",
    "incidental",
    "attribution",
    "not_a_place",
  ] as const;

  for (const classification of reclassifications) {
    let generateCount = 0;
    const stale = {
      ...modelCandidate("Alpha Cafe", "Alpha Cafe", 0),
      classification: "destination",
    };
    const explicitReclassification = {
      ...modelCandidate("Alpha Cafe", "Alpha Cafe", 0),
      classification,
    };
    const bravo = {
      ...modelCandidate("Bravo Books", "Bravo Books", 1),
      classification: "destination",
    };
    const context = {
      intent: "place_list",
      declaredCount: 2,
      declaredCountEvidenceIds: ["caption:0"],
      globalArea: "",
      globalAreaEvidenceIds: [],
    };
    const dependencies = runtime((input) => {
      const url = String(input);
      if (!url.includes(":generateContent")) {
        throw new Error(`unexpected fetch ${url}`);
      }
      generateCount += 1;
      return geminiUnderstandingResponse(
        context,
        generateCount === 1 ? [stale] : [explicitReclassification, bravo],
      );
    });

    const result = await understandWithGemini(
      source,
      {
        texts: [{
          id: "caption:0",
          modality: "caption",
          text: "Top 2: Alpha Cafe and Bravo Books",
          area: null,
          mediaID: null,
        }],
        media: [],
      },
      [],
      "gemini-secret",
      "gemini-3.5-flash",
      new Deadline(100_000, dependencies.now),
      dependencies,
    );

    assertEquals(
      result.candidates.map((candidate) => [
        candidate.name,
        candidate.classification,
      ]),
      [
        ["Alpha Cafe", classification],
        ["Bravo Books", "destination"],
      ],
    );
    assertEquals(
      result.candidates.some((candidate) =>
        candidate.itemIndex === 0 &&
        candidate.classification === "destination"
      ),
      false,
    );
    assertEquals(result.coverageIncomplete, true);
    assertEquals(
      result.declaredCountCoverageIncomplete,
      true,
    );
    assertEquals(generateCount, 2);
  }
});

Deno.test("Gemini reconciliation keeps an omitted first-pass destination when a same-index negative cites different evidence", async () => {
  let generateCount = 0;
  const alpha = {
    ...modelCandidate("Alpha Cafe", "Alpha Cafe", 0),
    classification: "destination",
  };
  const unrelatedNegative = {
    ...modelCandidate("Alpha Cafe", "Photo credit: Alpha Cafe", 0),
    classification: "attribution",
    evidenceIds: ["caption:1"],
  };
  const bravo = {
    ...modelCandidate("Bravo Books", "Bravo Books", 1),
    classification: "destination",
  };
  const context = {
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "",
    globalAreaEvidenceIds: [],
  };
  const dependencies = runtime((input) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    return geminiUnderstandingResponse(
      context,
      generateCount === 1 ? [alpha] : [unrelatedNegative, bravo],
    );
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Top 2: Alpha Cafe and Bravo Books",
        area: null,
        mediaID: null,
      }, {
        id: "caption:1",
        modality: "caption",
        text: "Photo credit: Alpha Cafe",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(
    result.candidates.map((candidate) => [
      candidate.sourceMention,
      candidate.classification,
      candidate.evidenceIds,
    ]),
    [
      ["Photo credit: Alpha Cafe", "attribution", ["caption:1"]],
      ["Bravo Books", "destination", ["caption:0"]],
      ["Alpha Cafe", "destination", ["caption:0"]],
    ],
  );
  assertEquals(result.coverageIncomplete, undefined);
  assertEquals(generateCount, 2);
});

Deno.test("Gemini reconciliation replaces a corrected primary spelling at the same item index", async () => {
  let generateCount = 0;
  const generatedBodies: Record<string, unknown>[] = [];
  const typo = {
    ...modelCandidate("Cafe Nivah", "16. Cafe Nivah Big Sur", 0),
    classification: "destination",
  };
  const corrected = {
    ...modelCandidate("Cafe Kevah", "16. Cafe Kevah Big Sur", 0),
    classification: "destination",
  };
  const bravo = {
    ...modelCandidate("Bravo Books", "Bravo Books", 1),
    classification: "destination",
  };
  const context = {
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "",
    globalAreaEvidenceIds: [],
  };
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    generatedBodies.push(JSON.parse(String(init?.body)));
    return geminiUnderstandingResponse(
      context,
      generateCount === 1 ? [typo] : [corrected, bravo],
    );
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Top 2: Cafe Kevah and Bravo Books",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.candidates.map((candidate) => candidate.name), [
    "Cafe Kevah",
    "Bravo Books",
  ]);
  assertEquals(generateCount, 2);
  const firstConfig = asRecord(generatedBodies[0]?.generationConfig);
  const reconciliationConfig = asRecord(generatedBodies[1]?.generationConfig);
  assertEquals(firstConfig?.thinkingConfig, { thinkingLevel: "LOW" });
  assertEquals(reconciliationConfig?.thinkingConfig, {
    thinkingLevel: "MEDIUM",
  });
  const system = asRecord(generatedBodies[0]?.systemInstruction);
  const systemParts = Array.isArray(system?.parts) ? system.parts : [];
  assertEquals(
    JSON.stringify(systemParts).includes("smallest plausible edit"),
    true,
  );
  assertEquals(
    JSON.stringify(systemParts).includes(
      "adding an official Trail or Loop suffix",
    ),
    true,
  );
  const reconciliation = JSON.parse(
    String(asRecord(requestParts(generatedBodies[1]).at(-1))?.text),
  );
  assertEquals(
    reconciliation.instruction.includes("nearby parent property"),
    true,
  );
});

Deno.test("Gemini reconciliation accepts official route suffixes for the same primary", async () => {
  let generateCount = 0;
  const mirrorLake = {
    ...modelCandidate("Mirror Lake", "Mirror Lake", 0),
    classification: "destination",
  };
  const meadow = {
    ...modelCandidate(
      "Sentinel & Cook's Meadow",
      "Sentinel & Cook's Meadow",
      1,
    ),
    classification: "destination",
  };
  const mirrorLakeTrail = {
    ...modelCandidate("Mirror Lake Trail", "Mirror Lake", 0),
    classification: "destination",
  };
  const meadowLoop = {
    ...modelCandidate(
      "Sentinel & Cook's Meadow Loop",
      "Sentinel & Cook's Meadow",
      1,
    ),
    classification: "destination",
  };
  const third = {
    ...modelCandidate("Vernal Fall", "Vernal Fall", 2),
    classification: "destination",
  };
  const context = {
    intent: "place_list",
    declaredCount: 3,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "Yosemite National Park",
    globalAreaEvidenceIds: ["caption:0"],
  };
  const dependencies = runtime((input) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    return geminiUnderstandingResponse(
      context,
      generateCount === 1
        ? [mirrorLake, meadow]
        : [mirrorLakeTrail, meadowLoop, third],
    );
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text:
          "3 Yosemite hikes: Mirror Lake, Sentinel & Cook's Meadow, Vernal Fall",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.candidates.map((candidate) => candidate.name), [
    "Mirror Lake Trail",
    "Sentinel & Cook's Meadow Loop",
    "Vernal Fall",
  ]);
  assertEquals(
    result.candidates.map((candidate) => candidate.sourceMention),
    ["Mirror Lake", "Sentinel & Cook's Meadow", "Vernal Fall"],
  );
  assertEquals(generateCount, 2);
});

Deno.test("Gemini reconciliation retains first-pass primaries after unsupported renames", async () => {
  let generateCount = 0;
  const cafeNivah = {
    ...modelCandidate("Cafe Nivah", "16. Cafe Nivah Big Sur", 0),
    classification: "destination",
  };
  const elixirTeaBar = {
    ...modelCandidate("Elixir Tea Bar", "Elixir Tea Bar", 1),
    classification: "destination",
  };
  const cafeNepenthe = {
    ...modelCandidate("Cafe Nepenthe", "16. Cafe Nivah Big Sur", 0),
    classification: "destination",
  };
  const elixirWizardAcademy = {
    ...modelCandidate("Elixir Wizard Academy", "Elixir Tea Bar", 1),
    classification: "destination",
  };
  const third = {
    ...modelCandidate("Bravo Books", "Bravo Books", 2),
    classification: "destination",
  };
  const context = {
    intent: "place_list",
    declaredCount: 3,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "California",
    globalAreaEvidenceIds: ["caption:0"],
  };
  const dependencies = runtime((input) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    return geminiUnderstandingResponse(
      context,
      generateCount === 1
        ? [cafeNivah, elixirTeaBar]
        : [cafeNepenthe, elixirWizardAcademy, third],
    );
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "3 stops: Cafe Nivah, Elixir Tea Bar, and Bravo Books",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.candidates.map((candidate) => candidate.name), [
    "Cafe Nivah",
    "Elixir Tea Bar",
    "Bravo Books",
  ]);
  assertEquals(
    result.candidates.map((candidate) => candidate.sourceMention),
    ["16. Cafe Nivah Big Sur", "Elixir Tea Bar", "Bravo Books"],
  );
  assertEquals(generateCount, 2);
});

Deno.test("Gemini skips reconciliation on a low budget and marks coverage incomplete", async () => {
  let generateCount = 0;
  const alpha = modelCandidate("Alpha Cafe", "@alpha", 0);
  const context = {
    intent: "place_list",
    declaredCount: 2,
    declaredCountEvidenceIds: ["caption:0"],
    globalArea: "",
    globalAreaEvidenceIds: [],
  };
  const dependencies = runtime((input) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    return geminiUnderstandingResponse(context, [alpha]);
  });

  const result = await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Top 2:\n1. @alpha\n2. @bravo",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(11_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.coverageIncomplete, true);
  assertEquals(generateCount, 1);
});

Deno.test("Gemini uses a provider-compatible schema while runtime validation keeps bounds", async () => {
  const generatedBodies: Record<string, unknown>[] = [];
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generatedBodies.push(JSON.parse(String(init?.body)));
    return geminiResponse([]);
  });

  await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Visit Bart's Books",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  const generatedBody = generatedBodies[0] ?? null;
  const generationConfig = asRecord(generatedBody?.generationConfig);
  const responseFormat = asRecord(generationConfig?.responseFormat);
  const textFormat = asRecord(responseFormat?.text);
  const schema = asRecord(textFormat?.schema);
  const rootProperties = asRecord(schema?.properties);
  assertEquals(schema?.required, [
    "postContext",
    "candidates",
    "mediaAssessments",
  ]);
  const postContext = asRecord(rootProperties?.postContext);
  const postContextProperties = asRecord(postContext?.properties);
  assertEquals(postContextProperties?.declaredCount, { type: "integer" });
  assertEquals(postContextProperties?.declaredCountEvidenceIds, {
    type: "array",
    items: { type: "string" },
  });
  assertEquals(postContextProperties?.globalAreaEvidenceIds, {
    type: "array",
    items: { type: "string" },
  });

  const candidates = asRecord(rootProperties?.candidates);
  assertEquals(candidates?.maxItems, undefined);
  const candidateItems = asRecord(candidates?.items);
  const candidateProperties = asRecord(candidateItems?.properties);
  assertEquals(candidateProperties?.itemIndex, { type: "integer" });
  assertEquals(candidateProperties?.evidenceIds, {
    type: "array",
    items: { type: "string" },
  });
  const mediaAssessments = asRecord(rootProperties?.mediaAssessments);
  const mediaAssessmentItems = asRecord(mediaAssessments?.items);
  const mediaAssessmentProperties = asRecord(mediaAssessmentItems?.properties);
  assertEquals(mediaAssessmentProperties?.mediaEvidenceId, { type: "string" });
  assertEquals(mediaAssessmentProperties?.disposition, {
    type: "string",
    enum: ["place_mentions", "no_place_mentions"],
  });
  assertEquals(mediaAssessmentProperties?.candidateItemIndexes, {
    type: "array",
    items: { type: "integer" },
  });
});

Deno.test("Gemini receives profile display names only as scoped handle identities", async () => {
  const generatedBodies: Record<string, unknown>[] = [];
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generatedBodies.push(JSON.parse(String(init?.body)));
    return geminiResponse([]);
  });

  await understandWithGemini(
    source,
    {
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: "Lunch at @hvojai. Photo by @creator.",
        area: null,
        mediaID: null,
      }],
      media: [],
    },
    [],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
    undefined,
    [
      { username: "hvojai", fullName: "Hip Vegan" },
      { username: "bad handle", fullName: "Rejected" },
      { username: "creator", fullName: "Caption Creator" },
      { username: "duplicate", fullName: "First Name" },
      { username: "duplicate", fullName: "Conflicting Name" },
    ],
  );

  const evidence = JSON.parse(
    String(asRecord(requestParts(generatedBodies[0]).at(-1))?.text),
  );
  assertEquals(evidence.caption_handle_identity_aliases, [
    { source_mention: "@hvojai", profile_name: "Hip Vegan" },
    { source_mention: "@creator", profile_name: "Caption Creator" },
  ]);
  assertEquals(
    JSON.stringify(evidence).includes("biography"),
    false,
  );
});

Deno.test("Gemini rejects non-Google resumable upload URLs without fetching them", async () => {
  for (
    const value of [
      "https://evil.example/upload/v1beta/files?upload_id=stolen",
      "http://generativelanguage.googleapis.com/upload/v1beta/files",
      "https://user:pass@generativelanguage.googleapis.com/upload/v1beta/files",
      "https://generativelanguage.googleapis.com:444/upload/v1beta/files",
      "https://generativelanguage.googleapis.com/v1beta/files",
    ]
  ) {
    assertErrorCode(
      () => validatedGeminiUploadURL(value),
      "gemini_unsafe_upload_url",
    );
  }
  assertEquals(validatedGeminiUploadURL(uploadURL).toString(), uploadURL);

  let fetchCount = 0;
  const dependencies = runtime((input) => {
    fetchCount += 1;
    assertEquals(String(input), `${geminiOrigin}/upload/v1beta/files`);
    return new Response(null, {
      headers: {
        "x-goog-upload-url":
          "https://evil.example/upload/v1beta/files?upload_id=stolen",
      },
    });
  });
  const ingestion = videoIngestion();
  await assertRejectsCode(
    () =>
      understandWithGemini(
        source,
        emptyCatalog,
        [ingestion],
        "gemini-secret",
        undefined,
        new Deadline(100_000, dependencies.now),
        dependencies,
      ),
    "gemini_no_evidence",
  );
  assertEquals(fetchCount, 1);
  assertEquals(ingestion.status, "failed");
  assertEquals(ingestion.errorCode, "gemini_video_ingestion_failed");
  assertEquals(ingestion.bytes, undefined);
});

Deno.test("Gemini deletes uploaded videos when model generation fails", async () => {
  const calls: string[] = [];
  const dependencies = runtime((input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    if (url === `${geminiOrigin}/upload/v1beta/files`) {
      calls.push("start");
      return new Response(null, {
        headers: { "x-goog-upload-url": uploadURL },
      });
    }
    if (url === uploadURL) {
      calls.push("upload");
      return Response.json({
        file: { name: fileName, uri: fileURI, state: "ACTIVE" },
      });
    }
    if (url.includes(":generateContent")) {
      calls.push("generate");
      return Response.json({ error: {} }, { status: 400 });
    }
    if (url === fileURI && method === "DELETE") {
      calls.push("delete");
      return new Response(null, { status: 204 });
    }
    throw new Error(`unexpected fetch ${method} ${url}`);
  });
  const ingestion = videoIngestion();

  await assertRejectsCode(
    () =>
      understandWithGemini(
        source,
        emptyCatalog,
        [ingestion],
        "gemini-secret",
        undefined,
        new Deadline(100_000, dependencies.now),
        dependencies,
      ),
    "gemini_http_400",
  );

  assertEquals(calls, ["start", "upload", "generate", "delete"]);
  assertEquals(ingestion.bytes, undefined);
});

Deno.test("a pre-cancelled request starts no Gemini upload or model work", async () => {
  let fetchCount = 0;
  const dependencies = runtime(() => {
    fetchCount += 1;
    throw new Error("cancelled requests must not reach Gemini");
  });
  const controller = new AbortController();
  controller.abort();
  const ingestion = videoIngestion();

  await assertRejectsCode(
    () =>
      understandWithGemini(
        source,
        {
          texts: [{
            id: "caption:0",
            modality: "caption",
            text: "Carbon Beach Club",
            area: null,
            mediaID: null,
          }],
          media: [],
        },
        [ingestion],
        "gemini-secret",
        undefined,
        new Deadline(100_000, dependencies.now),
        dependencies,
        controller.signal,
      ),
    "request_cancelled",
  );

  assertEquals(fetchCount, 0);
});

Deno.test("inline image selection leaves overflow available for Files API upload", () => {
  const first = imageIngestion("media:0", 10 * 1_024 * 1_024);
  const second = imageIngestion("media:1", 3 * 1_024 * 1_024);

  const selected = selectInlineImageIngestions([first, second]);

  assertEquals(maximumInlineImageBytes, 12 * 1_024 * 1_024);
  assertEquals(selected.map((item) => item.mediaID), ["media:0"]);
  assertEquals(first.status, "ok");
  assert(first.bytes instanceof Uint8Array);
  assertEquals(second.status, "ok");
  assertEquals(second.errorCode, null);
  assert(second.bytes instanceof Uint8Array);
});

Deno.test("Gemini uploads a realistic seventeen-image overflow with bounded concurrency and preserves source order", async () => {
  const oneMiB = 1_024 * 1_024;
  const ingestions = Array.from(
    { length: 17 },
    (_, index) => imageIngestion(`media:${index}`, oneMiB),
  );
  const generatedBodies: Record<string, unknown>[] = [];
  const deletedFiles: string[] = [];
  let nextUploadIndex = 0;
  let activeStarts = 0;
  let maximumActiveStarts = 0;
  let uploadCount = 0;

  const dependencies = runtime(async (input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    if (url === `${geminiOrigin}/upload/v1beta/files`) {
      const index = nextUploadIndex;
      nextUploadIndex += 1;
      activeStarts += 1;
      maximumActiveStarts = Math.max(maximumActiveStarts, activeStarts);
      await Promise.resolve();
      activeStarts -= 1;
      return new Response(null, {
        headers: {
          "x-goog-upload-url":
            `${geminiOrigin}/upload/v1beta/files?upload_id=image-${index}`,
        },
      });
    }
    if (
      url.startsWith(`${geminiOrigin}/upload/v1beta/files?upload_id=image-`)
    ) {
      uploadCount += 1;
      const index = Number(
        new URL(url).searchParams.get("upload_id")?.slice(6),
      );
      const name = `files/image-${index}`;
      return Response.json({
        file: {
          name,
          uri: `${geminiOrigin}/v1beta/${name}`,
          state: "ACTIVE",
        },
      });
    }
    if (url.includes(":generateContent")) {
      generatedBodies.push(JSON.parse(String(init?.body)));
      return geminiUnderstandingResponse(
        {
          intent: "unknown",
          declaredCount: -1,
          declaredCountEvidenceIds: [],
          globalArea: "",
          globalAreaEvidenceIds: [],
        },
        [],
        completeMediaAssessments(17),
      );
    }
    if (
      method === "DELETE" && url.startsWith(`${geminiOrigin}/v1beta/files/`)
    ) {
      deletedFiles.push(url);
      return new Response(null, { status: 204 });
    }
    throw new Error(`unexpected fetch ${method} ${url}`);
  });

  const result = await understandWithGemini(
    {
      platform: "instagram",
      contentType: "post",
      url: "https://www.instagram.com/p/ABC123xyz/",
      sourceID: "ABC123xyz",
    },
    emptyCatalog,
    ingestions,
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.attemptCount, 2);
  assertEquals(nextUploadIndex, 5);
  assertEquals(uploadCount, 5);
  assertEquals(deletedFiles.length, 5);
  assertEquals(maximumActiveStarts, maximumConcurrentGeminiImageUploads);
  assert(maximumActiveStarts <= maximumConcurrentGeminiImageUploads);
  assertEquals(ingestions.map((item) => item.status), Array(17).fill("ok"));
  assertEquals(ingestions.map((item) => item.errorCode), Array(17).fill(null));
  assert(ingestions.every((item) => item.bytes === undefined));

  const parts = requestParts(generatedBodies[0] ?? null);
  assertEquals(parts.filter((part) => part.inlineData).length, 12);
  assertEquals(parts.filter((part) => part.fileData).length, 5);
  const mediaParts = parts.filter((part) => part.inlineData || part.fileData);
  assertEquals(mediaParts.length, 17);
  assertEquals(
    mediaParts.slice(12).map((part) => asRecord(part.fileData)?.fileUri),
    Array.from(
      { length: 5 },
      (_, index) => `${geminiOrigin}/v1beta/files/image-${index}`,
    ),
  );
  const evidence = JSON.parse(String(asRecord(parts.at(-1))?.text));
  assertEquals(
    evidence.allowed_media_evidence_ids,
    Array.from({ length: 17 }, (_, index) => `media:${index}`),
  );
});

Deno.test("Gemini marks a seventeen-image response incomplete when only five media are assessed", async () => {
  const generatedBodies: Record<string, unknown>[] = [];
  const ingestions = Array.from(
    { length: 17 },
    (_, index) => imageIngestion(`media:${index}`, 1),
  );
  const candidates = Array.from({ length: 5 }, (_, index) => ({
    ...modelCandidate(`Hotel ${index + 1}`, `Hotel ${index + 1}`, index),
    classification: "destination",
    modality: "image_text",
    evidenceIds: [`media:${index}`],
  }));
  const assessments = Array.from(
    { length: 5 },
    (_, index) => mediaAssessment(`media:${index}`, [index]),
  );
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generatedBodies.push(JSON.parse(String(init?.body)));
    return geminiUnderstandingResponse(
      {
        intent: "place_list",
        declaredCount: -1,
        declaredCountEvidenceIds: [],
        globalArea: "",
        globalAreaEvidenceIds: [],
      },
      candidates,
      assessments,
    );
  });

  const result = await understandWithGemini(
    source,
    emptyCatalog,
    ingestions,
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.attemptCount, 2);
  assertEquals(result.candidates.length, 5);
  assertEquals(result.coverageIncomplete, true);
  assertEquals(result.mediaCoverageIncomplete, true);
  assertEquals(result.captionCoverageIncomplete, undefined);
  assertEquals(result.declaredCountCoverageIncomplete, undefined);
  const reconciliation = JSON.parse(
    String(asRecord(requestParts(generatedBodies[1]).at(-1))?.text),
  );
  assertEquals(
    reconciliation.coverage_requirements.missing_media_assessment_ids,
    Array.from({ length: 12 }, (_, index) => `media:${index + 5}`),
  );
  assertEquals(
    reconciliation.coverage_requirements.audit_every_media_asset,
    true,
  );
});

Deno.test("Gemini accepts complete ordered assessments for all seventeen images", async () => {
  const ingestions = Array.from(
    { length: 17 },
    (_, index) => imageIngestion(`media:${index}`, 1),
  );
  const candidates = Array.from({ length: 17 }, (_, index) => ({
    ...modelCandidate(`Hotel ${index + 1}`, `Hotel ${index + 1}`, index),
    classification: "destination",
    modality: "image_text",
    evidenceIds: [`media:${index}`],
  }));
  const assessments = Array.from(
    { length: 17 },
    (_, index) => mediaAssessment(`media:${index}`, [index]),
  );
  let generateCount = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (!url.includes(":generateContent")) {
      throw new Error(`unexpected fetch ${url}`);
    }
    generateCount += 1;
    return geminiUnderstandingResponse(
      {
        intent: "place_list",
        declaredCount: 17,
        declaredCountEvidenceIds: ["media:0"],
        globalArea: "",
        globalAreaEvidenceIds: [],
      },
      candidates,
      assessments,
    );
  });

  const result = await understandWithGemini(
    source,
    emptyCatalog,
    ingestions,
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(generateCount, 2);
  assertEquals(result.attemptCount, 2);
  assertEquals(result.candidates.length, 17);
  assertEquals(result.coverageIncomplete, undefined);
  assertEquals(result.mediaCoverageIncomplete, undefined);
  assertEquals(result.captionCoverageIncomplete, undefined);
  assertEquals(result.declaredCountCoverageIncomplete, undefined);
});

Deno.test("Gemini treats missing duplicate unknown and reordered media assessments as incomplete", async () => {
  const cases: Array<{ name: string; assessments: ModelMediaAssessment[] }> = [
    {
      name: "missing",
      assessments: [mediaAssessment("media:0")],
    },
    {
      name: "duplicate",
      assessments: [
        mediaAssessment("media:0"),
        mediaAssessment("media:0"),
        mediaAssessment("media:1"),
      ],
    },
    {
      name: "unknown",
      assessments: [
        mediaAssessment("media:0"),
        mediaAssessment("media:1"),
        mediaAssessment("media:99"),
      ],
    },
    {
      name: "reordered",
      assessments: [
        mediaAssessment("media:1"),
        mediaAssessment("media:0"),
      ],
    },
  ];

  for (const testCase of cases) {
    const ingestions = [
      imageIngestion("media:0", 1),
      imageIngestion("media:1", 1),
    ];
    const dependencies = runtime((input) => {
      const url = String(input);
      if (!url.includes(":generateContent")) {
        throw new Error(`unexpected fetch ${url}`);
      }
      return geminiUnderstandingResponse(
        {
          intent: "unknown",
          declaredCount: -1,
          declaredCountEvidenceIds: [],
          globalArea: "",
          globalAreaEvidenceIds: [],
        },
        [],
        testCase.assessments,
      );
    });

    const result = await understandWithGemini(
      source,
      emptyCatalog,
      ingestions,
      "gemini-secret",
      "gemini-3.5-flash",
      new Deadline(100_000, dependencies.now),
      dependencies,
    );
    assert(
      result.coverageIncomplete === true,
      `${testCase.name} assessment ledger must stay incomplete`,
    );
    assertEquals(result.mediaCoverageIncomplete, true);
  }
});

Deno.test("Gemini treats assessment-to-candidate contradictions as incomplete", async () => {
  const citedCandidate = {
    ...modelCandidate("Alpha Hotel", "Alpha Hotel", 0),
    classification: "destination",
    modality: "image_text",
    evidenceIds: ["media:0"],
  };
  const cases = [{
    name: "assessment references a missing candidate index",
    candidates: [],
    assessment: mediaAssessment("media:0", [0]),
  }, {
    name: "assessment says no place despite a media-cited candidate",
    candidates: [citedCandidate],
    assessment: mediaAssessment("media:0"),
  }];

  for (const testCase of cases) {
    const generatedBodies: Record<string, unknown>[] = [];
    const dependencies = runtime((input, init) => {
      const url = String(input);
      if (!url.includes(":generateContent")) {
        throw new Error(`unexpected fetch ${url}`);
      }
      generatedBodies.push(JSON.parse(String(init?.body)));
      return geminiUnderstandingResponse(
        {
          intent: "unknown",
          declaredCount: -1,
          declaredCountEvidenceIds: [],
          globalArea: "",
          globalAreaEvidenceIds: [],
        },
        testCase.candidates,
        [testCase.assessment],
      );
    });

    const result = await understandWithGemini(
      source,
      emptyCatalog,
      [imageIngestion("media:0", 1)],
      "gemini-secret",
      "gemini-3.5-flash",
      new Deadline(100_000, dependencies.now),
      dependencies,
    );

    if (generatedBodies.length !== 2) {
      throw new Error(
        `${testCase.name} must receive a reconciliation pass; got ${generatedBodies.length}`,
      );
    }
    assertEquals(result.coverageIncomplete, true);
    assertEquals(result.mediaCoverageIncomplete, true);
    const reconciliation = JSON.parse(
      String(asRecord(requestParts(generatedBodies[1]).at(-1))?.text),
    );
    assertEquals(
      reconciliation.coverage_requirements
        .referentially_invalid_media_assessment_ids,
      ["media:0"],
    );
  }
});

Deno.test("a genuine overflow image upload failure remains an honest per-media failure", async () => {
  const first = imageIngestion("media:0", 10 * 1_024 * 1_024);
  const overflow = imageIngestion("media:1", 3 * 1_024 * 1_024);
  let generateCount = 0;
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url === `${geminiOrigin}/upload/v1beta/files`) {
      return new Response(null, { status: 503 });
    }
    if (url.includes(":generateContent")) {
      generateCount += 1;
      return geminiUnderstandingResponse(
        {
          intent: "unknown",
          declaredCount: -1,
          declaredCountEvidenceIds: [],
          globalArea: "",
          globalAreaEvidenceIds: [],
        },
        [],
        [mediaAssessment("media:0")],
      );
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const result = await understandWithGemini(
    source,
    emptyCatalog,
    [first, overflow],
    "gemini-secret",
    "gemini-3.5-flash",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.attemptCount, 1);
  assertEquals(generateCount, 1);
  assertEquals(first.status, "ok");
  assertEquals(first.bytes, undefined);
  assertEquals(overflow.status, "failed");
  assertEquals(overflow.errorCode, "gemini_image_ingestion_failed");
  assertEquals(overflow.bytes, undefined);
});

type TestFetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Response | Promise<Response>;

function runtime(fetcher: TestFetcher): RuntimeDependencies {
  return {
    fetch:
      ((input, init) => Promise.resolve(fetcher(input, init))) as typeof fetch,
    env: () => undefined,
    now: () => 1_000,
    sleep: async () => {},
    random: () => 0,
  };
}

const source: SocialSource = {
  platform: "instagram",
  contentType: "reel",
  url: "https://www.instagram.com/reel/DcAU9e5DYcH",
  sourceID: "DcAU9e5DYcH",
};

const emptyCatalog: EvidenceCatalog = { texts: [], media: [] };

function videoIngestion(): MediaIngestion {
  return {
    mediaID: "media:0",
    kind: "video",
    status: "ok",
    byteCount: 8,
    mimeType: "video/mp4",
    bytes: new Uint8Array([0, 0, 0, 0, 0x66, 0x74, 0x79, 0x70]),
    errorCode: null,
  };
}

function imageIngestion(mediaID: string, byteCount: number): MediaIngestion {
  return {
    mediaID,
    kind: "image",
    status: "ok",
    byteCount,
    mimeType: "image/jpeg",
    bytes: new Uint8Array(byteCount),
    errorCode: null,
  };
}

function requestParts(
  body: Record<string, unknown> | null,
): Record<string, unknown>[] {
  const contents = Array.isArray(body?.contents) ? body.contents : [];
  const content = asRecord(contents[0]);
  return Array.isArray(content?.parts)
    ? content.parts.map(asRecord).filter(
      (value): value is Record<string, unknown> => value !== null,
    )
    : [];
}

function geminiResponse(candidates: unknown[]): Response {
  return Response.json({
    candidates: [{
      content: { parts: [{ text: JSON.stringify({ candidates }) }] },
    }],
  });
}

function geminiUnderstandingResponse(
  postContext: Record<string, unknown>,
  candidates: unknown[],
  mediaAssessments: unknown[] = [],
  usageMetadata?: Record<string, unknown>,
): Response {
  return Response.json({
    candidates: [{
      content: {
        parts: [{
          text: JSON.stringify({
            postContext,
            candidates,
            mediaAssessments,
          }),
        }],
      },
    }],
    ...(usageMetadata ? { usageMetadata } : {}),
  });
}

function mediaAssessment(
  mediaEvidenceId: string,
  candidateItemIndexes: number[] = [],
): ModelMediaAssessment {
  return {
    mediaEvidenceId,
    disposition: candidateItemIndexes.length > 0
      ? "place_mentions"
      : "no_place_mentions",
    candidateItemIndexes,
  };
}

function completeMediaAssessments(count: number): ModelMediaAssessment[] {
  return Array.from(
    { length: count },
    (_, index) => mediaAssessment(`media:${index}`),
  );
}

function modelCandidate(
  name: string,
  sourceMention: string,
  itemIndex: number,
): Record<string, unknown> {
  return {
    name,
    sourceMention,
    area: "",
    entityType: "poi",
    itemIndex,
    classification: "itinerary",
    modality: "caption",
    evidenceIds: ["caption:0"],
    confidence: 0.98,
    startMs: -1,
    endMs: -1,
  };
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
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
