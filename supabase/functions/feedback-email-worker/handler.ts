export type Feedback = {
  id: string;
  user_id: string;
  body: string;
  attachments: Array<{ filename: string; kind: string; content_type: string; byte_size: number }>;
  app_version: string;
  build_number: string;
  submitted_at: string;
  claim_token: string;
};

type Dependencies = { env: (key: string) => string | undefined; fetch: typeof fetch };
const recipient = "admin@HotchkissTechnologies.com";
const headers = { "Cache-Control": "no-store" };
const maxBytes = 2 * 1024 * 1024;

export async function handleRequest(request: Request, deps: Dependencies): Promise<Response> {
  if (request.method !== "POST") return Response.json({ error: "method_not_allowed" }, { status: 405, headers });
  const secret = deps.env("ASTIR_FEEDBACK_WORKER_SECRET");
  if (!secret || request.headers.get("x-feedback-worker-secret") !== secret) {
    return Response.json({ error: "unauthorized" }, { status: 401, headers });
  }
  const url = deps.env("SUPABASE_URL")?.replace(/\/$/, "");
  const key = deps.env("SUPABASE_SERVICE_ROLE_KEY");
  const emailKey = deps.env("ASTIR_FEEDBACK_RESEND_API_KEY");
  const from = deps.env("ASTIR_FEEDBACK_EMAIL_FROM");
  // Do not claim/retry jobs while the provider is not configured.
  if (!url || !key || !emailKey || !from) {
    return Response.json({ error: "not_configured" }, { status: 503, headers });
  }
  const serviceHeaders = { apikey: key, Authorization: `Bearer ${key}` };
  const rpc = async (name: string, body: unknown) => {
    const response = await deps.fetch(`${url}/rest/v1/rpc/${name}`, {
      method: "POST", headers: { ...serviceHeaders, "Content-Type": "application/json" },
      body: JSON.stringify(body), signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error("database_unavailable");
    return await response.json();
  };

  try {
    const jobs: Feedback[] = await rpc("claim_feedback_emails", {});
    let sent = 0;
    let retrying = 0;
    for (const job of jobs) {
      let emailID: string | null = null;
      let error: string | null = null;
      try {
        const attachments = [];
        for (const attachment of job.attachments) {
          const response = await deps.fetch(
            `${url}/storage/v1/object/feedback-attachments/${encodeURIComponent(job.id)}/${encodeURIComponent(attachment.filename)}`,
            { headers: serviceHeaders, signal: AbortSignal.timeout(10_000) },
          );
          if (!response.ok) throw new Error("attachment_unavailable");
          const bytes = await boundedBytes(response, maxBytes);
          if (bytes.length !== attachment.byte_size) throw new Error("attachment_unavailable");
          attachments.push({ filename: attachment.filename, content: base64(bytes), content_type: attachment.content_type });
        }
        const response = await deps.fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${emailKey}`, "Content-Type": "application/json",
            "Idempotency-Key": `astir-feedback/${job.id}`,
          },
          body: JSON.stringify(emailPayload(job, from, attachments)),
          signal: AbortSignal.timeout(15_000),
        });
        if (!response.ok) throw new Error("email_provider_unavailable");
        const receipt = await response.json();
        if (typeof receipt.id !== "string" || !receipt.id) throw new Error("email_provider_unavailable");
        emailID = receipt.id;
      } catch (failure) {
        // Coarse codes only. Never log feedback, audio, provider responses or keys.
        error = failure instanceof Error && failure.message === "attachment_unavailable"
          ? "attachment_unavailable" : "email_provider_unavailable";
      }
      const settled = await rpc("settle_feedback_email", {
        p_id: job.id, p_claim: job.claim_token, p_email_id: emailID, p_error: error,
      });
      if (settled && emailID) sent++;
      else retrying++;
    }
    return Response.json({ sent, retrying }, { headers });
  } catch {
    return Response.json({ error: "worker_unavailable" }, { status: 503, headers });
  }
}

export function emailPayload(job: Feedback, from: string, attachments: unknown[]) {
  return {
    from, to: [recipient], subject: "Astir feedback",
    // Plain text prevents user content from becoming HTML or headers.
    text: ["New feedback from Astir", "", job.body || "(Feedback is in the attachments.)", "",
      `Account: ${job.user_id}`, `App: ${job.app_version} (${job.build_number})`,
      `Submitted: ${job.submitted_at}`, `Report: ${job.id}`].join("\n"),
    attachments,
  };
}

async function boundedBytes(response: Response, limit: number): Promise<Uint8Array> {
  if (Number(response.headers.get("Content-Length")) > limit || !response.body) throw new Error("attachment_unavailable");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.length;
      if (size > limit) { await reader.cancel(); throw new Error("attachment_unavailable"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
  return result;
}

function base64(bytes: Uint8Array): string {
  let binary = "";
  for (let offset = 0; offset < bytes.length; offset += 8192) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  }
  return btoa(binary);
}
