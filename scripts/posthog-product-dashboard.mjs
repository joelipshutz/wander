#!/usr/bin/env node

import { pathToFileURL } from "node:url";

const DASHBOARD_TAG = "recme:iac:dashboard:product-funnel";
const INSIGHT_TAG_PREFIX = "recme:iac:insight:";
const MANAGED_TAG = "recme:managed";
const DEFAULT_HOST = "https://us.posthog.com";

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

const trends = (series, { breakdown, interval = "week" } = {}) => ({
  kind: "TrendsQuery",
  series,
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

const insights = [
  {
    key: "acquisition-first-opens",
    name: "Acquisition — first opens",
    description: "Unique devices that recorded their first app open marker, split by known acquisition source. The schema-v2 release establishes the baseline and includes upgraded installs once.",
    query: trends([event("app_first_opened")], { breakdown: "acquisition_source" }),
  },
  {
    key: "acquisition-campaign-links",
    name: "Acquisition — tagged link opens",
    description: "Known tagged links by UTM source. Values are sanitized and no full URL is collected.",
    query: trends([
      event("acquisition_link_opened", [property("has_campaign", "true")]),
    ], { breakdown: "utm_source" }),
  },
  {
    key: "onboarding-full-funnel",
    name: "Activation — full onboarding funnel and drop-off",
    description: "First open through each onboarding step. Ordered within 14 days; shows conversion and loss at every step.",
    query: funnel([
      event("app_first_opened"),
      event("onboarding_auth_started", [property("mode", "sign_up")]),
      event("onboarding_auth_completed"),
      event("onboarding_started"),
      event("onboarding_step_completed", [property("step", "identity")]),
      event("onboarding_step_completed", [property("step", "location")]),
      event("onboarding_step_completed", [property("step", "contacts")]),
      event("onboarding_step_completed", [property("step", "friends")]),
      event("onboarding_step_completed", [property("step", "notifications")]),
      event("onboarding_completed"),
    ]),
  },
  {
    key: "activation-first-value",
    name: "Activation — onboarding to trusted value",
    description: "Trusted-value path in the product's actual order: onboarding starts, follow at least one person, complete onboarding, then save at least one place.",
    query: funnel([
      event("onboarding_started"),
      event("follow_created"),
      event("onboarding_completed"),
      event("place_saved"),
    ]),
  },
  {
    key: "engagement-human-needs",
    name: "Engagement — active users by human need",
    description: "Canonical engagement coverage across Connect, Expression, and Status.",
    query: trends([event("engagement_action_performed")], { breakdown: "need" }),
  },
  {
    key: "engagement-actions",
    name: "Engagement — actions within each need",
    description: "Action volume and unique actors for the human-need map. Use need/action together when diagnosing a change.",
    query: hogql(`
select
  properties.need as need,
  properties.action as action,
  uniqExact(distinct_id) as unique_users,
  count() as actions
from events
where event = 'engagement_action_performed'
  and timestamp >= now() - interval 90 day
group by need, action
order by need asc, unique_users desc
limit 100
`.trim()),
  },
  {
    key: "retention-activation-cohorts",
    name: "Retention — D1 / D7 / D14 / D30 after activation",
    description: "Activated users are those who completed onboarding. A return is a later app session on the exact day window.",
    query: hogql(`
with activated as (
  select distinct_id, min(timestamp) as activated_at
  from events
  where event = 'onboarding_completed'
  group by distinct_id
), returns as (
  select
    activated.distinct_id as distinct_id,
    max(if(dateDiff('day', activated.activated_at, events.timestamp) = 1, 1, 0)) as d1,
    max(if(dateDiff('day', activated.activated_at, events.timestamp) = 7, 1, 0)) as d7,
    max(if(dateDiff('day', activated.activated_at, events.timestamp) = 14, 1, 0)) as d14,
    max(if(dateDiff('day', activated.activated_at, events.timestamp) = 30, 1, 0)) as d30
  from activated
  left join events on events.distinct_id = activated.distinct_id
    and events.event = 'app_session_started'
    and events.timestamp > activated.activated_at
    and events.timestamp < activated.activated_at + interval 31 day
  group by activated.distinct_id
)
select
  count() as activated_users,
  round(100 * sum(d1) / count(), 1) as d1_percent,
  round(100 * sum(d7) / count(), 1) as d7_percent,
  round(100 * sum(d14) / count(), 1) as d14_percent,
  round(100 * sum(d30) / count(), 1) as d30_percent
from returns
`.trim()),
  },
  {
    key: "referrals-invite-funnel",
    name: "Referrals — invite send funnel",
    description: "Invite sheet open to delivery start to a successful Messages/share-sheet handoff.",
    query: funnel([
      event("contact_invite_sheet_opened"),
      event("contact_invite_delivery_started"),
      event("contact_invite_completed", [property("outcome", "sent")]),
    ]),
  },
  {
    key: "referrals-invites-by-surface",
    name: "Referrals — successful invite handoffs",
    description: "Invite handoffs by entry point. This measures outbound intent, not attributed installs.",
    query: trends([
      event("contact_invite_completed", [property("outcome", "sent")]),
    ], { breakdown: "surface" }),
  },
  {
    key: "search-stage-latency",
    name: "Search — stage latency and health",
    description: "Request-correlated local, parser, lexical, semantic, fusion, and total Search stages. Latency is numeric milliseconds; queries and place content are never collected.",
    query: hogql(`
select
  properties.stage as stage,
  count() as stage_completions,
  round(avg(toFloat(properties.latency_ms)), 1) as average_ms,
  round(quantile(0.5)(toFloat(properties.latency_ms)), 1) as p50_ms,
  round(quantile(0.95)(toFloat(properties.latency_ms)), 1) as p95_ms,
  countIf(properties.outcome in ('failed', 'failure')) as failures
from events
where event = 'trusted_place_search_stage_completed'
  and timestamp >= now() - interval 30 day
group by stage
order by p95_ms desc
`.trim()),
  },
  {
    key: "search-provider-selection",
    name: "Search — selected rank and provider provenance",
    description: "Which Search result sources and rank buckets users select. Provider labels include lexical, semantic, lexical+semantic, trusted-memory, and mapkit; no place identifiers or content are sent.",
    query: hogql(`
select
  properties.provider as provider,
  properties.rank as rank_bucket,
  properties.stage as delivery_stage,
  count() as selections,
  uniqExact(distinct_id) as unique_users
from events
where event = 'trusted_place_search_result_selected'
  and timestamp >= now() - interval 30 day
group by provider, rank_bucket, delivery_stage
order by selections desc
limit 100
`.trim()),
  },
  {
    key: "search-request-outcomes",
    name: "Search — request selection, conversion, and reformulation",
    description: "Request-level Search outcomes joined by an opaque per-submission ID: submitted, selected, check-in/Wanna conversion, and reformulation. This measures the retrieval loop without raw query text.",
    query: hogql(`
with outcomes as (
  select
    uniqExactIf(properties.search_request_id, event = 'discover_search_submitted') as submitted_requests,
    uniqExactIf(properties.search_request_id, event = 'trusted_place_search_result_selected') as selected_requests,
    uniqExactIf(properties.search_request_id, event = 'trusted_place_search_converted') as converted_requests,
    uniqExactIf(properties.search_request_id, event = 'trusted_place_search_reformulated') as reformulated_requests
  from events
  where event in (
    'discover_search_submitted',
    'trusted_place_search_result_selected',
    'trusted_place_search_converted',
    'trusted_place_search_reformulated'
  )
    and timestamp >= now() - interval 30 day
    and properties.search_request_id is not null
    and properties.search_request_id != ''
)
select
  submitted_requests,
  selected_requests,
  converted_requests,
  reformulated_requests,
  round(100.0 * selected_requests / nullIf(submitted_requests, 0), 1) as selection_rate_percent,
  round(100.0 * converted_requests / nullIf(selected_requests, 0), 1) as selected_to_conversion_percent,
  round(100.0 * reformulated_requests / nullIf(submitted_requests, 0), 1) as reformulation_rate_percent
from outcomes
`.trim()),
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
    title: "Acquisition",
    body: "Install → first open → tagged campaign entry. The schema-v2 rollout includes each upgraded install once, so use a build filter when establishing the new-install baseline. App Store impressions/downloads and deferred attribution require App Store Connect or an attribution provider; `direct_or_unknown` is not silently reassigned.",
    insightKeys: ["acquisition-first-opens", "acquisition-campaign-links"],
  },
  {
    title: "Activation",
    body: "First open → sign-up → complete identity, location, contacts, friends, notifications → onboarding complete → follow one person → save one place. Funnels expose step-by-step drop-off.",
    insightKeys: ["onboarding-full-funnel", "activation-first-value"],
  },
  {
    title: "Engagement",
    body: "Human needs → actions. Connect: follow, like, comment, invite, shared-visit invite, trusted-profile view. Expression: save, check in, create list, share recommendation. Status: advance a streak, accept a shared visit, view own profile.",
    insightKeys: ["engagement-human-needs", "engagement-actions"],
  },
  {
    title: "Retention",
    body: "Exact-day return rates after onboarding activation: D1, D7, D14, and D30. App sessions are explicit events; PostHog autocapture remains disabled.",
    insightKeys: ["retention-activation-cohorts"],
  },
  {
    title: "Referrals",
    body: "Invites are measured through successful outbound handoff. Generic TestFlight links cannot attribute install, signup, or activation back to a sender; those later referral steps stay visibly unavailable until attributed invite links ship.",
    insightKeys: ["referrals-invite-funnel", "referrals-invites-by-surface"],
  },
  {
    title: "Monetization",
    body: "Deliberately blank. There is no monetization model or event contract yet. Add metrics only after a product decision, then update docs/analytics.md and this managed dashboard together.",
    insightKeys: [],
  },
  {
    title: "Search Retrieval",
    body: "Search quality and speed by request: stage p50/p95, provider health, selected rank/provenance, downstream check-in/Wanna conversion, and reformulation. Opaque request IDs connect events; raw queries, place names, coordinates, and private content are excluded.",
    insightKeys: [
      "search-stage-latency",
      "search-provider-selection",
      "search-request-outcomes",
    ],
  },
  {
    title: "Notification Operations",
    body: "Remote notification volume, APNs provider acceptance, aggregate tap-through, and 30-day frequency across notification-eligible users. APNs acceptance does not prove that iOS displayed an alert. Frequency snapshots include zero-notification users and export only aggregate counts—never recipient IDs, notification copy, device tokens, routes, or place data.",
    insightKeys: [
      "notifications-accepted-volume",
      "notifications-delivery-health",
      "notifications-open-rate",
      "notifications-frequency-summary",
      "notifications-frequency-histogram",
    ],
  },
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
  return { dashboard: "rec.me Product Funnel", sections: sections.length, insights: insights.length };
}

function parseArgs(args) {
  return {
    apply: args.includes("--apply"),
    check: args.includes("--check"),
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

async function applyDashboard() {
  const projectID = process.env.WANDER_POSTHOG_PROJECT_ID;
  if (!projectID) throw new Error("Missing WANDER_POSTHOG_PROJECT_ID");

  const [existingInsights, existingDashboards] = await Promise.all([
    listAll(`/api/projects/${projectID}/insights/?limit=200`),
    listAll(`/api/projects/${projectID}/dashboards/?limit=200`),
  ]);
  const dashboardPayload = {
    name: "rec.me Product Funnel",
    description: "Acquisition → activation → engagement → retention → referrals → monetization → notification operations. Managed by scripts/posthog-product-dashboard.mjs; do not hand-edit managed tiles.",
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
  await api(`/api/projects/${projectID}/dashboards/${dashboard.id}/reorder_tiles/`, {
    method: "POST",
    body: { tile_order: desiredTileOrder, layout: "preserve" },
  });
  return { dashboardID: dashboard.id, insightIDs: created.map(({ id }) => id) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const options = parseArgs(process.argv.slice(2));
  const summary = assertDefinition();
  if (options.check || !options.apply) {
    console.log(JSON.stringify({ mode: "check", ...summary }, null, 2));
  } else {
    console.log(JSON.stringify({ mode: "apply", ...summary, ...(await applyDashboard()) }, null, 2));
  }
}

export { applyDashboard, assertDefinition, insights, sections };
