import assert from "node:assert/strict";
import { test } from "node:test";
import { frozenInputs } from "./frozen-inputs.ts";
import { productionOperations } from "./production-parity.ts";
import { Deadline } from "../../supabase/functions/social-import-understand/types.ts";

const source = {
  platform: "instagram" as const,
  contentType: "post" as const,
  sourceID: "fixture",
  url: "https://www.instagram.com/p/fixture/",
};
const media = [{
  id: "media:0",
  index: 0,
  kind: "image" as const,
  url: "https://example.com/media",
  thumbnailURL: null,
  altText: null,
}];
const runtime = {
  fetch,
  env: () => undefined,
  now: Date.now,
  sleep: async () => {},
  random: Math.random,
};
const deadline = new Deadline(1000, Date.now);

test("frozen input caches once, hashes bytes and clones data for each model", async () => {
  let calls = 0;
  const frozen = frozenInputs({
    ...productionOperations,
    ingestAcquiredMedia: async () => {
      calls++;
      return [{
        mediaID: "media:0",
        kind: "image",
        status: "ok",
        bytes: new Uint8Array([1, 2]),
        byteCount: 2,
        mimeType: "image/jpeg",
        errorCode: null,
      }];
    },
  });
  const first = await frozen.operations.ingestAcquiredMedia(
    media,
    source,
    "",
    deadline,
    runtime,
  );
  first[0].bytes![0] = 99;
  delete first[0].bytes;
  const manifest = await frozen.seal();
  const second = await frozen.operations.ingestAcquiredMedia(
    media,
    source,
    "",
    deadline,
    runtime,
  );
  assert.deepEqual(second[0].bytes, new Uint8Array([1, 2]));
  assert.equal(calls, 1);
  assert.equal(manifest.mediaByteCount, 2);
  assert.match(manifest.hashes[0].sha256, /^[a-f0-9]{64}$/);
  await assert.rejects(
    () =>
      frozen.operations.ingestAcquiredMedia([], source, "", deadline, runtime),
    /frozen_media_missing/,
  );
  await assert.rejects(
    () =>
      frozen.operations.acquireInstagramProfileAliases(
        ["new"],
        "",
        deadline,
        runtime,
      ),
    /frozen_aliases_missing/,
  );
});

test("incomplete media prevents sealing and model comparisons", async () => {
  const frozen = frozenInputs({
    ...productionOperations,
    ingestAcquiredMedia: async () => [],
  });
  await assert.rejects(
    () =>
      frozen.operations.ingestAcquiredMedia(
        media,
        source,
        "",
        deadline,
        runtime,
      ),
    /frozen_media_incomplete/,
  );
  await assert.rejects(() => frozen.seal(), /frozen_media_incomplete/);
});

test("aliases are shared but mutations and acquisition drift are rejected", async () => {
  let calls = 0;
  let caption = "Original";
  const frozen = frozenInputs({
    ...productionOperations,
    normalizeApifyDataset: () => ({
      title: null,
      caption,
      taggedLocations: [],
      media: [],
    }),
    acquireInstagramProfileAliases: async () => {
      calls++;
      return [{ username: "place", fullName: "Place" }];
    },
  });
  frozen.operations.normalizeApifyDataset([], source);
  const first = await frozen.operations.acquireInstagramProfileAliases(
    ["place"],
    "",
    deadline,
    runtime,
  );
  first[0].fullName = "Mutated";
  await frozen.seal();
  assert.equal(
    (await frozen.operations.acquireInstagramProfileAliases(
      ["place"],
      "",
      deadline,
      runtime,
    ))[0].fullName,
    "Place",
  );
  assert.equal(calls, 1);
  caption = "Changed";
  assert.throws(
    () => frozen.operations.normalizeApifyDataset([], source),
    /frozen_acquisition_drift/,
  );
});
