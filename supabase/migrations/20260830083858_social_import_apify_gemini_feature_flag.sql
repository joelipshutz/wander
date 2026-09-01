begin;

-- Keep the hosted key and value-type contracts aligned with the app registry
-- before inserting the new fail-closed global row.
alter table public.feature_flags
  drop constraint feature_flags_registered_key_check,
  drop constraint feature_flags_key_value_contract_check;

alter table public.feature_flags
  add constraint feature_flags_registered_key_check
    check (
      key in (
        'first_visit_nux',
        'debug_settings',
        'place_profile_save_tray_v1',
        'semantic_place_search_v1',
        'social_import_apify_gemini_v1',
        'place_profile_action_variant'
      )
    ),
  add constraint feature_flags_key_value_contract_check
    check (
      key not in (
        'first_visit_nux',
        'debug_settings',
        'place_profile_save_tray_v1',
        'semantic_place_search_v1',
        'social_import_apify_gemini_v1',
        'place_profile_action_variant'
      )
      or (
        key in (
          'first_visit_nux',
          'debug_settings',
          'place_profile_save_tray_v1',
          'semantic_place_search_v1',
          'social_import_apify_gemini_v1'
        )
        and value_type = 'boolean'
        and integer_value is null
      )
      or (
        key = 'place_profile_action_variant'
        and value_type = 'integer'
        and integer_value is not null
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
  'social_import_apify_gemini_v1',
  null,
  false,
  'boolean',
  null
)
on conflict (key) where user_id is null
do update set
  enabled = excluded.enabled,
  value_type = excluded.value_type,
  integer_value = excluded.integer_value;

commit;
