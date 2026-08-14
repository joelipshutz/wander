import assert from "node:assert/strict";
import test from "node:test";

import {
  applyDashboard,
  assertDefinition,
  insights,
  sections,
} from "./posthog-product-dashboard.mjs";

test("dashboard contract has every requested lifecycle section", () => {
  assert.deepEqual(
    sections.map(({ title }) => title),
    ["Acquisition", "Activation", "Engagement", "Retention", "Referrals", "Monetization"],
  );
  assert.equal(sections.at(-1).insightKeys.length, 0);
  assert.equal(assertDefinition().insights, insights.length);
});

test("activation funnel exposes every onboarding step", () => {
  const funnel = insights.find(({ key }) => key === "onboarding-full-funnel");
  const steps = funnel.query.series
    .filter(({ event }) => event === "onboarding_step_completed")
    .map(({ properties }) => properties[0].value[0]);
  assert.deepEqual(steps, ["identity", "location", "contacts", "friends", "notifications"]);
});

test("engagement and retention queries use canonical events", () => {
  const humanNeeds = insights.find(({ key }) => key === "engagement-human-needs");
  assert.equal(humanNeeds.query.series[0].event, "engagement_action_performed");
  const retention = insights.find(({ key }) => key === "retention-activation-cohorts");
  assert.match(retention.query.query, /d1_percent/);
  assert.match(retention.query.query, /d30_percent/);
});

test("apply provisions an ordered dashboard through supported tile endpoints", async () => {
  const originalFetch = globalThis.fetch;
  const originalProjectID = process.env.WANDER_POSTHOG_PROJECT_ID;
  const originalAPIKey = process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
  process.env.WANDER_POSTHOG_PROJECT_ID = "170";
  process.env.WANDER_POSTHOG_PERSONAL_API_KEY = "test-only";

  const requests = [];
  const sectionTiles = [];
  const partialInsight = {
    id: 77,
    name: insights[0].name,
    tags: ["recme:managed"],
  };
  let insightWriteInFlight = false;
  const insightTiles = insights.map((definition, index) => ({
    id: 300 + index,
    insight: { tags: [`recme:iac:insight:${definition.key}`] },
  }));
  globalThis.fetch = async (url, options = {}) => {
    const parsed = new URL(url);
    const method = options.method || "GET";
    const body = options.body ? JSON.parse(options.body) : undefined;
    requests.push({ path: parsed.pathname, method, body });

    let responseBody;
    if (method === "GET" && parsed.pathname.endsWith("/insights/")) {
      responseBody = { results: [partialInsight], next: null };
    } else if (method === "GET" && parsed.pathname.endsWith("/dashboards/")) {
      responseBody = { results: [], next: null };
    } else if (method === "POST" && parsed.pathname.endsWith("/dashboards/")) {
      responseBody = { id: 42 };
    } else if (method === "POST" && parsed.pathname.endsWith("/insights/")) {
      assert.equal(insightWriteInFlight, false, "managed insight writes must be serialized");
      insightWriteInFlight = true;
      await new Promise((resolve) => setTimeout(resolve, 0));
      insightWriteInFlight = false;
      responseBody = { id: 100 + requests.filter(({ path }) => path.endsWith("/insights/")).length };
    } else if (method === "PATCH" && parsed.pathname.endsWith("/insights/77/")) {
      responseBody = { id: 77 };
    } else if (method === "GET" && parsed.pathname.endsWith("/dashboards/42/")) {
      responseBody = {
        id: 42,
        tiles: sectionTiles.length === sections.length ? [...sectionTiles, ...insightTiles] : [],
      };
    } else if (method === "POST" && parsed.pathname.endsWith("/create_text_tile/")) {
      responseBody = { id: 200 + sectionTiles.length, text: { body: body.body } };
      sectionTiles.push(responseBody);
    } else if (method === "POST" && parsed.pathname.endsWith("/reorder_tiles/")) {
      responseBody = { id: 42 };
    } else {
      throw new Error(`Unexpected request ${method} ${parsed.pathname}`);
    }
    return {
      ok: true,
      json: async () => responseBody,
      text: async () => JSON.stringify(responseBody),
    };
  };

  try {
    const result = await applyDashboard();
    assert.equal(result.dashboardID, 42);
    const dashboardCreate = requests.find(
      ({ path, method }) => path.endsWith("/dashboards/") && method === "POST",
    );
    assert.equal("tiles" in dashboardCreate.body, false);

    const insightCreates = requests.filter(
      ({ path, method }) => path.endsWith("/insights/") && method === "POST",
    );
    assert.equal(insightCreates.length, insights.length - 1);
    assert.ok(insightCreates.every(({ body }) => body.dashboards[0] === 42));
    const repairedInsight = requests.find(
      ({ path, method }) => path.endsWith("/insights/77/") && method === "PATCH",
    );
    assert.deepEqual(repairedInsight.body.tags, [
      "recme:managed",
      `recme:iac:insight:${insights[0].key}`,
    ]);

    const textCreates = requests.filter(({ path }) => path.endsWith("/create_text_tile/"));
    assert.equal(textCreates.length, sections.length);
    assert.ok(textCreates.every(({ body }) => body.layouts.sm.w === 12 && body.layouts.xs.w === 1));

    const reorder = requests.find(({ path }) => path.endsWith("/reorder_tiles/"));
    assert.equal(reorder.body.tile_order.length, sections.length + insights.length);
    assert.equal(reorder.body.tile_order[0], 200);
    assert.equal(reorder.body.layout, "preserve");
  } finally {
    globalThis.fetch = originalFetch;
    if (originalProjectID === undefined) delete process.env.WANDER_POSTHOG_PROJECT_ID;
    else process.env.WANDER_POSTHOG_PROJECT_ID = originalProjectID;
    if (originalAPIKey === undefined) delete process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
    else process.env.WANDER_POSTHOG_PERSONAL_API_KEY = originalAPIKey;
  }
});
