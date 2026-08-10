import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  buildReleaseArtifacts,
  parseCommitRecord,
  reconcileManifest,
  sortTestFlightTags,
} from "./reconcile-testflight-manifest.mjs";

const fixture = JSON.parse(
  readFileSync(new URL("./fixtures/testflight-manifest-history.json", import.meta.url), "utf8"),
);

function ship(commit, pr, issue, change) {
  return {
    commit,
    pr,
    issue,
    disposition: "ship",
    testerFacingChange: change,
    whatToTest: [`Test ${change.toLowerCase()}`],
    releaseOperations: "none",
    validation: "Focused tests passed.",
  };
}

function reportFor(history, entries) {
  return reconcileManifest({
    commits: history.commits.map(parseCommitRecord),
    manifest: {
      schemaVersion: 1,
      baselineTag: history.baselineTag,
      baselineSha: history.baselineSha,
      candidateSha: history.candidateSha,
      entries,
    },
    baseRef: history.baselineTag,
    resolvedBaseSha: history.baselineSha,
    resolvedHeadSha: history.candidateSha,
  });
}

test("build 122 fixture reconciles every commit and keeps c555 in tester copy", () => {
  const history = fixture.build122;
  const report = reportFor(history, [
    ship(history.commits[0].slice(0, 40), 327, "REC-225", "Map and Feed share trusted-place search."),
    {
      commit: history.commits[1].slice(0, 40),
      pr: 325,
      issue: null,
      disposition: "exclude",
      reason: "Docs/process-only design approval.",
    },
    ship(history.commits[2].slice(0, 40), 329, "REC-229", "Tab icons react on touch down."),
    ship(history.commits[3].slice(0, 40), 323, "REC-224", "Contact invites are available from contextual entry points."),
    {
      commit: history.commits[4].slice(0, 40),
      pr: 331,
      issue: null,
      disposition: "release-operation",
      reason: "Build-number metadata only.",
      releaseOperations: "Build number 122.",
    },
  ]);

  assert.equal(report.ok, true, report.errors.join("\n"));
  assert.equal(report.shipped.length, 3);
  assert.equal(report.excluded.length, 1);
  assert.equal(report.releaseOperations.length, 1);

  const artifacts = buildReleaseArtifacts({ report, buildNumber: 122, status: "live" });
  assert.match(artifacts.slack, /Map and Feed share trusted-place search/);
  assert.match(artifacts.slack, /#testflight-feedback/);
  assert.doesNotMatch(artifacts.slack, /Docs\/process-only/);
});

test("missing c555 fails closed instead of silently dropping search", () => {
  const history = fixture.build122;
  const report = reportFor(history, [
    {
      commit: history.commits[1].slice(0, 40),
      pr: 325,
      issue: null,
      disposition: "exclude",
      reason: "Docs/process-only design approval.",
    },
    ship(history.commits[2].slice(0, 40), 329, "REC-229", "Tab icons react on touch down."),
    ship(history.commits[3].slice(0, 40), 323, "REC-224", "Contact invites are available."),
    {
      commit: history.commits[4].slice(0, 40),
      pr: 331,
      issue: null,
      disposition: "release-operation",
      reason: "Build-number metadata only.",
    },
  ]);

  assert.equal(report.ok, false);
  assert.ok(report.errors.some((error) => error.includes("c555a2d57c") && error.includes("#327")));
});

test("build 124 fixture catches a post-bump navigation fix missing from the manifest", () => {
  const history = fixture.build124;
  const report = reportFor(history, [
    ship(history.commits[0].slice(0, 40), 328, "REC-228", "Imports use adaptive review."),
    ship(history.commits[1].slice(0, 40), 330, "REC-227", "Social capture is rebuilt."),
    {
      commit: history.commits[2].slice(0, 40),
      pr: 335,
      issue: null,
      disposition: "release-operation",
      reason: "Build-number metadata only.",
    },
  ]);

  assert.equal(report.ok, false);
  assert.ok(report.errors.some((error) => error.includes("27427a3095") && error.includes("#336")));
});

test("a prior-build commit is rejected as stale in a later delta", () => {
  const history = fixture.build124;
  const report = reportFor(history, [
    ship(fixture.build122.commits[0].slice(0, 40), 327, "REC-225", "Trusted search."),
  ]);

  assert.equal(report.ok, false);
  assert.ok(report.errors.some((error) => error.includes("outside the release range")));
});

test("manifest metadata must match the exact baseline and candidate", () => {
  const history = fixture.build124;
  const report = reconcileManifest({
    commits: history.commits.map(parseCommitRecord),
    manifest: {
      schemaVersion: 1,
      baselineTag: "testflight/build-122",
      baselineSha: history.baselineSha,
      candidateSha: fixture.build122.candidateSha,
      entries: [],
    },
    baseRef: history.baselineTag,
    resolvedBaseSha: history.baselineSha,
    resolvedHeadSha: history.candidateSha,
  });

  assert.equal(report.ok, false);
  assert.ok(report.errors.some((error) => error.includes("baselineTag")));
  assert.ok(report.errors.some((error) => error.includes("candidateSha")));
});

test("TestFlight tags sort by numeric build for cumulative ancestry audits", () => {
  assert.deepEqual(
    sortTestFlightTags(["testflight/build-124", "testflight/build-99", "testflight/build-122"]),
    ["testflight/build-99", "testflight/build-122", "testflight/build-124"],
  );
});

test("an explicitly recorded direct push can carry a shipped payload", () => {
  const sha = "d".repeat(40);
  const report = reconcileManifest({
    commits: [{ sha, subject: "REC-500: emergency direct fix", pr: null, issue: "REC-500" }],
    manifest: {
      schemaVersion: 1,
      baselineTag: "testflight/build-1",
      baselineSha: "b".repeat(40),
      candidateSha: sha,
      entries: [ship(sha, null, "REC-500", "Emergency direct fix ships safely.")],
    },
    baseRef: "testflight/build-1",
    resolvedBaseSha: "b".repeat(40),
    resolvedHeadSha: sha,
  });
  assert.equal(report.ok, true, report.errors.join("\n"));
});
