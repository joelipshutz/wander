import { handleRequest } from "./index.ts";

const vector = Array.from({ length: 1536 }, (_, index) => index === 0 ? 1 : 0);
const env = (name: string) => ({
  OPENAI_API_KEY: "openai-key",
  SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_ANON_KEY: "publishable-key",
}[name]);

Deno.test("semantic search requires a validated caller", async () => {
  const missing = await handleRequest(new Request("https://example.test", { method: "POST" }));
  assertEquals(missing.status, 401);

  const invalid = await handleRequest(
    request({ query: "quiet coffee" }),
    { validateAuthorization: async () => false },
  );
  assertEquals(invalid.status, 401);
});

Deno.test("semantic search embeds only the submitted query and forwards hard filters", async () => {
  const calls: Array<{ url: string; body: Record<string, unknown> }> = [];
  const response = await handleRequest(
    request({
      query: "  quiet   coffee for a rainy afternoon  ",
      categories: ["coffee_tea_sweets"],
      area: "Los Angeles",
      favorite_only: true,
      scope: "friends",
      limit: 99,
    }),
    {
      env,
      validateAuthorization: async () => true,
      fetcher: async (input, init) => {
        const url = String(input);
        const body = JSON.parse(String(init?.body ?? "{}"));
        calls.push({ url, body });
        if (url.endsWith("/v1/embeddings")) {
          return Response.json({ data: [{ index: 0, embedding: vector }] });
        }
        if (url.endsWith("/rest/v1/rpc/search_recme_places_semantic")) {
          return Response.json([{
            id: "place-1",
            canonical_name: "Quiet Coffee",
            category: "coffee_tea_sweets",
            semantic_similarity: 0.81,
          }]);
        }
        throw new Error(`unexpected_url_${url}`);
      },
    },
  );

  assertEquals(response.status, 200);
  const result = await response.json();
  assertEquals(result, {
    candidates: [{
      id: "place-1",
      canonical_name: "Quiet Coffee",
      category: "coffee_tea_sweets",
    }],
    provider: "semantic_v1",
  });
  assertEquals(calls.length, 2);
  assertEquals(calls[0].body, {
    model: "text-embedding-3-small",
    input: "quiet coffee for a rainy afternoon",
    encoding_format: "float",
  });
  assertEquals(calls[1].body.input_categories, ["coffee_tea_sweets"]);
  assertEquals(calls[1].body.input_area, "Los Angeles");
  assertEquals(calls[1].body.input_favorite_only, true);
  assertEquals(calls[1].body.input_scope, "friends");
  assertEquals(calls[1].body.input_limit, 20);
  assertEquals(calls[1].body.input_min_similarity, 0.35);
  assertEquals(typeof calls[1].body.input_embedding, "string");
});

Deno.test("semantic search fails closed on a malformed embedding", async () => {
  await assertRejects(() =>
    handleRequest(request({ query: "quiet coffee" }), {
      env,
      validateAuthorization: async () => true,
      fetcher: async () => Response.json({ data: [{ index: 0, embedding: [1, 2] }] }),
    })
  );
});

Deno.test("semantic search treats an empty query as an honest empty provider", async () => {
  let fetchCount = 0;
  const response = await handleRequest(request({ query: "  " }), {
    validateAuthorization: async () => true,
    fetcher: async () => {
      fetchCount += 1;
      return Response.json({});
    },
  });
  assertEquals(await response.json(), { candidates: [], provider: "semantic_v1" });
  assertEquals(fetchCount, 0);
});

function request(body: Record<string, unknown>): Request {
  return new Request("https://example.test", {
    method: "POST",
    headers: {
      Authorization: "Bearer user-token",
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

async function assertRejects(operation: () => Promise<unknown>): Promise<void> {
  try {
    await operation();
  } catch {
    return;
  }
  throw new Error("Expected operation to reject");
}
