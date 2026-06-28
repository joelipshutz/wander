import { AIProviderCallError } from "../types.ts";
import type { ProviderJSONRequest } from "../types.ts";

export async function openAICompatibleJSON(
  request: ProviderJSONRequest,
): Promise<string> {
  if (!request.baseURL?.trim()) {
    throw new AIProviderCallError(
      "provider_unavailable",
      "missing_openai_compatible_base_url",
    );
  }

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (request.apiKey) {
    headers.Authorization = `Bearer ${request.apiKey}`;
  }

  const response = await request.fetcher(
    chatCompletionsEndpoint(request.baseURL),
    {
      method: "POST",
      signal: request.signal,
      headers,
      body: JSON.stringify({
        model: request.model,
        max_tokens: request.maxOutputTokens,
        messages: [
          { role: "system", content: request.system },
          { role: "user", content: JSON.stringify(request.user) },
        ],
        response_format: {
          type: "json_schema",
          json_schema: {
            name: request.schemaName,
            strict: true,
            schema: request.schema,
          },
        },
      }),
    },
  );

  if (!response.ok) {
    throw new AIProviderCallError(
      "request_failed",
      `openai_compatible_status_${response.status}`,
      true,
    );
  }

  return openAICompatibleOutputText(await response.json());
}

function openAICompatibleOutputText(body: unknown): string {
  if (
    !body || typeof body !== "object" || !("choices" in body) ||
    !Array.isArray(body.choices)
  ) {
    throw new AIProviderCallError(
      "missing_output",
      "openai_compatible_missing_choices",
    );
  }

  for (const choice of body.choices) {
    if (
      choice &&
      typeof choice === "object" &&
      "message" in choice &&
      choice.message &&
      typeof choice.message === "object" &&
      "content" in choice.message &&
      typeof choice.message.content === "string"
    ) {
      const content = choice.message.content.trim();
      if (content) return content;
    }
  }

  throw new AIProviderCallError(
    "missing_output",
    "openai_compatible_missing_output",
  );
}

function chatCompletionsEndpoint(baseURL: string): string {
  const base = baseURL.trim().replace(/\/+$/, "");
  return base.endsWith("/chat/completions") ? base : `${base}/chat/completions`;
}
