#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const TESTFLIGHT_URL = "https://testflight.apple.com/join/knEhRa6t";
const RELEASE_NOTES_CHANNEL = "#release-notes";
const FEEDBACK_CHANNEL = "#testflight-feedback";
const DISPOSITIONS = new Set(["ship", "exclude", "release-operation"]);

function fail(message) {
  throw new Error(message);
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

export function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function stringList(value) {
  if (Array.isArray(value)) {
    return value.filter(nonEmptyString).map((item) => item.trim());
  }
  if (nonEmptyString(value)) {
    return [value.trim()];
  }
  return [];
}

export function parseCommitRecord(line) {
  const separator = line.indexOf("\t");
  if (separator < 0) {
    fail(`Malformed git log row: ${line}`);
  }

  const sha = line.slice(0, separator).trim();
  const subject = line.slice(separator + 1).trim();
  const prMatches = [...subject.matchAll(/\(#(\d+)\)/g)];
  const issueMatch = subject.match(/\bREC-\d+\b/i);

  return {
    sha,
    subject,
    pr: prMatches.length > 0
      ? Number(prMatches[prMatches.length - 1][1])
      : null,
    issue: issueMatch ? issueMatch[0].toUpperCase() : null,
  };
}

function resolveEntryCommit(commits, commitRef) {
  if (!nonEmptyString(commitRef) || commitRef.trim().length < 7) {
    fail("Every manifest entry needs a commit SHA with at least 7 characters.");
  }

  const normalized = commitRef.trim().toLowerCase();
  const matches = commits.filter((commit) => commit.sha.toLowerCase().startsWith(normalized));
  if (matches.length === 0) {
    fail(`Manifest entry ${commitRef} is outside the release range.`);
  }
  if (matches.length > 1) {
    fail(`Manifest entry ${commitRef} is ambiguous inside the release range.`);
  }
  return matches[0];
}

function validateShipEntry(entry, label) {
  if (!nonEmptyString(entry.issue)) {
    fail(`${label} must name its Linear issue.`);
  }
  if (entry.pr !== null && (!Number.isInteger(entry.pr) || entry.pr <= 0)) {
    fail(`${label} pull request must be a positive integer or null for an explicitly recorded direct push.`);
  }
  if (!nonEmptyString(entry.testerFacingChange)) {
    fail(`${label} must include testerFacingChange.`);
  }
  if (stringList(entry.whatToTest).length === 0) {
    fail(`${label} must include at least one whatToTest action.`);
  }
  if (!nonEmptyString(entry.releaseOperations)) {
    fail(`${label} must include releaseOperations or explicitly say "none".`);
  }
  if (!nonEmptyString(entry.validation)) {
    fail(`${label} must include validation evidence.`);
  }
}

export function reconcileManifest({
  commits,
  manifest,
  baseRef,
  resolvedBaseSha,
  resolvedHeadSha,
}) {
  const errors = [];
  const capture = (callback) => {
    try {
      callback();
    } catch (error) {
      errors.push(error.message);
    }
  };

  if (manifest.schemaVersion !== 1) {
    errors.push("Manifest schemaVersion must be 1.");
  }
  if (manifest.baselineTag !== baseRef) {
    errors.push(`Manifest baselineTag must equal ${baseRef}.`);
  }
  if (manifest.baselineSha !== resolvedBaseSha) {
    errors.push(`Manifest baselineSha must equal ${resolvedBaseSha}.`);
  }
  if (manifest.candidateSha !== resolvedHeadSha) {
    errors.push(`Manifest candidateSha must equal ${resolvedHeadSha}.`);
  }
  if (!Array.isArray(manifest.entries)) {
    errors.push("Manifest entries must be an array.");
  }

  const entries = [];
  const seenCommits = new Set();
  const seenPRs = new Set();

  for (const [index, entry] of (manifest.entries ?? []).entries()) {
    const label = `Manifest entry ${index + 1}`;
    capture(() => {
      if (!DISPOSITIONS.has(entry.disposition)) {
        fail(`${label} has invalid disposition ${entry.disposition ?? "<missing>"}.`);
      }

      const commit = resolveEntryCommit(commits, entry.commit);
      if (seenCommits.has(commit.sha)) {
        fail(`${label} duplicates commit ${commit.sha}.`);
      }
      seenCommits.add(commit.sha);

      if (commit.pr !== null) {
        if (entry.pr !== commit.pr) {
          fail(`${label} says PR #${entry.pr ?? "<missing>"}, but git says PR #${commit.pr}.`);
        }
        if (seenPRs.has(commit.pr)) {
          fail(`${label} duplicates PR #${commit.pr}.`);
        }
        seenPRs.add(commit.pr);
      }

      if (commit.issue !== null && entry.issue !== commit.issue) {
        fail(`${label} says ${entry.issue ?? "<missing>"}, but git says ${commit.issue}.`);
      }

      if (entry.disposition === "ship") {
        validateShipEntry(entry, label);
      } else if (!nonEmptyString(entry.reason)) {
        fail(`${label} must explain why it is ${entry.disposition}.`);
      }

      entries.push({ ...entry, commit: commit.sha, gitSubject: commit.subject });
    });
  }

  const missing = commits.filter((commit) => !seenCommits.has(commit.sha));
  for (const commit of missing) {
    errors.push(
      `Missing classification: ${commit.sha.slice(0, 10)} ${commit.subject}`,
    );
  }

  const order = new Map(commits.map((commit, index) => [commit.sha, index]));
  entries.sort((left, right) => order.get(left.commit) - order.get(right.commit));

  const shipped = entries.filter((entry) => entry.disposition === "ship");
  const excluded = entries.filter((entry) => entry.disposition === "exclude");
  const releaseOperations = entries.filter(
    (entry) => entry.disposition === "release-operation",
  );

  return {
    ok: errors.length === 0,
    errors,
    baseRef,
    baselineSha: resolvedBaseSha,
    candidateSha: resolvedHeadSha,
    commits,
    entries,
    shipped,
    excluded,
    releaseOperations,
  };
}

function bulletList(items, emptyCopy) {
  if (items.length === 0) {
    return `- ${emptyCopy}`;
  }
  return items.map((item) => `- ${item}`).join("\n");
}

function releaseStatusCopy(status) {
  switch (status) {
  case "live":
    return "is live and approved in TestFlight";
  case "processing":
    return "has been uploaded and is processing in TestFlight";
  case "candidate":
    return "is the locked release candidate";
  default:
    fail("Release status must be candidate, processing, or live.");
  }
}

export function buildReleaseArtifacts({
  report,
  buildNumber,
  marketingVersion,
  status,
  approvedTesterCopy = null,
}) {
  if (!report.ok) {
    fail("Cannot generate release artifacts from a failed reconciliation.");
  }
  if (!Number.isInteger(buildNumber) || buildNumber <= 0) {
    fail("A positive integer build number is required to generate release artifacts.");
  }
  if (!nonEmptyString(marketingVersion)) {
    fail("A project marketing version is required to generate release artifacts.");
  }
  if (report.shipped.length === 0) {
    fail("At least one shipped payload is required to generate tester copy.");
  }

  const changes = report.shipped.map((entry) => entry.testerFacingChange.trim());
  const tests = report.shipped.flatMap((entry) => stringList(entry.whatToTest));
  const limitations = report.shipped.flatMap((entry) => stringList(entry.knownLimitations));
  const allOperations = report.entries
    .filter((entry) => entry.disposition !== "exclude")
    .map((entry) => entry.releaseOperations)
    .filter(nonEmptyString)
    .filter((operation, index, all) => all.indexOf(operation) === index);
  const substantiveOperations = allOperations.filter(
    (operation) => operation.trim().toLowerCase().replace(/\.$/, "") !== "none",
  );
  const operations = substantiveOperations.length > 0
    ? substantiveOperations
    : ["none"];

  const generatedWhatToTest = [
    "What changed",
    bulletList(changes, "No tester-facing changes."),
    "",
    "What to test",
    bulletList(tests, "No additional tester action."),
    "",
    "Known limitations",
    bulletList(limitations, "No known limitations beyond existing tracked issues."),
  ].join("\n");
  const whatToTest = approvedTesterCopy == null
    ? generatedWhatToTest
    : String(approvedTesterCopy).trim();

  if (approvedTesterCopy != null) {
    if (!nonEmptyString(whatToTest)) {
      fail("Approved TestFlight tester copy cannot be empty.");
    }
    for (const heading of ["What changed", "What to test", "Known limitations"]) {
      if (!whatToTest.includes(heading)) {
        fail(`Approved TestFlight tester copy must include the ${heading} heading.`);
      }
    }
  }

  if (whatToTest.length > 4000) {
    fail(`Generated TestFlight What to Test copy is ${whatToTest.length} characters; limit is 4000.`);
  }

  const slackBody = approvedTesterCopy == null
    ? [
      "What changed",
      bulletList(changes, "No tester-facing changes."),
      "",
      "What to test",
      bulletList(tests, "No additional tester action."),
      "",
      "Known limitations",
      bulletList(limitations, "No known limitations beyond existing tracked issues."),
    ].join("\n")
    : whatToTest;
  const slack = [
    `rec.me ${marketingVersion.trim()} (${buildNumber}) ${releaseStatusCopy(status)}.`,
    "",
    slackBody,
    "",
    `Install or update: ${TESTFLIGHT_URL}`,
    `Please report problems in ${FEEDBACK_CHANNEL} with your device, account/email if relevant, screenshots, and exact repro steps.`,
  ].join("\n");

  if (slack.length > 5000) {
    fail(`Generated Slack release note is ${slack.length} characters; limit is 5000.`);
  }

  const payloadRows = report.shipped.map(
    (entry) => `- ${entry.issue} / ${entry.pr ? `PR #${entry.pr}` : "direct push"} / \`${entry.commit}\` — ${entry.testerFacingChange.trim()}`,
  );
  const excludedRows = report.excluded.map(
    (entry) => `- PR #${entry.pr ?? "n/a"} / \`${entry.commit}\` — ${entry.reason.trim()}`,
  );
  const operationRows = report.releaseOperations.map(
    (entry) => `- PR #${entry.pr ?? "n/a"} / \`${entry.commit}\` — ${entry.reason.trim()}`,
  );

  const releaseRecord = [
    `## TestFlight build ${buildNumber} reconciliation`,
    "",
    `- Baseline: \`${report.baseRef}\` / \`${report.baselineSha}\``,
    `- Candidate: \`${report.candidateSha}\``,
    `- Canonical Slack channel: ${RELEASE_NOTES_CHANNEL}`,
    "",
    "### Included payloads",
    bulletList(payloadRows.map((row) => row.slice(2)), "None."),
    "",
    "### Explicit exclusions",
    bulletList(excludedRows.map((row) => row.slice(2)), "None."),
    "",
    "### Release-only commits",
    bulletList(operationRows.map((row) => row.slice(2)), "None."),
    "",
    "### Release operations",
    bulletList(operations, "none"),
  ].join("\n");

  return { whatToTest, slack, releaseRecord };
}

export function sortTestFlightTags(tags) {
  return [...tags].sort((left, right) => {
    const leftBuild = Number(left.match(/testflight\/build-(\d+)$/)?.[1] ?? Number.MAX_SAFE_INTEGER);
    const rightBuild = Number(right.match(/testflight\/build-(\d+)$/)?.[1] ?? Number.MAX_SAFE_INTEGER);
    return leftBuild - rightBuild || left.localeCompare(right);
  });
}

export function runGit(args, cwd) {
  return execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
}

export function resolveMarketingVersion(ref, cwd) {
  const projectYAML = runGit(["show", `${ref}:project.yml`], cwd);
  const match = projectYAML.match(
    /^\s*MARKETING_VERSION:\s*["']?([^"'\s#]+)["']?\s*(?:#.*)?$/m,
  );
  if (!match) {
    fail(`project.yml at ${ref} does not declare MARKETING_VERSION.`);
  }
  return match[1];
}

export function resolveCommit(ref, cwd) {
  return runGit(["rev-parse", `${ref}^{commit}`], cwd);
}

export function collectCommits(baseRef, headRef, cwd) {
  try {
    runGit(["merge-base", "--is-ancestor", baseRef, headRef], cwd);
  } catch {
    fail(`${baseRef} is not an ancestor of ${headRef}.`);
  }

  const output = runGit(
    ["log", "--first-parent", "--reverse", "--format=%H%x09%s", `${baseRef}..${headRef}`],
    cwd,
  );
  return output ? output.split("\n").map(parseCommitRecord) : [];
}

function parseArgs(argv) {
  const options = { cwd: process.cwd(), status: "candidate", force: false };
  const valueFlags = new Set([
    "--audit-sha",
    "--base",
    "--build",
    "--cwd",
    "--head",
    "--manifest",
    "--status",
    "--write-dir",
  ]);

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--force") {
      options.force = true;
      continue;
    }
    if (!valueFlags.has(argument)) {
      fail(`Unknown argument: ${argument}`);
    }
    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      fail(`${argument} requires a value.`);
    }
    index += 1;
    options[argument.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase())] = value;
  }
  return options;
}

function auditSha(shaRef, cwd) {
  const sha = resolveCommit(shaRef, cwd);
  const tagOutput = runGit(["tag", "--contains", sha, "--list", "testflight/build-*"], cwd);
  const tags = sortTestFlightTags(tagOutput ? tagOutput.split("\n").filter(Boolean) : []);
  const mainContains = (() => {
    try {
      runGit(["merge-base", "--is-ancestor", sha, "origin/main"], cwd);
      return true;
    } catch {
      return false;
    }
  })();

  return {
    sha,
    firstTestFlightTag: tags[0] ?? null,
    containingTestFlightTags: tags,
    containedInOriginMain: mainContains,
  };
}

export function writeArtifacts({
  directory,
  buildNumber,
  report,
  artifacts,
  force,
  manifestSource = null,
}) {
  mkdirSync(directory, { recursive: true });
  const prefix = `testflight-build-${buildNumber}`;
  const files = {
    reconciliation: resolve(directory, `${prefix}-reconciliation.json`),
    whatToTest: resolve(directory, `${prefix}-what-to-test.md`),
    slack: resolve(directory, `${prefix}-slack-release-notes.md`),
    releaseRecord: resolve(directory, `${prefix}-release-record.md`),
  };
  const flag = force ? "w" : "wx";
  const lockedReport = {
    ...report,
    gateVersion: manifestSource ? 2 : 1,
    buildNumber,
    whatToTestSha256: sha256(artifacts.whatToTest.trim()),
    ...(manifestSource ? { manifestSource } : {}),
  };
  writeFileSync(files.reconciliation, `${JSON.stringify(lockedReport, null, 2)}\n`, { flag });
  writeFileSync(files.whatToTest, `${artifacts.whatToTest}\n`, { flag });
  writeFileSync(files.slack, `${artifacts.slack}\n`, { flag });
  writeFileSync(files.releaseRecord, `${artifacts.releaseRecord}\n`, { flag });
  return files;
}

function usage() {
  return [
    "Reconcile a TestFlight manifest:",
    "  node scripts/reconcile-testflight-manifest.mjs --base testflight/build-124 --head <candidate> --manifest <manifest.json> [--build 125 --status candidate --write-dir <dir>]",
    "",
    "Audit when a commit first shipped:",
    "  node scripts/reconcile-testflight-manifest.mjs --audit-sha c555a2d5",
  ].join("\n");
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const cwd = resolve(options.cwd);

  if (options.auditSha) {
    process.stdout.write(`${JSON.stringify(auditSha(options.auditSha, cwd), null, 2)}\n`);
    return;
  }

  if (!options.base || !options.head || !options.manifest) {
    fail(`${usage()}\n\n--base, --head, and --manifest are required.`);
  }

  const resolvedBaseSha = resolveCommit(options.base, cwd);
  const resolvedHeadSha = resolveCommit(options.head, cwd);
  const commits = collectCommits(options.base, options.head, cwd);
  const manifest = JSON.parse(readFileSync(resolve(options.manifest), "utf8"));
  const report = reconcileManifest({
    commits,
    manifest,
    baseRef: options.base,
    resolvedBaseSha,
    resolvedHeadSha,
  });

  if (!report.ok) {
    process.stderr.write(`${report.errors.map((error) => `ERROR: ${error}`).join("\n")}\n`);
    process.exitCode = 1;
    return;
  }

  let files = null;
  if (options.build || options.writeDir) {
    const buildNumber = Number(options.build);
    const artifacts = buildReleaseArtifacts({
      report,
      buildNumber,
      marketingVersion: resolveMarketingVersion(options.head, cwd),
      status: options.status,
    });
    if (options.writeDir) {
      files = writeArtifacts({
        directory: resolve(options.writeDir),
        buildNumber,
        report,
        artifacts,
        force: options.force,
      });
    }
  }

  process.stdout.write(`${JSON.stringify({
    ok: true,
    baseline: report.baseRef,
    baselineSha: report.baselineSha,
    candidateSha: report.candidateSha,
    commitCount: report.commits.length,
    shipped: report.shipped.map((entry) => ({ commit: entry.commit, pr: entry.pr, issue: entry.issue })),
    excluded: report.excluded.map((entry) => ({ commit: entry.commit, pr: entry.pr, reason: entry.reason })),
    releaseOperations: report.releaseOperations.map((entry) => ({ commit: entry.commit, pr: entry.pr, reason: entry.reason })),
    files,
  }, null, 2)}\n`);
}

const isMain = process.argv[1]
  && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;

if (isMain) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`ERROR: ${error.message}\n`);
    process.exitCode = 1;
  }
}
