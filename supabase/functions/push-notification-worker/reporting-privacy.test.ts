import { handleRequest, NOTIFICATION_ANALYTICS_AUDIENCE } from "./index.ts";

Deno.test("reporting exports aggregate counts without claiming pushes or fetching private audit rows", async () => {
  const originalFetch = globalThis.fetch;
  const fixtureEnvironment = {
    SUPABASE_URL: "https://fixture.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "fixture-service",
    WANDER_WORKER_SECRET: "fixture-worker",
    WANDER_POSTHOG_PROJECT_TOKEN: "fixture-project",
  };
  const previous = Object.fromEntries(Object.keys(fixtureEnvironment).map(key => [key, Deno.env.get(key)]));
  for (const [key, value] of Object.entries(fixtureEnvironment)) Deno.env.set(key, value);
  try {
    for (const rejectCapture of [false, true]) {
      let queries = 0;
      let captures = 0;
      globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
        const url = String(input);
        if (url.endsWith("/rest/v1/rpc/notification_operations_snapshot")) {
          queries += 1;
          return Promise.resolve(Response.json({
            analytics_audience: NOTIFICATION_ANALYTICS_AUDIENCE,
            window_days: 30, eligible_recipient_count: 2, accepted_notification_count: 3,
            average_per_recipient: 1.5, p50_per_recipient: 1, p90_per_recipient: 2,
            max_per_recipient: 2, histogram: [],
            // Unexpected fields must never flow into the exported aggregate.
            user_id: "private-recipient", title: "private-copy", body: "private-copy",
          }));
        }
        if (url !== "https://us.i.posthog.com/batch/") throw new Error("Reporting attempted a non-aggregate operation");
        captures += 1;
        const body = String(init?.body);
        if (body.includes("private-recipient") || body.includes("private-copy")) throw new Error("Reporting leaked private fields");
        const batch = JSON.parse(body).batch;
        if (batch.length !== 1 || batch[0].properties.distinct_id !== "notification_operations") throw new Error("Non-aggregate analytics exported");
        return Promise.resolve(new Response("{}", { status: rejectCapture ? 500 : 200 }));
      }) as typeof fetch;
      const response = await handleRequest(new Request("https://fixture/report", {
        method: "POST", headers: { "x-wander-worker-secret": "fixture-worker" },
        body: JSON.stringify({ analytics_snapshot: true }),
      }));
      if (response.status !== (rejectCapture ? 502 : 200) || queries !== 1 || captures !== 1) throw new Error("Invalid reporting outcome");
    }
  } finally {
    globalThis.fetch = originalFetch;
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) Deno.env.delete(key); else Deno.env.set(key, value);
    }
  }
});
