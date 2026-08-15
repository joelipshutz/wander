import "@supabase/functions-js/edge-runtime.d.ts";

export type PushToken = {
  id: string;
  device_token: string;
  environment: "sandbox" | "production";
  app_bundle_id: string;
};

export type PushEvent = {
  event_id: string;
  claim_token: string;
  recipient_user_id: string;
  actor_user_id?: string | null;
  notification_type: string;
  title: string;
  body: string;
  deeplink_url?: string | null;
  data: Record<string, unknown>;
  attempt_count?: number;
  max_attempts?: number;
  claim_expires_at?: string | null;
  tokens: PushToken[];
};

type APNsConfig = {
  keyId: string;
  teamId: string;
  privateKeyPEM: string;
  defaultTopic?: string | null;
};

export type DeliveryStatus =
  | "accepted"
  | "retryable_failure"
  | "permanent_token_failure"
  | "permanent_event_failure";

export type TokenSendResult = {
  token_id: string;
  status: DeliveryStatus;
  http_status?: number | null;
  apns_reason?: string | null;
  error_message?: string | null;
  apns_id?: string | null;
};

type DeliverySettlement = {
  status: "sent" | "failed" | "pending" | "skipped" | "stale_claim";
  accepted_count?: number;
  retryable_count?: number;
  permanent_token_failure_count?: number;
  permanent_event_failure_count?: number;
};

type ProcessedEvent = {
  event_id: string;
  status: "sent" | "failed" | "skipped" | "retrying";
  accepted_count?: number;
  failed_count?: number;
  deactivated_token_count?: number;
  reason?: string;
  error?: string;
};

const jsonHeaders = { "Content-Type": "application/json" };
const requestTimeoutMilliseconds = 5_000;

if (import.meta.main) {
  Deno.serve(async (req) => {
    try {
      return await handleRequest(req);
    } catch (error) {
      console.error(
        "push_notification_worker_error",
        error instanceof Error ? error.message : "unknown_error",
      );
      return Response.json({ error: "internal_error" }, { status: 500 });
    }
  });
}

export async function handleRequest(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }

  if (!isAuthorizedWorker(req)) {
    return Response.json({ error: "missing_worker_secret" }, { status: 401 });
  }

  const body = await readBody(req);
  const limit = Math.min(Math.max(Number(body.limit ?? 10) || 10, 1), 20);
  const events = await serviceRpc<PushEvent[]>(
    "claim_pending_push_notifications",
    { input_limit: limit },
  );

  const config = apnsConfig();
  const jwt = config ? await apnsJWT(config) : null;
  const processed = await Promise.all(
    events.map((event) => processEvent(event, config, jwt)),
  );

  return Response.json({
    claimed_count: events.length,
    summary: processingSummary(processed),
    processed,
  });
}

async function processEvent(
  event: PushEvent,
  config: APNsConfig | null,
  jwt: string | null,
): Promise<ProcessedEvent> {
  const results = config && jwt
    ? await Promise.all(
      event.tokens.map((token) => sendToToken(event, token, config, jwt)),
    )
    : event.tokens.map((token) => ({
      token_id: token.id,
      status: "permanent_event_failure" as const,
      error_message: "apns_not_configured",
    }));
  const settlement = await serviceRpc<DeliverySettlement>(
    "record_push_notification_delivery_results",
    {
      input_event_id: event.event_id,
      input_claim_token: event.claim_token,
      input_results: results,
    },
  );
  const acceptedCount =
    results.filter((result) => result.status === "accepted").length;
  const permanentTokenFailureCount = results.filter(
    (result) => result.status === "permanent_token_failure",
  ).length;
  const failedCount = results.length - acceptedCount;
  const status = settlement.status === "pending"
    ? "retrying"
    : settlement.status === "stale_claim"
    ? "skipped"
    : settlement.status;

  return {
    event_id: event.event_id,
    status,
    accepted_count: acceptedCount,
    failed_count: failedCount,
    deactivated_token_count: permanentTokenFailureCount,
    reason: settlement.status === "stale_claim" ? "stale_claim" : undefined,
    error: results
      .filter((result) => result.status !== "accepted")
      .map((result) => result.error_message)
      .filter(Boolean)
      .join("; ") || undefined,
  };
}

function processingSummary(
  processed: ProcessedEvent[],
): Record<string, number> {
  return processed.reduce(
    (summary, event) => {
      summary[event.status] += 1;
      summary.accepted_tokens += event.accepted_count ?? 0;
      summary.failed_tokens += event.failed_count ?? 0;
      summary.deactivated_tokens += event.deactivated_token_count ?? 0;
      return summary;
    },
    {
      sent: 0,
      failed: 0,
      skipped: 0,
      retrying: 0,
      accepted_tokens: 0,
      failed_tokens: 0,
      deactivated_tokens: 0,
    },
  );
}

export async function sendToToken(
  event: PushEvent,
  token: PushToken,
  config: APNsConfig,
  jwt: string,
  fetcher: typeof fetch = fetch,
  apnsID: string = crypto.randomUUID(),
): Promise<TokenSendResult> {
  const topic = config.defaultTopic || token.app_bundle_id;
  const host = token.environment === "sandbox"
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  const payload = {
    aps: {
      alert: { title: event.title, body: event.body },
      sound: "default",
    },
    recme: {
      notification_type: event.notification_type,
      event_id: event.event_id,
      deeplink_url: event.deeplink_url ?? null,
      data: event.data,
    },
  };

  try {
    const response = await fetcher(
      `https://${host}/3/device/${token.device_token}`,
      {
        method: "POST",
        headers: {
          ...jsonHeaders,
          authorization: `bearer ${jwt}`,
          "apns-topic": topic,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "apns-collapse-id": event.event_id,
          "apns-id": apnsID,
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(requestTimeoutMilliseconds),
      },
    );
    const responseAPNsID = response.headers.get("apns-id") ?? apnsID;

    if (response.ok) {
      return {
        token_id: token.id,
        status: "accepted",
        http_status: response.status,
        apns_id: responseAPNsID,
      };
    }

    const errorBody = await readAPNsError(response);
    const status = classifyAPNsFailure(response.status, errorBody.reason);
    return {
      token_id: token.id,
      status,
      http_status: response.status,
      apns_reason: errorBody.reason ?? null,
      error_message: `${response.status}:${
        errorBody.reason ?? "unknown_apns_error"
      }`,
      apns_id: responseAPNsID,
    };
  } catch (error) {
    return {
      token_id: token.id,
      status: "retryable_failure",
      error_message: error instanceof Error
        ? error.message
        : "unknown_transport_error",
      apns_id: apnsID,
    };
  }
}

export function classifyAPNsFailure(
  httpStatus: number,
  reason?: string | null,
): Exclude<DeliveryStatus, "accepted"> {
  if (
    httpStatus === 410 ||
    reason === "BadDeviceToken" ||
    reason === "DeviceTokenNotForTopic" ||
    reason === "ExpiredToken" ||
    reason === "Unregistered"
  ) {
    return "permanent_token_failure";
  }

  if (httpStatus === 429 || httpStatus >= 500) {
    return "retryable_failure";
  }

  if (httpStatus >= 400 && httpStatus < 500) {
    return "permanent_event_failure";
  }

  return "retryable_failure";
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

async function readAPNsError(
  response: Response,
): Promise<{ reason?: string | null }> {
  const text = await response.text();
  if (!text.trim()) return {};

  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object"
      ? parsed as { reason?: string | null }
      : {};
  } catch {
    return {};
  }
}

function isAuthorizedWorker(req: Request): boolean {
  const workerSecret = Deno.env.get("WANDER_WORKER_SECRET");
  if (!workerSecret) return false;
  const header = req.headers.get("x-wander-worker-secret");
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return header === workerSecret || bearer === workerSecret;
}

function apnsConfig(): APNsConfig | null {
  const keyId = firstEnv(["APNS_KEY_ID", "WANDER_APNS_KEY_ID"]);
  const teamId = firstEnv(["APNS_TEAM_ID", "WANDER_APNS_TEAM_ID"]);
  const privateKey = firstEnv([
    "APNS_PRIVATE_KEY",
    "APNS_AUTH_KEY",
    "WANDER_APNS_PRIVATE_KEY",
    "WANDER_APNS_AUTH_KEY",
  ])?.replaceAll("\\n", "\n");

  if (!keyId || !teamId || !privateKey) return null;

  return {
    keyId,
    teamId,
    privateKeyPEM: privateKey,
    defaultTopic: firstEnv(["APNS_TOPIC", "WANDER_APNS_TOPIC"]),
  };
}

function firstEnv(names: string[]): string | null {
  for (const name of names) {
    const value = Deno.env.get(name)?.trim();
    if (value) return value;
  }
  return null;
}

async function apnsJWT(config: APNsConfig): Promise<string> {
  const header = base64URLJSON({ alg: "ES256", kid: config.keyId });
  const payload = base64URLJSON({
    iss: config.teamId,
    iat: Math.floor(Date.now() / 1000),
  });
  const signingInput = `${header}.${payload}`;
  const key = await importP8Key(config.privateKeyPEM);
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64URLBytes(ecdsaSignatureToJOSE(signature))}`;
}

async function importP8Key(privateKeyPEM: string): Promise<CryptoKey> {
  const base64 = privateKeyPEM
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const raw = atob(base64);
  const binary = new Uint8Array(raw.length);
  for (let index = 0; index < raw.length; index += 1) {
    binary[index] = raw.charCodeAt(index);
  }
  return await crypto.subtle.importKey(
    "pkcs8",
    binary,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

function ecdsaSignatureToJOSE(signature: ArrayBuffer): Uint8Array {
  const bytes = new Uint8Array(signature);
  if (bytes.length === 64) return bytes;
  if (bytes[0] !== 0x30) throw new Error("invalid_ecdsa_signature");

  let offset = 2;
  if (bytes[1] & 0x80) offset = 2 + (bytes[1] & 0x7f);
  if (bytes[offset] !== 0x02) throw new Error("invalid_ecdsa_signature_r");
  const rLength = bytes[offset + 1];
  const r = bytes.slice(offset + 2, offset + 2 + rLength);
  offset = offset + 2 + rLength;
  if (bytes[offset] !== 0x02) throw new Error("invalid_ecdsa_signature_s");
  const sLength = bytes[offset + 1];
  const s = bytes.slice(offset + 2, offset + 2 + sLength);
  return new Uint8Array([...leftPad32(r), ...leftPad32(s)]);
}

function leftPad32(value: Uint8Array): Uint8Array {
  let trimmed = value;
  while (trimmed.length > 32 && trimmed[0] === 0) trimmed = trimmed.slice(1);
  if (trimmed.length > 32) throw new Error("invalid_ecdsa_signature_component");
  const output = new Uint8Array(32);
  output.set(trimmed, 32 - trimmed.length);
  return output;
}

function base64URLJSON(value: unknown): string {
  return base64URLBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64URLBytes(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll(
    "=",
    "",
  );
}

async function serviceRpc<T>(
  name: string,
  body: Record<string, unknown>,
): Promise<T> {
  const serviceKey = Deno.env.get("WANDER_SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) throw new Error("missing_service_role_key");

  const supabaseURL = Deno.env.get("WANDER_SUPABASE_URL") ??
    Deno.env.get("SUPABASE_URL");
  if (!supabaseURL) throw new Error("missing_supabase_url");

  const response = await fetch(`${supabaseURL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      ...jsonHeaders,
      apikey: serviceKey,
      authorization: `Bearer ${serviceKey}`,
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`rpc_${name}_failed:${response.status}:${text}`);
  }
  return (text.trim() ? JSON.parse(text) : null) as T;
}
