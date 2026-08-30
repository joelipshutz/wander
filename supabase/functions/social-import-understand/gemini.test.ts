import {
  maximumInlineImageBytes,
  selectInlineImageIngestions,
  understandWithGemini,
  validatedGeminiUploadURL,
} from "./gemini.ts";
import type {
  EvidenceCatalog,
  MediaIngestion,
  RuntimeDependencies,
  SocialSource,
} from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

const geminiOrigin = "https://generativelanguage.googleapis.com";
const uploadURL =
  `${geminiOrigin}/upload/v1beta/files?upload_id=session-123&upload_protocol=resumable`;
const fileName = "files/video-123";
const fileURI = `${geminiOrigin}/v1beta/${fileName}`;

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
      return geminiResponse([]);
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

  assertEquals(result, { candidates: [], attemptCount: 1 });
  assertEquals(calls, ["start", "upload", "poll", "generate", "delete"]);
  assertEquals(ingestion.status, "ok");
  assertEquals(ingestion.bytes, undefined);
  const generateBody = generatedBodies[0] ?? null;
  const generationConfig = asRecord(generateBody?.generationConfig);
  assertEquals(generationConfig?.maxOutputTokens, 8_192);
  const parts = requestParts(generateBody);
  assertEquals(parts[1], {
    fileData: { mimeType: "video/mp4", fileUri: fileURI },
  });
  const evidence = JSON.parse(String(asRecord(parts.at(-1))?.text));
  assertEquals(evidence.allowed_media_evidence_ids, ["media:0"]);
});

Deno.test("Gemini requests bounded integer indexes and evidence arrays", async () => {
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
  const postContext = asRecord(rootProperties?.postContext);
  const postContextProperties = asRecord(postContext?.properties);
  assertEquals(postContextProperties?.declaredCount, {
    type: "integer",
    minimum: -1,
    maximum: 150,
  });
  assertEquals(postContextProperties?.declaredCountEvidenceIds, {
    type: "array",
    maxItems: 8,
    items: { type: "string" },
  });
  assertEquals(postContextProperties?.globalAreaEvidenceIds, {
    type: "array",
    maxItems: 8,
    items: { type: "string" },
  });

  const candidates = asRecord(rootProperties?.candidates);
  assertEquals(candidates?.maxItems, 300);
  const candidateItems = asRecord(candidates?.items);
  const candidateProperties = asRecord(candidateItems?.properties);
  assertEquals(candidateProperties?.itemIndex, {
    type: "integer",
    minimum: -1,
    maximum: 299,
  });
  assertEquals(candidateProperties?.evidenceIds, {
    type: "array",
    minItems: 1,
    maxItems: 8,
    items: { type: "string" },
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

Deno.test("inline images are selected under an aggregate raw-byte cap and excluded images cannot be cited", () => {
  const first = imageIngestion("media:0", 10 * 1_024 * 1_024);
  const second = imageIngestion("media:1", 3 * 1_024 * 1_024);

  const selected = selectInlineImageIngestions([first, second]);

  assertEquals(maximumInlineImageBytes, 12 * 1_024 * 1_024);
  assertEquals(selected.map((item) => item.mediaID), ["media:0"]);
  assertEquals(first.status, "ok");
  assert(first.bytes instanceof Uint8Array);
  assertEquals(second.status, "failed");
  assertEquals(second.errorCode, "gemini_inline_image_limit_exceeded");
  assertEquals(second.bytes, undefined);
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
