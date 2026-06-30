import { structuredJSON } from "./structured-json.ts";
import type { EnvReader, Fetcher } from "./types.ts";

Deno.test("structuredJSON calls OpenAI Responses with schema, store false, and task model", async () => {
  let capturedURL = "";
  let capturedHeaders: Headers | null = null;
  let capturedBody: Record<string, unknown> | null = null;

  const result = await structuredJSON({
    task: "test_task",
    schemaName: "test_schema",
    schema: {
      type: "object",
      properties: { category: { type: "string" } },
      required: ["category"],
      additionalProperties: false,
    },
    system: "Return JSON only.",
    user: { name: "Dayglow Coffee" },
    maxOutputTokens: 80,
    modelEnvKeys: ["WANDER_AI_CATEGORY_MODEL"],
    defaultModels: { openai: "fallback-model" },
    env: envReader({
      WANDER_AI_PROVIDER: "openai",
      OPENAI_API_KEY: "test-openai-key",
      WANDER_AI_CATEGORY_MODEL: "gpt-test",
    }),
    fetcher: (async (input, init) => {
      capturedURL = String(input);
      capturedHeaders = new Headers(init?.headers);
      capturedBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({
        output_text: JSON.stringify({ category: "coffee" }),
      });
    }) as Fetcher,
    validate: (value) => {
      if (
        !value || typeof value !== "object" || !("category" in value) ||
        value.category !== "coffee"
      ) return null;
      return { category: value.category };
    },
  });

  assert(result.ok);
  const headers = capturedHeaders as unknown as Headers;
  const body = capturedBody as unknown as Record<string, unknown>;
  assertEquals(result.provider, "openai");
  assertEquals(result.model, "gpt-test");
  assertEquals(capturedURL, "https://api.openai.com/v1/responses");
  assertEquals(headers.get("authorization"), "Bearer test-openai-key");
  assertEquals(body.model, "gpt-test");
  assertEquals(body.store, false);
  assertEquals(body.max_output_tokens, 80);
  assertEquals(
    ((body.text as Record<string, unknown>).format as Record<string, unknown>)
      .type,
    "json_schema",
  );
});

Deno.test("structuredJSON keeps legacy OpenAI model env only for OpenAI", async () => {
  const openAIResult = await structuredJSON({
    task: "test_task",
    schemaName: "test_schema",
    schema: { type: "object", properties: {}, additionalProperties: false },
    system: "Return JSON only.",
    user: {},
    maxOutputTokens: 16,
    legacyOpenAIModelEnvKeys: ["WANDER_OPENAI_DISCOVER_MODEL"],
    defaultModels: { openai: "fallback-openai" },
    env: envReader({
      WANDER_AI_PROVIDER: "openai",
      OPENAI_API_KEY: "test-key",
      WANDER_OPENAI_DISCOVER_MODEL: "legacy-openai-model",
    }),
    fetcher: okJSONFetcher({}),
    validate: () => ({}),
  });

  assert(openAIResult.ok);
  assertEquals(openAIResult.model, "legacy-openai-model");

  const anthropicResult = await structuredJSON({
    task: "test_task",
    schemaName: "test_schema",
    schema: { type: "object", properties: {}, additionalProperties: false },
    system: "Return JSON only.",
    user: {},
    maxOutputTokens: 16,
    legacyOpenAIModelEnvKeys: ["WANDER_OPENAI_DISCOVER_MODEL"],
    env: envReader({
      WANDER_AI_PROVIDER: "anthropic",
      ANTHROPIC_API_KEY: "test-key",
      WANDER_OPENAI_DISCOVER_MODEL: "legacy-openai-model",
    }),
    fetcher: okAnthropicFetcher({}),
    validate: () => ({}),
  });

  assert(!anthropicResult.ok);
  assertEquals(anthropicResult.errorCode, "model_unavailable");
});

Deno.test("structuredJSON maps Anthropic tool-use input through the same validator", async () => {
  let capturedURL = "";
  let capturedHeaders: Headers | null = null;
  let capturedBody: Record<string, unknown> | null = null;

  const result = await structuredJSON({
    task: "test_task",
    schemaName: "recme_test_schema",
    schema: {
      type: "object",
      properties: { category: { type: "string" } },
      required: ["category"],
      additionalProperties: false,
    },
    system: "Return JSON only.",
    user: { name: "Maru Coffee" },
    maxOutputTokens: 80,
    modelEnvKeys: ["WANDER_AI_CATEGORY_MODEL"],
    env: envReader({
      WANDER_AI_PROVIDER: "anthropic",
      ANTHROPIC_API_KEY: "test-anthropic-key",
      WANDER_AI_CATEGORY_MODEL: "claude-test",
    }),
    fetcher: (async (input, init) => {
      capturedURL = String(input);
      capturedHeaders = new Headers(init?.headers);
      capturedBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Response.json({
        content: [
          {
            type: "tool_use",
            name: "recme_test_schema",
            input: { category: "coffee" },
          },
        ],
      });
    }) as Fetcher,
    validate: (value) => {
      if (
        !value || typeof value !== "object" || !("category" in value) ||
        value.category !== "coffee"
      ) return null;
      return { category: value.category };
    },
  });

  assert(result.ok);
  const headers = capturedHeaders as unknown as Headers;
  const body = capturedBody as unknown as Record<string, unknown>;
  assertEquals(result.provider, "anthropic");
  assertEquals(result.model, "claude-test");
  assertEquals(capturedURL, "https://api.anthropic.com/v1/messages");
  assertEquals(headers.get("x-api-key"), "test-anthropic-key");
  assertEquals(body.model, "claude-test");
  assertEquals(
    (body.tool_choice as Record<string, unknown>).name,
    "recme_test_schema",
  );
});

Deno.test("structuredJSON supports OpenAI-compatible endpoints without requiring an API key", async () => {
  let capturedURL = "";
  let capturedHeaders: Headers | null = null;

  const result = await structuredJSON({
    task: "test_task",
    schemaName: "test_schema",
    schema: {
      type: "object",
      properties: { category: { type: "string" } },
      required: ["category"],
      additionalProperties: false,
    },
    system: "Return JSON only.",
    user: { name: "Local Cafe" },
    maxOutputTokens: 64,
    modelEnvKeys: ["WANDER_AI_CATEGORY_MODEL"],
    env: envReader({
      WANDER_AI_PROVIDER: "openai-compatible",
      WANDER_AI_BASE_URL: "http://127.0.0.1:11434/v1",
      WANDER_AI_CATEGORY_MODEL: "local-json-model",
    }),
    fetcher: (async (input, init) => {
      capturedURL = String(input);
      capturedHeaders = new Headers(init?.headers);
      return Response.json({
        choices: [
          { message: { content: JSON.stringify({ category: "coffee" }) } },
        ],
      });
    }) as Fetcher,
    validate: (value) => {
      if (
        !value || typeof value !== "object" || !("category" in value) ||
        value.category !== "coffee"
      ) return null;
      return { category: value.category };
    },
  });

  assert(result.ok);
  const headers = capturedHeaders as unknown as Headers;
  assertEquals(result.provider, "openai-compatible");
  assertEquals(result.model, "local-json-model");
  assertEquals(capturedURL, "http://127.0.0.1:11434/v1/chat/completions");
  assertEquals(headers.get("authorization"), null);
});

Deno.test("structuredJSON returns typed failures for missing key and invalid output", async () => {
  const noKey = await structuredJSON({
    task: "test_task",
    schemaName: "test_schema",
    schema: { type: "object", properties: {}, additionalProperties: false },
    system: "Return JSON only.",
    user: {},
    maxOutputTokens: 16,
    defaultModels: { openai: "gpt-test" },
    env: envReader({ WANDER_AI_PROVIDER: "openai" }),
    fetcher: okJSONFetcher({}),
    validate: () => ({}),
  });

  assert(!noKey.ok);
  assertEquals(noKey.provider, "openai");
  assertEquals(noKey.errorCode, "provider_unavailable");

  const invalid = await structuredJSON({
    task: "test_task",
    schemaName: "test_schema",
    schema: { type: "object", properties: {}, additionalProperties: false },
    system: "Return JSON only.",
    user: {},
    maxOutputTokens: 16,
    defaultModels: { openai: "gpt-test" },
    env: envReader({
      WANDER_AI_PROVIDER: "openai",
      OPENAI_API_KEY: "test-key",
    }),
    fetcher: okJSONFetcher({ unexpected: true }),
    validate: (value) => {
      if (!value || typeof value !== "object" || !("expected" in value)) {
        return null;
      }
      return value as { expected: true };
    },
  });

  assert(!invalid.ok);
  assertEquals(invalid.errorCode, "invalid_output");
});

function envReader(values: Record<string, string>): EnvReader {
  return {
    get(name: string): string | undefined {
      return values[name];
    },
  };
}

function okJSONFetcher(value: unknown): Fetcher {
  return (async () =>
    Response.json({ output_text: JSON.stringify(value) })) as Fetcher;
}

function okAnthropicFetcher(value: unknown): Fetcher {
  return (async () =>
    Response.json({
      content: [
        {
          type: "tool_use",
          input: value,
        },
      ],
    })) as Fetcher;
}

function assert(
  condition: unknown,
  message = "assertion failed",
): asserts condition {
  if (!condition) throw new Error(message);
}

function assertEquals(actual: unknown, expected: unknown): void {
  if (actual !== expected) {
    throw new Error(
      `expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}
