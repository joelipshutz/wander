import {
  classifyAPNsFailure,
  PushEvent,
  PushToken,
  sendToToken,
} from "./index.ts";

function assertEquals(
  actual: unknown,
  expected: unknown,
  message?: string,
): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      message ??
        `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("APNs failures distinguish bad tokens from bad events and retryable outages", () => {
  assertEquals(
    classifyAPNsFailure(410, "Unregistered"),
    "permanent_token_failure",
  );
  assertEquals(
    classifyAPNsFailure(400, "BadDeviceToken"),
    "permanent_token_failure",
  );
  assertEquals(
    classifyAPNsFailure(400, "PayloadTooLarge"),
    "permanent_event_failure",
  );
  assertEquals(
    classifyAPNsFailure(403, "InvalidProviderToken"),
    "permanent_event_failure",
  );
  assertEquals(
    classifyAPNsFailure(429, "TooManyRequests"),
    "retryable_failure",
  );
  assertEquals(
    classifyAPNsFailure(503, "ServiceUnavailable"),
    "retryable_failure",
  );
});

Deno.test("APNs requests include collapse and request IDs and retain Apple's response ID", async () => {
  const event: PushEvent = {
    event_id: "10000000-0000-0000-0000-000000000001",
    claim_token: "20000000-0000-0000-0000-000000000001",
    recipient_user_id: "user_joe",
    notification_type: "shared_visit",
    title: "Shared visit",
    body: "Ryan saved a place with you.",
    data: {},
    tokens: [],
  };
  const token: PushToken = {
    id: "30000000-0000-0000-0000-000000000001",
    device_token: "a".repeat(64),
    environment: "production",
    app_bundle_id: "com.grayline.wander",
  };
  let capturedHeaders: Headers | undefined;
  const result = await sendToToken(
    event,
    token,
    { keyId: "key", teamId: "team", privateKeyPEM: "unused" },
    "jwt",
    async (_input, init) => {
      capturedHeaders = new Headers(init?.headers);
      return new Response(null, {
        status: 200,
        headers: { "apns-id": "40000000-0000-0000-0000-000000000001" },
      });
    },
    "50000000-0000-0000-0000-000000000001",
  );

  assertEquals(capturedHeaders?.get("apns-collapse-id"), event.event_id);
  assertEquals(
    capturedHeaders?.get("apns-id"),
    "50000000-0000-0000-0000-000000000001",
  );
  assertEquals(result.status, "accepted");
  assertEquals(result.apns_id, "40000000-0000-0000-0000-000000000001");
});

Deno.test("transport failures remain retryable without deactivating the token", async () => {
  const result = await sendToToken(
    {
      event_id: "10000000-0000-0000-0000-000000000001",
      claim_token: "20000000-0000-0000-0000-000000000001",
      recipient_user_id: "user_joe",
      notification_type: "followed_place_visit",
      title: "Ryan saved a place",
      body: "Bar Nido",
      data: {},
      tokens: [],
    },
    {
      id: "30000000-0000-0000-0000-000000000001",
      device_token: "a".repeat(64),
      environment: "sandbox",
      app_bundle_id: "com.grayline.wander",
    },
    { keyId: "key", teamId: "team", privateKeyPEM: "unused" },
    "jwt",
    () => Promise.reject(new Error("network_down")),
  );

  assertEquals(result.status, "retryable_failure");
  assertEquals(result.error_message, "network_down");
});
