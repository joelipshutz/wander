begin;

alter table public.user_places
  add column if not exists planned_date date;

create or replace function app.normalize_user_place_planned_date()
returns trigger
language plpgsql
security invoker
set search_path = public, app
as $$
begin
  if new.status <> 'wanna_go' then
    new.planned_date := null;
  end if;
  return new;
end;
$$;

drop trigger if exists user_places_normalize_planned_date on public.user_places;
create trigger user_places_normalize_planned_date
  before insert or update of status, planned_date on public.user_places
  for each row execute function app.normalize_user_place_planned_date();

alter table public.user_places
  drop constraint if exists user_places_planned_date_requires_wanna_go;
alter table public.user_places
  add constraint user_places_planned_date_requires_wanna_go check (
    planned_date is null or status = 'wanna_go'
  );

create or replace function public.save_own_place(
  input_place jsonb,
  input_user_place jsonb,
  input_attributes jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = app, public
as $$
declare
  viewer_id text := app.current_user_id();
  saved public.user_places;
  requested_planned_date date;
  planned_date_kind text;
begin
  if viewer_id is null then
    raise exception 'not_authenticated';
  end if;

  select *
  into saved
  from app.save_own_place(input_place, input_user_place, input_attributes);

  if input_user_place ? 'planned_date' then
    planned_date_kind := jsonb_typeof(input_user_place->'planned_date');
    if planned_date_kind not in ('string', 'null') then
      raise exception 'invalid_planned_date';
    end if;

    if planned_date_kind = 'string' then
      begin
        requested_planned_date := (input_user_place->>'planned_date')::date;
      exception
        when invalid_datetime_format or datetime_field_overflow then
          raise exception 'invalid_planned_date';
      end;
    end if;

    if requested_planned_date is not null
       and input_user_place->>'status' <> 'wanna_go' then
      raise exception 'planned_date_requires_wanna_go';
    end if;

    update public.user_places
    set planned_date = requested_planned_date
    where id = saved.id
      and user_id = viewer_id
    returning * into saved;
  end if;

  return jsonb_build_object(
    'user_place_id', saved.id,
    'place_id', saved.place_id
  );
end;
$$;

create or replace function public.own_wanna_go_plans()
returns table (
  user_place_id uuid,
  place_id uuid,
  planned_date date
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select
    user_place.id,
    user_place.place_id,
    user_place.planned_date
  from public.user_places user_place
  where user_place.user_id = app.current_user_id()
    and user_place.status = 'wanna_go'
    and user_place.planned_date is not null
    and user_place.deleted_at is null
  order by user_place.planned_date, user_place.id;
$$;

alter table public.notification_preferences
  add column if not exists wanna_go_reminders_enabled boolean not null default false;

alter table public.notification_preferences
  alter column wanna_go_reminders_enabled set default false;

create or replace function public.update_notification_preferences(input_preferences jsonb)
returns public.notification_preferences
language plpgsql
security definer
set search_path = public, app
as $$
declare
  viewer_id text := app.current_user_id();
  output_preferences public.notification_preferences;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  if coalesce(jsonb_typeof(input_preferences), '') <> 'object' then
    raise exception 'invalid_notification_preferences_payload';
  end if;

  perform app.ensure_notification_preferences(viewer_id);
  update public.notification_preferences set
    push_enabled = coalesce((input_preferences->>'push_enabled')::boolean, push_enabled),
    social_graph_enabled = coalesce((input_preferences->>'social_graph_enabled')::boolean, social_graph_enabled),
    shared_lists_enabled = coalesce((input_preferences->>'shared_lists_enabled')::boolean, shared_lists_enabled),
    shared_visits_enabled = coalesce((input_preferences->>'shared_visits_enabled')::boolean, shared_visits_enabled),
    recommendations_enabled = coalesce((input_preferences->>'recommendations_enabled')::boolean, recommendations_enabled),
    capture_enabled = coalesce((input_preferences->>'capture_enabled')::boolean, capture_enabled),
    discovery_digest_enabled = coalesce((input_preferences->>'discovery_digest_enabled')::boolean, discovery_digest_enabled),
    followed_activity_enabled = coalesce((input_preferences->>'followed_activity_enabled')::boolean, followed_activity_enabled),
    wanna_go_reminders_enabled = coalesce((input_preferences->>'wanna_go_reminders_enabled')::boolean, wanna_go_reminders_enabled)
  where user_id = viewer_id
  returning * into output_preferences;
  return output_preferences;
end;
$$;

comment on column public.user_places.planned_date is
  'Owner-only calendar day associated with a Wanna Go save. Local device reminders are derived from this date.';
comment on column public.notification_preferences.wanna_go_reminders_enabled is
  'Account preference for device-local reminders three days before an optional Wanna Go planned date.';
comment on function public.save_own_place(jsonb, jsonb, jsonb) is
  'Authenticated own-place save wrapper. Atomically applies the optional owner-only Wanna Go planned date after the hardened app.save_own_place upsert.';
comment on function public.own_wanna_go_plans() is
  'Returns only the authenticated owner''s dated Wanna Go saves for local reminder reconciliation.';

revoke all on function app.normalize_user_place_planned_date() from public, anon, authenticated;
revoke all on function public.save_own_place(jsonb, jsonb, jsonb) from public, anon;
revoke all on function public.own_wanna_go_plans() from public, anon;
revoke all on function public.update_notification_preferences(jsonb) from public, anon;

grant execute on function public.save_own_place(jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.own_wanna_go_plans() to authenticated;
grant execute on function public.update_notification_preferences(jsonb) to authenticated;

do $$
declare
  default_expression text;
begin
  select pg_get_expr(attribute_default.adbin, attribute_default.adrelid)
  into default_expression
  from pg_attribute attribute
  join pg_attrdef attribute_default
    on attribute_default.adrelid = attribute.attrelid
   and attribute_default.adnum = attribute.attnum
  where attribute.attrelid = 'public.notification_preferences'::regclass
    and attribute.attname = 'wanna_go_reminders_enabled'
    and not attribute.attisdropped;

  if default_expression is distinct from 'false' then
    raise exception 'wanna_go_reminders_enabled must default off, found %', default_expression;
  end if;

  if not exists (
    select 1
    from pg_proc
    where oid = 'public.save_own_place(jsonb,jsonb,jsonb)'::regprocedure
      and not prosecdef
      and 'search_path=app, public' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'public.save_own_place security posture changed';
  end if;

  if not exists (
    select 1
    from pg_proc
    where oid = 'public.own_wanna_go_plans()'::regprocedure
      and not prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'public.own_wanna_go_plans security posture is invalid';
  end if;

  if not exists (
    select 1
    from pg_proc
    where oid = 'public.update_notification_preferences(jsonb)'::regprocedure
      and prosecdef
      and 'search_path=public, app' = any(coalesce(proconfig, array[]::text[]))
  ) then
    raise exception 'public.update_notification_preferences security posture changed';
  end if;

  if not has_function_privilege('authenticated', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.save_own_place(jsonb,jsonb,jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.own_wanna_go_plans()', 'execute')
     or has_function_privilege('anon', 'public.own_wanna_go_plans()', 'execute')
     or not has_function_privilege('authenticated', 'public.update_notification_preferences(jsonb)', 'execute')
     or has_function_privilege('anon', 'public.update_notification_preferences(jsonb)', 'execute') then
    raise exception 'REC-118 RPC grants are invalid';
  end if;
end;
$$;

commit;
