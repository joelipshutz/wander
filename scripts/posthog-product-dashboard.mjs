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
];

function assertDefinition() {
  const keys = new Set(insights.map(({ key }) => key));
  if (keys.size !== insights.length) throw new Error("Duplicate insight key");
  for (const section of sections) {
    for (const key of section.insightKeys) {
      if (!keys.has(key)) throw new Error(`Unknown insight key ${key}`);
    }
  }
  if (sections.at(-1)?.title !== "Monetization" || sections.at(-1).insightKeys.length !== 0) {
    throw new Error("Monetization must remain an explicit empty section");
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
    description: "Acquisition → activation → engagement → retention → referrals → monetization. Managed by scripts/posthog-product-dashboard.mjs; do not hand-edit managed tiles.",
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
