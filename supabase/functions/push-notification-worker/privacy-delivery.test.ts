import { processEvent, type PushEvent } from "./index.ts";

const claimed: PushEvent = {
  event_id: "10000000-0000-0000-0000-000000000001",
  claim_token: "20000000-0000-0000-0000-000000000001",
  recipient_user_id: "fixture",
  notification_type: "shared_visit",
  title: "Cached private title",
  body: "Cached private body",
  data: { note: "private" },
  tokens: [{
    id: "token", device_token: "a".repeat(64), environment: "sandbox",
    app_bundle_id: "com.grayline.wander",
  }],
};

Deno.test("revoked sources and stale claims never reach APNs or settlement", async () => {
  // No network or environment permission is granted: either side effect fails.
  for (const result of [null, { ...claimed, claim_token: "stale" }, { ...claimed, event_id: "other" }]) {
    const processed = await processEvent(claimed,
      { keyId: "fixture", teamId: "fixture", privateKeyPEM: "unused" }, "jwt",
      async () => result);
    if (processed.status !== "skipped" || processed.reason !== "source_unavailable_or_stale_claim") {
      throw new Error("Denied or stale source was not skipped");
    }
  }
});

Deno.test("delivery uses the reauthorized envelope instead of the earlier private claim", async () => {
  const fresh = { ...claimed, title: "New activity on Astir", body: "Open Astir to view.", data: {} };
  let deliveries = 0;
  await processEvent(claimed, null, null, async () => fresh, async (event) => {
    deliveries += 1;
    if (event !== fresh) throw new Error("Delivery used an obsolete envelope");
    return { event_id: event.event_id, status: "sent" };
  });
  if (deliveries !== 1) throw new Error("Authorized event was not delivered exactly once");
});
