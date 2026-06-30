import { anthropicJSON } from "./providers/anthropic.ts";
import { openAIJSON } from "./providers/openai.ts";
import { openAICompatibleJSON } from "./providers/openai-compatible.ts";
import { AIProviderCallError } from "./types.ts";
import type {
  AIProviderName,
  EnvReader,
  Fetcher,
  ProviderJSONRequest,
  StructuredJSONErrorCode,
  StructuredJSONRequest,
  StructuredJSONResult,
} from "./types.ts";

const defaultEnv: EnvReader = {
  get(name: string): string | undefined {
    return Deno.env.get(name) ?? undefined;
  },
};

export function configuredAIProviderName(
  env: EnvReader = defaultEnv,
): AIProviderName | "unsupported" {
  return normalizeProvider(
    firstNonEmpty([env.get("WANDER_AI_PROVIDER")]) ?? "openai",
  ) ?? "unsupported";
}

export async function structuredJSON<T>(
  request: StructuredJSONRequest<T>,
): Promise<StructuredJSONResult<T>> {
  const started = Date.now();
  const env = request.env ?? defaultEnv;
  const provider = configuredAIProviderName(env);

  if (provider === "unsupported") {
    return failure(
      "unsupported_provider",
      provider,
      null,
      started,
      false,
      "unsupported_ai_provider",
    );
  }

  const model = modelForProvider(provider, request, env);
  if (!model) {
    return failure(
      "model_unavailable",
      provider,
      null,
      started,
      false,
      "missing_ai_model",
    );
  }

  const apiKey = apiKeyForProvider(provider, env);
  const baseURL = baseURLForProvider(provider, env);
  const timeoutMS = timeoutMSForRequest(request, env);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMS);
  const fetcher = request.fetcher ?? (fetch as Fetcher);

  try {
    const rawText = await providerCall(provider, {
      apiKey,
      baseURL,
      model,
      schemaName: request.schemaName,
      schema: request.schema,
      system: request.system,
      user: request.user,
      maxOutputTokens: request.maxOutputTokens,
      signal: controller.signal,
      fetcher,
    });

    let parsed: unknown;
    try {
      parsed = JSON.parse(rawText);
    } catch {
      return failure(
        "invalid_json",
        provider,
        model,
        started,
        false,
        "invalid_ai_json",
      );
    }

    const value = request.validate(parsed);
    if (!value) {
      return failure(
        "invalid_output",
        provider,
        model,
        started,
        false,
        "invalid_ai_output",
      );
    }

    return {
      ok: true,
      value,
      provider,
      model,
      latencyMS: elapsedMS(started),
    };
  } catch (error) {
    const code = errorCode(error);
    return failure(
      code,
      provider,
      model,
      started,
      retryable(error, code),
      errorMessage(error),
    );
  } finally {
    clearTimeout(timeout);
  }
}

function providerCall(
  provider: AIProviderName,
  request: ProviderJSONRequest,
): Promise<string> {
  switch (provider) {
    case "anthropic":
      return anthropicJSON(request);
    case "openai-compatible":
      return openAICompatibleJSON(request);
    case "openai":
      return openAIJSON(request);
  }
}

function modelForProvider<T>(
  provider: AIProviderName,
  request: StructuredJSONRequest<T>,
  env: EnvReader,
): string | null {
  const configured = firstNonEmpty([
    ...(request.modelEnvKeys ?? []).map((key) => env.get(key)),
    env.get("WANDER_AI_MODEL"),
    ...(provider === "openai"
      ? (request.legacyOpenAIModelEnvKeys ?? []).map((key) => env.get(key))
      : []),
  ]);
  return configured ?? request.defaultModels?.[provider] ?? null;
}

function apiKeyForProvider(
  provider: AIProviderName,
  env: EnvReader,
): string | null {
  switch (provider) {
    case "anthropic":
      return firstNonEmpty([
        env.get("WANDER_AI_API_KEY"),
        env.get("ANTHROPIC_API_KEY"),
        env.get("WANDER_ANTHROPIC_API_KEY"),
      ]);
    case "openai-compatible":
      return firstNonEmpty([
        env.get("WANDER_AI_API_KEY"),
        env.get("WANDER_OPENAI_COMPATIBLE_API_KEY"),
        env.get("OPENAI_API_KEY"),
        env.get("WANDER_OPENAI_API_KEY"),
      ]);
    case "openai":
      return firstNonEmpty([
        env.get("WANDER_AI_API_KEY"),
        env.get("OPENAI_API_KEY"),
        env.get("WANDER_OPENAI_API_KEY"),
      ]);
  }
}

function baseURLForProvider(
  provider: AIProviderName,
  env: EnvReader,
): string | null {
  switch (provider) {
    case "anthropic":
      return firstNonEmpty([
        env.get("WANDER_AI_BASE_URL"),
        env.get("ANTHROPIC_BASE_URL"),
        env.get("WANDER_ANTHROPIC_BASE_URL"),
      ]);
    case "openai-compatible":
      return firstNonEmpty([
        env.get("WANDER_AI_BASE_URL"),
        env.get("WANDER_OPENAI_COMPATIBLE_BASE_URL"),
      ]);
    case "openai":
      return firstNonEmpty([
        env.get("WANDER_AI_BASE_URL"),
        env.get("OPENAI_BASE_URL"),
        env.get("WANDER_OPENAI_BASE_URL"),
      ]);
  }
}

function timeoutMSForRequest<T>(
  request: StructuredJSONRequest<T>,
  env: EnvReader,
): number {
  const configured = firstNonEmpty([
    ...(request.timeoutEnvKeys ?? []).map((key) => env.get(key)),
    env.get("WANDER_AI_TIMEOUT_MS"),
  ]);
  const value = Number(configured);
  if (Number.isFinite(value) && value > 0) {
    return Math.min(value, 10_000);
  }
  return request.defaultTimeoutMS ?? 3_500;
}

function normalizeProvider(value: string): AIProviderName | null {
  const normalized = value.trim().toLowerCase().replaceAll("_", "-");
  if (
    normalized === "openai" || normalized === "anthropic" ||
    normalized === "openai-compatible"
  ) {
    return normalized;
  }
  return null;
}

function errorCode(error: unknown): StructuredJSONErrorCode {
  if (error instanceof AIProviderCallError) return error.code;
  if (error instanceof DOMException && error.name === "AbortError") {
    return "timeout";
  }
  return "request_failed";
}

function retryable(error: unknown, code: StructuredJSONErrorCode): boolean {
  if (error instanceof AIProviderCallError) return error.retryable;
  return code === "request_failed" || code === "timeout";
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "unknown_ai_error";
}

function failure(
  errorCode: StructuredJSONErrorCode,
  provider: AIProviderName | "unsupported",
  model: string | null,
  started: number,
  retryable: boolean,
  message: string,
): StructuredJSONResult<never> {
  return {
    ok: false,
    errorCode,
    provider,
    model,
    latencyMS: elapsedMS(started),
    retryable,
    message,
  };
}

function elapsedMS(started: number): number {
  return Math.max(0, Date.now() - started);
}

function firstNonEmpty(
  values: Array<string | undefined | null>,
): string | null {
  for (const value of values) {
    const trimmed = value?.trim();
    if (trimmed) return trimmed;
  }
  return null;
}
