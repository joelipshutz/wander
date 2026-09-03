#!/usr/bin/env -S deno run --allow-env=APIFY_TOKEN,GEMINI_API_KEY,GEMINI_MODEL --allow-net

import {
  acquireInstagramProfileAliases,
  acquireWithApify,
  normalizeApifyDataset,
} from "../../supabase/functions/social-import-understand/apify.ts";
import { inventoryInstagramCaption } from "../../supabase/functions/social-import-understand/caption-inventory.ts";
import {
  deterministicFallbackHints,
  evidenceCatalog,
  groundedHints,
  profileAliasCandidates,
  recommendedCaptionHandles,
} from "../../supabase/functions/social-import-understand/evidence.ts";
import {
  defaultGeminiThinkingProfile,
  type GeminiThinkingLevel,
  understandWithGemini,
} from "../../supabase/functions/social-import-understand/gemini.ts";
import { ingestAcquiredMedia } from "../../supabase/functions/social-import-understand/media.ts";
import { parseSocialSource } from "../../supabase/functions/social-import-understand/source.ts";
import type {
  AcquisitionEvidence,
  EvidenceCatalog,
  InstagramProfileAlias,
  MediaIngestion,
  ModelCandidate,
  ModelPostContext,
  PlaceHint,
  PublicFallbackReason,
  RuntimeDependencies,
  SocialSource,
} from "../../supabase/functions/social-import-understand/types.ts";
import {
  Deadline,
  SocialImportError,
} from "../../supabase/functions/social-import-understand/types.ts";

const maximumCases = 200;
const maximumCaseDurationMilliseconds = 112_000;
const maximumPersistedModelCandidates = 320;
const maximumPersistedHints = 150;

type DiagnosticArguments = {
  corpusPath: string;
  outputDirectory: string;
  fixtureDirectory: string | null;
  geminiModel: string | null;
  initialThinkingLevel: GeminiThinkingLevel;
  reconciliationThinkingLevel: GeminiThinkingLevel;
  help: boolean;
};

type DiagnosticCorpusCase = {
  id: string;
  platform?: string;
  url: string;
};

type PreparedCase = {
  id: string;
  source: SocialSource;
};

export type DiagnosticOperations = {
  parseSocialSource: typeof parseSocialSource;
  acquireWithApify: typeof acquireWithApify;
  normalizeApifyDataset: typeof normalizeApifyDataset;
  deterministicFallbackHints: typeof deterministicFallbackHints;
  evidenceCatalog: typeof evidenceCatalog;
  inventoryInstagramCaption: typeof inventoryInstagramCaption;
  acquireInstagramProfileAliases: typeof acquireInstagramProfileAliases;
  ingestAcquiredMedia: typeof ingestAcquiredMedia;
  understandWithGemini: typeof understandWithGemini;
  profileAliasCandidates: typeof profileAliasCandidates;
  groundedHints: typeof groundedHints;
};

export type DiagnosticFileSystem = {
  readTextFile(path: string): Promise<string>;
  readOptionalTextFile(path: string): Promise<string | null>;
  prepareOutputDirectory(path: string): Promise<void>;
  writeJSON(
    directory: string,
    filename: string,
    value: unknown,
    secrets: string[],
  ): Promise<void>;
};

type DiagnosticRunOptions = {
  corpusPath: string;
  outputDirectory: string;
  apifyToken: string;
  geminiAPIKey: string;
  geminiModel?: string;
  initialThinkingLevel?: GeminiThinkingLevel;
  reconciliationThinkingLevel?: GeminiThinkingLevel;
  fixtureDirectory?: string;
};

type DiagnosticRunDependencies = {
  operations: DiagnosticOperations;
  runtime: RuntimeDependencies;
  fileSystem: DiagnosticFileSystem;
};

type StageName =
  | "source"
  | "acquisition"
  | "media"
  | "understanding"
  | "grounding";

type DiagnosticCaseResult = {
  schemaVersion: 1;
  caseID: string;
  source: {
    platform: SocialSource["platform"];
    contentType: SocialSource["contentType"];
    sourceID: string | null;
  };
  status: "completed" | "failed";
  failedStage: StageName | null;
  errorCode: string | null;
  acquisition: ReturnType<typeof acquisitionSummary> | null;
  profileEnrichment: {
    status: "ok" | "failed" | "skipped";
    requestedHandleCount: number;
    resolvedAliasCount: number;
  } | null;
  mediaIngestion: ReturnType<typeof ingestionSummary>[];
  understanding: {
    attemptCount: number;
    tokenUsage: {
      promptTokens: number;
      cachedPromptTokens: number;
      responseTokens: number;
      thinkingTokens: number;
      billedOutputTokens: number;
      totalTokens: number;
    } | null;
    postContext: ReturnType<typeof postContextSummary>;
    candidates: ReturnType<typeof candidateSummary>[];
  } | null;
  grounding: {
    fallback: {
      triggerStage: "media" | "understanding";
      failureCategory: PublicFallbackReason;
      modelAttemptCount: number;
    } | null;
    rejectedCount: number;
    excludedCount: number;
    intentionalExcludedCount: number;
    profileAliasCandidateCount: number;
    hints: ReturnType<typeof hintSummary>[];
  } | null;
  latencyMs: number;
};

class DiagnosticError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "DiagnosticError";
    this.code = code;
  }
}

const productionOperations: DiagnosticOperations = {
  parseSocialSource,
  acquireWithApify,
  normalizeApifyDataset,
  deterministicFallbackHints,
  evidenceCatalog,
  inventoryInstagramCaption,
  acquireInstagramProfileAliases,
  ingestAcquiredMedia,
  understandWithGemini,
  profileAliasCandidates,
  groundedHints,
};

export function parseDiagnosticArguments(args: string[]): DiagnosticArguments {
  const values: DiagnosticArguments = {
    corpusPath: "",
    outputDirectory: "",
    fixtureDirectory: null,
    geminiModel: null,
    initialThinkingLevel: defaultGeminiThinkingProfile.initial,
    reconciliationThinkingLevel: defaultGeminiThinkingProfile.reconciliation,
    help: false,
  };
  for (let index = 0; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--help" || argument === "-h") {
      values.help = true;
      continue;
    }
    if (
      ![
        "--corpus",
        "--out",
        "--fixture-dir",
        "--model",
        "--thinking",
        "--reconciliation-thinking",
      ].includes(argument)
    ) {
      throw new DiagnosticError("unknown_argument");
    }
    const next = args[index + 1];
    if (!next || next.startsWith("--")) {
      throw new DiagnosticError("missing_argument_value");
    }
    if (argument === "--corpus") values.corpusPath = next;
    else if (argument === "--out") values.outputDirectory = next;
    else if (argument === "--fixture-dir") values.fixtureDirectory = next;
    else if (argument === "--model") values.geminiModel = validModel(next);
    else if (argument === "--thinking") {
      values.initialThinkingLevel = validThinkingLevel(next);
    } else {
      values.reconciliationThinkingLevel = validThinkingLevel(next);
    }
    index += 1;
  }
  if (!values.help && (!values.corpusPath || !values.outputDirectory)) {
    throw new DiagnosticError("missing_required_argument");
  }
  return values;
}

export async function runProductionParityDiagnostic(
  options: DiagnosticRunOptions,
  dependencies: DiagnosticRunDependencies,
): Promise<
  { manifest: Record<string, unknown>; results: DiagnosticCaseResult[] }
> {
  const corpusText = await dependencies.fileSystem.readTextFile(
    options.corpusPath,
  );
  const corpus = parseCorpus(corpusText, dependencies.operations);
  await dependencies.fileSystem.prepareOutputDirectory(options.outputDirectory);

  const secrets = [options.apifyToken, options.geminiAPIKey];
  const startedAt = new Date().toISOString();
  const corpusSHA256 = await sha256(corpusText);
  const manifest: Record<string, unknown> = {
    schemaVersion: 1,
    runner: "production-parity-v1",
    startedAt,
    corpus: {
      sha256: corpusSHA256,
      selectedCaseIDs: corpus.map((item) => item.id),
    },
    caseCount: corpus.length,
    acquisitionMode: options.fixtureDirectory
      ? "saved_apify_fixture"
      : "live_apify",
    understandingConfiguration: {
      provider: "gemini",
      model: options.geminiModel ?? "gemini-3.5-flash",
      initialThinkingLevel: options.initialThinkingLevel ??
        defaultGeminiThinkingProfile.initial,
      reconciliationThinkingLevel: options.reconciliationThinkingLevel ??
        defaultGeminiThinkingProfile.reconciliation,
    },
  };
  await dependencies.fileSystem.writeJSON(
    options.outputDirectory,
    "manifest.json",
    manifest,
    secrets,
  );

  const results: DiagnosticCaseResult[] = [];
  for (const testCase of corpus) {
    results.push(await runCase(testCase, options, dependencies));
    await dependencies.fileSystem.writeJSON(
      options.outputDirectory,
      "results.json",
      results,
      secrets,
    );
  }

  const completedManifest = {
    ...manifest,
    completedAt: new Date().toISOString(),
    completedCaseCount: results.length,
    failedCaseCount: results.filter((item) => item.status === "failed").length,
  };
  await dependencies.fileSystem.writeJSON(
    options.outputDirectory,
    "manifest.json",
    completedManifest,
    secrets,
  );
  return { manifest: completedManifest, results };
}

async function runCase(
  testCase: PreparedCase,
  options: DiagnosticRunOptions,
  dependencies: DiagnosticRunDependencies,
): Promise<DiagnosticCaseResult> {
  const startedAt = dependencies.runtime.now();
  const deadline = new Deadline(
    maximumCaseDurationMilliseconds,
    dependencies.runtime.now,
  );
  const abortController = new AbortController();
  let stage: StageName = "acquisition";
  let evidence: AcquisitionEvidence | null = null;
  let catalog: EvidenceCatalog | null = null;
  let aliases: InstagramProfileAlias[] = [];
  let ingestions: MediaIngestion[] = [];
  let requestedHandleCount = 0;
  let profileStatus: "ok" | "failed" | "skipped" = "skipped";

  try {
    evidence = options.fixtureDirectory
      ? await loadFixtureEvidence(
        options.fixtureDirectory,
        testCase,
        dependencies.fileSystem,
        dependencies.operations,
      )
      : await dependencies.operations.acquireWithApify(
        testCase.source,
        options.apifyToken,
        deadline,
        dependencies.runtime,
        abortController.signal,
      );
    catalog = dependencies.operations.evidenceCatalog(evidence);

    stage = "media";
    const handles = testCase.source.platform === "instagram" && evidence.caption
      ? prioritizedProfileUsernames(
        evidence.caption,
        dependencies.operations,
      )
      : [];
    requestedHandleCount = handles.length;
    const aliasesPromise = handles.length > 0
      ? dependencies.operations.acquireInstagramProfileAliases(
        handles,
        options.apifyToken,
        deadline,
        dependencies.runtime,
        abortController.signal,
      )
      : Promise.resolve([]);
    const [mediaResult, aliasResult] = await Promise.allSettled([
      dependencies.operations.ingestAcquiredMedia(
        evidence.media,
        testCase.source,
        options.apifyToken,
        deadline,
        dependencies.runtime,
      ),
      aliasesPromise,
    ]);
    if (aliasResult.status === "fulfilled") {
      aliases = aliasResult.value;
      profileStatus = handles.length > 0 ? "ok" : "skipped";
    } else {
      profileStatus = "failed";
    }
    if (mediaResult.status === "rejected") throw mediaResult.reason;
    ingestions = mediaResult.value;

    stage = "understanding";
    const understanding = await dependencies.operations.understandWithGemini(
      testCase.source,
      catalog,
      ingestions,
      options.geminiAPIKey,
      options.geminiModel,
      deadline,
      dependencies.runtime,
      abortController.signal,
      aliases,
      {
        initial: options.initialThinkingLevel ??
          defaultGeminiThinkingProfile.initial,
        reconciliation: options.reconciliationThinkingLevel ??
          defaultGeminiThinkingProfile.reconciliation,
      },
    );
    const aliasCandidates = dependencies.operations.profileAliasCandidates(
      aliases,
      catalog,
    );

    stage = "grounding";
    const grounded = dependencies.operations.groundedHints(
      [...understanding.candidates, ...aliasCandidates],
      catalog,
      ingestions,
      maximumPersistedHints,
      understanding.postContext,
      aliases,
    );
    return {
      schemaVersion: 1,
      caseID: testCase.id,
      source: sourceSummary(testCase.source),
      status: "completed",
      failedStage: null,
      errorCode: null,
      acquisition: acquisitionSummary(
        evidence,
        catalog,
        options.fixtureDirectory ? "saved_apify_fixture" : "live_apify",
      ),
      profileEnrichment: {
        status: profileStatus,
        requestedHandleCount,
        resolvedAliasCount: aliases.length,
      },
      mediaIngestion: ingestions.map(ingestionSummary),
      understanding: {
        attemptCount: boundedInteger(understanding.attemptCount, 0, 6),
        tokenUsage: understanding.tokenUsage
          ? {
            ...understanding.tokenUsage,
            billedOutputTokens: understanding.tokenUsage.responseTokens +
              understanding.tokenUsage.thinkingTokens,
          }
          : null,
        postContext: postContextSummary(understanding.postContext),
        candidates: understanding.candidates
          .slice(0, maximumPersistedModelCandidates)
          .map(candidateSummary),
      },
      grounding: {
        fallback: null,
        rejectedCount: boundedInteger(grounded.rejectedCount, 0, 1_000),
        excludedCount: boundedInteger(grounded.excludedCount, 0, 1_000),
        intentionalExcludedCount: boundedInteger(
          grounded.intentionalExcludedCount,
          0,
          1_000,
        ),
        profileAliasCandidateCount: aliasCandidates.length,
        hints: grounded.hints.slice(0, maximumPersistedHints).map(hintSummary),
      },
      latencyMs: elapsedMilliseconds(startedAt, dependencies.runtime.now()),
    };
  } catch (error) {
    const errorCode = publicErrorCode(error);
    const fallback = catalog && (stage === "media" || stage === "understanding")
      ? fallbackGrounding(
        catalog,
        stage,
        error,
        dependencies.operations,
      )
      : null;
    return {
      schemaVersion: 1,
      caseID: testCase.id,
      source: sourceSummary(testCase.source),
      status: "failed",
      failedStage: stage,
      errorCode,
      acquisition: evidence && catalog
        ? acquisitionSummary(
          evidence,
          catalog,
          options.fixtureDirectory ? "saved_apify_fixture" : "live_apify",
        )
        : null,
      profileEnrichment: evidence
        ? {
          status: profileStatus,
          requestedHandleCount,
          resolvedAliasCount: aliases.length,
        }
        : null,
      mediaIngestion: ingestions.map(ingestionSummary),
      understanding: null,
      grounding: fallback,
      latencyMs: elapsedMilliseconds(startedAt, dependencies.runtime.now()),
    };
  } finally {
    abortController.abort();
    for (const ingestion of ingestions) delete ingestion.bytes;
  }
}

function prioritizedProfileUsernames(
  caption: string,
  operations: DiagnosticOperations,
): string[] {
  const preferred = recommendedCaptionHandles(caption, 20);
  const inventory = operations.inventoryInstagramCaption(caption);
  return [...new Set([...preferred, ...inventory.profileUsernames])].slice(
    0,
    20,
  );
}

function fallbackGrounding(
  catalog: EvidenceCatalog,
  stage: "media" | "understanding",
  error: unknown,
  operations: DiagnosticOperations,
): NonNullable<DiagnosticCaseResult["grounding"]> {
  const hints = operations.deterministicFallbackHints(
    catalog,
    maximumPersistedHints,
  );
  return {
    fallback: {
      triggerStage: stage,
      failureCategory: error instanceof SocialImportError &&
          error.code === "deadline_exceeded"
        ? "deadline_exceeded"
        : stage === "media"
        ? "media_unavailable"
        : "understanding_unavailable",
      modelAttemptCount: stage === "understanding" &&
          error instanceof SocialImportError
        ? boundedInteger(error.attemptCount, 0, 6)
        : 0,
    },
    rejectedCount: 0,
    excludedCount: 0,
    intentionalExcludedCount: 0,
    profileAliasCandidateCount: 0,
    hints: hints.slice(0, maximumPersistedHints).map(hintSummary),
  };
}

function parseCorpus(
  text: string,
  operations: DiagnosticOperations,
): PreparedCase[] {
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new DiagnosticError("invalid_corpus_json");
  }
  const record = asRecord(value);
  if (!record || !Array.isArray(record.cases)) {
    throw new DiagnosticError("invalid_corpus");
  }
  if (record.cases.length === 0 || record.cases.length > maximumCases) {
    throw new DiagnosticError("invalid_corpus_case_count");
  }
  const seen = new Set<string>();
  return record.cases.map((rawCase) => {
    const item = asRecord(rawCase) as DiagnosticCorpusCase | null;
    if (
      !item || typeof item.id !== "string" ||
      !/^[A-Za-z0-9._-]{1,120}$/.test(item.id) || seen.has(item.id) ||
      typeof item.url !== "string" || item.url.length > 2_048
    ) {
      throw new DiagnosticError("invalid_corpus_case");
    }
    const source = operations.parseSocialSource(item.url);
    if (!source || (item.platform && item.platform !== source.platform)) {
      throw new DiagnosticError("unsupported_corpus_source");
    }
    seen.add(item.id);
    return { id: item.id, source };
  });
}

async function loadFixtureEvidence(
  fixtureDirectory: string,
  testCase: PreparedCase,
  fileSystem: DiagnosticFileSystem,
  operations: DiagnosticOperations,
): Promise<AcquisitionEvidence> {
  const filename = `${testCase.id}/apify.json`;
  const candidates = [
    joinPath(fixtureDirectory, filename),
    joinPath(joinPath(fixtureDirectory, "raw"), filename),
  ];
  let text: string | null = null;
  for (const path of candidates) {
    text = await fileSystem.readOptionalTextFile(path);
    if (text !== null) break;
  }
  if (text === null) throw new DiagnosticError("fixture_acquisition_missing");

  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new DiagnosticError("fixture_acquisition_invalid_json");
  }
  const envelope = asRecord(value);
  if (
    !envelope || envelope.caseID !== testCase.id ||
    envelope.provider !== "apify"
  ) {
    throw new DiagnosticError("fixture_acquisition_identity_mismatch");
  }
  if (envelope.status !== "ok") {
    throw new DiagnosticError("fixture_acquisition_unavailable");
  }
  const fixtureSource = operations.parseSocialSource(envelope.sourceURL);
  if (!sameSource(fixtureSource, testCase.source)) {
    throw new DiagnosticError("fixture_acquisition_source_mismatch");
  }
  const raw = asRecord(envelope.raw);
  if (!raw || raw.items == null) {
    throw new DiagnosticError("fixture_acquisition_missing_raw_dataset");
  }
  return operations.normalizeApifyDataset(raw.items, testCase.source);
}

function sameSource(
  candidate: SocialSource | null,
  expected: SocialSource,
): boolean {
  if (!candidate || candidate.platform !== expected.platform) return false;
  if (candidate.sourceID && expected.sourceID) {
    return candidate.sourceID === expected.sourceID;
  }
  return candidate.url === expected.url;
}

function sourceSummary(source: SocialSource) {
  return {
    platform: source.platform,
    contentType: source.contentType,
    sourceID: boundedText(source.sourceID, 64),
  };
}

function acquisitionSummary(
  evidence: AcquisitionEvidence,
  catalog: EvidenceCatalog,
  mode: "live_apify" | "saved_apify_fixture",
) {
  return {
    mode,
    titlePresent: Boolean(evidence.title),
    captionPresent: Boolean(evidence.caption),
    captionCharacterCount: evidence.caption?.length ?? 0,
    taggedLocationCount: evidence.taggedLocations.length,
    textEvidence: catalog.texts.slice(0, 160).map((item) => ({
      id: boundedText(item.id, 80),
      modality: item.modality,
      characterCount: item.text.length,
      mediaID: boundedText(item.mediaID, 80),
    })),
    media: evidence.media.slice(0, 150).map((item) => ({
      id: boundedText(item.id, 80),
      index: boundedInteger(item.index, 0, 10_000),
      kind: item.kind,
      altTextPresent: Boolean(item.altText),
    })),
  };
}

function ingestionSummary(item: MediaIngestion) {
  return {
    mediaID: boundedText(item.mediaID, 80),
    kind: item.kind,
    status: item.status,
    byteCount: item.byteCount == null
      ? null
      : boundedInteger(item.byteCount, 0, 100_000_000),
    mimeType: boundedText(item.mimeType, 100),
    errorCode: boundedCode(item.errorCode),
  };
}

function candidateSummary(candidate: ModelCandidate) {
  return {
    name: boundedText(candidate.name, 160),
    sourceMention: boundedText(candidate.sourceMention, 200),
    area: boundedText(candidate.area, 160) ?? "",
    entityType: candidate.entityType,
    itemIndex: boundedInteger(candidate.itemIndex, -1, 10_000),
    classification: candidate.classification,
    modality: candidate.modality,
    evidenceIds: candidate.evidenceIds.slice(0, 8).map((item) =>
      boundedText(item, 80)
    ).filter((item): item is string => item !== null),
    confidence: boundedNumber(candidate.confidence, 0, 1),
    startMs: boundedNumber(candidate.startMs, -1, 86_400_000),
    endMs: boundedNumber(candidate.endMs, -1, 86_400_000),
  };
}

function postContextSummary(context?: ModelPostContext) {
  if (!context) return null;
  return {
    intent: context.intent,
    declaredCount: boundedInteger(context.declaredCount, -1, 150),
    declaredCountEvidenceIds: context.declaredCountEvidenceIds
      .slice(0, 8)
      .map((item) => boundedText(item, 80))
      .filter((item): item is string => item !== null),
    globalArea: boundedText(context.globalArea, 160) ?? "",
    globalAreaEvidenceIds: context.globalAreaEvidenceIds
      .slice(0, 8)
      .map((item) => boundedText(item, 80))
      .filter((item): item is string => item !== null),
  };
}

function hintSummary(hint: PlaceHint) {
  return {
    name: boundedText(hint.name, 160),
    area: boundedText(hint.area, 160),
    classification: hint.classification,
    modality: hint.modality,
    evidence_ids: hint.evidence_ids.slice(0, 8).map((item) =>
      boundedText(item, 80)
    ).filter((item): item is string => item !== null),
    confidence: boundedNumber(hint.confidence, 0, 1),
    start_ms: hint.start_ms == null
      ? null
      : boundedNumber(hint.start_ms, 0, 86_400_000),
    end_ms: hint.end_ms == null
      ? null
      : boundedNumber(hint.end_ms, 0, 86_400_000),
  };
}

function boundedText(value: unknown, maximum: number): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/[\u0000-\u001f\u007f]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maximum);
  if (!cleaned) return null;
  return /(?:https?:\/\/|api\.apify\.com\/v2\/key-value-stores\/)/i.test(
      cleaned,
    )
    ? "[redacted_url]"
    : cleaned;
}

function boundedCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  return /^[A-Za-z0-9._:-]{1,100}$/.test(value) ? value : "redacted_error";
}

function boundedInteger(
  value: number,
  minimum: number,
  maximum: number,
): number {
  if (!Number.isFinite(value)) return minimum;
  return Math.max(minimum, Math.min(maximum, Math.round(value)));
}

function boundedNumber(
  value: number,
  minimum: number,
  maximum: number,
): number {
  if (!Number.isFinite(value)) return minimum;
  return Math.max(minimum, Math.min(maximum, value));
}

function elapsedMilliseconds(startedAt: number, endedAt: number): number {
  return boundedInteger(
    endedAt - startedAt,
    0,
    maximumCaseDurationMilliseconds,
  );
}

function publicErrorCode(error: unknown): string {
  if (error instanceof SocialImportError) {
    return boundedCode(error.code) ?? "provider_error";
  }
  if (error instanceof DiagnosticError) return error.code;
  return "unexpected_error";
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function productionRuntime(): RuntimeDependencies {
  return {
    fetch,
    env: (name) => Deno.env.get(name),
    now: () => Date.now(),
    sleep: (milliseconds) =>
      new Promise((resolve) => setTimeout(resolve, milliseconds)),
    random: Math.random,
  };
}

function denoFileSystem(): DiagnosticFileSystem {
  return {
    readTextFile: (path) => Deno.readTextFile(path),
    readOptionalTextFile: async (path) => {
      try {
        return await Deno.readTextFile(path);
      } catch (error) {
        if (error instanceof Deno.errors.NotFound) return null;
        throw error;
      }
    },
    prepareOutputDirectory: preparePrivateOutputDirectory,
    writeJSON: writePrivateJSON,
  };
}

async function preparePrivateOutputDirectory(path: string): Promise<void> {
  let info: Deno.FileInfo;
  try {
    info = await Deno.stat(path);
  } catch (error) {
    if (!(error instanceof Deno.errors.NotFound)) throw error;
    await Deno.mkdir(path, { recursive: true, mode: 0o700 });
    info = await Deno.stat(path);
  }
  if (!info.isDirectory) throw new DiagnosticError("output_is_not_directory");
  if (info.mode != null && (info.mode & 0o077) !== 0) {
    throw new DiagnosticError("output_directory_not_private");
  }
  for (const filename of ["manifest.json", "results.json"]) {
    try {
      await Deno.stat(joinPath(path, filename));
      throw new DiagnosticError("output_file_exists");
    } catch (error) {
      if (error instanceof Deno.errors.NotFound) continue;
      throw error;
    }
  }
}

async function writePrivateJSON(
  directory: string,
  filename: string,
  value: unknown,
  secrets: string[],
): Promise<void> {
  const serialized = JSON.stringify(value, null, 2) + "\n";
  for (const secret of secrets) {
    if (secret.length >= 8 && serialized.includes(secret)) {
      throw new DiagnosticError("secret_redaction_failed");
    }
  }
  const destination = joinPath(directory, filename);
  const temporary = `${destination}.tmp-${crypto.randomUUID()}`;
  try {
    await Deno.writeTextFile(temporary, serialized, { mode: 0o600 });
    await Deno.rename(temporary, destination);
    await Deno.chmod(destination, 0o600);
  } finally {
    await Deno.remove(temporary).catch(() => undefined);
  }
}

function joinPath(directory: string, filename: string): string {
  return `${directory.replace(/\/+$/, "")}/${filename}`;
}

function validSecret(value: string | undefined): string | null {
  return typeof value === "string" && value.trim() && value.length <= 4_096
    ? value.trim()
    : null;
}

function validModel(value: string): string {
  const model = value.trim();
  if (!/^[A-Za-z0-9._-]{1,120}$/.test(model)) {
    throw new DiagnosticError("invalid_model");
  }
  return model;
}

function validThinkingLevel(value: string): GeminiThinkingLevel {
  const level = value.trim().toUpperCase();
  if (level !== "LOW" && level !== "MEDIUM" && level !== "HIGH") {
    throw new DiagnosticError("invalid_thinking_level");
  }
  return level;
}

function usage(): string {
  return `Production-parity social import diagnostic

Usage:
  deno run --allow-env=APIFY_TOKEN,GEMINI_API_KEY,GEMINI_MODEL \\
    --allow-read --allow-write --allow-net \\
    scripts/social-import-eval/production-parity.ts \\
    --corpus <path> --out <private-directory> [--fixture-dir <run-or-raw-directory>] \
    [--model <gemini-model>] [--thinking <low|medium|high>] \
    [--reconciliation-thinking <low|medium|high>]
`;
}

async function main(): Promise<void> {
  let args: DiagnosticArguments;
  try {
    args = parseDiagnosticArguments(Deno.args);
  } catch (error) {
    console.error(`production-parity diagnostic: ${publicErrorCode(error)}`);
    Deno.exitCode = 1;
    return;
  }
  if (args.help) {
    console.log(usage());
    return;
  }
  const apifyToken = validSecret(Deno.env.get("APIFY_TOKEN"));
  const geminiAPIKey = validSecret(Deno.env.get("GEMINI_API_KEY"));
  if (!apifyToken || !geminiAPIKey) {
    console.error(
      "production-parity diagnostic: missing_provider_configuration",
    );
    Deno.exitCode = 1;
    return;
  }
  try {
    const run = await runProductionParityDiagnostic(
      {
        corpusPath: args.corpusPath,
        outputDirectory: args.outputDirectory,
        apifyToken,
        geminiAPIKey,
        geminiModel: args.geminiModel ??
          validSecret(Deno.env.get("GEMINI_MODEL")) ?? undefined,
        initialThinkingLevel: args.initialThinkingLevel,
        reconciliationThinkingLevel: args.reconciliationThinkingLevel,
        fixtureDirectory: args.fixtureDirectory ?? undefined,
      },
      {
        operations: productionOperations,
        runtime: productionRuntime(),
        fileSystem: denoFileSystem(),
      },
    );
    console.log(JSON.stringify({
      outcome: "complete",
      caseCount: run.results.length,
      failedCaseCount: run.results.filter((item) =>
        item.status === "failed"
      ).length,
    }));
  } catch (error) {
    console.error(`production-parity diagnostic: ${publicErrorCode(error)}`);
    Deno.exitCode = 1;
  }
}

if (import.meta.main) await main();
