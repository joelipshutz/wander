import { normalizedIdentifiers, verifiedIdentifiers, type ContactIdentifier, type VerifiedContactUser } from "../_shared/contact-identifiers.ts";

export type Dependencies = { fetch: typeof fetch; env: (key: string) => string | undefined };
const projectURL = "https://rugmtlgufrhlxwfkumhw.supabase.co";
const headers = { "Content-Type": "application/json", "Cache-Control": "private, no-store" };
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

export async function handleRequest(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return reply({ error: "unauthorized" }, 401);
  if (deps.env("SUPABASE_URL") !== projectURL) return reply({ error: "unavailable" }, 503);
  const anon = deps.env("SUPABASE_ANON_KEY");
  const service = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  if (!anon || !service) return reply({ error: "unavailable" }, 503);
  const rpc = async (name: string, body: unknown, privileged = false): Promise<Response> => deps.fetch(
    `${projectURL}/rest/v1/rpc/${name}`, {
      method: "POST", headers: { "Content-Type": "application/json", apikey: privileged ? service : anon,
        Authorization: privileged ? `Bearer ${service}` : authorization },
      body: JSON.stringify(body), signal: AbortSignal.timeout(8_000),
    });

  try {
    // PostgREST verifies the Clerk JWT and resolves canonical identity. JWT
    // contents are read only AFTER this authenticated check succeeds.
    const auth = await rpc("current_profile", {});
    if (!auth.ok) return reply({ error: "unauthorized" }, 401);
    const rows = await auth.json();
    if (!Array.isArray(rows) || rows.length !== 1) return reply({ error: "unauthorized" }, 401);
    const profile = rows[0];
    if (!profile || typeof profile.id !== "string" || profile.deleted_at) return reply({ error: "unauthorized" }, 401);
    let claims: { sub?: string; iss?: string };
    try {
      const encoded = authorization.slice(7).split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      claims = JSON.parse(atob(encoded));
    } catch { return reply({ error: "unauthorized" }, 401); }
    if (claims.iss !== "https://clerk.getrec.me" || !claims.sub?.startsWith("user_")) return reply({ error: "unauthorized" }, 401);

    // Bound streaming bodies too; Content-Length alone is not authoritative.
    const reader = request.body?.getReader();
    if (!reader) return reply({ error: "invalid_request" }, 400);
    const chunks: Uint8Array[] = []; let size = 0;
    while (true) {
      const next = await reader.read(); if (next.done) break;
      size += next.value.byteLength;
      if (size > 300_000) { await reader.cancel(); return reply({ error: "request_too_large" }, 413); }
      chunks.push(next.value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
    let body: { action?: string; identifiers?: ContactIdentifier[]; region?: string };
    try { body = JSON.parse(new TextDecoder().decode(bytes)); }
    catch { return reply({ error: "invalid_request" }, 400); }
    if (!body || !["status", "enable", "disable", "match"].includes(body.action ?? "")) return reply({ error: "invalid_request" }, 400);

    if (body.action === "status") {
      const result = await rpc("own_contact_discovery_enabled", {});
      if (!result.ok) return reply({ error: "unavailable" }, 503);
      return reply({ enabled: await result.json() === true });
    }
    if (body.action === "disable") {
      const result = await rpc("set_contact_discovery_enabled", { input_enabled: false });
      return result.ok ? reply({ enabled: false }) : reply({ error: "unavailable" }, 503);
    }

    if (body.action === "enable") {
      const admitted = await rpc("admit_contact_discovery", { input_count: 0 });
      if (!admitted.ok) return reply({ error: "unavailable" }, 503);
      if (await admitted.json() !== true) return reply({ error: "try_later" }, 429);
      // This existing environment alias contains Astir's production Clerk key;
      // no contact data is sent to Clerk. Only the signed-in user is fetched.
      const clerkKey = deps.env("ASTIR_FEEDBACK_CLERK_SECRET_KEY");
      if (!clerkKey) return reply({ error: "unavailable" }, 503);
      const userResponse = await deps.fetch(`https://api.clerk.com/v1/users/${encodeURIComponent(claims.sub)}`, {
        headers: { Authorization: `Bearer ${clerkKey}` }, signal: AbortSignal.timeout(8_000),
      });
      if (!userResponse.ok) return reply({ error: "unavailable" }, 503);
      const user = await userResponse.json() as VerifiedContactUser;
      if (user.id !== claims.sub || !Number.isFinite(user.updated_at)) return reply({ error: "unavailable" }, 503);
      const enabled = await rpc("set_contact_discovery_enabled", { input_enabled: true });
      if (!enabled.ok) return reply({ error: "unavailable" }, 503);
      const synced = await rpc("sync_contact_discovery_identity", {
        input_clerk_user_id: user.id, input_user_id: profile.id,
        input_updated_at: new Date(user.updated_at!).toISOString(), input_identifiers: verifiedIdentifiers(user),
      }, true);
      if (!synced.ok) return reply({ error: "unavailable" }, 503);
      return reply({ enabled: true });
    }

    if (!Array.isArray(body.identifiers) || body.identifiers.length > 5000 ||
      (body.region !== undefined && (typeof body.region !== "string" || !/^[A-Z]{2}$/.test(body.region))) ||
      body.identifiers.some(v => !v || !["phone", "email"].includes(v.kind) || typeof v.value !== "string" || v.value.length > 254)) {
      return reply({ error: "invalid_request" }, 400);
    }
    const consent = await rpc("own_contact_discovery_enabled", {});
    if (!consent.ok || await consent.json() !== true) return reply({ error: "consent_required" }, 403);
    const identifiers = normalizedIdentifiers(body.identifiers, body.region);
    const admitted = await rpc("admit_contact_discovery", { input_count: identifiers.length });
    if (!admitted.ok) return reply({ error: "unavailable" }, 503);
    if (await admitted.json() !== true) return reply({ error: "try_later" }, 429);
    const matches = await rpc("match_contact_discovery", { input_viewer_id: profile.id, input_identifiers: identifiers }, true);
    if (!matches.ok) return reply({ error: "unavailable" }, 503);
    return reply({ profiles: await matches.json() });
  } catch {
    // Never log request bodies, identifiers, JWTs, provider responses or error
    // objects: their messages can contain the private payload.
    return reply({ error: "unavailable" }, 503);
  }
}
