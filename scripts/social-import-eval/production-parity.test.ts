import assert from "node:assert/strict";
import { test } from "node:test";

import { deterministicFallbackHints } from "../../supabase/functions/social-import-understand/evidence.ts";
import {
  type RuntimeDependencies,
  SocialImportError,
} from "../../supabase/functions/social-import-understand/types.ts";
import {
  type DiagnosticFileSystem,
  type DiagnosticOperations,
  parseDiagnosticArguments,
  runProductionParityDiagnostic,
} from "./production-parity.ts";

test("production-parity arguments require explicit corpus and output paths", () => {
  assert.deepEqual(
    parseDiagnosticArguments([
      "--corpus",
      "/private/corpus.json",
      "--out",
      "/private/run",
    ]),
    {
      corpusPath: "/private/corpus.json",
      outputDirectory: "/private/run",
      fixtureDirectory: null,
      help: false,
    },
  );
  assert.throws(
    () => parseDiagnosticArguments(["--corpus", "/private/corpus.json"]),
    /missing_required_argument/,
  );
  assert.throws(
    () => parseDiagnosticArguments(["--token", "must-not-be-supported"]),
    /unknown_argument/,
  );
  assert.equal(
    parseDiagnosticArguments([
      "--corpus",
      "/private/corpus.json",
      "--out",
      "/private/run",
      "--fixture-dir",
      "/private/acquisition",
    ]).fixtureDirectory,
    "/private/acquisition",
  );
});

test("production-parity output is bounded and omits tokens, captions, bytes, and media URLs", async () => {
  const apifyToken = "apify-token-that-must-never-be-written";
  const geminiAPIKey = "gemini-key-that-must-never-be-written";
  const signedMediaURL =
    `https://api.apify.com/v2/key-value-stores/store/records/video?token=${apifyToken}`;
  const caption =
    "Dinner at @grounded_cafe with private diagnostic caption text";
  const calls: string[] = [];
  const writes = new Map<string, string>();
  const corpus = JSON.stringify({
    schemaVersion: 1,
    cases: [{
      id: "private-case",
      platform: "instagram",
      url: "https://www.instagram.com/reel/DcpkzKFIEuz/",
    }],
  });
  const fileSystem: DiagnosticFileSystem = {
    readTextFile: async () => corpus,
    readOptionalTextFile: async () => null,
    prepareOutputDirectory: async () => undefined,
    writeJSON: async (_directory, filename, value, secrets) => {
      const serialized = JSON.stringify(value);
      for (const secret of secrets) {
        assert.equal(serialized.includes(secret), false);
      }
      writes.set(filename, serialized);
    },
  };
  const operations = {
    parseSocialSource: () => ({
      platform: "instagram",
      contentType: "reel",
      url: "https://www.instagram.com/reel/DcpkzKFIEuz",
      sourceID: "DcpkzKFIEuz",
    }),
    acquireWithApify: async () => {
      calls.push("acquire");
      return {
        title: "Private title",
        caption,
        taggedLocations: [],
        media: [{
          id: "media:0",
          index: 0,
          kind: "video",
          url: signedMediaURL,
          thumbnailURL: null,
          altText: null,
        }],
      };
    },
    evidenceCatalog: (evidence: { caption: string; media: unknown[] }) => ({
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: evidence.caption,
        area: null,
        mediaID: null,
      }],
      media: evidence.media,
    }),
    inventoryInstagramCaption: () => {
      calls.push("inventory");
      return {
        mentions: [],
        handleMentions: [],
        listItems: [],
        profileUsernames: ["grounded_cafe"],
      };
    },
    acquireInstagramProfileAliases: async () => {
      calls.push("aliases");
      return [{ username: "grounded_cafe", fullName: "Grounded Cafe" }];
    },
    ingestAcquiredMedia: async () => {
      calls.push("media");
      return [{
        mediaID: "media:0",
        kind: "video",
        status: "ok",
        byteCount: 4,
        mimeType: "video/mp4",
        bytes: new TextEncoder().encode(apifyToken),
        errorCode: null,
      }];
    },
    understandWithGemini: async () => {
      calls.push("gemini");
      return {
        candidates: [{
          name: "Grounded Cafe",
          sourceMention: "@grounded_cafe",
          area: "Los Angeles",
          entityType: "poi",
          itemIndex: 0,
          classification: "destination",
          modality: "caption",
          evidenceIds: ["caption:0"],
          confidence: 0.98,
          startMs: -1,
          endMs: -1,
        }],
        postContext: {
          intent: "place_list",
          declaredCount: 1,
          declaredCountEvidenceIds: ["caption:0"],
          globalArea: "Los Angeles",
          globalAreaEvidenceIds: ["caption:0"],
        },
        attemptCount: 1,
      };
    },
    profileAliasCandidates: () => {
      calls.push("profile_candidates");
      return [];
    },
    groundedHints: () => {
      calls.push("grounding");
      return {
        hints: [{
          name: "Grounded Cafe",
          area: "Los Angeles",
          classification: "destination",
          modality: "caption",
          evidence_ids: ["caption:0"],
          confidence: 0.98,
          start_ms: null,
          end_ms: null,
        }],
        rejectedCount: 0,
        excludedCount: 0,
        intentionalExcludedCount: 0,
      };
    },
  } as unknown as DiagnosticOperations;
  const runtime: RuntimeDependencies = {
    fetch: globalThis.fetch,
    env: () => undefined,
    now: Date.now,
    sleep: async () => undefined,
    random: () => 0.5,
  };

  const run = await runProductionParityDiagnostic(
    {
      corpusPath: "/private/corpus.json",
      outputDirectory: "/private/run",
      apifyToken,
      geminiAPIKey,
      geminiModel: "gemini-test-model",
    },
    { operations, runtime, fileSystem },
  );

  assert.deepEqual(calls, [
    "acquire",
    "inventory",
    "aliases",
    "media",
    "gemini",
    "profile_candidates",
    "grounding",
  ]);
  assert.equal(run.results[0].status, "completed");
  assert.equal(
    run.results[0].understanding?.candidates[0].name,
    "Grounded Cafe",
  );
  assert.equal(run.results[0].grounding?.hints[0].name, "Grounded Cafe");
  const persisted = [...writes.values()].join("\n");
  for (
    const forbidden of [
      apifyToken,
      geminiAPIKey,
      signedMediaURL,
      caption,
      "Private title",
    ]
  ) assert.equal(persisted.includes(forbidden), false);
  assert.equal(persisted.includes("bytes"), false);
  assert.equal(persisted.includes("captionCharacterCount"), true);
});

test("production-parity reuses a saved evaluator acquisition without starting Apify scraping", async () => {
  const apifyToken = "fixture-apify-token-that-stays-in-memory";
  const geminiAPIKey = "fixture-gemini-key-that-stays-in-memory";
  const mediaURL =
    "https://api.apify.com/v2/key-value-stores/store/records/video";
  const fixturePaths: string[] = [];
  const writes = new Map<string, string>();
  const corpus = JSON.stringify({
    schemaVersion: 1,
    cases: [{
      id: "fixture-case",
      platform: "instagram",
      url: "https://www.instagram.com/reel/DcpkzKFIEuz/",
    }],
  });
  const fixture = JSON.stringify({
    schemaVersion: 1,
    caseID: "fixture-case",
    sourceURL: "https://www.instagram.com/reel/DcpkzKFIEuz/",
    provider: "apify",
    status: "ok",
    raw: { items: [{ fixtureRecord: true }] },
  });
  const fileSystem: DiagnosticFileSystem = {
    readTextFile: async () => corpus,
    readOptionalTextFile: async (path) => {
      fixturePaths.push(path);
      return path.endsWith("/raw/fixture-case/apify.json") ? fixture : null;
    },
    prepareOutputDirectory: async () => undefined,
    writeJSON: async (_directory, filename, value) => {
      writes.set(filename, JSON.stringify(value));
    },
  };
  let liveAcquisitionCalled = false;
  const operations = {
    parseSocialSource: () => ({
      platform: "instagram",
      contentType: "reel",
      url: "https://www.instagram.com/reel/DcpkzKFIEuz",
      sourceID: "DcpkzKFIEuz",
    }),
    acquireWithApify: async () => {
      liveAcquisitionCalled = true;
      throw new Error("live acquisition must not run during fixture replay");
    },
    normalizeApifyDataset: (
      raw: unknown,
      source: { sourceID: string | null },
    ) => {
      assert.deepEqual(raw, [{ fixtureRecord: true }]);
      assert.equal(source.sourceID, "DcpkzKFIEuz");
      return {
        title: null,
        caption: "One place at Fixture Cafe",
        taggedLocations: [],
        media: [{
          id: "media:0",
          index: 0,
          kind: "video",
          url: mediaURL,
          thumbnailURL: null,
          altText: null,
        }],
      };
    },
    evidenceCatalog: (evidence: { caption: string; media: unknown[] }) => ({
      texts: [{
        id: "caption:0",
        modality: "caption",
        text: evidence.caption,
        area: null,
        mediaID: null,
      }],
      media: evidence.media,
    }),
    inventoryInstagramCaption: () => ({
      mentions: [],
      handleMentions: [],
      listItems: [],
      profileUsernames: [],
    }),
    acquireInstagramProfileAliases: async () => {
      throw new Error("profile acquisition should be skipped without handles");
    },
    ingestAcquiredMedia: async (
      media: Array<{ url: string }>,
      _source: unknown,
      token: string,
    ) => {
      assert.equal(token, apifyToken);
      assert.equal(media[0].url, mediaURL);
      return [{
        mediaID: "media:0",
        kind: "video",
        status: "ok",
        byteCount: 4,
        mimeType: "video/mp4",
        bytes: new Uint8Array([0, 1, 2, 3]),
        errorCode: null,
      }];
    },
    understandWithGemini: async () => ({
      candidates: [{
        name: "Fixture Cafe",
        sourceMention: "Fixture Cafe",
        area: "",
        entityType: "poi",
        itemIndex: 0,
        classification: "destination",
        modality: "caption",
        evidenceIds: ["caption:0"],
        confidence: 0.9,
        startMs: -1,
        endMs: -1,
      }],
      attemptCount: 1,
    }),
    profileAliasCandidates: () => [],
    groundedHints: () => ({
      hints: [{
        name: "Fixture Cafe",
        area: null,
        classification: "destination",
        modality: "caption",
        evidence_ids: ["caption:0"],
        confidence: 0.9,
        start_ms: null,
        end_ms: null,
      }],
      rejectedCount: 0,
      excludedCount: 0,
      intentionalExcludedCount: 0,
    }),
  } as unknown as DiagnosticOperations;
  const runtime: RuntimeDependencies = {
    fetch: globalThis.fetch,
    env: () => undefined,
    now: Date.now,
    sleep: async () => undefined,
    random: () => 0.5,
  };

  const run = await runProductionParityDiagnostic(
    {
      corpusPath: "/private/corpus.json",
      outputDirectory: "/private/output",
      fixtureDirectory: "/private/saved-run",
      apifyToken,
      geminiAPIKey,
    },
    { operations, runtime, fileSystem },
  );

  assert.equal(liveAcquisitionCalled, false);
  assert.deepEqual(fixturePaths, [
    "/private/saved-run/fixture-case/apify.json",
    "/private/saved-run/raw/fixture-case/apify.json",
  ]);
  assert.equal(run.manifest.acquisitionMode, "saved_apify_fixture");
  assert.equal(run.results[0].acquisition?.mode, "saved_apify_fixture");
  assert.equal(run.results[0].grounding?.hints[0].name, "Fixture Cafe");
  const persisted = [...writes.values()].join("\n");
  assert.equal(persisted.includes(mediaURL), false);
  assert.equal(persisted.includes(apifyToken), false);
  assert.equal(persisted.includes(geminiAPIKey), false);
  assert.equal(persisted.includes("One place at Fixture Cafe"), false);
});

for (const failureStage of ["media", "understanding"] as const) {
  test(`production-parity persists production fallback hints after ${failureStage} failure`, async () => {
    const apifyToken = "fallback-apify-token-that-stays-in-memory";
    const geminiAPIKey = "fallback-gemini-key-that-stays-in-memory";
    const caption = "1. Fallback Cafe\n2. Backup Bar";
    const writes = new Map<string, string>();
    let understandingCalled = false;
    const corpus = JSON.stringify({
      schemaVersion: 1,
      cases: [{
        id: `${failureStage}-fallback-case`,
        platform: "instagram",
        url: "https://www.instagram.com/reel/DcpkzKFIEuz/",
      }],
    });
    const fileSystem: DiagnosticFileSystem = {
      readTextFile: async () => corpus,
      readOptionalTextFile: async () => null,
      prepareOutputDirectory: async () => undefined,
      writeJSON: async (_directory, filename, value, secrets) => {
        const serialized = JSON.stringify(value);
        for (const secret of secrets) {
          assert.equal(serialized.includes(secret), false);
        }
        writes.set(filename, serialized);
      },
    };
    const operations = {
      parseSocialSource: () => ({
        platform: "instagram",
        contentType: "reel",
        url: "https://www.instagram.com/reel/DcpkzKFIEuz",
        sourceID: "DcpkzKFIEuz",
      }),
      acquireWithApify: async () => ({
        title: null,
        caption,
        taggedLocations: [],
        media: [{
          id: "media:0",
          index: 0,
          kind: "video",
          url: "https://media.example/video.mp4",
          thumbnailURL: null,
          altText: null,
        }],
      }),
      evidenceCatalog: (evidence: { caption: string; media: unknown[] }) => ({
        texts: [{
          id: "caption:0",
          modality: "caption",
          text: evidence.caption,
          area: null,
          mediaID: null,
        }],
        media: evidence.media,
      }),
      inventoryInstagramCaption: () => ({
        mentions: [],
        handleMentions: [],
        listItems: [],
        profileUsernames: [],
      }),
      acquireInstagramProfileAliases: async () => {
        throw new Error("profile acquisition should be skipped without handles");
      },
      ingestAcquiredMedia: async () => {
        if (failureStage === "media") {
          throw new SocialImportError("media_fetch_failed");
        }
        return [{
          mediaID: "media:0",
          kind: "video",
          status: "ok",
          byteCount: 4,
          mimeType: "video/mp4",
          bytes: new Uint8Array([0, 1, 2, 3]),
          errorCode: null,
        }];
      },
      understandWithGemini: async () => {
        understandingCalled = true;
        throw new SocialImportError("gemini_http_503", 2);
      },
      deterministicFallbackHints,
      profileAliasCandidates: () => {
        throw new Error("profile candidates must not run after a failed stage");
      },
      groundedHints: () => {
        throw new Error("Gemini grounding must not run after a failed stage");
      },
    } as unknown as DiagnosticOperations;
    const runtime: RuntimeDependencies = {
      fetch: globalThis.fetch,
      env: () => undefined,
      now: Date.now,
      sleep: async () => undefined,
      random: () => 0.5,
    };

    const run = await runProductionParityDiagnostic(
      {
        corpusPath: "/private/corpus.json",
        outputDirectory: "/private/output",
        apifyToken,
        geminiAPIKey,
      },
      { operations, runtime, fileSystem },
    );

    const result = run.results[0];
    assert.equal(result.status, "failed");
    assert.equal(result.failedStage, failureStage);
    assert.equal(
      result.errorCode,
      failureStage === "media" ? "media_fetch_failed" : "gemini_http_503",
    );
    assert.equal(understandingCalled, failureStage === "understanding");
    assert.deepEqual(
      result.grounding?.hints.map((hint) => hint.name),
      ["Fallback Cafe", "Backup Bar"],
    );
    assert.deepEqual(result.grounding?.fallback, {
      triggerStage: failureStage,
      failureCategory: failureStage === "media"
        ? "media_unavailable"
        : "understanding_unavailable",
      modelAttemptCount: failureStage === "media" ? 0 : 2,
    });
    assert.equal(result.grounding?.rejectedCount, 0);
    assert.equal(result.grounding?.profileAliasCandidateCount, 0);

    const persisted = [...writes.values()].join("\n");
    assert.equal(persisted.includes(caption), false);
    assert.equal(persisted.includes("bytes"), false);
    assert.equal(persisted.includes(apifyToken), false);
    assert.equal(persisted.includes(geminiAPIKey), false);
  });
}
