import { AIProviderCallError } from "../types.ts";
import type { ProviderJSONRequest } from "../types.ts";

const defaultBaseURL = "https://api.openai.com/v1";

export async function openAIJSON(
  request: ProviderJSONRequest,
): Promise<string> {
  if (!request.apiKey) {
    throw new AIProviderCallError(
      "provider_unavailable",
      "missing_openai_api_key",
    );
  }

  const response = await request.fetcher(responsesEndpoint(request.baseURL), {
    method: "POST",
    signal: request.signal,
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${request.apiKey}`,
    },
    body: JSON.stringify({
      model: request.model,
      store: false,
      max_output_tokens: request.maxOutputTokens,
      input: [
        { role: "system", content: request.system },
        { role: "user", content: JSON.stringify(request.user) },
      ],
      text: {
        format: {
          type: "json_schema",
          name: request.schemaName,
          strict: true,
          schema: request.schema,
        },
      },
    }),
  });

  if (!response.ok) {
    throw new AIProviderCallError(
      "request_failed",
      `openai_status_${response.status}`,
      true,
    );
  }

  return openAIOutputText(await response.json());
}

export function openAIOutputText(body: unknown): string {
  if (
    body && typeof body === "object" && "output_text" in body &&
    typeof body.output_text === "string"
  ) {
    const direct = body.output_text.trim();
    if (direct) return direct;
  }

  if (
    !body || typeof body !== "object" || !("output" in body) ||
    !Array.isArray(body.output)
  ) {
    throw new AIProviderCallError("missing_output", "openai_missing_output");
  }

  const parts: string[] = [];
  for (const item of body.output) {
    if (
      !item || typeof item !== "object" || !("content" in item) ||
      !Array.isArray(item.content)
    ) {
      continue;
    }

    for (const content of item.content) {
      if (
        content &&
        typeof content === "object" &&
        "type" in content &&
        content.type === "output_text" &&
        "text" in content &&
        typeof content.text === "string"
      ) {
        parts.push(content.text);
      }
    }
  }

  const text = parts.join("").trim();
  if (!text) {
    throw new AIProviderCallError("missing_output", "openai_missing_output");
  }
  return text;
}

function responsesEndpoint(baseURL: string | null): string {
  const base = (baseURL?.trim() || defaultBaseURL).replace(/\/+$/, "");
  return base.endsWith("/responses") ? base : `${base}/responses`;
}
