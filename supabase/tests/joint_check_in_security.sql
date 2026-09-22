begin;
create extension if not exists pgtap;
set local search_path = public, extensions;
select plan(8);
select is((select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname=any(array['save_joint_check_in','edit_joint_check_in','accept_joint_check_in','save_joint_invitation_privately',
 'set_joint_check_in_invitees','leave_joint_check_in','decline_joint_check_in','joint_check_in_contexts','followed_feed_v2',
 'activity_detail_v2','activity_media_v2','activity_engagement_summaries_v2','place_activity_engagement_summaries_v2',
 'set_activity_like_v2','add_activity_comment_v2','activity_comments_v2','list_shared_visit_inbox_v2',
 'get_shared_visit_context_v2','resolve_shared_visit_destination_v2'])),19::bigint,'all nineteen v2 RPCs exist');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname=any(array['save_joint_check_in','edit_joint_check_in','accept_joint_check_in','save_joint_invitation_privately','set_joint_check_in_invitees','leave_joint_check_in','decline_joint_check_in','joint_check_in_contexts','followed_feed_v2','activity_detail_v2','activity_media_v2','activity_engagement_summaries_v2','place_activity_engagement_summaries_v2','set_activity_like_v2','add_activity_comment_v2','activity_comments_v2','list_shared_visit_inbox_v2','get_shared_visit_context_v2','resolve_shared_visit_destination_v2'])
 and (not p.prosecdef or not 'search_path=pg_catalog, public, app'=any(coalesce(p.proconfig,'{}')))),
 'v2 entry points are security definer with pinned search path');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname=any(array['save_joint_check_in','edit_joint_check_in','accept_joint_check_in','save_joint_invitation_privately','set_joint_check_in_invitees','leave_joint_check_in','decline_joint_check_in','joint_check_in_contexts','followed_feed_v2','activity_detail_v2','activity_media_v2','activity_engagement_summaries_v2','place_activity_engagement_summaries_v2','set_activity_like_v2','add_activity_comment_v2','activity_comments_v2','list_shared_visit_inbox_v2','get_shared_visit_context_v2','resolve_shared_visit_destination_v2'])
 and has_function_privilege('anon',p.oid,'EXECUTE')),'anonymous cannot call v2 RPCs');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname=any(array['save_joint_check_in','edit_joint_check_in','accept_joint_check_in','save_joint_invitation_privately','set_joint_check_in_invitees','leave_joint_check_in','decline_joint_check_in','joint_check_in_contexts','followed_feed_v2','activity_detail_v2','activity_media_v2','activity_engagement_summaries_v2','place_activity_engagement_summaries_v2','set_activity_like_v2','add_activity_comment_v2','activity_comments_v2','list_shared_visit_inbox_v2','get_shared_visit_context_v2','resolve_shared_visit_destination_v2'])
 and not has_function_privilege('authenticated',p.oid,'EXECUTE')),'authenticated can call supported v2 RPCs');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='app' and (p.proname like '%joint%' or p.proname in ('resolve_activity_v2','lock_activity_v2','activity_comment_json'))
 and (has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE'))),
 'private joint helpers cannot be called by clients');
select ok((select relrowsecurity from pg_class where oid='public.joint_check_in_operations'::regclass),
 'operation receipts enforce RLS');
select ok(not has_table_privilege('authenticated','public.joint_check_in_operations','SELECT')
 and not has_table_privilege('anon','public.joint_check_in_operations','SELECT'), 'receipts expose no direct client data');
select ok(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='app' and p.proname in ('create_legacy_shared_visit_invites','set_legacy_shared_visit_invitees',
 'accept_legacy_shared_visit','decline_legacy_shared_visit','claim_pending_push_notifications_before_joint','save_own_check_in_before_v2')
 and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE'))),
 'preserved legacy implementations cannot bypass v2 guards');
select * from finish();
rollback;
