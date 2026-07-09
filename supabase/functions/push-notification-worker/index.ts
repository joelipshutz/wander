import "@supabase/functions-js/edge-runtime.d.ts";

type PushToken = {
  id: string;
  device_token: string;
  environment: "sandbox" | "production";
  app_bundle_id: string;
};

type PushEvent = {
  event_id: string;
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

type TokenSendResult = {
  tokenId: string;
  status: "sent" | "failed";
  permanentFailure: boolean;
  error?: string;
};

type ProcessedEvent = {
  event_id: string;
  status: "sent" | "failed" | "skipped" | "retrying";
  sent_count?: number;
  failed_count?: number;
  deactivated_token_count?: number;
  retryable?: boolean;
  reason?: string;
  error?: string;
};

const jsonHeaders = { "Content-Type": "application/json" };

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

async function handleRequest(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }

  if (!isAuthorizedWorker(req)) {
    return Response.json({ error: "missing_worker_secret" }, { status: 401 });
  }

  const body = await readBody(req);
  const limit = Math.min(Math.max(Number(body.limit ?? 10) || 10, 1), 100);
  const events = await serviceRpc<PushEvent[]>(
    "claim_pending_push_notifications",
    { input_limit: limit },
  );

  const config = apnsConfig();
  const processed: ProcessedEvent[] = [];
  for (const event of events) {
    processed.push(await processEvent(event, config));
  }

  return Response.json({
    claimed_count: events.length,
    summary: processingSummary(processed),
    processed,
  });
}

async function processEvent(
  event: PushEvent,
  config: APNsConfig | null,
): Promise<ProcessedEvent> {
  if (event.tokens.length === 0) {
    await markEvent(event.event_id, "skipped", "no_active_tokens");
    return { event_id: event.event_id, status: "skipped", reason: "no_active_tokens" };
  }

  if (!config) {
    await markEvent(event.event_id, "skipped", "apns_not_configured");
    return { event_id: event.event_id, status: "skipped", reason: "apns_not_configured" };
  }

  const jwt = await apnsJWT(config);
  const results = await Promise.all(
    event.tokens.map((token) => sendToToken(event, token, config, jwt)),
  );
  const sentCount = results.filter((result) => result.status === "sent").length;
  const failedCount = results.length - sentCount;
  const inactiveTokenIds = results
    .filter((result) => result.permanentFailure)
    .map((result) => result.tokenId);

  if (inactiveTokenIds.length > 0) {
    await serviceRpc<number>("deactivate_push_tokens", {
      input_token_ids: inactiveTokenIds,
      input_reason: "apns_permanent_failure",
    });
  }

  if (sentCount > 0) {
    await markEvent(event.event_id, "sent", failedCount > 0 ? `${failedCount}_token_failures` : null);
    return {
      event_id: event.event_id,
      status: "sent",
      sent_count: sentCount,
      failed_count: failedCount,
      deactivated_token_count: inactiveTokenIds.length,
    };
  }

  const error = results.map((result) => result.error).filter(Boolean).join("; ") ||
    "all_tokens_failed";
  const retryable = results.some((result) => !result.permanentFailure);
  await markEvent(event.event_id, "failed", error, retryable);
  return {
    event_id: event.event_id,
    status: retryable ? "retrying" : "failed",
    sent_count: 0,
    failed_count: failedCount,
    deactivated_token_count: inactiveTokenIds.length,
    retryable,
    error,
  };
}

function processingSummary(processed: ProcessedEvent[]): Record<string, number> {
  return processed.reduce(
    (summary, event) => {
      summary[event.status] += 1;
      summary.sent_tokens += event.sent_count ?? 0;
      summary.failed_tokens += event.failed_count ?? 0;
      summary.deactivated_tokens += event.deactivated_token_count ?? 0;
      return summary;
    },
    {
      sent: 0,
      failed: 0,
      skipped: 0,
      retrying: 0,
      sent_tokens: 0,
      failed_tokens: 0,
      deactivated_tokens: 0,
    },
  );
}

async function sendToToken(
  event: PushEvent,
  token: PushToken,
  config: APNsConfig,
  jwt: string,
): Promise<TokenSendResult> {
  const topic = config.defaultTopic || token.app_bundle_id;
  const host = token.environment === "sandbox"
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  const payload = {
    aps: {
      alert: {
        title: event.title,
        body: event.body,
      },
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
    const response = await fetch(`https://${host}/3/device/${token.device_token}`, {
      method: "POST",
      headers: {
        ...jsonHeaders,
        authorization: `bearer ${jwt}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify(payload),
    });

    if (response.ok) {
      return { tokenId: token.id, status: "sent", permanentFailure: false };
    }

    const errorBody = await readAPNsError(response);
    return {
      tokenId: token.id,
      status: "failed",
      permanentFailure: isPermanentTokenFailure(response.status, errorBody.reason),
      error: `${response.status}:${errorBody.reason ?? "unknown_apns_error"}`,
    };
  } catch (error) {
    return {
      tokenId: token.id,
      status: "failed",
      permanentFailure: false,
      error: error instanceof Error ? error.message : "unknown_transport_error",
    };
  }
}

async function markEvent(
  eventId: string,
  status: "sent" | "failed" | "skipped",
  errorMessage: string | null,
  retryable = false,
): Promise<void> {
  await serviceRpc<null>("mark_push_notification_result", {
    input_event_id: eventId,
    input_status: status,
    input_error_message: errorMessage,
    input_retryable: retryable,
  });
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

function isPermanentTokenFailure(status: number, reason?: string | null): boolean {
  return status === 410 || reason === "BadDeviceToken" || reason === "Unregistered" ||
    reason === "DeviceTokenNotForTopic";
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

  if (bytes[0] !== 0x30) {
    throw new Error("invalid_ecdsa_signature");
  }

  let offset = 2;
  if (bytes[1] & 0x80) {
    offset = 2 + (bytes[1] & 0x7f);
  }

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
  while (trimmed.length > 32 && trimmed[0] === 0) {
    trimmed = trimmed.slice(1);
  }
  if (trimmed.length > 32) {
    throw new Error("invalid_ecdsa_signature_component");
  }

  const output = new Uint8Array(32);
  output.set(trimmed, 32 - trimmed.length);
  return output;
}

function base64URLJSON(value: unknown): string {
  return base64URLBytes(new TextEncoder().encode(JSON.stringify(value)));
}

function base64URLBytes(value: Uint8Array): string {
  let binary = "";
  for (const byte of value) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
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
