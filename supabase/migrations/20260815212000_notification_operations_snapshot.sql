begin;

create or replace function app.notification_operations_snapshot(
  input_window_days integer default 30
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, app
as $$
declare
  bounded_window_days integer := least(greatest(coalesce(input_window_days, 30), 1), 90);
  output_payload jsonb;
begin
  with eligible_recipients as (
    select distinct token.user_id
    from public.notification_device_tokens token
    join public.notification_preferences preferences
      on preferences.user_id = token.user_id
    join public.profiles profile
      on profile.id = token.user_id
     and profile.deleted_at is null
    where token.is_active
      and preferences.push_enabled
  ), per_recipient as (
    select
      eligible.user_id,
      count(event.id)::integer as accepted_notification_count
    from eligible_recipients eligible
    left join public.notification_events event
      on event.recipient_user_id = eligible.user_id
     and event.status = 'sent'
     and event.accepted_at >= now() - make_interval(days => bounded_window_days)
    group by eligible.user_id
  ), summary as (
    select
      count(*)::integer as eligible_recipient_count,
      coalesce(sum(accepted_notification_count), 0)::integer as accepted_notification_count,
      round(coalesce(avg(accepted_notification_count), 0), 2) as average_per_recipient,
      coalesce(
        percentile_disc(0.5) within group (order by accepted_notification_count),
        0
      )::integer as p50_per_recipient,
      coalesce(
        percentile_disc(0.9) within group (order by accepted_notification_count),
        0
      )::integer as p90_per_recipient,
      coalesce(max(accepted_notification_count), 0)::integer as max_per_recipient
    from per_recipient
  ), bucket_definitions(bucket_order, bucket) as (
    values
      (0, '0'),
      (1, '1'),
      (2, '2-3'),
      (3, '4-7'),
      (4, '8-14'),
      (5, '15-29'),
      (6, '30+')
  ), bucket_counts as (
    select
      definition.bucket_order,
      definition.bucket,
      count(recipient.user_id) filter (
        where case definition.bucket
          when '0' then recipient.accepted_notification_count = 0
          when '1' then recipient.accepted_notification_count = 1
          when '2-3' then recipient.accepted_notification_count between 2 and 3
          when '4-7' then recipient.accepted_notification_count between 4 and 7
          when '8-14' then recipient.accepted_notification_count between 8 and 14
          when '15-29' then recipient.accepted_notification_count between 15 and 29
          when '30+' then recipient.accepted_notification_count >= 30
          else false
        end
      )::integer as recipient_count
    from bucket_definitions definition
    left join per_recipient recipient on true
    group by definition.bucket_order, definition.bucket
  )
  select jsonb_build_object(
    'window_days', bounded_window_days,
    'eligible_recipient_count', summary.eligible_recipient_count,
    'accepted_notification_count', summary.accepted_notification_count,
    'average_per_recipient', summary.average_per_recipient,
    'p50_per_recipient', summary.p50_per_recipient,
    'p90_per_recipient', summary.p90_per_recipient,
    'max_per_recipient', summary.max_per_recipient,
    'histogram', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'bucket_order', bucket_order,
          'bucket', bucket,
          'recipient_count', recipient_count
        )
        order by bucket_order
      )
      from bucket_counts
    ), '[]'::jsonb)
  )
  into output_payload
  from summary;

  return output_payload;
end;
$$;

create or replace function public.notification_operations_snapshot(
  input_window_days integer default 30
)
returns jsonb
language sql
stable
security definer
set search_path = app, public
as $$
  select app.notification_operations_snapshot(input_window_days);
$$;

comment on function public.notification_operations_snapshot(integer) is
  'Service-role-only aggregate notification frequency snapshot. Returns no recipient identifiers or notification content.';

revoke all on function app.notification_operations_snapshot(integer)
  from public, anon, authenticated;
revoke all on function public.notification_operations_snapshot(integer)
  from public, anon, authenticated;
grant execute on function app.notification_operations_snapshot(integer)
  to service_role;
grant execute on function public.notification_operations_snapshot(integer)
  to service_role;

commit;
