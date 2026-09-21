begin;

-- Add a dormant, account-targetable campaign control to the existing registry.
-- Existing feature-flag RLS and grants continue to restrict writes to operators.
alter table public.feature_flags
  drop constraint feature_flags_registered_key_check,
  drop constraint feature_flags_key_value_contract_check;

alter table public.feature_flags
  add constraint feature_flags_registered_key_check check (key in (
    'first_visit_nux', 'debug_settings', 'place_profile_save_tray_v1',
    'semantic_place_search_v1', 'social_import_apify_gemini_v1',
    'place_profile_action_variant', 'profile_feedback_v1',
    'notification_reprompt_campaign'
  )),
  add constraint feature_flags_key_value_contract_check check (
    (key in ('first_visit_nux', 'debug_settings', 'place_profile_save_tray_v1',
             'semantic_place_search_v1', 'social_import_apify_gemini_v1', 'profile_feedback_v1')
      and value_type = 'boolean' and integer_value is null)
    or (key = 'place_profile_action_variant' and value_type = 'integer'
      and integer_value is not null and integer_value between 1 and 5)
    or (key = 'notification_reprompt_campaign' and value_type = 'integer'
      and integer_value is not null and integer_value between 0 and 1000000)
  );

insert into public.feature_flags(key, user_id, enabled, value_type, integer_value)
values ('notification_reprompt_campaign', null, false, 'integer', 0)
on conflict (key) where user_id is null do nothing;

commit;
