import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  ENTRY_MARKER,
  PR_PAYLOAD_MARKER,
  buildManifestEntry,
  createReleaseSnapshot,
  entriesSha256,
  finalizeManifest,
  parseEntryComment,
  parsePullRequestPayload,
  recordManifestEntry,
  renderEntryComment,
  renderIssueBody,
  syncManifestRange,
  validatePayloadAgainstChangedFiles,
  verifyManifestSourceCurrent,
} from "./testflight-manifest.mjs";
import { sha256 } from "./reconcile-testflight-manifest.mjs";

function markedPayload(payload) {
  return `Summary\n\n<!-- ${PR_PAYLOAD_MARKER}\n${JSON.stringify(payload, null, 2)}\n-->`;
}

const shipPayload = {
  disposition: "ship",
  issue: "REC-500",
  testerFacingChange: "Imports show their resolved places before saving.",
  whatToTest: ["Import an Instagram post and review the matched place."],
  releaseOperations: "none",
  validation: "Focused manifest tests passed.",
};

function git(cwd, args) {
  return execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
}

function makeRepository() {
  const cwd = mkdtempSync(join(tmpdir(), "recme-manifest-test-"));
  git(cwd, ["init", "-b", "main"]);
  git(cwd, ["config", "user.name", "Manifest Test"]);
  git(cwd, ["config", "user.email", "manifest@example.com"]);
  writeFileSync(join(cwd, "README.md"), "base\n");
  writeFileSync(join(cwd, "project.yml"), "settings:\n  base:\n    MARKETING_VERSION: \"1.0\"\n");
  git(cwd, ["add", "README.md", "project.yml"]);
  git(cwd, ["commit", "-m", "base"]);
  git(cwd, ["tag", "testflight/build-1"]);
  mkdirSync(join(cwd, "feature"));
  writeFileSync(join(cwd, "feature", "change.txt"), "change\n");
  git(cwd, ["add", "feature/change.txt"]);
  git(cwd, ["commit", "-m", "REC-500: add import review (#12)"]);
  return {
    cwd,
    baselineSha: git(cwd, ["rev-parse", "testflight/build-1"]),
    candidateSha: git(cwd, ["rev-parse", "HEAD"]),
  };
}

function fakeGitHub({ baselineSha, pullBody = markedPayload(shipPayload) }) {
  const state = {
    issue: {
      number: 77,
      title: "[machine] Next TestFlight manifest",
      state: "open",
      html_url: "https://github.com/joelipshutz/wander/issues/77",
      body: renderIssueBody({
        state: {
          schemaVersion: 1,
          baselineTag: "testflight/build-1",
          baselineSha,
        },
        pendingEntries: [],
        repository: "joelipshutz/wander",
      }),
    },
    comments: [],
    nextCommentId: 1,
  };

  const client = {
    repository: "joelipshutz/wander",
    async paginate(path) {
      if (path.startsWith("/issues?")) return [state.issue];
      if (path.startsWith("/issues/77/comments")) return state.comments;
      throw new Error(`Unexpected paginate ${path}`);
    },
    async request(method, path, body) {
      if (method === "GET" && path === "/pulls/12") {
        return { number: 12, body: pullBody, merged_at: "2026-08-10T00:00:00Z", base: { ref: "main" } };
      }
      if (method === "POST" && path === "/issues/77/comments") {
        const comment = {
          id: state.nextCommentId++,
          body: body.body,
          html_url: `https://github.com/joelipshutz/wander/issues/77#issuecomment-${state.nextCommentId}`,
        };
        state.comments.push(comment);
        return comment;
      }
      if (method === "PATCH" && path.startsWith("/issues/comments/")) {
        const id = Number(path.split("/").at(-1));
        const comment = state.comments.find((item) => item.id === id);
        comment.body = body.body;
        return comment;
      }
      if (method === "PATCH" && path === "/issues/77") {
        state.issue.body = body.body;
        return state.issue;
      }
      if (method === "GET" && path === "/issues/77") return state.issue;
      throw new Error(`Unexpected request ${method} ${path}`);
    },
  };
  return { client, state };
}

test("parses and normalizes the required PR payload", () => {
  const payload = parsePullRequestPayload(markedPayload({
    ...shipPayload,
    testerFacingChange: `  ${shipPayload.testerFacingChange}  `,
  }));
  assert.equal(payload.disposition, "ship");
  assert.equal(payload.testerFacingChange, shipPayload.testerFacingChange);
});

test("rejects a PR with no machine-readable release classification", () => {
  assert.throws(
    () => parsePullRequestPayload("Normal PR prose only."),
    new RegExp(`Missing <!-- ${PR_PAYLOAD_MARKER}`),
  );
});

test("rejects an untouched PR template placeholder", () => {
  assert.throws(
    () => parsePullRequestPayload(markedPayload({ disposition: "replace-me" })),
    /disposition must be ship, exclude, or release-operation/,
  );
});

test("rejects malformed test actions instead of silently dropping them", () => {
  assert.throws(
    () => parsePullRequestPayload(markedPayload({
      ...shipPayload,
      whatToTest: ["Valid action", 42],
    })),
    /every whatToTest action must be a non-empty string/,
  );
});

test("app/runtime changes cannot be hidden behind an exclude classification", () => {
  const errors = validatePayloadAgainstChangedFiles(
    { disposition: "exclude" },
    ["Wander/Features/Map/MapScreen.swift", "docs/decisions.md"],
  );
  assert.match(errors[0], /require disposition ship/);
});

test("build-number metadata accepts a release-operation classification", () => {
  assert.deepEqual(
    validatePayloadAgainstChangedFiles(
      { disposition: "release-operation" },
      ["project.yml", "Wander.xcodeproj/project.pbxproj"],
    ),
    [],
  );
});

test("entry comments round-trip exact machine JSON", () => {
  const entry = buildManifestEntry({
    commit: "a".repeat(40),
    pr: 12,
    payload: shipPayload,
  });
  const rendered = renderEntryComment(entry);
  assert.match(rendered, new RegExp(ENTRY_MARKER));
  assert.deepEqual(parseEntryComment(rendered), entry);
});

test("entry hashing is deterministic regardless of comment order", () => {
  const first = buildManifestEntry({ commit: "a".repeat(40), pr: 12, payload: shipPayload });
  const second = {
    commit: "b".repeat(40),
    pr: 13,
    disposition: "exclude",
    reason: "Process only.",
  };
  assert.equal(entriesSha256([first, second]), entriesSha256([second, first]));
});

test("snapshot syncs the same issue and emits a version-2 release gate", async () => {
  const repository = makeRepository();
  const output = mkdtempSync(join(tmpdir(), "recme-manifest-output-"));
  const { client, state } = fakeGitHub(repository);
  try {
    const result = await createReleaseSnapshot({
      client,
      cwd: repository.cwd,
      baseRef: "testflight/build-1",
      headRef: repository.candidateSha,
      buildNumber: 2,
      status: "candidate",
      writeDirectory: output,
    });
    const gate = JSON.parse(readFileSync(result.files.reconciliation, "utf8"));
    assert.equal(gate.gateVersion, 2);
    assert.equal(gate.manifestSource.issueNumber, 77);
    assert.equal(gate.manifestSource.entriesSha256, entriesSha256(gate.entries));
    assert.equal(gate.entries[0].commit, repository.candidateSha);
    assert.match(
      readFileSync(result.files.slack, "utf8"),
      /^rec\.me 1\.0 \(2\) is the locked release candidate\./,
    );
    assert.equal(parseEntryComment(state.comments[0].body).disposition, "ship");
  } finally {
    rmSync(repository.cwd, { recursive: true, force: true });
    rmSync(output, { recursive: true, force: true });
  }
});

test("snapshot hashes approved compact tester copy while retaining every manifest entry", async () => {
  const repository = makeRepository();
  const output = mkdtempSync(join(tmpdir(), "recme-manifest-approved-copy-"));
  const { client } = fakeGitHub(repository);
  const approvedTesterCopy = [
    "What changed",
    "- Imports are easier to review.",
    "",
    "What to test",
    "- Import a post and review it.",
    "",
    "Known limitations",
    "- No new known limitations.",
  ].join("\n");
  try {
    const result = await createReleaseSnapshot({
      client,
      cwd: repository.cwd,
      baseRef: "testflight/build-1",
      headRef: repository.candidateSha,
      buildNumber: 2,
      status: "candidate",
      writeDirectory: output,
      approvedTesterCopy,
    });
    const gate = JSON.parse(readFileSync(result.files.reconciliation, "utf8"));
    assert.equal(readFileSync(result.files.whatToTest, "utf8").trim(), approvedTesterCopy);
    assert.equal(gate.entries.length, 1);
    assert.equal(gate.whatToTestSha256, sha256(approvedTesterCopy));
  } finally {
    rmSync(repository.cwd, { recursive: true, force: true });
    rmSync(output, { recursive: true, force: true });
  }
});

test("main sync records an invalid PR as a visible release blocker", async () => {
  const repository = makeRepository();
  const { client, state } = fakeGitHub({ ...repository, pullBody: "No payload." });
  try {
    const result = await syncManifestRange({
      client,
      cwd: repository.cwd,
      headRef: repository.candidateSha,
    });
    assert.equal(result.pendingEntries[0].disposition, "unclassified");
    assert.match(result.pendingEntries[0].reason, /release payload is missing or invalid/);
    assert.match(state.issue.body, /🔴 unclassified/);
  } finally {
    rmSync(repository.cwd, { recursive: true, force: true });
  }
});

test("an explicit record command can classify a direct main push", async () => {
  const repository = makeRepository();
  git(repository.cwd, ["commit", "--amend", "-m", "REC-500: emergency direct fix"]);
  repository.candidateSha = git(repository.cwd, ["rev-parse", "HEAD"]);
  const { client } = fakeGitHub(repository);
  try {
    const result = await recordManifestEntry({
      client,
      cwd: repository.cwd,
      commitRef: repository.candidateSha,
      payload: shipPayload,
      headRef: repository.candidateSha,
    });
    assert.equal(result.entry.commit, repository.candidateSha);
    assert.equal(result.entry.pr, null);
    assert.equal(result.entry.disposition, "ship");
  } finally {
    rmSync(repository.cwd, { recursive: true, force: true });
  }
});

test("main sync preserves and deliberately replaces an explicit direct-push classification", async () => {
  const repository = makeRepository();
  git(repository.cwd, ["commit", "--amend", "-m", "REC-500: emergency direct fix"]);
  repository.candidateSha = git(repository.cwd, ["rev-parse", "HEAD"]);
  const { client } = fakeGitHub(repository);
  try {
    await recordManifestEntry({
      client,
      cwd: repository.cwd,
      commitRef: repository.candidateSha,
      payload: shipPayload,
      headRef: repository.candidateSha,
    });

    const synced = await syncManifestRange({
      client,
      cwd: repository.cwd,
      headRef: repository.candidateSha,
    });
    assert.equal(synced.pendingEntries[0].disposition, "ship");
    assert.equal(synced.results[0].action, "unchanged");

    await recordManifestEntry({
      client,
      cwd: repository.cwd,
      commitRef: repository.candidateSha,
      payload: {
        disposition: "release-operation",
        reason: "Deliberately replaced after release review.",
      },
      headRef: repository.candidateSha,
    });

    const resynced = await syncManifestRange({
      client,
      cwd: repository.cwd,
      headRef: repository.candidateSha,
    });
    assert.equal(resynced.pendingEntries[0].disposition, "release-operation");
    assert.equal(resynced.pendingEntries[0].reason, "Deliberately replaced after release review.");
    assert.equal(resynced.results[0].action, "unchanged");
  } finally {
    rmSync(repository.cwd, { recursive: true, force: true });
  }
});

test("release verification rejects a live manifest changed after snapshot", async () => {
  const commit = "a".repeat(40);
  const snapshotEntry = buildManifestEntry({ commit, pr: 12, payload: shipPayload });
  const changedEntry = { ...snapshotEntry, validation: "Edited after the release cut." };
  const fetchImpl = async (url) => {
    if (url.endsWith("/issues/77")) {
      return new Response(JSON.stringify({
        number: 77,
        title: "[machine] Next TestFlight manifest",
        state: "open",
        html_url: "https://github.com/joelipshutz/wander/issues/77",
        body: renderIssueBody({
          state: {
            schemaVersion: 1,
            baselineTag: "testflight/build-1",
            baselineSha: "b".repeat(40),
          },
          pendingEntries: [],
          repository: "joelipshutz/wander",
        }),
      }), { status: 200 });
    }
    if (url.includes("/issues/77/comments")) {
      return new Response(JSON.stringify([{ id: 1, body: renderEntryComment(changedEntry) }]), { status: 200 });
    }
    return new Response("not found", { status: 404 });
  };

  await assert.rejects(
    () => verifyManifestSourceCurrent({
      source: {
        kind: "github-issue",
        repository: "joelipshutz/wander",
        issueNumber: 77,
        baselineTag: "testflight/build-1",
        baselineSha: "b".repeat(40),
        entriesSha256: entriesSha256([snapshotEntry]),
      },
      commits: [{ sha: commit }],
      token: "test-token",
      fetchImpl,
    }),
    /changed after reconciliation/,
  );
});

test("finalization advances the same issue baseline only after the immutable tag exists", async () => {
  const repository = makeRepository();
  git(repository.cwd, ["tag", "testflight/build-2", repository.candidateSha]);
  const { client, state } = fakeGitHub(repository);
  try {
    const result = await finalizeManifest({
      client,
      cwd: repository.cwd,
      buildNumber: 2,
      candidateRef: repository.candidateSha,
      tagRef: "testflight/build-2",
      headRef: repository.candidateSha,
    });
    assert.equal(result.state.baselineTag, "testflight/build-2");
    assert.match(state.issue.body, /Completed baseline: `testflight\/build-2`/);
    assert.equal(result.pendingCount, 0);
  } finally {
    rmSync(repository.cwd, { recursive: true, force: true });
  }
});
