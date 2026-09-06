import {
  acquireSocialEvidence,
  mergeInstagramEvidence,
} from "./acquisition.ts";
import { parseSocialSource } from "./source.ts";
import type {
  AcquisitionEvidence,
  RuntimeDependencies,
  SocialSource,
} from "./types.ts";
import { Deadline } from "./types.ts";

const postURL = "https://www.instagram.com/p/DcAU9e5DYcH";
const reelURL = "https://www.instagram.com/reel/DcmS0tZySTw";
const brightImageURL = "https://images.cdninstagram.com/media/bright-640.jpg";
const apifyImageURL = "https://images.cdninstagram.com/media/apify-4096.jpg";
const videoURL = "https://images.cdninstagram.com/media/reel.mp4";

Deno.test("Instagram reels use Bright Data without starting Apify when Bright succeeds", async () => {
  const calls: string[] = [];
  const dependencies = runtime((input) => {
    const url = String(input);
    calls.push(url);
    if (url.includes("api.brightdata.com/datasets/v3/scrape")) {
      return Response.json([{
        url: reelURL,
        description: "A Los Angeles hike.",
        video_url: videoURL,
      }]);
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const result = await acquireSocialEvidence(
    source(reelURL),
    configuration(),
    new Deadline(30_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.provider, "brightdata");
  assertEquals(result.evidence.media[0].url, videoURL);
  assertEquals(calls.some((url) => url.includes("api.apify.com")), false);
});

Deno.test("Instagram reels fall back to Apify after a Bright Data failure", async () => {
  const calls: string[] = [];
  const dependencies = runtime((input) => {
    const url = String(input);
    calls.push(url);
    if (url.includes("api.brightdata.com/datasets/v3/scrape")) {
      return Response.json({}, { status: 503 });
    }
    if (url.includes("/v2/actors/apify~instagram-scraper/runs")) {
      return Response.json({
        data: {
          id: "fallback-run",
          status: "SUCCEEDED",
          defaultDatasetId: "fallback-dataset",
        },
      });
    }
    if (url.includes("/v2/datasets/fallback-dataset/items")) {
      return Response.json([{
        inputUrl: reelURL,
        description: "A Los Angeles hike.",
        videoUrl: videoURL,
      }]);
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const result = await acquireSocialEvidence(
    source(reelURL),
    configuration(),
    new Deadline(30_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.provider, "apify");
  assertEquals(result.evidence.media[0].url, videoURL);
  assertEquals(calls.some((url) => url.includes("api.apify.com")), true);
});

Deno.test("Instagram posts merge Bright metadata with Apify image media", async () => {
  const dependencies = runtime((input) => {
    const url = String(input);
    if (url.includes("api.brightdata.com/datasets/v3/scrape")) {
      return Response.json([{
        url: postURL,
        description: "Bright caption",
        location: ["Los Angeles", "California", "United States"],
        post_content: [{
          index: 0,
          type: "Photo",
          url: brightImageURL,
          alt_text: "Bright accessibility text",
          tagged_users: [{
            username: "brightvenue",
            full_name: "Bright Venue",
          }],
        }],
      }]);
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
        inputUrl: postURL,
        description: "Apify caption",
        locationName: "West Hollywood",
        childPosts: [{
          displayUrl: apifyImageURL,
          taggedUsers: [{ username: "apifyvenue", fullName: "Apify Venue" }],
        }],
      }]);
    }
    throw new Error(`unexpected fetch ${url}`);
  });

  const result = await acquireSocialEvidence(
    source(postURL),
    configuration(),
    new Deadline(30_000, dependencies.now),
    dependencies,
  );

  assertEquals(result.provider, "brightdata_apify");
  assertEquals(result.evidence.caption, "Bright caption");
  assertEquals(result.evidence.media[0].url, apifyImageURL);
  assertEquals(
    result.evidence.media[0].altText,
    "Bright accessibility text",
  );
  assertEquals(result.evidence.media[0].taggedProfiles, [
    { username: "brightvenue", fullName: "Bright Venue" },
    { username: "apifyvenue", fullName: "Apify Venue" },
  ]);
  assertEquals(result.evidence.taggedLocations, [
    { name: "Los Angeles", area: "California, United States" },
    { name: "West Hollywood", area: null },
  ]);
});

Deno.test("evidence merge keeps Bright video and an Apify-only image tail", () => {
  const result = mergeInstagramEvidence(
    evidence([
      media(0, "video", videoURL, "Bright video alt"),
    ]),
    evidence([
      media(0, "video", `${videoURL}?apify=1`, null),
      media(1, "image", apifyImageURL, "Apify tail"),
    ]),
  );

  assertEquals(result.media.map((item) => item.url), [videoURL, apifyImageURL]);
  assertEquals(result.media.map((item) => item.id), ["media:0", "media:1"]);
});

function configuration() {
  return {
    apifyToken: "private-apify-token",
    brightDataToken: "private-bright-token",
    instagramMode: "brightdata_hybrid" as const,
  };
}

function evidence(
  mediaItems: AcquisitionEvidence["media"],
): AcquisitionEvidence {
  return { title: null, caption: null, taggedLocations: [], media: mediaItems };
}

function media(
  index: number,
  kind: "image" | "video",
  url: string,
  altText: string | null,
) {
  return {
    id: `media:${index}`,
    index,
    kind,
    url,
    thumbnailURL: null,
    altText,
  };
}

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

function source(value: string): SocialSource {
  const parsed = parseSocialSource(value);
  if (!parsed) throw new Error("invalid source fixture");
  return parsed;
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
