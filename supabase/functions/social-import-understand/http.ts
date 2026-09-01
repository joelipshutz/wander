import type { RuntimeDependencies } from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

export async function fetchJSON(
  url: string,
  init: RequestInit,
  maximumResponseBytes: number,
  timeoutMilliseconds: number,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
): Promise<{ response: Response; body: unknown }> {
  const timeoutSignal = AbortSignal.timeout(
    deadline.remaining(timeoutMilliseconds),
  );
  const signal = init.signal
    ? AbortSignal.any([init.signal, timeoutSignal])
    : timeoutSignal;
  const response = await dependencies.fetch(url, {
    ...init,
    signal,
  });
  const text = await boundedResponseText(response, maximumResponseBytes);
  if (!text.trim()) return { response, body: {} };
  try {
    return { response, body: JSON.parse(text) };
  } catch {
    // Error pages are not guaranteed to be JSON. Preserve the HTTP status so
    // callers can apply the provider's retry policy without retaining details.
    if (!response.ok) return { response, body: {} };
    throw new SocialImportError("invalid_json_response");
  }
}

export async function boundedRequestBody(
  request: Request,
  maximumBytes: number,
): Promise<unknown> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new SocialImportError("request_too_large");
  }
  if (!request.body) return {};
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let count = 0;
  let text = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    count += value.byteLength;
    if (count > maximumBytes) {
      await reader.cancel().catch(() => undefined);
      throw new SocialImportError("request_too_large");
    }
    text += decoder.decode(value, { stream: true });
  }
  text += decoder.decode();
  if (!text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new SocialImportError("invalid_request_json");
  }
}

async function boundedResponseText(
  response: Response,
  maximumBytes: number,
): Promise<string> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    await response.body?.cancel().catch(() => undefined);
    throw new SocialImportError("provider_response_too_large");
  }
  if (!response.body) return "";
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let count = 0;
  let output = "";
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    count += value.byteLength;
    if (count > maximumBytes) {
      await reader.cancel().catch(() => undefined);
      throw new SocialImportError("provider_response_too_large");
    }
    output += decoder.decode(value, { stream: true });
  }
  output += decoder.decode();
  return output;
}
