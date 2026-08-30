begin;

-- Keep duplicate in-flight calls suppressed, but tell the client when a prior
-- attempt finished and its response must be replayed with a fresh opaque ID.
-- This preserves the no-content database boundary: results, URLs, captions,
-- media, and extracted place data are never cached in Postgres.
create or replace function public.begin_social_import_paid_work(
  input_client_request_id text
)
returns table (
  admitted boolean,
  decision text,
  admission_id uuid
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  viewer_id text := app.current_user_id();
  admission_now timestamptz := pg_catalog.clock_timestamp();
  new_admission_id uuid;
  active_count integer;
  recent_start_count integer;
  paid_import_enabled boolean;
begin
  if viewer_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if input_client_request_id is null
     or pg_catalog.char_length(input_client_request_id) not between 1 and 160
     or input_client_request_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'invalid_client_request_id' using errcode = '22023';
  end if;

  select coalesce(
    (
      select flag.enabled
      from public.feature_flags as flag
      where flag.key = 'social_import_apify_gemini_v1'
        and flag.user_id = viewer_id
        and flag.value_type = 'boolean'
        and flag.integer_value is null
      limit 1
    ),
    (
      select flag.enabled
      from public.feature_flags as flag
      where flag.key = 'social_import_apify_gemini_v1'
        and flag.user_id is null
        and flag.value_type = 'boolean'
        and flag.integer_value is null
      limit 1
    ),
    false
  )
  into paid_import_enabled;

  if not paid_import_enabled then
    return query select false, 'disabled'::text, null::uuid;
    return;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('recme:social-import-paid-work:' || viewer_id, 0)
  );

  update app.social_import_paid_work_admissions as admission
  set state = 'expired',
      finished_at = admission_now
  where admission.user_id = viewer_id
    and admission.state = 'in_flight'
    and admission.started_at <= admission_now - interval '5 minutes';

  if exists (
    select 1
    from app.social_import_paid_work_admissions as admission
    where admission.user_id = viewer_id
      and admission.client_request_id = input_client_request_id
      and admission.state = 'in_flight'
  ) then
    return query select false, 'duplicate'::text, null::uuid;
    return;
  end if;

  if exists (
    select 1
    from app.social_import_paid_work_admissions as admission
    where admission.user_id = viewer_id
      and admission.client_request_id = input_client_request_id
      and admission.state = 'finished'
  ) then
    return query select false, 'replay_required'::text, null::uuid;
    return;
  end if;

  select pg_catalog.count(*)::integer
  into active_count
  from app.social_import_paid_work_admissions as admission
  where admission.user_id = viewer_id
    and admission.state = 'in_flight';

  if active_count >= 3 then
    return query select false, 'busy'::text, null::uuid;
    return;
  end if;

  select pg_catalog.count(*)::integer
  into recent_start_count
  from app.social_import_paid_work_admissions as admission
  where admission.user_id = viewer_id
    and admission.started_at > admission_now - interval '24 hours';

  if recent_start_count >= 20 then
    return query select false, 'quota'::text, null::uuid;
    return;
  end if;

  insert into app.social_import_paid_work_admissions (
    user_id,
    client_request_id,
    state,
    started_at,
    finished_at
  ) values (
    viewer_id,
    input_client_request_id,
    'in_flight',
    admission_now,
    null
  )
  returning id into new_admission_id;

  return query select true, 'started'::text, new_admission_id;
end;
$$;

revoke all on function public.begin_social_import_paid_work(text)
  from public, anon, service_role;
grant execute on function public.begin_social_import_paid_work(text)
  to authenticated;

comment on function public.begin_social_import_paid_work(text) is
  'Atomically admits bounded authenticated social-import work; finished request IDs return replay_required without storing private result content.';

commit;
