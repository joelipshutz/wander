#!/usr/bin/env node

import { pathToFileURL } from "node:url";

const DASHBOARD_TAG = "recme:iac:dashboard:product-funnel";
const INSIGHT_TAG_PREFIX = "recme:iac:insight:";
const MANAGED_TAG = "recme:managed";
const DEFAULT_HOST = "https://us.posthog.com";

// Schema 3 is the launch measurement baseline. Old unclassified traffic is
// visible in Data Quality, never silently mixed with production cohorts.
const clientProperties = [
  { key: "analytics_schema_version", value: ["3"], operator: "exact", type: "event" },
  { key: "analytics_environment", value: ["production"], operator: "exact", type: "event" },
  { key: "$internal_or_test_user", value: ["true"], operator: "is_not", type: "person" },
  { key: "id", value: 481950, operator: "not_in", type: "cohort" },
];
const productionSQL = `properties.analytics_schema_version = '3'
  and properties.analytics_environment = 'production'
  and person_id not in cohort 481950
  and coalesce(toString(person.properties.$internal_or_test_user), 'false') != 'true'`;
const isServerSeries = (series) => series.every(({ event }) => event.startsWith("notification_delivery_") || event.startsWith("notification_frequency_"));

const event = (name, properties = []) => ({
  kind: "EventsNode",
  event: name,
  math: "dau",
  properties,
});

const eventTotal = (name, properties = []) => ({
  kind: "EventsNode",
  event: name,
  math: "total",
  properties,
});

const property = (key, value) => ({
  key,
  value: [value],
  operator: "exact",
  type: "event",
});

const trends = (series, { breakdown, interval = "day" } = {}) => ({
  kind: "TrendsQuery",
  series,
  properties: isServerSeries(series) ? [] : clientProperties,
  interval,
  dateRange: { date_from: "-90d", date_to: null, explicitDate: false },
  trendsFilter: { display: "ActionsLineGraph", showLegend: true },
  breakdownFilter: breakdown
    ? { breakdown, breakdown_type: "event", breakdown_limit: 12 }
    : undefined,
  filterTestAccounts: true,
});

const funnel = (series) => ({
  kind: "FunnelsQuery",
  series,
  properties: clientProperties,
  dateRange: { date_from: "-90d", date_to: null, explicitDate: false },
  funnelsFilter: {
    funnelVizType: "steps",
    funnelOrderType: "ordered",
    layout: "horizontal",
    funnelWindowInterval: 14,
    funnelWindowIntervalUnit: "day",
  },
  filterTestAccounts: true,
});

const hogql = (query) => ({ kind: "HogQLQuery", query });

const hogqlBar = (query, xAxis, yAxis) => ({
  kind: "DataVisualizationNode",
  source: hogql(query),
  display: "ActionsBar",
  chartSettings: {
    xAxis: { column: xAxis },
    yAxis: [{ column: yAxis }],
    showValuesOnSeries: true,
    showLegend: false,
  },
});

// Exact elapsed-day windows. Only fully observed users enter each denominator;
// an immature cohort yields null rather than an invented zero. person_id joins
// merged anonymous/account identities; distinct_id would split those people.
function retentionSQL(startEvent, returnEvent) {
  const days = [1, 7, 14, 30];
  return `with cohort as (
  select person_id, min(timestamp) as started_at
  from events
  where event = '${startEvent}' and ${productionSQL}
  group by person_id
  having started_at >= now() - interval 90 day
), return_events as (
  select person_id, timestamp from events
  where event = '${returnEvent}' and ${productionSQL}
), observed as (
  select cohort.person_id, cohort.started_at,
    ${days.map(d => `max(if(return_events.timestamp >= cohort.started_at + interval ${d} day and return_events.timestamp < cohort.started_at + interval ${d + 1} day, 1, 0)) as d${d}`).join(",\n    ")}
  from cohort left join return_events on cohort.person_id = return_events.person_id
    and return_events.timestamp > cohort.started_at
    and return_events.timestamp < cohort.started_at + interval 31 day
  group by cohort.person_id, cohort.started_at
)
select toStartOfWeek(started_at) as cohort_week, count() as cohort_users,
  ${days.map(d => `countIf(started_at + interval ${d + 1} day <= now()) as d${d}_eligible,
  sumIf(d${d}, started_at + interval ${d + 1} day <= now()) as d${d}_returned,
  round(100.0 * sumIf(d${d}, started_at + interval ${d + 1} day <= now()) / nullIf(countIf(started_at + interval ${d + 1} day <= now()), 0), 1) as d${d}_percent`).join(",\n  ")}
from observed group by cohort_week order by cohort_week desc`;
}

const insights = [
  {
    key: "acquisition-first-opens", name: "Acquisition — first observed opens",
    description: "Unique people with an install-local first-open marker. Reinstalls and historical upgrades can emit again; this is not App Store download attribution. Schema 3 production baseline.",
    query: trends([event("app_first_opened")], { breakdown: "acquisition_source" }),
  },
  {
    key: "acquisition-campaign-links", name: "Acquisition — tagged link opens",
    description: "Known tagged links by sanitized UTM source. No full URL; no deferred install attribution.",
    query: trends([event("acquisition_link_opened", [property("has_campaign", "true")])], { breakdown: "utm_source" }),
  },
  {
    key: "onboarding-full-funnel", name: "Onboarding — new-install sign-up funnel",
    description: "Strict first-open → sign-up → identity/photo → permissions → friends → completion, within 14 days. A skipped permission still completes that step. Resumed onboarding is diagnosed separately.",
    query: funnel([
      event("app_first_opened"), event("onboarding_auth_started", [property("mode", "sign_up")]),
      event("onboarding_started"),
      ...["identity", "location", "contacts", "friends", "notifications"].map(step => event("onboarding_step_completed", [property("step", step)])),
      event("onboarding_completed"),
    ]),
  },
  {
    key: "onboarding-resumed", name: "Onboarding — started to completed",
    description: "Includes resumed onboarding; does not require the original first-open or an optional follow. Compare with the strict acquisition funnel.",
    query: funnel([event("onboarding_started"), event("onboarding_completed")]),
  },
  {
    key: "onboarding-permissions", name: "Onboarding — permission decisions",
    description: "Permission outcomes by step and result, including skip/deny. Completion is not consent.",
    query: hogql(`select properties.permission as step, properties.granted as result, uniqExact(person_id) as people, count() as decisions
from events where event = 'onboarding_permission_result' and ${productionSQL}
  and timestamp >= now() - interval 30 day group by step, result order by step, decisions desc`),
  },
  {
    key: "activation-first-value", name: "Activation — onboarding to first core action",
    description: "Complete onboarding then save a Wanna or create a check-in within 14 days. Following is optional. A first check-in counts once, even when it also creates a saved place. Local completion; inspect sync health separately.",
    query: funnel([event("onboarding_completed"), event("core_action_performed")]),
  },
  {
    key: "engagement-active-users", name: "Engagement — daily active and core-active users",
    description: "Daily unique people opening the app versus creating a Wanna/check-in. Viewing one's profile alone is not core activation.",
    query: trends([event("app_session_started"), event("core_action_performed")]),
  },
  {
    key: "engagement-weekly-users", name: "Engagement — weekly active and core-active users",
    description: "Unique people per calendar week, not the sum of daily active users.",
    query: trends([event("app_session_started"), event("core_action_performed")], { interval: "week" }),
  },
  {
    key: "engagement-core-actions", name: "Engagement — Wanna and check-in volume",
    description: "Unduplicated core action volume. Includes local/offline saves; backend health is separate.",
    query: trends([eventTotal("core_action_performed")], { breakdown: "action" }),
  },
  {
    key: "engagement-surfaces", name: "Engagement — feature reach",
    description: "Unique viewers by Map, Feed (discover), Events teaser, Lists, Profile, and Add surface. Exposure is not successful use.",
    query: trends([event("app_surface_viewed")], { breakdown: "surface" }),
  },
  {
    key: "engagement-human-needs", name: "Engagement — active users by human need",
    description: "Connect, Expression, and Status remain exploratory groupings. Use core actions for activation and value retention.",
    query: trends([event("engagement_action_performed")], { breakdown: "need" }),
  },
  {
    key: "engagement-actions", name: "Engagement — actions within each need",
    description: "Unique merged people and action volume. Schema 3 production only; excludes the internal/test-person marker.",
    query: hogql(`select properties.need as need, properties.action as action, uniqExact(person_id) as unique_users, count() as actions
from events where event = 'engagement_action_performed' and ${productionSQL}
  and timestamp >= now() - interval 30 day group by need, action order by need, unique_users desc limit 100`),
  },
  {
    key: "save-editor-funnel", name: "Saves — editor to submitted to local completion",
    description: "Unique-user diagnostic funnel for new/repeat saves; edits excluded. Synced and pending both count as local completion. Not an attempt-level conversion rate or a server-success claim.",
    query: funnel([
      event("save_flow_opened", [{ ...property("mode", "edit"), operator: "is_not" }]),
      event("save_flow_submitted", [{ ...property("mode", "edit"), operator: "is_not" }]),
      event("save_flow_completed", [{ ...property("mode", "edit"), operator: "is_not" }, { ...property("outcome", "synced"), value: ["synced", "pending"] }]),
    ]),
  },
  {
    key: "save-editor-outcomes", name: "Saves — submitted outcomes",
    description: "Editor completion results: synced, pending, failed. Count attempts separately from unique-user funnels; closed/abandoned editors have no completion.",
    query: trends([eventTotal("save_flow_completed")], { breakdown: "outcome" }),
  },
  {
    key: "discovery-use", name: "Discovery — search and place-profile reach",
    description: "Unique people submitting Feed search, selecting a trusted/recme/MapKit result, and viewing a full place profile. Search text and place identity are not collected.",
    query: trends([event("discover_search_submitted"), event("trusted_place_search_result_selected"), event("place_profile_viewed")]),
  },
  {
    key: "imports-use", name: "Imports — queued and matching completed",
    description: "Pasted import batches accepted and matching finished. Matching does not imply review/save completion; imported saves also appear under source_type in save sources.",
    query: trends([event("place_import_started"), event("place_import_matching_completed")]),
  },
  {
    key: "save-sources", name: "Saves — acquisition of saved places",
    description: "Existing raw place_saved counts by capture source (including imports/social saves). A first check-in can also emit this raw event; do not add it to check-in counts.",
    query: trends([eventTotal("place_saved")], { breakdown: "source_type" }),
  },
  {
    key: "events-interest", name: "Events — teaser to confirmed waitlist interest",
    description: "Teaser viewed → registration submitted → server-confirmed interest. Existing/cached registrations do not emit a new conversion; this is not RSVP or attendance.",
    query: funnel([event("app_surface_viewed", [property("surface", "events")]), event("events_interest_submitted"), event("events_interest_result", [property("outcome", "confirmed")])]),
  },
  {
    key: "retention-activation-cohorts", name: "Retention — session return after onboarding",
    description: "Weekly cohorts; exact elapsed D1/D7/D14/D30 windows. Shows eligible and returned people per horizon. Only fully matured windows enter the rate; null means not yet measurable. Fixed 90-day cohort view.",
    query: hogql(retentionSQL("onboarding_completed", "app_session_started")),
  },
  {
    key: "retention-core-cohorts", name: "Retention — repeat Wanna or check-in",
    description: "Weekly cohorts anchored to the first schema-3 core action; returns require another core action. Existing users enter when first observed after rollout, so this is not exclusively a new-signup cohort. Mature exact elapsed-day windows; fixed 90-day cohort view.",
    query: hogql(retentionSQL("core_action_performed", "core_action_performed")),
  },
  {
    key: "referrals-invite-funnel", name: "Referrals — invite send funnel",
    description: "Invite sheet → delivery start → successful Messages/share-sheet handoff. No install attribution claimed.",
    query: funnel([event("contact_invite_sheet_opened"), event("contact_invite_delivery_started"), event("contact_invite_completed", [property("outcome", "sent")])]),
  },
  {
    key: "referrals-invites-by-surface", name: "Referrals — successful invite handoffs",
    description: "Unique successful handoffs by entry point; outbound intent, not installs.",
    query: trends([event("contact_invite_completed", [property("outcome", "sent")])], { breakdown: "surface" }),
  },
  {
    key: "in-common-invitations", name: "In Common — invitations created, shared, opened",
    description: "Separate sender creation, native share completion, and recipient opening. These are independent actor counts, not a cross-person conversion funnel; no token/recipient/content is captured.",
    query: trends([event("place_plan_created"), event("place_plan_share_completed", [property("outcome", "shared")]), event("place_plan_opened")]),
  },
  {
    key: "save-sync-health", name: "Data Quality — saved-place sync outcomes",
    description: "Raw sync attempts/success/failure volume, including retries. This is diagnostic activity, not unique saves or a save conversion rate.",
    query: trends([eventTotal("own_place_sync_attempted"), eventTotal("own_place_sync_succeeded"), eventTotal("own_place_sync_failed")]),
  },
  {
    key: "auth-health", name: "Data Quality — native authentication outcomes",
    description: "Terminal Apple/Google auth results by coarse outcome. Provider cancellation is distinct from failure; no messages or credentials.",
    query: trends([eventTotal("native_social_auth_result")], { breakdown: "result" }),
  },
  {
    key: "instrumentation-coverage", name: "Data Quality — event coverage by build and environment",
    description: "Intentionally includes historical, development, and server traffic. Last 30 days; event/build/schema/environment/counts only. Missing schema-3 rows mean the new app instrumentation has not reached PostHog yet, not zero user interest.",
    query: hogql(`select event, properties.build_number as build, properties.analytics_schema_version as schema,
  properties.analytics_environment as environment, count() as events, uniqExact(person_id) as people, max(timestamp) as last_seen
from events where timestamp >= now() - interval 30 day and event not like '$%'
group by event, build, schema, environment order by last_seen desc limit 500`),
  },
  {
    key: "notifications-accepted-volume",
    name: "Notifications — APNs-accepted volume",
    description: "Notifications with at least one APNs-accepted device delivery, split by coarse notification type. This is provider acceptance, not proof that iOS displayed the alert.",
    query: trends([
      eventTotal("notification_delivery_processed", [property("delivery_outcome", "sent")]),
    ], { breakdown: "notification_type", interval: "day" }),
  },
  {
    key: "notifications-delivery-health",
    name: "Notifications — delivery health",
    description: "Terminal notification outcomes and final per-device APNs disposition over the last 30 days. Retry-only worker passes are excluded from the terminal notification rate.",
    query: hogql(`
select
  sum(if(properties.delivery_outcome = 'sent', 1, 0)) as accepted_notifications,
  sum(if(properties.delivery_outcome = 'failed', 1, 0)) as failed_notifications,
  round(
    100.0 * sum(if(properties.delivery_outcome = 'sent', 1, 0)) /
    nullIf(sum(if(properties.delivery_outcome in ('sent', 'failed'), 1, 0)), 0),
    1
  ) as notification_acceptance_percent,
  sum(if(properties.delivery_outcome in ('sent', 'failed'), toInt(properties.accepted_token_count), 0)) as accepted_device_tokens,
  sum(if(properties.delivery_outcome in ('sent', 'failed'),
    toInt(properties.permanent_token_failure_count) +
    toInt(properties.permanent_event_failure_count) +
    toInt(properties.retryable_failure_count), 0)) as failed_device_tokens,
  sum(if(properties.delivery_outcome = 'retrying', 1, 0)) as retry_passes
from events
where event = 'notification_delivery_processed'
  and timestamp >= now() - interval 30 day
`.trim()),
  },
  {
    key: "notifications-open-rate",
    name: "Notifications — remote open rate",
    description: "Routable remote notification taps divided by APNs-accepted notifications over the last 30 days. This is an aggregate directional rate; no notification or recipient identifier is exported by the server analytics path.",
    query: hogql(`
with delivery as (
  select count() as accepted_notifications
  from events
  where event = 'notification_delivery_processed'
    and properties.delivery_outcome = 'sent'
    and timestamp >= now() - interval 30 day
), opens as (
  select count() as notification_opens
  from events
  where event = 'notification_opened'
    and properties.delivery_channel = 'remote'
    and timestamp >= now() - interval 30 day
)
select
  delivery.accepted_notifications as accepted_notifications,
  opens.notification_opens as notification_opens,
  round(
    100.0 * opens.notification_opens / nullIf(delivery.accepted_notifications, 0),
    1
  ) as aggregate_open_percent
from delivery
cross join opens
`.trim()),
  },
  {
    key: "notifications-frequency-summary",
    name: "Notifications — 30-day frequency per eligible recipient",
    description: "Latest privacy-preserving aggregate snapshot across users who currently have notifications enabled and at least one active device token. Includes recipients with zero accepted notifications.",
    query: hogql(`
select
  toInt(properties.eligible_recipient_count) as eligible_recipients,
  toInt(properties.accepted_notification_count) as accepted_notifications,
  toFloat(properties.average_per_recipient) as average_per_recipient,
  toInt(properties.p50_per_recipient) as p50_per_recipient,
  toInt(properties.p90_per_recipient) as p90_per_recipient,
  toInt(properties.max_per_recipient) as max_per_recipient
from events
where event = 'notification_frequency_snapshot'
order by timestamp desc
limit 1
`.trim()),
  },
  {
    key: "notifications-frequency-histogram",
    name: "Notifications — recipient frequency distribution (30 days)",
    description: "Latest count of notification-eligible recipients in each APNs-accepted notification bucket. Zero is included. The server exports aggregate bucket counts only, never recipient IDs.",
    query: hogqlBar(`
select
  properties.bucket as notification_count_bucket,
  argMax(toInt(properties.recipient_count), timestamp) as recipients,
  argMax(toInt(properties.bucket_order), timestamp) as bucket_order
from events
where event = 'notification_frequency_bucket_snapshot'
group by notification_count_bucket
order by bucket_order asc
`.trim(), "notification_count_bucket", "recipients"),
  },
];

const sections = [
  {
    "title": "Acquisition",
    "body": "Schema 3 production baseline (release device builds, including TestFlight). Debug/simulator traffic is excluded. First open is an install marker, not a download. App Store attribution and internal-person labeling remain explicit operational checks.",
    "insightKeys": [
      "acquisition-first-opens",
      "acquisition-campaign-links"
    ]
  },
  {
    "title": "Activation",
    "body": "Measure required onboarding separately from product value. Following and permission consent are optional. First value is a locally created Wanna or check-in within 14 days after onboarding.",
    "insightKeys": [
      "onboarding-full-funnel",
      "onboarding-resumed",
      "onboarding-permissions",
      "activation-first-value"
    ]
  },
  {
    "title": "Engagement",
    "body": "Start with active people and unduplicated core actions. Then diagnose feature reach, save completion, discovery, import usage, and Events interest. Local completion and server sync are separate.",
    "insightKeys": [
      "engagement-active-users",
      "engagement-weekly-users",
      "engagement-core-actions",
      "engagement-surfaces",
      "engagement-human-needs",
      "engagement-actions",
      "save-editor-funnel",
      "save-editor-outcomes",
      "discovery-use",
      "imports-use",
      "save-sources",
      "events-interest"
    ]
  },
  {
    "title": "Retention",
    "body": "Compare app returns after onboarding with repeat value after a first observed Wanna/check-in. Exact elapsed-day windows: D1 is hours 24\u201348, D7 is days 7\u20138, etc. Each horizon has its own fully matured denominator; immature cohorts remain blank. Fixed 90-day SQL windows do not inherit the dashboard date selector.",
    "insightKeys": [
      "retention-activation-cohorts",
      "retention-core-cohorts"
    ]
  },
  {
    "title": "Referrals",
    "body": "Successful outbound handoffs and In Common invitations. Recipient opens involve a different person; these counts are not a same-user funnel or attributed install rate.",
    "insightKeys": [
      "referrals-invite-funnel",
      "referrals-invites-by-surface",
      "in-common-invitations"
    ]
  },
  {
    "title": "Monetization",
    "body": "Deliberately blank until a product decision defines revenue behavior and an event contract.",
    "insightKeys": []
  },
  {
    "title": "Data Quality",
    "body": "Check ingestion, environments, auth results and sync failures before interpreting behavior. Behavioral tiles require schema 3 and production; they remain empty until the instrumented release ships. The existing Internal / Test users cohort (481950) is excluded, plus the internal/test-person marker. The cohort had zero members at audit; classify staff/review accounts before interpreting launch behavior. The inventory deliberately includes all traffic and uses a fixed 30-day SQL window.",
    "insightKeys": [
      "save-sync-health",
      "auth-health",
      "instrumentation-coverage"
    ]
  },
  {
    "title": "Notification Operations",
    "body": "Aggregate server operations retain historical coverage. APNs acceptance is not display. Opens/acceptances is a directional ratio, not recipient conversion, and may cross time windows. No recipient IDs or notification payloads are exported.",
    "insightKeys": [
      "notifications-accepted-volume",
      "notifications-delivery-health",
      "notifications-open-rate",
      "notifications-frequency-summary",
      "notifications-frequency-histogram"
    ]
  }
];

function assertDefinition() {
  const keys = new Set(insights.map(({ key }) => key));
  if (keys.size !== insights.length) throw new Error("Duplicate insight key");
  for (const section of sections) {
    for (const key of section.insightKeys) {
      if (!keys.has(key)) throw new Error(`Unknown insight key ${key}`);
    }
  }
  const monetization = sections.find((section) => section.title === "Monetization");
  if (!monetization || monetization.insightKeys.length !== 0) {
    throw new Error("Monetization must remain an explicit empty section");
  }
  if (sections.at(-1)?.title !== "Notification Operations") {
    throw new Error("Notification Operations must remain the bottom dashboard section");
  }
  return { dashboard: "Astir Launch — Product Behavior", sections: sections.length, insights: insights.length };
}

function parseArgs(args) {
  return {
    apply: args.includes("--apply"),
    check: args.includes("--check"),
    verify: args.includes("--verify"),
  };
}

async function api(path, { method = "GET", body } = {}) {
  const host = (process.env.WANDER_POSTHOG_API_HOST || DEFAULT_HOST).replace(/\/$/, "");
  const key = process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
  if (!key) throw new Error("Missing WANDER_POSTHOG_PERSONAL_API_KEY");
  const response = await fetch(`${host}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) {
    throw new Error(`${method} ${path} failed (${response.status}): ${await response.text()}`);
  }
  return response.json();
}

async function listAll(path) {
  const rows = [];
  let next = path;
  while (next) {
    const page = await api(next);
    rows.push(...(page.results || []));
    next = page.next ? new URL(page.next).pathname + new URL(page.next).search : null;
  }
  return rows;
}

async function upsertInsight(projectID, dashboardID, definition, existing) {
  const tag = `${INSIGHT_TAG_PREFIX}${definition.key}`;
  const payload = {
    name: definition.name,
    description: definition.description,
    query: definition.query,
    tags: [MANAGED_TAG, tag],
    dashboards: [dashboardID],
  };
  const match = existing.find(
    (item) =>
      item.tags?.includes(tag) ||
      (item.tags?.includes(MANAGED_TAG) && item.name === definition.name),
  );
  if (match) {
    payload.dashboards = [...new Set([...(match.dashboards || []), dashboardID])];
    payload.tags = [...new Set([...(match.tags || []), ...payload.tags])];
    return api(`/api/projects/${projectID}/insights/${match.id}/`, { method: "PATCH", body: payload });
  }
  return api(`/api/projects/${projectID}/insights/`, { method: "POST", body: payload });
}

function sectionMarker(section) {
  return `<!-- recme:iac:section:${section.title.toLowerCase()} -->`;
}

function sectionBody(section) {
  return `${sectionMarker(section)}\n# ${section.title}\n\n${section.body}`;
}

async function upsertSectionTile(projectID, dashboardID, section, existingTiles) {
  const existing = existingTiles.find(({ text }) => text?.body?.includes(sectionMarker(section)));
  const payload = {
    body: sectionBody(section),
    layouts: {
      sm: { x: 0, y: 0, w: 12, h: 2 },
      xs: { x: 0, y: 0, w: 1, h: 2 },
    },
  };
  if (existing) {
    return api(`/api/projects/${projectID}/dashboards/${dashboardID}/update_text_tile/`, {
      method: "POST",
      body: { tile_id: existing.id, ...payload },
    });
  }
  return api(`/api/projects/${projectID}/dashboards/${dashboardID}/create_text_tile/`, {
    method: "POST",
    body: payload,
  });
}

function configuredProjectID() {
  const projectID = process.env.WANDER_POSTHOG_PROJECT_ID;
  if (projectID !== "557259") throw new Error("This dashboard and its internal-user cohort belong to Astir project 557259");
  return projectID;
}

// The existing key has insight:read but no direct query scope. Refreshing saved
// insights is a supported API operation; return aggregate status, not row data.
async function verifyDashboard() {
  const projectID = configuredProjectID();
  const dashboards = await listAll(`/api/projects/${projectID}/dashboards/?limit=200`);
  const match = dashboards.find(item => item.tags?.includes(DASHBOARD_TAG));
  if (!match) throw new Error("Managed launch dashboard is missing");
  const dashboard = await api(`/api/projects/${projectID}/dashboards/${match.id}/`);
  const results = [];
  for (const definition of insights) {
    const tile = dashboard.tiles?.find(item => item.insight?.tags?.includes(`${INSIGHT_TAG_PREFIX}${definition.key}`));
    if (!tile) throw new Error(`Missing managed insight: ${definition.key}`);
    const insight = await api(`/api/projects/${projectID}/insights/${tile.insight.id}/?refresh=force_blocking`);
    if (insight.error || !Array.isArray(insight.result) || !insight.last_refresh) {
      throw new Error(`Insight failed to produce a refreshed result: ${definition.key}`);
    }
    results.push({ key: definition.key, id: insight.id, rows: insight.result.length, refreshedAt: insight.last_refresh });
  }
  return { dashboardID: dashboard.id, verifiedInsights: results.length, results };
}

async function applyDashboard() {
  const projectID = configuredProjectID();

  const [existingInsights, existingDashboards] = await Promise.all([
    listAll(`/api/projects/${projectID}/insights/?limit=200`),
    listAll(`/api/projects/${projectID}/dashboards/?limit=200`),
  ]);
  const dashboardPayload = {
    name: "Astir Launch — Product Behavior",
    description: "Launch analytics: acquisition, onboarding, core actions, feature adoption, mature retention, referrals, data quality, and notification operations. Managed by scripts/posthog-product-dashboard.mjs; do not hand-edit managed tiles.",
    pinned: true,
    tags: [MANAGED_TAG, DASHBOARD_TAG],
  };
  const existing = existingDashboards.find((dashboard) => dashboard.tags?.includes(DASHBOARD_TAG));
  const dashboard = existing
    ? await api(`/api/projects/${projectID}/dashboards/${existing.id}/`, {
        method: "PATCH",
        body: dashboardPayload,
      })
    : await api(`/api/projects/${projectID}/dashboards/`, {
        method: "POST",
        body: dashboardPayload,
      });

  // PostHog creates missing tags while saving an insight. Concurrent writes for
  // several new managed tags can race and leave an otherwise-created insight
  // without its canonical tag, so serialize these idempotent upserts.
  const created = [];
  for (const definition of insights) {
    created.push(await upsertInsight(projectID, dashboard.id, definition, existingInsights));
  }
  let currentDashboard = await api(`/api/projects/${projectID}/dashboards/${dashboard.id}/`);
  const sectionTiles = [];
  for (const section of sections) {
    sectionTiles.push(
      await upsertSectionTile(projectID, dashboard.id, section, currentDashboard.tiles || []),
    );
  }

  currentDashboard = await api(`/api/projects/${projectID}/dashboards/${dashboard.id}/`);
  const desiredTileOrder = [];
  sections.forEach((section, sectionIndex) => {
    desiredTileOrder.push(sectionTiles[sectionIndex].id);
    for (const insightKey of section.insightKeys) {
      const tag = `${INSIGHT_TAG_PREFIX}${insightKey}`;
      const tile = currentDashboard.tiles?.find(({ insight }) => insight?.tags?.includes(tag));
      if (!tile) throw new Error(`Dashboard tile missing for managed insight ${insightKey}`);
      desiredTileOrder.push(tile.id);
    }
  });
  for (const tile of currentDashboard.tiles || []) {
    if (!desiredTileOrder.includes(tile.id)) desiredTileOrder.push(tile.id);
  }
  await api(`/api/projects/${projectID}/dashboards/${dashboard.id}/reorder_tiles/`, {
    method: "POST",
    body: { tile_order: desiredTileOrder, layout: "preserve" },
  });
  return { dashboardID: dashboard.id, insightIDs: created.map(({ id }) => id) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const options = parseArgs(process.argv.slice(2));
  const summary = assertDefinition();
  if (options.verify) {
    console.log(JSON.stringify({ mode: "verify", ...(await verifyDashboard()) }, null, 2));
  } else if (options.check || !options.apply) {
    console.log(JSON.stringify({ mode: "check", ...summary }, null, 2));
  } else {
    console.log(JSON.stringify({ mode: "apply", ...summary, ...(await applyDashboard()) }, null, 2));
  }
}

export { applyDashboard, assertDefinition, insights, sections, retentionSQL, clientProperties, verifyDashboard };
