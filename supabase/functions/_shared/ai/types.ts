export type AIProviderName = "openai" | "anthropic" | "openai-compatible";

export type AIJSONSchema = Record<string, unknown>;

export type EnvReader = {
  get(name: string): string | undefined | null;
};

export type Fetcher = (
  input: string | URL | Request,
  init?: RequestInit,
) => Promise<Response>;

export type StructuredJSONErrorCode =
  | "invalid_json"
  | "invalid_output"
  | "missing_output"
  | "model_unavailable"
  | "provider_unavailable"
  | "request_failed"
  | "timeout"
  | "unsupported_provider";

export type StructuredJSONRequest<T> = {
  task: string;
  schemaName: string;
  schema: AIJSONSchema;
  system: string;
  user: unknown;
  maxOutputTokens: number;
  validate: (value: unknown) => T | null;
  modelEnvKeys?: string[];
  legacyOpenAIModelEnvKeys?: string[];
  timeoutEnvKeys?: string[];
  defaultTimeoutMS?: number;
  defaultModels?: Partial<Record<AIProviderName, string>>;
  env?: EnvReader;
  fetcher?: Fetcher;
};

export type StructuredJSONSuccess<T> = {
  ok: true;
  value: T;
  provider: AIProviderName;
  model: string;
  latencyMS: number;
};

export type StructuredJSONFailure = {
  ok: false;
  errorCode: StructuredJSONErrorCode;
  provider: AIProviderName | "unsupported";
  model: string | null;
  latencyMS: number;
  retryable: boolean;
  message: string;
};

export type StructuredJSONResult<T> =
  | StructuredJSONSuccess<T>
  | StructuredJSONFailure;

export type ProviderJSONRequest = {
  apiKey: string | null;
  baseURL: string | null;
  model: string;
  schemaName: string;
  schema: AIJSONSchema;
  system: string;
  user: unknown;
  maxOutputTokens: number;
  signal: AbortSignal;
  fetcher: Fetcher;
};

export class AIProviderCallError extends Error {
  readonly code: StructuredJSONErrorCode;
  readonly retryable: boolean;

  constructor(
    code: StructuredJSONErrorCode,
    message: string,
    retryable = false,
  ) {
    super(message);
    this.name = "AIProviderCallError";
    this.code = code;
    this.retryable = retryable;
  }
}
