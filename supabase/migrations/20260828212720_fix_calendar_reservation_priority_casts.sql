-- PostgreSQL resolves integer literals before applying named-argument defaults.
-- The governor intentionally accepts a bounded smallint priority, so make the two
-- reservation priorities explicit without widening the internal function API.

do $migration$
declare
  function_definition text;
begin
  select pg_get_functiondef(
    'public.sync_calendar_reservations(jsonb,timestamptz,timestamptz)'::regprocedure
  ) into function_definition;

  if position('input_priority := 70,' in function_definition) = 0
     or position('input_priority := 60,' in function_definition) = 0 then
    raise exception 'unexpected_sync_calendar_reservations_definition';
  end if;

  function_definition := replace(
    function_definition,
    'input_priority := 70,',
    'input_priority := 70::smallint,'
  );
  function_definition := replace(
    function_definition,
    'input_priority := 60,',
    'input_priority := 60::smallint,'
  );

  execute function_definition;
end;
$migration$;

alter function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  security definer;
alter function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  set search_path to public, app;

comment on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz) is
  'Syncs locally detected, resolved calendar reservations without accepting raw calendar content and queues the two-stage prompt waterfall.';

revoke all on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  from public, anon, authenticated;
grant execute on function public.sync_calendar_reservations(jsonb, timestamptz, timestamptz)
  to authenticated;
