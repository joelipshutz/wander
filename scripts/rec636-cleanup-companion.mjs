// REC-636 operator-only verification. No default executor, credentials or sockets.
// SQL and baseline receipts belong in the private run journal, never reports.
import { validateJournalState, validateJournalBaseline, buildCleanupPlan } from './rec636-mutation-journal.mjs';

const verified = new WeakSet();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const ACCOUNT = /^[A-Za-z0-9_-]{1,256}$/u;
const REF = /^[a-z0-9]{20}$/u;
const canonical = (value) => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map((key)=>[key,canonical(value[key])])) : value;
const same = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
const clone = (value) => JSON.parse(JSON.stringify(value));
export class CleanupCompanionError extends Error {
  constructor(code) { super(code); this.name = 'CleanupCompanionError'; this.code = code; }
}
const fail = (code) => { throw new CleanupCompanionError(code); };
function shape(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || ![Object.prototype, null].includes(Object.getPrototypeOf(value))
    || Object.getOwnPropertySymbols(value).length
    || Object.values(Object.getOwnPropertyDescriptors(value)).some((item) => !Object.hasOwn(item, 'value'))
    || keys.some((key) => !Object.hasOwn(value, key))
    || Object.keys(value).some((key) => !keys.includes(key))) fail('invalid_companion_input');
}
function specOf(value) {
  shape(value, ['runID', 'targetRef', 'accounts', 'context']);
  shape(value.accounts, ['A', 'B']); shape(value.context, ['kind', 'id']);
  if (!UUID.test(value.runID) || !REF.test(value.targetRef)
    || Object.values(value.accounts).some((item) => typeof item !== 'string' || !ACCOUNT.test(item))
    || value.accounts.A === value.accounts.B || !UUID.test(value.context.id)
    || !['place', 'activity'].includes(value.context.kind)) fail('invalid_companion_scope');
  return clone(value);
}
const literal = (value) => `'${String(value).replaceAll("'", "''")}'`;
const json = (value) => `${literal(JSON.stringify(value))}::jsonb`;
const uuid = (value) => `${literal(value)}::uuid`;
const ids = (values) => values.length ? `array[${values.map(uuid).join(',')}]::uuid[]` : 'array[]::uuid[]';
const textIDs = (spec) => `array[${literal(spec.accounts.A)},${literal(spec.accounts.B)}]::text[]`;
const flagRow = (alias) => `jsonb_build_object('id',${alias}.id,'xmin',${alias}.xmin::text,'enabled',${alias}.enabled,'valueType',${alias}.value_type,'integerValue',${alias}.integer_value)`;
const followRow = (alias) => `jsonb_build_object('id',${alias}.id,'xmin',${alias}.xmin::text,'source',${alias}.source,'createdAt',${alias}.created_at,'updatedAt',${alias}.updated_at)`;
const blockRow = (alias) => `jsonb_build_object('id',${alias}.id,'xmin',${alias}.xmin::text,'createdAt',${alias}.created_at)`;

function contextQuery(spec) {
  const { kind, id } = spec.context;
  const source = kind === 'place'
    ? `select saved.xmin::text as source_revision,saved.* from public.user_places saved where saved.place_id=${uuid(id)} and saved.user_id=any(${textIDs(spec)}) and saved.deleted_at is null order by saved.id limit 1`
    : `select saved.xmin::text as source_revision,saved.* from public.feed_events event join public.user_places saved on saved.id=event.user_place_id where event.id=${uuid(id)} and app.canonical_activity_id(event.id)=event.id and event.actor_user_id=saved.user_id and event.place_id=saved.place_id and event.list_id is null and event.list_item_id is null and event.event_type='place_want_to_go'`;
  const main = kind === 'place' ? 'public.places' : 'public.feed_events';
  return `(select jsonb_build_object('kind',${literal(kind)},'id',root.id,'xmin',root.xmin::text,
    'deleted',saved.deleted_at is not null,'allowedA',app.private_message_context_allowed(${literal(spec.accounts.A)},${literal(spec.accounts.B)},${literal(kind)},root.id),
    'allowedB',app.private_message_context_allowed(${literal(spec.accounts.B)},${literal(spec.accounts.A)},${literal(kind)},root.id),
    'ownerID',saved.user_id,'placeID',saved.place_id,'visibility',saved.visibility,'userPlaceID',saved.id,'sourceXmin',saved.source_revision)
    from ${main} root cross join lateral (${source}) saved where root.id=${uuid(id)})`;
}
function sideEffectCount(spec) {
  const sourceID = `((${contextQuery(spec)})->>'userPlaceID')::uuid`;
  // These relationships can cause irreversible collateral changes on a source
  // visibility update. Refuse such contexts rather than repairing their data.
  return `((case when exists(select 1 from public.places p join public.user_places saved on saved.place_id=p.id
      where saved.id=${sourceID} and p.source_provider='rec636_validation'
      and p.source_provider_place_id='rec636:'||${literal(spec.runID)}||':'||p.id::text
      and p.canonical_name='REC-636 verification fixture' and saved.source_type='manual' and saved.status='wanna_go'
      and saved.note is null and saved.rating_signal is null) then 0 else 1 end)
    +(select count(*) from public.follows where (follower_user_id=any(${textIDs(spec)}) or followed_user_id=any(${textIDs(spec)}))
      and not(follower_user_id=any(${textIDs(spec)}) and followed_user_id=any(${textIDs(spec)})))
    +(select count(*) from public.blocks where (blocker_user_id=any(${textIDs(spec)}) or blocked_user_id=any(${textIDs(spec)}))
      and not(blocker_user_id=any(${textIDs(spec)}) and blocked_user_id=any(${textIDs(spec)})))
    +(case when (select count(*) from public.user_places p where p.place_id=((${contextQuery(spec)})->>'placeID')::uuid)=1 then 0 else 1 end)
    +(select count(*) from public.notification_events e where e.data->>'user_place_id'=${sourceID}::text or e.data->>'place_id'=(((${contextQuery(spec)})->>'placeID')::uuid)::text)
    +(select count(*) from public.activity_comments c join public.feed_events e on e.id=c.activity_id where e.user_place_id=${sourceID})
    +(select count(*) from public.activity_likes l join public.feed_events e on e.id=l.activity_id where e.user_place_id=${sourceID})
    +(select count(*) from public.place_list_items where user_place_id=${sourceID})
    +(select count(*) from public.place_attributes where user_place_id=${sourceID})
    +(select count(*) from app.private_list_companion_origins where user_place_id=${sourceID})
    +(select count(*) from public.place_visits where user_place_id=${sourceID})
    +(case when exists(select 1 from public.place_taxonomy_snapshots s join public.user_places p
       on p.user_id=s.user_id and p.place_id=s.place_id where p.id=${sourceID}) then 0 else 1 end)
    +(select count(*) from public.user_places p where p.place_id=((${contextQuery(spec)})->>'placeID')::uuid and not (p.user_id=any(${textIDs(spec)}))))`;
}
function sharedVisitCount(spec) {
  return `((select count(*) from public.shared_visit_groups where owner_user_id=any(${textIDs(spec)}))
    +(select count(*) from public.shared_visit_participants where user_id=any(${textIDs(spec)}) or invited_by_user_id=any(${textIDs(spec)})))`;
}
function baselineQuery(spec) {
  const pair = [[spec.accounts.A, spec.accounts.B], [spec.accounts.B, spec.accounts.A]];
  return `select jsonb_build_object('version',1,'runID',${literal(spec.runID)},'targetRef',${literal(spec.targetRef)},
    'accounts',${json(spec.accounts)},'context',${json(spec.context)},'capturedAt',clock_timestamp(),
    'profiles',(select jsonb_agg(jsonb_build_object('id',p.id,'xmin',p.xmin::text,'deleted',p.deleted_at is not null) order by array_position(${textIDs(spec)},p.id)) from public.profiles p where p.id=any(${textIDs(spec)})),
    'globalFlag',(select ${flagRow('f')} from public.feature_flags f where key='unified_live_v1' and user_id is null),
    'accountFlags',jsonb_build_array(${Object.values(spec.accounts).map((id) => `jsonb_build_object('userID',${literal(id)},'row',(select ${flagRow('f')} from public.feature_flags f where key='unified_live_v1' and user_id=${literal(id)}))`).join(',')}),
    'follows',jsonb_build_array(${pair.map(([a, b]) => `jsonb_build_object('followerID',${literal(a)},'followedID',${literal(b)},'row',(select ${followRow('f')} from public.follows f where follower_user_id=${literal(a)} and followed_user_id=${literal(b)}))`).join(',')}),
    'blocks',jsonb_build_array(${pair.map(([a, b]) => `jsonb_build_object('blockerID',${literal(a)},'blockedID',${literal(b)},'row',(select ${blockRow('b')} from public.blocks b where blocker_user_id=${literal(a)} and blocked_user_id=${literal(b)}))`).join(',')}),
    'contextReceipt',${contextQuery(spec)},
    'conversationCount',(select count(*) from public.private_conversations where low_user_id=any(${textIDs(spec)}) or high_user_id=any(${textIDs(spec)})),
    'messageCount',(select count(*) from public.private_messages m join public.private_conversations c on c.id=m.conversation_id where c.low_user_id=any(${textIDs(spec)}) or c.high_user_id=any(${textIDs(spec)})),
    'sharedVisitCount',${sharedVisitCount(spec)},'sourceSideEffectCount',${sideEffectCount(spec)})`;
}
function transaction(body, { rollback = false, readOnly = false } = {}) {
  return `begin isolation level serializable${readOnly ? ' read only' : ''};
set local lock_timeout='5s'; set local statement_timeout='30s'; set local search_path=pg_catalog; set local timezone='UTC';
${body}
${rollback ? 'rollback' : 'commit'};\n`;
}
export function generateBaselineSQL(value) {
  const spec = specOf(value);
  return transaction(`${baselineQuery(spec)} as rec636_result;`, { readOnly: true, rollback: true });
}
export function validateBaselineReceipt(value, scope = value) {
  const spec = specOf({ runID: scope.runID, targetRef: scope.targetRef, accounts: scope.accounts, context: scope.context });
  try { validateJournalBaseline(value, spec); } catch { fail('unclean_or_invalid_baseline'); }
  if (value.accountFlags.some((item) => item.row?.enabled !== true)
    || value.follows.some((item) => item.row === null) || value.blocks.some((item) => item.row !== null)
    || value.sharedVisitCount !== 0 || value.sourceSideEffectCount !== 0
    || !value.contextReceipt.userPlaceID || !value.contextReceipt.sourceXmin || value.contextReceipt.visibility !== 'mutuals') fail('fixture_not_ready');
  return clone(value);
}
function locks(spec) {
  const ordered = Object.values(spec.accounts).sort();
  return `${ordered.map((id) => `perform pg_advisory_xact_lock(hashtextextended('private-message:'||${literal(id)},0));`).join('\n')}
  perform 1 from public.profiles where id=any(${textIDs(spec)}) order by id for update;
  perform 1 from public.feature_flags where key='unified_live_v1' and (user_id is null or user_id=any(${textIDs(spec)})) order by id for update;
  perform 1 from public.follows where follower_user_id=any(${textIDs(spec)}) and followed_user_id=any(${textIDs(spec)}) order by id for update;
  perform 1 from public.blocks where blocker_user_id=any(${textIDs(spec)}) and blocked_user_id=any(${textIDs(spec)}) order by id for update;
  perform 1 from public.private_conversations where low_user_id=any(${textIDs(spec)}) or high_user_id=any(${textIDs(spec)}) order by id for update;
  perform 1 from public.private_messages where conversation_id in (select id from public.private_conversations where low_user_id=any(${textIDs(spec)}) or high_user_id=any(${textIDs(spec)})) order by id for update;`;
}
function currentResourceSQL(spec, transition) {
  const actor = spec.accounts[transition.actor];
  const target = spec.accounts[transition.targetActor];
  if (transition.resource === 'account_flag') return `(select ${flagRow('f')} from public.feature_flags f where key='unified_live_v1' and user_id=${literal(actor)})`;
  if (transition.resource === 'follow') return `(select ${followRow('f')} from public.follows f where follower_user_id=${literal(actor)} and followed_user_id=${literal(target)})`;
  if (transition.resource === 'block') return `(select ${blockRow('b')} from public.blocks b where blocker_user_id=${literal(actor)} and blocked_user_id=${literal(target)})`;
  return contextQuery(spec);
}
function resourceKey(t) { return t.resource === 'context' ? 'context' : `${t.resource}:${t.actor}:${t.targetActor ?? ''}`; }
function baselineResources(state) {
  const map = new Map([['context', state.baseline.contextReceipt]]);
  for (const [index, label] of ['A', 'B'].entries()) {
    map.set(`account_flag:${label}:`, state.baseline.accountFlags[index].row);
    map.set(`follow:${label}:${label === 'A' ? 'B' : 'A'}`, state.baseline.follows[index].row);
    map.set(`block:${label}:${label === 'A' ? 'B' : 'A'}`, state.baseline.blocks[index].row);
  }
  return map;
}
function expectedResources(state) {
  const expected = baselineResources(state);
  for (const intent of state.intents) {
    if (intent.kind !== 'operator_transition') continue;
    if (!intent.ack && !['absent', 'rejected'].includes(intent.state)) continue;
    if (!intent.ack) continue;
    const key = resourceKey(intent.transition);
    if (intent.transition.resource === 'context' && intent.ack.before?.ownerID !== state.accounts[intent.actor]) fail('context_not_owned');
    if (!same(expected.get(key), intent.ack.before)) fail('operator_receipt_chain_mismatch');
    const baseline = baselineResources(state).get(key);
    if (baseline?.id && intent.ack.after?.id && baseline.id !== intent.ack.after.id) fail('operator_row_identity_mismatch');
    if (intent.transition.resource === 'block' && intent.ack.after?.id !== undefined && intent.ack.after.id !== intent.id) fail('operator_row_identity_mismatch');
    expected.set(key, intent.ack.after);
  }
  return expected;
}
function guardSQL(state, { allowOwnedConversations = true } = {}) {
  const expected = expectedResources(state); const spec = specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context});
  let guards = `if (select ${flagRow('f')} from public.feature_flags f where key='unified_live_v1' and user_id is null) is distinct from ${json(state.baseline.globalFlag)} then raise exception 'global_live_drift'; end if;
  if (select jsonb_agg(jsonb_build_object('id',p.id,'xmin',p.xmin::text,'deleted',p.deleted_at is not null) order by array_position(${textIDs(spec)},p.id)) from public.profiles p where p.id=any(${textIDs(spec)})) is distinct from ${json(state.baseline.profiles)} then raise exception 'profile_baseline_drift'; end if;
  if ${sharedVisitCount(spec)} <> 0 or ${sideEffectCount(spec)} <> 0 then raise exception 'fixture_side_effect_risk'; end if;`;
  for (const resource of ['account_flag', 'follow', 'block']) for (const actor of ['A', 'B']) {
    const targetActor = actor === 'A' ? 'B' : 'A';
    const t = { resource, actor, ...(resource === 'account_flag' ? {} : { targetActor }) };
    guards += `\nif ${currentResourceSQL(spec, t)} is distinct from ${json(expected.get(resourceKey(t)))} then raise exception 'operator_baseline_drift'; end if;`;
  }
  guards += `\nif (${contextQuery(spec)} - 'allowedA' - 'allowedB') is distinct from (${json(expected.get('context'))} - 'allowedA' - 'allowedB') then raise exception 'context_baseline_drift'; end if;`;
  const owned = allowOwnedConversations ? buildCleanupPlan(state).conversationIDs : [];
  guards += `\nif exists(select 1 from public.private_conversations c where (c.low_user_id=any(${textIDs(spec)}) or c.high_user_id=any(${textIDs(spec)})) and not(c.id=any(${ids(owned)}))) then raise exception 'foreign_conversation'; end if;`;
  for (const id of owned) guards += `\nif exists(select 1 from public.private_conversations c where c.id=${uuid(id)} and (c.low_user_id<>least(${literal(spec.accounts.A)},${literal(spec.accounts.B)}) or c.high_user_id<>greatest(${literal(spec.accounts.A)},${literal(spec.accounts.B)}))) then raise exception 'foreign_conversation'; end if;`;
  return guards;
}
function stateOf(value) {
  let state; try { state = validateJournalState(value); } catch { fail('invalid_cleanup_journal'); }
  validateBaselineReceipt(state.baseline, state); expectedResources(state); return state;
}
function transitionMutation(state, entry, before) {
  const spec = specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context}); const t = entry.transition; const actor = spec.accounts[t.actor];
  const target = spec.accounts[t.targetActor]; const original = baselineResources(state).get(resourceKey(t));
  if (t.resource === 'account_flag') {
    if (!before || !original) fail('unowned_flag_insert_forbidden');
    return `update public.feature_flags set enabled=${t.action === 'revoke' ? 'false' : original.enabled ? 'true' : 'false'} where id=${uuid(original.id)} and key='unified_live_v1' and user_id=${literal(actor)};`;
  }
  if (t.resource === 'follow') {
    if (!original) fail('unowned_follow_insert_forbidden');
    if (t.action === 'remove') {
      if (!before) fail('follow_already_absent');
      return `delete from public.follows where id=${uuid(original.id)} and follower_user_id=${literal(actor)} and followed_user_id=${literal(target)};`;
    }
    if (before !== null) fail('follow_restore_requires_absence');
    // Both reviewed INSERT notification triggers omit signup_default. The
    // original source is restored before commit, with no trigger bypass.
    return `insert into public.follows(id,follower_user_id,followed_user_id,source,created_at,updated_at)
      values(${uuid(original.id)},${literal(actor)},${literal(target)},'signup_default',${literal(original.createdAt)}::timestamptz,${literal(original.updatedAt)}::timestamptz);
      update public.follows set source=${literal(original.source)} where id=${uuid(original.id)};`;
  }
  if (t.resource === 'block') {
    if (original !== null) fail('preexisting_block');
    if (t.action === 'insert') {
      if (before !== null) fail('block_already_present');
      return `insert into public.blocks(id,blocker_user_id,blocked_user_id) values(${uuid(entry.id)},${literal(actor)},${literal(target)});`;
    }
    if (!before) fail('block_already_absent');
    return `delete from public.blocks where id=${uuid(before.id)} and blocker_user_id=${literal(actor)} and blocked_user_id=${literal(target)};`;
  }
  const context = state.baseline.contextReceipt;
  if (context.visibility === 'self') fail('context_revoke_not_meaningful');
  if (context.ownerID !== actor || !context.userPlaceID || !context.sourceXmin) fail('context_not_owned');
  return `update public.user_places set visibility=${literal(t.action === 'revoke' ? 'self' : context.visibility)} where id=${uuid(context.userPlaceID)} and user_id=${literal(actor)} and place_id=${uuid(context.placeID)} and deleted_at is null;`;
}
export function generateTransitionSQL(value, intentID, { rollback = false } = {}) {
  const state = stateOf(value); const spec = specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context});
  const entry = state.intents.find((item) => item.id === intentID);
  if (!entry || entry.kind !== 'operator_transition' || entry.state !== 'intent') fail('invalid_transition_intent');
  if (state.intents.some((item) => item.id !== intentID && ['intent', 'interrupted'].includes(item.state))) fail('reconciliation_required');
  const before = expectedResources(state).get(resourceKey(entry.transition));
  const mutation = transitionMutation(state, entry, before);
  return transaction(`do $rec636$ declare original jsonb; final_row jsonb; notification_count bigint; begin
  ${locks(spec)} ${guardSQL(state)}
  original := ${currentResourceSQL(spec, entry.transition)};
  select count(*) into notification_count from public.notification_events where recipient_user_id=any(${textIDs(spec)}) or actor_user_id=any(${textIDs(spec)});
  ${mutation}
  if (select count(*) from public.notification_events where recipient_user_id=any(${textIDs(spec)}) or actor_user_id=any(${textIDs(spec)}))<>notification_count then raise exception 'unexpected_notification_effect'; end if;
  if ${sharedVisitCount(spec)}<>0 then raise exception 'unexpected_shared_visit_effect'; end if;
  final_row := ${currentResourceSQL(spec, entry.transition)};
  ${entry.transition.resource==='context'&&entry.transition.action==='revoke'?"if final_row is null or (coalesce((final_row->>'allowedA')::boolean,true) and coalesce((final_row->>'allowedB')::boolean,true)) then raise exception 'context_revocation_failed'; end if;":''}
  perform set_config('rec636.result',jsonb_build_object('before',original,'after',final_row)::text,true);
end $rec636$;
select current_setting('rec636.result')::jsonb as rec636_result;`, { rollback });
}
export function generateReconcileSQL(value) {
  const state = stateOf(value); const spec = specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context});
  const pending = state.intents.filter((item) => ['intent', 'interrupted'].includes(item.state));
  if (pending.some((item) => item.kind === 'operator_transition' || item.kind === 'mark_read')) fail('operator_or_read_reconciliation_required');
  const expressions = pending.map((item) => {
    if (item.kind === 'start') return `jsonb_build_object('intentID',${literal(item.id)},'status',case when exists(select 1 from public.private_conversations where low_user_id=least(${literal(spec.accounts.A)},${literal(spec.accounts.B)}) and high_user_id=greatest(${literal(spec.accounts.A)},${literal(spec.accounts.B)})) then 'ambiguous' else 'absent' end)`;
    const contextMatch = item.context === null ? 'm.context_kind is null and m.context_id is null'
      : `m.context_kind=${literal(item.context.kind)} and m.context_id=${uuid(item.context.id)}`;
    return `(select case when count(*)=0 then jsonb_build_object('intentID',${literal(item.id)},'status','absent') else
      jsonb_build_object('intentID',${literal(item.id)},'status','found','ack',min(jsonb_build_object('conversationID',m.conversation_id,'messageID',m.id,'senderID',m.sender_id,'clientID',m.client_id)::text)::jsonb) end
      from public.private_messages m join public.private_conversations c on c.id=m.conversation_id
      where m.sender_id=${literal(spec.accounts[item.actor])} and m.client_id=${uuid(item.clientID)}
        and m.conversation_id=${uuid(item.conversationID)} and ${contextMatch}
        and c.low_user_id=least(${literal(spec.accounts.A)},${literal(spec.accounts.B)}) and c.high_user_id=greatest(${literal(spec.accounts.A)},${literal(spec.accounts.B)}))`;
  });
  return transaction(`do $rec636$ begin ${locks(spec)}
  if (select ${flagRow('f')} from public.feature_flags f where key='unified_live_v1' and user_id is null) is distinct from ${json(state.baseline.globalFlag)} then raise exception 'global_live_drift'; end if;
  ${pending.filter((item) => ['send','send_retry'].includes(item.kind)).map((item) => `if exists(select 1 from public.private_messages m where m.sender_id=${literal(spec.accounts[item.actor])} and m.client_id=${uuid(item.clientID)} and (m.conversation_id<>${uuid(item.conversationID)} or m.context_kind is distinct from ${item.context ? literal(item.context.kind) : 'null'} or m.context_id is distinct from ${item.context ? uuid(item.context.id) : 'null::uuid'})) then raise exception 'foreign_client_identity'; end if;`).join('\n')}
  perform set_config('rec636.result',jsonb_build_object('intents',jsonb_build_array(${expressions.join(',')}))::text,true);
end $rec636$; select current_setting('rec636.result')::jsonb as rec636_result;`, { rollback: true });
}
function foreignMessageGuard(state) {
  const spec = specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context}); const plan = buildCleanupPlan(state);
  const known = state.intents.filter((item) => ['send','send_retry'].includes(item.kind) && item.ack).map((item) => {
    const context = item.context === null ? 'm.context_kind is null and m.context_id is null'
      : `m.context_kind=${literal(item.context.kind)} and m.context_id=${uuid(item.context.id)}`;
    return `(m.id=${uuid(item.ack.messageID)} and m.sender_id=${literal(spec.accounts[item.actor])} and m.client_id=${uuid(item.clientID)} and m.conversation_id=${uuid(item.conversationID)} and ${context})`;
  });
  return `if exists(select 1 from public.private_messages m where m.conversation_id=any(${ids(plan.conversationIDs)}) and not (${known.length ? known.join(' or ') : 'false'})) then raise exception 'foreign_message'; end if;`;
}
function restoredGuardSQL(state) {
  const spec = specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context});
  let checks = '';
  for (const resource of ['account_flag','follow','block']) for (const actor of ['A','B']) {
    const t = {resource,actor,...(resource==='account_flag'?{}:{targetActor:actor==='A'?'B':'A'})};
    const expected = baselineResources(state).get(resourceKey(t));
    const omitted = resource==='follow' ? " - 'xmin' - 'updatedAt'" : " - 'xmin'";
    checks += `if (${currentResourceSQL(spec,t)}${omitted}) is distinct from (${json(expected)}${omitted}) then raise exception 'baseline_restoration_failed'; end if;\n`;
  }
  checks += `if (${contextQuery(spec)} - 'xmin' - 'sourceXmin' - 'allowedA' - 'allowedB') is distinct from (${json(state.baseline.contextReceipt)} - 'xmin' - 'sourceXmin' - 'allowedA' - 'allowedB')
    or not app.private_message_context_allowed(${literal(spec.accounts.A)},${literal(spec.accounts.B)},${literal(spec.context.kind)},${uuid(spec.context.id)}) then raise exception 'context_restoration_failed'; end if;`;
  return checks;
}
export function generateCleanupSQL(value, { rollback = false } = {}) {
  const state = stateOf(value); const plan = buildCleanupPlan(state); const spec = specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context});
  if (plan.status === 'blocked') fail('reconciliation_required');
  if (plan.status === 'already_cleaned') return generateCleanedVerificationSQL(state);
  if (state.phase !== 'cleanup_planned') fail('cleanup_freeze_required');
  const expected = expectedResources(state); const baseline = baselineResources(state); let restore = '';
  for (const [key, before] of expected) {
    const original = baseline.get(key); const resource = key.split(':')[0];
    if (same(before, original)) continue;
    if (resource === 'account_flag' && before?.enabled === original?.enabled) continue;
    if (resource === 'follow' && before !== null && before.id === original?.id && before.source === original.source && before.createdAt === original.createdAt) continue;
    if (resource === 'context' && before.visibility === original.visibility && !before.deleted) continue;
    if (resource === 'block' && before === null) continue;
    const actor = resource === 'context' ? (original.ownerID === spec.accounts.A ? 'A' : 'B') : key.split(':')[1];
    const targetActor = key.split(':')[2];
    const entry = { id: before?.id ?? state.runID, transition: { resource: resource === 'context' ? 'context' : resource, actor,
      action: resource === 'block' ? 'remove' : 'restore', ...(targetActor ? { targetActor } : {}) } };
    restore += `\n${transitionMutation(state, entry, before)}`;
  }
  return transaction(`do $rec636$ declare notification_count bigint; begin
  ${locks(spec)} ${guardSQL(state)} ${foreignMessageGuard(state)}
  select count(*) into notification_count from public.notification_events where recipient_user_id=any(${textIDs(spec)}) or actor_user_id=any(${textIDs(spec)});
  delete from public.private_messages where id=any(${ids(plan.messages.map((item) => item.id))}) and conversation_id=any(${ids(plan.conversationIDs)});
  if exists(select 1 from public.private_messages where conversation_id=any(${ids(plan.conversationIDs)})) then raise exception 'foreign_message'; end if;
  delete from public.private_conversations where id=any(${ids(plan.conversationIDs)}) and low_user_id=least(${literal(spec.accounts.A)},${literal(spec.accounts.B)}) and high_user_id=greatest(${literal(spec.accounts.A)},${literal(spec.accounts.B)});
  ${restore}
  if (select count(*) from public.notification_events where recipient_user_id=any(${textIDs(spec)}) or actor_user_id=any(${textIDs(spec)}))<>notification_count then raise exception 'unexpected_notification_effect'; end if;
  ${restoredGuardSQL(state)}
  if exists(select 1 from public.private_conversations where low_user_id=any(${textIDs(spec)}) or high_user_id=any(${textIDs(spec)})) then raise exception 'cleanup_incomplete'; end if;
  perform set_config('rec636.result',jsonb_build_object('runID',${literal(spec.runID)},'conversationCount',0,'messageCount',0,'baselineRestored',true,'globalLiveEnabled',false)::text,true);
end $rec636$; select current_setting('rec636.result')::jsonb as rec636_result;`, { rollback });
}
function generateCleanedVerificationSQL(state) {
  const spec = specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context});
  // A cleaned journal authorizes verification only, never another deletion.
  // IDs and logical source/social contents remain exact. Only revisions and
  // the follow timestamp caused by this run's restoration are omitted.
  return transaction(`do $rec636$ begin
    if (select ${flagRow('f')} from public.feature_flags f where key='unified_live_v1' and user_id is null) is distinct from ${json(state.baseline.globalFlag)} then raise exception 'global_live_drift'; end if;
    if (select jsonb_agg(jsonb_build_object('id',p.id,'xmin',p.xmin::text,'deleted',p.deleted_at is not null) order by array_position(${textIDs(spec)},p.id)) from public.profiles p where p.id=any(${textIDs(spec)})) is distinct from ${json(state.baseline.profiles)} then raise exception 'profile_baseline_drift'; end if;
    if ${sharedVisitCount(spec)}<>0 or ${sideEffectCount(spec)}<>0 then raise exception 'fixture_side_effect_risk'; end if;
    ${restoredGuardSQL(state)}
    perform set_config('rec636.result',jsonb_build_object('runID',${literal(spec.runID)},
      'conversationCount',(select count(*) from public.private_conversations where low_user_id=any(${textIDs(spec)}) or high_user_id=any(${textIDs(spec)})),
      'messageCount',(select count(*) from public.private_messages where sender_id=any(${textIDs(spec)})),
      'baselineRestored',true,'globalLiveEnabled',false)::text,true);
    end $rec636$; select current_setting('rec636.result')::jsonb as rec636_result;`, { rollback: true, readOnly: true });
}

// Source hashes are from the final checked-in definitions. These exclude
// formatting of pg_get_functiondef for historical functions, preserving prosrc.
const TRIGGER_SOURCE_HASHES = [
  ['app.notify_follow_insert()', 'f7974e1e74e01ff027738170e5b7a099'],
  ['app.record_follow_notification_receipt()', 'b647494c2c8293f26c1fc1c16aa7b8d5'],
  ['app.cancel_shared_visits_after_block()', '010b89f6df88cafad42254c741f91d17'],
  ['app.record_companion_audience_change()', '95277f79f54c7c72ce82daade2a99228'],
  ['app.user_place_taxonomy_maintenance()', '0b49a7207135dfb2970b530aa37244d1'],
  ['app.recompute_place_taxonomy_consensus(uuid)', '752801530d3e8779a1b84a71a44a50fe'],
  ['app.capture_place_taxonomy_snapshot(text,uuid,text)', '57e13fe8392c87ff65e300a2d6415e37'],
  ['app.cancel_shared_visits_after_user_place_change()', 'dc54bb2fb26a669ed97e4c4f449baeeb'],
  ['app.set_updated_at()', '9b1889f56258bf9d6554213c05019c76'],
  ['app.remove_unused_place_taxonomy_snapshot(text,uuid)', '2cda21763a5710eda3f7bdb063742ad7'],
];
const MESSAGE_DEFINITION_HASHES = [
  ['app.private_message_participant_enabled(text)', 'a6dcbd6d518a464e9ead69db14cc2383'],
  ['app.private_message_pair_allowed(text,text)', '67af27f960a55fc8feda545db6d2fd1a'],
  ['app.private_message_context_allowed(text,text,text,uuid)', 'a4cef1bd31ae96cafb08cc379c83d1cd'],
  ['app.private_message_json(uuid,text)', '8fa48db1ce57321ecd195776238a6519'],
  ['app.private_conversation_json(uuid,text)', '16a4ea757347664016999fd1326a3e83'],
  ['public.private_message_conversation(uuid)', '943b30d5b208b1fe965160d92b7f685d'],
  ['public.private_message_start(text,text,uuid)', '94fdbae16e6e455e7a18e7c9730e2ac3'],
  ['public.private_message_inbox(timestamptz,uuid,integer)', 'bd253e15ddb729bc941de748ad999711'],
  ['public.private_message_history(uuid,timestamptz,uuid,integer)', 'eac81989a10be3680a2880efbec53493'],
  ['public.private_message_send(uuid,text,uuid,text,uuid)', '686a7fd0f440f5def4595f530873dd3a'],
  ['public.private_message_mark_read(uuid,uuid)', 'a9b6e4ef5840e07e022722d04a2d633d'],
  ['app.live_feed_polygon(jsonb)', 'dc6c59eebf7ee3eb7f831f29562ef365'],
  ['app.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[])', 'c75e611f44162f6504dab1d4cc113edf'],
  ['public.live_activity_feed(text,timestamptz,timestamptz,text,jsonb,text,integer,double precision,double precision,integer,text[],text[])', '5d0cefdb1b9cdfaef4aa701e03e21a9c'],
];
function contractChecksSQL() {
  return `  if not exists(select 1 from pg_roles where rolname=current_user and (rolsuper or rolbypassrls)) then raise exception 'operator_session_required'; end if;
  for expected in select * from (values ${MESSAGE_DEFINITION_HASHES.map(([sig, hash]) => `(${literal(sig)},${literal(hash)})`).join(',')}) v(signature,hash) loop
    if to_regprocedure(expected.signature) is null or md5(pg_get_functiondef(to_regprocedure(expected.signature)))<>expected.hash then raise exception 'message_contract_drift'; end if;
  end loop;
  for expected in select * from (values ${TRIGGER_SOURCE_HASHES.map(([sig, hash]) => `(${literal(sig)},${literal(hash)})`).join(',')}) v(signature,hash) loop
    if not exists(select 1 from pg_proc where oid=to_regprocedure(expected.signature) and md5(prosrc)=expected.hash) then raise exception 'trigger_contract_drift'; end if;
  end loop;
  for expected in select * from (values ('public'),('anon'),('authenticated')) roles(name) loop
    if has_table_privilege(expected.name,'public.private_messages','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      or has_table_privilege(expected.name,'public.private_conversations','SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      or has_any_column_privilege(expected.name,'public.private_messages','SELECT,INSERT,UPDATE,REFERENCES')
      or has_any_column_privilege(expected.name,'public.private_conversations','SELECT,INSERT,UPDATE,REFERENCES')
      or has_table_privilege(expected.name,'public.feature_flags','INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
      or has_any_column_privilege(expected.name,'public.feature_flags','INSERT,UPDATE,REFERENCES') then raise exception 'client_write_grant_drift'; end if;
  end loop;
  if (select count(*) from pg_trigger where tgrelid='public.follows'::regclass and not tgisinternal and tgname in('follows_notify_insert','follows_record_inbox_receipt') and tgenabled='O' and pg_get_triggerdef(oid) like '%WHEN ((new.source <> ''signup_default''::text))%')<>2 then raise exception 'follow_trigger_guard_drift'; end if;
`;
}
export function generateContractVerificationSQL() {
  // Metadata-only: can run in a migration preview before test identities exist.
  // No fixture rows, persisted helpers, credentials, grants or activation.
  return transaction(`do $rec636$ declare expected record; begin
  ${contractChecksSQL()}
  perform set_config('rec636.result',jsonb_build_object('version',1,'contractChecks',24,'triggerGuardsVerified',true,'clientWriteGrantsDenied',true,'rolledBack',true,'accountTrialsVerified',false)::text,true);
  end $rec636$; select current_setting('rec636.result')::jsonb as rec636_result;`, {rollback:true,readOnly:true});
}
export function generateVerificationSQL(value) {
  const baseline = validateBaselineReceipt(value); const spec = specOf({runID:value.runID,targetRef:value.targetRef,accounts:value.accounts,context:value.context});
  const state = { version: 1, ...spec, createdAt: baseline.capturedAt, revision: 0, phase: 'active', baseline, intents: [] };
  const probeID = (suffix) => `${spec.runID.slice(0,-4)}${suffix}`;
  const probe = {...state,phase:'cleanup_planned',revision:2,intents:[
    {id:probeID('d001'),kind:'start',actor:'A',recipient:'B',context:spec.context,state:'acknowledged',ack:{conversationID:spec.runID}},
    {id:probeID('d002'),kind:'send',actor:'A',conversationID:spec.runID,clientID:probeID('d003'),context:spec.context,state:'acknowledged',
      ack:{conversationID:spec.runID,messageID:probeID('d004'),senderID:spec.accounts.A,clientID:probeID('d003')}},
  ]};
  // Execute the production generator's exact cleanup DO block over private
  // synthetic rows inside this same rollback transaction. No client receives
  // these rows and no preexisting fixture context is deleted.
  const cleanupSQL=generateCleanupSQL(probe,{rollback:true});
  const cleanupDO=cleanupSQL.slice(cleanupSQL.indexOf('do $rec636$'),cleanupSQL.lastIndexOf("select current_setting('rec636.result')"));
  const cleanupProbe=`do $rec636$ declare expected record; begin
    ${locks(spec)} ${guardSQL(state,{allowOwnedConversations:false})} ${contractChecksSQL()}
    insert into public.private_conversations(id,low_user_id,high_user_id,created_by)
      values(${uuid(spec.runID)},least(${literal(spec.accounts.A)},${literal(spec.accounts.B)}),greatest(${literal(spec.accounts.A)},${literal(spec.accounts.B)}),${literal(spec.accounts.A)});
    insert into public.private_messages(id,conversation_id,sender_id,client_id,body,context_kind,context_id)
      values(${uuid(probeID('d004'))},${uuid(spec.runID)},${literal(spec.accounts.A)},${uuid(probeID('d003'))},'REC-636 rollback verification payload',${literal(spec.context.kind)},${uuid(spec.context.id)});
    end $rec636$;
    ${cleanupDO}`;
  const aFollow = baseline.follows[0].row; const context = baseline.contextReceipt;
  return transaction(`${cleanupProbe}
  do $rec636$ declare expected record; original_notifications bigint; original_receipts bigint; original_shared bigint; source_before text; begin
  if not exists(select 1 from pg_roles where rolname=current_user and (rolsuper or rolbypassrls)) then raise exception 'operator_session_required'; end if;
  ${locks(spec)} ${guardSQL(state, { allowOwnedConversations: false })}
  ${contractChecksSQL()}
  select count(*) into original_notifications from public.notification_events where recipient_user_id=any(${textIDs(spec)}) or actor_user_id=any(${textIDs(spec)});
  select count(*) into original_receipts from public.follow_notification_receipts where recipient_id=any(${textIDs(spec)}) or actor_id=any(${textIDs(spec)});
  original_shared := ${sharedVisitCount(spec)};
  -- Exercise each restoration path against the exact scoped fixture, then
  -- discard the entire transaction. No grants/helpers/records persist.
  update public.feature_flags set enabled=false where id=${uuid(baseline.accountFlags[0].row.id)};
  update public.feature_flags set enabled=true where id=${uuid(baseline.accountFlags[0].row.id)};
  delete from public.follows where id=${uuid(aFollow.id)};
  insert into public.follows(id,follower_user_id,followed_user_id,source,created_at,updated_at) values(${uuid(aFollow.id)},${literal(spec.accounts.A)},${literal(spec.accounts.B)},'signup_default',${literal(aFollow.createdAt)}::timestamptz,${literal(aFollow.updatedAt)}::timestamptz);
  update public.follows set source=${literal(aFollow.source)} where id=${uuid(aFollow.id)};
  insert into public.blocks(id,blocker_user_id,blocked_user_id) values(${uuid(spec.runID)},${literal(spec.accounts.A)},${literal(spec.accounts.B)});
  delete from public.blocks where id=${uuid(spec.runID)};
  update public.user_places set visibility='self' where id=${uuid(context.userPlaceID)};
  update public.user_places set visibility=${literal(context.visibility)} where id=${uuid(context.userPlaceID)};
  if (select count(*) from public.notification_events where recipient_user_id=any(${textIDs(spec)}) or actor_user_id=any(${textIDs(spec)}))<>original_notifications
    or (select count(*) from public.follow_notification_receipts where recipient_id=any(${textIDs(spec)}) or actor_id=any(${textIDs(spec)}))<>original_receipts
    or ${sharedVisitCount(spec)}<>original_shared then raise exception 'fixture_transition_side_effect'; end if;
  if not app.is_mutual(${literal(spec.accounts.A)},${literal(spec.accounts.B)})
    or not app.private_message_context_allowed(${literal(spec.accounts.A)},${literal(spec.accounts.B)},${literal(spec.context.kind)},${uuid(spec.context.id)})
    or not app.private_message_pair_allowed(${literal(spec.accounts.A)},${literal(spec.accounts.B)}) then raise exception 'fixture_restoration_failed'; end if;
  perform set_config('rec636.result',jsonb_build_object('version',1,'runID',${literal(spec.runID)},'targetRef',${literal(spec.targetRef)},'operatorVerified',true,'globalLiveOff',true,'pristineBaseline',true,'fixtureTransitionsVerified',true,'rolledBack',true,'contractChecks',24)::text,true);
end $rec636$; select current_setting('rec636.result')::jsonb as rec636_result;`, { rollback: true });
}
function resultOf(rows) {
  if (!Array.isArray(rows) || rows.length !== 1 || !rows[0] || !Object.hasOwn(rows[0], 'rec636_result')) fail('invalid_operator_response');
  return rows[0].rec636_result;
}
export function isVerifiedCleanupCompanion(value) { return verified.has(value); }
export async function createCleanupCompanion({ executeSQL, spec: inputSpec } = {}) {
  if (typeof executeSQL !== 'function') fail('operator_adapter_required');
  const spec = specOf(inputSpec);
  const execute = async (sql, purpose) => {
    try { return resultOf(await executeSQL(sql, { purpose, runID: spec.runID, targetRef: spec.targetRef })); }
    catch (error) { if (error instanceof CleanupCompanionError) throw error; fail('operator_execution_failed'); }
  };
  const baseline = validateBaselineReceipt(await execute(generateBaselineSQL(spec), 'baseline'), spec);
  const proof = await execute(generateVerificationSQL(baseline), 'verification');
  shape(proof, ['version', 'runID', 'targetRef', 'operatorVerified', 'globalLiveOff', 'pristineBaseline', 'fixtureTransitionsVerified', 'rolledBack', 'contractChecks']);
  if (proof.version !== 1 || proof.runID !== spec.runID || proof.targetRef !== spec.targetRef
    || proof.contractChecks !== 24 || ['operatorVerified','globalLiveOff','pristineBaseline','fixtureTransitionsVerified','rolledBack'].some((key) => proof[key] !== true)) fail('operator_verification_failed');
  const scoped = (value) => {
    const state = stateOf(value);
    if (!same(specOf({runID:state.runID,targetRef:state.targetRef,accounts:state.accounts,context:state.context}), spec) || !same(state.baseline, baseline)) fail('companion_scope_mismatch');
    return state;
  };
  const companion = Object.freeze({
    capabilities: Object.freeze({ baseline: true, reconciliation: true, cleanup: true, fixtureTransitions: true, databaseWriterQuiescence: true, transportQuiescence: false, cleanupQuiescence: false, fixtureProvisioning: false, fixtureDeletion: false }),
    baseline: () => clone(baseline),
    inspectBaseline: async (value = spec) => {
      if (!same(specOf(value), spec)) fail('companion_scope_mismatch');
      return validateBaselineReceipt(await execute(generateBaselineSQL(spec), 'baseline'), spec);
    },
    assertReady: async (value) => {
      const state = scoped(value);
      if (state.intents.length || state.phase !== 'active') fail('pristine_journal_required');
      const current = validateBaselineReceipt(await execute(generateBaselineSQL(spec), 'baseline'), spec);
      current.capturedAt = baseline.capturedAt;
      if (!same(current, baseline)) fail('baseline_drift');
      return { globalLiveOff: true, pristineBaseline: true, fixtureTransitionsVerified: true };
    },
    transitionOwnedFixture: async (value, intentID) => {
      const state = scoped(value); const receipt = await execute(generateTransitionSQL(state, intentID), 'transition');
      shape(receipt, ['before','after']);
      const candidate=clone(state); const entry=candidate.intents.find(item=>item.id===intentID);
      entry.state='acknowledged'; entry.ack=receipt;
      try { stateOf(candidate); } catch { fail('invalid_operator_receipt'); }
      return clone(receipt);
    },
    reconcile: async (value) => {
      const state = scoped(value); const result = await execute(generateReconcileSQL(state), 'reconcile');
      shape(result, ['intents']);
      const pending = state.intents.filter((item) => ['intent','interrupted'].includes(item.state));
      if (!Array.isArray(result.intents) || result.intents.length !== pending.length) fail('invalid_reconciliation');
      for (const [index, item] of result.intents.entries()) {
        if (item.intentID !== pending[index].id || !['found','absent'].includes(item.status)) fail('ambiguous_reconciliation');
        shape(item, item.status === 'found' ? ['intentID','status','ack'] : ['intentID','status']);
        if (item.status === 'found') {
          const candidate = clone(state); candidate.intents.find((entry) => entry.id === item.intentID).state='reconciled'; candidate.intents.find((entry) => entry.id === item.intentID).ack=item.ack;
          try { validateJournalState(candidate); } catch { fail('invalid_reconciliation'); }
        }
      }
      return clone(result);
    },
    cleanup: async (value) => {
      const state = scoped(value); const receipt = await execute(generateCleanupSQL(state), 'cleanup');
      shape(receipt, ['runID','conversationCount','messageCount','baselineRestored','globalLiveEnabled']);
      if (receipt.runID !== spec.runID || receipt.conversationCount !== 0 || receipt.messageCount !== 0
        || receipt.baselineRestored !== true || receipt.globalLiveEnabled !== false) fail('cleanup_not_verified');
      return { ...receipt, verified: true, globalLiveOff: true };
    },
  });
  verified.add(companion); return companion;
}
