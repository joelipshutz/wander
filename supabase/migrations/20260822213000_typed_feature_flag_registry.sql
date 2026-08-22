begin;

-- Keep the hosted control plane aligned with the app's FeatureFlagKey registry.
-- A new remote flag must ship with an app registry entry and Settings metadata;
-- it can no longer be created as a remote-only row.
alter table public.feature_flags
  add column value_type text not null default 'boolean',
  add column integer_value integer;

alter table public.feature_flags
  add constraint feature_flags_value_type_check
    check (value_type in ('boolean', 'integer')),
  add constraint feature_flags_typed_value_check
    check (
      (value_type = 'boolean' and integer_value is null)
      or (value_type = 'integer' and integer_value is not null)
    ),
  add constraint feature_flags_registered_key_check
    check (
      key in (
        'first_visit_nux',
        'debug_settings',
        'place_profile_save_tray_v1',
        'semantic_place_search_v1',
        'place_profile_action_variant'
      )
    ),
  add constraint feature_flags_integer_range_check
    check (
      key <> 'place_profile_action_variant'
      or (
        value_type = 'integer'
        and integer_value between 1 and 5
      )
    );

insert into public.feature_flags(
  key,
  user_id,
  enabled,
  value_type,
  integer_value
)
values (
  'place_profile_action_variant',
  null,
  false,
  'integer',
  5
)
on conflict (key) where user_id is null
do update set
  value_type = excluded.value_type,
  integer_value = excluded.integer_value;

commit;
