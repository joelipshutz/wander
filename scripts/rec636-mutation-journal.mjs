#!/usr/bin/env node

// REC-636 operator tooling only. This module records identifiers and receipts;
// it opens no socket, discovers no credentials and enables no client writes.
import { randomUUID } from 'node:crypto';
import { constants } from 'node:fs';
import { open, lstat, rename, unlink } from 'node:fs/promises';
import { dirname, isAbsolute } from 'node:path';

const VERSION = 1;
const MAX_BYTES = 256 * 1024;
const MAX_INTENTS = 128;
const JOURNAL_HANDLES = new WeakSet();
export const isMutationJournalHandle = (value) => JOURNAL_HANDLES.has(value);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const ACCOUNT = /^[A-Za-z0-9_-]{1,256}$/u;
const REF = /^[a-z0-9]{20}$/u;
const XMIN = /^[0-9]{1,20}$/u;
const SOURCES = new Set(['username', 'contacts', 'profile', 'invite_link_future', 'signup_default']);
const VISIBILITIES = new Set(['followers', 'mutuals', 'self']);
const clone = (value) => JSON.parse(JSON.stringify(value));
const canonical = (value) => Array.isArray(value) ? value.map(canonical)
  : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonical(value[key])])) : value;
const same = (a, b) => JSON.stringify(canonical(a)) === JSON.stringify(canonical(b));
const own = (value, key) => Object.hasOwn(value, key);

export class MutationJournalError extends Error {
  constructor(code) { super(code); this.name = 'MutationJournalError'; this.code = code; }
}
const fail = (code = 'invalid_journal') => { throw new MutationJournalError(code); };
function shape(value, required, optional = [], code = 'invalid_journal') {
  if (value === null || typeof value !== 'object' || Array.isArray(value)
    || ![Object.prototype, null].includes(Object.getPrototypeOf(value))
    || Object.getOwnPropertySymbols(value).length) fail(code);
  const descriptors = Object.getOwnPropertyDescriptors(value);
  if (Object.values(descriptors).some((descriptor) => !own(descriptor, 'value'))
    || required.some((key) => !own(value, key))
    || Object.keys(value).some((key) => !required.includes(key) && !optional.includes(key))) fail(code);
}
const uuid = (value) => { if (typeof value !== 'string' || !UUID.test(value)) fail(); return value; };
const accountID = (value) => { if (typeof value !== 'string' || !ACCOUNT.test(value)) fail(); return value; };
const label = (value) => { if (!['A', 'B'].includes(value)) fail(); return value; };
const timestamp = (value) => {
  if (typeof value !== 'string' || value.length > 35
    || !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|[+-]\d\d:\d\d)$/u.test(value)
    || !Number.isFinite(Date.parse(value))) fail();
  return value;
};
function accounts(value) {
  shape(value, ['A', 'B']); accountID(value.A); accountID(value.B);
  if (value.A === value.B) fail();
}
function context(value) {
  shape(value, ['kind', 'id']);
  if (!['place', 'activity'].includes(value.kind)) fail(); uuid(value.id);
}
function rowBase(value) {
  uuid(value.id); if (typeof value.xmin !== 'string' || !XMIN.test(value.xmin)) fail();
}
function flagRow(value) {
  shape(value, ['id', 'xmin', 'enabled', 'valueType', 'integerValue']); rowBase(value);
  if (typeof value.enabled !== 'boolean' || value.valueType !== 'boolean' || value.integerValue !== null) fail();
}
function followRow(value) {
  shape(value, ['id', 'xmin', 'source', 'createdAt', 'updatedAt']); rowBase(value);
  if (!SOURCES.has(value.source)) fail(); timestamp(value.createdAt); timestamp(value.updatedAt);
}
function blockRow(value) {
  shape(value, ['id', 'xmin', 'createdAt']); rowBase(value); timestamp(value.createdAt);
}
function contextReceipt(value, state, isBaseline = false) {
  shape(value, ['kind', 'id', 'xmin', 'deleted', 'allowedA', 'allowedB'], ['ownerID', 'placeID', 'visibility', 'userPlaceID', 'sourceXmin']);
  if (value.kind !== state.context.kind || value.id !== state.context.id
    || typeof value.xmin !== 'string' || !XMIN.test(value.xmin)
    || ['deleted', 'allowedA', 'allowedB'].some((key) => typeof value[key] !== 'boolean')) fail();
  if (own(value, 'ownerID') && !Object.values(state.accounts).includes(value.ownerID)) fail();
  if (own(value, 'placeID')) uuid(value.placeID);
  if (own(value, 'visibility') && !VISIBILITIES.has(value.visibility)) fail();
  if (own(value, 'userPlaceID') !== own(value, 'sourceXmin')) fail();
  if (own(value, 'userPlaceID')) { uuid(value.userPlaceID); if (typeof value.sourceXmin !== 'string' || !XMIN.test(value.sourceXmin)) fail(); }
  if (isBaseline && (value.deleted || !value.allowedA || !value.allowedB)) fail('unclean_baseline');
}
function array(value, count) { if (!Array.isArray(value) || value.length !== count) fail(); }

// Structural and scope validation is deliberately separate from the companion's
// privileged query verification. A caller-supplied object is never hosted proof.
export function validateJournalBaseline(value, state) {
  shape(value, ['version', 'runID', 'targetRef', 'accounts', 'context', 'capturedAt', 'profiles',
    'globalFlag', 'accountFlags', 'follows', 'blocks', 'contextReceipt', 'conversationCount', 'messageCount', 'sharedVisitCount', 'sourceSideEffectCount']);
  if (value.version !== VERSION || value.runID !== state.runID || value.targetRef !== state.targetRef) fail();
  accounts(value.accounts); context(value.context);
  if (!same(value.accounts, state.accounts) || !same(value.context, state.context)) fail('baseline_scope_mismatch');
  timestamp(value.capturedAt);
  array(value.profiles, 2);
  for (const [index, row] of value.profiles.entries()) {
    shape(row, ['id', 'xmin', 'deleted']);
    if (row.id !== value.accounts[['A', 'B'][index]] || typeof row.xmin !== 'string' || !XMIN.test(row.xmin) || row.deleted !== false) fail('unclean_baseline');
  }
  flagRow(value.globalFlag); if (value.globalFlag.enabled) fail('global_live_must_remain_off');
  array(value.accountFlags, 2);
  for (const [index, item] of value.accountFlags.entries()) {
    shape(item, ['userID', 'row']); if (item.userID !== value.accounts[['A', 'B'][index]]) fail();
    if (item.row !== null) flagRow(item.row);
  }
  for (const [key, first, second, validateRow] of [
    ['follows', 'followerID', 'followedID', followRow], ['blocks', 'blockerID', 'blockedID', blockRow],
  ]) {
    array(value[key], 2);
    for (const [index, item] of value[key].entries()) {
      shape(item, [first, second, 'row']);
      if (item[first] !== value.accounts[index === 0 ? 'A' : 'B']
        || item[second] !== value.accounts[index === 0 ? 'B' : 'A']) fail();
      if (item.row !== null) validateRow(item.row);
    }
  }
  contextReceipt(value.contextReceipt, state, true);
  if (value.conversationCount !== 0 || value.messageCount !== 0 || value.sharedVisitCount !== 0 || value.sourceSideEffectCount !== 0) fail('unclean_baseline');
  return clone(value);
}

function transition(value) {
  shape(value, ['resource', 'action', 'actor'], ['targetActor']); label(value.actor);
  const actions = {
    account_flag: ['enable', 'revoke', 'restore'], follow: ['remove', 'restore'],
    block: ['insert', 'remove'], context: ['revoke', 'restore'],
  };
  if (!actions[value.resource]?.includes(value.action)) fail('unsupported_transition');
  if (['follow', 'block'].includes(value.resource)) {
    label(value.targetActor); if (value.actor === value.targetActor) fail();
  } else if (own(value, 'targetActor')) fail();
}
function transitionReceipt(value, intent, state) {
  shape(value, ['before', 'after']);
  const validateRow = { account_flag: flagRow, follow: followRow, block: blockRow,
    context: (row) => contextReceipt(row, state) }[intent.transition.resource];
  for (const key of ['before', 'after']) {
    if (value[key] === null) {
      if (intent.transition.resource === 'context') fail();
    } else validateRow(value[key]);
  }
  const { action, resource } = intent.transition;
  if ((action === 'insert' || action === 'enable') && value.after === null
    || action === 'remove' && value.after !== null
    || resource === 'account_flag' && action === 'enable' && value.after.enabled !== true
    || resource === 'account_flag' && action === 'revoke' && value.after !== null && value.after.enabled !== false) fail();
}
function acknowledgment(value, intent, state) {
  if (intent.kind === 'operator_transition') return transitionReceipt(value, intent, state);
  if (intent.kind === 'start') { shape(value, ['conversationID']); uuid(value.conversationID); return; }
  if (intent.kind === 'mark_read') {
    shape(value, ['conversationID', 'throughMessageID']);
    if (value.conversationID !== intent.conversationID || value.throughMessageID !== intent.throughMessageID) fail('acknowledgment_scope_mismatch');
    return;
  }
  shape(value, ['conversationID', 'messageID', 'senderID', 'clientID']); uuid(value.messageID);
  if (value.conversationID !== intent.conversationID || value.clientID !== intent.clientID
    || value.senderID !== state.accounts[intent.actor]) fail('acknowledgment_scope_mismatch');
}
function operatorKey(value) {
  return value.resource === 'context' ? 'context' : `${value.resource}:${value.actor}:${value.targetActor ?? ''}`;
}
function baselineOperatorRow(state, value) {
  if (value.resource === 'context') return state.baseline.contextReceipt;
  if (value.resource === 'account_flag') return state.baseline.accountFlags.find((item) => item.userID === state.accounts[value.actor]).row;
  const [list, first, second] = value.resource === 'follow'
    ? ['follows', 'followerID', 'followedID'] : ['blocks', 'blockerID', 'blockedID'];
  return state.baseline[list].find((item) => item[first] === state.accounts[value.actor] && item[second] === state.accounts[value.targetActor]).row;
}
function logicalRow(value, resource) {
  if (value === null) return null;
  const result = clone(value); delete result.xmin; delete result.sourceXmin;
  // Follow restoration runs the existing updated_at trigger. Its new timestamp
  // is an exact observed receipt, while the original identity/source remain fixed.
  if (resource === 'follow') delete result.updatedAt;
  return result;
}
function verifyOperatorChain(entry, state, currentRow) {
  const { resource, action, actor } = entry.transition;
  const { before, after } = entry.ack;
  if (!same(before, currentRow)) fail('operator_receipt_chain_mismatch');
  if (before !== null && after !== null && before.id !== after.id) fail('operator_row_identity_mismatch');
  if (resource === 'context' && state.baseline.contextReceipt.ownerID !== undefined
    && state.baseline.contextReceipt.ownerID !== state.accounts[actor]) fail('operator_scope_mismatch');
  if (resource === 'follow' && action === 'remove' && before === null
    || resource === 'block' && action === 'insert' && before !== null
    || resource === 'block' && action === 'remove' && before === null) fail('operator_receipt_chain_mismatch');
  if (action === 'restore' && !same(logicalRow(after, resource), logicalRow(baselineOperatorRow(state, entry.transition), resource))) fail('operator_restoration_mismatch');
  if (resource === 'context' && action === 'revoke' && after.allowedA && after.allowedB) fail('operator_revocation_unverified');
}
function intent(value, state) {
  shape(value, ['id', 'kind', 'actor', 'state'], ['recipient', 'conversationID', 'clientID',
    'context', 'throughMessageID', 'transition', 'ack', 'rejectionCode', 'originalIntentID']);
  uuid(value.id); label(value.actor);
  if (!['intent', 'interrupted', 'acknowledged', 'reconciled', 'absent', 'rejected'].includes(value.state)) fail();
  const fields = {
    start: ['recipient', 'context'], send: ['conversationID', 'clientID', 'context'],
    send_retry: ['conversationID', 'clientID', 'context', 'originalIntentID'],
    mark_read: ['conversationID', 'throughMessageID'], operator_transition: ['transition'],
  }[value.kind];
  if (!fields || fields.some((key) => !own(value, key))
    || ['recipient', 'conversationID', 'clientID', 'context', 'throughMessageID', 'transition', 'originalIntentID']
      .some((key) => own(value, key) && !fields.includes(key))) fail();
  if (value.kind === 'start') {
    label(value.recipient); if (value.recipient === value.actor) fail(); context(value.context);
    if (!same(value.context, state.context)) fail('context_scope_mismatch');
  }
  if (['send', 'send_retry'].includes(value.kind)) {
    uuid(value.conversationID); uuid(value.clientID);
    if (value.kind === 'send_retry') uuid(value.originalIntentID);
    if (value.context !== null) { context(value.context); if (!same(value.context, state.context)) fail('context_scope_mismatch'); }
  }
  if (value.kind === 'mark_read') { uuid(value.conversationID); uuid(value.throughMessageID); }
  if (value.kind === 'operator_transition') {
    transition(value.transition); if (value.transition.actor !== value.actor) fail();
  }
  const completed = ['acknowledged', 'reconciled'].includes(value.state);
  if (own(value, 'ack') !== completed) fail();
  if (completed) acknowledgment(value.ack, value, state);
  if (own(value, 'rejectionCode') !== (value.state === 'rejected')
    || value.state === 'rejected' && !['private_message_unavailable', 'private_message_idempotency_conflict'].includes(value.rejectionCode)) fail();
  if (value.state === 'rejected' && value.kind === 'operator_transition') fail();
}
export function validateJournalState(value) {
  shape(value, ['version', 'runID', 'targetRef', 'accounts', 'context', 'createdAt', 'revision', 'phase', 'baseline', 'intents'], ['cleanupReceipt']);
  if (value.version !== VERSION || typeof value.targetRef !== 'string' || !REF.test(value.targetRef)
    || !Number.isSafeInteger(value.revision) || value.revision < 0
    || !['active', 'cleanup_planned', 'cleaned'].includes(value.phase)) fail();
  uuid(value.runID); accounts(value.accounts); context(value.context); timestamp(value.createdAt);
  validateJournalBaseline(value.baseline, value);
  if (!Array.isArray(value.intents) || value.intents.length > MAX_INTENTS) fail();
  const ids = new Set(); const clients = new Set(); const messages = new Map(); const conversationIDs = new Set();
  const earlierIntents = new Map(); const operatorRows = new Map(); const pendingOperators = new Set();
  for (const entry of value.intents) {
    intent(entry, value); if (ids.has(entry.id)) fail('duplicate_intent'); ids.add(entry.id);
    if (entry.kind === 'send') { if (clients.has(entry.clientID)) fail('duplicate_client_id'); clients.add(entry.clientID); }
    if (entry.kind === 'start' && entry.ack) conversationIDs.add(entry.ack.conversationID);
    if (entry.kind === 'send_retry') {
      const original = earlierIntents.get(entry.originalIntentID);
      if (!original || original.kind !== 'send' || ['absent', 'rejected'].includes(original.state)
        || entry.actor !== original.actor || entry.clientID !== original.clientID
        || entry.conversationID !== original.conversationID || !same(entry.context, original.context)) fail('retry_not_allowed');
    }
    if (['send', 'send_retry'].includes(entry.kind) && entry.ack) {
      if (messages.has(entry.ack.messageID) && !same(messages.get(entry.ack.messageID), entry.ack)) fail('duplicate_message_id');
      messages.set(entry.ack.messageID, entry.ack);
    }
    // Write operations may only reference a conversation already acknowledged
    // by an earlier start in this clean-baseline run.
    if (['send', 'send_retry', 'mark_read'].includes(entry.kind) && !conversationIDs.has(entry.conversationID)) fail('conversation_not_owned');
    if (entry.kind === 'mark_read' && !messages.has(entry.throughMessageID)) fail('message_not_owned');
    if (entry.kind === 'operator_transition') {
      const key = operatorKey(entry.transition);
      if (pendingOperators.has(key)) fail('operator_reconciliation_required');
      if (['intent', 'interrupted'].includes(entry.state)) pendingOperators.add(key);
      if (entry.ack) {
        const before = operatorRows.has(key) ? operatorRows.get(key) : baselineOperatorRow(value, entry.transition);
        verifyOperatorChain(entry, value, before); operatorRows.set(key, entry.ack.after);
      }
    }
    earlierIntents.set(entry.id, entry);
  }
  if (conversationIDs.size > 1) fail('conversation_scope_mismatch');
  if (own(value, 'cleanupReceipt') !== (value.phase === 'cleaned')) fail();
  if (value.phase === 'cleaned') cleanupReceipt(value.cleanupReceipt, value);
  if (value.phase !== 'active' && value.intents.some((entry) => ['intent', 'interrupted'].includes(entry.state))) fail('reconciliation_required');
  const safe = clone(value); if (Buffer.byteLength(JSON.stringify(safe)) > MAX_BYTES) fail('journal_too_large');
  return safe;
}
function cleanupReceipt(receipt, state) {
  shape(receipt, ['runID', 'conversationCount', 'messageCount', 'baselineRestored', 'globalLiveEnabled']);
  if (receipt.runID !== state.runID || receipt.conversationCount !== 0 || receipt.messageCount !== 0
    || receipt.baselineRestored !== true || receipt.globalLiveEnabled !== false) fail('cleanup_not_verified');
}

export function buildCleanupPlan(value) {
  const state = validateJournalState(value);
  const unresolvedIntentIDs = state.intents.filter((entry) => ['intent', 'interrupted'].includes(entry.state)).map((entry) => entry.id);
  const conversationIDs = [...new Set(state.intents.filter((entry) => entry.kind === 'start' && entry.ack).map((entry) => entry.ack.conversationID))];
  const messages = [...new Map(state.intents.filter((entry) => ['send', 'send_retry'].includes(entry.kind) && entry.ack).map((entry) => [
    entry.ack.messageID, { id: entry.ack.messageID, senderID: entry.ack.senderID, clientID: entry.clientID, conversationID: entry.conversationID },
  ])).values()];
  const operatorMutations = state.intents.filter((entry) => entry.kind === 'operator_transition' && entry.ack).map((entry) => ({
    intentID: entry.id, transition: entry.transition, before: entry.ack.before, after: entry.ack.after,
  }));
  return { status: state.phase === 'cleaned' ? 'already_cleaned' : unresolvedIntentIDs.length ? 'blocked' : 'ready',
    runID: state.runID, conversationIDs, messages, operatorMutations, unresolvedIntentIDs };
}

function findIntent(state, id) { uuid(id); const found = state.intents.find((entry) => entry.id === id); if (!found) fail('unknown_intent'); return found; }
function applyEvent(state, event) {
  const next = clone(state);
  if (state.phase === 'cleaned') {
    if (event.type === 'cleanup') {
      cleanupReceipt(event.receipt, state); if (same(event.receipt, state.cleanupReceipt)) return next;
    }
    fail('journal_already_cleaned');
  }
  if (state.phase === 'cleanup_planned' && !['cleanup', 'prepare_cleanup'].includes(event.type)) fail('journal_frozen_for_cleanup');
  if (event.type === 'prepare_cleanup') {
    if (buildCleanupPlan(next).status !== 'ready') fail('reconciliation_required');
    if (next.phase === 'cleanup_planned') return next;
    next.phase = 'cleanup_planned';
  } else if (event.type === 'retry') {
    if (next.intents.length >= MAX_INTENTS) fail('too_many_intents');
    const original = findIntent(next, event.originalIntentID);
    if (original.kind !== 'send' || ['absent', 'rejected'].includes(original.state)) fail('retry_not_allowed');
    next.intents.push({ id: event.id, kind: 'send_retry', actor: original.actor, state: 'intent',
      conversationID: original.conversationID, clientID: original.clientID, context: clone(original.context), originalIntentID: original.id });
  } else if (event.type === 'intent') {
    if (next.intents.length >= MAX_INTENTS) fail('too_many_intents');
    next.intents.push(event.intent);
  } else if (event.type === 'cleanup') {
    if (buildCleanupPlan(next).status !== 'ready') fail('reconciliation_required');
    if (next.phase !== 'cleanup_planned') fail('cleanup_not_prepared');
    cleanupReceipt(event.receipt, next); next.phase = 'cleaned'; next.cleanupReceipt = clone(event.receipt);
  } else {
    const entry = findIntent(next, event.intentID);
    if (event.type === 'interrupted') {
      if (['acknowledged', 'reconciled', 'absent', 'rejected'].includes(entry.state)) return next;
      entry.state = 'interrupted';
    } else if (event.type === 'rejection') {
      shape(event.receipt, ['code']);
      if (!['private_message_unavailable', 'private_message_idempotency_conflict'].includes(event.receipt.code)
        || entry.kind === 'operator_transition') fail('invalid_rejection');
      if (entry.ack || entry.state === 'absent') fail('acknowledgment_conflict');
      if (entry.state === 'rejected' && entry.rejectionCode !== event.receipt.code) fail('acknowledgment_conflict');
      entry.state = 'rejected'; entry.rejectionCode = event.receipt.code;
    } else if (event.type === 'ack' || event.type === 'reconcile') {
      if (entry.state === 'rejected') fail('acknowledgment_conflict');
      if (event.absent) {
        if (entry.ack) fail('acknowledgment_conflict');
        entry.state = 'absent';
      } else {
        acknowledgment(event.ack, entry, next);
        if (entry.ack && !same(entry.ack, event.ack)) fail('acknowledgment_conflict');
        if (entry.state === 'absent') fail('acknowledgment_conflict');
        entry.ack = clone(event.ack); entry.state = event.type === 'ack' ? 'acknowledged' : 'reconciled';
        if (entry.kind === 'send_retry') {
          const original = findIntent(next, entry.originalIntentID);
          if (original.ack && !same(original.ack, event.ack)) fail('acknowledgment_conflict');
          if (!original.ack) { original.ack = clone(event.ack); original.state = 'reconciled'; }
        }
      }
    } else fail('unsupported_event');
  }
  next.revision += 1; return validateJournalState(next);
}

function safePath(path) {
  if (typeof path !== 'string' || !isAbsolute(path) || path.includes('\0')) fail('invalid_journal_path');
}
async function secureParent(path) {
  const stat = await lstat(dirname(path));
  if (!stat.isDirectory() || stat.isSymbolicLink() || (stat.mode & 0o022) !== 0
    || (typeof process.getuid === 'function' && stat.uid !== process.getuid())) fail('invalid_journal_path');
}
async function syncParent(path) {
  const handle = await open(dirname(path), constants.O_RDONLY);
  try { await handle.sync(); } finally { await handle.close(); }
}
async function readState(path) {
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const stat = await handle.stat();
    if (!stat.isFile() || stat.nlink !== 1 || (stat.mode & 0o077) !== 0
      || (typeof process.getuid === 'function' && stat.uid !== process.getuid())) fail('unsafe_journal_file');
    if (stat.size > MAX_BYTES) fail('journal_too_large');
    let value; try { value = JSON.parse(await handle.readFile('utf8')); } catch { fail('invalid_journal'); }
    return validateJournalState(value);
  } finally { await handle.close(); }
}
function sanitized(error, fallback = 'journal_io_failed') {
  if (error instanceof MutationJournalError) return error;
  if (error?.code === 'EEXIST') return new MutationJournalError('journal_busy_or_exists');
  if (error?.code === 'ENOENT') return new MutationJournalError('journal_missing');
  return new MutationJournalError(fallback);
}
function matchesScope(state, scope) {
  if (state.runID !== scope.expectedRunID || state.targetRef !== scope.targetRef
    || !same(state.accounts, scope.accounts)) fail('journal_scope_mismatch');
}
async function atomicSave(path, state) {
  const temporary = `${path}.tmp-${randomUUID()}`;
  let handle; let created = false;
  try {
    handle = await open(temporary, 'wx', 0o600); created = true;
    await handle.writeFile(`${JSON.stringify(state)}\n`, 'utf8'); await handle.sync(); await handle.close(); handle = undefined;
    await rename(temporary, path); await syncParent(path);
  } finally {
    await handle?.close();
    // This exact randomly named intermediate was created by this call only.
    if (created) await unlink(temporary).catch((error) => { if (error?.code !== 'ENOENT') throw error; });
  }
}
function journalHandle(path, initial) {
  let current = initial; let queued = Promise.resolve();
  const scope = { expectedRunID: initial.runID, targetRef: initial.targetRef, accounts: initial.accounts };
  const update = (event) => {
    const operation = queued.then(async () => {
      let lock;
      try {
        await secureParent(path); lock = await open(`${path}.lock`, 'wx', 0o600);
        const state = await readState(path); matchesScope(state, scope);
        const next = applyEvent(state, event);
        await atomicSave(path, next); current = next; return clone(next);
      } catch (error) { throw sanitized(error); }
      finally { if (lock) {
        try { await lock.close(); await unlink(`${path}.lock`); } catch (error) { throw sanitized(error); }
      } }
    });
    queued = operation.catch(() => {}); return operation;
  };
  const handle = Object.freeze({
    snapshot: () => clone(current),
    recordIntent: async (input) => {
      shape(input, ['kind', 'actor'], ['recipient', 'conversationID', 'context', 'throughMessageID', 'transition']);
      const entry = { id: randomUUID(), ...clone(input), state: 'intent' };
      if (entry.kind === 'send') entry.clientID = randomUUID();
      // Validate before opening or changing any file. The persisted snapshot is
      // validated again under the exclusive lock before mutation.
      intent(entry, current);
      const state = await update({ type: 'intent', intent: entry }); return clone(findIntent(state, entry.id));
    },
    recordRetry: async (intentID) => {
      uuid(intentID); const retryID = randomUUID();
      const state = await update({ type: 'retry', originalIntentID: intentID, id: retryID });
      return clone(findIntent(state, retryID));
    },
    recordRejection: async (intentID, receipt) => update({ type: 'rejection', intentID, receipt }),
    recordAcknowledgment: async (intentID, ack) => update({ type: 'ack', intentID, ack }),
    markInterrupted: async (intentID) => update({ type: 'interrupted', intentID }),
    reconcile: async (intentID, result) => {
      shape(result, ['status'], ['ack']);
      if (!['found', 'absent'].includes(result.status) || own(result, 'ack') !== (result.status === 'found')) fail('invalid_reconciliation');
      return update({ type: 'reconcile', intentID, ack: result.ack, absent: result.status === 'absent' });
    },
    planCleanup: () => buildCleanupPlan(current),
    beginCleanup: async () => buildCleanupPlan(await update({ type: 'prepare_cleanup' })),
    markCleanupVerified: async (receipt) => update({ type: 'cleanup', receipt }),
  });
  JOURNAL_HANDLES.add(handle); return handle;
}

export async function createMutationJournal({ path, targetRef, accounts: pair, context: source, baseline }) {
  safePath(path);
  const initial = { version: VERSION, runID: baseline?.runID, targetRef, accounts: pair, context: source,
    createdAt: new Date().toISOString(), revision: 0, phase: 'active', baseline, intents: [] };
  const state = validateJournalState(initial);
  let handle;
  try {
    await secureParent(path); handle = await open(path, 'wx', 0o600);
    await handle.writeFile(`${JSON.stringify(state)}\n`, 'utf8'); await handle.sync(); await handle.close(); handle = undefined;
    await syncParent(path); return journalHandle(path, state);
  } catch (error) { throw sanitized(error); }
  finally { try { await handle?.close(); } catch (error) { throw sanitized(error); } }
}
export async function openMutationJournal({ path, expectedRunID, targetRef, accounts: pair }) {
  safePath(path); uuid(expectedRunID); accounts(pair);
  if (typeof targetRef !== 'string' || !REF.test(targetRef)) fail('invalid_journal');
  try {
    await secureParent(path); const state = await readState(path);
    matchesScope(state, { expectedRunID, targetRef, accounts: pair }); return journalHandle(path, state);
  } catch (error) { throw sanitized(error); }
}
