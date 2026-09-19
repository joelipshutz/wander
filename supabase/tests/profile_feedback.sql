begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions, pg_temp;
select plan(1);
-- Runs only inside the smoke tool's rollback transaction. Fictional accounts.
reset role;
insert into public.profiles(id, handle, display_name) values
  ('user_codex_feedback_owner','codexfeedbackowner','Feedback Owner'),
  ('user_codex_feedback_other','codexfeedbackother','Feedback Other');
do $security$
declare signature text;
begin
  if not (select relrowsecurity from pg_class where oid = 'public.app_feedback'::regclass)
    or has_table_privilege('authenticated','public.app_feedback','select,insert,update,delete')
    or has_table_privilege('anon','public.app_feedback','select,insert,update,delete')
    or (select public from storage.buckets where id = 'feedback-attachments') then
    raise exception 'feedback privacy contract failed'; end if;
  foreach signature in array array[
    'public.begin_own_feedback(uuid,text,jsonb,text,text)', 'public.submit_own_feedback(uuid)',
    'public.can_write_own_feedback_object(text)'
  ] loop
    if has_function_privilege('anon',signature,'execute')
      or not has_function_privilege('authenticated',signature,'execute')
      or not exists(select 1 from pg_proc where oid = signature::regprocedure and prosecdef
        and 'search_path=public, app' = any(proconfig) and provolatile = 'v') then
      raise exception 'feedback owner RPC posture changed: %', signature; end if;
  end loop;
  foreach signature in array array['public.claim_feedback_emails()', 'public.settle_feedback_email(uuid,uuid,text,text)',
    'app.account_storage_objects(text,timestamp with time zone)'] loop
    if has_function_privilege('authenticated',signature,'execute') or has_function_privilege('anon',signature,'execute')
      or not has_function_privilege('service_role',signature,'execute') then
      raise exception 'feedback service RPC posture changed'; end if;
  end loop;
end
$security$;
set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select set_config('request.jwt.claim.canonical_user_id','',true);
select set_config('request.jwt.claim.sub','user_codex_feedback_owner',true);
do $owner$
declare fid uuid := '54500000-0000-0000-0000-000000000001';
begin
  if (public.begin_own_feedback(fid, 'A feature request', '[]', '1.0','176')->>'submitted')::boolean then
    raise exception 'draft was already submitted'; end if;
  if not (public.submit_own_feedback(fid)->>'submitted')::boolean
    or not (public.submit_own_feedback(fid)->>'submitted')::boolean
    or not (public.begin_own_feedback(fid,'A feature request','[]','1.0','176')->>'submitted')::boolean then
    raise exception 'idempotent submission failed'; end if;
  begin
    perform public.begin_own_feedback(fid,'changed','[]','1.0','176'); raise exception 'test_payload_changed';
  exception when others then if sqlerrm <> 'feedback_payload_changed' then raise; end if; end;
  begin
    perform 1 from public.app_feedback; raise exception 'test_private_table';
  exception when insufficient_privilege then null; end;
  begin
    perform public.claim_feedback_emails(); raise exception 'test_worker_access';
  exception when insufficient_privilege then null; end;
  begin
    perform public.begin_own_feedback(gen_random_uuid(),'','[]','1.0','176'); raise exception 'test_empty';
  exception when others then if sqlerrm <> 'invalid_feedback' then raise; end if; end;
  begin
    perform public.begin_own_feedback(gen_random_uuid(),'x','[{"filename":"../other.jpg","kind":"photo","content_type":"image/jpeg","byte_size":1}]','1.0','176');
    raise exception 'test_path';
  exception when others then if sqlerrm <> 'invalid_attachment' then raise; end if; end;
  perform set_config('request.jwt.claim.sub','user_codex_feedback_other',true);
  begin
    perform public.submit_own_feedback(fid); raise exception 'test_other_owner';
  exception when others then if sqlerrm <> 'feedback_not_found' then raise; end if; end;
  begin
    perform public.begin_own_feedback(fid,'A feature request','[]','1.0','176'); raise exception 'test_other_draft';
  exception when others then if sqlerrm <> 'feedback_not_found' then raise; end if; end;
  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.submit_own_feedback(fid); raise exception 'test_anonymous';
  exception when others then if sqlerrm <> 'not_authenticated' then raise; end if; end;
end
$owner$;
select set_config('request.jwt.claim.sub','user_codex_feedback_owner',true);
select public.begin_own_feedback('54500000-0000-0000-0000-000000000002','',
  '[{"filename":"54500000-0000-0000-0000-000000000010.jpg","kind":"photo","content_type":"image/jpeg","byte_size":3}]','1.0','176');
do $missing$
begin
  begin
    perform public.submit_own_feedback('54500000-0000-0000-0000-000000000002'); raise exception 'test_missing_media';
  exception when others then if sqlerrm <> 'attachment_not_ready' then raise; end if; end;
  if not public.can_write_own_feedback_object('54500000-0000-0000-0000-000000000002/54500000-0000-0000-0000-000000000010.jpg')
    or public.can_write_own_feedback_object('54500000-0000-0000-0000-000000000002/unlisted.jpg') then
    raise exception 'manifest storage boundary failed'; end if;
end
$missing$;
insert into storage.objects(bucket_id,name,metadata) values('feedback-attachments',
  '54500000-0000-0000-0000-000000000002/54500000-0000-0000-0000-000000000010.jpg','{"size":3,"mimetype":"image/jpeg"}');
select public.submit_own_feedback('54500000-0000-0000-0000-000000000002');
do $sealed$
begin
  if public.can_write_own_feedback_object('54500000-0000-0000-0000-000000000002/54500000-0000-0000-0000-000000000010.jpg')
    or exists(select 1 from storage.objects where bucket_id = 'feedback-attachments') then
    raise exception 'submitted files are client-accessible'; end if;
end
$sealed$;
reset role;
do $delivery$
declare job public.app_feedback; claimed integer := 0;
begin
  -- Put fictional rows first; all claims are rolled back with this transaction.
  update public.app_feedback set created_at = '1900-01-01' where user_id = 'user_codex_feedback_owner';
  if (select count(*) from public.app_feedback where user_id = 'user_codex_feedback_owner') <> 2 then
    raise exception 'duplicate feedback created'; end if;
  if not exists(select 1 from public.account_storage_objects('user_codex_feedback_owner', now())
    where bucket_id = 'feedback-attachments') then raise exception 'account purge missed feedback'; end if;
  for job in select * from public.claim_feedback_emails() loop
    if job.user_id <> 'user_codex_feedback_owner' then continue; end if;
    claimed := claimed + 1;
    if public.settle_feedback_email(job.id, gen_random_uuid(), 'bad', null) then raise exception 'stale claim accepted'; end if;
    if not public.settle_feedback_email(job.id, job.claim_token, 'fictional-email', null) then raise exception 'settlement failed'; end if;
    if public.settle_feedback_email(job.id, job.claim_token, 'duplicate', null) then raise exception 'duplicate settlement'; end if;
  end loop;
  if claimed <> 2 then raise exception 'claim count mismatch'; end if;
  if exists(select 1 from public.app_feedback where user_id = 'user_codex_feedback_owner' and email_status <> 'sent') then
    raise exception 'sent state not durable'; end if;
  update public.app_feedback set created_at = now() where user_id = 'user_codex_feedback_owner';
end
$delivery$;
set local role authenticated;
select set_config('request.jwt.claim.sub','user_codex_feedback_owner',true);
do $quota$
begin
  for i in 1..3 loop perform public.begin_own_feedback(gen_random_uuid(),'quota test','[]','1','1'); end loop;
  begin
    perform public.begin_own_feedback(gen_random_uuid(),'sixth','[]','1','1'); raise exception 'test_quota';
  exception when others then if sqlerrm <> 'feedback_rate_limited' then raise; end if; end;
end
$quota$;
reset role;

select pass('feedback authorization, storage, idempotency, quotas, account purge and email settlement');
select * from finish();
rollback;
