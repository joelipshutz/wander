#!/usr/bin/env node
import { pathToFileURL } from 'node:url';
import { api, listAll, upsertInsight, upsertSectionTile, productionSQL, staffExclusionSQL, INTERNAL_USER_IDS } from './posthog-product-dashboard.mjs';

export const permissions = ['notifications', 'location', 'contacts', 'camera', 'microphone', 'calendar', 'save_photos'];
const sqlList = values => values.map(value => `'${value}'`).join(', ');
export const permissionVariableID = '01a0cf21-7962-0000-aa4c-08dee5d9ed28';
const table = query => ({kind: 'HogQLQuery', query, ...(query.includes('{filters}') ? {filters: {properties: []}} : {}), ...(query.includes('{variables.notification_permission}') ? {variables:{[permissionVariableID]:{code_name:'notification_permission',variableId:permissionVariableID,value:'all'}}} : {})});
const chart = (query, columns, display='ActionsLineGraph') => ({
  kind: 'DataVisualizationNode', source: table(query), display,
  chartSettings: {xAxis: {column: 'day'}, yAxis: columns.map(column => ({column})), showLegend: true},
});

export function permissionOverviewSQL() {
  return `with active as (
  select distinct person_id from events where ${productionSQL}
    and distinct_id like 'user_%' and timestamp >= now()-interval 30 day
), latest as (
  select person_id, properties.permission as permission, argMax(toString(properties.status),timestamp) as status
  from events where event='permission_status_observed' and ${productionSQL}
    and timestamp >= now()-interval 30 day group by person_id,permission
), permissions as (select arrayJoin([${sqlList(permissions)}]) as permission), observed as (
  select p.permission, a.person_id, coalesce(nullIf(l.status,''),'unknown') as status
  from permissions p cross join active a left join latest l on l.person_id=a.person_id and l.permission=p.permission
)
select permission, count() as active_users, countIf(status!='unknown') as observed_users,
  countIf(status in ('enabled','limited')) as enabled_users,
  countIf(status='limited') as limited_users, countIf(status='denied') as denied_users,
  countIf(status='not_determined') as not_yet_asked, countIf(status='restricted') as restricted_users,
  countIf(status='unknown') as unknown_users,
  round(100.0*countIf(status in ('enabled','limited'))/nullIf(countIf(status!='unknown'),0),1) as enabled_percent
from observed group by permission order by permission`;
}

export function permissionDailySQL() {
  return `with observed as (
  select toDate(timestamp) as day, person_id, properties.permission as permission,
    argMax(toString(properties.status),timestamp) as status
  from events where event='permission_status_observed' and ${productionSQL}
    and timestamp >= now()-interval 30 day group by day,person_id,permission
)
select day, ${permissions.map(p=>`round(100.0*countIf(permission='${p}' and status in ('enabled','limited'))/nullIf(countIf(permission='${p}' and status!='unknown'),0),1) as ${p}`).join(',\n  ')}
from observed group by day order by day`;
}

export const recipientGuard = `distinct_id not in (${sqlList(INTERNAL_USER_IDS)}) and ${staffExclusionSQL}
  and person_id not in cohort 481950
  and coalesce(toString(person.properties.$internal_or_test_user),'false')!='true'`;

export function recipientCTEs(filtered = false) {
  return `completed_batches as (
  select toString(properties.snapshot_id) as batch_id, max(toInt(properties.recipient_count)) as expected_rows
  from events where event='notification_recipient_snapshot_completed'
    and properties.analytics_audience='external_recipients_v1' and timestamp>=now()-interval 2 day
  group by batch_id
), available_batches as (
  select toString(properties.snapshot_id) as batch_id, toInt(uniqExact(distinct_id)) as actual_rows
  from events where event='notification_recipient_snapshot'
    and properties.analytics_audience='external_recipients_v1' and timestamp>=now()-interval 2 day group by batch_id
), complete as (
  select max(c.batch_id) as snapshot_id from completed_batches c
  left join available_batches a on a.batch_id=c.batch_id
  where coalesce(a.actual_rows,0)=c.expected_rows
), directory as (
  select distinct_id as user_id, argMax(person_id,timestamp) as person_key,
    argMax(toString(properties.username),timestamp) as username,
    argMax(toString(properties.push_enabled),timestamp) as push_enabled,
    argMax(toString(properties.preferences_known),timestamp) as preferences_known,
    argMax(toInt(properties.active_production_tokens),timestamp) as active_production_tokens,
    argMax(toString(properties.preferences),timestamp) as preferences,
    argMax(toString(properties.daily_counts),timestamp) as daily_counts,
    max(timestamp) as snapshot_at
  from events where event='notification_recipient_snapshot' and ${recipientGuard}
    and properties.analytics_audience='external_recipients_v1'
    and properties.snapshot_id=(select snapshot_id from complete)
    and timestamp>=now()-interval 2 day ${filtered ? 'and {filters}' : ''} group by user_id
)`;
}

export const selectedCTEs = () => `${recipientCTEs(true)}, selected as (
  select * from directory where (select count() from directory)=1
)`;

export function recipientDailySQL() {
  return `with ${selectedCTEs()}, days as (
  select arrayJoin(JSONExtractArrayRaw(coalesce(daily_counts,'[]'))) as daily from selected
), opens as (
  select toDate(timestamp) as day,count() as opens from events
  where event='notification_opened' and properties.delivery_channel='remote' and ${productionSQL}
    and person_id in (select person_key from selected) and timestamp>=now()-interval 31 day group by day
)
select toDate(JSONExtractString(daily,'day')) as day,
  JSONExtractInt(daily,'accepted') as accepted_by_apns,
  JSONExtractInt(daily,'failed') as failed, JSONExtractInt(daily,'skipped') as skipped,
  JSONExtractInt(daily,'pending') as pending_created_that_day, coalesce(opens.opens,0) as recorded_opens
from days left join opens on opens.day=toDate(JSONExtractString(daily,'day')) order by day`;
}


export function notificationUsersCTEs() {
  return `${recipientCTEs(true)}, last_permission as (
  select person_id as observed_person, argMax(toString(properties.status),timestamp) as os_status,
    max(timestamp) as permission_observed_at
  from events where event='permission_status_observed' and properties.permission='notifications'
    and ${productionSQL} and timestamp>=now()-interval 30 day group by person_id
), classified_users as (
  select d.*, coalesce(nullIf(p.os_status,''),'unknown') as os_status,
    if(empty(coalesce(p.os_status,'')),null,p.permission_observed_at) as permission_observed_at,
    multiIf(p.os_status in ('enabled','limited'),'on',p.os_status in ('denied','restricted'),'off',
      p.os_status='not_determined','not_prompted','unknown') as notification_permission
  from directory d left join last_permission p on p.observed_person=d.person_key
), filtered_users as (
  select * from classified_users where {variables.notification_permission}='all'
    or notification_permission={variables.notification_permission}
)`;
}
export function notificationUsersSQL() {
  return `with ${notificationUsersCTEs()}
select username, notification_permission,os_status,
  if(preferences_known='true',push_enabled,'unknown') as app_push_enabled,
  active_production_tokens,permission_observed_at,snapshot_at
from filtered_users order by username limit 10000`;
}
export function notificationAuditSQL(failuresOnly=false) {
  // Dashboard event filters apply to audit records, not to the recipient directory:
  // e.g. audit_status=permanent_token_failure must not erase the current-user join.
  const users=notificationUsersCTEs().replace('and {filters}','');
  return `with ${users}, audit as (
  select toString(properties.audit_id) as audit_id,
    argMax(toString(properties.notification_ref),timestamp) as notification_ref,
    argMax(distinct_id,timestamp) as recipient_id,
    argMax(toString(properties.username),timestamp) as recipient_username,
    argMax(toString(properties.occurred_at),timestamp) as occurred_at,
    argMax(toString(properties.record_kind),timestamp) as record_kind,
    argMax(toString(properties.audit_status),timestamp) as delivery_status,
    argMax(toString(properties.notification_type),timestamp) as notification_type,
    argMax(toString(properties.notification_title),timestamp) as notification_title,
    argMax(toString(properties.notification_body),timestamp) as notification_body,
    argMax(toString(properties.failure_reason),timestamp) as failure_reason,
    argMax(toString(properties.http_status),timestamp) as http_status,
    argMax(toInt(properties.attempt_count),timestamp) as attempt_count,
    argMax(toString(properties.delivery_environment),timestamp) as delivery_environment,
    argMax(toString(properties.history_source),timestamp) as history_source
  from events where event='notification_delivery_audit' and ${recipientGuard}
    and properties.analytics_audience='external_recipients_v1' and timestamp>=now()-interval 32 day
    and toDateTime(properties.occurred_at)>=now()-interval 30 day and {filters}
  group by audit_id
)
select occurred_at,recipient_username,notification_type,notification_title,notification_body,
  delivery_status,failure_reason,http_status,attempt_count,delivery_environment,record_kind,
  history_source,notification_ref,audit_id
from audit where ({variables.notification_permission}='all' or recipient_id in (select user_id from filtered_users))
  ${failuresOnly ? "and delivery_status in ('failed','retryable_failure','permanent_token_failure','permanent_event_failure')" : ''}
order by occurred_at desc,audit_id limit 10000`;
}

const preferenceKeys = ['social_graph','shared_lists','recommendations','capture','discovery_digest','followed_activity','shared_visits','wanna_go_reminders','engagement','reservation_reminders'];
export const permissionInsights = [
  {key:'permissions-users-filtered',name:'Users — notification permission filter',description:'Select Notification permission above: on, off, not_prompted or unknown. Latest observed OS state per user (30 days); app push preference is separate. Missing data is unknown, never not prompted. Username filters also apply. Up to 10,000 users.',query:table(notificationUsersSQL())},
  {key:'permissions-audit-trail',name:'Notifications — delivery audit trail',description:'Last 30 days; newest first, up to 10,000 records. Recipient, title/body, outcome, reason and attempts. Historical snapshots lack overwritten retries; live transitions retain new attempts. Device-attempt rows are per device. APNs acceptance does not confirm display.',query:table(notificationAuditSQL())},
  {key:'permissions-audit-failures',name:'Notifications — failed attempts',description:'Failed notifications and failed device attempts in the last 30 days, including failures later followed by success. Use notification_ref to correlate the full trail. Username, notification permission, audit_status and notification_type filters apply. Up to 10,000 records.',query:table(notificationAuditSQL(true))},

  {key:'permissions-overview',name:'Permissions — latest enablement and coverage',description:'Identified users active in the last 30 days. Latest system status per user/permission. Rate = enabled (including limited) / known status; not-yet-asked stays in the denominator. Missing observations are unknown. New app release required.',query:table(permissionOverviewSQL())},
  {key:'permissions-daily',name:'Permissions — daily observed enablement (%)',description:'Latest observation per user, permission and UTC day. Enabled includes limited access. Known statuses, including not-yet-asked, form the denominator. These are daily observed users, not signup cohorts. New app release required.',query:chart(permissionDailySQL(),permissions)},
  {key:'permissions-onboarding-history',name:'Permissions — historical onboarding decisions',description:'Latest recorded decision per user/permission in 90 days. This measures onboarding decisions, not current OS settings. Recorded true/false results enter the rate; false can include skipping the prompt. Missing decisions are not grants.',query:table(`with decisions as (select person_id,properties.permission as permission,argMax(toString(properties.granted),timestamp) as granted
from events where event='onboarding_permission_result' and ${productionSQL} and timestamp>=now()-interval 90 day group by person_id,permission)
select permission,countIf(granted='true') as granted_users,countIf(granted='false') as not_granted_users,
countIf(granted not in ('true','false')) as other_decisions,
round(100.0*countIf(granted='true')/nullIf(countIf(granted in ('true','false')),0),1) as grant_percent from decisions group by permission order by permission`)},
  {key:'permissions-notification-preferences',name:'Notifications — category enablement',description:'Latest complete server snapshot. Preference rate includes users with known notification settings. Backend-ready also requires master push enabled and an active production token; OS authorization may differ. Local reminder preferences are shown separately from remote delivery.',query:table(`with ${recipientCTEs()}, categories as (select arrayJoin([${sqlList(preferenceKeys)}]) as category)
select category,count() as users_with_settings,
countIf(JSONExtractBool(preferences,category)) as category_enabled_users,
round(100.0*countIf(JSONExtractBool(preferences,category))/nullIf(count(),0),1) as category_enabled_percent,
countIf(JSONExtractBool(preferences,category) and push_enabled='true' and active_production_tokens>0) as backend_ready_users
from directory cross join categories where preferences_known='true' group by category order by category`)},
  {key:'permissions-recipient-directory',name:'Find a username',description:'Use the dashboard filter: username → equals → type or choose a username. This table lists matching accounts; detail charts require exactly one match. Without a filter it lists available usernames. Only the latest complete snapshot is used; stale/missing data is never represented as zero delivery.',query:table(`with ${recipientCTEs(true)} select username,push_enabled,active_production_tokens,snapshot_at from directory order by username limit 100`)},
  {key:'permissions-recipient-status',name:'Selected user — notification readiness',description:'Exact username match. Backend readiness uses the master preference and active production tokens. It does not prove current iOS permission or device delivery. Missing or older-than-2-day snapshots produce an empty result. Snapshot normally refreshes every 15 minutes.',query:table(`with ${selectedCTEs()} select username,
if(preferences_known='true',push_enabled,'unknown') as app_push_enabled, active_production_tokens,
if(preferences_known!='true','unknown',if(push_enabled!='true','disabled in app',if(active_production_tokens=0,'no active production token','backend ready'))) as delivery_readiness,
snapshot_at from selected`)},
  {key:'permissions-recipient-permissions',name:'Selected user — last observed permissions',description:'Latest observed system settings in the last 30 days for the exact selected user. Unknown means this permission has not been observed on an instrumented build. This is the last observed device state; a user may have several devices.',query:table(`with ${selectedCTEs()}, permissions as (select arrayJoin([${sqlList(permissions)}]) as permission), latest as (
select properties.permission as permission,argMax(toString(properties.status),timestamp) as status,max(timestamp) as last_observed
from events where event='permission_status_observed' and ${productionSQL} and person_id in (select person_key from selected)
and timestamp>=now()-interval 30 day group by permission)
select p.permission,coalesce(nullIf(l.status,''),'unknown') as status, if(empty(coalesce(l.status,'')),null,l.last_observed) as last_observed from permissions p
left join latest l on l.permission=p.permission where (select count() from selected)=1 order by p.permission`)},
  {key:'permissions-recipient-daily',name:'Selected user — notifications per day',description:'UTC daily counts, last 30 calendar days including today. Accepted = one notification accepted for at least one production token. Failures/skips use outcome date; pending uses creation date. Opens use tap date. APNs acceptance does not confirm device display.',query:chart(recipientDailySQL(),['accepted_by_apns','recorded_opens'],'ActionsBar')},
  {key:'permissions-recipient-daily-details',name:'Selected user — daily delivery details',description:'Same daily data with failures, skips and currently pending notifications. Zeroes come from the stored delivery ledger; no match or missing snapshot yields no rows. Opens are recorded taps, not matched delivery receipts; do not divide these columns into a per-message open rate.',query:table(recipientDailySQL())},
];

export const permissionSections = [
  {title:'Notification users and audit',body:'Choose Notification permission to filter the user list and audits: all, on, off, not_prompted, or unknown. On includes limited/quiet permission; off includes denied/restricted. App push_enabled is a separate in-app toggle. Add a username filter for one recipient; Use audit_status or notification_type for the audit; clear those filters to browse the user list. New audit rows retain failures and retries with recipient and message text; historical_snapshot rows only preserve the latest old state. Notifications accepted by Apple are not confirmed as displayed. Joe and Ryan are excluded.',insightKeys:permissionInsights.slice(0,3).map(x=>x.key)},
  {title:'Permission enablement',body:'Population metrics in this section cover all external users; username filtering applies to the delivery section below. Current enablement comes from system observations on the new app build. Unknown is separate from denied. Limited contacts/quiet notifications count as enabled, with limited counts visible. Photo permission means saving images; the system photo picker does not request full-library access.',insightKeys:permissionInsights.slice(3,7).map(x=>x.key)},
  {title:'Notification delivery by username',body:'Use Add filter → Event properties → username → equals, then type or choose a username. The detail charts appear when exactly one account matches; the directory lists available accounts. Counts refresh every 15 minutes and cover the last 30 UTC calendar days. “Accepted by APNs” means Apple accepted the request, not proof of banner delivery. Notification text is shown only in the audit section above; device tokens are never exported.',insightKeys:permissionInsights.slice(7).map(x=>x.key)},
];

export async function applyPermissionsDashboard() {
  if(process.env.WANDER_POSTHOG_PROJECT_ID!=='557259') throw Error('Expected Astir project');
  const project=557259, tag='recme:iac:dashboard:permissions-delivery';
  const [dashboards,existing]=await Promise.all([listAll(`/api/projects/${project}/dashboards/?limit=200`),listAll(`/api/projects/${project}/insights/?limit=200`)]);
  const match=dashboards.find(d=>d.tags?.includes(tag));
  const payload={name:'Astir — Permissions & Notification Delivery',description:'Permission enablement and username-searchable daily notification delivery. Joe and Ryan excluded. Managed by scripts/posthog-permissions-dashboard.mjs.',tags:['recme:managed',tag],pinned:true};
  const dashboard=await api(`/api/projects/${project}/dashboards/${match?match.id+'/':''}`,{method:match?'PATCH':'POST',body:payload});
  const created=[];
  for(const definition of permissionInsights) created.push(await upsertInsight(project,dashboard.id,definition,existing));
  const current=await api(`/api/projects/${project}/dashboards/${dashboard.id}/`);
  const headers=[];
  for(const section of permissionSections) headers.push(await upsertSectionTile(project,dashboard.id,section,current.tiles));
  const saved=await api(`/api/projects/${project}/dashboards/${dashboard.id}/`);
  // Recipient and message columns need a full row on desktop. Preserve all other tile sizes.
  const wideKeys=permissionInsights.slice(0,3).map(definition=>'recme:iac:insight:'+definition.key);
  const wideTiles=saved.tiles.filter(tile=>tile.insight?.tags?.some(tag=>wideKeys.includes(tag)));
  await api(`/api/projects/${project}/dashboards/${dashboard.id}/`,{method:'PATCH',body:{
    tiles:wideTiles.map(tile=>({id:tile.id,layouts:{...tile.layouts,sm:{...tile.layouts?.sm,x:0,w:12}}})),
  }});
  const order=permissionSections.flatMap((section,i)=>[headers[i].id,...section.insightKeys.map(key=>saved.tiles.find(t=>t.insight?.tags?.includes('recme:iac:insight:'+key)).id)]);
  for(const tile of saved.tiles) if(!order.includes(tile.id))order.push(tile.id);
  await api(`/api/projects/${project}/dashboards/${dashboard.id}/reorder_tiles/`,{method:'POST',body:{tile_order:order,layout:'preserve'}});
  return {dashboardID:dashboard.id,insights:created.map(({id,short_id})=>({id,short_id}))};
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href) {
  if(process.argv.includes('--apply'))console.log(JSON.stringify(await applyPermissionsDashboard()));
  else console.log(JSON.stringify({insights:permissionInsights.length,permissions}));
}
