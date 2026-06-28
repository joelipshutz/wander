import { AIProviderCallError } from "../types.ts";
import type { ProviderJSONRequest } from "../types.ts";

const defaultBaseURL = "https://api.anthropic.com/v1";

export async function anthropicJSON(
  request: ProviderJSONRequest,
): Promise<string> {
  if (!request.apiKey) {
    throw new AIProviderCallError(
      "provider_unavailable",
      "missing_anthropic_api_key",
    );
  }

  const response = await request.fetcher(messagesEndpoint(request.baseURL), {
    method: "POST",
    signal: request.signal,
    headers: {
      "Content-Type": "application/json",
      "anthropic-version": "2023-06-01",
      "x-api-key": request.apiKey,
    },
    body: JSON.stringify({
      model: request.model,
      max_tokens: request.maxOutputTokens,
      system: request.system,
      messages: [
        { role: "user", content: JSON.stringify(request.user) },
      ],
      tools: [
        {
          name: request.schemaName,
          description: "Return the structured JSON for this Rec.me task.",
          input_schema: request.schema,
        },
      ],
      tool_choice: {
        type: "tool",
        name: request.schemaName,
      },
    }),
  });

  if (!response.ok) {
    throw new AIProviderCallError(
      "request_failed",
      `anthropic_status_${response.status}`,
      true,
    );
  }

  return anthropicOutputText(await response.json());
}

function anthropicOutputText(body: unknown): string {
  const content = body && typeof body === "object" && "content" in body &&
      Array.isArray(body.content)
    ? body.content
    : [];

  for (const item of content) {
    if (
      item && typeof item === "object" && "type" in item &&
      item.type === "tool_use" && "input" in item
    ) {
      return JSON.stringify(item.input);
    }
  }

  for (const item of content) {
    if (
      item && typeof item === "object" && "type" in item &&
      item.type === "text" && "text" in item && typeof item.text === "string"
    ) {
      const text = item.text.trim();
      if (text) return text;
    }
  }

  throw new AIProviderCallError("missing_output", "anthropic_missing_output");
}

function messagesEndpoint(baseURL: string | null): string {
  const base = (baseURL?.trim() || defaultBaseURL).replace(/\/+$/, "");
  return base.endsWith("/messages") ? base : `${base}/messages`;
}
