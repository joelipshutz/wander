begin;

-- Wait for the app-owned name; abandoned onboarding becomes eligible after ten
-- minutes without spending retry attempts. Do not label generated handles as names.
create or replace function public.claim_signup_slack()
returns table(profile_id text, display_name text, clerk_user_ids jsonb,
  signed_up_at timestamptz, claim_token uuid)
language plpgsql volatile security definer set search_path = public
as $$
begin
  update public.signup_slack_deliveries q set status='failed',last_error='delivery_needs_review'
    where q.status in ('pending','sending') and q.attempt_count >= 12
      and (q.claim_expires_at is null or q.claim_expires_at < now());
  -- A delayed create event must not resurrect a notification for a deleted user.
  update public.signup_slack_deliveries q set status='skipped',last_error='account_deleted'
    where q.status='pending' and exists(select 1 from public.clerk_profile_mirror_state s
      where s.clerk_user_id=q.profile_id and s.last_event_type='user.deleted');
  return query
  with candidates as (
    select q.profile_id from public.signup_slack_deliveries q
      join public.profiles p on p.id=q.profile_id and p.deleted_at is null
    where (p.onboarding_completed_at is not null or q.signed_up_at <= now() - interval '10 minutes')
      and q.attempt_count < 12
      and ((q.status='pending' and q.next_attempt_at <= now())
        or (q.status='sending' and q.claim_expires_at < now()))
    order by q.next_attempt_at for update of q skip locked limit 5
  ), claimed as (
    update public.signup_slack_deliveries q set status='sending',claim_token=gen_random_uuid(),
      claim_expires_at=now()+interval '5 minutes',attempt_count=q.attempt_count+1
    from candidates c where q.profile_id=c.profile_id returning q.*
  )
  select c.profile_id,
    case when p.onboarding_completed_at is not null or p.display_name is distinct from p.handle
      then p.display_name else null end,
    coalesce((select jsonb_agg(m.clerk_user_id) from
      (select mapping.clerk_user_id from public.clerk_identity_mappings mapping
       where mapping.profile_id=c.profile_id order by mapping.updated_at desc limit 4) m),'[]'::jsonb),
    c.signed_up_at,c.claim_token
  from claimed c join public.profiles p on p.id=c.profile_id;
end;
$$;


commit;
