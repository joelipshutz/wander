import {
  classifyAPNsFailure,
  notificationDeliveryAnalyticsEvent,
  notificationFrequencyAnalyticsEvents,
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

Deno.test("delivery analytics exports coarse outcomes without recipient or notification content", () => {
  const analyticsEvent = notificationDeliveryAnalyticsEvent(
    {
      event_id: "10000000-0000-0000-0000-000000000001",
      claim_token: "20000000-0000-0000-0000-000000000001",
      recipient_user_id: "private_recipient",
      actor_user_id: "private_actor",
      notification_type: "shared_visit",
      title: "Private title",
      body: "Private body",
      deeplink_url: "recme://places/private-place",
      data: { place_id: "private-place" },
      attempt_count: 2,
      tokens: [{
        id: "30000000-0000-0000-0000-000000000001",
        device_token: "a".repeat(64),
        environment: "production",
        app_bundle_id: "com.grayline.wander",
      }],
    },
    {
      status: "sent",
      accepted_count: 1,
      retryable_count: 0,
      permanent_token_failure_count: 1,
      permanent_event_failure_count: 0,
    },
  );

  assertEquals(analyticsEvent.event, "notification_delivery_processed");
  assertEquals(
    analyticsEvent.properties.distinct_id,
    "notification_operations",
  );
  assertEquals(analyticsEvent.properties.delivery_outcome, "sent");
  assertEquals(analyticsEvent.properties.failure_category, "permanent_token");
  assertEquals(analyticsEvent.properties.accepted_token_count, 1);
  const serialized = JSON.stringify(analyticsEvent);
  for (
    const privateValue of [
      "private_recipient",
      "private_actor",
      "Private title",
      "Private body",
      "private-place",
      "recme://",
      "a".repeat(64),
    ]
  ) {
    if (serialized.includes(privateValue)) {
      throw new Error(`Analytics leaked private value: ${privateValue}`);
    }
  }
});

Deno.test("delivery analytics replaces unexpected notification types", () => {
  const analyticsEvent = notificationDeliveryAnalyticsEvent(
    {
      event_id: "10000000-0000-0000-0000-000000000001",
      claim_token: "20000000-0000-0000-0000-000000000001",
      recipient_user_id: "private_recipient",
      notification_type: "customer-name-that-must-not-leak",
      title: "Private title",
      body: "Private body",
      data: {},
      tokens: [],
    },
    { status: "failed", permanent_event_failure_count: 1 },
  );

  assertEquals(analyticsEvent.properties.notification_type, "unknown");
});

Deno.test("delivery analytics allowlists every reservation and client reminder type", () => {
  for (
    const notificationType of [
      "calendar_reservation_live",
      "calendar_reservation_follow_up",
      "import_finished",
      "save_streak_reminder",
      "wanna_go_reminder",
    ]
  ) {
    const analyticsEvent = notificationDeliveryAnalyticsEvent(
      {
        event_id: "10000000-0000-0000-0000-000000000001",
        claim_token: "20000000-0000-0000-0000-000000000001",
        recipient_user_id: "private_recipient",
        notification_type: notificationType,
        title: "Private title",
        body: "Private body",
        data: {},
        tokens: [],
      },
      { status: "sent", accepted_count: 1 },
    );

    assertEquals(
      analyticsEvent.properties.notification_type,
      notificationType,
    );
  }
});

Deno.test("frequency analytics exposes summary and complete aggregate histogram only", () => {
  const events = notificationFrequencyAnalyticsEvents({
    window_days: 30,
    eligible_recipient_count: 2,
    accepted_notification_count: 4,
    average_per_recipient: 2,
    p50_per_recipient: 1,
    p90_per_recipient: 3,
    max_per_recipient: 3,
    histogram: [
      { bucket_order: 0, bucket: "0", recipient_count: 1 },
      { bucket_order: 1, bucket: "1", recipient_count: 0 },
      { bucket_order: 2, bucket: "2-3", recipient_count: 1 },
      { bucket_order: 3, bucket: "4-7", recipient_count: 0 },
      { bucket_order: 4, bucket: "8-14", recipient_count: 0 },
      { bucket_order: 5, bucket: "15-29", recipient_count: 0 },
      { bucket_order: 6, bucket: "30+", recipient_count: 0 },
    ],
  });

  assertEquals(events.length, 8);
  assertEquals(events[0].event, "notification_frequency_snapshot");
  assertEquals(
    events.slice(1).map((event) => event.properties.bucket),
    ["0", "1", "2-3", "4-7", "8-14", "15-29", "30+"],
  );
  if (JSON.stringify(events).includes("user_")) {
    throw new Error(
      "Frequency analytics must not contain recipient identifiers",
    );
  }
});
