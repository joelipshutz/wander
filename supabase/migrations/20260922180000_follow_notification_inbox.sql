begin;

-- In-app receipts are independent of push preferences and APNs delivery.
-- Existing relationships are deliberately not backfilled as new notifications.
create table public.follow_notification_receipts (
  id uuid primary key,
  recipient_id text not null references public.profiles(id) on delete cascade,
  actor_id text not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  is_mutual boolean not null default false,
  check (recipient_id <> actor_id)
);
create index follow_notification_receipts_recipient_idx
  on public.follow_notification_receipts(recipient_id, created_at desc, id);
alter table public.follow_notification_receipts enable row level security;
revoke all on public.follow_notification_receipts from public, anon, authenticated;

-- A separate trigger preserves the existing push queue and delivery policy.
-- The follow UUID gives retries one identity and refollows a new identity.
create function app.record_follow_notification_receipt()
returns trigger language plpgsql security definer
set search_path = public, app
as $$
begin
  if not app.is_blocked(new.followed_user_id, new.follower_user_id) then
    insert into public.follow_notification_receipts(id, recipient_id, actor_id, created_at, is_mutual)
    values (new.id, new.followed_user_id, new.follower_user_id, new.created_at,
      exists (select 1 from public.follows reciprocal
        where reciprocal.follower_user_id = new.followed_user_id
          and reciprocal.followed_user_id = new.follower_user_id))
    on conflict (id) do nothing;
  end if;
  return new;
end;
$$;
revoke all on function app.record_follow_notification_receipt() from public, anon, authenticated;
create trigger follows_record_inbox_receipt after insert on public.follows
  for each row when (new.source <> 'signup_default')
  execute function app.record_follow_notification_receipt();

-- No recipient parameter: callers can enumerate only their own notifications.
-- Recheck actor visibility at read time, including blocks after delivery.
create function public.received_follow_notifications()
returns table (
  id uuid, actor_id text, display_name text, handle text, avatar_url text,
  created_at timestamptz, is_mutual boolean
)
language sql stable security definer
set search_path = public, app
as $$
  select receipt.id, actor.id, actor.display_name, actor.handle, actor.avatar_url,
    receipt.created_at, receipt.is_mutual
  from public.follow_notification_receipts receipt
  join public.profiles actor on actor.id = receipt.actor_id
  join public.profiles recipient on recipient.id = receipt.recipient_id
  where receipt.recipient_id = app.current_user_id()
    and actor.deleted_at is null and recipient.deleted_at is null
    and not actor.is_private_profile
    and not app.is_blocked(receipt.recipient_id, receipt.actor_id)
  order by receipt.created_at desc, receipt.id
  limit 100;
$$;
revoke all on function public.received_follow_notifications() from public, anon;
grant execute on function public.received_follow_notifications() to authenticated;

commit;
