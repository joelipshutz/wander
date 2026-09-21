-- REC-566: read-only aggregate audit, September 21, 2026.
-- Run only with the isolated Astir account; never the generic CLI login.
-- No identities, note text, credentials or row-level user data are selected.
-- Snapshot observed: 25 total groups; 19 uncancelled groups.
select count(*) as total_groups,
       count(*) filter (where cancelled_at is null) as active_groups
from public.shared_visit_groups;

-- Observed: accepted 16, pending 2, largest occupied 3, above ten 0,
-- linked events 21, comments 5, likes 6. Counts can include historical/test data.
with group_sizes as (
  select group_id, count(*) as occupied
  from public.shared_visit_participants
  where status in ('owner', 'accepted', 'pending')
  group by group_id
), linked_events as (
  select e.id
  from public.feed_events e
  where e.visit_id in (
    select visit_id from public.shared_visit_participants where visit_id is not null
    union
    select source_visit_id from public.shared_visit_groups
  )
)
select
  (select count(*) from public.shared_visit_participants where status = 'accepted') as accepted_participants,
  (select count(*) from public.shared_visit_participants where status = 'pending') as pending_invitations,
  (select coalesce(max(occupied), 0) from group_sizes) as largest_group_including_pending,
  (select count(*) from group_sizes where occupied > 10) as groups_above_ten,
  (select count(*) from linked_events) as linked_activity_events,
  (select count(*) from public.activity_comments where activity_id in (select id from linked_events)) as linked_comments,
  (select count(*) from public.activity_likes where activity_id in (select id from linked_events)) as linked_likes;
