import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { promisify } from "node:util";

import {
  buildSummary,
  extractDeterministicHints,
  namesEquivalent,
  renderSummaryMarkdown,
  scorePredictions,
} from "./social-import-eval/lib.mjs";
import {
  normalizeVendorDataset,
  parseTikTokHTML,
  runAcquisitionProvider,
  runUnderstandingProvider,
} from "./social-import-eval/providers.mjs";
import { fetchAcquiredMediaBytes } from "./social-import-eval/media.mjs";
import {
  inspectMapKitGeography,
  inspectMapKitQueryLimits,
  inspectMapKitRanking,
} from "./social-import-eval/mapkit.mjs";
import { runCredentialFreeProcess } from "./social-import-eval/subprocess.mjs";
import {
  assessAcquisitionCompleteness,
  validateAcquisitionCompleteness,
} from "./social-import-eval/completeness.mjs";

const execFileAsync = promisify(execFile);

function tinyMP4Bytes() {
  return Buffer.from([
    0x00, 0x00, 0x00, 0x18,
    0x66, 0x74, 0x79, 0x70,
    0x69, 0x73, 0x6f, 0x6d,
    0x00, 0x00, 0x00, 0x00,
    0x69, 0x73, 0x6f, 0x6d,
    0x6d, 0x70, 0x34, 0x32,
  ]);
}

function tinyJPEGBytes() {
  return Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
}

function JSONResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

test("normalizes production spelling variants without accepting unrelated names", () => {
  assert.equal(namesEquivalent("Farson Merc", "Farson Mercantile"), true);
  assert.equal(namesEquivalent("Flaming Gorge", "Flaming Gorge Reservoir"), true);
  assert.equal(namesEquivalent("Amboy", "Frank N Frank's"), false);
});

test("extracts caption, visible slide text, accessibility text, and tagged locations", () => {
  const hints = extractDeterministicHints({
    caption: "Road trip through Wyoming\n📍 Cave Springs Resort, CA",
    taggedLocations: [{ name: "Castle Crags State Park", address: "California" }],
    media: [
      { type: "image", ocrText: "1. Green River Lakes\n2. Half Moon Lake Lodge" },
      { type: "image", altText: "Farson Mercantile, Wyoming" },
      { type: "video", videoText: "Pine Coffee Supply\nPinedale, WY" },
    ],
  });
  const names = hints.map((hint) => hint.name);
  for (const expected of [
    "Cave Springs Resort", "Castle Crags State Park", "Green River Lakes",
    "Half Moon Lake Lodge", "Farson Mercantile", "Pine Coffee Supply",
  ]) {
    assert.ok(names.some((name) => namesEquivalent(name, expected)), expected);
  }
});

test("model output drops attribution and incidental candidates", () => {
  const hints = extractDeterministicHints({
    modelCandidates: [
      { name: "Frank N Frank's", classification: "destination", modality: "video_text" },
      { name: "Amboy", classification: "attribution", modality: "caption" },
      { name: "Howlin's Ray's", classification: "incidental", modality: "speech" },
    ],
  });
  assert.deepEqual(hints.map((hint) => hint.name), ["Frank N Frank's"]);
});

test("scores recall, false positives, and forbidden attribution separately", () => {
  const score = scorePredictions({
    status: "labeled",
    required: [{ name: "Frank N Frank's", aliases: ["franknfranks"] }],
    acceptable: [],
    forbidden: [{ name: "Amboy", aliases: [] }],
  }, ["franknfranks", "Amboy", "Generic Venue"]);
  assert.equal(score.requiredHitCount, 1);
  assert.equal(score.forbiddenHitCount, 1);
  assert.equal(score.recall, 1);
  assert.equal(score.precision, 1 / 3);
  assert.equal(score.exactRequiredSet, false);
});

test("ground-truth scoring rejects fuzzy name fragments", () => {
  const labels = {
    status: "labeled",
    required: [{
      name: "Caption by Hyatt Namba Osaka",
      aliases: ["Caption by Hyatt Namba"],
    }],
    acceptable: [],
    forbidden: [],
  };
  const score = scorePredictions(labels, ["Caption"]);
  assert.equal(score.requiredHitCount, 0);
  assert.deepEqual(score.requiredMisses, ["Caption by Hyatt Namba Osaka"]);
  assert.equal(
    scorePredictions(labels, ["Stay at Caption by Hyatt Namba"]).requiredHitCount,
    1,
  );
  const fragmentThenFull = scorePredictions(labels, [
    "Caption",
    "Caption by Hyatt Namba Osaka",
  ]);
  assert.equal(fragmentThenFull.requiredHitCount, 1);
  assert.equal(fragmentThenFull.predictionCount, 2);
  assert.deepEqual(fragmentThenFull.falsePredictions, ["Caption"]);
});

test("ground-truth scoring matches labels and predictions one-to-one", () => {
  const labels = {
    status: "labeled",
    required: [
      { name: "Alpha Cafe", aliases: [] },
      { name: "Bravo Hotel", aliases: [] },
    ],
    acceptable: [],
    forbidden: [],
  };
  const combined = scorePredictions(labels, ["Alpha Cafe and Bravo Hotel"]);
  assert.equal(combined.requiredHitCount, 1);
  assert.equal(combined.recall, 1 / 2);
  assert.equal(combined.precision, 1);
  assert.equal(combined.exactRequiredSet, false);

  const independentlyGrounded = scorePredictions(labels, ["Alpha Cafe", "Bravo Hotel"]);
  assert.equal(independentlyGrounded.requiredHitCount, 2);
  assert.equal(independentlyGrounded.precision, 1);
  assert.equal(independentlyGrounded.recall, 1);
  assert.equal(independentlyGrounded.exactRequiredSet, true);
});

test("unlabeled cases never contribute a synthetic score", () => {
  assert.deepEqual(
    scorePredictions({ status: "pending_manual_label", required: [], acceptable: [], forbidden: [] }, []),
    { scorable: false, labelStatus: "pending_manual_label" },
  );
});

test("committed corpus is fully labeled with the expected place coverage", async () => {
  const corpus = JSON.parse(await readFile(
    new URL("./social-import-eval/corpus.json", import.meta.url),
    "utf8",
  ));
  assert.equal(corpus.cases.length, 8);
  assert.equal(new Set(corpus.cases.map((item) => item.id)).size, corpus.cases.length);
  assert.ok(corpus.cases.every((item) => item.labels.status === "labeled"));
  assert.ok(corpus.cases.every((item) => {
    const needsMedia = item.modalitiesExpected.some((modality) =>
      ["carousel_image_text", "video_text", "speech"].includes(modality)
    );
    return !needsMedia || Number.isInteger(item.minimumMediaAssets);
  }));
  assert.equal(
    corpus.cases.reduce((sum, item) => sum + item.labels.required.length, 0),
    121,
  );
  const dense = corpus.cases.find((item) => item.id === "instagram-dense-image-guide");
  assert.equal(dense.labels.required.length, 100);
});

test("summary reports macro and micro metrics without hiding dense-post misses", () => {
  const scores = [
    scorePredictions({
      status: "labeled",
      required: [{ name: "One", aliases: [] }],
      acceptable: [],
      forbidden: [],
    }, ["One"]),
    scorePredictions({
      status: "labeled",
      required: [
        { name: "Two", aliases: [] },
        { name: "Three", aliases: [] },
        { name: "Four", aliases: [] },
      ],
      acceptable: [],
      forbidden: [],
    }, ["Two", "Noise"]),
  ];
  const results = scores.map((score, index) => ({
    variant: "example",
    case: { labels: { status: "labeled" } },
    acquisition: { status: "ok" },
    understanding: { status: "ok" },
    scores: {
      extraction: score,
      endToEnd: score,
      endToEndStage: "selected_mapkit_names",
    },
    poiResolution: { response: null },
    timing: { totalMs: 10 + index },
  }));
  const item = buildSummary(results).variants[0];
  assert.equal(item.extractionRecall, 2 / 3);
  assert.equal(item.extractionMicroRecall, 1 / 2);
  assert.equal(item.extractionMicroPrecision, 2 / 3);
  assert.equal(item.selectedNameRequiredCount, 4);
  assert.equal(item.selectedNameRequiredHitCount, 2);
  assert.match(renderSummaryMarkdown(buildSummary(results)), /Hint micro P\/R/);
});

test("summary never presents unresolved hints as selected-name quality", () => {
  const score = scorePredictions({
    status: "labeled",
    required: [{ name: "One", aliases: [] }],
    acceptable: [],
    forbidden: [],
  }, ["One"]);
  const item = buildSummary([{
    variant: "no-resolver",
    case: { labels: { status: "labeled" }, modalitiesExpected: [] },
    acquisition: { status: "ok", modalityCoverage: { complete: true } },
    understanding: { status: "ok" },
    scores: {
      extraction: score,
      endToEnd: score,
      endToEndStage: "unresolved_hints",
    },
    poiResolution: { mode: "none", status: "not_run", response: null },
    timing: { totalMs: 1 },
  }]).variants[0];
  assert.equal(item.extractionMicroRecall, 1);
  assert.equal(item.selectedNameMicroRecall, null);
  assert.equal(item.selectedNameLabeledCaseCount, 0);
});

test("MapKit geography mirror preserves production LA, Georgia, and DC semantics", {
  skip: process.platform !== "darwin",
}, async () => {
  const outputDirectory = await mkdtemp(join(tmpdir(), "rec120-mapkit-parity-"));
  try {
    const actual = await inspectMapKitGeography([
      { id: "los-angeles-abbreviation", area: "LA" },
      { id: "los-angeles-state", area: "Los Angeles, CA" },
      { id: "louisiana", area: "Baton Rouge, LA" },
      { id: "georgia-country-ambiguous", area: "Georgia" },
      { id: "georgia-state-explicit", area: "Georgia, USA" },
      { id: "dc-code", area: "Washington, DC" },
      { id: "dc-name", area: "District of Columbia" },
    ], outputDirectory);
    assert.deepEqual(actual, [
      { id: "los-angeles-abbreviation", hasSearchRegion: false, localityText: "LA" },
      { id: "los-angeles-state", stateCode: "CA", hasSearchRegion: true, localityText: "Los Angeles" },
      { id: "louisiana", stateCode: "LA", hasSearchRegion: true, localityText: "Baton Rouge" },
      { id: "georgia-country-ambiguous", hasSearchRegion: false, localityText: "Georgia" },
      { id: "georgia-state-explicit", stateCode: "GA", hasSearchRegion: true },
      { id: "dc-code", stateCode: "DC", hasSearchRegion: true, localityText: "Washington" },
      { id: "dc-name", stateCode: "DC", hasSearchRegion: true },
    ]);
  } finally {
    await rm(outputDirectory, { recursive: true, force: true });
  }
});

test("MapKit ranking mirror applies production category ordering before truncation", {
  skip: process.platform !== "darwin",
}, async () => {
  const actual = await inspectMapKitRanking([{
    id: "production-order",
    items: [
      { id: "address", hasPointOfInterestCategory: false, isPark: false, hasPrimaryCategory: false },
      { id: "poi", hasPointOfInterestCategory: true, isPark: false, hasPrimaryCategory: true },
      { id: "named-address", hasPointOfInterestCategory: false, isPark: false, hasPrimaryCategory: true },
      { id: "park", hasPointOfInterestCategory: true, isPark: true, hasPrimaryCategory: true },
    ],
  }], null);
  assert.deepEqual(actual, [{
    id: "production-order",
    orderedItemIDs: ["park", "poi", "named-address", "address"],
  }]);
});

test("MapKit mirror applies each query limit before global deduplication", {
  skip: process.platform !== "darwin",
}, async () => {
  const actual = await inspectMapKitQueryLimits([{
    id: "cross-query-duplicate",
    perQueryLimit: 2,
    queryItemIDs: [
      ["shared", "first-only", "first-outside-limit"],
      ["shared", "second-only", "second-outside-limit"],
    ],
  }], null);
  assert.deepEqual(actual, [{
    id: "cross-query-duplicate",
    accumulatedItemIDs: ["shared", "first-only", "second-only"],
  }]);
});

test("MapKit re-resolution fails rather than relabeling a resolver-none run", async () => {
  const runDirectory = await mkdtemp(join(tmpdir(), "rec120-rescore-none-"));
  const manifest = { schemaVersion: 1, resolver: "none" };
  try {
    await Promise.all([
      writeFile(join(runDirectory, "manifest.json"), JSON.stringify(manifest)),
      writeFile(join(runDirectory, "results.json"), JSON.stringify([{
        poiResolution: { mode: "none", status: "not_run", response: null },
      }])),
    ]);
    const rescorer = new URL("./social-import-eval/rescore.mjs", import.meta.url);
    await assert.rejects(
      execFileAsync(process.execPath, [rescorer.pathname, runDirectory, "--reresolve-mapkit"]),
      (error) => {
        assert.match(error.stderr, /requires a run originally created with --resolve mapkit/);
        return true;
      },
    );
    assert.deepEqual(JSON.parse(await readFile(join(runDirectory, "manifest.json"), "utf8")), manifest);
  } finally {
    await rm(runDirectory, { recursive: true, force: true });
  }
});

test("local helper subprocesses never inherit provider credentials", {
  concurrency: false,
}, async () => {
  const original = {
    apify: process.env.APIFY_TOKEN,
    gemini: process.env.GEMINI_API_KEY,
    brightData: process.env.BRIGHTDATA_API_TOKEN,
    google: process.env.GOOGLE_CLOUD_ACCESS_TOKEN,
  };
  process.env.APIFY_TOKEN = "unit-test-apify-secret";
  process.env.GEMINI_API_KEY = "unit-test-gemini-secret";
  process.env.BRIGHTDATA_API_TOKEN = "unit-test-brightdata-secret";
  process.env.GOOGLE_CLOUD_ACCESS_TOKEN = "unit-test-google-secret";
  try {
    const { output } = await runCredentialFreeProcess(process.execPath, [
      "-e",
      "process.stdout.write(JSON.stringify({apify:process.env.APIFY_TOKEN??null,gemini:process.env.GEMINI_API_KEY??null,brightData:process.env.BRIGHTDATA_API_TOKEN??null,google:process.env.GOOGLE_CLOUD_ACCESS_TOKEN??null}))",
    ]);
    assert.deepEqual(JSON.parse(output), {
      apify: null,
      gemini: null,
      brightData: null,
      google: null,
    });
  } finally {
    if (original.apify == null) delete process.env.APIFY_TOKEN;
    else process.env.APIFY_TOKEN = original.apify;
    if (original.gemini == null) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = original.gemini;
    if (original.brightData == null) delete process.env.BRIGHTDATA_API_TOKEN;
    else process.env.BRIGHTDATA_API_TOKEN = original.brightData;
    if (original.google == null) delete process.env.GOOGLE_CLOUD_ACCESS_TOKEN;
    else process.env.GOOGLE_CLOUD_ACCESS_TOKEN = original.google;
  }
});

test("fixture replay blocks network-capable understanding unless explicitly allowed", async () => {
  const runner = new URL("./social-import-eval/run.mjs", import.meta.url);
  await assert.rejects(
    execFileAsync(process.execPath, [
      runner.pathname,
      "--fixture-dir", "/private/tmp/nonexistent-rec120-fixtures",
      "--understanders", "gemini",
    ]),
    (error) => {
      assert.match(error.stderr, /Fixture replay is offline by default/);
      return true;
    },
  );
});

test("credentialed providers fail closed without leaking configuration", async () => {
  const original = {
    brightData: process.env.BRIGHTDATA_API_TOKEN,
    apify: process.env.APIFY_TOKEN,
    gemini: process.env.GEMINI_API_KEY,
  };
  delete process.env.BRIGHTDATA_API_TOKEN;
  delete process.env.APIFY_TOKEN;
  delete process.env.GEMINI_API_KEY;
  try {
    const testCase = {
      id: "test",
      platform: "instagram",
      contentType: "post",
      url: "https://www.instagram.com/p/DbPM9o1mzbL/",
    };
    const brightData = await runAcquisitionProvider("brightdata", testCase);
    const apify = await runAcquisitionProvider("apify", testCase);
    const gemini = await runUnderstandingProvider("gemini", testCase, {
      status: "ok",
      evidence: { media: [] },
    });
    assert.equal(brightData.status, "not_configured");
    assert.equal(apify.status, "not_configured");
    assert.equal(gemini.status, "not_configured");
    assert.equal(JSON.stringify([brightData, apify, gemini]).includes("Bearer"), false);
  } finally {
    if (original.brightData == null) delete process.env.BRIGHTDATA_API_TOKEN;
    else process.env.BRIGHTDATA_API_TOKEN = original.brightData;
    if (original.apify == null) delete process.env.APIFY_TOKEN;
    else process.env.APIFY_TOKEN = original.apify;
    if (original.gemini == null) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = original.gemini;
  }
});

test("acquisition completeness consumes expected modalities and asset counts", () => {
  const testCase = {
    modalitiesExpected: ["caption", "carousel_image_text"],
    minimumMediaAssets: 3,
  };
  const degraded = assessAcquisitionCompleteness(testCase, {
    status: "ok",
    error: null,
    evidence: {
      caption: "Three places",
      media: [{ type: "image", url: "https://cdn.example/cover.jpg" }],
    },
  });
  assert.equal(degraded.status, "ok");
  assert.equal(degraded.modalityCoverage.complete, false);
  assert.equal(degraded.modalityCoverage.missingMediaAssetCount, 2);

  const complete = assessAcquisitionCompleteness(testCase, {
    status: "ok",
    error: null,
    evidence: {
      caption: "Three places",
      media: [1, 2, 3].map((index) => ({
        type: "image",
        url: "https://cdn.example/" + index + ".jpg",
      })),
    },
  });
  assert.equal(complete.status, "ok");
  assert.equal(complete.modalityCoverage.declaredComplete, true);
  assert.equal(complete.modalityCoverage.complete, null);
});

test("a caption-only reel cannot pass expected video acquisition", () => {
  const result = assessAcquisitionCompleteness({
    modalitiesExpected: ["caption", "video_text", "speech"],
    minimumMediaAssets: 1,
  }, {
    status: "ok",
    evidence: { caption: "A reel", media: [] },
  });
  assert.equal(result.status, "ok");
  assert.equal(result.modalityCoverage.complete, false);
  assert.deepEqual(result.modalityCoverage.missing, ["video_text", "speech"]);
});

test("mixed-media completeness requires both image and video assets", () => {
  const complete = assessAcquisitionCompleteness({
    modalitiesExpected: ["carousel_image_text", "video_text"],
    minimumImageAssets: 2,
    minimumVideoAssets: 1,
  }, {
    status: "ok",
    evidence: {
      media: [
        { type: "image", url: "https://scontent.cdninstagram.com/one.jpg" },
        { type: "image", url: "https://scontent.cdninstagram.com/two.jpg" },
        { type: "video", url: "https://scontent.cdninstagram.com/three.mp4" },
      ],
    },
  });
  assert.equal(complete.modalityCoverage.declaredComplete, true);
  assert.deepEqual(complete.modalityCoverage.requiredMediaByKind, { image: 2, video: 1 });
});

test("strict completeness rejects an expired media URL without hiding partial evidence", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response("expired", { status: 403 });
  try {
    const result = await validateAcquisitionCompleteness({
      url: "https://www.tiktok.com/@creator/video/7448513035146251566",
      modalitiesExpected: ["caption", "video_text"],
      minimumMediaAssets: 1,
    }, {
      status: "ok",
      latencyMs: 12,
      evidence: {
        caption: "Still useful caption",
        media: [{ type: "video", url: "https://v16.tiktokcdn.com/video.mp4" }],
      },
    });
    assert.equal(result.status, "ok");
    assert.equal(result.evidence.caption, "Still useful caption");
    assert.equal(result.modalityCoverage.complete, false);
    assert.equal(result.modalityCoverage.assetChecks[0].error.code, "media_http_error");
    assert.ok(result.latencyMs >= 12);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("normalizes official Clockworks TikTok video and slideshow payloads", () => {
  const videoCase = {
    platform: "tiktok",
    contentType: "video",
    url: "https://www.tiktok.com/@creator/video/7448513035146251566",
  };
  const transcriptionLink = "https://api.apify.com/v2/key-value-stores/store/records/transcript.txt";
  const videoFixture = [{
    webVideoUrl: videoCase.url,
    text: "Hidden coffee stop",
    videoMeta: {
      downloadAddr: "https://v16.tiktokcdn.com/video.mp4",
      coverUrl: "https://p16.tiktokcdn.com/cover.jpeg",
      aiVideoDescription: "A storefront sign reads Pine Coffee Supply.",
      transcriptionLink,
    },
    locationMeta: {
      locationName: "Pine Coffee Supply",
      address: "Pinedale, Wyoming",
      locationId: "poi-123",
    },
    mediaUrls: ["https://api.apify.com/v2/key-value-stores/store/records/video.mp4"],
  }];
  const before = JSON.stringify(videoFixture);
  const video = normalizeVendorDataset(videoFixture, videoCase);
  assert.equal(video.status, "ok");
  assert.equal(video.evidence.caption, "Hidden coffee stop");
  assert.equal(video.evidence.sceneDescription, "A storefront sign reads Pine Coffee Supply.");
  assert.deepEqual(video.evidence.taggedLocations, [{
    name: "Pine Coffee Supply",
    address: "Pinedale, Wyoming",
    providerID: "poi-123",
  }]);
  assert.deepEqual(video.evidence.media, [{
    index: 0,
    type: "video",
    url: "https://api.apify.com/v2/key-value-stores/store/records/video.mp4",
    persistentURL: "https://api.apify.com/v2/key-value-stores/store/records/video.mp4",
    thumbnailURL: "https://p16.tiktokcdn.com/cover.jpeg",
    altText: null,
    ocrText: null,
    videoText: null,
  }]);
  assert.equal(video.evidence.transcript, null);
  assert.equal(JSON.stringify(videoFixture), before);
  assert.equal(videoFixture[0].videoMeta.transcriptionLink, transcriptionLink);

  const slideshowCase = {
    platform: "tiktok",
    contentType: "video",
    url: "https://www.tiktok.com/@creator/video/7399320195497577735",
  };
  const slideshow = normalizeVendorDataset([{
    submittedVideoUrl: slideshowCase.url,
    isSlideshow: true,
    text: "Two places to try",
    slideshowImageLinks: [
      {
        downloadLink: "https://api.apify.com/v2/key-value-stores/store/records/slide-1.jpeg",
        tiktokLink: "https://p16.tiktokcdn.com/slide-1.jpeg",
      },
      { tiktokLink: "https://p16.tiktokcdn.com/slide-2.jpeg" },
    ],
    mediaUrls: ["https://api.apify.com/v2/key-value-stores/store/records/slide-3.jpeg"],
  }], slideshowCase);
  assert.equal(slideshow.status, "ok");
  assert.equal(slideshow.evidence.media.length, 3);
  assert.deepEqual(
    slideshow.evidence.media.map((item) => item.type),
    ["image", "image", "image"],
  );
  assert.ok(slideshow.evidence.media.some((item) => (
    item.url === "https://p16.tiktokcdn.com/slide-2.jpeg"
  )));
});

test("vendor normalization does not ingest unmeasured transcript fields", () => {
  const testCase = {
    platform: "instagram",
    contentType: "reel",
    url: "https://www.instagram.com/reel/Da9EdCzBFuw/",
  };
  const normalized = normalizeVendorDataset([{
    inputUrl: testCase.url,
    videoUrl: "https://cdninstagram.com/example.mp4",
    transcript: { text: "Visit Unmeasured Cafe" },
    speechTranscript: "Visit Another Unmeasured Cafe",
  }], testCase);
  assert.equal(normalized.status, "ok");
  assert.equal(normalized.evidence.transcript, null);
});

test("current-improved preserves TikTok slideshow stickers and scoped headers", () => {
  const testCase = {
    platform: "tiktok",
    url: "https://www.tiktok.com/@creator/video/7448513035146251566",
  };
  const fallback = {
    evidence: { title: null, caption: null, authorName: null, media: [], taggedLocations: [] },
    raw: null,
  };
  const post = {
    id: "7448513035146251566",
    desc: "Caption",
    author: { uniqueId: "creator" },
    imagePost: {
      images: [
        { imageURL: { urlList: ["https://p16.tiktokcdn.com/slide-1.jpeg"] } },
        { imageURL: { urlList: ["https://p16.tiktokcdn.com/slide-2.jpeg"] } },
      ],
    },
    stickersOnItem: [{ stickerText: ["Caroline's Seaside Cafe"] }],
  };
  const html = '<script id="__UNIVERSAL_DATA_FOR_REHYDRATION__">'
    + JSON.stringify({ post })
    + "</script>";
  const result = parseTikTokHTML(html, testCase, fallback, {
    cookie: "private-test-cookie",
  });
  assert.equal(result.evidence.media.length, 2);
  assert.equal(result.evidence.media[0].videoText, "Caroline's Seaside Cafe");
  assert.equal(result.evidence.media[0].privateRequestHeaders.cookie, "private-test-cookie");
  assert.equal(JSON.stringify(result).includes("private-test-cookie"), false);
});

test("normalizes official Apify Instagram reel payload fields", () => {
  const testCase = {
    platform: "instagram",
    contentType: "reel",
    url: "https://www.instagram.com/reel/Da9EdCzBFuw/",
  };
  const normalized = normalizeVendorDataset([{
    inputUrl: testCase.url,
    url: testCase.url,
    shortCode: "Da9EdCzBFuw",
    caption: "A hidden hotel in Osaka",
    images: ["https://scontent.cdninstagram.com/reel-preview.jpeg"],
    displayUrl: "https://scontent.cdninstagram.com/reel-cover.jpeg",
    videoUrl: "https://scontent.cdninstagram.com/reel.mp4",
    downloadedVideo: "https://api.apify.com/v2/key-value-stores/store/records/reel.mp4",
    transcript: "Welcome to Caption by Hyatt Namba Osaka.",
    locationName: "Caption by Hyatt Namba Osaka",
    locationId: "ig-location-123",
  }], testCase);
  assert.equal(normalized.status, "ok");
  assert.equal(normalized.evidence.caption, "A hidden hotel in Osaka");
  assert.equal(normalized.evidence.transcript, null);
  assert.deepEqual(normalized.evidence.taggedLocations, [{
    name: "Caption by Hyatt Namba Osaka",
    address: null,
    providerID: "ig-location-123",
  }]);
  const video = normalized.evidence.media.find((item) => item.type === "video");
  assert.equal(video.url, "https://api.apify.com/v2/key-value-stores/store/records/reel.mp4");
  assert.equal(video.persistentURL, "https://api.apify.com/v2/key-value-stores/store/records/reel.mp4");
  assert.equal(video.thumbnailURL, "https://scontent.cdninstagram.com/reel-cover.jpeg");
});

test("normalizes Bright Data reel thumbnail and author fields", () => {
  const testCase = {
    platform: "instagram",
    contentType: "reel",
    url: "https://www.instagram.com/reel/Dav5_60ywYJ/",
  };
  const userPosted = normalizeVendorDataset([{
    url: testCase.url,
    user_posted: "creator-one",
    thumbnail: "https://scontent.cdninstagram.com/brightdata-cover.jpeg",
    video_url: "https://scontent.cdninstagram.com/brightdata-reel.mp4",
  }], testCase);
  assert.equal(userPosted.status, "ok");
  assert.equal(userPosted.evidence.authorName, "creator-one");
  assert.equal(
    userPosted.evidence.media.find((item) => item.type === "video").thumbnailURL,
    "https://scontent.cdninstagram.com/brightdata-cover.jpeg",
  );

  const profileUsername = normalizeVendorDataset([{
    url: testCase.url,
    profile_username: "creator-two",
    video_url: "https://scontent.cdninstagram.com/brightdata-reel-2.mp4",
  }], testCase);
  assert.equal(profileUsername.status, "ok");
  assert.equal(profileUsername.evidence.authorName, "creator-two");
});

test("vendor dataset validation fails closed on empty, error, mismatch, and missing media", () => {
  const testCase = {
    platform: "instagram",
    contentType: "reel",
    url: "https://www.instagram.com/reel/Da9EdCzBFuw/",
  };
  assert.equal(normalizeVendorDataset([], testCase).error.code, "vendor_empty_dataset");
  assert.equal(normalizeVendorDataset([{
    inputUrl: testCase.url,
    errorCode: "not-found",
    errorDescription: "Post was unavailable",
  }], testCase).error.code, "vendor_item_error");
  assert.equal(normalizeVendorDataset([{
    inputUrl: "https://www.instagram.com/reel/Different01/",
    videoUrl: "https://scontent.cdninstagram.com/wrong.mp4",
  }], testCase).error.code, "vendor_source_mismatch");
  assert.equal(normalizeVendorDataset([{
    inputUrl: testCase.url,
    caption: "No assets returned",
  }], testCase).error.code, "vendor_missing_media_assets");
  assert.equal(normalizeVendorDataset([{
    inputUrl: testCase.url,
    images: ["https://scontent.cdninstagram.com/cover-only.jpeg"],
  }], testCase).error.code, "vendor_missing_video_asset");
});

test("Bright Data and Apify acquisitions propagate dataset validation failures", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalBrightData = process.env.BRIGHTDATA_API_TOKEN;
  const originalApify = process.env.APIFY_TOKEN;
  const testCase = {
    platform: "instagram",
    contentType: "reel",
    url: "https://www.instagram.com/reel/Da9EdCzBFuw/",
  };
  process.env.BRIGHTDATA_API_TOKEN = "unit-test-brightdata-token";
  process.env.APIFY_TOKEN = "unit-test-apify-token";
  try {
    globalThis.fetch = async (input) => {
      assert.match(String(input), /api\.brightdata\.com/);
      return JSONResponse([]);
    };
    const brightData = await runAcquisitionProvider("brightdata", testCase);
    assert.equal(brightData.status, "failed");
    assert.equal(brightData.error.code, "vendor_empty_dataset");
    assert.deepEqual(brightData.raw, []);

    globalThis.fetch = async (input) => {
      const url = String(input);
      if (url.includes("/runs?")) {
        return JSONResponse({
          data: { id: "run-123", status: "SUCCEEDED", defaultDatasetId: "dataset-123" },
        });
      }
      if (url.includes("/datasets/dataset-123/items")) {
        return JSONResponse([{
          inputUrl: testCase.url,
          requestErrorMessages: ["Post unavailable"],
        }]);
      }
      throw new Error("Unexpected Apify request");
    };
    const apify = await runAcquisitionProvider("apify", testCase);
    assert.equal(apify.status, "failed");
    assert.equal(apify.error.code, "vendor_item_error");
    assert.equal(apify.raw.run.id, "run-123");
    assert.equal(apify.raw.items[0].requestErrorMessages[0], "Post unavailable");
  } finally {
    globalThis.fetch = originalFetch;
    if (originalBrightData == null) delete process.env.BRIGHTDATA_API_TOKEN;
    else process.env.BRIGHTDATA_API_TOKEN = originalBrightData;
    if (originalApify == null) delete process.env.APIFY_TOKEN;
    else process.env.APIFY_TOKEN = originalApify;
  }
});

test("Apify media authorization is scoped to private KVS downloads and never serialized", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalApify = process.env.APIFY_TOKEN;
  const token = "unit-test-apify-token";
  const testCase = {
    platform: "tiktok",
    contentType: "video",
    url: "https://www.tiktok.com/@creator/video/7448513035146251566",
  };
  let mediaHeaders;
  process.env.APIFY_TOKEN = token;
  globalThis.fetch = async (input, options = {}) => {
    const url = String(input);
    if (url.includes("/runs?")) {
      const body = JSON.parse(options.body);
      assert.equal(body.aiVideoDescription, false);
      return JSONResponse({
        data: { id: "run-123", status: "SUCCEEDED", defaultDatasetId: "dataset-123" },
      });
    }
    if (url.includes("/datasets/dataset-123/items")) {
      return JSONResponse([{
        webVideoUrl: testCase.url,
        videoMeta: { downloadAddr: "https://v16.tiktokcdn.com/direct-video.mp4" },
        mediaUrls: ["https://api.apify.com/v2/key-value-stores/store/records/video.mp4"],
      }]);
    }
    if (url.includes("/key-value-stores/store/records/video.mp4")) {
      mediaHeaders = options.headers;
      return new Response(tinyMP4Bytes(), { headers: { "content-type": "video/mp4" } });
    }
    throw new Error("Unexpected Apify request");
  };

  try {
    const acquisition = await runAcquisitionProvider("apify", testCase);
    assert.equal(acquisition.status, "ok");
    assert.match(acquisition.evidence.media[0].privateRequestHeaders.authorization, /^Bearer /);
    assert.equal(JSON.stringify(acquisition).includes(token), false);

    const ingestion = await fetchAcquiredMediaBytes(acquisition.evidence.media[0], {
      expectedKind: "video",
      maximumBytes: 1_000,
      socialPageURL: testCase.url,
    });
    assert.equal(ingestion.error, undefined);
    assert.equal(mediaHeaders.authorization, "Bearer " + token);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalApify == null) delete process.env.APIFY_TOKEN;
    else process.env.APIFY_TOKEN = originalApify;
  }
});

test("Apify authorization is stripped from cross-host media redirects", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const media = {
    type: "video",
    url: "https://api.apify.com/v2/key-value-stores/store/records/video.mp4",
  };
  Object.defineProperty(media, "privateRequestHeaders", {
    enumerable: false,
    value: { authorization: "Bearer unit-test-apify-token" },
  });
  const requestHeaders = [];
  globalThis.fetch = async (input, options = {}) => {
    requestHeaders.push({ url: String(input), headers: options.headers });
    if (String(input).includes("api.apify.com")) {
      return new Response(null, {
        status: 302,
        headers: { location: "https://v16.tiktokcdn.com/redirected-video.mp4" },
      });
    }
    return new Response(tinyMP4Bytes(), { headers: { "content-type": "video/mp4" } });
  };
  try {
    const result = await fetchAcquiredMediaBytes(media, {
      expectedKind: "video",
      maximumBytes: 1_000,
      socialPageURL: "https://www.tiktok.com/@creator/video/7448513035146251566",
    });
    assert.equal(result.error, undefined);
    assert.equal(requestHeaders[0].headers.authorization, "Bearer unit-test-apify-token");
    assert.equal(requestHeaders[1].headers.authorization, undefined);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("Apify authorization is stripped from same-host redirects outside KVS records", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const media = {
    type: "video",
    url: "https://api.apify.com/v2/key-value-stores/store/records/video.mp4",
  };
  Object.defineProperty(media, "privateRequestHeaders", {
    enumerable: false,
    value: { authorization: "Bearer unit-test-apify-token" },
  });
  const requestHeaders = [];
  globalThis.fetch = async (input, options = {}) => {
    requestHeaders.push({ url: String(input), headers: options.headers });
    if (String(input).includes("/key-value-stores/")) {
      return new Response(null, {
        status: 302,
        headers: { location: "https://api.apify.com/v2/users/me" },
      });
    }
    return new Response(tinyMP4Bytes(), { headers: { "content-type": "video/mp4" } });
  };
  try {
    const result = await fetchAcquiredMediaBytes(media, {
      expectedKind: "video",
      maximumBytes: 1_000,
      socialPageURL: "https://www.tiktok.com/@creator/video/7448513035146251566",
    });
    assert.equal(result.error, undefined);
    assert.equal(requestHeaders[0].headers.authorization, "Bearer unit-test-apify-token");
    assert.equal(requestHeaders[1].headers.authorization, undefined);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("Gemini downloads acquired TikTok bytes with scoped private headers and sends inline data", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  const privateCookie = "ttwid=unit-test-cookie";
  const bytes = tinyMP4Bytes();
  const media = {
    index: 0,
    type: "video",
    url: "https://v16.tiktokcdn.com/object/video.mp4",
  };
  Object.defineProperty(media, "privateRequestHeaders", {
    enumerable: false,
    value: {
      cookie: privateCookie,
      referer: "https://www.tiktok.com/@creator/video/1234567890123456789",
      "user-agent": "unit-test-agent",
    },
  });
  let downloadHeaders;
  let modelRequest;
  process.env.GEMINI_API_KEY = "unit-test-gemini-key";
  globalThis.fetch = async (input, options = {}) => {
    const url = String(input);
    if (url.includes("tiktokcdn.com")) {
      downloadHeaders = options.headers;
      return new Response(bytes, { headers: { "content-type": "video/mp4" } });
    }
    if (url.includes("generativelanguage.googleapis.com")) {
      modelRequest = JSON.parse(options.body);
      return JSONResponse({
        candidates: [{ content: { parts: [{ text: JSON.stringify({ candidates: [] }) }] } }],
      });
    }
    throw new Error("Unexpected fetch destination");
  };

  try {
    const result = await runUnderstandingProvider("gemini", {
      id: "gemini-media",
      platform: "tiktok",
      contentType: "reel",
      url: "https://www.tiktok.com/@creator/video/1234567890123456789",
    }, {
      status: "ok",
      evidence: { caption: "A place", media: [media] },
    });
    const parts = modelRequest.contents[0].parts;
    const inlinePart = parts.find((part) => part.inlineData);
    assert.equal(result.status, "ok");
    assert.equal(downloadHeaders.cookie, privateCookie);
    assert.equal(parts.some((part) => part.fileData), false);
    assert.equal(inlinePart.inlineData.mimeType, "video/mp4");
    assert.equal(inlinePart.inlineData.data, bytes.toString("base64"));
    assert.equal(typeof parts.at(-1).text, "string");
    assert.equal(
      modelRequest.generationConfig.responseFormat.text.mimeType,
      "APPLICATION_JSON",
    );
    assert.equal(modelRequest.generationConfig.temperature, 0);
    assert.equal(
      "maxItems" in modelRequest.generationConfig.responseFormat.text.schema.properties.candidates,
      false,
    );
    assert.equal(result.mediaIngestion[0].byteCount, bytes.length);
    assert.equal(JSON.stringify(result).includes(privateCookie), false);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
  }
});

test("Gemini retries transient provider failures without redownloading media", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  const originalBase = process.env.GEMINI_RETRY_BASE_MS;
  let mediaFetches = 0;
  let modelFetches = 0;
  process.env.GEMINI_API_KEY = "unit-test-gemini-key";
  process.env.GEMINI_RETRY_BASE_MS = "1";
  globalThis.fetch = async (input) => {
    const url = String(input);
    if (url.includes("cdninstagram.com")) {
      mediaFetches += 1;
      return new Response(tinyMP4Bytes(), { headers: { "content-type": "video/mp4" } });
    }
    modelFetches += 1;
    if (modelFetches === 1) {
      return JSONResponse({ error: { code: 503, status: "UNAVAILABLE" } }, 503);
    }
    return JSONResponse({
      candidates: [{ content: { parts: [{ text: JSON.stringify({ candidates: [] }) }] } }],
    });
  };
  try {
    const result = await runUnderstandingProvider("gemini", {
      platform: "instagram",
      contentType: "reel",
      url: "https://www.instagram.com/reel/ABC123xyz/",
    }, {
      status: "ok",
      evidence: {
        media: [{ type: "video", url: "https://scontent.cdninstagram.com/video.mp4" }],
      },
    });
    assert.equal(result.status, "ok");
    assert.equal(mediaFetches, 1);
    assert.equal(modelFetches, 2);
    assert.deepEqual(result.requestAttempts.map((item) => item.statusCode), [503, 200]);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
    if (originalBase == null) delete process.env.GEMINI_RETRY_BASE_MS;
    else process.env.GEMINI_RETRY_BASE_MS = originalBase;
  }
});

test("Gemini does not retry invalid requests", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  let modelFetches = 0;
  process.env.GEMINI_API_KEY = "unit-test-gemini-key";
  globalThis.fetch = async () => {
    modelFetches += 1;
    return JSONResponse({ error: { code: 400, status: "INVALID_ARGUMENT" } }, 400);
  };
  try {
    const result = await runUnderstandingProvider("gemini", {
      platform: "instagram",
      contentType: "post",
      url: "https://www.instagram.com/p/ABC123xyz/",
    }, { status: "ok", evidence: { media: [] } });
    assert.equal(result.status, "failed");
    assert.equal(result.error.message, "HTTP 400");
    assert.equal(modelFetches, 1);
    assert.deepEqual(result.requestAttempts.map((item) => item.statusCode), [400]);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
  }
});

test("Gemini reports exhausted transport retries without leaking the request", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  const originalAttempts = process.env.GEMINI_MAX_ATTEMPTS;
  const originalBase = process.env.GEMINI_RETRY_BASE_MS;
  const originalMaximum = process.env.GEMINI_RETRY_MAX_MS;
  let modelFetches = 0;
  process.env.GEMINI_API_KEY = "unit-test-gemini-key";
  process.env.GEMINI_MAX_ATTEMPTS = "2";
  process.env.GEMINI_RETRY_BASE_MS = "10000";
  process.env.GEMINI_RETRY_MAX_MS = "1";
  globalThis.fetch = async () => {
    modelFetches += 1;
    throw new TypeError("fetch failed", { cause: { code: "UND_ERR_SOCKET" } });
  };
  try {
    const result = await runUnderstandingProvider("gemini", {
      platform: "instagram",
      contentType: "post",
      url: "https://www.instagram.com/p/ABC123xyz/",
    }, { status: "ok", evidence: { media: [] } });
    assert.equal(result.status, "failed");
    assert.equal(result.error.code, "gemini_transport_error");
    assert.equal(result.error.message, "UND_ERR_SOCKET");
    assert.equal(modelFetches, 2);
    assert.equal(result.requestAttempts.length, 2);
    assert.ok(result.requestAttempts[0].retryDelayMs <= 1);
    assert.equal(JSON.stringify(result).includes("unit-test-gemini-key"), false);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
    if (originalAttempts == null) delete process.env.GEMINI_MAX_ATTEMPTS;
    else process.env.GEMINI_MAX_ATTEMPTS = originalAttempts;
    if (originalBase == null) delete process.env.GEMINI_RETRY_BASE_MS;
    else process.env.GEMINI_RETRY_BASE_MS = originalBase;
    if (originalMaximum == null) delete process.env.GEMINI_RETRY_MAX_MS;
    else process.env.GEMINI_RETRY_MAX_MS = originalMaximum;
  }
});

test("Gemini does not spend a model call after acquisition failure", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  let fetchCount = 0;
  process.env.GEMINI_API_KEY = "unit-test-gemini-key";
  globalThis.fetch = async () => {
    fetchCount += 1;
    throw new Error("Gemini must not run after acquisition failed");
  };
  try {
    const result = await runUnderstandingProvider("gemini", {
      id: "blocked-gemini",
      platform: "instagram",
      contentType: "reel",
      url: "https://www.instagram.com/reel/ABC123xyz/",
    }, {
      status: "failed",
      error: { code: "fixture_acquisition_failed", message: "No post" },
      evidence: { media: [] },
    });
    assert.equal(result.status, "blocked_by_acquisition");
    assert.equal(result.error.code, "fixture_acquisition_failed");
    assert.equal(fetchCount, 0);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
  }
});

test("Gemini attempts every carousel asset beyond sixteen", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalKey = process.env.GEMINI_API_KEY;
  const media = Array.from({ length: 17 }, (_, index) => ({
    index,
    type: "image",
    url: "https://scontent.cdninstagram.com/slide-" + index + ".jpg",
  }));
  let modelRequest;
  process.env.GEMINI_API_KEY = "unit-test-gemini-key";
  globalThis.fetch = async (input, options = {}) => {
    if (String(input).includes("cdninstagram.com")) {
      return new Response(tinyJPEGBytes(), { headers: { "content-type": "image/jpeg" } });
    }
    modelRequest = JSON.parse(options.body);
    return JSONResponse({
      candidates: [{ content: { parts: [{ text: JSON.stringify({ candidates: [] }) }] } }],
    });
  };
  try {
    const result = await runUnderstandingProvider("gemini", {
      platform: "instagram",
      contentType: "carousel",
      url: "https://www.instagram.com/p/ABC123xyz/",
    }, { status: "ok", evidence: { media } });
    assert.equal(result.status, "ok");
    assert.equal(result.mediaIngestion.length, 17);
    assert.equal(modelRequest.contents[0].parts.filter((part) => part.inlineData).length, 17);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalKey == null) delete process.env.GEMINI_API_KEY;
    else process.env.GEMINI_API_KEY = originalKey;
  }
});

test("Google Video downloads acquired bytes before submitting inline content", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalToken = process.env.GOOGLE_CLOUD_ACCESS_TOKEN;
  const privateCookie = "tt_chain_token=unit-test";
  const bytes = tinyMP4Bytes();
  const media = {
    index: 0,
    type: "video",
    url: "https://v19.tiktokcdn-us.com/object/video.mp4",
  };
  Object.defineProperty(media, "privateRequestHeaders", {
    enumerable: false,
    value: {
      cookie: privateCookie,
      referer: "https://www.tiktok.com/@creator/video/1234567890123456789",
    },
  });
  let downloadHeaders;
  let annotateRequest;
  process.env.GOOGLE_CLOUD_ACCESS_TOKEN = "unit-test-google-token";
  globalThis.fetch = async (input, options = {}) => {
    const url = String(input);
    if (url.includes("tiktokcdn-us.com")) {
      downloadHeaders = options.headers;
      return new Response(bytes, { headers: { "content-type": "video/mp4" } });
    }
    if (url.endsWith("/v1/videos:annotate")) {
      annotateRequest = JSON.parse(options.body);
      return JSONResponse({
        name: "operations/unit-test",
        done: true,
        response: { annotationResults: [] },
      });
    }
    throw new Error("Unexpected fetch destination");
  };

  try {
    const result = await runUnderstandingProvider("google-video", {
      id: "google-video-media",
      platform: "tiktok",
      contentType: "reel",
      url: "https://www.tiktok.com/@creator/video/1234567890123456789",
    }, {
      status: "ok",
      evidence: { media: [media] },
    });
    assert.equal(result.status, "ok");
    assert.equal(downloadHeaders.cookie, privateCookie);
    assert.equal(annotateRequest.inputContent, bytes.toString("base64"));
    assert.deepEqual(annotateRequest.features, ["TEXT_DETECTION", "SPEECH_TRANSCRIPTION"]);
    assert.equal(JSON.stringify(result).includes(privateCookie), false);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalToken == null) delete process.env.GOOGLE_CLOUD_ACCESS_TOKEN;
    else process.env.GOOGLE_CLOUD_ACCESS_TOKEN = originalToken;
  }
});

test("Google Video rejects a social page URL before making any network request", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalToken = process.env.GOOGLE_CLOUD_ACCESS_TOKEN;
  const pageURL = "https://www.instagram.com/reel/ABC123xyz/";
  let fetchCount = 0;
  process.env.GOOGLE_CLOUD_ACCESS_TOKEN = "unit-test-google-token";
  globalThis.fetch = async () => {
    fetchCount += 1;
    throw new Error("Social page must not be fetched as media");
  };

  try {
    const result = await runUnderstandingProvider("google-video", {
      id: "social-page-rejected",
      platform: "instagram",
      contentType: "reel",
      url: pageURL,
    }, {
      status: "ok",
      evidence: { media: [{ index: 0, type: "video", url: pageURL }] },
    });
    assert.equal(result.status, "failed");
    assert.equal(result.error.code, "social_page_url");
    assert.equal(fetchCount, 0);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalToken == null) delete process.env.GOOGLE_CLOUD_ACCESS_TOKEN;
    else process.env.GOOGLE_CLOUD_ACCESS_TOKEN = originalToken;
  }
});

test("Google Video analyzes every acquired video child", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  const originalToken = process.env.GOOGLE_CLOUD_ACCESS_TOKEN;
  let annotateCount = 0;
  process.env.GOOGLE_CLOUD_ACCESS_TOKEN = "unit-test-google-token";
  globalThis.fetch = async (input) => {
    const url = String(input);
    if (url.includes("cdninstagram.com")) {
      return new Response(tinyMP4Bytes(), { headers: { "content-type": "video/mp4" } });
    }
    annotateCount += 1;
    return JSONResponse({
      name: "operations/unit-test-" + annotateCount,
      done: true,
      response: { annotationResults: [] },
    });
  };
  try {
    const result = await runUnderstandingProvider("google-video", {
      platform: "instagram",
      contentType: "carousel",
      url: "https://www.instagram.com/p/ABC123xyz/",
    }, {
      status: "ok",
      evidence: {
        media: [0, 1].map((index) => ({
          index,
          type: "video",
          url: "https://scontent.cdninstagram.com/child-" + index + ".mp4",
        })),
      },
    });
    assert.equal(result.status, "ok");
    assert.equal(result.mediaIngestion.length, 2);
    assert.equal(annotateCount, 2);
  } finally {
    globalThis.fetch = originalFetch;
    if (originalToken == null) delete process.env.GOOGLE_CLOUD_ACCESS_TOKEN;
    else process.env.GOOGLE_CLOUD_ACCESS_TOKEN = originalToken;
  }
});

test("media acquisition rejects oversized and HTML responses without retaining bytes", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  let responseKind = "oversized";
  globalThis.fetch = async () => responseKind === "oversized"
    ? new Response(tinyMP4Bytes(), {
      headers: { "content-length": "1000", "content-type": "video/mp4" },
    })
    : new Response("<!doctype html><html></html>", {
      headers: { "content-type": "text/html" },
    });

  try {
    const oversized = await fetchAcquiredMediaBytes({
      type: "video",
      url: "https://scontent.cdninstagram.com/video.mp4",
    }, {
      expectedKind: "video",
      maximumBytes: 100,
      socialPageURL: "https://www.instagram.com/reel/ABC123xyz/",
    });
    assert.equal(oversized.error.code, "media_too_large");
    assert.equal("bytes" in oversized, false);

    responseKind = "html";
    const HTML = await fetchAcquiredMediaBytes({
      type: "video",
      url: "https://scontent.cdninstagram.com/video.mp4",
    }, {
      expectedKind: "video",
      maximumBytes: 100,
      socialPageURL: "https://www.instagram.com/reel/ABC123xyz/",
    });
    assert.equal(HTML.error.code, "unsupported_media_type");
    assert.equal("bytes" in HTML, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("media acquisition rejects non-allowlisted hostnames before DNS or fetch", {
  concurrency: false,
}, async () => {
  const originalFetch = globalThis.fetch;
  let fetchCount = 0;
  globalThis.fetch = async () => {
    fetchCount += 1;
    throw new Error("must not fetch");
  };
  try {
    const result = await fetchAcquiredMediaBytes({
      type: "video",
      url: "https://attacker-controlled.example/video.mp4",
    }, {
      expectedKind: "video",
      maximumBytes: 1_000,
      socialPageURL: "https://www.instagram.com/reel/ABC123xyz/",
    });
    assert.equal(result.error.code, "unsafe_media_url");
    assert.equal(fetchCount, 0);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
