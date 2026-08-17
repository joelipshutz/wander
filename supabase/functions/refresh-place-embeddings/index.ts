import "@supabase/functions-js/edge-runtime.d.ts";

const embeddingModel = "text-embedding-3-small";
const embeddingDimensions = 1536;
const documentVersion = 1;
const openAIEmbeddingsURL = "https://api.openai.com/v1/embeddings";
const jsonHeaders = { "Content-Type": "application/json" };

type Environment = (name: string) => string | undefined;
type Dependencies = { fetcher: typeof fetch; env: Environment };
type BackfillCandidate = {
  place_id: string;
  document: string;
  document_hash: string;
};

if (import.meta.main) {
  Deno.serve(async (req) => {
    try {
      return await handleRequest(req);
    } catch (error) {
      console.error(
        "place_embedding_refresh_error",
        error instanceof Error ? error.message : "unknown_error",
      );
      return Response.json({ error: "embedding_refresh_failed" }, { status: 500 });
    }
  });
}

export async function handleRequest(
  req: Request,
  overrides: Partial<Dependencies> = {},
): Promise<Response> {
  if (req.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }

  const env = overrides.env ?? ((name: string) => Deno.env.get(name));
  const fetcher = overrides.fetcher ?? fetch;
  const workerSecret = boundedEnv(env("WANDER_WORKER_SECRET"), 2_048);
  const suppliedSecret = req.headers.get("x-wander-worker-secret")?.trim();
  if (!workerSecret || !suppliedSecret || !constantTimeEqual(workerSecret, suppliedSecret)) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }

  const serviceRoleKey = boundedEnv(
    env("WANDER_SUPABASE_SERVICE_ROLE_KEY") ?? env("SUPABASE_SERVICE_ROLE_KEY"),
    2_048,
  );
  const supabaseURL = boundedEnv(
    env("WANDER_SUPABASE_URL") ?? env("SUPABASE_URL"),
    500,
  );
  const apiKey = boundedEnv(
    env("OPENAI_API_KEY") ?? env("WANDER_OPENAI_API_KEY"),
    2_048,
  );
  if (!serviceRoleKey || !supabaseURL || !apiKey) {
    return Response.json({ error: "embedding_refresh_unavailable" }, { status: 503 });
  }

  const body = await readBody(req);
  const limit = clampInteger(body.limit, 1, 100, 50);
  const candidates = await backfillCandidates(
    limit,
    supabaseURL,
    serviceRoleKey,
    fetcher,
  );
  if (!candidates.length) {
    return Response.json({ processed: 0, remaining: false, model: embeddingModel });
  }

  const embeddings = await createEmbeddings(
    candidates.map((candidate) => candidate.document),
    apiKey,
    fetcher,
  );
  await upsertEmbeddings(candidates, embeddings, supabaseURL, serviceRoleKey, fetcher);

  return Response.json({
    processed: candidates.length,
    remaining: candidates.length === limit,
    model: embeddingModel,
  });
}

async function backfillCandidates(
  limit: number,
  supabaseURL: string,
  serviceRoleKey: string,
  fetcher: typeof fetch,
): Promise<BackfillCandidate[]> {
  const response = await fetcher(
    `${supabaseURL}/rest/v1/rpc/semantic_place_embedding_backfill_batch`,
    {
      method: "POST",
      headers: serviceHeaders(serviceRoleKey),
      body: JSON.stringify({
        input_model: embeddingModel,
        input_document_version: documentVersion,
        input_limit: limit,
      }),
    },
  );
  if (!response.ok) throw new Error(`backfill_rpc_status_${response.status}`);

  const value = await response.json();
  if (!Array.isArray(value)) throw new Error("invalid_backfill_response");
  return value.filter(isBackfillCandidate);
}

async function createEmbeddings(
  documents: string[],
  apiKey: string,
  fetcher: typeof fetch,
): Promise<number[][]> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20_000);
  try {
    const response = await fetcher(openAIEmbeddingsURL, {
      method: "POST",
      signal: controller.signal,
      headers: { ...jsonHeaders, Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        model: embeddingModel,
        input: documents,
        encoding_format: "float",
      }),
    });
    if (!response.ok) throw new Error(`embedding_status_${response.status}`);

    const body = await response.json();
    const rows = Array.isArray(body?.data)
      ? [...body.data].sort((left, right) => left.index - right.index)
      : [];
    const embeddings = rows.map((row) => row.embedding);
    if (embeddings.length !== documents.length || !embeddings.every(isEmbedding)) {
      throw new Error("invalid_embedding_response");
    }
    return embeddings;
  } finally {
    clearTimeout(timeout);
  }
}

async function upsertEmbeddings(
  candidates: BackfillCandidate[],
  embeddings: number[][],
  supabaseURL: string,
  serviceRoleKey: string,
  fetcher: typeof fetch,
): Promise<void> {
  const rows = candidates.map((candidate, index) => ({
    place_id: candidate.place_id,
    model: embeddingModel,
    dimensions: embeddingDimensions,
    document_version: documentVersion,
    document_hash: candidate.document_hash,
    embedding: `[${embeddings[index].join(",")}]`,
  }));
  const response = await fetcher(
    `${supabaseURL}/rest/v1/place_search_embeddings?on_conflict=place_id`,
    {
      method: "POST",
      headers: {
        ...serviceHeaders(serviceRoleKey),
        Prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(rows),
    },
  );
  if (!response.ok) throw new Error(`embedding_upsert_status_${response.status}`);
}

function serviceHeaders(serviceRoleKey: string): Record<string, string> {
  return {
    ...jsonHeaders,
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
  };
}

function isBackfillCandidate(value: unknown): value is BackfillCandidate {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const row = value as Record<string, unknown>;
  return typeof row.place_id === "string" &&
    typeof row.document === "string" && row.document.length > 0 && row.document.length <= 1_000 &&
    typeof row.document_hash === "string" && /^[0-9a-f]{64}$/.test(row.document_hash);
}

function isEmbedding(value: unknown): value is number[] {
  return Array.isArray(value) && value.length === embeddingDimensions &&
    value.every((component) => typeof component === "number" && Number.isFinite(component));
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (!text.trim()) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

function clampInteger(
  value: unknown,
  minimum: number,
  maximum: number,
  fallback: number,
): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  return Math.max(minimum, Math.min(maximum, Math.trunc(value)));
}

function boundedEnv(value: string | undefined, maxLength: number): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed.slice(0, maxLength) : null;
}

function constantTimeEqual(left: string, right: string): boolean {
  const encoder = new TextEncoder();
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  const size = Math.max(leftBytes.length, rightBytes.length);
  let difference = leftBytes.length ^ rightBytes.length;
  for (let index = 0; index < size; index += 1) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return difference === 0;
}
