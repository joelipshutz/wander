import assert from "node:assert/strict";
import test from "node:test";

import {
  applyDashboard,
  assertDefinition,
  insights,
  sections,
  retentionSQL,
  clientProperties,
  verifyDashboard,
} from "./posthog-product-dashboard.mjs";

test("dashboard contract has every requested lifecycle section", () => {
  assert.deepEqual(
    sections.map(({ title }) => title),
    [
      "Acquisition",
      "Activation",
      "Engagement",
      "Retention",
      "Referrals",
      "Monetization",
      "Data Quality",
      "Notification Operations",
    ],
  );
  assert.equal(sections.find(({ title }) => title === "Monetization").insightKeys.length, 0);
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

test("notification operations includes delivery, opens, frequency, and aggregate histogram", () => {
  const section = sections.find(({ title }) => title === "Notification Operations");
  assert.equal(section.insightKeys.length, 5);

  const volume = insights.find(({ key }) => key === "notifications-accepted-volume");
  assert.equal(volume.query.series[0].event, "notification_delivery_processed");
  assert.equal(volume.query.series[0].math, "total");
  assert.equal(volume.query.series[0].properties[0].value[0], "sent");

  const openRate = insights.find(({ key }) => key === "notifications-open-rate");
  assert.match(openRate.query.query, /notification_opened/);
  assert.match(openRate.query.query, /delivery_channel = 'remote'/);

  const histogram = insights.find(({ key }) => key === "notifications-frequency-histogram");
  assert.equal(histogram.query.kind, "DataVisualizationNode");
  assert.equal(histogram.query.display, "ActionsBar");
  assert.match(histogram.query.source.query, /notification_frequency_bucket_snapshot/);
  assert.doesNotMatch(histogram.query.source.query, /distinct_id/);
});

test("apply provisions an ordered dashboard through supported tile endpoints", async () => {
  const originalFetch = globalThis.fetch;
  const originalProjectID = process.env.WANDER_POSTHOG_PROJECT_ID;
  const originalAPIKey = process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
  process.env.WANDER_POSTHOG_PROJECT_ID = "557259";
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


test("core activation does not require an optional follow or count raw save/check-in twice", () => {
  const activation = insights.find(({ key }) => key === "activation-first-value");
  assert.deepEqual(activation.query.series.map(({ event }) => event), ["onboarding_completed", "core_action_performed"]);
  const core = insights.find(({ key }) => key === "engagement-core-actions");
  assert.deepEqual(core.query.series.map(({ event }) => event), ["core_action_performed"]);
});

test("retention joins merged people and separately matures every horizon", () => {
  const query = retentionSQL("core_action_performed", "core_action_performed");
  assert.match(query, /cohort.person_id = return_events.person_id/);
  assert.doesNotMatch(query, /distinct_id/);
  for (const day of [1, 7, 14, 30]) {
    assert.ok(query.includes(`started_at + interval ${day + 1} day <= now()`));
    assert.ok(query.includes(`as d${day}_eligible`));
    assert.ok(query.includes(`as d${day}_returned`));
    assert.ok(query.includes(`as d${day}_percent`));
    assert.ok(query.includes(`timestamp >= cohort.started_at + interval ${day} day`));
    assert.ok(query.includes(`timestamp < cohort.started_at + interval ${day + 1} day`));
  }
  assert.match(query, /nullIf\(countIf/);
});

test("behavioral tiles require the new production baseline while server metrics remain aggregate", () => {
  for (const insight of insights) {
    if (["TrendsQuery", "FunnelsQuery"].includes(insight.query.kind) && !insight.key.startsWith("notifications-")) {
      assert.deepEqual(insight.query.properties, clientProperties, insight.key);
    }
  }
  for (const key of ["engagement-actions", "retention-activation-cohorts", "retention-core-cohorts"]) {
    const sql = insights.find(item => item.key === key).query.query;
    assert.match(sql, /analytics_schema_version = '3'/);
    assert.match(sql, /analytics_environment = 'production'/);
    assert.match(sql, /internal_or_test_user/);
  }
  const inventory = insights.find(item => item.key === "instrumentation-coverage").query.query;
  assert.doesNotMatch(inventory, /analytics_schema_version =/);
});

test("every dashboard event is backed by the client or aggregate server contract", async () => {
  const { readFile } = await import("node:fs/promises");
  const swift = await readFile(new URL("../Wander/Services/AnalyticsEvent.swift", import.meta.url), "utf8");
  const server = new Set(["notification_delivery_processed", "notification_frequency_snapshot", "notification_frequency_bucket_snapshot"]);
  const names = new Set([...swift.matchAll(/static let \w+ = "([^"\n]+)"/g)].map(match => match[1]));
  for (const insight of insights) {
    for (const series of insight.query.series || []) assert.ok(names.has(series.event) || server.has(series.event), series.event);
  }
});


test("live verification refuses another project and fails on missing managed coverage", async () => {
  const oldID = process.env.WANDER_POSTHOG_PROJECT_ID;
  const oldKey = process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
  const oldFetch = globalThis.fetch;
  try {
    process.env.WANDER_POSTHOG_PROJECT_ID = "another-project";
    await assert.rejects(verifyDashboard(), /belong to Astir/);
    process.env.WANDER_POSTHOG_PROJECT_ID = "557259";
    process.env.WANDER_POSTHOG_PERSONAL_API_KEY = "test-only";
    globalThis.fetch = async url => ({ ok: true, json: async () =>
      new URL(url).pathname.endsWith("/dashboards/")
        ? { results: [{ id: 42, tags: ["recme:iac:dashboard:product-funnel"] }] }
        : { id: 42, tiles: [] }
    });
    await assert.rejects(verifyDashboard(), /Missing managed insight/);
  } finally {
    globalThis.fetch = oldFetch;
    if (oldID === undefined) delete process.env.WANDER_POSTHOG_PROJECT_ID;
    else process.env.WANDER_POSTHOG_PROJECT_ID = oldID;
    if (oldKey === undefined) delete process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
    else process.env.WANDER_POSTHOG_PERSONAL_API_KEY = oldKey;
  }
});
