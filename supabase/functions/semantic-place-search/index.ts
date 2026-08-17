import "@supabase/functions-js/edge-runtime.d.ts";

const embeddingModel = "text-embedding-3-small";
const embeddingDimensions = 1536;
const openAIEmbeddingsURL = "https://api.openai.com/v1/embeddings";
const jsonHeaders = { "Content-Type": "application/json" };
const allowedScopes = new Set(["everyone", "mine", "friends", "following"]);

type Environment = (name: string) => string | undefined;
type Dependencies = {
  fetcher: typeof fetch;
  env: Environment;
  validateAuthorization: (authorization: string) => Promise<boolean>;
};
type SemanticSearchPayload = {
  query: string;
  categories: string[];
  area: string | null;
  favoriteOnly: boolean;
  scope: string;
  limit: number;
};
type SemanticRPCRow = Record<string, unknown> & { semantic_similarity?: unknown };

if (import.meta.main) {
  Deno.serve(async (req) => {
    try {
      return await handleRequest(req);
    } catch (error) {
      console.error(
        "semantic_place_search_error",
        error instanceof Error ? error.message : "unknown_error",
      );
      return Response.json({ error: "semantic_search_unavailable" }, { status: 503 });
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
  const authorization = req.headers.get("authorization");
  if (!authorization) {
    return Response.json({ error: "missing_authorization" }, { status: 401 });
  }

  const validateAuthorization = overrides.validateAuthorization ??
    ((value: string) => hasValidSupabaseSession(value, fetcher, env));
  if (!await validateAuthorization(authorization)) {
    return Response.json({ error: "invalid_authorization" }, { status: 401 });
  }

  const payload = semanticSearchPayload(await readBody(req));
  if (!payload.query) {
    return Response.json({ candidates: [], provider: "semantic_v1" });
  }

  const apiKey = boundedEnv(
    env("OPENAI_API_KEY") ?? env("WANDER_OPENAI_API_KEY"),
    2_048,
  );
  const supabaseURL = boundedEnv(env("SUPABASE_URL") ?? env("WANDER_SUPABASE_URL"), 500);
  const publishableKey = boundedEnv(
    env("SUPABASE_ANON_KEY") ?? env("WANDER_SUPABASE_ANON_KEY"),
    2_048,
  );
  if (!apiKey || !supabaseURL || !publishableKey) {
    return Response.json({ error: "semantic_search_unavailable" }, { status: 503 });
  }

  const embedding = await createEmbedding(payload.query, apiKey, fetcher);
  const rows = await semanticRPC(
    payload,
    embedding,
    authorization,
    supabaseURL,
    publishableKey,
    fetcher,
  );

  return Response.json({
    candidates: rows.map(({ semantic_similarity: _, ...candidate }) => candidate),
    provider: "semantic_v1",
  });
}

export async function hasValidSupabaseSession(
  authorization: string,
  fetcher: typeof fetch = fetch,
  env: Environment = (name) => Deno.env.get(name),
): Promise<boolean> {
  const suppliedToken = authorization.replace(/^Bearer\s+/i, "").trim();
  const serviceRoleKey = boundedEnv(env("SUPABASE_SERVICE_ROLE_KEY"), 2_048);
  if (serviceRoleKey && suppliedToken === serviceRoleKey) return true;

  const supabaseURL = boundedEnv(env("SUPABASE_URL"), 500);
  const publishableKey = boundedEnv(env("SUPABASE_ANON_KEY"), 2_048);
  if (!supabaseURL || !publishableKey) return false;

  try {
    const response = await fetcher(`${supabaseURL}/rest/v1/rpc/current_profile`, {
      method: "POST",
      headers: {
        ...jsonHeaders,
        apikey: publishableKey,
        Authorization: authorization,
      },
      body: "{}",
    });
    return response.ok;
  } catch {
    return false;
  }
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

function semanticSearchPayload(body: Record<string, unknown>): SemanticSearchPayload {
  const scopeCandidate = cleanString(body.scope, 24)?.toLowerCase() ?? "everyone";
  const scope = allowedScopes.has(scopeCandidate) ? scopeCandidate : "everyone";
  const categoryValues = Array.isArray(body.categories) ? body.categories : [];
  const categories = [...new Set(categoryValues
    .map((value) => cleanString(value, 64))
    .filter((value): value is string => value !== null))]
    .slice(0, 8);

  return {
    query: cleanString(body.query, 160) ?? "",
    categories,
    area: cleanString(body.area, 100),
    favoriteOnly: body.favorite_only === true,
    scope,
    limit: clampInteger(body.limit, 1, 20, 20),
  };
}

async function createEmbedding(
  query: string,
  apiKey: string,
  fetcher: typeof fetch,
): Promise<number[]> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4_000);
  try {
    const response = await fetcher(openAIEmbeddingsURL, {
      method: "POST",
      signal: controller.signal,
      headers: { ...jsonHeaders, Authorization: `Bearer ${apiKey}` },
      body: JSON.stringify({
        model: embeddingModel,
        input: query,
        encoding_format: "float",
      }),
    });
    if (!response.ok) throw new Error(`embedding_status_${response.status}`);

    const body = await response.json();
    const vector = body?.data?.[0]?.embedding;
    if (!isEmbedding(vector)) throw new Error("invalid_embedding_response");
    return vector;
  } finally {
    clearTimeout(timeout);
  }
}

async function semanticRPC(
  payload: SemanticSearchPayload,
  embedding: number[],
  authorization: string,
  supabaseURL: string,
  publishableKey: string,
  fetcher: typeof fetch,
): Promise<SemanticRPCRow[]> {
  const response = await fetcher(`${supabaseURL}/rest/v1/rpc/search_recme_places_semantic`, {
    method: "POST",
    headers: {
      ...jsonHeaders,
      apikey: publishableKey,
      Authorization: authorization,
    },
    body: JSON.stringify({
      input_embedding: vectorLiteral(embedding),
      input_categories: payload.categories.length ? payload.categories : null,
      input_area: payload.area,
      input_favorite_only: payload.favoriteOnly,
      input_scope: payload.scope,
      input_limit: payload.limit,
      input_min_similarity: 0.35,
    }),
  });
  if (!response.ok) throw new Error(`semantic_rpc_status_${response.status}`);

  const rows = await response.json();
  if (!Array.isArray(rows)) throw new Error("invalid_semantic_rpc_response");
  return rows.filter((row): row is SemanticRPCRow =>
    row !== null && typeof row === "object" && !Array.isArray(row)
  );
}

function isEmbedding(value: unknown): value is number[] {
  return Array.isArray(value) && value.length === embeddingDimensions &&
    value.every((component) => typeof component === "number" && Number.isFinite(component));
}

function vectorLiteral(value: number[]): string {
  return `[${value.join(",")}]`;
}

function cleanString(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") return null;
  const cleaned = value.replace(/[\u0000-\u001F\u007F]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength);
  return cleaned || null;
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
