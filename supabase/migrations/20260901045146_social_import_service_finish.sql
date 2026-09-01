begin;

-- Provider/model work can outlive the caller's short-lived Clerk bearer. Keep
-- the existing authenticated finish RPC unchanged, and give the Edge Function
-- one service-only cleanup path that cannot select a user account. The exact
-- admission UUID plus opaque request ID resolves ownership inside Postgres.
create function public.finish_social_import_paid_work_service(
  input_client_request_id text,
  input_admission_id uuid
)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  admission_now timestamptz := pg_catalog.clock_timestamp();
  admission_user_id text;
  updated_count integer;
begin
  if input_client_request_id is null
     or pg_catalog.char_length(input_client_request_id) not between 1 and 160
     or input_client_request_id !~ '^[A-Za-z0-9._:-]+$'
     or input_admission_id is null then
    raise exception 'invalid_admission_identity' using errcode = '22023';
  end if;

  select admission.user_id
  into admission_user_id
  from app.social_import_paid_work_admissions as admission
  where admission.id = input_admission_id
    and admission.client_request_id = input_client_request_id;

  if admission_user_id is null then
    return false;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'recme:social-import-paid-work:' || admission_user_id,
      0
    )
  );

  update app.social_import_paid_work_admissions as admission
  set state = 'expired',
      finished_at = admission_now
  where admission.user_id = admission_user_id
    and admission.state = 'in_flight'
    and admission.started_at <= admission_now - interval '5 minutes';

  -- Match the authenticated finish contract when a very late orphan races a
  -- replacement attempt for the same account and request ID.
  if exists (
    select 1
    from app.social_import_paid_work_admissions as completed
    where completed.user_id = admission_user_id
      and completed.client_request_id = input_client_request_id
      and completed.state = 'finished'
  ) then
    update app.social_import_paid_work_admissions as admission
    set state = 'expired',
        finished_at = admission_now
    where admission.id = input_admission_id
      and admission.user_id = admission_user_id
      and admission.client_request_id = input_client_request_id
      and admission.state = 'in_flight';
    return false;
  end if;

  update app.social_import_paid_work_admissions as admission
  set state = 'finished',
      finished_at = admission_now
  where admission.id = input_admission_id
    and admission.user_id = admission_user_id
    and admission.client_request_id = input_client_request_id
    and admission.state = 'in_flight';

  get diagnostics updated_count = row_count;
  return updated_count = 1;
end;
$$;

revoke all on function public.finish_social_import_paid_work_service(text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.finish_social_import_paid_work_service(text, uuid)
  to service_role;

comment on function public.finish_social_import_paid_work_service(text, uuid) is
  'Service-role-only completion for an exact admitted social-import attempt; derives owner from the admission and accepts no user ID.';

commit;
