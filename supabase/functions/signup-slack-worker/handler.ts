export type SignupJob = {
  profile_id: string; display_name: string; clerk_user_ids: string[];
  signed_up_at: string; claim_token: string;
};
type Dependencies = { env: (key: string) => string | undefined; fetch: typeof fetch };
const headers = { "Cache-Control": "no-store" };
const projectURL = "https://rugmtlgufrhlxwfkumhw.supabase.co";
const bounded = (value: unknown, limit: number) => typeof value === "string"
  ? Array.from(value.trim().replace(/[\r\n\t]+/g, " ")).slice(0, limit).join("") : "";

export function signupDetails(user: any, job: SignupJob) {
  const canonicalID = bounded(user.external_id, 200) || bounded(user.public_metadata?.canonical_user_id, 200) || user.id;
  if (canonicalID !== job.profile_id) throw new Error("identity_mismatch");
  // A dev account can map to an existing production profile. Only announce a
  // production account created at the time of this creation event.
  if (typeof user.created_at !== "number" || !Number.isFinite(user.created_at)
    || Math.abs(user.created_at - Date.parse(job.signed_up_at)) > 5 * 60_000
    || !Number.isFinite(Date.parse(job.signed_up_at))) throw new Error("creation_mismatch");
  const name = bounded(job.display_name, 200)
    || [bounded(user.first_name, 100), bounded(user.last_name, 100)].filter(Boolean).join(" ");
  const email = user.email_addresses?.find((item: any) => item.id === user.primary_email_address_id
    && item.verification?.status === "verified")?.email_address;
  return { name, email: bounded(email, 320) || "Not provided" };
}

export function slackPayload(details: { name: string; email: string }) {
  const text = `${details.name || "Someone"} signed up\nEmail: ${details.email}`;
  return {
    // Escape fallback text too: customer names must never mention a Slack user/channel.
    text: text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"),
    blocks: [{ type: "section", text: { type: "plain_text", text, emoji: false } }],
    mrkdwn: false, parse: "none", unfurl_links: false, unfurl_media: false,
  };
}

export async function handleRequest(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method !== "POST") return Response.json({ error: "method_not_allowed" }, { status: 405, headers });
  const secret = deps.env("ASTIR_SIGNUP_SLACK_WORKER_SECRET");
  if (!secret || request.headers.get("x-signup-worker-secret") !== secret) {
    return Response.json({ error: "unauthorized" }, { status: 401, headers });
  }
  const url = deps.env("SUPABASE_URL")?.replace(/\/$/, "");
  const key = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  const webhook = deps.env("ASTIR_SIGNUP_SLACK_WEBHOOK_URL");
  const clerkKey = deps.env("ASTIR_SIGNUP_CLERK_SECRET_KEY");
  if (url !== projectURL || !key || !clerkKey?.startsWith("sk_live_") || !webhook
    || !/^https:\/\/hooks\.slack\.com\/services\/T0B9DS16JS2\/[A-Za-z0-9]+\/[A-Za-z0-9]+$/.test(webhook)) {
    return Response.json({ error: "not_configured" }, { status: 503, headers });
  }
  const rpc = async (name: string, body: unknown) => {
    const response = await deps.fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error("database_unavailable");
    return response.json();
  };
  try {
    const jobs: SignupJob[] = await rpc("claim_signup_slack", {});
    // Bound external work for the whole batch, leaving time to settle all five
    // claims even during repeated provider timeouts (under the Edge time limit).
    const externalDeadline = AbortSignal.timeout(80_000);
    let sent = 0; let retrying = 0; let skipped = 0;
    for (const job of jobs) {
      let outcome = "retry"; let error: string | null = null;
      try {
        let details;
        for (const id of [...new Set([...(job.clerk_user_ids || []), job.profile_id])].slice(0, 5)) {
          const response = await deps.fetch(`https://api.clerk.com/v1/users/${encodeURIComponent(id)}`, {
            headers: { Authorization: `Bearer ${clerkKey}`, "User-Agent": "AstirSignups/1.0" },
            signal: AbortSignal.any([externalDeadline, AbortSignal.timeout(8_000)]),
          });
          if (response.status === 404) continue;
          if (!response.ok) throw new Error("contact_lookup_unavailable");
          details = signupDetails(await response.json(), job);
          break;
        }
        if (!details) {
          // Shared Supabase also receives development events. Never announce
          // accounts absent from production. Give identity mapping retries time.
          const age = Date.now() - Date.parse(job.signed_up_at);
          outcome = Number.isFinite(age) && age > 10 * 60_000 ? "skipped" : "retry";
          error = "production_account_not_found";
        } else {
          const response = await deps.fetch(webhook, {
            method: "POST", headers: { "Content-Type": "application/json" },
            body: JSON.stringify(slackPayload(details)),
            signal: AbortSignal.any([externalDeadline, AbortSignal.timeout(15_000)]),
          });
          if (!response.ok || (await response.text()).trim() !== "ok") throw new Error("slack_unavailable");
          outcome = "sent";
        }
      } catch (failure) {
        const code = failure instanceof Error ? failure.message : "";
        if (code === "creation_mismatch") outcome = "skipped";
        error = ["identity_mismatch", "creation_mismatch", "contact_lookup_unavailable"].includes(code) ? code : "slack_unavailable";
      }
      if (await rpc("settle_signup_slack", { p_id: job.profile_id, p_claim: job.claim_token, p_outcome: outcome, p_error: error })) {
        if (outcome === "sent") sent++; else if (outcome === "skipped") skipped++; else retrying++;
      } else retrying++;
    }
    return Response.json({ sent, retrying, skipped }, { headers });
  } catch { return Response.json({ error: "worker_unavailable" }, { status: 503, headers }); }
}
