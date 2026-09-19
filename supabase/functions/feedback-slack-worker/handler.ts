type Attachment = { filename: string; kind: string };
export type FeedbackJob = {
  id: string; user_id: string; body: string; attachments: Attachment[];
  display_name: string; handle: string; clerk_user_ids: string[];
  app_version: string; build_number: string; submitted_at: string; claim_token: string;
};
type Dependencies = { env: (key: string) => string | undefined; fetch: typeof fetch };
type Contact = { email?: string; phone?: string };
const headers = { "Cache-Control": "no-store" };
const projectURL = "https://rugmtlgufrhlxwfkumhw.supabase.co";
const dashboardURL = "https://supabase.com/dashboard/project/rugmtlgufrhlxwfkumhw/editor";

export function verifiedContact(user: any, canonicalID: string): Contact {
  const identity = user.external_id || user.public_metadata?.canonical_user_id || user.id;
  if (identity !== canonicalID) return {};
  const email = user.email_addresses?.find((value: any) => value.id === user.primary_email_address_id
    && value.verification?.status === "verified");
  const phone = user.phone_numbers?.find((value: any) => value.id === user.primary_phone_number_id
    && value.verification?.status === "verified" && !value.reserved_for_second_factor);
  return { email: email?.email_address, phone: phone?.phone_number };
}

export function slackPayload(job: FeedbackJob, contact: Contact, media: Array<{ name: string; url: string }>) {
  // Feedback is plain_text, so user text cannot become mentions, links or Slack commands.
  const plain = (text: string) => ({ type: "section", text: { type: "plain_text", text, emoji: false } });
  const blocks: any[] = [
    { type: "header", text: { type: "plain_text", text: "New Astir feedback", emoji: false } },
    plain(`${job.display_name} (@${job.handle})\nEmail: ${contact.email || "Not available — use account lookup"}\nPhone: ${contact.phone || "Not provided"}`),
  ];
  const body = job.body || "Feedback is in the attachments.";
  for (let index = 0; index < body.length; index += 2500) blocks.push(plain(body.slice(index, index + 2500)));
  if (media.length) blocks.push({ type: "actions", elements: media.map(item => ({
    type: "button", text: { type: "plain_text", text: item.name }, url: item.url,
  })) });
  blocks.push(plain(`Account: ${job.user_id}\nReport: ${job.id}\nApp: ${job.app_version} (${job.build_number})\nSubmitted: ${job.submitted_at}`));
  blocks.push({ type: "actions", elements: [{ type: "button", text: { type: "plain_text", text: "Open server inbox" }, url: dashboardURL }] });
  blocks.push(plain("Attachment links expire in 24 hours. Originals remain in private server storage. Slack replies stay internal; use the listed contact details to reach the sender."));
  return { text: "New Astir feedback", blocks, unfurl_links: false, unfurl_media: false };
}

export async function handleRequest(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method !== "POST") return Response.json({ error: "method_not_allowed" }, { status: 405, headers });
  const secret = deps.env("ASTIR_FEEDBACK_SLACK_WORKER_SECRET");
  if (!secret || request.headers.get("x-feedback-worker-secret") !== secret) {
    return Response.json({ error: "unauthorized" }, { status: 401, headers });
  }
  const url = deps.env("SUPABASE_URL")?.replace(/\/$/, "");
  const key = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  const webhook = deps.env("ASTIR_FEEDBACK_SLACK_WEBHOOK_URL");
  const clerkKey = deps.env("ASTIR_FEEDBACK_CLERK_SECRET_KEY");
  // Fail closed on routing. A missing notification configuration never blocks submission.
  if (url !== projectURL || !key || !clerkKey || !webhook || !/^https:\/\/hooks\.slack\.com\/services\/[A-Za-z0-9/]+$/.test(webhook)) {
    return Response.json({ error: "not_configured" }, { status: 503, headers });
  }
  const serviceHeaders = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
  const rpc = async (name: string, body: unknown) => {
    const response = await deps.fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST", headers: serviceHeaders, body: JSON.stringify(body), signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error("database_unavailable");
    return response.json();
  };
  try {
    const jobs: FeedbackJob[] = await rpc("claim_feedback_slack", {});
    let sent = 0; let retrying = 0;
    for (const job of jobs) {
      let accepted = false; let error: string | null = null;
      try {
        let contact: Contact = {};
        for (const clerkID of [...new Set([...(job.clerk_user_ids || []), job.user_id])].slice(0, 5)) {
          const response = await deps.fetch(`https://api.clerk.com/v1/users/${encodeURIComponent(clerkID)}`, {
            headers: { Authorization: `Bearer ${clerkKey}`, "User-Agent": "AstirFeedback/1.0" }, signal: AbortSignal.timeout(8_000),
          });
          if (response.status === 404) continue;
          if (!response.ok) throw new Error("contact_lookup_unavailable");
          contact = verifiedContact(await response.json(), job.user_id);
          if (contact.email || contact.phone) break;
        }
        const media = [];
        let photos = 0;
        for (const attachment of job.attachments) {
          const path = `feedback-attachments/${encodeURIComponent(job.id)}/${encodeURIComponent(attachment.filename)}`;
          const response = await deps.fetch(`${url}/storage/v1/object/sign/${path}`, {
            method: "POST", headers: serviceHeaders, body: JSON.stringify({ expiresIn: 86400 }), signal: AbortSignal.timeout(10_000),
          });
          if (!response.ok) throw new Error("attachment_unavailable");
          const signed = await response.json();
          if (typeof signed.signedURL !== "string" || !signed.signedURL.startsWith(`/object/sign/${path}?`)) throw new Error("attachment_unavailable");
          media.push({ name: attachment.kind === "voice" ? "Listen to voice note" : `View photo ${++photos}`, url: `${url}/storage/v1${signed.signedURL}` });
        }
        const response = await deps.fetch(webhook, { method: "POST", headers: { "Content-Type": "application/json" },
          body: JSON.stringify(slackPayload(job, contact, media)), signal: AbortSignal.timeout(15_000) });
        if (!response.ok || (await response.text()).trim() !== "ok") throw new Error("slack_unavailable");
        accepted = true;
      } catch (failure) {
        const code = failure instanceof Error ? failure.message : "";
        error = ["attachment_unavailable", "contact_lookup_unavailable"].includes(code) ? code : "slack_unavailable";
      }
      if (await rpc("settle_feedback_slack", { p_id: job.id, p_claim: job.claim_token, p_accepted: accepted, p_error: error })) {
        if (accepted) sent++; else retrying++;
      } else retrying++;
    }
    return Response.json({ sent, retrying }, { headers });
  } catch { return Response.json({ error: "worker_unavailable" }, { status: 503, headers }); }
}
