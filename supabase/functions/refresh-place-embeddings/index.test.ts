import { handleRequest } from "./index.ts";

const vector = Array.from({ length: 1536 }, (_, index) => index === 0 ? 1 : 0);
const env = (name: string) => ({
  WANDER_WORKER_SECRET: "worker-secret",
  OPENAI_API_KEY: "openai-key",
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "service-key",
}[name]);

Deno.test("embedding refresh rejects missing or incorrect worker secrets", async () => {
  const missing = await handleRequest(new Request("https://example.test", { method: "POST" }), { env });
  assertEquals(missing.status, 401);

  const incorrect = await handleRequest(request("wrong-secret"), { env });
  assertEquals(incorrect.status, 401);
});

Deno.test("embedding refresh sends minimized documents and upserts versioned vectors", async () => {
  const calls: Array<{ url: string; body: unknown }> = [];
  const candidates = [
    {
      place_id: "place-1",
      document: "Quiet Coffee | coffee_tea_sweets | coffee_shop | Los Angeles | CA",
      document_hash: "a".repeat(64),
    },
    {
      place_id: "place-2",
      document: "Trail Park | outdoors_nature | park | Malibu | CA",
      document_hash: "b".repeat(64),
    },
  ];

  const response = await handleRequest(request("worker-secret", { limit: 999 }), {
    env,
    fetcher: async (input, init) => {
      const url = String(input);
      const body = JSON.parse(String(init?.body ?? "{}"));
      calls.push({ url, body });
      if (url.endsWith("/rest/v1/rpc/semantic_place_embedding_backfill_batch")) {
        return Response.json(candidates);
      }
      if (url.endsWith("/v1/embeddings")) {
        return Response.json({
          data: [
            { index: 1, embedding: vector },
            { index: 0, embedding: vector },
          ],
        });
      }
      if (url.includes("/rest/v1/place_search_embeddings?")) {
        return new Response(null, { status: 201 });
      }
      throw new Error(`unexpected_url_${url}`);
    },
  });

  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    processed: 2,
    remaining: false,
    model: "text-embedding-3-small",
  });
  assertEquals(calls[0].body, {
    input_model: "text-embedding-3-small",
    input_document_version: 1,
    input_limit: 100,
  });
  assertEquals((calls[1].body as Record<string, unknown>).input, candidates.map((row) => row.document));
  const upserts = calls[2].body as Array<Record<string, unknown>>;
  assertEquals(upserts.map((row) => ({
    place_id: row.place_id,
    model: row.model,
    dimensions: row.dimensions,
    document_version: row.document_version,
    document_hash: row.document_hash,
  })), candidates.map((candidate) => ({
    place_id: candidate.place_id,
    model: "text-embedding-3-small",
    dimensions: 1536,
    document_version: 1,
    document_hash: candidate.document_hash,
  })));
});

Deno.test("embedding refresh skips OpenAI when no documents are stale", async () => {
  let fetchCount = 0;
  const response = await handleRequest(request("worker-secret"), {
    env,
    fetcher: async () => {
      fetchCount += 1;
      return Response.json([]);
    },
  });
  assertEquals(await response.json(), {
    processed: 0,
    remaining: false,
    model: "text-embedding-3-small",
  });
  assertEquals(fetchCount, 1);
});

function request(secret: string, body: Record<string, unknown> = {}): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: {
      "x-wander-worker-secret": secret,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`);
  }
}
