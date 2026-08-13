#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";

const DEFAULTS = {
  apiBase: "https://api.appstoreconnect.apple.com/v1",
  appId: "6776850787",
  envPath: "/Users/joelipshutz/.openclaw/workspace/.env.keys",
  version: "1.0",
};

const COPY = {
  subtitle: "Places from people you trust",
  privacyPolicyUrl: "https://getrec.me/privacy",
  privacyChoicesUrl: "https://getrec.me/privacy-choices",
  promotionalText: "Remember places worth returning to—and find your next one through people you trust.",
  keywords: "map,friends,restaurants,travel,save,discover,lists,checkin,local,food,cafes,bars,hikes,trip",
  marketingUrl: "https://getrec.me/",
  supportUrl: "https://getrec.me/support",
  description: `Find places through people you trust—not anonymous ratings.

rec.me turns real experiences from friends into a living map you can actually use. See where your people went, what they thought, and what fits the moment when you need a place now.

WITH REC.ME, YOU CAN

• See places your friends have actually visited

• Search your trusted map in natural language

• Save restaurants, bars, coffee shops, hikes, shops, and more

• Keep the notes and context that make a place worth remembering

• Organize places into lists and make plans together

• Control who can see what you share

Your map gets more useful with every memory—and every person you trust.

Need help? Visit https://getrec.me/support

Privacy: https://getrec.me/privacy

Terms: https://getrec.me/terms`,
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

function resource(type, id, attributes) {
  return { data: { type, id, attributes } };
}

function relationship(type, id) {
  return { data: { type, id } };
}

function pickCategory(categories, id) {
  const category = categories.find((candidate) => candidate.id === id);
  if (!category) throw new Error(`App Store category not found: ${id}`);
  return category;
}

function summarize(resourceValue) {
  return { id: resourceValue.id, ...resourceValue.attributes };
}

async function resolveState(api, options) {
  const [infos, versions, categories] = await Promise.all([
    api(`/apps/${options.appId}/appInfos?limit=10`),
    api(`/apps/${options.appId}/appStoreVersions?filter[versionString]=${encodeURIComponent(options.version)}&filter[platform]=IOS&limit=10`),
    api("/appCategories?limit=200"),
  ]);
  const info = infos.data?.find((candidate) => candidate.attributes?.appStoreState === "PREPARE_FOR_SUBMISSION")
    ?? infos.data?.[0];
  const version = versions.data?.find((candidate) => candidate.attributes?.versionString === options.version);
  if (!info) throw new Error("No editable App Store app info found");
  if (!version) throw new Error(`No iOS App Store version ${options.version} found`);

  const [infoLocalizations, versionLocalizations, primaryCategory, secondaryCategory] = await Promise.all([
    api(`/appInfos/${info.id}/appInfoLocalizations?limit=50`),
    api(`/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=50`),
    api(`/appInfos/${info.id}/primaryCategory`).catch(() => ({ data: null })),
    api(`/appInfos/${info.id}/secondaryCategory`).catch(() => ({ data: null })),
  ]);
  const infoLocalization = infoLocalizations.data?.find((candidate) => candidate.attributes?.locale === "en-US");
  const versionLocalization = versionLocalizations.data?.find((candidate) => candidate.attributes?.locale === "en-US");
  if (!infoLocalization || !versionLocalization) throw new Error("Missing editable en-US localization");

  return {
    info,
    version,
    infoLocalization,
    versionLocalization,
    primaryCategory: primaryCategory.data,
    secondaryCategory: secondaryCategory.data,
    desiredPrimaryCategory: pickCategory(categories.data ?? [], "SOCIAL_NETWORKING"),
    desiredSecondaryCategory: pickCategory(categories.data ?? [], "TRAVEL"),
  };
}

function plan(state) {
  return {
    appInfoLocalization: {
      id: state.infoLocalization.id,
      before: {
        subtitle: state.infoLocalization.attributes?.subtitle ?? null,
        privacyPolicyUrl: state.infoLocalization.attributes?.privacyPolicyUrl ?? null,
        privacyChoicesUrl: state.infoLocalization.attributes?.privacyChoicesUrl ?? null,
      },
      after: {
        subtitle: COPY.subtitle,
        privacyPolicyUrl: COPY.privacyPolicyUrl,
        privacyChoicesUrl: COPY.privacyChoicesUrl,
      },
    },
    versionLocalization: {
      id: state.versionLocalization.id,
      before: summarize(state.versionLocalization),
      after: {
        locale: "en-US",
        description: COPY.description,
        keywords: COPY.keywords,
        marketingUrl: COPY.marketingUrl,
        promotionalText: COPY.promotionalText,
        supportUrl: COPY.supportUrl,
      },
    },
    version: {
      id: state.version.id,
      versionString: state.version.attributes?.versionString,
      beforeReleaseType: state.version.attributes?.releaseType ?? null,
      afterReleaseType: "MANUAL",
    },
    categories: {
      before: {
        primary: state.primaryCategory?.id ?? null,
        secondary: state.secondaryCategory?.id ?? null,
      },
      after: {
        primary: state.desiredPrimaryCategory.id,
        secondary: state.desiredSecondaryCategory.id,
      },
    },
  };
}

async function applyPlan(api, state) {
  await api(`/appInfoLocalizations/${state.infoLocalization.id}`, {
    method: "PATCH",
    body: resource("appInfoLocalizations", state.infoLocalization.id, {
      subtitle: COPY.subtitle,
      privacyPolicyUrl: COPY.privacyPolicyUrl,
      privacyChoicesUrl: COPY.privacyChoicesUrl,
    }),
  });
  await api(`/appStoreVersionLocalizations/${state.versionLocalization.id}`, {
    method: "PATCH",
    body: resource("appStoreVersionLocalizations", state.versionLocalization.id, {
      description: COPY.description,
      keywords: COPY.keywords,
      marketingUrl: COPY.marketingUrl,
      promotionalText: COPY.promotionalText,
      supportUrl: COPY.supportUrl,
    }),
  });
  await api(`/appStoreVersions/${state.version.id}`, {
    method: "PATCH",
    body: resource("appStoreVersions", state.version.id, { releaseType: "MANUAL" }),
  });
  await api(`/appInfos/${state.info.id}/relationships/primaryCategory`, {
    method: "PATCH",
    body: relationship("appCategories", state.desiredPrimaryCategory.id),
  });
  await api(`/appInfos/${state.info.id}/relationships/secondaryCategory`, {
    method: "PATCH",
    body: relationship("appCategories", state.desiredSecondaryCategory.id),
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log("Usage: node scripts/app-store-metadata-release.mjs [--apply] [--app-id <id>] [--version <version>] [--env <path>]");
    console.log("Defaults to a read-only dry run. Pass --apply to update only reversible product-page metadata.");
    return;
  }
  loadEnv(options.envPath);
  const api = createClient(createToken());
  const before = await resolveState(api, options);
  console.log(JSON.stringify({ mode: options.apply ? "apply" : "dry-run", plan: plan(before) }, null, 2));
  if (!options.apply) return;

  await applyPlan(api, before);
  const after = await resolveState(api, options);
  const verification = plan(after);
  const expected = {
    appInfoLocalization: verification.appInfoLocalization.after,
    versionLocalization: verification.versionLocalization.after,
    releaseType: verification.version.afterReleaseType,
    categories: verification.categories.after,
  };
  const actual = {
    appInfoLocalization: verification.appInfoLocalization.before,
    versionLocalization: {
      locale: after.versionLocalization.attributes?.locale,
      description: after.versionLocalization.attributes?.description,
      keywords: after.versionLocalization.attributes?.keywords,
      marketingUrl: after.versionLocalization.attributes?.marketingUrl,
      promotionalText: after.versionLocalization.attributes?.promotionalText,
      supportUrl: after.versionLocalization.attributes?.supportUrl,
    },
    releaseType: after.version.attributes?.releaseType,
    categories: verification.categories.before,
  };
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(`Post-apply verification failed: ${JSON.stringify({ expected, actual })}`);
  }
  console.log(JSON.stringify({ applied: true, verified: actual }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  if (error.body) console.error(JSON.stringify(error.body, null, 2));
  process.exitCode = 1;
});
