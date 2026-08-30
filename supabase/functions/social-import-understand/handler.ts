import { acquireWithApify } from "./apify.ts";
import {
  deterministicFallbackHints,
  evidenceCatalog,
  groundedHints,
} from "./evidence.ts";
import { understandWithGemini } from "./gemini.ts";
import { boundedRequestBody, fetchJSON } from "./http.ts";
import { ingestAcquiredMedia } from "./media.ts";
import { asRecord, cleanString, parseSocialSource } from "./source.ts";
import type {
  AcquisitionEvidence,
  EvidenceCatalog,
  MediaIngestion,
  PublicFallbackReason,
  RuntimeDependencies,
  SocialSource,
  UnderstandResponse,
} from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

export const maximumHandlerDurationMilliseconds = 112_000;
const noStoreHeaders = { "Cache-Control": "private, no-store, max-age=0" };

type PaidWorkAdmissionDecision =
  | "started"
  | "disabled"
  | "duplicate"
  | "replay_required"
  | "busy"
  | "quota";

type PaidWorkAdmission =
  | {
    admitted: true;
    decision: "started";
    admissionID: string;
  }
  | {
    admitted: false;
    decision: Exclude<PaidWorkAdmissionDecision, "started">;
    admissionID: null;
  };

const defaultDependencies: RuntimeDependencies = {
  fetch,
  env: (name) => Deno.env.get(name),
  now: () => Date.now(),
  sleep: (milliseconds) =>
    new Promise((resolve) => setTimeout(resolve, milliseconds)),
  random: Math.random,
};

export async function handleRequest(
  request: Request,
  dependencies: RuntimeDependencies = defaultDependencies,
): Promise<Response> {
  const deadline = new Deadline(
    maximumHandlerDurationMilliseconds,
    dependencies.now,
  );
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authorization = request.headers.get("authorization");
  if (!validBearerHeader(authorization)) {
    return json({ error: "missing_authorization" }, 401);
  }
  if (!await hasCurrentProfile(authorization, deadline, dependencies)) {
    return json({ error: "invalid_authorization" }, 401);
  }
  if (
    !request.headers.get("content-type")?.toLowerCase().includes(
      "application/json",
    )
  ) {
    return json({ error: "unsupported_content_type" }, 415);
  }

  let body: Record<string, unknown>;
  try {
    const parsed = asRecord(await boundedRequestBody(request, 16_384));
    const expectedKeys = new Set([
      "schema_version",
      "platform",
      "url",
      "client_request_id",
    ]);
    if (
      !parsed || Object.keys(parsed).length !== expectedKeys.size ||
      Object.keys(parsed).some((key) => !expectedKeys.has(key)) ||
      parsed.schema_version !== 1 ||
      !validClientRequestID(parsed.client_request_id) ||
      !["instagram", "tiktok"].includes(String(parsed.platform))
    ) {
      return json({ error: "invalid_request" }, 400);
    }
    body = parsed;
  } catch (error) {
    const code = error instanceof SocialImportError
      ? error.code
      : "invalid_request";
    return json({
      error: code === "request_too_large" ? code : "invalid_request",
    }, 400);
  }
  const source = parseSocialSource(body.url);
  if (!source) return json({ error: "unsupported_social_url" }, 400);
  if (body.platform !== source.platform) {
    return json({ error: "platform_mismatch" }, 400);
  }
  const clientRequestID = String(body.client_request_id);

  const apifyToken = secret(dependencies.env("WANDER_APIFY_TOKEN"));
  const geminiKey = secret(dependencies.env("WANDER_GEMINI_API_KEY"));
  if (!apifyToken || !geminiKey) {
    return finish(fallbackResponse(
      "configuration_unavailable",
      null,
      null,
      [],
      0,
    ));
  }

  let admission: PaidWorkAdmission;
  try {
    admission = await beginPaidWorkAdmission(
      authorization,
      clientRequestID,
      deadline,
      dependencies,
    );
  } catch {
    return finish(fallbackResponse(
      "admission_unavailable",
      null,
      null,
      [],
      0,
    ));
  }
  if (!admission.admitted) {
    return finish(fallbackResponse(
      admissionFallbackReason(admission.decision),
      null,
      null,
      [],
      0,
    ));
  }

  let payload: UnderstandResponse;
  try {
    payload = await runAdmittedImport(
      source,
      apifyToken,
      geminiKey,
      deadline,
      dependencies,
      request.signal,
    );
  } catch (error) {
    payload = fallbackResponse(
      fallbackReason(error, "understanding_unavailable"),
      null,
      null,
      [],
      error instanceof SocialImportError ? error.attemptCount : 0,
    );
  } finally {
    try {
      await finishPaidWorkAdmission(
        authorization,
        clientRequestID,
        admission.admissionID,
        deadline,
        dependencies,
      );
    } catch {
      // The database expires orphaned attempts after five minutes. Never log
      // the request ID, admission token, URL, or provider response here.
      console.warn("social_import_admission_finish_failed");
    }
  }
  return finish(payload);
}

async function runAdmittedImport(
  source: SocialSource,
  apifyToken: string,
  geminiKey: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
  signal: AbortSignal,
): Promise<UnderstandResponse> {
  let evidence: AcquisitionEvidence;
  try {
    evidence = await acquireWithApify(
      source,
      apifyToken,
      deadline,
      dependencies,
      signal,
    );
  } catch (error) {
    return fallbackResponse(
      fallbackReason(error, "acquisition_unavailable"),
      null,
      null,
      [],
      0,
    );
  }

  const catalog = evidenceCatalog(evidence);
  let ingestions: MediaIngestion[] = [];
  try {
    ingestions = await ingestAcquiredMedia(
      evidence.media,
      source,
      apifyToken,
      deadline,
      dependencies,
    );
  } catch (error) {
    return fallbackResponse(
      fallbackReason(error, "media_unavailable"),
      evidence,
      catalog,
      ingestions,
      0,
    );
  }

  let understanding;
  try {
    understanding = await understandWithGemini(
      source,
      catalog,
      ingestions,
      geminiKey,
      dependencies.env("WANDER_GEMINI_MODEL"),
      deadline,
      dependencies,
      signal,
    );
  } catch (error) {
    const attempts = error instanceof SocialImportError
      ? error.attemptCount
      : 0;
    clearMediaBytes(ingestions);
    return fallbackResponse(
      fallbackReason(error, "understanding_unavailable"),
      evidence,
      catalog,
      ingestions,
      attempts,
    );
  }

  const grounded = groundedHints(understanding.candidates, catalog, ingestions);
  const ingestedCount =
    ingestions.filter((item) => item.status === "ok").length;
  const failedCount = ingestions.length - ingestedCount;
  clearMediaBytes(ingestions);
  if (grounded.hints.length === 0) {
    if (understanding.candidates.length > 0) {
      return fallbackResponse(
        "grounding_rejected",
        evidence,
        catalog,
        ingestions,
        understanding.attemptCount,
      );
    }
    if (failedCount > 0) {
      return fallbackResponse(
        "media_incomplete",
        evidence,
        catalog,
        ingestions,
        understanding.attemptCount,
      );
    }
    return {
      schema_version: 1,
      outcome: "no_places",
      provider_path: "apify_gemini",
      hints: [],
      media_count: evidence.media.length,
      model_attempt_count: understanding.attemptCount,
      failure_category: null,
    };
  }

  const failureCategory = failedCount > 0
    ? "media_incomplete"
    : grounded.rejectedCount > 0
    ? "grounding_rejected"
    : null;
  return {
    schema_version: 1,
    outcome: failureCategory === null ? "ok" : "partial",
    provider_path: "apify_gemini",
    hints: grounded.hints,
    media_count: evidence.media.length,
    model_attempt_count: understanding.attemptCount,
    failure_category: failureCategory,
  };
}

export async function hasCurrentProfile(
  authorization: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
): Promise<boolean> {
  const supabaseURL = cleanString(
    dependencies.env("SUPABASE_URL") ?? dependencies.env("WANDER_SUPABASE_URL"),
    500,
  );
  const publishableKey = publishableKeyFromEnvironment(dependencies);
  if (!supabaseURL || !publishableKey) return false;
  try {
    const result = await fetchJSON(
      `${supabaseURL.replace(/\/$/, "")}/rest/v1/rpc/current_profile`,
      {
        method: "POST",
        headers: {
          "content-type": "application/json",
          apikey: publishableKey,
          authorization,
        },
        body: "{}",
      },
      64_000,
      10_000,
      deadline,
      dependencies,
    );
    if (!result.response.ok || !Array.isArray(result.body)) return false;
    return result.body.some((value) =>
      cleanString(asRecord(value)?.id, 300) !== null
    );
  } catch {
    return false;
  }
}

export async function beginPaidWorkAdmission(
  authorization: string,
  clientRequestID: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
): Promise<PaidWorkAdmission> {
  const configuration = supabaseRPCConfiguration(dependencies);
  if (!configuration) {
    throw new SocialImportError("admission_configuration_unavailable");
  }
  const result = await fetchJSON(
    `${configuration.url}/rest/v1/rpc/begin_social_import_paid_work`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: configuration.publishableKey,
        authorization,
      },
      body: JSON.stringify({ input_client_request_id: clientRequestID }),
    },
    64_000,
    5_000,
    deadline,
    dependencies,
  );
  if (!result.response.ok) {
    throw new SocialImportError("admission_http_error");
  }
  const row = asRecord(
    Array.isArray(result.body) ? result.body[0] : result.body,
  );
  const decision = cleanString(row?.decision, 32);
  if (
    row?.admitted === true && decision === "started" &&
    validUUID(row.admission_id)
  ) {
    return {
      admitted: true,
      decision,
      admissionID: String(row.admission_id),
    };
  }
  if (
    row?.admitted === false &&
    ["disabled", "duplicate", "replay_required", "busy", "quota"].includes(
      String(decision),
    ) &&
    (row.admission_id === null || row.admission_id === undefined)
  ) {
    return {
      admitted: false,
      decision: decision as Exclude<PaidWorkAdmissionDecision, "started">,
      admissionID: null,
    };
  }
  throw new SocialImportError("invalid_admission_response");
}

export async function finishPaidWorkAdmission(
  authorization: string,
  clientRequestID: string,
  admissionID: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
): Promise<boolean> {
  const configuration = supabaseRPCConfiguration(dependencies);
  if (!configuration) {
    throw new SocialImportError("admission_configuration_unavailable");
  }
  const result = await fetchJSON(
    `${configuration.url}/rest/v1/rpc/finish_social_import_paid_work`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        apikey: configuration.publishableKey,
        authorization,
      },
      body: JSON.stringify({
        input_client_request_id: clientRequestID,
        input_admission_id: admissionID,
      }),
    },
    64_000,
    3_000,
    deadline,
    dependencies,
  );
  if (!result.response.ok || typeof result.body !== "boolean") {
    throw new SocialImportError("admission_finish_error");
  }
  return result.body;
}

function fallbackResponse(
  reason: PublicFallbackReason,
  evidence: AcquisitionEvidence | null,
  catalog: EvidenceCatalog | null,
  ingestions: MediaIngestion[],
  modelAttempts: number,
): UnderstandResponse {
  const safeCatalog = catalog ?? { texts: [], media: [] };
  const hints = deterministicFallbackHints(safeCatalog);
  clearMediaBytes(ingestions);
  return {
    schema_version: 1,
    outcome: hints.length > 0 ? "partial" : "fallback",
    provider_path: "apify_deterministic",
    hints,
    media_count: evidence?.media.length ?? 0,
    model_attempt_count: modelAttempts,
    failure_category: reason,
  };
}

function admissionFallbackReason(
  decision: Exclude<PaidWorkAdmissionDecision, "started">,
): PublicFallbackReason {
  switch (decision) {
    case "disabled":
      return "feature_disabled";
    case "duplicate":
      return "duplicate_request";
    case "replay_required":
      return "retry_required";
    case "busy":
      return "capacity_limited";
    case "quota":
      return "quota_exceeded";
  }
}

function fallbackReason(
  error: unknown,
  defaultReason: PublicFallbackReason,
): PublicFallbackReason {
  return error instanceof SocialImportError &&
      error.code === "deadline_exceeded"
    ? "deadline_exceeded"
    : defaultReason;
}

function validBearerHeader(value: string | null): value is string {
  return value !== null && value.length <= 4_096 &&
    /^Bearer\s+\S+$/i.test(value);
}

function validClientRequestID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[A-Za-z0-9._:-]{1,160}$/.test(value);
}

function validUUID(value: unknown): value is string {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value);
}

function supabaseRPCConfiguration(
  dependencies: RuntimeDependencies,
): { url: string; publishableKey: string } | null {
  const url = cleanString(
    dependencies.env("SUPABASE_URL") ?? dependencies.env("WANDER_SUPABASE_URL"),
    500,
  );
  const publishableKey = publishableKeyFromEnvironment(dependencies);
  return url && publishableKey
    ? { url: url.replace(/\/$/, ""), publishableKey }
    : null;
}

function publishableKeyFromEnvironment(
  dependencies: RuntimeDependencies,
): string | null {
  const publishable = secret(
    dependencies.env("SUPABASE_PUBLISHABLE_KEY") ??
      dependencies.env("WANDER_SUPABASE_PUBLISHABLE_KEY"),
  );
  if (publishable) return publishable;
  const legacy = secret(
    dependencies.env("SUPABASE_ANON_KEY") ??
      dependencies.env("WANDER_SUPABASE_ANON_KEY"),
  );
  if (legacy) return legacy;
  const named = dependencies.env("SUPABASE_PUBLISHABLE_KEYS");
  if (!named) return null;
  try {
    const parsed = asRecord(JSON.parse(named));
    return secret(parsed?.default) ?? Object.values(parsed ?? {})
      .map(secret)
      .find((value) => value !== null) ??
      null;
  } catch {
    return null;
  }
}

function secret(value: unknown): string | null {
  return typeof value === "string" && value.trim() && value.length <= 4_096
    ? value.trim()
    : null;
}

function clearMediaBytes(ingestions: MediaIngestion[]): void {
  for (const ingestion of ingestions) delete ingestion.bytes;
}

function finish(payload: UnderstandResponse): Response {
  console.log(
    "social_import_understand_complete",
    JSON.stringify({
      outcome: payload.outcome,
      providerPath: payload.provider_path,
      mediaCount: payload.media_count,
      modelAttemptCount: payload.model_attempt_count,
      hintCount: payload.hints.length,
      failureCategory: payload.failure_category,
    }),
  );
  return json(payload, 200);
}

function json(value: unknown, status: number): Response {
  return Response.json(value, { status, headers: noStoreHeaders });
}
