begin;

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id text not null references public.profiles(id) on delete cascade,
  reported_user_id text not null references public.profiles(id) on delete cascade,
  subject_kind text not null check (
    subject_kind in ('profile', 'activity', 'comment', 'user_place', 'visit_photo', 'place_list')
  ),
  subject_id text not null,
  reason text not null check (
    reason in (
      'spam',
      'harassment',
      'hate_or_abuse',
      'sexual_content',
      'dangerous_content',
      'impersonation',
      'privacy',
      'other'
    )
  ),
  details text,
  content_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check (
    status in ('queued', 'reviewing', 'resolved', 'dismissed')
  ),
  priority text not null default 'normal' check (priority in ('normal', 'urgent')),
  assigned_to text,
  resolution_action text check (
    resolution_action is null or resolution_action in (
      'content_removed',
      'warning_issued',
      'account_suspended',
      'account_removed',
      'no_violation'
    )
  ),
  resolution_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz,
  check (reporter_user_id <> reported_user_id),
  check (char_length(subject_id) between 1 and 200),
  check (details is null or char_length(details) between 1 and 500)
);

create index content_reports_queue_idx
  on public.content_reports (status, priority desc, created_at asc);
create index content_reports_reporter_subject_idx
  on public.content_reports (reporter_user_id, subject_kind, subject_id, created_at desc);
create index content_reports_reported_user_idx
  on public.content_reports (reported_user_id, created_at desc);

create table public.moderation_report_events (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.content_reports(id) on delete restrict,
  actor_id text not null,
  action text not null,
  previous_status text,
  next_status text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index moderation_report_events_report_idx
  on public.moderation_report_events (report_id, created_at asc);

alter table public.content_reports enable row level security;
alter table public.moderation_report_events enable row level security;

revoke all on table public.content_reports from public, anon, authenticated;
revoke all on table public.moderation_report_events from public, anon, authenticated;
grant select, update on table public.content_reports to service_role;
grant select, insert on table public.moderation_report_events to service_role;

create function app.normalized_community_text(input_text text)
returns text
language sql
immutable
strict
security invoker
set search_path = pg_catalog
as $$
  select btrim(
    regexp_replace(
      regexp_replace(
        lower(translate(input_text, '013457@$', 'oieastas')),
        '[^a-z0-9]+',
        ' ',
        'g'
      ),
      '\s+',
      ' ',
      'g'
    )
  );
$$;

create function app.community_text_allowed(input_text text)
returns boolean
language sql
immutable
security invoker
set search_path = pg_catalog, app
as $$
  with normalized as (
    select app.normalized_community_text(coalesce(input_text, '')) as value
  )
  select value = '' or (
    value !~ '(^| )(chink|faggot|kike|kys|nigga|nigger|spic)( |$)'
    and (' ' || value || ' ') not like '% child porn %'
    and (' ' || value || ' ') not like '% child pornography %'
    and (' ' || value || ' ') not like '% go kill yourself %'
    and (' ' || value || ' ') not like '% heil hitler %'
    and (' ' || value || ' ') not like '% i will kill you %'
    and (' ' || value || ' ') not like '% kill yourself %'
    and (' ' || value || ' ') not like '% rape you %'
  )
  from normalized;
$$;

create function app.assert_community_text(input_text text)
returns void
language plpgsql
immutable
security invoker
set search_path = pg_catalog, app
as $$
begin
  if not app.community_text_allowed(input_text) then
    raise exception 'content_not_allowed' using errcode = '22023';
  end if;
end;
$$;

create function app.enforce_community_text_policy()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
begin
  case tg_table_name
    when 'profiles' then
      perform app.assert_community_text(new.display_name);
      perform app.assert_community_text(new.handle);
      perform app.assert_community_text(new.bio);
      perform app.assert_community_text(new.home_area);
    when 'user_places' then
      perform app.assert_community_text(new.note);
    when 'place_visits' then
      perform app.assert_community_text(new.note);
      perform app.assert_community_text(new.attribute_answers::text);
    when 'place_attributes' then
      perform app.assert_community_text(new.value::text);
    when 'place_lists' then
      perform app.assert_community_text(new.name);
      perform app.assert_community_text(new.description);
    when 'activity_comments' then
      perform app.assert_community_text(new.body);
  end case;
  return new;
end;
$$;

create trigger profiles_community_text_guard
before insert or update of display_name, handle, bio, home_area on public.profiles
for each row execute function app.enforce_community_text_policy();

create trigger user_places_community_text_guard
before insert or update of note on public.user_places
for each row execute function app.enforce_community_text_policy();

create trigger place_visits_community_text_guard
before insert or update of note, attribute_answers on public.place_visits
for each row execute function app.enforce_community_text_policy();

create trigger place_attributes_community_text_guard
before insert or update of value on public.place_attributes
for each row execute function app.enforce_community_text_policy();

create trigger place_lists_community_text_guard
before insert or update of name, description on public.place_lists
for each row execute function app.enforce_community_text_policy();

create trigger activity_comments_community_text_guard
before insert or update of body on public.activity_comments
for each row execute function app.enforce_community_text_policy();

create function app.audit_content_report_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, app
as $$
declare
  actor text := coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''), current_user);
begin
  if tg_op = 'INSERT' then
    insert into public.moderation_report_events (
      report_id, actor_id, action, previous_status, next_status
    ) values (
      new.id, actor, 'submitted', null, new.status
    );
    return new;
  end if;

  if new.status is distinct from old.status
     or new.assigned_to is distinct from old.assigned_to
     or new.resolution_action is distinct from old.resolution_action
     or new.resolution_notes is distinct from old.resolution_notes then
    insert into public.moderation_report_events (
      report_id,
      actor_id,
      action,
      previous_status,
      next_status,
      metadata
    ) values (
      new.id,
      actor,
      case
        when new.status is distinct from old.status then 'status_changed'
        when new.assigned_to is distinct from old.assigned_to then 'assigned'
        else 'resolution_updated'
      end,
      old.status,
      new.status,
      jsonb_strip_nulls(jsonb_build_object(
        'assigned_to', new.assigned_to,
        'resolution_action', new.resolution_action
      ))
    );
  end if;
  return new;
end;
$$;

create function app.prepare_content_report_update()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  new.updated_at := now();
  if new.status in ('resolved', 'dismissed') then
    if new.resolution_action is null then
      raise exception 'moderation_resolution_required' using errcode = '23514';
    end if;
    new.closed_at := coalesce(new.closed_at, now());
  else
    new.closed_at := null;
  end if;
  return new;
end;
$$;

create trigger content_reports_prepare_update
before update on public.content_reports
for each row execute function app.prepare_content_report_update();

create trigger content_reports_audit
after insert or update on public.content_reports
for each row execute function app.audit_content_report_change();

create function public.submit_content_report(
  input_subject_kind text,
  input_subject_id text,
  input_reported_user_id text,
  input_reason text,
  input_details text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, app
as $$
declare
  viewer_id text := app.current_user_id();
  normalized_subject_id text := btrim(coalesce(input_subject_id, ''));
  normalized_details text := nullif(btrim(coalesce(input_details, '')), '');
  subject_uuid uuid;
  snapshot jsonb := '{}'::jsonb;
  existing_report public.content_reports;
  saved_report public.content_reports;
begin
  if viewer_id is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  if viewer_id = input_reported_user_id then
    raise exception 'cannot_report_self' using errcode = '22023';
  end if;
  if input_subject_kind not in ('profile', 'activity', 'comment', 'user_place', 'visit_photo', 'place_list') then
    raise exception 'invalid_report_subject' using errcode = '22023';
  end if;
  if input_reason not in (
    'spam', 'harassment', 'hate_or_abuse', 'sexual_content',
    'dangerous_content', 'impersonation', 'privacy', 'other'
  ) then
    raise exception 'invalid_report_reason' using errcode = '22023';
  end if;
  if normalized_subject_id = '' or char_length(normalized_subject_id) > 200 then
    raise exception 'invalid_report_subject' using errcode = '22023';
  end if;
  if normalized_details is not null and char_length(normalized_details) > 500 then
    raise exception 'report_details_too_long' using errcode = '22023';
  end if;
  perform app.assert_community_text(normalized_details);

  if (
    select count(*)
    from public.content_reports report
    where report.reporter_user_id = viewer_id
      and report.created_at >= now() - interval '1 hour'
  ) >= 30 then
    raise exception 'report_rate_limited' using errcode = '54000';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = input_reported_user_id and deleted_at is null
  ) then
    raise exception 'reported_user_not_found' using errcode = 'P0002';
  end if;

  if input_subject_kind = 'profile' then
    if normalized_subject_id <> input_reported_user_id
       or not app.can_read_profile(input_reported_user_id) then
      raise exception 'report_subject_not_visible' using errcode = '42501';
    end if;
    select jsonb_strip_nulls(jsonb_build_object(
      'display_name', profile.display_name,
      'handle', profile.handle,
      'bio', profile.bio,
      'home_area', profile.home_area
    )) into snapshot
    from public.profiles profile
    where profile.id = input_reported_user_id and profile.deleted_at is null;
  else
    begin
      subject_uuid := normalized_subject_id::uuid;
    exception when invalid_text_representation then
      raise exception 'invalid_report_subject' using errcode = '22023';
    end;

    case input_subject_kind
      when 'activity' then
        select jsonb_strip_nulls(jsonb_build_object(
          'event_type', event.event_type,
          'note', user_place.note,
          'list_name', place_list.name,
          'list_description', place_list.description
        )) into snapshot
        from public.feed_events event
        left join public.user_places user_place on user_place.id = event.user_place_id
        left join public.place_lists place_list on place_list.id = event.list_id
        where event.id = subject_uuid
          and event.actor_user_id = input_reported_user_id
          and app.can_read_activity_event(viewer_id, event.id);
      when 'comment' then
        select jsonb_build_object('body', comment.body) into snapshot
        from public.activity_comments comment
        where comment.id = subject_uuid
          and comment.author_user_id = input_reported_user_id
          and app.can_read_activity_event(viewer_id, comment.activity_id);
      when 'user_place' then
        select jsonb_strip_nulls(jsonb_build_object('note', user_place.note)) into snapshot
        from public.user_places user_place
        where user_place.id = subject_uuid
          and user_place.user_id = input_reported_user_id
          and user_place.deleted_at is null
          and app.can_read_user_place(viewer_id, user_place.user_id, user_place.visibility);
      when 'visit_photo' then
        select jsonb_build_object(
          'storage_bucket', photo.storage_bucket,
          'storage_path', photo.storage_path,
          'visit_id', photo.visit_id
        ) into snapshot
        from public.visit_photos photo
        join public.place_visits visit on visit.id = photo.visit_id
        join public.user_places user_place on user_place.id = visit.user_place_id
        where photo.id = subject_uuid
          and user_place.user_id = input_reported_user_id
          and photo.deleted_at is null
          and visit.deleted_at is null
          and app.can_read_place_visit(visit.id);
      when 'place_list' then
        select jsonb_build_object(
          'name', place_list.name,
          'description', place_list.description
        ) into snapshot
        from public.place_lists place_list
        where place_list.id = subject_uuid
          and place_list.owner_user_id = input_reported_user_id
          and place_list.deleted_at is null
          and app.can_read_place_list(place_list.id, viewer_id);
    end case;

    if snapshot is null then
      raise exception 'report_subject_not_visible' using errcode = '42501';
    end if;
  end if;

  select * into existing_report
  from public.content_reports report
  where report.reporter_user_id = viewer_id
    and report.subject_kind = input_subject_kind
    and report.subject_id = normalized_subject_id
    and report.reason = input_reason
    and report.created_at >= now() - interval '24 hours'
  order by report.created_at desc
  limit 1;

  if existing_report.id is not null then
    return jsonb_build_object(
      'report_id', existing_report.id,
      'status', existing_report.status,
      'created_at', existing_report.created_at,
      'is_duplicate', true
    );
  end if;

  insert into public.content_reports (
    reporter_user_id,
    reported_user_id,
    subject_kind,
    subject_id,
    reason,
    details,
    content_snapshot,
    priority
  ) values (
    viewer_id,
    input_reported_user_id,
    input_subject_kind,
    normalized_subject_id,
    input_reason,
    normalized_details,
    snapshot,
    case when input_reason in ('dangerous_content', 'sexual_content') then 'urgent' else 'normal' end
  ) returning * into saved_report;

  return jsonb_build_object(
    'report_id', saved_report.id,
    'status', saved_report.status,
    'created_at', saved_report.created_at,
    'is_duplicate', false
  );
end;
$$;

revoke all on function app.normalized_community_text(text) from public, anon, authenticated;
revoke all on function app.community_text_allowed(text) from public, anon, authenticated;
revoke all on function app.assert_community_text(text) from public, anon, authenticated;
revoke all on function app.enforce_community_text_policy() from public, anon, authenticated;
revoke all on function app.audit_content_report_change() from public, anon, authenticated;
revoke all on function app.prepare_content_report_update() from public, anon, authenticated;
revoke all on function public.submit_content_report(text, text, text, text, text) from public, anon;
grant execute on function public.submit_content_report(text, text, text, text, text) to authenticated;

comment on table public.content_reports is
  'Private abuse reports available only to the service-role moderation workflow.';
comment on table public.moderation_report_events is
  'Append-only moderation status and assignment audit trail.';
comment on function public.submit_content_report(text, text, text, text, text) is
  'Creates a private report after verifying the authenticated viewer can see the reported subject.';

commit;
