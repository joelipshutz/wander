begin;

-- REC-545. The roster and email outbox are service-only. Owner RPCs deliberately
-- use narrow definers so clients cannot change delivery state or another owner.
create table public.app_feedback (
  id uuid primary key,
  user_id text not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) <= 5000),
  attachments jsonb not null default '[]' check (jsonb_typeof(attachments) = 'array' and jsonb_array_length(attachments) <= 4),
  app_version text not null check (length(app_version) <= 64),
  build_number text not null check (length(build_number) <= 64),
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  email_status text not null default 'draft' check (email_status in ('draft','pending','sending','sent','failed')),
  attempt_count integer not null default 0,
  first_attempt_at timestamptz,
  next_attempt_at timestamptz not null default now(),
  claim_token uuid,
  claim_expires_at timestamptz,
  email_id text,
  email_error text,
  email_sent_at timestamptz
);
alter table public.app_feedback enable row level security;
revoke all on public.app_feedback from public, anon, authenticated;
grant select, insert, update, delete on public.app_feedback to service_role;
create index app_feedback_owner_created on public.app_feedback(user_id, created_at);
create index app_feedback_email_queue on public.app_feedback(next_attempt_at) where email_status in ('pending','sending');

insert into storage.buckets(id, name, public, file_size_limit, allowed_mime_types)
values ('feedback-attachments', 'feedback-attachments', false, 2097152, array['image/jpeg','audio/mp4']);

create function public.begin_own_feedback(p_id uuid, p_body text, p_attachments jsonb, p_app_version text, p_build_number text)
returns jsonb language plpgsql volatile security definer set search_path = public, app
as $$
declare viewer_id text := app.current_user_id(); prior public.app_feedback; item jsonb;
begin
  if viewer_id is null then raise exception 'not_authenticated'; end if;
  -- Serialize admission per account: concurrent requests cannot bypass the quota.
  perform 1 from public.profiles where id = viewer_id and deleted_at is null for update;
  if not found then raise exception 'profile_not_found'; end if;
  select * into prior from public.app_feedback where id = p_id for update;
  if found then
    if prior.user_id <> viewer_id then raise exception 'feedback_not_found'; end if;
    if prior.body is distinct from p_body or prior.attachments is distinct from p_attachments
      or prior.app_version is distinct from p_app_version or prior.build_number is distinct from p_build_number then
      raise exception 'feedback_payload_changed';
    end if;
    return jsonb_build_object('submitted', prior.submitted_at is not null);
  end if;
  if p_id is null or p_body is null or char_length(p_body) > 5000
    or p_attachments is null or jsonb_typeof(p_attachments) <> 'array'
    or p_app_version is null or p_build_number is null
    or length(p_app_version) > 64 or length(p_build_number) > 64 then raise exception 'invalid_feedback'; end if;
  if (btrim(p_body) = '' and jsonb_array_length(p_attachments) = 0)
    or jsonb_array_length(p_attachments) > 4 then raise exception 'invalid_feedback'; end if;
  if (select count(*) from jsonb_array_elements(p_attachments) a where a->>'kind' = 'photo') > 3
    or (select count(*) from jsonb_array_elements(p_attachments) a where a->>'kind' = 'voice') > 1
    or (select count(distinct a->>'filename') from jsonb_array_elements(p_attachments) a) <> jsonb_array_length(p_attachments)
    then raise exception 'invalid_attachments'; end if;
  for item in select * from jsonb_array_elements(p_attachments) loop
    if not coalesce(
      jsonb_typeof(item) = 'object' and (item->>'byte_size')::integer between 1 and 2097152
      and (
        (item->>'kind' = 'photo' and item->>'content_type' = 'image/jpeg'
          and item->>'filename' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$')
        or (item->>'kind' = 'voice' and item->>'content_type' = 'audio/mp4'
          and (item->>'duration_seconds')::integer between 1 and 120
          and item->>'filename' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.m4a$')
      ), false) then raise exception 'invalid_attachment'; end if;
  end loop;
  if (select count(*) from public.app_feedback where user_id = viewer_id and created_at > now() - interval '1 hour') >= 5
    or (select count(*) from public.app_feedback where user_id = viewer_id and created_at > now() - interval '1 day') >= 20
    then raise exception 'feedback_rate_limited'; end if;
  insert into public.app_feedback(id, user_id, body, attachments, app_version, build_number)
  values(p_id, viewer_id, p_body, p_attachments, p_app_version, p_build_number);
  return jsonb_build_object('submitted', false);
end;
$$;

-- Lock the parent during each storage transaction so finalization waits for
-- in-flight writes. After finalization, clients cannot replace the email media.
create function public.can_write_own_feedback_object(p_name text)
returns boolean language plpgsql volatile security definer set search_path = public, app
as $$
declare feedback public.app_feedback;
begin
  select * into feedback from public.app_feedback f
    where f.id::text = split_part(p_name, '/', 1) and f.user_id = app.current_user_id()
    and f.submitted_at is null
    and exists(select 1 from public.profiles p where p.id = f.user_id and p.deleted_at is null)
    for share;
  return found and exists(select 1 from jsonb_array_elements(feedback.attachments) a
    where p_name = feedback.id::text || '/' || (a->>'filename'));
end;
$$;
create policy feedback_object_insert on storage.objects for insert to authenticated
  with check(bucket_id = 'feedback-attachments' and public.can_write_own_feedback_object(name));
-- Storage upsert requires SELECT and UPDATE. Reads exist only for the caller's
-- unsubmitted draft; submitted files are service-only, with no public URLs.
create policy feedback_object_draft_read on storage.objects for select to authenticated
  using(bucket_id = 'feedback-attachments' and public.can_write_own_feedback_object(name));
create policy feedback_object_update on storage.objects for update to authenticated
  using(bucket_id = 'feedback-attachments' and public.can_write_own_feedback_object(name))
  with check(bucket_id = 'feedback-attachments' and public.can_write_own_feedback_object(name));

create function public.submit_own_feedback(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public, app
as $$
declare feedback public.app_feedback; item jsonb;
begin
  if app.current_user_id() is null then raise exception 'not_authenticated'; end if;
  select f.* into feedback from public.app_feedback f
    join public.profiles p on p.id = f.user_id and p.deleted_at is null
    where f.id = p_id and f.user_id = app.current_user_id() for update of f;
  if not found then raise exception 'feedback_not_found'; end if;
  if feedback.submitted_at is not null then return jsonb_build_object('submitted', true); end if;
  for item in select * from jsonb_array_elements(feedback.attachments) loop
    if not exists(select 1 from storage.objects where bucket_id = 'feedback-attachments'
      and name = p_id::text || '/' || (item->>'filename')
      and (metadata->>'size')::bigint = (item->>'byte_size')::bigint
      and metadata->>'mimetype' = item->>'content_type') then raise exception 'attachment_not_ready'; end if;
  end loop;
  update public.app_feedback set submitted_at = now(), email_status = 'pending' where id = p_id;
  return jsonb_build_object('submitted', true);
end;
$$;

create function public.claim_feedback_emails()
returns setof public.app_feedback language plpgsql volatile security definer set search_path = public
as $$
begin
  -- Resend deduplicates for 24h. Never blindly resend an ambiguous delivery
  -- after that window: retain it for operator reconciliation instead.
  update public.app_feedback set email_status = 'failed', email_error = 'delivery_needs_review'
    where email_status in ('pending','sending')
      and (attempt_count >= 12 or first_attempt_at < now() - interval '23 hours')
      and (claim_expires_at is null or claim_expires_at < now());
  return query
  with candidates as (
    select id from public.app_feedback where
      ((email_status = 'pending' and next_attempt_at <= now())
        or (email_status = 'sending' and claim_expires_at < now()))
      and attempt_count < 12
      and exists(select 1 from public.profiles p where p.id = user_id and p.deleted_at is null)
    -- Two reports keep bounded sequential attachment/email requests within the
    -- Edge worker lifetime and well inside the five-minute claim lease.
    order by created_at for update skip locked limit 2
  ) update public.app_feedback f set email_status = 'sending', claim_token = gen_random_uuid(),
      claim_expires_at = now() + interval '5 minutes', attempt_count = attempt_count + 1,
      first_attempt_at = coalesce(first_attempt_at, now())
    from candidates c where f.id = c.id returning f.*;
end;
$$;

create function public.settle_feedback_email(p_id uuid, p_claim uuid, p_email_id text, p_error text)
returns boolean language plpgsql volatile security definer set search_path = public
as $$
begin
  update public.app_feedback set
    email_status = case when p_email_id is not null then 'sent' when attempt_count >= 12 then 'failed' else 'pending' end,
    email_id = left(p_email_id, 128), email_error = left(p_error, 64),
    email_sent_at = case when p_email_id is not null then now() else null end,
    next_attempt_at = now() + least(3600, 30 * power(2, attempt_count)::integer) * interval '1 second',
    claim_token = null, claim_expires_at = null
  where id = p_id and claim_token = p_claim and email_status = 'sending' and claim_expires_at > now();
  return found;
end;
$$;

revoke all on function public.begin_own_feedback(uuid,text,jsonb,text,text) from public, anon, authenticated;
revoke all on function public.submit_own_feedback(uuid) from public, anon, authenticated;
revoke all on function public.can_write_own_feedback_object(text) from public, anon, authenticated;
revoke all on function public.claim_feedback_emails() from public, anon, authenticated;
revoke all on function public.settle_feedback_email(uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.begin_own_feedback(uuid,text,jsonb,text,text) to authenticated;
grant execute on function public.submit_own_feedback(uuid) to authenticated;
grant execute on function public.can_write_own_feedback_object(text) to authenticated;
grant execute on function public.claim_feedback_emails() to service_role;
grant execute on function public.settle_feedback_email(uuid,uuid,text,text) to service_role;

comment on table public.app_feedback is 'Private Astir feedback and durable email outbox. Text, optional JPEG photos and AAC voice note; delivery to admin@HotchkissTechnologies.com. No public or social visibility.';

-- Preserve REC-89's stale-event protection and existing avatar/visit inventory.
-- Include draft and submitted feedback files before the profile hard-purge.
create or replace function app.account_storage_objects(profile_id text, event_timestamp timestamptz)
returns table(bucket_id text, object_path text)
language sql stable security definer set search_path = public, app
as $$
  select 'profile-avatars'::text, p.avatar_storage_path from public.profiles p
  where p.id = profile_id and p.avatar_storage_path is not null
    and not exists(select 1 from public.clerk_profile_mirror_state s
      where s.clerk_user_id = profile_id and s.last_event_timestamp > event_timestamp)
  union all
  select vp.storage_bucket, vp.storage_path from public.visit_photos vp
    join public.place_visits pv on pv.id = vp.visit_id
    join public.user_places up on up.id = pv.user_place_id
  where up.user_id = profile_id and not exists(select 1 from public.clerk_profile_mirror_state s
    where s.clerk_user_id = profile_id and s.last_event_timestamp > event_timestamp)
  union all
  select o.bucket_id, o.name from storage.objects o
    join public.app_feedback f on f.id::text = split_part(o.name, '/', 1)
  where o.bucket_id = 'feedback-attachments' and f.user_id = profile_id
    and not exists(select 1 from public.clerk_profile_mirror_state s
      where s.clerk_user_id = profile_id and s.last_event_timestamp > event_timestamp);
$$;
revoke all on function app.account_storage_objects(text,timestamptz) from public, anon, authenticated;
grant execute on function app.account_storage_objects(text,timestamptz) to service_role;

-- The dedicated worker is inert until its matching Vault/Edge secret exists.
-- The existing recme_project_url Vault value identifies this project.
select cron.schedule('astir-feedback-email-worker', '* * * * *', $schedule$
  with config as (
    select max(decrypted_secret) filter(where name = 'recme_project_url') as url,
      max(decrypted_secret) filter(where name = 'astir_feedback_worker_secret') as secret
    from vault.decrypted_secrets
  ) select net.http_post(url := trim(trailing '/' from url) || '/functions/v1/feedback-email-worker',
    headers := jsonb_build_object('Content-Type','application/json','x-feedback-worker-secret',secret),
    body := '{}'::jsonb, timeout_milliseconds := 10000)
    from config where url is not null and secret is not null
$schedule$);

commit;
