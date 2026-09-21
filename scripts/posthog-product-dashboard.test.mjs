import assert from "node:assert/strict";
import test from "node:test";

import {
  applyDashboard,
  assertDefinition,
  firstDayFollowSQL,
  activationSQL,
  insights,
  sections,
  retentionSQL,
  clientProperties,
  verifyDashboard,
  staffExclusionSQL,
  INTERNAL_USER_IDS,
  withStaffExclusions,
  appEntrySQL,
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
  assert.deepEqual(funnel.query.series.map(step => step.custom_name), [
    "First app open", "Started sign-up", "Started profile setup", "Profile details saved",
    "Location step completed", "Contacts step completed", "Follow suggestions completed",
    "Notifications step completed", "Onboarding completed",
  ]);
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

test("notification clicks and entry sources live under Engagement with external production filters", () => {
  const engagement = sections.find(({ title }) => title === "Engagement").insightKeys;
  for (const key of ["engagement-notification-clicks", "engagement-notification-click-details", "engagement-entry-lifecycle", "engagement-entry-source", "engagement-entry-source-details"]) {
    assert.ok(engagement.includes(key));
  }
  const clicks = insights.find(({ key }) => key === "engagement-notification-clicks").query;
  assert.equal(clicks.series[0].event, "notification_opened");
  assert.equal(clicks.series[0].math, "total");
  assert.equal(clicks.breakdownFilter.breakdown, "notification_type");
  assert.ok(clicks.breakdownFilter.breakdown_limit >= 18, "Keep all 17 known types plus unknown visible");
  assert.deepEqual(clicks.properties, clientProperties);
  const sessions = insights.find(({ key }) => key === "engagement-entry-lifecycle").query;
  assert.equal(sessions.breakdownFilter.breakdown, "session_source");
  assert.equal(sessions.series[0].math, "total");
  for (const sql of [appEntrySQL(), appEntrySQL({ daily: true })]) {
    assert.ok(sql.includes("entries left join sources on entries.entry_id = sources.entry_id"));
    assert.equal(sql.split(staffExclusionSQL).length - 1, 2);
    assert.equal(sql.split("analytics_environment = 'production'").length - 1, 2);
    assert.match(sql, /group by entry_id/);
    assert.match(sql, /direct_or_unknown/);
    assert.doesNotMatch(sql, /app_session_started|notification_opened/);
  }
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
  let transientReadFailure = true;
  const insightTiles = insights.map((definition, index) => ({
    id: 300 + index,
    insight: { tags: [`recme:iac:insight:${definition.key}`] },
  }));
  globalThis.fetch = async (url, options = {}) => {
    const parsed = new URL(url);
    const method = options.method || "GET";
    const body = options.body ? JSON.parse(options.body) : undefined;
    requests.push({ path: parsed.pathname, method, body });

    if (method === "GET" && parsed.pathname.endsWith("/insights/") && transientReadFailure) {
      transientReadFailure = false;
      return { ok: false, status: 503, text: async () => "temporary upstream failure" };
    }
    let responseBody;
    if (method === "GET" && parsed.pathname.endsWith("/insights/")) {
      responseBody = { results: [partialInsight, {id: 88, tags: ["recme:iac:insight:activation-first-day-follows-per-user"], dashboards: [42, 99]}], next: null };
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
    } else if (method === "PATCH" && parsed.pathname.endsWith("/insights/88/")) {
      assert.deepEqual(body.dashboards, [99]);
      assert.ok(body.query.source.query.includes(staffExclusionSQL));
      assert.equal(body.deleted, undefined);
      responseBody = {id: 88};
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
    assert.ok(requests.some(r => r.path.endsWith("/insights/88/") && r.method === "PATCH"));
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


test("activation includes a successful follow OR core action, including during onboarding", () => {
  const activation = insights.find(({ key }) => key === "activation-first-value");
  assert.equal(activation.query.source.query, activationSQL());
  assert.match(activationSQL(), /event = 'onboarding_completed'/);
  assert.match(activationSQL(), /event = 'core_action_performed'\s+or \(event = 'follow_created' and properties.outcome = 'succeeded'/);
  assert.match(activationSQL(), /cohort left join actions on cohort.person_id = actions.person_id/);
  assert.match(activationSQL(), /completed_at - interval 14 day/);
  assert.match(activationSQL(), /completed_at \+ interval 14 day/);
  assert.match(activationSQL(), /activated_users \/ nullIf\(onboarded_users, 0\)/);
  const core = insights.find(({ key }) => key === "engagement-core-actions");
  assert.deepEqual(core.query.series.map(({ event }) => event), ["core_action_performed"]);
});

test("first-day follow cohorts preserve zeroes, mature denominators, and exact 24-hour boundaries", () => {
  const sql = firstDayFollowSQL();
  assert.match(sql, /event = 'onboarding_started'/);
  assert.match(sql, /min\(timestamp\) as started_at/);
  assert.match(sql, /group by person_id\s+having started_at/);
  assert.match(sql, /event = 'follow_created' and properties.outcome = 'succeeded'/);
  assert.match(sql, /cohort left join follow_events on cohort.person_id = follow_events.person_id/);
  assert.match(sql, /timestamp >= cohort.started_at/);
  assert.match(sql, /timestamp < cohort.started_at \+ interval 24 hour/);
  assert.match(sql, /started_at \+ interval 24 hour <= now\(\)/);
  assert.match(sql, /if\(eligible_users = 0, null, sumIf/);
  assert.match(sql, /users_who_followed \/ nullIf\(eligible_users, 0\)/);
  assert.match(sql, /first_day_follows \/ nullIf\(eligible_users, 0\)/);
  assert.doesNotMatch(sql, /followed_count|onboarding_completed/);
  assert.match(sql, /source\), ''\) != 'signup_default'/);
  for (const filter of ["analytics_schema_version = '3'", "analytics_environment = 'production'", "person_id not in cohort 481950", "internal_or_test_user"]) {
    assert.equal(sql.split(filter).length - 1, 2, `Both cohort and follow events need ${filter}`);
  }
});

test("first-day follow dashboard charts share a cohort query and expose rate and per-user mean without a duplicate average tile", () => {
  const section = sections.find(({ title }) => title === "Activation");
  for (const [key, column] of [
    ["activation-first-day-follow-rate", "follow_rate_percent"],
    ["activation-first-day-follow-count", "follows_per_user"],
  ]) {
    assert.ok(section.insightKeys.includes(key));
    const { query } = insights.find(item => item.key === key);
    assert.equal(query.source.query, firstDayFollowSQL());
    assert.equal(query.display, "ActionsBar");
    assert.equal(query.chartSettings.showValuesOnSeries, true);
    assert.equal(query.chartSettings.xAxis.column, "cohort_day");
    assert.deepEqual(query.chartSettings.yAxis, [{ column }]);
  }
});

test("retention joins merged people and separately matures every horizon", () => {
  const query = retentionSQL("core_action_performed", "core_action_performed");
  assert.match(query, /cohort.person_id = return_events.person_id/);
  assert.ok(query.includes(staffExclusionSQL));
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
    for (const series of insight.query.series || []) {
      for (const node of series.nodes || [series]) assert.ok(names.has(node.event) || server.has(node.event), node.event);
    }
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


test("every person-level tile explicitly excludes both staff accounts and merged anonymous activity", () => {
  for (const id of INTERNAL_USER_IDS) assert.ok(staffExclusionSQL.includes(id));
  assert.match(staffExclusionSQL, /person_id not in/);
  assert.match(staffExclusionSQL, /select person_id from events where distinct_id in/);
  for (const insight of insights.filter(item => !item.key.startsWith("notifications-"))) {
    if (insight.query.series) {
      assert.ok(insight.query.properties.some(p => p.type === "hogql" && p.key === staffExclusionSQL), insight.key);
    } else {
      assert.ok((insight.query.source?.query || insight.query.query).includes(staffExclusionSQL), insight.key);
    }
  }
  assert.ok(insights.find(item => item.key === "notifications-open-rate").query.query.includes(staffExclusionSQL));
  assert.ok(!sections.flatMap(section => section.insightKeys).includes("activation-first-day-follows-per-user"));
});


test("auto-follow provenance is excluded from every client metric and legacy mixed recipient aggregates stay out", () => {
  assert.ok(clientProperties.some(p => p.key === "source" && p.operator === "is_not" && p.value[0] === "signup_default"));
  for (const insight of insights.filter(item => !item.key.startsWith("notifications-"))) {
    const sql = insight.query.source?.query || insight.query.query;
    if (sql) assert.ok(sql.includes("coalesce(toString(properties.source), '') != 'signup_default'"), insight.key);
  }
  for (const insight of insights.filter(item => item.key.startsWith("notifications-"))) {
    if (insight.query.series) {
      assert.ok(insight.query.properties.some(p => p.key === "analytics_audience" && p.value[0] === "external_recipients_v1"));
    } else {
      assert.ok((insight.query.source?.query || insight.query.query).includes("analytics_audience = 'external_recipients_v1'"), insight.key);
    }
  }
  assert.match(insights.find(item => item.key === "notifications-open-rate").query.query, /timestamp >= \(select reporting_started_at from delivery\)/);
});


test("existing-insight maintenance preserves scope and is idempotent", () => {
  const original = {kind: "InsightVizNode", source: {
    kind: "TrendsQuery", series: [{kind:"EventsNode", event:"$pageview"}],
    properties: [{key:"existing", type:"event", value:["keep"], operator:"exact"}],
    filterTestAccounts: false, interval: "week",
  }};
  const result = withStaffExclusions(original);
  assert.deepEqual(result.source.properties.slice(0, 1), original.source.properties);
  assert.equal(result.source.properties.length, 3);
  assert.equal(result.source.filterTestAccounts, false);
  assert.deepEqual(result.source.series, original.source.series);
  assert.deepEqual(withStaffExclusions(result), result);
  assert.equal(original.source.properties.length, 1);
  assert.equal(withStaffExclusions({kind:"HogQLQuery",query:"select 1"}), null);
  assert.throws(() => withStaffExclusions({kind:"TrendsQuery",properties:{type:"OR",values:[]}}), /Review grouped/);
});
