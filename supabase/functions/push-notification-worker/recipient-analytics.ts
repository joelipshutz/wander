// User-authorized support diagnostics. Never accept arbitrary event properties here.
export type RecipientSnapshot = {
  snapshot_at: string;
  window_days: number;
  analytics_audience: string;
  recipients: Array<{
    user_id: string;
    username: string;
    push_enabled: boolean;
    preferences_known: boolean;
    active_production_tokens: number;
    preferences: Record<string, boolean>;
    daily_counts: Array<{day: string; accepted: number; failed: number; skipped: number; pending: number}>;
  }>;
};

export const preferenceKeys = ["social_graph", "shared_lists", "recommendations", "capture", "discovery_digest", "followed_activity", "shared_visits", "wanna_go_reminders", "engagement", "reservation_reminders"];

export function recipientAnalyticsEvents(snapshot: RecipientSnapshot, excludedIDs: Set<string>) {
  if (snapshot.analytics_audience !== "external_recipients_v1") throw Error("Invalid recipient analytics audience");
  const common = {
    snapshot_id: snapshot.snapshot_at,
    window_days: snapshot.window_days,
    analytics_audience: snapshot.analytics_audience,
    analytics_schema_version: "1",
    platform: "server",
    source: "notification_recipient_snapshot",
    $geoip_disable: true,
    $process_person_profile: false,
  };
  const rows = snapshot.recipients.filter(row => !excludedIDs.has(row.user_id)).map(row => ({
    event: "notification_recipient_snapshot",
    properties: {
      ...common,
      distinct_id: row.user_id,
      username: row.username.slice(0, 64),
      push_enabled: row.push_enabled,
      preferences_known: row.preferences_known,
      active_production_tokens: row.active_production_tokens,
      preferences: JSON.stringify(Object.fromEntries(preferenceKeys.map(key => [key, row.preferences[key] === true]))),
      daily_counts: JSON.stringify(row.daily_counts.map(day => ({
        day: day.day, accepted: day.accepted, failed: day.failed, skipped: day.skipped, pending: day.pending,
      }))),
    },
  }));
  const completion = {
    event: "notification_recipient_snapshot_completed",
    properties: {...common, distinct_id: "notification_operations", recipient_count: rows.length},
  };
  return { rows, completion };
}
