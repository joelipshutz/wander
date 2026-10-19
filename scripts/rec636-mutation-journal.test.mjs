import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { chmod, link, mkdtemp, readFile, rm, stat, symlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import test from 'node:test';
import {
  MutationJournalError, buildCleanupPlan, createMutationJournal, openMutationJournal, isMutationJournalHandle,
  validateJournalBaseline, validateJournalState,
} from './rec636-mutation-journal.mjs';

// Every identity, receipt and resource below is a fictional offline fixture.
// Tests neither connect to a service nor discover credentials or account data.
const REF = 'a'.repeat(20);
const PAIR = { A: 'fixture_A', B: 'fixture_B' };
const DATE = '2030-01-01T00:00:00.000Z';
const flag = (enabled = false) => ({ id: randomUUID(), xmin: '12', enabled, valueType: 'boolean', integerValue: null });
const follow = () => ({ id: randomUUID(), xmin: '13', source: 'profile', createdAt: DATE, updatedAt: DATE });
function baseline() {
  const context = { kind: 'place', id: randomUUID() };
  return { version: 1, runID: randomUUID(), targetRef: REF, accounts: PAIR, context,
    capturedAt: DATE, profiles: Object.values(PAIR).map((id) => ({ id, xmin: '10', deleted: false })),
    globalFlag: flag(), accountFlags: Object.values(PAIR).map((userID) => ({ userID, row: null })),
    follows: [{ followerID: PAIR.A, followedID: PAIR.B, row: follow() },
      { followerID: PAIR.B, followedID: PAIR.A, row: follow() }],
    blocks: [{ blockerID: PAIR.A, blockedID: PAIR.B, row: null },
      { blockerID: PAIR.B, blockedID: PAIR.A, row: null }],
    contextReceipt: { ...context, xmin: '14', ownerID: PAIR.A, placeID: context.id, visibility: 'followers',
      userPlaceID: randomUUID(), sourceXmin: '15', deleted: false, allowedA: true, allowedB: true },
    conversationCount: 0, messageCount: 0, sharedVisitCount: 0, sourceSideEffectCount: 0 };
}
const copy = (value) => JSON.parse(JSON.stringify(value));
const scope = (path, value) => ({ path, expectedRunID: value.runID, targetRef: REF, accounts: PAIR });
const goodError = (code) => ({ name: 'MutationJournalError', code });
async function fixture(t, receipt = baseline()) {
  const directory = await mkdtemp('/private/tmp/rec636-journal-test-');
  t.after(() => rm(directory, { recursive: true, force: true }));
  const path = join(directory, 'journal.json');
  const handle = await createMutationJournal({ path, targetRef: REF, accounts: PAIR, context: receipt.context, baseline: receipt });
  return { directory, path, handle, baseline: receipt };
}
async function start(handle, source, actor = 'A', conversationID = randomUUID()) {
  const intent = await handle.recordIntent({ kind: 'start', actor, recipient: actor === 'A' ? 'B' : 'A', context: source });
  await handle.recordAcknowledgment(intent.id, { conversationID });
  return { intent, conversationID };
}
async function send(handle, source, conversationID, actor = 'A', messageID = randomUUID()) {
  const intent = await handle.recordIntent({ kind: 'send', actor, conversationID, context: source });
  const ack = { conversationID, messageID, senderID: PAIR[actor], clientID: intent.clientID };
  await handle.recordAcknowledgment(intent.id, ack); return { intent, ack };
}

test('creation is exclusive, durable, private and scoped to a clean baseline', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const disk = JSON.parse(await readFile(path, 'utf8'));
  assert.deepEqual(disk, handle.snapshot());
  assert.equal(disk.runID, receipt.runID);
  assert.equal((await stat(path)).mode & 0o777, 0o600);
  assert.equal(disk.phase, 'active');
  assert.deepEqual(buildCleanupPlan(disk), { status: 'ready', runID: receipt.runID,
    conversationIDs: [], messages: [], operatorMutations: [], unresolvedIntentIDs: [] });
  await assert.rejects(createMutationJournal({ path, targetRef: REF, accounts: PAIR, context: receipt.context, baseline: receipt }), goodError('journal_busy_or_exists'));
  assert.deepEqual(JSON.parse(await readFile(path, 'utf8')), disk);
});

test('baseline rejects dirty accounts, global activation, source side effects and scope mismatch', () => {
  const clean = baseline();
  const state = { runID: clean.runID, targetRef: REF, accounts: PAIR, context: clean.context };
  for (const mutate of [
    (v) => { v.conversationCount = 1; }, (v) => { v.messageCount = 1; },
    (v) => { v.sharedVisitCount = 1; }, (v) => { v.sourceSideEffectCount = 1; },
    (v) => { v.globalFlag.enabled = true; }, (v) => { v.profiles[0].deleted = true; },
    (v) => { v.contextReceipt.allowedB = false; }, (v) => { v.accounts.B = 'foreign_account'; },
    (v) => { v.contextReceipt.ownerID = 'foreign_owner'; }, (v) => { delete v.contextReceipt.sourceXmin; },
    (v) => { v.globalFlag.valueType = 'integer'; }, (v) => { v.profiles[0].xmin = 10; },
  ]) {
    const value = copy(clean); mutate(value);
    assert.throws(() => validateJournalBaseline(value, state), { name: 'MutationJournalError' });
  }
  assert.deepEqual(validateJournalBaseline({ ...clean, context: { id: clean.context.id, kind: 'place' } }, state).context.id, clean.context.id);
});

test('intent and generated send identity are persisted before an interrupted call', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context);
  const intent = await handle.recordIntent({ kind: 'send', actor: 'A', conversationID, context: receipt.context });
  const onDisk = JSON.parse(await readFile(path, 'utf8')).intents.at(-1);
  assert.deepEqual(onDisk, intent);
  assert.match(intent.clientID, /^[0-9a-f-]{36}$/u);
  assert.equal(intent.state, 'intent');
  await handle.markInterrupted(intent.id);
  assert.equal(handle.planCleanup().status, 'blocked');
  assert.deepEqual(handle.planCleanup().unresolvedIntentIDs, [intent.id]);
  const recovered = await openMutationJournal(scope(path, receipt));
  const retry = await recovered.recordRetry(intent.id);
  assert.equal(retry.clientID, intent.clientID);
  assert.equal(retry.state, 'intent');
  assert.equal(retry.originalIntentID, intent.id);
  assert.equal(recovered.snapshot().intents.length, 3);
});

test('lost send acknowledgments reconcile only exact sender/client/conversation identities', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context);
  const intent = await handle.recordIntent({ kind: 'send', actor: 'A', conversationID, context: null });
  await handle.markInterrupted(intent.id);
  const ack = { conversationID, messageID: randomUUID(), senderID: PAIR.A, clientID: intent.clientID };
  for (const foreign of [{ ...ack, senderID: PAIR.B }, { ...ack, conversationID: randomUUID() },
    { ...ack, clientID: randomUUID() }, { ...ack, body: 'PRIVATE TEXT' }]) {
    await assert.rejects(handle.reconcile(intent.id, { status: 'found', ack: foreign }), { name: 'MutationJournalError' });
  }
  assert.equal(handle.snapshot().intents.at(-1).state, 'interrupted');
  await handle.reconcile(intent.id, { status: 'found', ack });
  const reopened = await openMutationJournal(scope(path, receipt));
  assert.equal(reopened.snapshot().intents.at(-1).state, 'reconciled');
  assert.deepEqual(reopened.planCleanup().messages, [{ id: ack.messageID, senderID: PAIR.A,
    clientID: intent.clientID, conversationID }]);
  assert.deepEqual(reopened.planCleanup().conversationIDs, [conversationID]);
  assert.equal(reopened.planCleanup().status, 'ready');
});

test('lost reciprocal starts require reconciliation and deduplicate the exact pair conversation', async (t) => {
  const { handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context, 'A');
  const reciprocal = await handle.recordIntent({ kind: 'start', actor: 'B', recipient: 'A', context: receipt.context });
  await handle.markInterrupted(reciprocal.id);
  await assert.rejects(handle.reconcile(reciprocal.id, { status: 'found', ack: { conversationID: randomUUID() } }), goodError('conversation_scope_mismatch'));
  assert.equal(handle.planCleanup().status, 'blocked');
  await handle.reconcile(reciprocal.id, { status: 'found', ack: { conversationID } });
  assert.deepEqual(handle.planCleanup().conversationIDs, [conversationID]);
});

test('confirmed absent or rolled-back denied requests add no cleanup ownership', async (t) => {
  const { handle, baseline: receipt } = await fixture(t);
  const first = await handle.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context });
  await handle.markInterrupted(first.id);
  await handle.reconcile(first.id, { status: 'absent' });
  const denied = await handle.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context });
  await handle.recordRejection(denied.id, { code: 'private_message_unavailable' });
  assert.equal(handle.planCleanup().status, 'ready');
  assert.deepEqual(handle.planCleanup().conversationIDs, []);
  await assert.rejects(handle.recordAcknowledgment(denied.id, { conversationID: randomUUID() }), goodError('acknowledgment_conflict'));
  await assert.rejects(handle.recordRejection(first.id, { code: 'PRIVATE RAW ERROR' }), goodError('invalid_rejection'));
});

test('acknowledgments are idempotent and contradictions preserve the original evidence', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context);
  const { intent, ack } = await send(handle, receipt.context, conversationID);
  await handle.recordAcknowledgment(intent.id, ack);
  await handle.markInterrupted(intent.id);
  assert.deepEqual(handle.snapshot().intents.at(-1).ack, ack);
  await assert.rejects(handle.recordAcknowledgment(intent.id, { ...ack, messageID: randomUUID() }), goodError('acknowledgment_conflict'));
  await assert.rejects(handle.reconcile(intent.id, { status: 'absent' }), goodError('acknowledgment_conflict'));
  await assert.rejects(handle.recordRejection(intent.id, { code: 'private_message_unavailable' }), goodError('acknowledgment_conflict'));
  assert.deepEqual(JSON.parse(await readFile(path, 'utf8')).intents.at(-1).ack, ack);
  assert.equal((await handle.recordRetry(intent.id)).clientID, intent.clientID);
});

test('foreign conversations, source IDs, participants and mark-read targets cannot become cleanup scope', async (t) => {
  const { handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context);
  const { ack } = await send(handle, receipt.context, conversationID);
  for (const input of [
    { kind: 'send', actor: 'A', conversationID: randomUUID(), context: null },
    { kind: 'send', actor: 'A', conversationID, context: { kind: 'place', id: randomUUID() } },
    { kind: 'start', actor: 'A', recipient: 'A', context: receipt.context },
    { kind: 'start', actor: 'C', recipient: 'A', context: receipt.context },
    { kind: 'mark_read', actor: 'B', conversationID, throughMessageID: randomUUID() },
  ]) await assert.rejects(handle.recordIntent(input), { name: 'MutationJournalError' });
  const mark = await handle.recordIntent({ kind: 'mark_read', actor: 'B', conversationID, throughMessageID: ack.messageID });
  await handle.recordAcknowledgment(mark.id, { conversationID, throughMessageID: ack.messageID });
  assert.equal(handle.planCleanup().messages.length, 1);
});

test('private content and credential-shaped fields never enter disk or diagnostics', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context);
  for (const extra of [{ body: 'PRIVATE_MESSAGE' }, { jwt: 'PRIVATE_TOKEN' },
    { apiKey: 'PRIVATE_KEY' }, { clientID: randomUUID() }, { metadata: { note: 'PRIVATE_NOTE' } }]) {
    try {
      await handle.recordIntent({ kind: 'send', actor: 'A', conversationID, context: null, ...extra });
      assert.fail('private fields accepted');
    } catch (error) {
      assert.ok(error instanceof MutationJournalError);
      assert.doesNotMatch(error.message, /PRIVATE_|jwt|apiKey/);
    }
  }
  const state = handle.snapshot(); state.baseline.contextReceipt.note = 'PRIVATE_NOTE';
  assert.throws(() => validateJournalState(state), { name: 'MutationJournalError' });
  assert.doesNotMatch(await readFile(path, 'utf8'), /PRIVATE_|body|jwt|apiKey|note/);
  const accessor = { kind: 'start', actor: 'A', recipient: 'B' };
  Object.defineProperty(accessor, 'context', { enumerable: true, get: () => assert.fail('accessor evaluated') });
  await assert.rejects(handle.recordIntent(accessor), { name: 'MutationJournalError' });
});

test('operator receipts are durable, bounded to named resources and preserve cleanup order', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const operation = await handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'account_flag', action: 'enable', actor: 'A' } });
  assert.equal(JSON.parse(await readFile(path, 'utf8')).intents.at(-1).state, 'intent');
  const after = flag(true);
  await handle.recordAcknowledgment(operation.id, { before: null, after });
  const revoke = await handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'context', action: 'revoke', actor: 'A' } });
  const changed = { ...receipt.contextReceipt, sourceXmin: '16', visibility: 'self', allowedB: false };
  await handle.recordAcknowledgment(revoke.id, { before: receipt.contextReceipt, after: changed });
  assert.deepEqual(handle.planCleanup().operatorMutations, [
    { intentID: operation.id, transition: operation.transition, before: null, after },
    { intentID: revoke.id, transition: revoke.transition, before: receipt.contextReceipt, after: changed },
  ]);
  for (const resource of ['profiles', 'account', 'global_flag', 'private_messages']) {
    await assert.rejects(handle.recordIntent({ kind: 'operator_transition', actor: 'A',
      transition: { resource, action: 'remove', actor: 'A' } }), goodError('unsupported_transition'));
  }
  await assert.rejects(handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'block', action: 'insert', actor: 'A', targetActor: 'A' } }), { name: 'MutationJournalError' });
  const foreign = copy(after); foreign.valueType = 'integer';
  await assert.rejects(handle.recordAcknowledgment(operation.id, { before: null, after: foreign }), { name: 'MutationJournalError' });
});

test('cleanup remains blocked through unknown writes and completion requires zero rows, baseline restoration and global Off', async (t) => {
  const { handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context);
  const pending = await handle.recordIntent({ kind: 'send', actor: 'A', conversationID, context: null });
  const completion = { runID: receipt.runID, conversationCount: 0, messageCount: 0, baselineRestored: true, globalLiveEnabled: false };
  await assert.rejects(handle.markCleanupVerified(completion), goodError('reconciliation_required'));
  await handle.reconcile(pending.id, { status: 'absent' });
  await assert.rejects(handle.markCleanupVerified(completion), goodError('cleanup_not_prepared'));
  await handle.beginCleanup();
  for (const invalid of [{ ...completion, messageCount: 1 }, { ...completion, conversationCount: 1 },
    { ...completion, baselineRestored: false }, { ...completion, globalLiveEnabled: true },
    { ...completion, runID: randomUUID() }]) await assert.rejects(handle.markCleanupVerified(invalid), goodError('cleanup_not_verified'));
  await handle.markCleanupVerified(completion);
  const revision = handle.snapshot().revision;
  await handle.markCleanupVerified(completion);
  assert.equal(handle.snapshot().revision, revision);
  assert.equal(handle.planCleanup().status, 'already_cleaned');
  assert.equal(handle.planCleanup().status, 'already_cleaned');
  await assert.rejects(handle.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context }), goodError('journal_already_cleaned'));
  await assert.rejects(handle.recordRetry(pending.id), goodError('journal_already_cleaned'));
});

test('reopening refuses a wrong run, project or account pair', async (t) => {
  const { path, baseline: receipt } = await fixture(t);
  for (const extra of [{ expectedRunID: randomUUID() }, { targetRef: 'b'.repeat(20) },
    { accounts: { A: PAIR.A, B: 'foreign_account' } }]) {
    await assert.rejects(openMutationJournal({ ...scope(path, receipt), ...extra }), goodError('journal_scope_mismatch'));
  }
});

test('symlinks, hard links, shared permissions and stale locks fail closed without overwriting', async (t) => {
  const { directory, path, handle, baseline: receipt } = await fixture(t);
  const alias = join(directory, 'alias.json'); await symlink(path, alias);
  await assert.rejects(openMutationJournal(scope(alias, receipt)), goodError('journal_io_failed'));
  const linked = join(directory, 'hard-link.json'); await link(path, linked);
  await assert.rejects(openMutationJournal(scope(path, receipt)), goodError('unsafe_journal_file'));
  await rm(linked); await chmod(path, 0o644);
  await assert.rejects(openMutationJournal(scope(path, receipt)), goodError('unsafe_journal_file'));
  await chmod(path, 0o600); await writeFile(`${path}.lock`, 'fictional interrupted lock', { mode: 0o600 });
  const before = await readFile(path, 'utf8');
  await assert.rejects(handle.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context }), goodError('journal_busy_or_exists'));
  assert.equal(await readFile(path, 'utf8'), before);
  assert.equal(await readFile(`${path}.lock`, 'utf8'), 'fictional interrupted lock');
});

test('multiple handles serialize against the latest persisted revision without lost intents', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const second = await openMutationJournal(scope(path, receipt));
  const one = await handle.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context });
  const two = await second.recordIntent({ kind: 'start', actor: 'B', recipient: 'A', context: receipt.context });
  const reopened = await openMutationJournal(scope(path, receipt));
  assert.deepEqual(reopened.snapshot().intents.map(({ id }) => id), [one.id, two.id]);
  assert.equal(reopened.snapshot().revision, 2);
  assert.equal(reopened.planCleanup().unresolvedIntentIDs.length, 2);
});

test('invalid persisted input and size/count bounds return sanitized errors', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const state = handle.snapshot();
  state.intents = Array.from({ length: 129 }, () => ({ id: randomUUID(), kind: 'start', actor: 'A',
    recipient: 'B', context: receipt.context, state: 'intent' }));
  assert.throws(() => validateJournalState(state), { name: 'MutationJournalError' });
  await writeFile(path, 'PRIVATE_INPUT is not JSON', { mode: 0o600 });
  try { await openMutationJournal(scope(path, receipt)); assert.fail('invalid journal accepted'); }
  catch (error) { assert.equal(error.code, 'invalid_journal'); assert.doesNotMatch(error.message, /PRIVATE_INPUT|journal.json/); }
  await writeFile(path, 'x'.repeat(256 * 1024 + 1), { mode: 0o600 });
  await assert.rejects(openMutationJournal(scope(path, receipt)), goodError('journal_too_large'));
});


test('cleanup freeze reloads the latest disk state, refuses unresolved writers and prevents new intents', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const second = await openMutationJournal(scope(path, receipt));
  const pending = await second.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context });
  assert.equal(handle.planCleanup().status, 'ready', 'cached diagnostic view is deliberately not cleanup authority');
  await assert.rejects(handle.beginCleanup(), goodError('reconciliation_required'));
  await second.reconcile(pending.id, { status: 'absent' });
  await handle.beginCleanup();
  assert.equal(JSON.parse(await readFile(path, 'utf8')).phase, 'cleanup_planned');
  await assert.rejects(second.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context }), goodError('journal_frozen_for_cleanup'));
  const reopened = await openMutationJournal(scope(path, receipt));
  assert.equal((await reopened.beginCleanup()).status, 'ready');
  assert.equal(reopened.snapshot().phase, 'cleanup_planned');
});

test('a writable parent directory cannot receive a journal', async (t) => {
  const { directory, path, baseline: receipt } = await fixture(t);
  await chmod(directory, 0o777);
  await assert.rejects(openMutationJournal(scope(path, receipt)), goodError('invalid_journal_path'));
  await chmod(directory, 0o700);
});


test('retry reservations use current disk state, block cleanup while in flight and retain one owned row', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context);
  const { intent, ack } = await send(handle, receipt.context, conversationID);
  const stale = await openMutationJournal(scope(path, receipt));
  const retry = await stale.recordRetry(intent.id);
  assert.equal(retry.clientID, intent.clientID);
  assert.equal(retry.originalIntentID, intent.id);
  await assert.rejects(handle.beginCleanup(), goodError('reconciliation_required'));
  await stale.recordAcknowledgment(retry.id, ack);
  await handle.beginCleanup();
  await assert.rejects(stale.recordRetry(intent.id), goodError('journal_frozen_for_cleanup'));
  assert.equal(handle.planCleanup().messages.length, 1);
});

test('a retry acknowledgment resolves an interrupted original send and rejects contradictory history', async (t) => {
  const { handle, baseline: receipt } = await fixture(t);
  const { conversationID } = await start(handle, receipt.context);
  const original = await handle.recordIntent({ kind: 'send', actor: 'A', conversationID, context: null });
  await handle.markInterrupted(original.id);
  const retry = await handle.recordRetry(original.id);
  const ack = { conversationID, messageID: randomUUID(), senderID: PAIR.A, clientID: original.clientID };
  await handle.recordAcknowledgment(retry.id, ack);
  assert.equal(handle.snapshot().intents.find(({ id }) => id === original.id).state, 'reconciled');
  assert.deepEqual(handle.planCleanup().messages.map(({ id }) => id), [ack.messageID]);
  assert.equal(handle.planCleanup().status, 'ready');
  const conflicting = await handle.recordRetry(original.id);
  await assert.rejects(handle.recordAcknowledgment(conflicting.id, { ...ack, messageID: randomUUID() }), goodError('acknowledgment_conflict'));
  assert.equal(handle.planCleanup().status, 'blocked');
});

test('absent and rejected starts cannot grant conversation ownership or retry authority', async (t) => {
  const { handle, baseline: receipt } = await fixture(t);
  const absent = await handle.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context });
  await handle.reconcile(absent.id, { status: 'absent' });
  await assert.rejects(handle.recordIntent({ kind: 'send', actor: 'A', conversationID: randomUUID(), context: null }), goodError('conversation_not_owned'));
  await assert.rejects(handle.recordRetry(absent.id), goodError('retry_not_allowed'));
  const denied = await handle.recordIntent({ kind: 'start', actor: 'A', recipient: 'B', context: receipt.context });
  await handle.recordRejection(denied.id, { code: 'private_message_unavailable' });
  await assert.rejects(handle.reconcile(denied.id, { status: 'found', ack: { conversationID: randomUUID() } }), goodError('acknowledgment_conflict'));
  await assert.rejects(handle.recordIntent({ kind: 'send', actor: 'A', conversationID: randomUUID(), context: null }), goodError('conversation_not_owned'));
});

test('only successfully secured create/open handles have the module-private brand', async (t) => {
  const { path, handle, baseline: receipt } = await fixture(t);
  assert.equal(isMutationJournalHandle(handle), true);
  assert.equal(isMutationJournalHandle(await openMutationJournal(scope(path, receipt))), true);
  assert.equal(isMutationJournalHandle({ ...handle }), false);
  assert.equal(isMutationJournalHandle({ snapshot: handle.snapshot, recordIntent: handle.recordIntent }), false);
  assert.equal(isMutationJournalHandle(null), false);
});


test('operator acknowledgments must form an exact before/after receipt chain', async (t) => {
  const { handle } = await fixture(t);
  const enable = await handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'account_flag', action: 'enable', actor: 'A' } });
  const enabled = flag(true);
  await assert.rejects(handle.recordAcknowledgment(enable.id, { before: flag(), after: enabled }), goodError('operator_receipt_chain_mismatch'));
  await handle.recordAcknowledgment(enable.id, { before: null, after: enabled });
  const revoke = await handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'account_flag', action: 'revoke', actor: 'A' } });
  await assert.rejects(handle.recordAcknowledgment(revoke.id, { before: enabled, after: { ...flag(), enabled: false } }), goodError('operator_row_identity_mismatch'));
  const disabled = { ...enabled, enabled: false, xmin: '16' };
  await handle.recordAcknowledgment(revoke.id, { before: enabled, after: disabled });
  const restore = await handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'account_flag', action: 'restore', actor: 'A' } });
  await assert.rejects(handle.recordAcknowledgment(restore.id, { before: disabled, after: { ...disabled, enabled: true } }), goodError('operator_restoration_mismatch'));
  await handle.recordAcknowledgment(restore.id, { before: disabled, after: null });
  assert.equal(handle.planCleanup().operatorMutations.length, 3);
});

test('an unresolved operator resource cannot be overwritten by a later trial', async (t) => {
  const { handle } = await fixture(t);
  const enable = await handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'account_flag', action: 'enable', actor: 'A' } });
  await handle.markInterrupted(enable.id);
  await assert.rejects(handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'account_flag', action: 'revoke', actor: 'A' } }), goodError('operator_reconciliation_required'));
  assert.equal(handle.planCleanup().status, 'blocked');
});


test('follow restoration permits its observed trigger timestamp but preserves identity, source and creation time', async (t) => {
  const { handle, baseline: receipt } = await fixture(t);
  const before = receipt.follows[0].row;
  const remove = await handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'follow', action: 'remove', actor: 'A', targetActor: 'B' } });
  await handle.recordAcknowledgment(remove.id, { before, after: null });
  const restore = await handle.recordIntent({ kind: 'operator_transition', actor: 'A',
    transition: { resource: 'follow', action: 'restore', actor: 'A', targetActor: 'B' } });
  const after = { ...before, xmin: '31', updatedAt: '2030-01-01T01:00:00.000Z' };
  for (const foreign of [{ ...after, id: randomUUID() }, { ...after, source: 'contacts' },
    { ...after, createdAt: after.updatedAt }]) {
    await assert.rejects(handle.recordAcknowledgment(restore.id, { before: null, after: foreign }), goodError('operator_restoration_mismatch'));
  }
  await handle.recordAcknowledgment(restore.id, { before: null, after });
  assert.deepEqual(handle.planCleanup().operatorMutations.at(-1).after, after);
});
