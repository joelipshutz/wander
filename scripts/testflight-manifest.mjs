#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  buildReleaseArtifacts,
  collectCommits,
  reconcileManifest,
  resolveCommit,
  runGit,
  sha256,
  writeArtifacts,
} from "./reconcile-testflight-manifest.mjs";

export const MANIFEST_ISSUE_TITLE = "[machine] Next TestFlight manifest";
export const PR_PAYLOAD_MARKER = "recme-testflight-payload";
export const ISSUE_STATE_MARKER = "recme-testflight-state";
export const ENTRY_MARKER = "recme-testflight-entry";

const VALID_DISPOSITIONS = new Set(["ship", "exclude", "release-operation"]);
const PAYLOAD_KEYS = new Set([
  "disposition",
  "issue",
  "testerFacingChange",
  "whatToTest",
  "releaseOperations",
  "validation",
  "knownLimitations",
  "reason",
]);
const APP_RUNTIME_PREFIXES = [
  "Wander/",
  "WanderControlShared/",
  "WanderImportShared/",
  "WanderNearbyWidgets/",
  "WanderShareExtension/",
  "WanderWidgetShared/",
  "WanderWidgets/",
  "shared/",
];

function fail(message) {
  throw new Error(message);
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function cleanString(value) {
  return nonEmptyString(value) ? value.trim() : value;
}

function cleanStringList(value) {
  return Array.isArray(value)
    ? value.filter(nonEmptyString).map((item) => item.trim())
    : value;
}

function hasPlaceholder(value) {
  return typeof value === "string"
    && (/<[^>]+>/.test(value) || /replace-me|REC-#+/i.test(value));
}

export function extractMarkedJSON(body, marker, { required = true } = {}) {
  const expression = new RegExp(`<!--\\s*${marker}\\s*\\n([\\s\\S]*?)\\n?-->`, "g");
  const matches = [...String(body ?? "").matchAll(expression)];
  if (matches.length === 0) {
    if (!required) return null;
    fail(`Missing <!-- ${marker} ... --> JSON block.`);
  }
  if (matches.length > 1) {
    fail(`Found multiple ${marker} JSON blocks; exactly one is required.`);
  }
  try {
    return JSON.parse(matches[0][1]);
  } catch (error) {
    fail(`Invalid JSON in ${marker} block: ${error.message}`);
  }
}

export function validatePullRequestPayload(payload) {
  const errors = [];
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return ["Release payload must be a JSON object."];
  }

  const unknownKeys = Object.keys(payload).filter((key) => !PAYLOAD_KEYS.has(key));
  if (unknownKeys.length > 0) {
    errors.push(`Unknown release payload field(s): ${unknownKeys.join(", ")}.`);
  }
  if (!VALID_DISPOSITIONS.has(payload.disposition)) {
    errors.push("disposition must be ship, exclude, or release-operation.");
  }
  if (payload.issue != null && !/^REC-[0-9]+$/.test(payload.issue)) {
    errors.push("issue must match REC-<number> when provided.");
  }

  if (payload.disposition === "ship") {
    if (!/^REC-[0-9]+$/.test(payload.issue ?? "")) {
      errors.push("ship payloads require a Linear issue matching REC-<number>.");
    }
    if (!nonEmptyString(payload.testerFacingChange)) {
      errors.push("ship payloads require testerFacingChange.");
    }
    if (!Array.isArray(payload.whatToTest) || payload.whatToTest.filter(nonEmptyString).length === 0) {
      errors.push("ship payloads require at least one whatToTest action.");
    } else if (payload.whatToTest.some((item) => !nonEmptyString(item))) {
      errors.push("every whatToTest action must be a non-empty string.");
    }
    if (!nonEmptyString(payload.releaseOperations)) {
      errors.push("ship payloads require releaseOperations or the literal none.");
    }
    if (!nonEmptyString(payload.validation)) {
      errors.push("ship payloads require validation evidence.");
    }
    if (payload.knownLimitations != null) {
      if (!Array.isArray(payload.knownLimitations)) {
        errors.push("knownLimitations must be an array when provided.");
      } else if (payload.knownLimitations.some((item) => !nonEmptyString(item))) {
        errors.push("every known limitation must be a non-empty string.");
      }
    }
    if (payload.reason != null) {
      errors.push("ship payloads cannot include reason; use testerFacingChange instead.");
    }
  } else if (VALID_DISPOSITIONS.has(payload.disposition) && !nonEmptyString(payload.reason)) {
    errors.push(`${payload.disposition} payloads require a reason.`);
  } else if (VALID_DISPOSITIONS.has(payload.disposition)) {
    const shipOnly = ["testerFacingChange", "whatToTest", "validation", "knownLimitations"]
      .filter((key) => payload[key] != null);
    if (shipOnly.length > 0) {
      errors.push(`${payload.disposition} payloads cannot include ship-only field(s): ${shipOnly.join(", ")}.`);
    }
  }

  for (const [key, value] of Object.entries(payload)) {
    const values = Array.isArray(value) ? value : [value];
    if (values.some(hasPlaceholder)) {
      errors.push(`${key} still contains template placeholder text.`);
    }
    if (values.some((item) => typeof item === "string" && item.length > 3000)) {
      errors.push(`${key} exceeds the 3000-character field limit.`);
    }
    if (values.some((item) => typeof item === "string" && item.includes("-->"))) {
      errors.push(`${key} cannot contain an HTML comment terminator.`);
    }
  }
  return errors;
}

export function parsePullRequestPayload(body) {
  const payload = extractMarkedJSON(body, PR_PAYLOAD_MARKER);
  const errors = validatePullRequestPayload(payload);
  if (errors.length > 0) fail(errors.join(" "));
  return {
    ...payload,
    issue: cleanString(payload.issue),
    testerFacingChange: cleanString(payload.testerFacingChange),
    whatToTest: cleanStringList(payload.whatToTest),
    releaseOperations: cleanString(payload.releaseOperations),
    validation: cleanString(payload.validation),
    knownLimitations: cleanStringList(payload.knownLimitations),
    reason: cleanString(payload.reason),
  };
}

export function validatePayloadAgainstChangedFiles(payload, changedFiles) {
  const files = changedFiles.filter(nonEmptyString);
  const runtimeFiles = files.filter((file) => APP_RUNTIME_PREFIXES.some((prefix) => file.startsWith(prefix)));
  if (runtimeFiles.length > 0 && payload.disposition !== "ship") {
    return [`App/runtime files require disposition ship; ${runtimeFiles[0]} cannot be ${payload.disposition}.`];
  }
  const projectMetadata = files.filter(
    (file) => file === "project.yml" || file.startsWith("Wander.xcodeproj/"),
  );
  if (projectMetadata.length > 0 && payload.disposition === "exclude") {
    return [`Project/build metadata requires ship or release-operation; ${projectMetadata[0]} cannot be exclude.`];
  }
  return [];
}

export function buildManifestEntry({ commit, pr, payload }) {
  return {
    commit,
    pr,
    ...(payload.issue ? { issue: payload.issue } : {}),
    disposition: payload.disposition,
    ...(payload.disposition === "ship" ? {
      testerFacingChange: payload.testerFacingChange,
      whatToTest: payload.whatToTest,
      releaseOperations: payload.releaseOperations,
      validation: payload.validation,
      ...(payload.knownLimitations?.length > 0
        ? { knownLimitations: payload.knownLimitations }
        : {}),
    } : {
      reason: payload.reason,
      ...(payload.releaseOperations
        ? { releaseOperations: payload.releaseOperations }
        : {}),
    }),
  };
}

export function buildUnclassifiedEntry({ commit, pr = null, issue = null, reason }) {
  return {
    commit,
    pr,
    ...(issue ? { issue } : {}),
    disposition: "unclassified",
    reason,
  };
}

function markedJSON(marker, value) {
  return `<!-- ${marker}\n${JSON.stringify(value, null, 2)}\n-->`;
}

function escapeTable(value) {
  return String(value ?? "").replaceAll("|", "\\|").replaceAll("\n", " ");
}

export function renderEntryComment(entry) {
  const label = entry.disposition === "unclassified" ? "BLOCKED" : entry.disposition;
  const summary = entry.testerFacingChange ?? entry.reason;
  return [
    markedJSON(ENTRY_MARKER, entry),
    `**${label}** · \`${entry.commit.slice(0, 10)}\`${entry.pr ? ` · PR #${entry.pr}` : " · direct push"}${entry.issue ? ` · ${entry.issue}` : ""}`,
    "",
    summary,
  ].join("\n");
}

export function parseEntryComment(body) {
  return extractMarkedJSON(body, ENTRY_MARKER, { required: false });
}

export function parseIssueState(body) {
  const state = extractMarkedJSON(body, ISSUE_STATE_MARKER);
  if (state.schemaVersion !== 1) fail("Manifest issue state schemaVersion must be 1.");
  if (!/^testflight\/build-[0-9]+$/.test(state.baselineTag ?? "")) {
    fail("Manifest issue baselineTag must match testflight/build-<number>.");
  }
  if (!/^[0-9a-f]{40}$/.test(state.baselineSha ?? "")) {
    fail("Manifest issue baselineSha must be a full commit SHA.");
  }
  return state;
}

export function renderIssueBody({ state, pendingEntries, repository }) {
  const rows = pendingEntries.length === 0
    ? "| — | — | No pending commits |"
    : pendingEntries.map((entry) => {
      const status = entry.disposition === "unclassified" ? "🔴 unclassified" : entry.disposition;
      const source = entry.pr ? `#${entry.pr}` : "direct push";
      const summary = entry.testerFacingChange ?? entry.reason;
      return `| \`${entry.commit.slice(0, 10)}\` | ${source} · ${status} | ${escapeTable(summary)} |`;
    }).join("\n");

  return [
    "This issue is the machine-owned release queue for `main`. Do not hand-edit the JSON markers or entry comments.",
    "",
    `Repository: \`${repository}\``,
    `Completed baseline: \`${state.baselineTag}\` / \`${state.baselineSha}\``,
    "",
    markedJSON(ISSUE_STATE_MARKER, state),
    "",
    "## Pending commits",
    "",
    "| Commit | Classification | Tester/release context |",
    "|---|---|---|",
    rows,
    "",
    "A red entry blocks the TestFlight cut until its merged PR payload is corrected or the commit is explicitly recorded.",
  ].join("\n");
}

export function canonicalEntries(entries) {
  return [...entries]
    .sort((left, right) => left.commit.localeCompare(right.commit))
    .map((entry) => {
      const {
        commentId: _commentId,
        gitSubject: _gitSubject,
        ...manifestEntry
      } = entry;
      return JSON.parse(JSON.stringify(manifestEntry));
    });
}

export function entriesSha256(entries) {
  return sha256(JSON.stringify(canonicalEntries(entries)));
}

export function resolveGitHubToken(explicitToken = null) {
  if (nonEmptyString(explicitToken)) return explicitToken.trim();
  if (nonEmptyString(process.env.GH_TOKEN)) return process.env.GH_TOKEN.trim();
  if (nonEmptyString(process.env.GITHUB_TOKEN)) return process.env.GITHUB_TOKEN.trim();
  try {
    return execFileSync("gh", ["auth", "token"], { encoding: "utf8" }).trim();
  } catch {
    fail("GitHub authentication is required via GH_TOKEN, GITHUB_TOKEN, or gh auth login.");
  }
}

export function createGitHubClient({ repository, token, fetchImpl = fetch }) {
  const [owner, repo] = String(repository ?? "").split("/");
  if (!owner || !repo) fail("GitHub repository must be owner/name.");
  const base = `https://api.github.com/repos/${owner}/${repo}`;
  const request = async (method, path, body = null) => {
    const response = await fetchImpl(`${base}${path}`, {
      method,
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json",
      },
      ...(body == null ? {} : { body: JSON.stringify(body) }),
    });
    if (!response.ok) {
      const message = await response.text();
      fail(`GitHub ${method} ${path} failed (${response.status}): ${message}`);
    }
    return response.status === 204 ? null : response.json();
  };
  const paginate = async (path) => {
    const values = [];
    for (let page = 1; ; page += 1) {
      const joiner = path.includes("?") ? "&" : "?";
      const batch = await request("GET", `${path}${joiner}per_page=100&page=${page}`);
      values.push(...batch);
      if (batch.length < 100) return values;
    }
  };
  return { repository, request, paginate };
}

function repositoryFromGit(cwd) {
  if (nonEmptyString(process.env.GITHUB_REPOSITORY)) return process.env.GITHUB_REPOSITORY;
  try {
    return execFileSync("gh", ["repo", "view", "--json", "nameWithOwner", "--jq", ".nameWithOwner"], {
      cwd,
      encoding: "utf8",
    }).trim();
  } catch {
    fail("Pass --repo owner/name or set GITHUB_REPOSITORY.");
  }
}

function latestTestFlightTag(cwd) {
  const output = runGit(["tag", "--list", "testflight/build-*", "--sort=-version:refname"], cwd);
  const tag = output.split("\n").find(Boolean);
  if (!tag) fail("No immutable testflight/build-<n> baseline tag exists.");
  return tag;
}

async function findManifestIssue(client, { create = false, cwd = process.cwd() } = {}) {
  const issues = await client.paginate("/issues?state=open");
  const matches = issues.filter((issue) => !issue.pull_request && issue.title === MANIFEST_ISSUE_TITLE);
  if (matches.length > 1) fail(`Multiple open issues titled ${MANIFEST_ISSUE_TITLE}.`);
  if (matches.length === 1) return matches[0];
  if (!create) fail(`No open issue titled ${MANIFEST_ISSUE_TITLE}.`);

  const baselineTag = latestTestFlightTag(cwd);
  const state = {
    schemaVersion: 1,
    baselineTag,
    baselineSha: resolveCommit(baselineTag, cwd),
  };
  return client.request("POST", "/issues", {
    title: MANIFEST_ISSUE_TITLE,
    body: renderIssueBody({ state, pendingEntries: [], repository: client.repository }),
  });
}

async function listManifestComments(client, issueNumber) {
  const comments = await client.paginate(`/issues/${issueNumber}/comments?sort=created&direction=asc`);
  return comments.map((comment) => ({ ...comment, entry: parseEntryComment(comment.body) }))
    .filter((comment) => comment.entry);
}

function pullRequestNumberFromSubject(subject) {
  const matches = [...String(subject).matchAll(/\(#([0-9]+)\)/g)];
  return matches.length > 0 ? Number(matches.at(-1)[1]) : null;
}

async function pullRequestForCommit(client, commit) {
  const subjectPR = pullRequestNumberFromSubject(commit.subject);
  if (subjectPR) return client.request("GET", `/pulls/${subjectPR}`);
  const pulls = await client.request("GET", `/commits/${commit.sha}/pulls`);
  const merged = pulls.find((pull) => pull.merged_at && pull.base?.ref === "main");
  return merged ?? null;
}

export async function deriveEntryForCommit(client, commit) {
  const pull = await pullRequestForCommit(client, commit);
  if (!pull) {
    return buildUnclassifiedEntry({
      commit: commit.sha,
      issue: commit.issue,
      reason: "Direct main push has no pull request release payload.",
    });
  }
  try {
    const payload = parsePullRequestPayload(pull.body);
    return buildManifestEntry({ commit: commit.sha, pr: pull.number, payload });
  } catch (error) {
    const safeError = error.message.replaceAll("<!--", "marker ").replaceAll("-->", "");
    return buildUnclassifiedEntry({
      commit: commit.sha,
      pr: pull.number,
      issue: commit.issue,
      reason: `PR #${pull.number} release payload is missing or invalid: ${safeError}`,
    });
  }
}

async function upsertEntryComment(client, issueNumber, existingComments, entry) {
  const matches = existingComments.filter((comment) => comment.entry.commit === entry.commit);
  if (matches.length > 1) fail(`Manifest issue has duplicate comments for ${entry.commit}.`);
  const body = renderEntryComment(entry);
  if (matches.length === 0) {
    const created = await client.request("POST", `/issues/${issueNumber}/comments`, { body });
    existingComments.push({ ...created, entry });
    return "created";
  }
  if (JSON.stringify(matches[0].entry) === JSON.stringify(entry)) return "unchanged";
  const updated = await client.request("PATCH", `/issues/comments/${matches[0].id}`, { body });
  matches[0].body = updated.body;
  matches[0].entry = entry;
  return "updated";
}

function entriesForCommits(comments, commits) {
  const byCommit = new Map();
  for (const comment of comments) {
    if (byCommit.has(comment.entry.commit)) fail(`Duplicate manifest entry for ${comment.entry.commit}.`);
    byCommit.set(comment.entry.commit, comment.entry);
  }
  return commits.map((commit) => byCommit.get(commit.sha)).filter(Boolean);
}

async function refreshIssueBody(client, issue, state, cwd, headRef) {
  const pendingCommits = collectCommits(state.baselineTag, headRef, cwd);
  const comments = await listManifestComments(client, issue.number);
  const pendingEntries = entriesForCommits(comments, pendingCommits);
  const body = renderIssueBody({ state, pendingEntries, repository: client.repository });
  if (issue.body !== body) {
    const updated = await client.request("PATCH", `/issues/${issue.number}`, { body });
    issue.body = updated.body;
  }
  return pendingEntries;
}

export async function syncManifestRange({
  client,
  cwd,
  headRef,
  createIssue = true,
}) {
  const issue = await findManifestIssue(client, { create: createIssue, cwd });
  const state = parseIssueState(issue.body);
  // Always sweep the complete pending range. A push event's `before` SHA is an
  // optimization hint, not a correctness boundary; this is what backfills a
  // missed updater run and makes every later main push self-healing.
  const commits = collectCommits(state.baselineTag, headRef, cwd);
  const comments = await listManifestComments(client, issue.number);
  const results = [];
  for (const commit of commits) {
    const existing = comments.find((comment) => comment.entry.commit === commit.sha)?.entry;
    const entry = existing && existing.pr == null && existing.disposition !== "unclassified"
      ? existing
      : await deriveEntryForCommit(client, commit);
    const action = await upsertEntryComment(client, issue.number, comments, entry);
    results.push({ commit: commit.sha, disposition: entry.disposition, action });
  }
  const pendingEntries = await refreshIssueBody(client, issue, state, cwd, headRef);
  return { issue, state, results, pendingEntries };
}

export async function loadManifestEntries(client, issueNumber, commits) {
  const comments = await listManifestComments(client, issueNumber);
  const byCommit = new Map();
  for (const comment of comments) {
    if (byCommit.has(comment.entry.commit)) fail(`Duplicate manifest entry for ${comment.entry.commit}.`);
    byCommit.set(comment.entry.commit, comment);
  }
  return commits.map((commit) => {
    const comment = byCommit.get(commit.sha);
    return comment ? { ...comment.entry, commentId: comment.id } : null;
  });
}

export async function recordManifestEntry({ client, cwd, commitRef, payload, headRef }) {
  const errors = validatePullRequestPayload(payload);
  if (errors.length > 0) fail(errors.join(" "));
  const commitSha = resolveCommit(commitRef, cwd);
  const issue = await findManifestIssue(client, { create: true, cwd });
  const state = parseIssueState(issue.body);
  const pendingCommits = collectCommits(state.baselineTag, headRef, cwd);
  const commit = pendingCommits.find((item) => item.sha === commitSha);
  if (!commit) {
    fail(`${commitSha} is not in the pending range ${state.baselineTag}..${headRef}.`);
  }
  const comments = await listManifestComments(client, issue.number);
  const entry = buildManifestEntry({ commit: commitSha, pr: commit.pr, payload });
  const action = await upsertEntryComment(client, issue.number, comments, entry);
  const pendingEntries = await refreshIssueBody(client, issue, state, cwd, headRef);
  return { issue, entry, action, pendingEntries };
}

function stripCommentMetadata(entry) {
  if (!entry) return entry;
  const { commentId: _commentId, ...manifestEntry } = entry;
  return manifestEntry;
}

export async function createReleaseSnapshot({
  client,
  cwd,
  baseRef,
  headRef,
  queueHeadRef = headRef,
  buildNumber,
  status,
  writeDirectory,
  force = false,
}) {
  const synced = await syncManifestRange({ client, cwd, headRef: queueHeadRef, createIssue: true });
  const state = synced.state;
  if (state.baselineTag !== baseRef) {
    fail(`Machine manifest baseline is ${state.baselineTag}; requested release baseline is ${baseRef}.`);
  }
  const baselineSha = resolveCommit(baseRef, cwd);
  if (state.baselineSha !== baselineSha) {
    fail(`Machine manifest baseline SHA ${state.baselineSha} does not match ${baselineSha}.`);
  }
  const candidateSha = resolveCommit(headRef, cwd);
  const commits = collectCommits(baseRef, headRef, cwd);
  const sourcedEntries = await loadManifestEntries(client, synced.issue.number, commits);
  const missing = commits.filter((_, index) => !sourcedEntries[index]);
  const unclassified = sourcedEntries.filter((entry) => entry?.disposition === "unclassified");
  if (missing.length > 0 || unclassified.length > 0) {
    const problems = [
      ...missing.map((commit) => `Missing machine entry: ${commit.sha.slice(0, 10)} ${commit.subject}`),
      ...unclassified.map((entry) => `Unclassified: ${entry.commit.slice(0, 10)} — ${entry.reason}`),
    ];
    fail(`TestFlight manifest is incomplete:\n${problems.join("\n")}`);
  }

  const entries = sourcedEntries.map(stripCommentMetadata);
  const manifest = {
    schemaVersion: 1,
    baselineTag: baseRef,
    baselineSha,
    candidateSha,
    entries,
  };
  const report = reconcileManifest({
    commits,
    manifest,
    baseRef,
    resolvedBaseSha: baselineSha,
    resolvedHeadSha: candidateSha,
  });
  if (!report.ok) fail(report.errors.join("\n"));

  const artifacts = buildReleaseArtifacts({ report, buildNumber, status });
  const directory = resolve(writeDirectory);
  const manifestPath = resolve(directory, `testflight-build-${buildNumber}-manifest.json`);
  const manifestSource = {
    kind: "github-issue",
    repository: client.repository,
    issueNumber: synced.issue.number,
    issueUrl: synced.issue.html_url,
    baselineTag: baseRef,
    baselineSha,
    candidateSha,
    entriesSha256: entriesSha256(entries),
  };
  const files = writeArtifacts({
    directory,
    buildNumber,
    report,
    artifacts,
    force,
    manifestSource,
  });
  writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { flag: force ? "w" : "wx" });
  return { issue: synced.issue, manifest, manifestSource, files: { manifest: manifestPath, ...files } };
}

export async function verifyManifestSourceCurrent({ source, commits, token, fetchImpl = fetch }) {
  if (source?.kind !== "github-issue") fail("Reconciliation source must be a GitHub issue manifest.");
  if (!nonEmptyString(source.repository) || !Number.isInteger(source.issueNumber)) {
    fail("Reconciliation GitHub manifest source is incomplete.");
  }
  const client = createGitHubClient({
    repository: source.repository,
    token: resolveGitHubToken(token),
    fetchImpl,
  });
  const issue = await client.request("GET", `/issues/${source.issueNumber}`);
  if (issue.state !== "open" || issue.title !== MANIFEST_ISSUE_TITLE) {
    fail("Reconciliation manifest issue is not the open machine manifest.");
  }
  const state = parseIssueState(issue.body);
  if (state.baselineTag !== source.baselineTag || state.baselineSha !== source.baselineSha) {
    fail("Machine manifest baseline changed after reconciliation; regenerate release artifacts.");
  }
  const entries = await loadManifestEntries(client, source.issueNumber, commits);
  if (entries.some((entry) => !entry || entry.disposition === "unclassified")) {
    fail("Live machine manifest is missing or has unclassified candidate commits.");
  }
  const currentHash = entriesSha256(entries.map(stripCommentMetadata));
  if (currentHash !== source.entriesSha256) {
    fail("Live machine manifest changed after reconciliation; regenerate release artifacts.");
  }
  return { issueUrl: issue.html_url, entriesSha256: currentHash };
}

export async function finalizeManifest({ client, cwd, buildNumber, candidateRef, tagRef, headRef }) {
  const candidateSha = resolveCommit(candidateRef, cwd);
  const tagSha = resolveCommit(tagRef, cwd);
  if (tagRef !== `testflight/build-${buildNumber}`) {
    fail(`Final tag must be testflight/build-${buildNumber}.`);
  }
  if (tagSha !== candidateSha) fail(`${tagRef} does not resolve to candidate ${candidateSha}.`);
  const issue = await findManifestIssue(client, { create: false, cwd });
  const priorState = parseIssueState(issue.body);
  const state = { schemaVersion: 1, baselineTag: tagRef, baselineSha: candidateSha };
  const pendingEntries = await refreshIssueBody(client, issue, state, cwd, headRef);
  await client.request("POST", `/issues/${issue.number}/comments`, {
    body: `Completed TestFlight build ${buildNumber}. Baseline advanced from \`${priorState.baselineTag}\` to \`${tagRef}\` at \`${candidateSha}\`. ${pendingEntries.length} later commit(s) remain pending.`,
  });
  return { issueUrl: issue.html_url, state, pendingCount: pendingEntries.length };
}

function parseArgs(argv) {
  const command = argv[0];
  const options = { cwd: process.cwd(), status: "candidate", force: false };
  const booleanFlags = new Set(["--force"]);
  for (let index = 1; index < argv.length; index += 1) {
    const argument = argv[index];
    if (booleanFlags.has(argument)) {
      options.force = true;
      continue;
    }
    if (!argument.startsWith("--")) fail(`Unknown argument: ${argument}`);
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) fail(`${argument} requires a value.`);
    index += 1;
    options[argument.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value;
  }
  return { command, options };
}

function required(options, name) {
  if (!nonEmptyString(options[name])) fail(`--${name.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)} is required.`);
  return options[name];
}

function buildRuntime(options) {
  const cwd = resolve(options.cwd);
  const repository = options.repo ?? repositoryFromGit(cwd);
  const token = resolveGitHubToken(options.token);
  return { cwd, repository, client: createGitHubClient({ repository, token }) };
}

function usage() {
  return [
    "Validate a PR payload:",
    "  node scripts/testflight-manifest.mjs validate-pr --event <github-event.json>",
    "",
    "Sync main commits into the machine manifest:",
    "  node scripts/testflight-manifest.mjs sync --head <sha>",
    "",
    "Explicitly classify a direct push or repair a blocked commit:",
    "  node scripts/testflight-manifest.mjs record --commit <sha> --entry-file <payload.json> --head origin/main",
    "",
    "Cut and reconcile a release from the same manifest:",
    "  node scripts/testflight-manifest.mjs snapshot --base testflight/build-124 --head <candidate> --build 125 --write-dir <dir>",
    "",
    "Advance the manifest after a completed release:",
    "  node scripts/testflight-manifest.mjs finalize --build 125 --candidate <sha> --tag testflight/build-125 --head origin/main",
  ].join("\n");
}

async function main() {
  const { command, options } = parseArgs(process.argv.slice(2));
  if (!command || command === "help" || command === "--help") {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (command === "validate-pr") {
    const event = JSON.parse(readFileSync(resolve(required(options, "event")), "utf8"));
    const payload = parsePullRequestPayload(event.pull_request?.body);
    let changedFiles = [];
    if (options.checkFiles === "true") {
      const repository = options.repo ?? event.repository?.full_name ?? process.env.GITHUB_REPOSITORY;
      const client = createGitHubClient({ repository, token: resolveGitHubToken(options.token) });
      changedFiles = (await client.paginate(`/pulls/${event.pull_request?.number}/files`))
        .map((file) => file.filename);
      const errors = validatePayloadAgainstChangedFiles(payload, changedFiles);
      if (errors.length > 0) fail(errors.join(" "));
    }
    process.stdout.write(`${JSON.stringify({
      ok: true,
      pr: event.pull_request?.number,
      disposition: payload.disposition,
      checkedFiles: changedFiles.length,
    }, null, 2)}\n`);
    return;
  }

  const runtime = buildRuntime(options);
  if (command === "sync") {
    const headRef = required(options, "head");
    const result = await syncManifestRange({
      ...runtime,
      headRef,
      createIssue: true,
    });
    const blocked = result.pendingEntries.filter((entry) => entry.disposition === "unclassified");
    process.stdout.write(`${JSON.stringify({
      ok: blocked.length === 0,
      issue: result.issue.html_url,
      synced: result.results,
      pending: result.pendingEntries.length,
      blocked: blocked.map((entry) => entry.commit),
    }, null, 2)}\n`);
    if (blocked.length > 0) {
      fail("Machine manifest contains unclassified main commits; correct their PR payloads before release.");
    }
    return;
  }
  if (command === "snapshot") {
    const result = await createReleaseSnapshot({
      ...runtime,
      baseRef: required(options, "base"),
      headRef: required(options, "head"),
      queueHeadRef: options.queueHead ?? "origin/main",
      buildNumber: Number(required(options, "build")),
      status: options.status,
      writeDirectory: required(options, "writeDir"),
      force: options.force,
    });
    process.stdout.write(`${JSON.stringify({ ok: true, issue: result.issue.html_url, files: result.files }, null, 2)}\n`);
    return;
  }
  if (command === "record") {
    const payload = JSON.parse(readFileSync(resolve(required(options, "entryFile")), "utf8"));
    const result = await recordManifestEntry({
      ...runtime,
      commitRef: required(options, "commit"),
      payload,
      headRef: options.head ?? "origin/main",
    });
    process.stdout.write(`${JSON.stringify({
      ok: true,
      issue: result.issue.html_url,
      action: result.action,
      entry: result.entry,
    }, null, 2)}\n`);
    return;
  }
  if (command === "finalize") {
    const result = await finalizeManifest({
      ...runtime,
      buildNumber: Number(required(options, "build")),
      candidateRef: required(options, "candidate"),
      tagRef: required(options, "tag"),
      headRef: options.head ?? "origin/main",
    });
    process.stdout.write(`${JSON.stringify({ ok: true, ...result }, null, 2)}\n`);
    return;
  }
  fail(`Unknown command: ${command}\n\n${usage()}`);
}

const isMain = process.argv[1]
  && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;

if (isMain) {
  try {
    await main();
  } catch (error) {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  }
}
