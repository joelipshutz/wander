import {
  ingestAcquiredMedia,
  maximumImageBytes,
  maximumTotalMediaBytes,
} from "./media.ts";
import { parseSocialSource } from "./source.ts";
import { Deadline } from "./types.ts";
import type { AcquiredMedia, RuntimeDependencies } from "./types.ts";

const source = parseSocialSource("https://www.instagram.com/p/Fixture123/")!;
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xdb, 0, 1]);
const media = (count: number): AcquiredMedia[] =>
  Array.from({ length: count }, (_, index) => ({
    id: `media:${index}`,
    index,
    kind: "image",
    thumbnailURL: null,
    altText: null,
    url: `https://images.cdninstagram.com/media/${index}.jpg`,
  }));
const runtime = (
  fetcher: RuntimeDependencies["fetch"],
): RuntimeDependencies => ({
  fetch: fetcher,
  env: () => undefined,
  now: Date.now,
  sleep: async () => {},
  random: () => 0,
});
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("carousel downloads overlap, preserve source order, and never exceed three active requests", async () => {
  let active = 0;
  let peak = 0;
  const dependencies = runtime(async (input) => {
    const index = Number(
      new URL(String(input)).pathname.split("/").at(-1)!.split(".")[0],
    );
    active += 1;
    peak = Math.max(peak, active);
    await new Promise((resolve) => setTimeout(resolve, (3 - index % 3) * 2));
    active -= 1;
    return new Response(new Uint8Array([...jpeg, index]), {
      headers: { "content-type": "image/jpeg" },
    });
  });
  const result = await ingestAcquiredMedia(
    media(11),
    source,
    null,
    new Deadline(5_000, Date.now),
    dependencies,
  );
  equal(peak, 3);
  equal(result.map((item) => item.mediaID), media(11).map((item) => item.id));
  equal(
    result.map((item) => item.bytes?.at(-1)),
    Array.from({ length: 11 }, (_, i) => i),
  );
  equal(result.every((item) => item.status === "ok"), true);
});

Deno.test("parallel media reservations enforce the aggregate byte limit without fetching the tail", async () => {
  let calls = 0;
  const dependencies = runtime(async () => {
    calls += 1;
    await Promise.resolve();
    const bytes = new Uint8Array(maximumImageBytes);
    bytes.set(jpeg);
    return new Response(bytes, { headers: { "content-type": "image/jpeg" } });
  });
  const result = await ingestAcquiredMedia(
    media(8),
    source,
    null,
    new Deadline(5_000, Date.now),
    dependencies,
  );
  equal(calls, 6);
  equal(
    result.reduce((sum, item) => sum + (item.byteCount ?? 0), 0),
    maximumTotalMediaBytes,
  );
  equal(result.slice(6).map((item) => item.errorCode), [
    "media_total_too_large",
    "media_total_too_large",
  ]);
});

Deno.test("a failed slide does not discard its successfully downloaded siblings", async () => {
  const dependencies = runtime(async (input) => {
    await Promise.resolve();
    return String(input).endsWith("/1.jpg")
      ? new Response(null, { status: 404 })
      : new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
  });
  const result = await ingestAcquiredMedia(
    media(4),
    source,
    null,
    new Deadline(5_000, Date.now),
    dependencies,
  );
  equal(result.map((item) => item.status), ["ok", "failed", "ok", "ok"]);
});

Deno.test("a large video waits for an earlier image reservation instead of being falsely rejected", async () => {
  const items = media(3);
  items[1] = {
    ...items[1],
    kind: "video",
    url: "https://video.cdninstagram.com/media/1.mp4",
  };
  const videoSize = 55 * 1_024 * 1_024;
  let imageFinished = false;
  const dependencies = runtime(async (input) => {
    if (String(input).endsWith("/1.mp4")) {
      equal(imageFinished, true);
      const bytes = new Uint8Array(videoSize);
      bytes.set([0, 0, 0, 24, 102, 116, 121, 112, 105, 115, 111, 109]);
      return new Response(bytes, {
        headers: {
          "content-type": "video/mp4",
          "content-length": String(videoSize),
        },
      });
    }
    await Promise.resolve();
    imageFinished = true;
    return new Response(jpeg, { headers: { "content-type": "image/jpeg" } });
  });
  const result = await ingestAcquiredMedia(
    items,
    source,
    null,
    new Deadline(5_000, Date.now),
    dependencies,
  );
  equal(result.map((item) => item.status), ["ok", "ok", "ok"]);
  equal(result.map((item) => item.mediaID), items.map((item) => item.id));
  equal(result[1].byteCount, videoSize);
});

Deno.test("cancelled batch settles its active downloads and never starts the next batch", async () => {
  const controller = new AbortController();
  let calls = 0;
  let active = 0;
  const dependencies = runtime((_input, init) =>
    new Promise((_resolve, reject) => {
      calls += 1;
      active += 1;
      init!.signal!.addEventListener("abort", () => {
        active -= 1;
        reject(new DOMException("cancelled", "AbortError"));
      }, { once: true });
      if (calls === 3) queueMicrotask(() => controller.abort());
    })
  );
  // Also terminates the sequential baseline so a regression never hangs CI.
  const timer = setTimeout(() => controller.abort(), 50);
  try {
    await ingestAcquiredMedia(
      media(8),
      source,
      null,
      new Deadline(5_000, Date.now),
      dependencies,
      controller.signal,
    );
    throw new Error("expected cancellation");
  } catch (error) {
    equal((error as { code?: string }).code, "request_cancelled");
    equal(calls, 3);
    equal(active, 0);
  } finally {
    clearTimeout(timer);
  }
});
