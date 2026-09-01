import { fetchMediaBytes, mayReceiveApifyAuthorization } from "./media.ts";
import { handleRequest } from "./handler.ts";
import type { RuntimeDependencies, SocialSource } from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

const instagramURL = "https://www.instagram.com/reel/Da38nrgtmjn";
const mediaURL = "https://images.cdninstagram.com/media/video.mp4";
const privateMediaURL =
  "https://api.apify.com/v2/key-value-stores/store-1/records/video.mp4";
const mp4 = new Uint8Array([
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x69,
  0x73,
  0x6f,
  0x6d,
]);

Deno.test("media fetch retries transport failures and retryable HTTP statuses", async () => {
  for (const failure of ["transport", 408, 429, 500, 599] as const) {
    let fetchCount = 0;
    const delays: number[] = [];
    const dependencies = runtime((input) => {
      assertEquals(String(input), mediaURL);
      fetchCount += 1;
      if (fetchCount === 1) {
        if (failure === "transport") {
          throw new TypeError("simulated connection reset");
        }
        return new Response("temporary failure", { status: failure });
      }
      return mediaResponse();
    }, {
      random: () => 1,
      sleep: (milliseconds) => {
        delays.push(milliseconds);
        return Promise.resolve();
      },
    });

    const result = await fetchMediaBytes(
      mediaURL,
      "video",
      1_024,
      source(),
      "apify-secret",
      new Deadline(10_000, dependencies.now),
      dependencies,
    );

    assertEquals(result.mimeType, "video/mp4");
    assertEquals(fetchCount, 2);
    assertEquals(delays, [250]);
  }
});

Deno.test("media retries stay bounded and keep authorization on the token host", async () => {
  const observed: Array<{ url: string; authorization: string | null }> = [];
  const delays: number[] = [];
  let privateCalls = 0;
  let publicCalls = 0;
  const dependencies = runtime((input, init) => {
    const url = String(input);
    observed.push({
      url,
      authorization: new Headers(init?.headers).get("authorization"),
    });
    if (url === privateMediaURL) {
      privateCalls += 1;
      if (privateCalls === 1) return new Response(null, { status: 503 });
      return new Response(null, {
        status: 302,
        headers: { location: mediaURL },
      });
    }
    if (url === mediaURL) {
      publicCalls += 1;
      if (publicCalls === 1) throw new TypeError("simulated connection reset");
      return mediaResponse();
    }
    throw new Error(`unexpected fetch ${url}`);
  }, {
    random: () => 1,
    sleep: (milliseconds) => {
      delays.push(milliseconds);
      return Promise.resolve();
    },
  });

  assert(mayReceiveApifyAuthorization(new URL(privateMediaURL)));
  const result = await fetchMediaBytes(
    privateMediaURL,
    "video",
    1_024,
    source(),
    "apify-secret",
    new Deadline(10_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.mimeType, "video/mp4");
  assertEquals(delays, [250, 500]);
  assertEquals(observed, [
    { url: privateMediaURL, authorization: "Bearer apify-secret" },
    { url: privateMediaURL, authorization: "Bearer apify-secret" },
    { url: mediaURL, authorization: null },
    { url: mediaURL, authorization: null },
  ]);
});

Deno.test("media fetch stops after three total attempts", async () => {
  for (const failure of ["transport", 503] as const) {
    let fetchCount = 0;
    const delays: number[] = [];
    const dependencies = runtime(() => {
      fetchCount += 1;
      if (failure === "transport") {
        throw new TypeError("simulated connection reset");
      }
      return new Response(null, { status: failure });
    }, {
      random: () => 1,
      sleep: (milliseconds) => {
        delays.push(milliseconds);
        return Promise.resolve();
      },
    });

    try {
      await fetchMediaBytes(
        mediaURL,
        "video",
        1_024,
        source(),
        "apify-secret",
        new Deadline(10_000, dependencies.now),
        dependencies,
      );
      throw new Error(`Expected exhausted ${failure} retries to fail`);
    } catch (error) {
      if (failure === "transport") {
        assert(error instanceof TypeError);
      } else {
        assertEquals(
          error instanceof SocialImportError ? error.code : null,
          "media_http_error",
        );
      }
    }
    assertEquals(fetchCount, 3);
    assertEquals(delays, [250, 500]);
  }
});

Deno.test("media fetch does not retry unsafe URLs, ordinary 4xx, type, or size failures", async () => {
  let unsafeFetchCount = 0;
  const unsafeDependencies = runtime(() => {
    unsafeFetchCount += 1;
    return mediaResponse();
  });
  await assertRejectsCode(
    () =>
      fetchMediaBytes(
        "https://127.0.0.1/video.mp4",
        "video",
        1_024,
        source(),
        "apify-secret",
        new Deadline(10_000, unsafeDependencies.now),
        unsafeDependencies,
      ),
    "unsafe_media_url",
  );
  assertEquals(unsafeFetchCount, 0);

  const cases: Array<{
    name: string;
    response: () => Response;
    maximumBytes: number;
    expectedCode: string;
  }> = [
    {
      name: "ordinary 4xx",
      response: () => new Response(null, { status: 404 }),
      maximumBytes: 1_024,
      expectedCode: "media_http_error",
    },
    {
      name: "unsupported media type",
      response: () =>
        new Response("not video", {
          headers: { "content-type": "text/html" },
        }),
      maximumBytes: 1_024,
      expectedCode: "unsupported_media_type",
    },
    {
      name: "oversized response",
      response: () =>
        new Response(mp4, {
          headers: {
            "content-length": String(mp4.byteLength),
            "content-type": "video/mp4",
          },
        }),
      maximumBytes: mp4.byteLength - 1,
      expectedCode: "media_too_large",
    },
  ];

  for (const testCase of cases) {
    let fetchCount = 0;
    let sleepCount = 0;
    const dependencies = runtime(() => {
      fetchCount += 1;
      return testCase.response();
    }, {
      sleep: () => {
        sleepCount += 1;
        return Promise.resolve();
      },
    });
    await assertRejectsCode(
      () =>
        fetchMediaBytes(
          mediaURL,
          "video",
          testCase.maximumBytes,
          source(),
          "apify-secret",
          new Deadline(10_000, dependencies.now),
          dependencies,
        ),
      testCase.expectedCode,
      testCase.name,
    );
    assertEquals(fetchCount, 1, testCase.name);
    assertEquals(sleepCount, 0, testCase.name);
  }
});

Deno.test("media retry stops before another request when the deadline expires", async () => {
  let now = 1_000;
  let fetchCount = 0;
  const delays: number[] = [];
  const dependencies = runtime(() => {
    fetchCount += 1;
    throw new TypeError("simulated connection reset");
  }, {
    now: () => now,
    random: () => 1,
    sleep: (milliseconds) => {
      delays.push(milliseconds);
      now += milliseconds;
      return Promise.resolve();
    },
  });

  await assertRejectsCode(
    () =>
      fetchMediaBytes(
        mediaURL,
        "video",
        1_024,
        source(),
        "apify-secret",
        new Deadline(200, dependencies.now),
        dependencies,
      ),
    "deadline_exceeded",
  );
  assertEquals(fetchCount, 1);
  assertEquals(delays, [200]);
});

Deno.test("media retry sleep stops immediately when the request is cancelled", async () => {
  const controller = new AbortController();
  let fetchCount = 0;
  let sleepCount = 0;
  const dependencies = runtime(() => {
    fetchCount += 1;
    return new Response(null, { status: 503 });
  }, {
    random: () => 1,
    sleep: () => {
      sleepCount += 1;
      controller.abort();
      return new Promise<void>(() => {});
    },
  });

  await assertRejectsCode(
    () =>
      fetchMediaBytes(
        mediaURL,
        "video",
        1_024,
        source(),
        "apify-secret",
        new Deadline(10_000, dependencies.now),
        dependencies,
        controller.signal,
      ),
    "request_cancelled",
  );
  assertEquals(fetchCount, 1);
  assertEquals(sleepCount, 1);
});

Deno.test("handler threads request cancellation through media and still finishes admission", async () => {
  const controller = new AbortController();
  let mediaFetchCount = 0;
  let mediaSignalAborted = false;
  let finishCount = 0;
  let geminiFetchCount = 0;
  const dependencies = runtime((input, init) => {
    const url = String(input);
    if (url.endsWith("/rest/v1/rpc/current_profile")) {
      return Response.json([{ id: "user-1" }]);
    }
    if (url.endsWith("/rest/v1/rpc/begin_social_import_paid_work")) {
      return Response.json([{
        admitted: true,
        decision: "started",
        admission_id: "10000000-0000-4000-8000-000000000001",
      }]);
    }
    if (
      url.endsWith("/rest/v1/rpc/finish_social_import_paid_work_service")
    ) {
      finishCount += 1;
      const headers = new Headers(init?.headers);
      assertEquals(headers.get("apikey"), "service-role-key");
      assertEquals(headers.get("authorization"), "Bearer service-role-key");
      return Response.json(true);
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
        videoUrl: mediaURL,
      }]);
    }
    if (url === mediaURL) {
      mediaFetchCount += 1;
      controller.abort();
      mediaSignalAborted = init?.signal?.aborted ?? false;
      throw new TypeError("simulated aborted media fetch");
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      geminiFetchCount += 1;
      throw new Error("cancelled request must not reach Gemini");
    }
    throw new Error(`unexpected fetch ${url}`);
  }, {
    env: (name) =>
      ({
        SUPABASE_URL: "https://project.supabase.co",
        SUPABASE_PUBLISHABLE_KEY: "publishable-key",
        SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
        WANDER_APIFY_TOKEN: "apify-secret",
        WANDER_GEMINI_API_KEY: "gemini-secret",
        WANDER_GOOGLE_PLACES_API_KEY: "google-secret",
      })[name],
  });
  const request = new Request("https://function.test", {
    method: "POST",
    headers: {
      authorization: "Bearer user-token",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      schema_version: 1,
      platform: "instagram",
      url: instagramURL,
      client_request_id: "cancel-media-request",
    }),
    signal: controller.signal,
  });

  const payload = await (await handleRequest(request, dependencies)).json();

  assertEquals(mediaFetchCount, 1);
  assertEquals(mediaSignalAborted, true);
  assertEquals(geminiFetchCount, 0);
  assertEquals(finishCount, 1);
  assertEquals(payload.failure_category, "media_unavailable");
});

type RuntimeOverrides = Partial<
  Pick<RuntimeDependencies, "env" | "now" | "random" | "sleep">
>;

type TestFetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Response | Promise<Response>;

function runtime(
  fetcher: TestFetcher,
  overrides: RuntimeOverrides = {},
): RuntimeDependencies {
  return {
    fetch: (async (input, init) => await fetcher(input, init)) as typeof fetch,
    env: overrides.env ?? (() => undefined),
    now: overrides.now ?? (() => 1_000),
    random: overrides.random ?? (() => 0),
    sleep: overrides.sleep ?? (() => Promise.resolve()),
  };
}

function source(): SocialSource {
  return {
    platform: "instagram",
    contentType: "reel",
    url: instagramURL,
    sourceID: "Da38nrgtmjn",
  };
}

function mediaResponse(): Response {
  return new Response(mp4, { headers: { "content-type": "video/mp4" } });
}

async function assertRejectsCode(
  operation: () => Promise<unknown>,
  expectedCode: string,
  context = "",
): Promise<void> {
  try {
    await operation();
  } catch (error) {
    assertEquals(
      error instanceof SocialImportError ? error.code : null,
      expectedCode,
      context,
    );
    return;
  }
  throw new Error(
    `Expected ${expectedCode}${context ? ` for ${context}` : ""}`,
  );
}

function assert(
  value: unknown,
  message = "Expected condition to be true",
): asserts value {
  if (!value) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown, context = ""): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `${context ? `${context}: ` : ""}Expected ${
        JSON.stringify(expected)
      }, received ${JSON.stringify(actual)}`,
    );
  }
}
