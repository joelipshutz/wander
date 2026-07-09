begin;

create table if not exists public.place_visits (
  id uuid primary key default gen_random_uuid(),
  user_place_id uuid not null references public.user_places(id) on delete cascade,
  visited_at timestamptz not null default now(),
  note text,
  rating_score numeric(2, 1),
  attribute_answers jsonb not null default '[]'::jsonb
    check (jsonb_typeof(attribute_answers) = 'array'),
  tags text[] not null default '{}'::text[],
  backfilled_from_user_place boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check (
    rating_score is null
    or (
      rating_score between 1 and 5
      and rating_score * 2 = trunc(rating_score * 2)
    )
  )
);

create unique index if not exists place_visits_one_backfill_per_user_place_idx
  on public.place_visits(user_place_id)
  where backfilled_from_user_place;

create index if not exists place_visits_user_place_visited_idx
  on public.place_visits(user_place_id, visited_at desc)
  where deleted_at is null;

create index if not exists place_visits_user_place_rating_idx
  on public.place_visits(user_place_id, rating_score)
  where deleted_at is null
    and rating_score is not null;

create index if not exists place_visits_tags_idx
  on public.place_visits using gin(tags)
  where deleted_at is null;

create table if not exists public.visit_photos (
  id uuid primary key default gen_random_uuid(),
  visit_id uuid not null references public.place_visits(id) on delete cascade,
  storage_bucket text not null default 'visit-photos'
    check (storage_bucket = 'visit-photos'),
  storage_path text not null unique
    check (
      length(storage_path) between 1 and 512
      and storage_path !~ '(^/|//|\.\.)'
      and array_length(string_to_array(storage_path, '/'), 1) = 3
    ),
  content_type text not null
    check (content_type in ('image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp')),
  byte_size integer check (byte_size is null or byte_size > 0),
  width integer check (width is null or width > 0),
  height integer check (height is null or height > 0),
  captured_at timestamptz,
  sort_order integer not null default 0 check (sort_order >= 0),
  upload_state text not null default 'pending_upload'
    check (upload_state in ('pending_upload', 'uploaded', 'failed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists visit_photos_visit_sort_idx
  on public.visit_photos(visit_id, sort_order, created_at)
  where deleted_at is null;

create index if not exists visit_photos_uploaded_idx
  on public.visit_photos(visit_id, upload_state)
  where deleted_at is null;

drop trigger if exists place_visits_set_updated_at on public.place_visits;
create trigger place_visits_set_updated_at
  before update on public.place_visits
  for each row execute function app.set_updated_at();

drop trigger if exists visit_photos_set_updated_at on public.visit_photos;
create trigger visit_photos_set_updated_at
  before update on public.visit_photos
  for each row execute function app.set_updated_at();

create or replace function app.visit_tags_from_attribute_answers(input_attribute_answers jsonb)
returns text[]
language sql
immutable
set search_path = public, app
as $$
  select coalesce(array_agg(tag order by tag), array[]::text[])
  from (
    select distinct lower(btrim(tag_elements.tag_json #>> '{}')) as tag
    from jsonb_array_elements(
      case
        when jsonb_typeof(coalesce(input_attribute_answers, '[]'::jsonb)) = 'array'
          then coalesce(input_attribute_answers, '[]'::jsonb)
        else '[]'::jsonb
      end
    ) as answer(answer_json)
    cross join lateral jsonb_array_elements(
      case
        when answer.answer_json->>'value_type' = 'multi_tag'
          and jsonb_typeof(answer.answer_json->'value') = 'array'
          then answer.answer_json->'value'
        else '[]'::jsonb
      end
    ) as tag_elements(tag_json)
    where jsonb_typeof(tag_elements.tag_json) = 'string'
      and btrim(tag_elements.tag_json #>> '{}') <> ''
  ) normalized_tags
$$;

create or replace function app.set_place_visit_derived_tags()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if jsonb_typeof(new.attribute_answers) <> 'array' then
    raise exception 'invalid_visit_attribute_answers_payload';
  end if;

  new.tags := app.visit_tags_from_attribute_answers(new.attribute_answers);
  return new;
end;
$$;

drop trigger if exists place_visits_set_derived_tags on public.place_visits;
create trigger place_visits_set_derived_tags
  before insert or update on public.place_visits
  for each row execute function app.set_place_visit_derived_tags();

create or replace function app.user_place_attribute_answers(input_user_place_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, app
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'question_key', pa.question_key,
        'value_type', pa.value_type,
        'value', pa.value
      )
      order by pa.question_key
    ),
    '[]'::jsonb
  )
  from public.place_attributes pa
  where pa.user_place_id = input_user_place_id
$$;

create or replace function app.can_read_place_visit(input_visit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select exists (
    select 1
    from public.place_visits pv
    join public.user_places up on up.id = pv.user_place_id
    where pv.id = input_visit_id
      and pv.deleted_at is null
      and up.deleted_at is null
      and app.can_read_user_place(app.current_user_id(), up.user_id, up.visibility)
  )
$$;

create or replace function app.owns_place_visit(input_visit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, app
as $$
  select exists (
    select 1
    from public.place_visits pv
    join public.user_places up on up.id = pv.user_place_id
    where pv.id = input_visit_id
      and pv.deleted_at is null
      and up.deleted_at is null
      and up.user_id = app.current_user_id()
  )
$$;

create or replace function app.place_visit_rating_summary(input_place_id uuid)
returns table (
  recommended_score double precision,
  recommended_count integer
)
language sql
stable
security invoker
set search_path = public, app
as $$
  select
    round(avg(pv.rating_score)::numeric, 1)::double precision as recommended_score,
    count(pv.rating_score)::integer as recommended_count
  from public.place_visits pv
  join public.user_places up on up.id = pv.user_place_id
  where up.place_id = input_place_id
    and up.deleted_at is null
    and pv.deleted_at is null
    and pv.rating_score is not null
    and app.can_read_user_place(app.current_user_id(), up.user_id, up.visibility)
$$;

-- Security definer is intentional: this trigger writes a derived visit row from
-- the just-written user_places row. Callers cannot choose another user id here.
create or replace function app.sync_backfilled_place_visit_for_user_place()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if tg_op = 'DELETE' then
    update public.place_visits
    set deleted_at = coalesce(deleted_at, now()),
        updated_at = now()
    where user_place_id = old.id
      and backfilled_from_user_place;

    return old;
  end if;

  if new.deleted_at is not null or new.status <> 'been' then
    update public.place_visits
    set deleted_at = coalesce(deleted_at, now()),
        updated_at = now()
    where user_place_id = new.id
      and backfilled_from_user_place
      and deleted_at is null;

    return new;
  end if;

  insert into public.place_visits (
    user_place_id,
    visited_at,
    note,
    rating_score,
    attribute_answers,
    backfilled_from_user_place,
    created_at,
    updated_at,
    deleted_at
  )
  values (
    new.id,
    coalesce(new.visited_at, new.saved_at, new.created_at, now()),
    new.note,
    new.rating_score,
    app.user_place_attribute_answers(new.id),
    true,
    coalesce(new.created_at, now()),
    coalesce(new.updated_at, now()),
    null
  )
  on conflict (user_place_id) where backfilled_from_user_place
  do update set
    visited_at = excluded.visited_at,
    note = excluded.note,
    rating_score = excluded.rating_score,
    attribute_answers = excluded.attribute_answers,
    deleted_at = null,
    updated_at = now();

  return new;
end;
$$;

create or replace function app.sync_backfilled_place_visit_attributes_for_place_attribute()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  affected_user_place_id uuid;
begin
  if tg_op = 'DELETE' then
    affected_user_place_id := old.user_place_id;
  else
    affected_user_place_id := new.user_place_id;
  end if;

  update public.place_visits
  set attribute_answers = app.user_place_attribute_answers(affected_user_place_id),
      updated_at = now()
  where user_place_id = affected_user_place_id
    and backfilled_from_user_place;

  if tg_op = 'DELETE' then
    return old;
  end if;

  return new;
end;
$$;

create or replace function app.sync_user_place_after_place_visit_delete()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  affected_user_place_id uuid;
begin
  affected_user_place_id := old.user_place_id;

  if not exists (
    select 1
    from public.place_visits pv
    where pv.user_place_id = affected_user_place_id
      and pv.deleted_at is null
  ) then
    -- Current user_places is one row per user/place, so no separate retained
    -- wanna intent can exist yet. Last-visit deletion therefore unsaves.
    update public.user_places
    set deleted_at = coalesce(deleted_at, now()),
        rating_score = null,
        visited_at = null,
        updated_at = now()
    where id = affected_user_place_id
      and status = 'been'
      and deleted_at is null;
  end if;

  return old;
end;
$$;

drop trigger if exists user_places_sync_backfilled_visit on public.user_places;
create trigger user_places_sync_backfilled_visit
  after insert or update of status, note, rating_score, visited_at, saved_at, deleted_at
  on public.user_places
  for each row execute function app.sync_backfilled_place_visit_for_user_place();

drop trigger if exists place_attributes_sync_backfilled_visit_attributes on public.place_attributes;
create trigger place_attributes_sync_backfilled_visit_attributes
  after insert or update or delete on public.place_attributes
  for each row execute function app.sync_backfilled_place_visit_attributes_for_place_attribute();

drop trigger if exists place_visits_sync_user_place_after_delete on public.place_visits;
create trigger place_visits_sync_user_place_after_delete
  after delete on public.place_visits
  for each row execute function app.sync_user_place_after_place_visit_delete();

insert into public.place_visits (
  user_place_id,
  visited_at,
  note,
  rating_score,
  attribute_answers,
  backfilled_from_user_place,
  created_at,
  updated_at,
  deleted_at
)
select
  up.id,
  coalesce(up.visited_at, up.saved_at, up.created_at, now()),
  up.note,
  up.rating_score,
  app.user_place_attribute_answers(up.id),
  true,
  coalesce(up.created_at, now()),
  coalesce(up.updated_at, now()),
  null
from public.user_places up
where up.status = 'been'
  and up.deleted_at is null
on conflict (user_place_id) where backfilled_from_user_place
do update set
  visited_at = excluded.visited_at,
  note = excluded.note,
  rating_score = excluded.rating_score,
  attribute_answers = excluded.attribute_answers,
  deleted_at = null,
  updated_at = now();

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'visit-photos',
  'visit-photos',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

alter table public.place_visits enable row level security;
alter table public.visit_photos enable row level security;

drop policy if exists "place visits readable through user place" on public.place_visits;
create policy "place visits readable through user place"
  on public.place_visits for select
  using (
    deleted_at is null
    and exists (
      select 1
      from public.user_places up
      where up.id = place_visits.user_place_id
        and up.deleted_at is null
        and app.can_read_user_place(app.current_user_id(), up.user_id, up.visibility)
    )
  );

drop policy if exists "place visits owner insert" on public.place_visits;
create policy "place visits owner insert"
  on public.place_visits for insert
  with check (
    not backfilled_from_user_place
    and exists (
      select 1
      from public.user_places up
      where up.id = place_visits.user_place_id
        and up.user_id = app.current_user_id()
        and up.status = 'been'
        and up.deleted_at is null
    )
  );

drop policy if exists "place visits owner update" on public.place_visits;
create policy "place visits owner update"
  on public.place_visits for update
  using (
    exists (
      select 1
      from public.user_places up
      where up.id = place_visits.user_place_id
        and up.user_id = app.current_user_id()
        and up.deleted_at is null
    )
  )
  with check (
    not backfilled_from_user_place
    and exists (
      select 1
      from public.user_places up
      where up.id = place_visits.user_place_id
        and up.user_id = app.current_user_id()
        and up.status = 'been'
        and up.deleted_at is null
    )
  );

drop policy if exists "place visits owner delete" on public.place_visits;
create policy "place visits owner delete"
  on public.place_visits for delete
  using (
    exists (
      select 1
      from public.user_places up
      where up.id = place_visits.user_place_id
        and up.user_id = app.current_user_id()
    )
  );

drop policy if exists "visit photos readable through visit" on public.visit_photos;
create policy "visit photos readable through visit"
  on public.visit_photos for select
  using (
    deleted_at is null
    and app.can_read_place_visit(visit_id)
  );

drop policy if exists "visit photos owner insert" on public.visit_photos;
create policy "visit photos owner insert"
  on public.visit_photos for insert
  with check (
    storage_bucket = 'visit-photos'
    and split_part(storage_path, '/', 1) = app.current_user_id()
    and split_part(storage_path, '/', 2) = visit_id::text
    and split_part(split_part(storage_path, '/', 3), '.', 1) = id::text
    and app.owns_place_visit(visit_id)
  );

drop policy if exists "visit photos owner update" on public.visit_photos;
create policy "visit photos owner update"
  on public.visit_photos for update
  using (app.owns_place_visit(visit_id))
  with check (
    storage_bucket = 'visit-photos'
    and split_part(storage_path, '/', 1) = app.current_user_id()
    and split_part(storage_path, '/', 2) = visit_id::text
    and split_part(split_part(storage_path, '/', 3), '.', 1) = id::text
    and app.owns_place_visit(visit_id)
  );

drop policy if exists "visit photos owner delete" on public.visit_photos;
create policy "visit photos owner delete"
  on public.visit_photos for delete
  using (app.owns_place_visit(visit_id));

drop policy if exists "visit photo objects readable through visit" on storage.objects;
drop policy if exists "visit photo objects owner insert" on storage.objects;
drop policy if exists "visit photo objects owner update" on storage.objects;
drop policy if exists "visit photo objects owner delete" on storage.objects;

create policy "visit photo objects readable through visit"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'visit-photos'
    and exists (
      select 1
      from public.visit_photos vp
      where vp.storage_bucket = storage.objects.bucket_id
        and vp.storage_path = storage.objects.name
        and vp.deleted_at is null
        and app.can_read_place_visit(vp.visit_id)
    )
  );

create policy "visit photo objects owner insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'visit-photos'
    and (storage.foldername(name))[1] = app.current_user_id()
    and exists (
      select 1
      from public.visit_photos vp
      where vp.storage_bucket = storage.objects.bucket_id
        and vp.storage_path = storage.objects.name
        and vp.deleted_at is null
        and app.owns_place_visit(vp.visit_id)
    )
  );

create policy "visit photo objects owner update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'visit-photos'
    and exists (
      select 1
      from public.visit_photos vp
      where vp.storage_bucket = storage.objects.bucket_id
        and vp.storage_path = storage.objects.name
        and vp.deleted_at is null
        and app.owns_place_visit(vp.visit_id)
    )
  )
  with check (
    bucket_id = 'visit-photos'
    and (storage.foldername(name))[1] = app.current_user_id()
    and exists (
      select 1
      from public.visit_photos vp
      where vp.storage_bucket = storage.objects.bucket_id
        and vp.storage_path = storage.objects.name
        and vp.deleted_at is null
        and app.owns_place_visit(vp.visit_id)
    )
  );

create policy "visit photo objects owner delete"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'visit-photos'
    and exists (
      select 1
      from public.visit_photos vp
      where vp.storage_bucket = storage.objects.bucket_id
        and vp.storage_path = storage.objects.name
        and vp.deleted_at is null
        and app.owns_place_visit(vp.visit_id)
    )
  );

revoke all on function app.can_read_place_visit(uuid) from public, anon;
revoke all on function app.owns_place_visit(uuid) from public, anon;
revoke all on function app.place_visit_rating_summary(uuid) from public, anon;
revoke all on function app.visit_tags_from_attribute_answers(jsonb) from public, anon, authenticated;
revoke all on function app.set_place_visit_derived_tags() from public, anon, authenticated;
revoke all on function app.user_place_attribute_answers(uuid) from public, anon, authenticated;
revoke all on function app.sync_backfilled_place_visit_for_user_place() from public, anon, authenticated;
revoke all on function app.sync_backfilled_place_visit_attributes_for_place_attribute() from public, anon, authenticated;
revoke all on function app.sync_user_place_after_place_visit_delete() from public, anon, authenticated;

grant execute on function app.can_read_place_visit(uuid) to authenticated;
grant execute on function app.owns_place_visit(uuid) to authenticated;
grant execute on function app.place_visit_rating_summary(uuid) to authenticated;

grant select, insert, update, delete on public.place_visits to authenticated;
grant select, insert, update, delete on public.visit_photos to authenticated;

commit;
