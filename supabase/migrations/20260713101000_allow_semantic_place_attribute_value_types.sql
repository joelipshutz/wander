begin;

-- REC-87: Map save forms persist semantic attribute kinds so readers can
-- distinguish personal labels and restaurant cuisine from generic tags.
-- Keep both schema constraints aligned with the iOS PlaceAttributeDraft
-- contract. This is additive and preserves every existing row.

alter table public.question_definitions
  add constraint question_definitions_value_type_check_v2
  check (
    value_type in (
      'emoji_scale',
      'single_choice',
      'multi_tag',
      'price_scale',
      'text',
      'boolean',
      'personal_label',
      'restaurant_cuisine'
    )
  ) not valid;

alter table public.question_definitions
  validate constraint question_definitions_value_type_check_v2;

alter table public.question_definitions
  drop constraint question_definitions_value_type_check;

alter table public.question_definitions
  rename constraint question_definitions_value_type_check_v2
  to question_definitions_value_type_check;

alter table public.place_attributes
  add constraint place_attributes_value_type_check_v2
  check (
    value_type in (
      'emoji_scale',
      'single_choice',
      'multi_tag',
      'price_scale',
      'text',
      'boolean',
      'personal_label',
      'restaurant_cuisine'
    )
  ) not valid;

alter table public.place_attributes
  validate constraint place_attributes_value_type_check_v2;

alter table public.place_attributes
  drop constraint place_attributes_value_type_check;

alter table public.place_attributes
  rename constraint place_attributes_value_type_check_v2
  to place_attributes_value_type_check;

comment on constraint question_definitions_value_type_check on public.question_definitions is
  'Shared iOS/Supabase attribute value types, including semantic personal labels and restaurant cuisine.';

comment on constraint place_attributes_value_type_check on public.place_attributes is
  'Shared iOS/Supabase attribute value types, including semantic personal labels and restaurant cuisine.';

commit;
