import {
  acquireWithBrightData,
  defaultBrightDataInstagramPostsDatasetID,
  defaultBrightDataInstagramReelsDatasetID,
} from "./brightdata.ts";
import { parseSocialSource } from "./source.ts";
import type { RuntimeDependencies, SocialSource } from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

const postURL = "https://www.instagram.com/p/DcAU9e5DYcH";
const reelURL = "https://www.instagram.com/reel/DcmS0tZySTw";
const imageURL = "https://images.cdninstagram.com/media/bright-slide.jpg";
const videoURL = "https://images.cdninstagram.com/media/bright-reel.mp4";

Deno.test("Bright Data triggers the posts dataset and polls a bounded snapshot", async () => {
  const calls: ObservedCall[] = [];
  const delays: number[] = [];
  let polls = 0;
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    if (call.url.pathname === "/datasets/v3/scrape") {
      return Response.json({ snapshot_id: "snapshot_123" });
    }
    if (call.url.pathname === "/datasets/v3/snapshot/snapshot_123") {
      polls += 1;
      return polls === 1
        ? Response.json({ status: "running" }, { status: 202 })
        : Response.json([{
          url: postURL,
          description: "Eight places in Los Angeles.",
          post_content: [{ index: 0, type: "Photo", url: imageURL }],
        }]);
    }
    throw new Error(`unexpected fetch ${call.url}`);
  }, {
    sleep: (milliseconds) => {
      delays.push(milliseconds);
      return Promise.resolve();
    },
  });

  const evidence = await acquireWithBrightData(
    source(postURL),
    "private-bright-token",
    new Deadline(30_000, dependencies.now),
    dependencies,
  );

  assertEquals(evidence.caption, "Eight places in Los Angeles.");
  assertEquals(evidence.media.map((item) => item.url), [imageURL]);
  assertEquals(delays, [1_000]);
  const trigger = calls[0];
  assertEquals(trigger.url.origin, "https://api.brightdata.com");
  assertEquals(
    trigger.url.searchParams.get("dataset_id"),
    defaultBrightDataInstagramPostsDatasetID,
  );
  assertEquals(trigger.url.searchParams.get("include_errors"), "true");
  assertEquals(trigger.authorization, "Bearer private-bright-token");
  assertEquals(JSON.parse(trigger.body), { input: [{ url: postURL }] });
  assertEquals(
    calls[1].url.searchParams.get("format"),
    "json",
  );
});

Deno.test("Bright Data uses the reels dataset and accepts an immediate result", async () => {
  const calls: ObservedCall[] = [];
  const dependencies = runtime((input, init) => {
    const call = observe(input, init);
    calls.push(call);
    return Response.json([{
      url: reelURL,
      description: "Nine hikes around LA.",
      video_url: videoURL,
      thumbnail: imageURL,
    }]);
  });

  const evidence = await acquireWithBrightData(
    source(reelURL),
    "private-bright-token",
    new Deadline(30_000, dependencies.now),
    dependencies,
  );

  assertEquals(evidence.media[0].kind, "video");
  assertEquals(evidence.media[0].url, videoURL);
  assertEquals(
    calls[0].url.searchParams.get("dataset_id"),
    defaultBrightDataInstagramReelsDatasetID,
  );
  assertEquals(calls.length, 1);
});

Deno.test("Bright Data rejects an invalid configured dataset before network work", async () => {
  let fetchCount = 0;
  const dependencies = runtime(() => {
    fetchCount += 1;
    throw new Error("invalid dataset must not fetch");
  }, {
    env: (name) =>
      name === "WANDER_BRIGHTDATA_INSTAGRAM_POSTS_DATASET_ID"
        ? "https://attacker.test"
        : undefined,
  });

  await assertRejectsCode(
    () =>
      acquireWithBrightData(
        source(postURL),
        "private-bright-token",
        new Deadline(30_000, dependencies.now),
        dependencies,
      ),
    "brightdata_dataset_invalid",
  );
  assertEquals(fetchCount, 0);
});

type TestFetcher = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Response | Promise<Response>;

type ObservedCall = {
  url: URL;
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
    authorization: new Headers(init?.headers).get("authorization"),
    body: String(init?.body ?? ""),
  };
}

function source(value: string): SocialSource {
  const parsed = parseSocialSource(value);
  if (!parsed) throw new Error("invalid source fixture");
  return parsed;
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
