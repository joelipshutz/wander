// Programmatic assembly only. The caller supplies the reviewed operator
// capability and signed-in inputs; this module discovers no credentials and
// never provisions fixtures, retries a session, or proves transport quiescence.
import { lstat } from "node:fs/promises";
import { dirname, isAbsolute, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { validateInput } from "./rec636-real-client-verification.mjs";
import { createCleanupCompanion } from "./rec636-cleanup-companion.mjs";
import { createMutationJournal } from "./rec636-mutation-journal.mjs";
import { requestAuthenticatedRPC, verifyRealClients } from "./rec636-real-client-write-runner.mjs";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/u;
const plain = (value) => value !== null && typeof value === "object" && !Array.isArray(value)
  && [Object.prototype, null].includes(Object.getPrototypeOf(value))
  && Object.getOwnPropertySymbols(value).length === 0
  && Object.values(Object.getOwnPropertyDescriptors(value)).every((entry) => Object.hasOwn(entry, "value"));
const shape = (value, required, optional = []) => plain(value)
  && required.every((key) => Object.hasOwn(value, key))
  && Object.keys(value).every((key) => required.includes(key) || optional.includes(key));
const blocked = (code, stage, journal) => ({ status: "blocked", writesEnabled: false,
  step4Complete: false, backendDeliveryVerified: false, cleanupVerified: false,
  code, sessionStage: stage, journalCreated: Boolean(journal),
  journalPhase: journal ? journal.snapshot().phase : null });

function explicitScope(input, options) {
  if (!shape(options, ["expectedProjectRef", "designation", "journalPath", "executeSQL"], ["transport", "now"])
    || typeof options.executeSQL !== "function"
    || (options.transport !== undefined && typeof options.transport !== "function")
    || (options.now !== undefined && typeof options.now !== "function")
    || !shape(input, ["target", "accounts"])
    || !shape(input.target, ["projectRef", "url", "publishableKey"])
    || !Array.isArray(input.accounts) || input.accounts.length !== 2
    || input.accounts.some((account) => !shape(account, ["label", "accountID", "jwt"]))) throw new Error();
  const designation = options.designation;
  if (!shape(designation, ["internalAccountsApproved", "targetRef", "accounts", "runID", "context"])
    || designation.internalAccountsApproved !== true
    || designation.targetRef !== options.expectedProjectRef
    || !shape(designation.accounts, ["A", "B"])
    || !UUID.test(designation.runID ?? "")
    || !shape(designation.context, ["kind", "id"])
    || !["place", "activity"].includes(designation.context.kind)
    || !UUID.test(designation.context.id ?? "")) throw new Error();
  // Snapshot the explicit strings before the first await; caller mutation must
  // not change the approved target or identities while the operator runs.
  const snapshot = structuredClone(input);
  const approved = structuredClone(designation);
  const now = options.now ?? Date.now;
  const validated = validateInput(snapshot, options.expectedProjectRef, now());
  if (validated.accounts.some((account) => approved.accounts[account.label] !== account.accountID)) throw new Error();
  return { input: snapshot, designation: approved, now,
    expectedProjectRef: options.expectedProjectRef,
    executeSQL: options.executeSQL, transport: options.transport ?? requestAuthenticatedRPC,
    journalPath: options.journalPath,
    spec: { runID: approved.runID, targetRef: approved.targetRef, accounts: approved.accounts, context: approved.context } };
}

async function availableJournalPath(path) {
  if (typeof path !== "string" || !isAbsolute(path) || path.length > 4096 || path.includes("\0")) throw new Error();
  const parent = await lstat(dirname(path));
  if (!parent.isDirectory() || parent.isSymbolicLink() || (parent.mode & 0o077) !== 0
    || (process.getuid && parent.uid !== process.getuid())) throw new Error();
  for (const candidate of [path, `${path}.lock`]) {
    try { await lstat(candidate); }
    catch (error) { if (error?.code === "ENOENT") continue; throw new Error(); }
    throw new Error();
  }
}

/**
 * executeSQL is an explicitly reviewed, project-bound operator capability.
 * Its result contract is exactly [{rec636_result: ...}]. No serialized approval
 * substitutes for the companion's fresh baseline and rollback verification.
 * Unknown execution outcomes are retained by the existing durable journal;
 * callers must not retry this entry point or infer permission to clean them up.
 */
export async function runRealClientSession(input, options) {
  let scope;
  try { scope = explicitScope(input, options); }
  catch { return blocked("invalid_session_input", "input"); }
  try { await availableJournalPath(scope.journalPath); }
  catch { return blocked("journal_path_unavailable", "input"); }
  const executeSQL = async (sql, metadata) => {
    if (!shape(metadata, ["purpose", "runID", "targetRef"])
      || metadata.runID !== scope.spec.runID || metadata.targetRef !== scope.spec.targetRef
      || !["baseline", "verification", "transition", "reconcile", "cleanup"].includes(metadata.purpose)) throw new Error();
    const rows = await scope.executeSQL(sql, metadata);
    if (!Array.isArray(rows) || rows.length !== 1 || !shape(rows[0], ["rec636_result"])) throw new Error();
    return rows;
  };
  let companion;
  try { companion = await createCleanupCompanion({ executeSQL, spec: scope.spec }); }
  catch { return blocked("operator_setup_failed", "operator"); }
  let journal;
  try { journal = await createMutationJournal({ path: scope.journalPath,
    targetRef: scope.spec.targetRef, accounts: scope.spec.accounts,
    context: scope.spec.context, baseline: companion.baseline() }); }
  catch { return blocked("journal_creation_failed", "journal"); }
  // The existing runner exclusively owns permits, mutations, reconciliation
  // and cleanup. In particular, do not add a finally-cleanup or retry here.
  const result = await verifyRealClients(scope.input, { expectedProjectRef: scope.expectedProjectRef,
    designation: scope.designation, journal, companion, transport: scope.transport, now: scope.now });
  return { ...result, step4Complete: false, sessionStage: "verification",
    journalCreated: true, journalPhase: journal.snapshot().phase };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.stdout.write(`${JSON.stringify(blocked("programmatic_invocation_required", "input"))}\n`);
  process.exitCode = 2;
}
