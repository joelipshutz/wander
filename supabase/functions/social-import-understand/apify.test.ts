import {
  acquireInstagramProfileAliases,
  acquireWithApify,
  maximumInstagramProfileAliases,
  minimumProfileEnrichmentGlobalBudgetMilliseconds,
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
  assertEquals(start.url.searchParams.get("timeout"), "10");
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

  await assertRejectsCode(
    () =>
      acquireInstagramProfileAliases(
        ["hvojai"],
        "private-apify-token",
        new Deadline(100_000, dependencies.now),
        dependencies,
      ),
    "deadline_exceeded",
  );
  assertEquals(
    calls.filter((call) => call.url.pathname.endsWith("/abort")).length,
    1,
  );
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
