import assert from "node:assert/strict";
import test from "node:test";
import { handleRequest, emailPayload } from "./handler.ts";

const job = {
  id: "7d234dae-5653-4782-9a91-897094112234", user_id: "user_feedback_test",
  body: "Feature request: more parks! <script>no HTML</script>", attachments: [],
  app_version: "1.0", build_number: "176", submitted_at: "2026-09-19T03:30:00Z", claim_token: "test-claim",
};
const configuration = {
  ASTIR_FEEDBACK_WORKER_SECRET: "test-worker-secret", SUPABASE_URL: "https://example.supabase.co",
  SUPABASE_SERVICE_ROLE_KEY: "test-service-key", ASTIR_FEEDBACK_RESEND_API_KEY: "test-email-key",
  ASTIR_FEEDBACK_EMAIL_FROM: "Astir <feedback@example.test>",
};
const request = () => new Request("https://example.test", {
  method: "POST", headers: { "x-feedback-worker-secret": "test-worker-secret" },
});
test("rejects client requests before touching storage or email", async () => {
  let called = false;
  const response = await handleRequest(new Request("https://example.test", { method: "POST" }), {
    env: (key) => configuration[key], fetch: async () => { called = true; },
  });
  assert.equal(response.status, 401); assert.equal(called, false);
});
test("missing provider configuration leaves durable jobs unclaimed", async () => {
  let called = false;
  const response = await handleRequest(request(), {
    env: (key) => key === "ASTIR_FEEDBACK_RESEND_API_KEY" ? undefined : configuration[key],
    fetch: async () => { called = true; },
  });
  assert.equal(response.status, 503); assert.equal(called, false);
});
test("uses fixed recipient, plain text, and stable idempotent email payload", () => {
  const payload = emailPayload(job, configuration.ASTIR_FEEDBACK_EMAIL_FROM, []);
  assert.deepEqual(payload.to, ["admin@HotchkissTechnologies.com"]);
  assert.equal(payload.subject, "Astir feedback"); assert.equal(payload.html, undefined);
  assert.ok(payload.text.includes(job.body));
  assert.deepEqual(payload, emailPayload({ ...job, claim_token: "retry-claim" }, configuration.ASTIR_FEEDBACK_EMAIL_FROM, []));
});
test("delivers JPEG and voice bytes as attachments and settles only provider acceptance", async () => {
  const deliveries = []; const settlements = [];
  const photosAndVoice = { ...job, attachments: [
    { filename: "photo.jpg", content_type: "image/jpeg", byte_size: 3 },
    { filename: "voice.m4a", content_type: "audio/mp4", byte_size: 3 },
  ] };
  const response = await handleRequest(request(), { env: (key) => configuration[key], fetch: async (url, init) => {
    if (url.endsWith("claim_feedback_emails")) return Response.json([photosAndVoice]);
    if (url.includes("/storage/")) return new Response(new Uint8Array([1, 2, 3]));
    if (url === "https://api.resend.com/emails") {
      deliveries.push(init); return Response.json({ id: "email-test" });
    }
    settlements.push(JSON.parse(init.body)); return Response.json(true);
  } });
  assert.deepEqual(await response.json(), { sent: 1, retrying: 0 });
  assert.equal(deliveries[0].headers["Idempotency-Key"], `astir-feedback/${job.id}`);
  assert.equal(JSON.parse(deliveries[0].body).attachments[1].content, "AQID");
  assert.equal(settlements[0].p_email_id, "email-test");
});
for (const failure of ["provider", "missing_attachment", "oversize_attachment", "timeout"]) {
  test(`${failure} preserves queued work without reporting sent`, async () => {
    const settlements = []; let sent = false;
    const failedJob = { ...job, attachments: failure.includes("attachment") ? [{ filename: "photo.jpg", content_type: "image/jpeg", byte_size: 3 }] : [] };
    const response = await handleRequest(request(), { env: (key) => configuration[key], fetch: async (url, init) => {
      if (url.endsWith("claim_feedback_emails")) return Response.json([failedJob]);
      if (url.includes("/storage/")) return failure === "oversize_attachment"
        ? new Response(new Uint8Array(2 * 1024 * 1024 + 1)) : new Response("", { status: 404 });
      if (url === "https://api.resend.com/emails") {
        sent = true;
        if (failure === "timeout") throw new DOMException("timeout", "TimeoutError");
        return new Response("private provider error", { status: 429 });
      }
      settlements.push(JSON.parse(init.body)); return Response.json(true);
    } });
    assert.deepEqual(await response.json(), { sent: 0, retrying: 1 });
    assert.equal(settlements[0].p_email_id, null);
    assert.ok(["attachment_unavailable", "email_provider_unavailable"].includes(settlements[0].p_error));
    if (failure.includes("attachment")) assert.equal(sent, false);
  });
}
test("lost settlement causes retry with the same provider key", async () => {
  const keys = [];
  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await handleRequest(request(), { env: (key) => configuration[key], fetch: async (url, init) => {
      if (url.endsWith("claim_feedback_emails")) return Response.json([{ ...job, claim_token: `claim-${attempt}` }]);
      if (url === "https://api.resend.com/emails") { keys.push(init.headers["Idempotency-Key"]); return Response.json({ id: "one-email" }); }
      return attempt === 0 ? new Response("", { status: 500 }) : Response.json(true);
    } });
    assert.equal(response.status, attempt === 0 ? 503 : 200);
  }
  assert.equal(keys[0], keys[1]);
});
