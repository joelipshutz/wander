#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";

const DEFAULTS = {
  apiBase: "https://api.appstoreconnect.apple.com/v1",
  appId: "6776850787",
  envPath: "/Users/joelipshutz/.openclaw/workspace/.env.keys",
  territory: "USA",
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
      case "--territory":
        options.territory = next().toUpperCase();
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
    const apiBase = options.apiBase ?? DEFAULTS.apiBase;
    const response = await fetch(`${apiBase}${path}`, {
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
      error.status = response.status;
      error.body = body;
      throw error;
    }
    return body;
  };
}

async function optional(api, path, options) {
  try {
    return await api(path, options);
  } catch (error) {
    if (error.status === 404) return null;
    throw error;
  }
}

async function resolveState(api, options) {
  const [priceSchedule, availability, pricePoints, territories] = await Promise.all([
    optional(api, `/apps/${options.appId}/appPriceSchedule?include=baseTerritory,manualPrices`),
    optional(api, `/apps/${options.appId}/appAvailabilityV2?include=territoryAvailabilities&limit[territoryAvailabilities]=50`),
    api(`/apps/${options.appId}/appPricePoints?filter[territory]=${options.territory}&include=territory&limit=200`),
    api("/territories?limit=200"),
  ]);
  const freePricePoint = pricePoints.data?.find(
    (candidate) => Number(candidate.attributes?.customerPrice) === 0,
  );
  if (!freePricePoint) throw new Error(`No free price point found for ${options.territory}`);
  const manualPrices = priceSchedule?.data
    ? await api(
        `/appPriceSchedules/${priceSchedule.data.id}/manualPrices?include=appPricePoint,territory&limit=200`,
      )
    : null;
  if (!(territories.data ?? []).some((territory) => territory.id === options.territory)) {
    throw new Error(`Unknown App Store territory: ${options.territory}`);
  }
  return {
    priceSchedule,
    availability,
    freePricePoint,
    manualPrices,
    territories: territories.data ?? [],
  };
}

function configuredManualPrices(state) {
  const included = state.manualPrices?.included ?? [];
  return (state.manualPrices?.data ?? []).map((price) => {
    const pricePointId = price.relationships?.appPricePoint?.data?.id;
    const territoryId = price.relationships?.territory?.data?.id;
    const pricePoint = included.find(
      (item) => item.type === "appPricePoints" && item.id === pricePointId,
    );
    return {
      territory: territoryId ?? null,
      customerPrice: pricePoint?.attributes?.customerPrice ?? null,
      startDate: price.attributes?.startDate ?? null,
      endDate: price.attributes?.endDate ?? null,
    };
  });
}

function hasFreeLaunchPrice(state, options) {
  return configuredManualPrices(state).some(
    (price) => price.territory === options.territory && Number(price.customerPrice) === 0,
  );
}

function plan(state, options) {
  return {
    appId: options.appId,
    launchTerritory: options.territory,
    price: {
      configured: Boolean(state.priceSchedule?.data),
      target: "FREE",
      baseTerritory: options.territory,
      freePricePointId: state.freePricePoint.id,
      configuredManualPrices: configuredManualPrices(state),
    },
    availability: {
      configured: Boolean(state.availability?.data),
      target: [options.territory],
      availableInNewTerritories: false,
      preOrderEnabled: false,
    },
  };
}

async function createFreePriceSchedule(api, state, options) {
  const priceId = "${launch-price}";
  await api("/appPriceSchedules", {
    method: "POST",
    body: {
      data: {
        type: "appPriceSchedules",
        relationships: {
          app: { data: { type: "apps", id: options.appId } },
          baseTerritory: { data: { type: "territories", id: options.territory } },
          manualPrices: { data: [{ type: "appPrices", id: priceId }] },
        },
      },
      included: [{
        type: "appPrices",
        id: priceId,
        attributes: { startDate: null },
        relationships: {
          appPricePoint: {
            data: { type: "appPricePoints", id: state.freePricePoint.id },
          },
        },
      }],
    },
  });
}

async function createAvailability(api, state, options) {
  const included = state.territories.map((territory) => {
    const availabilityId = `\${launch-availability-${territory.id}}`;
    return {
      type: "territoryAvailabilities",
      id: availabilityId,
      attributes: {
        available: territory.id === options.territory,
        preOrderEnabled: false,
      },
      relationships: {
        territory: { data: { type: "territories", id: territory.id } },
      },
    };
  });
  await api("/appAvailabilities", {
    apiBase: "https://api.appstoreconnect.apple.com/v2",
    method: "POST",
    body: {
      data: {
        type: "appAvailabilities",
        attributes: { availableInNewTerritories: false },
        relationships: {
          app: { data: { type: "apps", id: options.appId } },
          territoryAvailabilities: {
            data: included.map(({ type, id }) => ({ type, id })),
          },
        },
      },
      included,
    },
  });
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log("Usage: node scripts/app-store-commerce-release.mjs [--apply] [--app-id <id>] [--territory <id>] [--env <path>]");
    console.log("Defaults to a read-only US-first plan: free, no pre-order, and no automatic new territories.");
    return;
  }

  loadEnv(options.envPath);
  const api = createClient(createToken());
  const before = await resolveState(api, options);
  console.log(JSON.stringify({ mode: options.apply ? "apply" : "dry-run", plan: plan(before, options) }, null, 2));
  if (!options.apply) return;

  if (before.priceSchedule?.data && !hasFreeLaunchPrice(before, options)) {
    throw new Error("An existing price schedule is present, but its US launch price is not free");
  }

  if (!before.priceSchedule?.data) await createFreePriceSchedule(api, before, options);
  if (!before.availability?.data) await createAvailability(api, before, options);

  const after = await resolveState(api, options);
  if (!after.priceSchedule?.data || !after.availability?.data || !hasFreeLaunchPrice(after, options)) {
    throw new Error("Post-apply verification failed: price schedule or availability is still absent");
  }
  const territoryAvailabilities = await api(
    `/appAvailabilities/${after.availability.data.id}/territoryAvailabilities?include=territory&limit=200`,
    { apiBase: "https://api.appstoreconnect.apple.com/v2" },
  );
  const availableTerritories = (territoryAvailabilities.data ?? [])
    .filter((item) => item.attributes?.available)
    .map((item) => item.relationships?.territory?.data?.id)
    .filter(Boolean)
    .sort();
  if (
    after.availability.data.attributes?.availableInNewTerritories !== false
    || JSON.stringify(availableTerritories) !== JSON.stringify([options.territory])
  ) {
    throw new Error(`Post-apply availability verification failed: ${JSON.stringify({
      availableInNewTerritories: after.availability.data.attributes?.availableInNewTerritories,
      availableTerritories,
    })}`);
  }
  console.log(JSON.stringify({
    applied: true,
    verified: {
      priceScheduleId: after.priceSchedule.data.id,
      availabilityId: after.availability.data.id,
      price: "FREE",
      availableTerritories,
      availableInNewTerritories: false,
      preOrderEnabled: false,
    },
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  if (error.body) console.error(JSON.stringify(error.body, null, 2));
  process.exitCode = 1;
});
