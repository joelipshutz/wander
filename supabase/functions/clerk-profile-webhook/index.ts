import "@supabase/functions-js/edge-runtime.d.ts";
import { purgeAccountStorage } from "./account-purge.ts";
import {
  canonicalProfileIDFromPayload,
  registerClerkIdentityMapping,
  resolveCanonicalProfileID,
  type ClerkIdentityPayload,
} from "./identity.ts";

type ClerkEmailAddress = {
  id?: string;
  email_address?: string;
};

type ClerkUser = ClerkIdentityPayload & {
  username?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  image_url?: string | null;
  profile_image_url?: string | null;
  primary_email_address_id?: string | null;
  email_addresses?: ClerkEmailAddress[];
  created_at?: number | string | null;
  updated_at?: number | string | null;
};

type ClerkDeletedUser = ClerkIdentityPayload & {
  deleted?: boolean;
};

type ClerkProfileWebhookEvent =
  | {
    type: "user.created" | "user.updated";
    data: ClerkUser;
    timestamp?: number | string | null;
  }
  | {
    type: "user.deleted";
    data: ClerkDeletedUser;
    timestamp?: number | string | null;
  };

type ClerkWebhookEvent =
  | ClerkProfileWebhookEvent
  | {
    type: string;
    data?: { id?: string };
    timestamp?: number | string | null;
  };

const encoder = new TextEncoder();

Deno.serve(async (req) => {
  try {
    return await handleRequest(req);
  } catch (error) {
    console.error(
      "clerk_profile_webhook_error",
      error instanceof Error ? error.message : "unknown_error",
    );
    return Response.json({ error: "internal_error" }, { status: 500 });
  }
});

async function handleRequest(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }

  const signingSecrets = [
    Deno.env.get("CLERK_WEBHOOK_SIGNING_SECRET"),
    Deno.env.get("CLERK_WEBHOOK_SIGNING_SECRET_SECONDARY"),
  ].filter((secret): secret is string => Boolean(secret?.trim()));
  if (signingSecrets.length === 0) {
    return Response.json({ error: "missing_signing_secret" }, { status: 500 });
  }

  const body = await req.text();
  const signatureChecks = await Promise.all(
    signingSecrets.map((secret) => verifySvixSignature(req.headers, body, secret)),
  );
  if (!signatureChecks.some(Boolean)) {
    return Response.json({ error: "invalid_signature" }, { status: 401 });
  }

  let event: ClerkWebhookEvent;
  try {
    event = JSON.parse(body) as ClerkWebhookEvent;
  } catch {
    return Response.json({ error: "invalid_json" }, { status: 400 });
  }

  if (!event.data?.id) {
    return Response.json({ error: "missing_user_id" }, { status: 400 });
  }

  switch (event.type) {
  case "user.created":
  case "user.updated":
  case "user.deleted":
    return Response.json(
      await mirrorClerkProfile(req.headers, event as ClerkProfileWebhookEvent),
    );
  default:
    return Response.json({ ok: true, action: "ignored", event_type: event.type });
  }
}

async function verifySvixSignature(headers: Headers, payload: string, secret: string): Promise<boolean> {
  const messageId = headers.get("svix-id");
  const timestamp = headers.get("svix-timestamp");
  const signatureHeader = headers.get("svix-signature");

  if (!messageId || !timestamp || !signatureHeader) {
    return false;
  }

  const timestampSeconds = Number(timestamp);
  if (!Number.isFinite(timestampSeconds)) {
    return false;
  }

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - timestampSeconds) > 5 * 60) {
    return false;
  }

  const signingPayload = `${messageId}.${timestamp}.${payload}`;
  const expectedSignature = await hmacSha256Base64(signingPayload, svixSecretBytes(secret));
  const signatures = signatureHeader
    .split(" ")
    .map((candidate) => candidate.trim())
    .flatMap((candidate) => {
      const [version, value] = candidate.split(",");
      return version === "v1" && value ? [value] : [];
    });

  return signatures.some((signature) => timingSafeEqual(signature, expectedSignature));
}

function svixSecretBytes(secret: string): Uint8Array {
  const base64Secret = secret.startsWith("whsec_") ? secret.slice("whsec_".length) : secret;
  return base64ToBytes(base64Secret);
}

async function hmacSha256Base64(payload: string, secretBytes: Uint8Array): Promise<string> {
  const secretBuffer = new Uint8Array(secretBytes).buffer;
  const key = await crypto.subtle.importKey(
    "raw",
    secretBuffer,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(payload));
  return bytesToBase64(new Uint8Array(signature));
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}

function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);
  if (aBytes.length !== bBytes.length) {
    return false;
  }

  let diff = 0;
  for (let index = 0; index < aBytes.length; index += 1) {
    diff |= aBytes[index] ^ bBytes[index];
  }
  return diff === 0;
}

async function mirrorClerkProfile(headers: Headers, event: ClerkProfileWebhookEvent): Promise<unknown> {
  const user = event.data;
  const isDelete = event.type === "user.deleted";
  const mirroredEventTimestamp = eventTimestamp(event, headers);
  const profileID = isDelete
    ? await resolveCanonicalProfileID(user, supabaseFetch)
    : canonicalProfileIDFromPayload(user) ?? user.id;
  if (isDelete) {
    await purgeAccountStorage(profileID, mirroredEventTimestamp, supabaseFetch);
  }
  const response = await supabaseFetch("/rest/v1/rpc/mirror_clerk_profile", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      event_id: headers.get("svix-id"),
      event_type: event.type,
      event_timestamp: mirroredEventTimestamp,
      profile_id: profileID,
      desired_handle: !isDelete && user ? profileHandle(user as ClerkUser) : null,
      desired_display_name: !isDelete && user ? displayName(user as ClerkUser) : null,
      desired_avatar_url: !isDelete && user ? (user as ClerkUser).image_url ?? (user as ClerkUser).profile_image_url ?? null : null,
    }),
  });

  if (!response.ok) {
    throw new Error(`profile_mirror_failed:${response.status}:${await response.text()}`);
  }

  if (!isDelete) {
    // This separate idempotent write deliberately happens after mirroring so
    // the profile foreign key exists. If it fails, Svix retries the event;
    // duplicate profile events are safe and the mapping write is retried.
    await registerClerkIdentityMapping(user.id, profileID, supabaseFetch);
  }

  return await response.json();
}

function profileHandle(user: ClerkUser): string {
  const primaryEmail = primaryEmailAddress(user);
  const raw = user.username ?? primaryEmail?.split("@")[0] ?? `user_${user.id.slice(-8)}`;
  const sanitized = raw.toLowerCase().replace(/[^a-z0-9_]/g, "_").replace(/^_+|_+$/g, "");
  if (sanitized.length >= 2) {
    return sanitized;
  }
  return `user_${user.id.slice(-8).toLowerCase().replace(/[^a-z0-9_]/g, "")}`;
}

function displayName(user: ClerkUser): string {
  const fullName = [user.first_name, user.last_name]
    .filter((part): part is string => Boolean(part?.trim()))
    .join(" ")
    .trim();
  return fullName || user.username || profileHandle(user);
}

function primaryEmailAddress(user: ClerkUser): string | undefined {
  return user.email_addresses?.find((email) => email.id === user.primary_email_address_id)?.email_address
    ?? user.email_addresses?.[0]?.email_address;
}

async function supabaseFetch(path: string, init: RequestInit): Promise<Response> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? Deno.env.get("WANDER_SUPABASE_URL");
  const serviceRoleKey = supabaseServiceRoleKey();

  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error("missing_supabase_env");
  }

  return await fetch(`${supabaseUrl}${path}`, {
    ...init,
    headers: {
      ...(init.headers ?? {}),
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${serviceRoleKey}`,
    },
  });
}

function eventTimestamp(event: ClerkWebhookEvent, headers: Headers): string {
  const user = event.data;
  return normalizeTimestamp(event.timestamp)
    ?? normalizeTimestamp(user && "updated_at" in user ? user.updated_at : undefined)
    ?? normalizeTimestamp(user && "created_at" in user ? user.created_at : undefined)
    ?? normalizeTimestamp(headers.get("svix-timestamp"))
    ?? new Date().toISOString();
}

function normalizeTimestamp(value: number | string | null | undefined): string | undefined {
  if (value === null || value === undefined || value === "") {
    return undefined;
  }

  if (typeof value === "number") {
    const milliseconds = value > 1_000_000_000_000 ? value : value * 1000;
    return new Date(milliseconds).toISOString();
  }

  const numeric = Number(value);
  if (Number.isFinite(numeric)) {
    const milliseconds = numeric > 1_000_000_000_000 ? numeric : numeric * 1000;
    return new Date(milliseconds).toISOString();
  }

  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? undefined : parsed.toISOString();
}

function supabaseServiceRoleKey(): string | undefined {
  const legacyKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacyKey) {
    return legacyKey;
  }

  const wanderKey = Deno.env.get("WANDER_SUPABASE_SERVICE_ROLE_KEY");
  if (wanderKey) {
    return wanderKey;
  }

  const secretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (!secretKeys) {
    return undefined;
  }

  try {
    const parsed = JSON.parse(secretKeys) as Record<string, string>;
    return parsed.default ?? Object.values(parsed)[0];
  } catch {
    return undefined;
  }
}
