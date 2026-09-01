import {
  acquireInstagramProfileAliases,
  acquireWithApify,
  maximumInstagramProfileAliases,
  minimumProfileEnrichmentGlobalBudgetMilliseconds,
  normalizeApifyDataset,
  normalizeInstagramProfileAliases,
} from "./apify.ts";
import { parseSocialSource } from "./source.ts";
import type { RuntimeDependencies, SocialSource } from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

const instagramURL = "https://www.instagram.com/p/DcAU9e5DYcH";
const imageURL = "https://images.cdninstagram.com/media/photo.jpg";

Deno.test("Apify starts immediately, polls a known run, and reads its dataset", async () => {
  const calls: ObservedCall[] = [];
  const delays: number[] = [];
  let pollCount = 0;
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname.includes("/v2/actors/") &&
      call.url.pathname.endsWith("/runs")
    ) {
      return Response.json({ data: { id: "run_123", status: "READY" } });
    }
    if (call.url.pathname === "/v2/actor-runs/run_123") {
      pollCount += 1;
      return Response.json({
        data: pollCount === 1 ? { id: "run_123", status: "RUNNING" } : {
          id: "run_123",
          status: "SUCCEEDED",
          defaultDatasetId: "dataset_123",
        },
      });
    }
    if (call.url.pathname === "/v2/datasets/dataset_123/items") {
      return Response.json([{
        inputUrl: instagramURL,
        description: "Visit Carbon Beach Club in Malibu.",
        images: [imageURL],
      }]);
    }
    throw new Error(`unexpected fetch ${call.url}`);
  }, {
    sleep: (milliseconds) => {
      delays.push(milliseconds);
      return Promise.resolve();
    },
  });

  const result = await acquireWithApify(
    source(),
    "private-apify-token",
    new Deadline(30_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.caption, "Visit Carbon Beach Club in Malibu.");
  assertEquals(result.media.map((item) => item.url), [imageURL]);
  assertEquals(delays, [750, 1_000]);
  assertEquals(pollCount, 2);
  const start = calls[0];
  assertEquals(start.url.origin, "https://api.apify.com");
  assertEquals(start.url.pathname, "/v2/actors/apify~instagram-scraper/runs");
  assertEquals(start.url.searchParams.get("waitForFinish"), "0");
  assertEquals(start.url.searchParams.get("timeout"), "90");
  assertEquals(start.url.searchParams.get("maxItems"), "1");
  assertEquals(start.url.searchParams.get("maxTotalChargeUsd"), "1");
  assertEquals(start.url.searchParams.has("token"), false);
  assertEquals(start.authorization, "Bearer private-apify-token");
  assertEquals(
    calls.some((call) => call.url.pathname.endsWith("/abort")),
    false,
  );
});

Deno.test("ordered carousel children remain canonical over top-level media", () => {
  const slideURLs = Array.from(
    { length: 17 },
    (_, index) =>
      `https://images.cdninstagram.com/media/carousel-slide-${index + 1}.jpg`,
  );
  const evidence = normalizeApifyDataset([{
    inputUrl: instagramURL,
    childPosts: slideURLs.map((url, index) => ({
      displayUrl: url,
      alt: `Carousel slide ${index + 1}`,
    })),
    images: [
      slideURLs[0],
      "https://images.cdninstagram.com/media/duplicate-top-level-image.jpg",
    ],
    photos: [
      { url: slideURLs[1] },
      {
        url:
          "https://images.cdninstagram.com/media/duplicate-top-level-photo.jpg",
      },
    ],
    displayUrl: slideURLs[0],
    videoUrl:
      "https://scontent.cdninstagram.com/media/duplicate-top-level-video.mp4",
  }], source());

  assertEquals(evidence.media.map((item) => item.url), slideURLs);
  assertEquals(
    evidence.media.map((item) => item.index),
    Array.from({ length: 17 }, (_, index) => index),
  );
  assertEquals(
    evidence.media.map((item) => item.id),
    Array.from({ length: 17 }, (_, index) => `media:${index}`),
  );
});

Deno.test("a partial childPosts tail does not suppress a complete declared carousel", () => {
  const slideURLs = Array.from(
    { length: 17 },
    (_, index) =>
      `https://images.cdninstagram.com/media/declared-slide-${index + 1}.jpg`,
  );
  const evidence = normalizeApifyDataset([{
    inputUrl: instagramURL,
    childPostsCount: 17,
    childPosts: slideURLs.slice(14).map((url, index) => ({
      displayUrl: url,
      alt: `Partial child slide ${index + 15}`,
    })),
    images: slideURLs,
    displayUrl: slideURLs[0],
  }], source());

  assertEquals(evidence.media.map((item) => item.url), slideURLs);
  assertEquals(
    evidence.media.map((item) => item.index),
    Array.from({ length: 17 }, (_, index) => index),
  );
  assertEquals(
    evidence.media.map((item) => item.id),
    Array.from({ length: 17 }, (_, index) => `media:${index}`),
  );
});

Deno.test("top-level media remains a fallback for unusable children", () => {
  const evidence = normalizeApifyDataset([{
    inputUrl: instagramURL,
    childPosts: [null, {}, { displayUrl: "" }],
    images: [imageURL],
    displayUrl: imageURL,
  }], source());

  assertEquals(evidence.media.map((item) => item.url), [imageURL]);
});

Deno.test("a matching restricted Instagram item triggers one bounded media fallback", async () => {
  const calls: ObservedCall[] = [];
  const fallbackMediaURL =
    "https://api.apify.com/v2/key-value-stores/store_123/records/video.mp4?signature=opaque";
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (call.url.pathname === "/v2/actors/apify~instagram-scraper/runs") {
      return Response.json({
        data: {
          id: "primary_restricted_run",
          status: "SUCCEEDED",
          defaultDatasetId: "primary_restricted_dataset",
        },
      });
    }
    if (
      call.url.pathname === "/v2/datasets/primary_restricted_dataset/items"
    ) {
      return Response.json([{
        url: instagramURL,
        restricted_age: 21,
        error: "restricted_page",
        errorDescription: "Restricted access, only partial data available",
      }]);
    }
    if (
      call.url.pathname ===
        "/v2/actors/crawlerbros~instagram-downloader-api/runs"
    ) {
      return Response.json({
        data: {
          id: "fallback_run",
          status: "SUCCEEDED",
          defaultDatasetId: "fallback_dataset",
        },
      });
    }
    if (call.url.pathname === "/v2/datasets/fallback_dataset/items") {
      return Response.json([{
        post_url: `${instagramURL}/`,
        username: "must_not_be_used_as_caption",
        type: "video",
        download_status: "finished",
        download_url: fallbackMediaURL,
      }]);
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });

  const result = await acquireWithApify(
    source(),
    "private-apify-token",
    new Deadline(112_000, dependencies.now),
    dependencies,
  );

  assertEquals(result, {
    title: null,
    caption: null,
    taggedLocations: [],
    media: [{
      index: 0,
      kind: "video",
      url: fallbackMediaURL,
      thumbnailURL: null,
      altText: null,
      id: "media:0",
    }],
  });
  const fallbackStarts = calls.filter((call) =>
    call.url.pathname ===
      "/v2/actors/crawlerbros~instagram-downloader-api/runs"
  );
  assertEquals(fallbackStarts.length, 1);
  const fallbackStart = fallbackStarts[0];
  assertEquals(fallbackStart.url.searchParams.get("waitForFinish"), "0");
  assertEquals(fallbackStart.url.searchParams.get("timeout"), "55");
  assertEquals(fallbackStart.url.searchParams.get("maxItems"), "20");
  assertEquals(fallbackStart.url.searchParams.get("maxTotalChargeUsd"), "0.10");
  assertEquals(fallbackStart.url.searchParams.has("token"), false);
  assertEquals(fallbackStart.authorization, "Bearer private-apify-token");
  assertEquals(JSON.parse(fallbackStart.body), {
    postUrls: [instagramURL],
  });
  const fallbackDataset = calls[3];
  assertEquals(
    fallbackDataset.url.searchParams.get("fields"),
    "post_url,type,download_status,download_url",
  );
  assertEquals(fallbackDataset.url.searchParams.get("limit"), "20");
});

Deno.test("an ordinary matching provider item error does not trigger the restricted fallback", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (call.url.pathname === "/v2/actors/apify~instagram-scraper/runs") {
      return Response.json({
        data: {
          id: "primary_error_run",
          status: "SUCCEEDED",
          defaultDatasetId: "primary_error_dataset",
        },
      });
    }
    if (call.url.pathname === "/v2/datasets/primary_error_dataset/items") {
      return Response.json([{
        url: instagramURL,
        error: "private_page",
        errorDescription: "not a restricted-page media fallback",
      }]);
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(112_000, dependencies.now),
        dependencies,
      ),
    "vendor_item_error",
  );
  assertEquals(
    calls.filter((call) => call.url.pathname.includes("crawlerbros")).length,
    0,
  );
});

Deno.test("a restricted primary item must match the requested source before fallback", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (call.url.pathname === "/v2/actors/apify~instagram-scraper/runs") {
      return Response.json({
        data: {
          id: "primary_mismatch_run",
          status: "SUCCEEDED",
          defaultDatasetId: "primary_mismatch_dataset",
        },
      });
    }
    if (call.url.pathname === "/v2/datasets/primary_mismatch_dataset/items") {
      return Response.json([{
        url: "https://www.instagram.com/reel/OtherSource123/",
        error: "restricted_page",
        errorDescription: "Restricted access, only partial data available",
      }]);
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(112_000, dependencies.now),
        dependencies,
      ),
    "vendor_item_error",
  );
  assertEquals(
    calls.filter((call) => call.url.pathname.includes("crawlerbros")).length,
    0,
  );
});

Deno.test("the restricted fallback rejects a mismatched downloader row", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = restrictedFallbackRuntime(calls, () =>
    Response.json([{
      post_url: "https://www.instagram.com/reel/OtherSource123/",
      type: "video",
      download_status: "finished",
      download_url:
        "https://api.apify.com/v2/key-value-stores/store_123/records/video.mp4?signature=opaque",
    }]));

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(112_000, dependencies.now),
        dependencies,
      ),
    "vendor_source_mismatch",
  );
  assertEquals(
    calls.filter((call) => call.url.pathname.includes("crawlerbros")).length,
    1,
  );
});

Deno.test("a restricted media fallback failure is returned without a second fallback", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = restrictedFallbackRuntime(
    calls,
    () => Response.json({ data: { id: "fallback_run", status: "FAILED" } }),
    true,
  );

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(112_000, dependencies.now),
        dependencies,
      ),
    "apify_run_failed",
  );
  assertEquals(
    calls.filter((call) => call.url.pathname.includes("crawlerbros")).length,
    1,
  );
});

Deno.test("a terminal failed provider run is not sent a redundant abort", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname.includes("/v2/actors/") &&
      call.url.pathname.endsWith("/runs")
    ) {
      return Response.json({ data: { id: "run_failed", status: "READY" } });
    }
    if (call.url.pathname === "/v2/actor-runs/run_failed") {
      return Response.json({ data: { id: "run_failed", status: "FAILED" } });
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(30_000, dependencies.now),
        dependencies,
      ),
    "apify_run_failed",
  );
  assertEquals(calls.length, 2);
  assertEquals(
    calls.some((call) => call.url.pathname.endsWith("/abort")),
    false,
  );
});

Deno.test("deadline expiry best-effort aborts the exact nonterminal run", async () => {
  const calls: ObservedCall[] = [];
  let now = 1_000;
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname.includes("/v2/actors/") &&
      call.url.pathname.endsWith("/runs")
    ) {
      return Response.json({
        data: { id: "run-timeout_1", status: "RUNNING" },
      });
    }
    if (call.url.pathname === "/v2/actor-runs/run-timeout_1/abort") {
      return Response.json({
        data: { id: "run-timeout_1", status: "ABORTING" },
      });
    }
    throw new Error(`unexpected fetch ${call.url}`);
  }, {
    now: () => now,
    sleep: (milliseconds) => {
      now += milliseconds;
      return Promise.resolve();
    },
  });

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(750, dependencies.now),
        dependencies,
      ),
    "deadline_exceeded",
  );

  const abortCalls = calls.filter((call) =>
    call.url.pathname.endsWith("/abort")
  );
  assertEquals(abortCalls.length, 1);
  const abort = abortCalls[0];
  assertEquals(abort.method, "POST");
  assertEquals(abort.url.origin, "https://api.apify.com");
  assertEquals(abort.url.pathname, "/v2/actor-runs/run-timeout_1/abort");
  assertEquals(abort.url.search, "?gracefully=true");
  assertEquals(abort.url.searchParams.has("token"), false);
  assertEquals(abort.authorization, "Bearer private-apify-token");
});

Deno.test("request cancellation aborts a known nonterminal run", async () => {
  const controller = new AbortController();
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname.includes("/v2/actors/") &&
      call.url.pathname.endsWith("/runs")
    ) {
      return Response.json({ data: { id: "run_cancel_1", status: "READY" } });
    }
    if (call.url.pathname === "/v2/actor-runs/run_cancel_1/abort") {
      return Response.json({
        data: { id: "run_cancel_1", status: "ABORTING" },
      });
    }
    throw new Error(`unexpected fetch ${call.url}`);
  }, {
    sleep: () => {
      controller.abort();
      return Promise.resolve();
    },
  });

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(30_000, dependencies.now),
        dependencies,
        controller.signal,
      ),
    "apify_run_cancelled",
  );
  assertEquals(
    calls.filter((call) => call.url.pathname.endsWith("/abort")).length,
    1,
  );
});

Deno.test("an already-cancelled request never starts paid work", async () => {
  const controller = new AbortController();
  controller.abort();
  let fetchCount = 0;
  const dependencies = runtime(() => {
    fetchCount += 1;
    throw new Error("cancelled request must not fetch");
  });

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(30_000, dependencies.now),
        dependencies,
        controller.signal,
      ),
    "apify_run_cancelled",
  );
  assertEquals(fetchCount, 0);
});

Deno.test("terminal success never aborts, including when dataset retrieval fails", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname.includes("/v2/actors/") &&
      call.url.pathname.endsWith("/runs")
    ) {
      return Response.json({
        data: {
          id: "run_complete_1",
          status: "SUCCEEDED",
          defaultDatasetId: "dataset_complete_1",
        },
      });
    }
    if (call.url.pathname === "/v2/datasets/dataset_complete_1/items") {
      return Response.json({ error: "private detail" }, { status: 503 });
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(30_000, dependencies.now),
        dependencies,
      ),
    "apify_dataset_http_error",
  );
  assertEquals(
    calls.some((call) => call.url.pathname.endsWith("/abort")),
    false,
  );
});

Deno.test("profile enrichment is capped, field-limited, and returns identity aliases only", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname ===
        "/v2/actors/apify~instagram-profile-scraper/runs"
    ) {
      return Response.json({
        data: {
          id: "profile_run_1",
          status: "SUCCEEDED",
          defaultDatasetId: "profile_dataset_1",
        },
      });
    }
    if (call.url.pathname === "/v2/datasets/profile_dataset_1/items") {
      return Response.json([{
        username: "hvojai",
        fullName: "Hip Vegan",
        biography: "must not be retained",
        externalUrl: "https://private.example",
      }]);
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });

  const result = await acquireInstagramProfileAliases(
    ["hvojai"],
    "private-apify-token",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result, [{ username: "hvojai", fullName: "Hip Vegan" }]);
  const start = calls[0];
  assertEquals(start.url.searchParams.get("waitForFinish"), "0");
  assertEquals(start.url.searchParams.get("timeout"), "18");
  assertEquals(
    start.url.searchParams.get("maxItems"),
    String(maximumInstagramProfileAliases),
  );
  assertEquals(start.url.searchParams.get("maxTotalChargeUsd"), "0.10");
  assertEquals(JSON.parse(start.body), {
    usernames: ["hvojai"],
    includeAboutSection: false,
  });
  const dataset = calls[1];
  assertEquals(dataset.url.searchParams.get("fields"), "username,fullName");
  assertEquals(
    dataset.url.searchParams.get("limit"),
    String(maximumInstagramProfileAliases),
  );
});

Deno.test("profile enrichment retains aliases from a timed-out run's partial dataset", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname ===
        "/v2/actors/apify~instagram-profile-scraper/runs"
    ) {
      return Response.json({
        data: {
          id: "profile_run_partial",
          status: "TIMED-OUT",
          defaultDatasetId: "profile_dataset_partial",
        },
      });
    }
    if (call.url.pathname === "/v2/datasets/profile_dataset_partial/items") {
      return Response.json([
        { username: "bartsbooksojai", fullName: "Bart's Books" },
        { username: "thedutchessojai", fullName: "The Dutchess" },
      ]);
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });

  const result = await acquireInstagramProfileAliases(
    ["bartsbooksojai", "thedutchessojai"],
    "private-apify-token",
    new Deadline(100_000, dependencies.now),
    dependencies,
  );

  assertEquals(result, [
    { username: "bartsbooksojai", fullName: "Bart's Books" },
    { username: "thedutchessojai", fullName: "The Dutchess" },
  ]);
  assertEquals(calls.length, 2);
});

Deno.test("primary acquisition rejects a timed-out run even when a partial dataset exists", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname.includes("/v2/actors/") &&
      call.url.pathname.endsWith("/runs")
    ) {
      return Response.json({
        data: {
          id: "primary_run_partial",
          status: "TIMED_OUT",
          defaultDatasetId: "primary_dataset_partial",
        },
      });
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });

  await assertRejectsCode(
    () =>
      acquireWithApify(
        source(),
        "private-apify-token",
        new Deadline(30_000, dependencies.now),
        dependencies,
      ),
    "apify_run_failed",
  );
  assertEquals(calls.length, 1);
});

Deno.test("profile normalization rejects mismatches, duplicates, and empty names", () => {
  const result = normalizeInstagramProfileAliases(
    [
      { username: "hvojai", fullName: "Hip Vegan" },
      { username: "hvojai", fullName: "Conflicting Duplicate" },
      { username: "bartsbooksojai", fullName: "" },
      { username: "unexpected", fullName: "Unrequested Account" },
      { username: "thedutchessojai", fullName: "The Dutchess" },
      { username: "@farmerandthecookojai", fullName: "Farmer and the Cook" },
    ],
    ["hvojai", "bartsbooksojai", "thedutchessojai", "farmerandthecookojai"],
  );

  assertEquals(result, [{
    username: "thedutchessojai",
    fullName: "The Dutchess",
  }]);
});

Deno.test("profile enrichment skips paid work when the global budget is low", async () => {
  let fetchCount = 0;
  const dependencies = runtime(() => {
    fetchCount += 1;
    throw new Error("low-budget enrichment must not fetch");
  });

  const result = await acquireInstagramProfileAliases(
    ["hvojai"],
    "private-apify-token",
    new Deadline(
      minimumProfileEnrichmentGlobalBudgetMilliseconds - 1,
      dependencies.now,
    ),
    dependencies,
  );

  assertEquals(result, []);
  assertEquals(fetchCount, 0);
});

Deno.test("profile child deadline aborts its exact nonterminal run", async () => {
  const calls: ObservedCall[] = [];
  let now = 1_000;
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (
      call.url.pathname ===
        "/v2/actors/apify~instagram-profile-scraper/runs"
    ) {
      return Response.json({
        data: { id: "profile_run_timeout", status: "RUNNING" },
      });
    }
    if (call.url.pathname === "/v2/actor-runs/profile_run_timeout") {
      return Response.json({
        data: { id: "profile_run_timeout", status: "RUNNING" },
      });
    }
    if (
      call.url.pathname === "/v2/actor-runs/profile_run_timeout/abort"
    ) {
      return Response.json({
        data: { id: "profile_run_timeout", status: "ABORTING" },
      });
    }
    throw new Error(`unexpected fetch ${call.url}`);
  }, {
    now: () => now,
    sleep: (milliseconds) => {
      now += milliseconds;
      return Promise.resolve();
    },
  });

  const parentDeadline = new Deadline(100_000, dependencies.now);
  await assertRejectsCode(
    () =>
      acquireInstagramProfileAliases(
        ["hvojai"],
        "private-apify-token",
        parentDeadline,
        dependencies,
      ),
    "deadline_exceeded",
  );
  assertEquals(
    calls.filter((call) => call.url.pathname.endsWith("/abort")).length,
    1,
  );
  assertEquals(parentDeadline.remaining() >= 70_000, true);
});

type TestFetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Response | Promise<Response>;

type ObservedCall = {
  url: URL;
  method: string;
  authorization: string | null;
  body: string;
};

function restrictedFallbackRuntime(
  calls: ObservedCall[],
  fallbackResponse: () => Response,
  failAtActorRun = false,
): RuntimeDependencies {
  return runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (call.url.pathname === "/v2/actors/apify~instagram-scraper/runs") {
      return Response.json({
        data: {
          id: "primary_restricted_run",
          status: "SUCCEEDED",
          defaultDatasetId: "primary_restricted_dataset",
        },
      });
    }
    if (
      call.url.pathname === "/v2/datasets/primary_restricted_dataset/items"
    ) {
      return Response.json([{
        url: instagramURL,
        restricted_age: 21,
        error: "restricted_page",
        errorDescription: "Restricted access, only partial data available",
      }]);
    }
    if (
      call.url.pathname ===
        "/v2/actors/crawlerbros~instagram-downloader-api/runs"
    ) {
      return failAtActorRun ? fallbackResponse() : Response.json({
        data: {
          id: "fallback_run",
          status: "SUCCEEDED",
          defaultDatasetId: "fallback_dataset",
        },
      });
    }
    if (call.url.pathname === "/v2/datasets/fallback_dataset/items") {
      return fallbackResponse();
    }
    throw new Error(`unexpected fetch ${call.url}`);
  });
}

function runtime(
  fetcher: TestFetcher,
  overrides: Partial<RuntimeDependencies> = {},
): RuntimeDependencies {
  return {
    fetch:
      ((input, init) => Promise.resolve(fetcher(input, init))) as typeof fetch,
    env: () => undefined,
    now: () => 1_000,
    sleep: async () => {},
    random: () => 0,
    ...overrides,
  };
}

function observe(input: RequestInfo | URL, init?: RequestInit): ObservedCall {
  return {
    url: new URL(String(input)),
    method: init?.method ?? "GET",
    authorization: new Headers(init?.headers).get("authorization"),
    body: String(init?.body ?? ""),
  };
}

function source(): SocialSource {
  const value = parseSocialSource(instagramURL);
  if (!value) throw new Error("invalid source fixture");
  return value;
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

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
