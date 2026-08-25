begin;

-- Viewer taxonomy rows are derived response metadata. Builds predating REC-362
-- could treat them as ordinary attributes and write them back on the next sync,
-- duplicating the projection appended by viewer-aware RPCs.
delete from public.place_attributes
where question_key in (
  '__viewer_taxonomy_primary_category',
  '__viewer_taxonomy_subcategory',
  '__viewer_taxonomy_food_type'
);

create or replace function app.ignore_viewer_taxonomy_projection_attribute()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Preserve save compatibility with older clients that may echo derived RPC
  -- metadata back in the ordinary attributes payload.
  return null;
end;
$$;

revoke all on function app.ignore_viewer_taxonomy_projection_attribute()
  from public, anon, authenticated;

drop trigger if exists place_attributes_ignore_viewer_taxonomy_projection_insert
  on public.place_attributes;
create trigger place_attributes_ignore_viewer_taxonomy_projection_insert
before insert on public.place_attributes
for each row
when (
  new.question_key in (
    '__viewer_taxonomy_primary_category',
    '__viewer_taxonomy_subcategory',
    '__viewer_taxonomy_food_type'
  )
)
execute function app.ignore_viewer_taxonomy_projection_attribute();

alter table public.place_attributes
  drop constraint if exists place_attributes_no_viewer_taxonomy_projection_keys;
alter table public.place_attributes
  add constraint place_attributes_no_viewer_taxonomy_projection_keys
  check (
    question_key not in (
      '__viewer_taxonomy_primary_category',
      '__viewer_taxonomy_subcategory',
      '__viewer_taxonomy_food_type'
    )
  );

comment on constraint place_attributes_no_viewer_taxonomy_projection_keys
  on public.place_attributes is
  'Viewer taxonomy projection keys are derived RPC metadata and must never be persisted as save content.';

commit;
