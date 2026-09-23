// Explicitly requested notification text is confined to this support audit export.
export type NotificationAuditRow = {
  audit_id: string; notification_ref: string; user_id: string; username: string;
  recorded_at: string; occurred_at: string; record_kind: string; status: string;
  environment: string; attempt_count: number; notification_type: string;
  title: string; body: string; reason: string|null; http_status: number|null; history_source: string;
};
export function notificationAuditEvents(rows: NotificationAuditRow[], excluded: Set<string>) {
  return rows.filter(row=>!excluded.has(row.user_id)).map(row=>({
    event:'notification_delivery_audit',
    properties:{
      distinct_id:row.user_id, $process_person_profile:false, $geoip_disable:true,
      analytics_schema_version:'1', analytics_audience:'external_recipients_v1', platform:'server',
      audit_id:row.audit_id, notification_ref:row.notification_ref, username:row.username,
      occurred_at:row.occurred_at, recorded_at:row.recorded_at, record_kind:row.record_kind,
      audit_status:row.status, delivery_environment:row.environment,
      attempt_count:row.attempt_count, notification_type:row.notification_type,
      notification_title:row.title, notification_body:row.body,
      ...(row.reason === null ? {} : {failure_reason:row.reason}),
      ...(row.http_status === null ? {} : {http_status:row.http_status}),
      history_source:row.history_source,
    },
  }));
}
export async function exportNotificationAudit(
  rpc: <T>(name:string,body:Record<string,unknown>)=>Promise<T>,
  capture:(events:ReturnType<typeof notificationAuditEvents>)=>Promise<boolean>,
  excluded:Set<string>,
):Promise<{ok:boolean;exported:number}> {
  let exported=0;
  // Bound each cron run. Unacknowledged rows remain pending, including late commits.
  for(let page=0;page<10;page++) {
    const rows=await rpc<NotificationAuditRow[]>('notification_audit_export_batch',{input_limit:200});
    if(rows.length===0)return {ok:true,exported};
    const events=notificationAuditEvents(rows,excluded);
    if(events.length>0&&!await capture(events))return {ok:false,exported};
    await rpc('ack_notification_audit_export',{input_ids:rows.map(row=>row.audit_id)});
    exported+=events.length;
  }
  return {ok:true,exported};
}
