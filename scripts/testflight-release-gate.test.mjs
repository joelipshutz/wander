import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";

import { entriesSha256 } from "./testflight-manifest.mjs";
import { validateReconciliationGate } from "./testflight-release.mjs";

const candidateSha = "a".repeat(40);
const payloadSha = "b".repeat(40);
const whatToTest = "What changed\n- Complete release coverage.\n\nWhat to test\n- Verify it.";

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function passingGate(overrides = {}) {
  const gate = {
    gateVersion: 2,
    ok: true,
    errors: [],
    buildNumber: 126,
    baseRef: "testflight/build-125",
    baselineSha: "c".repeat(40),
    candidateSha,
    commits: [{ sha: payloadSha, subject: "REC-250: example (#340)" }],
    entries: [{
      commit: payloadSha,
      pr: 340,
      issue: "REC-250",
      disposition: "ship",
      testerFacingChange: "Complete release coverage.",
      whatToTest: ["Verify it."],
      releaseOperations: "none",
      validation: "Tests passed.",
    }],
    shipped: [{ commit: payloadSha, pr: 340, issue: "REC-250" }],
    excluded: [],
    releaseOperations: [],
    whatToTestSha256: sha256(whatToTest),
    manifestSource: {
      kind: "github-issue",
      repository: "joelipshutz/wander",
      issueNumber: 42,
      issueUrl: "https://github.com/joelipshutz/wander/issues/42",
      baselineTag: "testflight/build-125",
      baselineSha: "c".repeat(40),
      candidateSha,
      entriesSha256: null,
    },
  };
  Object.assign(gate, overrides);
  if (!overrides.manifestSource) {
    gate.manifestSource.entriesSha256 = entriesSha256(gate.entries);
  }
  return gate;
}

function validate(gate = passingGate(), overrides = {}) {
  return validateReconciliationGate({
    gate,
    buildNumber: 126,
    candidateSha,
    whatToTest,
    ...overrides,
  });
}

test("accepts a passing gate for the exact build, candidate, and tester copy", () => {
  assert.equal(validate().ok, true);
});

test("rejects a reconciliation generated for another build", () => {
  assert.throws(
    () => validate(passingGate({ buildNumber: 125 })),
    /does not match requested build 126/,
  );
});

test("rejects a reconciliation generated for another candidate", () => {
  assert.throws(
    () => validate(passingGate({ candidateSha: "d".repeat(40) })),
    /does not match current HEAD/,
  );
});

test("rejects tester copy that was edited outside the manifest generator", () => {
  assert.throws(
    () => validate(passingGate(), { whatToTest: `${whatToTest}\n- Hand-added item.` }),
    /does not match the reconciled manifest output/,
  );
});

test("rejects incomplete commit classifications", () => {
  assert.throws(
    () => validate(passingGate({ entries: [] })),
    /does not classify every release-range commit/,
  );
});

test("rejects an unrecognized disposition even when the commit is present", () => {
  const gate = passingGate();
  gate.entries[0].disposition = "maybe";
  assert.throws(
    () => validate(gate),
    /invalid commit disposition/,
  );
});

test("rejects legacy reconciliation that did not come from the machine manifest", () => {
  assert.throws(
    () => validate(passingGate({ gateVersion: 1 })),
    /gateVersion must be 2/,
  );
});

test("rejects classifications edited after the machine manifest snapshot", () => {
  const gate = passingGate();
  gate.entries[0].validation = "Hand-edited after snapshot.";
  assert.throws(
    () => validate(gate),
    /source hash does not match/,
  );
});
