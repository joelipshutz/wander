#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";

const DEFAULTS = {
  apiBase: "https://api.appstoreconnect.apple.com/v1",
  appId: "6776850787",
  envPath: "/Users/joelipshutz/.openclaw/workspace/.env.keys",
  notesPath: "docs/app-store/reviewer-notes.txt",
  version: "1.0",
};

function parseArgs(argv) {
  const options = { ...DEFAULTS, apply: false };
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
      case "--notes-file":
        options.notesPath = next();
        break;
      case "--version":
        options.version = next();
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

function env(name) {
  return process.env[name]?.trim() ?? "";
}

function parseBoolean(value, name) {
  if (["1", "true", "yes"].includes(value.toLowerCase())) return true;
  if (["0", "false", "no"].includes(value.toLowerCase())) return false;
  throw new Error(`${name} must be true/false, yes/no, or 1/0`);
}

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function desiredAttributes(options, requireComplete) {
  const notes = fs.readFileSync(options.notesPath, "utf8").trim();
  const demoRequiredRaw = env("ASC_REVIEW_DEMO_ACCOUNT_REQUIRED");
  const attributes = {
    contactFirstName: env("ASC_REVIEW_CONTACT_FIRST_NAME"),
    contactLastName: env("ASC_REVIEW_CONTACT_LAST_NAME"),
    contactPhone: env("ASC_REVIEW_CONTACT_PHONE"),
    contactEmail: env("ASC_REVIEW_CONTACT_EMAIL"),
    demoAccountRequired: demoRequiredRaw
      ? parseBoolean(demoRequiredRaw, "ASC_REVIEW_DEMO_ACCOUNT_REQUIRED")
      : true,
    notes,
  };

  if (attributes.demoAccountRequired) {
    attributes.demoAccountName = env("ASC_REVIEW_DEMO_ACCOUNT_NAME");
    attributes.demoAccountPassword = env("ASC_REVIEW_DEMO_ACCOUNT_PASSWORD");
  }

  if (requireComplete) {
    const required = [
      ["ASC_REVIEW_CONTACT_FIRST_NAME", attributes.contactFirstName],
      ["ASC_REVIEW_CONTACT_LAST_NAME", attributes.contactLastName],
      ["ASC_REVIEW_CONTACT_PHONE", attributes.contactPhone],
      ["ASC_REVIEW_CONTACT_EMAIL", attributes.contactEmail],
    ];
    if (attributes.demoAccountRequired) {
      required.push(
        ["ASC_REVIEW_DEMO_ACCOUNT_NAME", attributes.demoAccountName],
        ["ASC_REVIEW_DEMO_ACCOUNT_PASSWORD", attributes.demoAccountPassword],
      );
    }
    const missing = required.filter(([, value]) => !value).map(([name]) => name);
    if (missing.length > 0) throw new Error(`Missing required review environment values: ${missing.join(", ")}`);
  }
  return attributes;
}

function redacted(attributes) {
  if (!attributes) return null;
  return {
    contactFirstNameConfigured: Boolean(attributes.contactFirstName),
    contactLastNameConfigured: Boolean(attributes.contactLastName),
    contactPhoneConfigured: Boolean(attributes.contactPhone),
    contactEmailConfigured: Boolean(attributes.contactEmail),
    demoAccountRequired: attributes.demoAccountRequired ?? null,
    demoAccountNameConfigured: Boolean(attributes.demoAccountName),
    demoAccountPasswordConfigured: Boolean(attributes.demoAccountPassword),
    notesLength: attributes.notes?.length ?? 0,
    notesSha256: attributes.notes ? sha256(attributes.notes) : null,
  };
}

async function resolveState(api, options) {
  const versions = await api(
    `/apps/${options.appId}/appStoreVersions?filter[versionString]=${encodeURIComponent(options.version)}&filter[platform]=IOS&limit=10`,
  );
  const version = versions.data?.find(
    (candidate) => candidate.attributes?.versionString === options.version,
  );
  if (!version) throw new Error(`No iOS App Store version ${options.version} found`);

  const response = await api(
    `/appStoreVersions/${version.id}/appStoreReviewDetail?fields[appStoreReviewDetails]=contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountName,demoAccountPassword,demoAccountRequired,notes`,
  ).catch((error) => {
    if (error.body?.errors?.some((item) => item.status === "404")) return { data: null };
    throw error;
  });
  return { version, reviewDetail: response.data };
}

async function apply(api, state, attributes) {
  if (state.reviewDetail) {
    return api(`/appStoreReviewDetails/${state.reviewDetail.id}`, {
      method: "PATCH",
      body: {
        data: {
          type: "appStoreReviewDetails",
          id: state.reviewDetail.id,
          attributes,
        },
      },
    });
  }

  return api("/appStoreReviewDetails", {
    method: "POST",
    body: {
      data: {
        type: "appStoreReviewDetails",
        attributes,
        relationships: {
          appStoreVersion: {
            data: { type: "appStoreVersions", id: state.version.id },
          },
        },
      },
    },
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log("Usage: node scripts/app-store-review-release.mjs [--apply] [--app-id <id>] [--version <version>] [--env <path>] [--notes-file <path>]");
    console.log("Defaults to a read-only dry run. Review contact and demo credentials are read only from the local environment and are always redacted in output.");
    return;
  }

  loadEnv(options.envPath);
  const desired = desiredAttributes(options, options.apply);
  const api = createClient(createToken());
  const before = await resolveState(api, options);
  console.log(JSON.stringify({
    mode: options.apply ? "apply" : "dry-run",
    version: { id: before.version.id, versionString: before.version.attributes?.versionString },
    before: redacted(before.reviewDetail?.attributes),
    desired: redacted(desired),
  }, null, 2));
  if (!options.apply) return;

  await apply(api, before, desired);
  const after = await resolveState(api, options);
  if (!after.reviewDetail) throw new Error("Post-apply verification failed: review detail is still missing");

  const actual = after.reviewDetail.attributes ?? {};
  for (const [key, expected] of Object.entries(desired)) {
    if (actual[key] !== expected) throw new Error(`Post-apply verification failed for ${key}`);
  }
  console.log(JSON.stringify({ applied: true, verified: redacted(actual) }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  if (error.body) console.error(JSON.stringify(error.body, null, 2));
  process.exitCode = 1;
});
