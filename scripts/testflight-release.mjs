#!/usr/bin/env node

import crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";
import {
  entriesSha256,
  verifyManifestSourceCurrent,
} from "./testflight-manifest.mjs";

const DEFAULTS = {
  apiBase: "https://api.appstoreconnect.apple.com/v1",
  appId: "6776850787",
  bundleId: "com.grayline.wander",
  envPath: "/Users/joelipshutz/.openclaw/workspace/.env.keys",
  groupName: "rec.me Alpha",
  pollSeconds: 30,
  projectPath: "project.yml",
  publicLink: "https://testflight.apple.com/join/knEhRa6t",
  timeoutAttempts: 30,
};

function printUsage() {
  console.log(`Usage:
  node scripts/testflight-release.mjs [options]

Options:
  --build-number <n>      Build number to process. Defaults to CURRENT_PROJECT_VERSION in project.yml.
  --archive-path <path>   Optional .xcarchive path. If present, verifies/uses Xcode's uploaded build number.
  --reconciliation-file <path>
                           Required passing reconciliation JSON generated from the machine manifest.
  --project <path>        Project YAML path. Default: project.yml.
  --app-id <id>           App Store Connect app id. Default: ${DEFAULTS.appId}.
  --group <name>          TestFlight beta group name. Default: ${DEFAULTS.groupName}.
  --locale <locale>       Beta build localization locale. Default: en-US.
  --what-to-test <text>   TestFlight "What to Test" copy for this build.
  --what-to-test-file <path>
                           Read TestFlight "What to Test" copy from a file.
  --env <path>            Local env file with ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH.
                           Default: ${DEFAULTS.envPath}
  --timeout-attempts <n>  Poll attempts before failing. Default: ${DEFAULTS.timeoutAttempts}.
  --poll-seconds <n>      Seconds between App Store Connect polls. Default: ${DEFAULTS.pollSeconds}.
  --dry-run               Print resolved config without calling App Store Connect.
  --help                  Show this help.

This script assumes xcodebuild archive/export upload already succeeded. It waits for the
uploaded build to become VALID, sets export compliance to usesNonExemptEncryption=false,
publishes the reconciled TestFlight "What to Test" copy, attaches the build to
the public TestFlight group, and submits external beta review. All non-help runs
require a passing reconciliation file for the exact build and current HEAD.`);
}

function parseArgs(argv) {
  const options = {
    appId: DEFAULTS.appId,
    archivePath: null,
    buildNumber: null,
    dryRun: false,
    envPath: DEFAULTS.envPath,
    groupName: DEFAULTS.groupName,
    locale: "en-US",
    pollSeconds: DEFAULTS.pollSeconds,
    projectPath: DEFAULTS.projectPath,
    publicLink: DEFAULTS.publicLink,
    reconciliationFile: null,
    timeoutAttempts: DEFAULTS.timeoutAttempts,
    whatToTest: null,
    whatToTestFile: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) throw new Error(`Missing value after ${arg}`);
      return argv[index];
    };

    switch (arg) {
      case "--app-id":
        options.appId = next();
        break;
      case "--archive-path":
        options.archivePath = next();
        break;
      case "--build-number":
        options.buildNumber = next();
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--env":
        options.envPath = next();
        break;
      case "--group":
        options.groupName = next();
        break;
      case "--locale":
        options.locale = next();
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--poll-seconds":
        options.pollSeconds = Number.parseInt(next(), 10);
        break;
      case "--project":
        options.projectPath = next();
        break;
      case "--reconciliation-file":
        options.reconciliationFile = next();
        break;
      case "--public-link":
        options.publicLink = next();
        break;
      case "--timeout-attempts":
        options.timeoutAttempts = Number.parseInt(next(), 10);
        break;
      case "--what-to-test":
      case "--whats-new":
        options.whatToTest = next();
        break;
      case "--what-to-test-file":
      case "--whats-new-file":
        options.whatToTestFile = next();
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  if (!Number.isInteger(options.pollSeconds) || options.pollSeconds < 1) {
    throw new Error("--poll-seconds must be a positive integer");
  }
  if (!Number.isInteger(options.timeoutAttempts) || options.timeoutAttempts < 1) {
    throw new Error("--timeout-attempts must be a positive integer");
  }
  if (options.whatToTest && options.whatToTestFile) {
    throw new Error("Use either --what-to-test or --what-to-test-file, not both");
  }
  if (!options.locale || !/^[a-z]{2}(-[A-Z]{2})?$/.test(options.locale)) {
    throw new Error("--locale must look like en-US");
  }

  return options;
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

export function validateReconciliationGate({
  gate,
  buildNumber,
  candidateSha,
  whatToTest,
}) {
  if (gate?.gateVersion !== 2) {
    throw new Error("Reconciliation gateVersion must be 2");
  }
  if (gate.ok !== true || !Array.isArray(gate.errors) || gate.errors.length > 0) {
    throw new Error("Reconciliation report is not passing");
  }
  if (String(gate.buildNumber) !== String(buildNumber)) {
    throw new Error(
      `Reconciliation build ${gate.buildNumber ?? "<missing>"} does not match requested build ${buildNumber}`,
    );
  }
  if (gate.candidateSha !== candidateSha) {
    throw new Error(
      `Reconciliation candidate ${gate.candidateSha ?? "<missing>"} does not match current HEAD ${candidateSha}`,
    );
  }
  if (!Array.isArray(gate.commits) || !Array.isArray(gate.entries)) {
    throw new Error("Reconciliation report must include commits and entries");
  }
  if (gate.commits.length === 0 || gate.entries.length !== gate.commits.length) {
    throw new Error("Reconciliation report does not classify every release-range commit");
  }
  if (!Array.isArray(gate.shipped) || gate.shipped.length === 0) {
    throw new Error("Reconciliation report has no shipped tester payload");
  }

  const commitShas = new Set(gate.commits.map((commit) => commit.sha));
  const entryShas = new Set(gate.entries.map((entry) => entry.commit));
  const shaPattern = /^[0-9a-f]{40}$/;
  if (
    commitShas.size !== gate.commits.length
    || entryShas.size !== gate.entries.length
    || [...commitShas].some((sha) => !shaPattern.test(sha))
    || [...entryShas].some((sha) => !shaPattern.test(sha))
    || [...commitShas].some((sha) => !entryShas.has(sha))
  ) {
    throw new Error("Reconciliation commit and classification sets do not match");
  }

  const dispositions = new Set(["ship", "exclude", "release-operation"]);
  if (gate.entries.some((entry) => !dispositions.has(entry.disposition))) {
    throw new Error("Reconciliation report contains an invalid commit disposition");
  }
  if (
    gate.manifestSource?.kind !== "github-issue"
    || !gate.manifestSource.repository
    || !Number.isInteger(gate.manifestSource.issueNumber)
    || !gate.manifestSource.issueUrl
    || gate.manifestSource.baselineTag !== gate.baseRef
    || gate.manifestSource.baselineSha !== gate.baselineSha
    || gate.manifestSource.candidateSha !== gate.candidateSha
  ) {
    throw new Error("Reconciliation must identify its GitHub issue manifest source");
  }
  if (gate.manifestSource.entriesSha256 !== entriesSha256(gate.entries)) {
    throw new Error("Reconciliation manifest source hash does not match its classifications");
  }
  const shippedEntryShas = new Set(
    gate.entries
      .filter((entry) => entry.disposition === "ship")
      .map((entry) => entry.commit),
  );
  const shippedReportShas = new Set(gate.shipped.map((entry) => entry.commit));
  if (
    shippedEntryShas.size !== shippedReportShas.size
    || [...shippedEntryShas].some((sha) => !shippedReportShas.has(sha))
  ) {
    throw new Error("Reconciliation shipped payload set does not match its classifications");
  }

  if (!whatToTest) {
    throw new Error("Passing reconciled TestFlight What to Test copy is required");
  }
  const actualHash = sha256(whatToTest.trim());
  if (gate.whatToTestSha256 !== actualHash) {
    throw new Error("What to Test copy does not match the reconciled manifest output");
  }

  return gate;
}

function readReconciliationGate(options, whatToTest) {
  if (!options.reconciliationFile) {
    throw new Error(
      "--reconciliation-file is required; generate it with scripts/testflight-manifest.mjs snapshot",
    );
  }
  if (!fs.existsSync(options.reconciliationFile)) {
    throw new Error(`Reconciliation file not found: ${options.reconciliationFile}`);
  }

  const gate = JSON.parse(fs.readFileSync(options.reconciliationFile, "utf8"));
  const candidateSha = execFileSync("git", ["rev-parse", "HEAD"], {
    encoding: "utf8",
  }).trim();
  return validateReconciliationGate({
    gate,
    buildNumber: options.buildNumber,
    candidateSha,
    whatToTest,
  });
}

function loadEnv(path) {
  if (!path || !fs.existsSync(path)) return;
  const text = fs.readFileSync(path, "utf8");
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const index = line.indexOf("=");
    const key = line.slice(0, index).trim();
    let value = line.slice(index + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = value;
  }
}

function readBuildNumber(projectPath) {
  const text = fs.readFileSync(projectPath, "utf8");
  const match = text.match(/CURRENT_PROJECT_VERSION:\s*["']?([^"'\n]+)["']?/);
  if (!match) throw new Error(`Could not find CURRENT_PROJECT_VERSION in ${projectPath}`);
  return match[1].trim();
}

function readArchiveValue(plistPath, keyPath) {
  try {
    return execFileSync("/usr/libexec/PlistBuddy", ["-c", `Print ${keyPath}`, plistPath], {
      encoding: "utf8",
    }).trim();
  } catch {
    return null;
  }
}

function readArchiveUploadMetadata(archivePath) {
  if (!archivePath) return null;
  const plistPath = `${archivePath.replace(/\/$/, "")}/Info.plist`;
  if (!fs.existsSync(plistPath)) {
    throw new Error(`Archive Info.plist not found at ${plistPath}`);
  }

  return {
    archivedBuildNumber: readArchiveValue(plistPath, ":ApplicationProperties:CFBundleVersion"),
    uploadedBuildNumber: readArchiveValue(plistPath, ":Distributions:0:uploadedBuildNumber"),
  };
}

function resolveUploadedBuildNumber(options) {
  const metadata = readArchiveUploadMetadata(options.archivePath);
  if (!metadata) return;

  if (
    metadata.archivedBuildNumber &&
    String(metadata.archivedBuildNumber) !== String(options.buildNumber)
  ) {
    console.log(
      `Archive CFBundleVersion is ${metadata.archivedBuildNumber}; requested helper build number is ${options.buildNumber}.`,
    );
  }

  if (!metadata.uploadedBuildNumber) {
    console.log("Archive has no uploadedBuildNumber yet; using requested build number.");
    return;
  }

  if (String(metadata.uploadedBuildNumber) === String(options.buildNumber)) {
    console.log(`Archive upload metadata confirms build ${metadata.uploadedBuildNumber}.`);
    return;
  }

  console.log(
    `Archive upload metadata says App Store Connect uploaded build ${metadata.uploadedBuildNumber}, not ${options.buildNumber}. Processing uploaded build ${metadata.uploadedBuildNumber}.`,
  );
  options.buildNumber = String(metadata.uploadedBuildNumber);
}

function readWhatToTest(options) {
  const value = options.whatToTestFile
    ? fs.readFileSync(options.whatToTestFile, "utf8")
    : options.whatToTest;
  if (!value) return null;

  const trimmed = value.trim();
  if (!trimmed) return null;
  if (trimmed.length > 4000) {
    throw new Error("TestFlight What to Test copy must be 4000 characters or fewer");
  }
  return trimmed;
}

function base64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

function derToJose(signature, keySize = 32) {
  let offset = 0;
  if (signature[offset] !== 0x30) throw new Error("Invalid DER signature");
  offset += 1;

  let sequenceLength = signature[offset];
  offset += 1;
  if (sequenceLength & 0x80) {
    const bytes = sequenceLength & 0x7f;
    sequenceLength = 0;
    for (let i = 0; i < bytes; i += 1) {
      sequenceLength = (sequenceLength << 8) | signature[offset];
      offset += 1;
    }
  }

  if (signature[offset] !== 0x02) throw new Error("Invalid DER r");
  offset += 1;
  const rLength = signature[offset];
  offset += 1;
  let r = signature.subarray(offset, offset + rLength);
  offset += rLength;

  if (signature[offset] !== 0x02) throw new Error("Invalid DER s");
  offset += 1;
  const sLength = signature[offset];
  offset += 1;
  let s = signature.subarray(offset, offset + sLength);

  const normalize = (part) => {
    while (part.length > keySize && part[0] === 0) part = part.subarray(1);
    if (part.length > keySize) throw new Error("Invalid ECDSA integer length");
    if (part.length === keySize) return part;
    return Buffer.concat([Buffer.alloc(keySize - part.length), part]);
  };

  return Buffer.concat([normalize(r), normalize(s)]);
}

function createToken() {
  const keyId = process.env.ASC_KEY_ID;
  const issuerId = process.env.ASC_ISSUER_ID;
  const keyPath = process.env.ASC_KEY_PATH;
  if (!keyId || !issuerId || !keyPath) {
    throw new Error("Missing ASC_KEY_ID, ASC_ISSUER_ID, or ASC_KEY_PATH");
  }

  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = { iss: issuerId, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const privateKey = fs.readFileSync(keyPath, "utf8");
  const derSignature = crypto.createSign("SHA256").update(signingInput).sign(privateKey);
  return `${signingInput}.${base64url(derToJose(derSignature))}`;
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function createClient(apiBase, token) {
  return async function api(path, options = {}) {
    const response = await fetch(`${apiBase}${path}`, {
      ...options,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        ...(options.headers ?? {}),
      },
    });

    const text = await response.text();
    let body = null;
    if (text) {
      try {
        body = JSON.parse(text);
      } catch {
        body = { raw: text };
      }
    }

    if (!response.ok) {
      const error = new Error(`ASC ${response.status} ${response.statusText} for ${path}`);
      error.status = response.status;
      error.body = body;
      throw error;
    }
    return body;
  };
}

async function getLatestBuild(api, appId, buildNumber) {
  const params = new URLSearchParams({
    "filter[app]": appId,
    "filter[version]": buildNumber,
    sort: "-uploadedDate",
    limit: "1",
    "fields[builds]": "version,processingState,usesNonExemptEncryption,uploadedDate,expired",
    include: "preReleaseVersion",
    "fields[preReleaseVersions]": "version",
  });
  const body = await api(`/builds?${params.toString()}`);
  const build = body.data?.[0] ?? null;
  if (!build) return null;
  const preRelease = body.included?.find((item) => item.type === "preReleaseVersions");
  build.marketingVersion = preRelease?.attributes?.version;
  return build;
}

async function waitForBuild(api, options) {
  for (let attempt = 1; attempt <= options.timeoutAttempts; attempt += 1) {
    const build = await getLatestBuild(api, options.appId, options.buildNumber);
    if (!build) {
      console.log(
        `Build (${options.buildNumber}) not visible yet; waiting... ${attempt}/${options.timeoutAttempts}`,
      );
      await sleep(options.pollSeconds * 1000);
      continue;
    }

    const attrs = build.attributes ?? {};
    const version = build.marketingVersion ? `${build.marketingVersion} ` : "";
    console.log(`Build ${version}(${attrs.version ?? options.buildNumber}) id=${build.id} processing=${attrs.processingState}`);
    if (attrs.processingState === "VALID") return build;
    await sleep(options.pollSeconds * 1000);
  }
  throw new Error(`Build (${options.buildNumber}) did not become VALID in time.`);
}

async function setExportCompliance(api, build) {
  if (build.attributes?.usesNonExemptEncryption === false) {
    console.log("Export compliance already set to usesNonExemptEncryption=false.");
    return;
  }

  try {
    await api(`/builds/${build.id}`, {
      method: "PATCH",
      body: JSON.stringify({
        data: {
          type: "builds",
          id: build.id,
          attributes: { usesNonExemptEncryption: false },
        },
      }),
    });
    console.log("Set export compliance to usesNonExemptEncryption=false.");
  } catch (error) {
    if (error.status === 409 || error.status === 422) {
      console.log(`Export compliance patch skipped: ${JSON.stringify(error.body?.errors?.[0] ?? error.body)}`);
      return;
    }
    throw error;
  }
}

async function getBetaBuildLocalization(api, buildId, locale) {
  const params = new URLSearchParams({
    "fields[betaBuildLocalizations]": "locale,whatsNew",
    limit: "200",
  });
  const body = await api(`/builds/${buildId}/betaBuildLocalizations?${params.toString()}`);
  return body.data?.find((localization) => localization.attributes?.locale === locale) ?? null;
}

async function setWhatToTest(api, build, locale, whatsNew) {
  if (!whatsNew) {
    console.log("No TestFlight What to Test copy provided.");
    return null;
  }

  const existing = await getBetaBuildLocalization(api, build.id, locale);
  if (existing) {
    if (existing.attributes?.whatsNew === whatsNew) {
      console.log(`TestFlight What to Test copy already set for ${locale}.`);
      return existing;
    }

    const body = await api(`/betaBuildLocalizations/${existing.id}`, {
      method: "PATCH",
      body: JSON.stringify({
        data: {
          type: "betaBuildLocalizations",
          id: existing.id,
          attributes: {
            whatsNew,
          },
        },
      }),
    });
    console.log(`Updated TestFlight What to Test copy for ${locale}.`);
    return body.data ?? null;
  }

  try {
    const body = await api("/betaBuildLocalizations", {
      method: "POST",
      body: JSON.stringify({
        data: {
          type: "betaBuildLocalizations",
          attributes: {
            locale,
            whatsNew,
          },
          relationships: {
            build: { data: { type: "builds", id: build.id } },
          },
        },
      }),
    });
    console.log(`Created TestFlight What to Test copy for ${locale}.`);
    return body.data ?? null;
  } catch (error) {
    const code = error.body?.errors?.[0]?.code;
    if (error.status === 409 || code === "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE") {
      const duplicate = await getBetaBuildLocalization(api, build.id, locale);
      if (!duplicate) throw error;
      const body = await api(`/betaBuildLocalizations/${duplicate.id}`, {
        method: "PATCH",
        body: JSON.stringify({
          data: {
            type: "betaBuildLocalizations",
            id: duplicate.id,
            attributes: {
              whatsNew,
            },
          },
        }),
      });
      console.log(`Updated existing TestFlight What to Test copy for ${locale}.`);
      return body.data ?? null;
    }
    throw error;
  }
}

async function getBetaGroup(api, appId, groupName) {
  const findGroup = async (name) => {
    const params = new URLSearchParams({
      "filter[app]": appId,
      "filter[name]": name,
      limit: "1",
    });
    const body = await api(`/betaGroups?${params.toString()}`);
    return body.data?.[0] ?? null;
  };

  let resolvedName = groupName;
  let group = await findGroup(groupName);
  if (!group && groupName === "rec.me Alpha") {
    resolvedName = "Wander Alpha";
    group = await findGroup(resolvedName);
    if (group) console.log("Using legacy Wander Alpha group; finish the App Store brand cutover.");
  }
  if (!group) throw new Error(`Missing beta group: ${groupName}`);
  console.log(`Beta group ${resolvedName} id=${group.id}`);
  group.resolvedName = resolvedName;
  return group;
}

async function attachBuildToGroup(api, build, group, groupName) {
  try {
    await api(`/betaGroups/${group.id}/relationships/builds`, {
      method: "POST",
      body: JSON.stringify({
        data: [{ type: "builds", id: build.id }],
      }),
    });
    console.log(`Attached build ${build.attributes?.version ?? build.id} to ${groupName}.`);
  } catch (error) {
    const code = error.body?.errors?.[0]?.code;
    if (error.status === 409 || code === "ENTITY_ERROR.ATTRIBUTE.INVALID.DUPLICATE") {
      console.log(`Build ${build.attributes?.version ?? build.id} is already attached to ${groupName}.`);
      return;
    }
    throw error;
  }
}

async function submitForReview(api, build) {
  try {
    await api("/betaAppReviewSubmissions", {
      method: "POST",
      body: JSON.stringify({
        data: {
          type: "betaAppReviewSubmissions",
          relationships: {
            build: { data: { type: "builds", id: build.id } },
          },
        },
      }),
    });
    console.log(`Submitted build ${build.attributes?.version ?? build.id} for external TestFlight review.`);
  } catch (error) {
    const code = error.body?.errors?.[0]?.code;
    if (error.status === 409 || error.status === 422 || code?.includes("DUPLICATE")) {
      console.log(`Review submission skipped: ${JSON.stringify(error.body?.errors?.[0] ?? error.body)}`);
      return;
    }
    throw error;
  }
}

async function getBuildSummary(api, buildId) {
  const params = new URLSearchParams({
    "fields[builds]": "version,processingState,usesNonExemptEncryption,uploadedDate,expired",
    include: "preReleaseVersion",
    "fields[preReleaseVersions]": "version",
  });
  return api(`/builds/${buildId}?${params.toString()}`);
}

async function getReviewSubmission(api, buildId) {
  try {
    const body = await api(`/builds/${buildId}/betaAppReviewSubmission`);
    return body.data ?? null;
  } catch (error) {
    if (error.status === 404) return null;
    throw error;
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printUsage();
    return;
  }

  if (!options.buildNumber) {
    options.buildNumber = readBuildNumber(options.projectPath);
  }
  resolveUploadedBuildNumber(options);
  const whatToTest = readWhatToTest(options);
  const reconciliation = readReconciliationGate(options, whatToTest);
  const manifestVerification = await verifyManifestSourceCurrent({
    source: reconciliation.manifestSource,
    commits: reconciliation.commits,
  });

  loadEnv(options.envPath);

  const resolved = {
    appId: options.appId,
    archivePath: options.archivePath,
    buildNumber: options.buildNumber,
    envPath: options.envPath,
    groupName: options.groupName,
    locale: options.locale,
    pollSeconds: options.pollSeconds,
    projectPath: options.projectPath,
    publicLink: options.publicLink,
    reconciliation: {
      baseline: reconciliation.baseRef,
      baselineSha: reconciliation.baselineSha,
      candidateSha: reconciliation.candidateSha,
      classifiedCommits: reconciliation.entries.length,
      manifestIssue: manifestVerification.issueUrl,
      shippedPayloads: reconciliation.shipped.length,
    },
    timeoutAttempts: options.timeoutAttempts,
    whatToTest: whatToTest ? `${whatToTest.length} chars` : null,
  };

  if (options.dryRun) {
    console.log(JSON.stringify({ dryRun: true, resolved }, null, 2));
    return;
  }

  const token = createToken();
  const api = createClient(DEFAULTS.apiBase, token);

  const build = await waitForBuild(api, options);
  await setExportCompliance(api, build);
  await setWhatToTest(api, build, options.locale, whatToTest);
  const group = await getBetaGroup(api, options.appId, options.groupName);
  await attachBuildToGroup(api, build, group, group.resolvedName ?? options.groupName);
  await submitForReview(api, build);

  const summary = await getBuildSummary(api, build.id);
  const reviewSubmission = await getReviewSubmission(api, build.id);
  console.log(JSON.stringify({
    buildId: build.id,
    attributes: summary.data?.attributes,
    marketingVersion: summary.included?.find((item) => item.type === "preReleaseVersions")?.attributes?.version,
    publicLink: options.publicLink,
    review: reviewSubmission ? {
      id: reviewSubmission.id,
      state: reviewSubmission.attributes?.betaReviewState,
    } : null,
  }, null, 2));
}

const isMain = process.argv[1]
  && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;

if (isMain) {
  main().catch((error) => {
    console.error(error.message);
    if (error.body) console.error(JSON.stringify(error.body, null, 2));
    process.exitCode = 1;
  });
}
