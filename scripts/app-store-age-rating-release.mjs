#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";

const DEFAULTS = {
  apiBase: "https://api.appstoreconnect.apple.com/v1",
  appId: "6776850787",
  envPath: "/Users/joelipshutz/.openclaw/workspace/.env.keys",
};

// These answers describe the release product, not hypothetical content a user
// might submit. rec.me contains profiles, place memories/photos, a social feed,
// likes, and comments/public posting inside a visibility-controlled social
// graph. It has no ads, embedded unrestricted browser, age gate, or mature/game
// content supplied by the app. Apple currently calculates 13+ from socialMedia.
const ANSWERS = {
  advertising: false,
  alcoholTobaccoOrDrugUseOrReferences: "NONE",
  contests: "NONE",
  gambling: false,
  gamblingSimulated: "NONE",
  gunsOrOtherWeapons: "NONE",
  healthOrWellnessTopics: false,
  lootBox: false,
  medicalOrTreatmentInformation: "NONE",
  messagingAndChat: true,
  parentalControls: false,
  profanityOrCrudeHumor: "NONE",
  ageAssurance: false,
  sexualContentGraphicAndNudity: "NONE",
  sexualContentOrNudity: "NONE",
  socialMedia: true,
  socialMediaAgeRestricted: false,
  horrorOrFearThemes: "NONE",
  matureOrSuggestiveThemes: "NONE",
  unrestrictedWebAccess: false,
  userGeneratedContent: true,
  violenceCartoonOrFantasy: "NONE",
  violenceRealisticProlongedGraphicOrSadistic: "NONE",
  violenceRealistic: "NONE",
  ageRatingOverrideV2: "NONE",
  koreaAgeRatingOverride: "NONE",
};

function parseArgs(argv) {
  const options = { appId: DEFAULTS.appId, envPath: DEFAULTS.envPath, apply: false };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) throw new Error(`Missing value after ${arg}`);
      return argv[index];
    };
    switch (arg) {
      case "--apply":
        options.apply = true;
        break;
      case "--app-id":
        options.appId = next();
        break;
      case "--env":
        options.envPath = next();
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }
  return options;
}

function loadEnv(path) {
  if (!path || !fs.existsSync(path)) return;
  const contents = fs.readFileSync(path, "utf8");
  for (const rawLine of contents.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const separator = line.indexOf("=");
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"'))
      || (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (!process.env[key]) process.env[key] = value;
  }
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
    for (let index = 0; index < bytes; index += 1) {
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

function createClient(token) {
  return async function api(path, options = {}) {
    const response = await fetch(`${DEFAULTS.apiBase}${path}`, {
      method: options.method ?? "GET",
      headers: {
        Authorization: `Bearer ${token}`,
        ...(options.body ? { "Content-Type": "application/json" } : {}),
      },
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    const text = await response.text();
    const body = text ? JSON.parse(text) : null;
    if (!response.ok) {
      const error = new Error(`ASC ${response.status} ${response.statusText} for ${path}`);
      error.body = body;
      throw error;
    }
    return body;
  };
}

function selectedAnswers(declaration) {
  return Object.fromEntries(Object.keys(ANSWERS).map((key) => [
    key,
    declaration.attributes?.[key] ?? null,
  ]));
}

async function resolveState(api, appId) {
  const infos = await api(`/apps/${appId}/appInfos?limit=10`);
  const info = infos.data?.find(
    (candidate) => candidate.attributes?.appStoreState === "PREPARE_FOR_SUBMISSION",
  ) ?? infos.data?.[0];
  if (!info) throw new Error("No App Store app info found");

  const [declaration, territoryRatings] = await Promise.all([
    api(`/appInfos/${info.id}/ageRatingDeclaration`),
    api(`/appInfos/${info.id}/territoryAgeRatings?limit=200`),
  ]);
  if (!declaration.data) throw new Error("No age rating declaration found");
  return { info, declaration: declaration.data, territoryRatings: territoryRatings.data ?? [] };
}

function summary(state) {
  return {
    appInfoId: state.info.id,
    declarationId: state.declaration.id,
    answers: selectedAnswers(state.declaration),
    territoryRatings: state.territoryRatings.map((rating) => ({
      id: rating.id,
      appStoreAgeRating: rating.attributes?.appStoreAgeRating,
    })),
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log("Usage: node scripts/app-store-age-rating-release.mjs [--apply] [--app-id <id>] [--env <path>]");
    console.log("Defaults to a read-only dry run. Pass --apply to submit and verify the evidence-backed questionnaire.");
    return;
  }

  loadEnv(options.envPath);
  const api = createClient(createToken());
  const before = await resolveState(api, options.appId);
  console.log(JSON.stringify({
    mode: options.apply ? "apply" : "dry-run",
    before: summary(before),
    after: { answers: ANSWERS },
  }, null, 2));
  if (!options.apply) return;

  await api(`/ageRatingDeclarations/${before.declaration.id}`, {
    method: "PATCH",
    body: {
      data: {
        type: "ageRatingDeclarations",
        id: before.declaration.id,
        attributes: ANSWERS,
      },
    },
  });

  const after = await resolveState(api, options.appId);
  const actual = selectedAnswers(after.declaration);
  if (JSON.stringify(actual) !== JSON.stringify(ANSWERS)) {
    throw new Error(`Post-apply verification failed: ${JSON.stringify({ expected: ANSWERS, actual })}`);
  }
  console.log(JSON.stringify({ applied: true, verified: summary(after) }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  if (error.body) console.error(JSON.stringify(error.body, null, 2));
  process.exitCode = 1;
});
