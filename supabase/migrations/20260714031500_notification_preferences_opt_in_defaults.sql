begin;

-- Preserve explicit choices on existing rows. Only newly created accounts start
-- fully off; the one-tap Allow action writes every category to true together.
alter table public.notification_preferences
  alter column push_enabled set default false,
  alter column social_graph_enabled set default false,
  alter column shared_lists_enabled set default false,
  alter column shared_visits_enabled set default false,
  alter column recommendations_enabled set default false,
  alter column capture_enabled set default false,
  alter column discovery_digest_enabled set default false,
  alter column followed_activity_enabled set default false;

do $$
declare
  column_name text;
  default_expression text;
begin
  foreach column_name in array array[
    'push_enabled',
    'social_graph_enabled',
    'shared_lists_enabled',
    'shared_visits_enabled',
    'recommendations_enabled',
    'capture_enabled',
    'discovery_digest_enabled',
    'followed_activity_enabled'
  ]
  loop
    select pg_get_expr(attribute_default.adbin, attribute_default.adrelid)
    into default_expression
    from pg_attribute attribute
    join pg_attrdef attribute_default
      on attribute_default.adrelid = attribute.attrelid
     and attribute_default.adnum = attribute.attnum
    where attribute.attrelid = 'public.notification_preferences'::regclass
      and attribute.attname = column_name
      and not attribute.attisdropped;

    if default_expression is distinct from 'false' then
      raise exception 'notification preference % must default off, found %', column_name, default_expression;
    end if;
  end loop;
end;
$$;

comment on table public.notification_preferences is
  'Per-account push consent and category preferences. New rows default fully off; explicit one-tap enrollment enables every category.';

commit;
