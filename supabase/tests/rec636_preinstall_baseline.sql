begin;

-- REC-636 read-only inventory before either new migration, and after a
-- rolled-back preview. Confirm the target project outside this SQL file.
-- Zero counts establish a clean baseline; this is not an installation check.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

with reserved_profiles(id) as (
  values ('user_codex_private_message_sender'),('user_codex_private_message_recipient'),('user_codex_private_message_stranger'),
    ('user_codex_live_viewer'),('user_codex_live_friend'),('user_codex_live_followee'),('user_codex_live_stranger'),
    ('user_codex_live_refine_viewer'),('user_codex_live_refine_actor'),('user_codex_live_refine_other'),('user_codex_live_refine_stranger'),
    ('user_codex_pm_quota_sender'),('user_codex_pm_quota_other')
  union all select 'user_codex_pm_quota_peer_' || n from generate_series(1,51) n
)
select jsonb_build_object(
  'contract_tables',(select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('private_conversations','private_messages')),
  'contract_functions',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='app' and p.proname in (
      'private_message_participant_enabled','private_message_pair_allowed','private_message_context_allowed',
      'private_message_json','private_conversation_json','live_feed_polygon','live_activity_feed'))
    or (n.nspname='public' and p.proname in (
      'private_message_conversation','private_message_start','private_message_inbox','private_message_history',
      'private_message_send','private_message_mark_read','live_activity_feed'))),
  'live_flag_rows',(select count(*) from public.feature_flags where key='unified_live_v1'),
  'reserved_profile_count',(select count(*) from reserved_profiles),
  'persisted_reserved_profiles',(select count(*) from public.profiles where id in(select id from reserved_profiles))
) as rec636_preinstall_baseline;

rollback;
