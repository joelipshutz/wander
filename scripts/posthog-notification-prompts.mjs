// Client prompt metrics. Correlate by a random presentation ID so repeated
// Settings taps cannot inflate conversion or join to another reminder.
const promptVersionSQL = `properties.prompt_analytics_version = '1'
  and coalesce(toString(properties.presentation_id), '') != ''`;

// Match the staff exclusions already applied to the live launch dashboard by
// REC-581, including when this module is applied from an older branch.
const promptStaffSQL = `person_id not in (
  select person_id from events where distinct_id in (
    'user_3EhATWssjvHxwGiUaoWR5VTgeoy', 'user_3EsQ6OZGVoIBhjfDUUfDhpa0PLc'
  )
)`;

function promptEventSource(productionSQL) {
  return `select person_id, event, properties.presentation_id as presentation_id,
    properties.campaign as campaign, properties.trigger as trigger,
    properties.impression_number as impression_number, properties.button as button
  from events
  where timestamp >= now() - interval 30 day and ${productionSQL}
    and ${promptStaffSQL} and ${promptVersionSQL}
    and event in ('product_upsell_shown', 'product_upsell_button_clicked')`;
}

function notificationPromptClickSQL(productionSQL, button, source = promptEventSource(productionSQL)) {
  if (!["continue", "open_settings", "not_now"].includes(button)) throw new Error("Unknown prompt button");
  return `with prompt_events as (${source}), presentations as (
  select person_id, presentation_id, campaign, trigger, impression_number,
    max(if(event = 'product_upsell_shown', 1, 0)) as has_show,
    countIf(event = 'product_upsell_button_clicked' and button = '${button}') as clicks
  from prompt_events
  group by person_id, presentation_id, campaign, trigger, impression_number
)
select campaign, trigger, impression_number, count() as shown_prompts,
  countIf(clicks > 0) as clicked_prompts, sum(clicks) as total_clicks,
  round(100.0 * countIf(clicks > 0) / nullIf(count(), 0), 1) as click_percent
from presentations where has_show = 1
group by campaign, trigger, impression_number
order by campaign, trigger, impression_number`;
}

function notificationPromptInsights(productionSQL) {
  const filter = `${productionSQL} and ${promptStaffSQL}`;
  return [
    {
      key: "notification-prompts-reach",
      name: "Notification prompt — reach",
      description: "Fixed last 30 days. Reach = shown users / users with any schema-3 production client event. Includes distinct users and prompt counts. New correlated shows only; no historical backfill. Excludes staff, internal/test people and development traffic. This is exposure, not notification permission or delivery.",
      query: { kind: "HogQLQuery", query: `select
  uniq(person_id) as active_users,
  uniqIf(person_id, event = 'product_upsell_shown' and ${promptVersionSQL}) as shown_users,
  uniqIf(properties.presentation_id, event = 'product_upsell_shown' and ${promptVersionSQL}) as shown_prompts,
  round(100.0 * uniqIf(person_id, event = 'product_upsell_shown' and ${promptVersionSQL}) / nullIf(uniq(person_id), 0), 1) as shown_user_percent
from events where timestamp >= now() - interval 30 day and ${filter}` }
    },
    ...[["continue", "Continue"], ["open_settings", "Open Settings"], ["not_now", "Not now"]].map(([button, title]) => ({
      key: `notification-prompts-${button.replaceAll("_", "-")}`,
      name: `Notification prompt — ${title} click %`,
      description: `Last 30 days: prompts with a ${title} click / all matching shows, including shows without this button. Repeat taps count once in the percentage. Split by campaign, trigger and reminder number. Button rates may overlap; these are taps, not permission grants. New correlated events only; production, excluding staff/test users.`,
      query: { kind: "HogQLQuery", query: notificationPromptClickSQL(productionSQL, button) }
    }))
  ];
}

export { notificationPromptInsights, notificationPromptClickSQL };
