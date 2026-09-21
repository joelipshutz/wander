#!/usr/bin/env node

import { pathToFileURL } from "node:url";

const DASHBOARD_TAG = "recme:iac:dashboard:product-funnel";
const INSIGHT_TAG_PREFIX = "recme:iac:insight:";
const MANAGED_TAG = "recme:managed";
const DEFAULT_HOST = "https://us.posthog.com";

// Verified Astir account IDs. Resolve to merged people so pre-login events are
// excluded too; keep this guard independent of mutable cohort membership.
const INTERNAL_USER_IDS = [
  "user_3EhATWssjvHxwGiUaoWR5VTgeoy", // Joe
  "user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc", // Ryan
];
const staffExclusionSQL = `person_id not in (
  select person_id from events where distinct_id in (${INTERNAL_USER_IDS.map(id => `'${id}'`).join(", ")})
)`;
const notificationAudience = "external_recipients_v1";
const notificationAudienceSQL = `properties.analytics_audience = '${notificationAudience}'`;
const RETIRED_INSIGHT_KEYS = ["activation-first-day-follows-per-user"];

// Schema 3 is the launch measurement baseline. Old unclassified traffic is
// visible in Data Quality, never silently mixed with production cohorts.
const clientProperties = [
  { key: staffExclusionSQL, type: "hogql" },
  { key: "source", value: ["signup_default"], operator: "is_not", type: "event" },
  { key: "analytics_schema_version", value: ["3"], operator: "exact", type: "event" },
  { key: "analytics_environment", value: ["production"], operator: "exact", type: "event" },
  { key: "$internal_or_test_user", value: ["true"], operator: "is_not", type: "person" },
  { key: "id", value: 481950, operator: "not_in", type: "cohort" },
];
const productionSQL = `${staffExclusionSQL}
  and coalesce(toString(properties.source), '') != 'signup_default'
  and properties.analytics_schema_version = '3'
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

const labeledEvent = (name, label, properties = []) => ({ ...event(name, properties), custom_name: label });

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

const trends = (series, { breakdown, interval = "day", breakdownLimit = 12 } = {}) => ({
  kind: "TrendsQuery",
  series,
  properties: isServerSeries(series) ? [property("analytics_audience", notificationAudience)] : clientProperties,
  interval,
  dateRange: { date_from: "-90d", date_to: null, explicitDate: false },
  trendsFilter: { display: "ActionsLineGraph", showLegend: true },
  breakdownFilter: breakdown
    ? { breakdown, breakdown_type: "event", breakdown_limit: breakdownLimit }
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

const hogqlDailyBars = (query, yAxis) => ({
  kind: "DataVisualizationNode",
  source: hogql(query),
  display: "ActionsBar",
  chartSettings: {
    showValuesOnSeries: true,
    xAxis: { column: "cohort_day" },
    yAxis: [{ column: yAxis }],
    showLegend: true,
  },
});

// One row per actual activation, with optional observed source. These new
// events deliberately do not retrofit attribution onto legacy sessions.
// Aggregate source callbacks first so duplicate callbacks cannot inflate entries.
function appEntrySQL({ daily = false } = {}) {
  return `with entries as (
  select properties.entry_id as entry_id, min(timestamp) as entered_at,
    argMin(properties.entry_kind, timestamp) as entry_kind,
    argMin(person_id, timestamp) as entry_person
  from events where event = 'app_entry_started' and ${productionSQL}
    and notEmpty(toString(properties.entry_id))
    and timestamp >= now() - interval 30 day
  group by entry_id
), sources as (
  select properties.entry_id as entry_id,
    countIf(properties.entry_source = 'notification') > 0 as from_notification,
    countIf(properties.entry_source = 'link') > 0 as from_link,
    argMinIf(properties.notification_type, timestamp, properties.entry_source = 'notification') as notification_type,
    argMinIf(properties.delivery_channel, timestamp, properties.entry_source = 'notification') as delivery_channel
  from events where event = 'app_entry_source_observed' and ${productionSQL}
    and timestamp >= now() - interval 31 day
    and notEmpty(toString(properties.entry_id))
  group by entry_id
), attributed as (
  select entries.entered_at, entries.entry_kind, entries.entry_person,
    if(coalesce(sources.from_notification, false), 'notification',
      if(coalesce(sources.from_link, false), 'link', 'direct_or_unknown')) as entry_source,
    if(coalesce(sources.from_notification, false), coalesce(nullIf(toString(sources.notification_type), ''), 'unknown'), 'not_applicable') as notification_type,
    if(coalesce(sources.from_notification, false), coalesce(nullIf(toString(sources.delivery_channel), ''), 'unknown'), 'not_applicable') as delivery_channel
  from entries left join sources on entries.entry_id = sources.entry_id
)
${daily ? `select toStartOfDay(entered_at) as day,
  countIf(entry_source = 'notification') as notification_entries,
  countIf(entry_source = 'link') as link_entries,
  countIf(entry_source = 'direct_or_unknown' and entry_kind = 'cold_launch') as other_cold_launches,
  countIf(entry_source = 'direct_or_unknown' and entry_kind = 'foreground_return') as other_foreground_returns
from attributed group by day order by day` : `select entry_source, entry_kind, notification_type, delivery_channel,
  count() as entries, uniqExact(entry_person) as unique_users
from attributed group by entry_source, entry_kind, notification_type, delivery_channel
order by entries desc`}`;
}

// Start before the friends step so onboarding follows are included. Take the
// first observed start before applying the date range, so resumes do not create
// new cohorts. Count successful user actions, never queued attempts or seeded
// server-side default follows. Keep zero-follow people in the denominator.
function firstDayFollowSQL() {
  return `with cohort as (
  select person_id, min(timestamp) as started_at
  from events
  where event = 'onboarding_started' and ${productionSQL}
  group by person_id
  having started_at >= now() - interval 90 day
), follow_events as (
  select person_id, timestamp from events
  where event = 'follow_created' and properties.outcome = 'succeeded'
    and ${productionSQL}
), observed as (
  select cohort.person_id, cohort.started_at,
    countIf(follow_events.timestamp >= cohort.started_at
      and follow_events.timestamp < cohort.started_at + interval 24 hour) as follows
  from cohort left join follow_events on cohort.person_id = follow_events.person_id
    and follow_events.timestamp >= cohort.started_at
    and follow_events.timestamp < cohort.started_at + interval 24 hour
  group by cohort.person_id, cohort.started_at
)
select toStartOfDay(started_at) as cohort_day,
  count() as cohort_users,
  countIf(started_at + interval 24 hour <= now()) as eligible_users,
  countIf(started_at + interval 24 hour > now()) as pending_users,
  countIf(follows > 0 and started_at + interval 24 hour <= now()) as users_who_followed,
  if(eligible_users = 0, null, sumIf(follows, started_at + interval 24 hour <= now())) as first_day_follows,
  round(100.0 * users_who_followed / nullIf(eligible_users, 0), 1) as follow_rate_percent,
  round(first_day_follows / nullIf(eligible_users, 0), 2) as follows_per_user
from observed group by cohort_day order by cohort_day asc`;
}

// PostHog's unordered funnel starts with people who did ANY step, including
// action-only users. Anchor explicitly to completed onboarding instead.
function activationSQL() {
  return `with cohort as (
  select person_id, min(timestamp) as completed_at
  from events where event = 'onboarding_completed' and ${productionSQL}
  group by person_id
  having completed_at >= now() - interval 90 day
), actions as (
  select person_id, timestamp from events
  where (event = 'core_action_performed'
    or (event = 'follow_created' and properties.outcome = 'succeeded'))
    and ${productionSQL}
), observed as (
  select cohort.person_id,
    max(if(actions.timestamp >= cohort.completed_at - interval 14 day
      and actions.timestamp <= cohort.completed_at + interval 14 day, 1, 0)) as activated
  from cohort left join actions on cohort.person_id = actions.person_id
    and actions.timestamp >= cohort.completed_at - interval 14 day
    and actions.timestamp <= cohort.completed_at + interval 14 day
  group by cohort.person_id
), summary as (
  select count() as onboarded_users, sum(activated) as activated_users from observed
)
select step, people, conversion_percent from (
select 'Completed onboarding' as step, onboarded_users as people,
  if(onboarded_users = 0, null, 100.0) as conversion_percent, 1 as step_order from summary
union all
select concat('Follow / Wanna / check-in (',
    coalesce(toString(round(100.0 * activated_users / nullIf(onboarded_users, 0), 1)), '—'), '%)') as step,
  activated_users as people,
  round(100.0 * activated_users / nullIf(onboarded_users, 0), 1) as conversion_percent, 2 as step_order from summary
) order by step_order`;
}

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
      labeledEvent("app_first_opened", "First app open"),
      labeledEvent("onboarding_auth_started", "Started sign-up", [property("mode", "sign_up")]),
      labeledEvent("onboarding_started", "Started profile setup"),
      ...[
        ["identity", "Profile details saved"],
        ["location", "Location step completed"],
        ["contacts", "Contacts step completed"],
        ["friends", "Follow suggestions completed"],
        ["notifications", "Notifications step completed"],
      ].map(([step, label]) => labeledEvent("onboarding_step_completed", label, [property("step", step)])),
      labeledEvent("onboarding_completed", "Onboarding completed"),
    ]),
  },
  {
    key: "onboarding-resumed", name: "Onboarding — started to completed",
    description: "Includes resumed onboarding; does not require the original first-open or an optional follow. Compare with the strict acquisition funnel.",
    query: funnel([labeledEvent("onboarding_started", "Started profile setup"), labeledEvent("onboarding_completed", "Onboarding completed")]),
  },
  {
    key: "onboarding-permissions", name: "Onboarding — permission decisions",
    description: "Permission outcomes by step and result, including skip/deny. Completion is not consent.",
    query: hogql(`select properties.permission as step, properties.granted as result, uniqExact(person_id) as people, count() as decisions
from events where event = 'onboarding_permission_result' and ${productionSQL}
  and timestamp >= now() - interval 30 day group by step, result order by step, decisions desc`),
  },
  {
    key: "activation-first-value", name: "Activation — onboarding + follow, Wanna or check-in",
    description: "Completed onboarding plus a successful chosen follow, Wanna, or check-in within 14 days before/after first completion. Includes deliberate onboarding follows; automatic follows never qualify. Each person counts once; action-only users excluded. Fixed 90-day cohorts; recent cohorts can still convert. Saves/check-ins are local completion.",
    query: hogqlBar(activationSQL(), "step", "people"),
  },
  {
    key: "activation-first-day-follow-rate", name: "First day — follow rate by daily cohort (%)",
    description: "Users who choose to follow at least one person in their first 24h from onboarding start, divided by all fully observed users. Includes deliberate onboarding follows and zero-follow users. Automatic follows never qualify. Daily UTC cohorts, last 90 days. Immature cohorts are blank.",
    query: hogqlDailyBars(firstDayFollowSQL(), "follow_rate_percent"),
  },
  {
    key: "activation-first-day-follow-count", name: "First day — follows per user by daily cohort",
    description: "Total successful chosen follow actions in the first 24h from onboarding start / all fully observed users in that daily cohort, including zero-follow users. Automatic follows never count. Daily UTC cohorts; last 90 days. Immature cohorts are blank. Re-follows count again; this is not current following balance.",
    query: hogqlDailyBars(firstDayFollowSQL(), "follows_per_user"),
  },
  {
    key: "activation-first-day-follow-cohorts", name: "First day — follow cohort counts and denominators",
    description: "Daily first-onboarding-start cohorts (UTC), last 90 days: all users, fully observed users, pending users, users who followed, successful first-24h follow actions, rate, and average. Pending users enter neither numerator nor denominator. Schema 3 production only; first observed onboarding is not guaranteed first-ever signup.",
    query: hogql(firstDayFollowSQL()),
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
    key: "engagement-notification-clicks", name: "Engagement — notification clicks by type",
    description: "Daily accepted notification opens by type: remote pushes, local reminders, and instrumented in-app inbox opens. Counts opens, not unique people or delivered notifications. Duplicate handling of the same system response is suppressed. Last 90 days; type/channel totals are in the companion table.",
    query: trends([eventTotal("notification_opened")], { breakdown: "notification_type", breakdownLimit: 20 }),
  },
  {
    key: "engagement-notification-click-details", name: "Engagement — notification clicks and users by type / channel",
    description: "Last 30 days of accepted notification opens, split by type and remote/local/in_app/unknown channel. Unique users are per row and must not be summed. An open means routing was accepted; it does not prove the destination finished loading. In-app coverage currently includes place-plan invitations.",
    query: hogql(`select coalesce(nullIf(toString(properties.notification_type), ''), 'unknown') as notification_type,
  coalesce(nullIf(toString(properties.delivery_channel), ''), 'unknown') as delivery_channel,
  count() as clicks, uniqExact(person_id) as unique_users
from events where event = 'notification_opened' and ${productionSQL}
  and timestamp >= now() - interval 30 day
group by notification_type, delivery_channel order by clicks desc`),
  },
  {
    key: "engagement-entry-lifecycle", name: "Engagement — app sessions: cold launches and foreground returns",
    description: "Existing session logging split by lifecycle. A cold launch can come from a notification or link; this chart alone does not identify the source. Foreground sessions follow the app refresh policy, including its 30-second grace, and do not count every brief app switch. Last 90 days.",
    query: trends([eventTotal("app_session_started")], { breakdown: "session_source" }),
  },
  {
    key: "engagement-entry-source", name: "Engagement — app entries by observed source",
    description: "Daily entries: notification, link, or other cold launch/foreground return. Source callbacks before activation or within 2s of it are associated, not proof of causality; other means direct or unknown. New app-entry logging only, after release; historical sessions cannot be attributed. Last 30 days, UTC. Every background return counts.",
    query: {
      kind: "DataVisualizationNode", source: hogql(appEntrySQL({ daily: true })), display: "ActionsBar",
      chartSettings: { xAxis: { column: "day" }, yAxis: ["notification_entries", "link_entries", "other_cold_launches", "other_foreground_returns"].map(column => ({ column })), showLegend: true, showValuesOnSeries: true },
    },
  },
  {
    key: "engagement-entry-source-details", name: "Engagement — entry source, notification type and launch kind",
    description: "Last 30 days of new app-entry logging after release, by source, cold/foreground kind, notification type and channel. One random per-entry correlation ID joins callbacks without exporting payload IDs. Callbacks before activation or within 2s are associated. Unmatched entries remain direct_or_unknown. In-app clicks do not supply entry attribution.",
    query: hogql(appEntrySQL()),
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
  and coalesce(toString(properties.source), '') != 'signup_default'
  and ${staffExclusionSQL}
  and (event not in ('notification_delivery_processed', 'notification_frequency_snapshot', 'notification_frequency_bucket_snapshot')
    or ${notificationAudienceSQL})
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
  and ${notificationAudienceSQL}
  and timestamp >= now() - interval 30 day
`.trim()),
  },
  {
    key: "notifications-open-rate",
    name: "Notifications — remote open rate",
    description: "Routable remote taps divided by APNs-accepted notifications, excluding Joe and Ryan. Uses the last 30 days from the first staff-excluded acceptance; legacy mixed-recipient deliveries are excluded. This is an aggregate directional rate; no notification or recipient identifier is exported by the server analytics path.",
    query: hogql(`
with delivery as (
  select count() as accepted_notifications, min(timestamp) as reporting_started_at
  from events
  where event = 'notification_delivery_processed'
  and ${notificationAudienceSQL}
    and properties.delivery_outcome = 'sent'
    and timestamp >= now() - interval 30 day
), opens as (
  select count() as notification_opens
  from events
  where event = 'notification_opened'
    and properties.delivery_channel = 'remote'
    and timestamp >= (select reporting_started_at from delivery)
    and (select accepted_notifications from delivery) > 0
    and ${productionSQL}
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
where event = 'notification_frequency_snapshot' and ${notificationAudienceSQL}
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
where event = 'notification_frequency_bucket_snapshot' and ${notificationAudienceSQL}
group by notification_count_bucket
order by bucket_order asc
`.trim(), "notification_count_bucket", "recipients"),
  },
];

const sections = [
  {
    "title": "Acquisition",
    "body": "Schema 3 production baseline (release device builds, including TestFlight). Debug/simulator traffic is excluded. First open is an install marker, not a download. Joe and Ryan are excluded from every user-behavior tile, including historical merged activity. App Store attribution remains an explicit operational check.",
    "insightKeys": [
      "acquisition-first-opens",
      "acquisition-campaign-links"
    ]
  },
  {
    "title": "Activation",
    "body": "Activation requires completed onboarding plus a successful follow, Wanna, or check-in within 14 days, in either order so onboarding follows count. First-day follow charts use the first 24 hours from first onboarding start, including onboarding follows. Follows per user divides cohort follow actions by all fully observed cohort users, including zero-follow users. Joe, Ryan, and automatic default follows are excluded. Daily cohorts use UTC; fixed last 90 days.",
    "insightKeys": [
      "onboarding-full-funnel",
      "onboarding-resumed",
      "onboarding-permissions",
      "activation-first-value",
      "activation-first-day-follow-rate",
      "activation-first-day-follow-count",
      "activation-first-day-follow-cohorts"
    ]
  },
  {
    "title": "Engagement",
    "body": "Start with active people, notification clicks, and app entry source. Cold/foreground describes lifecycle, while notification/link/direct-or-unknown describes source. Notification clicks and existing sessions are live; source attribution requires the new app release and cannot be backfilled. Then diagnose core actions and feature reach. Joe, Ryan, and automatic follows are excluded.",
    "insightKeys": [
      "engagement-active-users",
      "engagement-weekly-users",
      "engagement-notification-clicks",
      "engagement-notification-click-details",
      "engagement-entry-lifecycle",
      "engagement-entry-source",
      "engagement-entry-source-details",
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
    "body": "Check ingestion, environments, auth results and sync failures before interpreting behavior. Behavioral tiles require schema 3 and production; they remain empty until the instrumented release ships. The existing Internal / Test users cohort (481950) is excluded, plus the internal/test-person marker. Joe and Ryan also have an explicit merged-person exclusion in every client query. The inventory includes historical and development traffic, excluding Joe and Ryan, and uses a fixed 30-day SQL window.",
    "insightKeys": [
      "save-sync-health",
      "auth-health",
      "instrumentation-coverage"
    ]
  },
  {
    "title": "Notification Operations",
    "body": "Joe and Ryan are excluded as recipients before server aggregation. Delivery trends start with external-recipient reporting; old mixed totals cannot be separated retrospectively. Frequency snapshots recompute the full last 30 days for eligible external recipients. APNs acceptance is not display. Opens/acceptances is a directional ratio, not recipient conversion, and may cross time windows. No recipient IDs or notification payloads are exported.",
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
  for (const definition of insights) {
    if ((definition.description + " Joe and Ryan excluded.").length > 400) {
      throw new Error(`Insight description exceeds PostHog's 400-character limit: ${definition.key}`);
    }
  }
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
    excludeExisting: args.includes("--exclude-staff-from-existing"),
  };
}

async function api(path, { method = "GET", body } = {}) {
  const host = (process.env.WANDER_POSTHOG_API_HOST || DEFAULT_HOST).replace(/\/$/, "");
  const key = process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
  if (!key) throw new Error("Missing WANDER_POSTHOG_PERSONAL_API_KEY");
  const maxAttempts = ["GET", "PATCH"].includes(method) ? 3 : 1;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const response = await fetch(`${host}${path}`, {
      method,
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.ok) return response.json();
    if ([429, 502, 503, 504].includes(response.status) && attempt < maxAttempts) {
      await new Promise(resolve => setTimeout(resolve, 300 * attempt));
      continue;
    }
    throw new Error(`${method} ${path} failed (${response.status}): ${await response.text()}`);
  }
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
    description: definition.description + " Joe and Ryan excluded.",
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

// An explicit maintenance operation for Joe's existing legacy dashboard. This
// changes only the two named staff exclusions and automatic-follow provenance;
// it does not enable the broader project-wide internal/test-user default.
function withStaffExclusions(query) {
  if (query?.kind === "InsightVizNode") {
    const source = withStaffExclusions(query.source);
    return source ? { ...query, source } : null;
  }
  if (!["TrendsQuery", "FunnelsQuery", "RetentionQuery", "StickinessQuery", "LifecycleQuery", "PathsQuery"].includes(query?.kind)) return null;
  if (query.properties && !Array.isArray(query.properties)) throw new Error("Review grouped properties before adding exclusions");
  const properties = [...(query.properties || [])];
  for (const guard of clientProperties.slice(0, 2)) {
    if (!properties.some(p => JSON.stringify(p) === JSON.stringify(guard))) properties.push(guard);
  }
  return { ...query, properties };
}

async function excludeStaffFromExistingInsights() {
  const projectID = configuredProjectID();
  const existing = await listAll(`/api/projects/${projectID}/insights/?limit=200`);
  const updated = [], unsupported = [];
  for (const item of existing) {
    if (item.tags?.includes(MANAGED_TAG) || (!item.saved && !item.dashboards?.length)) continue;
    const query = withStaffExclusions(item.query);
    if (!query) { unsupported.push({ id: item.id, name: item.name }); continue; }
    if (JSON.stringify(query) !== JSON.stringify(item.query)) {
      await api(`/api/projects/${projectID}/insights/${item.id}/`, { method: "PATCH", body: { query } });
    }
    const verified = await api(`/api/projects/${projectID}/insights/${item.id}/?refresh=force_blocking`);
    const saved = verified.query?.source || verified.query;
    if (verified.error || !Array.isArray(verified.result) || !verified.last_refresh
        || !saved?.properties?.some(p => p.key === staffExclusionSQL)) {
      throw new Error(`Legacy insight verification failed: ${item.id}`);
    }
    updated.push({ id: item.id, name: item.name, refreshedAt: verified.last_refresh });
  }
  return { updated, unsupported };
}

async function applyDashboard() {
  const projectID = configuredProjectID();

  const [existingInsights, existingDashboards] = await Promise.all([
    listAll(`/api/projects/${projectID}/insights/?limit=200`),
    listAll(`/api/projects/${projectID}/dashboards/?limit=200`),
  ]);
  const dashboardPayload = {
    name: "Astir Launch — Product Behavior",
    description: "Joe and Ryan excluded from user-behavior metrics. Launch analytics: acquisition, onboarding, core actions, feature adoption, mature retention, referrals, data quality, and notification operations. Managed by scripts/posthog-product-dashboard.mjs; do not hand-edit managed tiles.",
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

  // Retire the duplicate average tile without deleting its saved insight or
  // removing it from other dashboards. Repeated applies are safe.
  for (const item of existingInsights) {
    if (RETIRED_INSIGHT_KEYS.some(key => item.tags?.includes(`${INSIGHT_TAG_PREFIX}${key}`))) {
      await api(`/api/projects/${projectID}/insights/${item.id}/`, {
        method: "PATCH",
        body: {
          dashboards: (item.dashboards || []).filter(id => id !== dashboard.id),
          query: hogqlDailyBars(firstDayFollowSQL(), "follows_per_user"),
          description: "Retired duplicate: see First day — follows per user by daily cohort. Same first-24h metric including zero-follow users, excluding Joe, Ryan, and automatic follows.",
        },
      });
    }
  }

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
  if (options.excludeExisting) {
    console.log(JSON.stringify({ mode: "exclude-staff-from-existing", ...(await excludeStaffFromExistingInsights()) }, null, 2));
  } else if (options.verify) {
    console.log(JSON.stringify({ mode: "verify", ...(await verifyDashboard()) }, null, 2));
  } else if (options.check || !options.apply) {
    console.log(JSON.stringify({ mode: "check", ...summary }, null, 2));
  } else {
    console.log(JSON.stringify({ mode: "apply", ...summary, ...(await applyDashboard()) }, null, 2));
  }
}

export { applyDashboard, assertDefinition, insights, sections, retentionSQL, firstDayFollowSQL, activationSQL, appEntrySQL, clientProperties, staffExclusionSQL, INTERNAL_USER_IDS, withStaffExclusions, verifyDashboard };
