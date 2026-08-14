#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";

const DEFAULTS = {
  apiBase: "https://api.appstoreconnect.apple.com/v1",
  appId: "6776850787",
  envPath: "/Users/joelipshutz/.openclaw/workspace/.env.keys",
};

function parseArgs(argv) {
  const options = { appId: DEFAULTS.appId, envPath: DEFAULTS.envPath };
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
    const response = await fetch(`${options.apiBase ?? DEFAULTS.apiBase}${path}`, {
      headers: { Authorization: `Bearer ${token}` },
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
    if ([403, 404].includes(error.status)) {
      return { unavailable: true, status: error.status };
    }
    throw error;
  }
}

function compact(resources) {
  return (resources?.data ?? []).map((item) => ({
    id: item.id,
    type: item.type,
    ...item.attributes,
  }));
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log("Usage: node scripts/app-store-readiness-audit.mjs [--app-id <id>] [--env <path>]");
    return;
  }
  loadEnv(options.envPath);
  const api = createClient(createToken());

  const app = await api(
    `/apps/${options.appId}?fields[apps]=name,bundleId,sku,primaryLocale,isOrEverWasMadeForKids,contentRightsDeclaration,accessibilityUrl`,
  );
  const versions = await api(
    `/apps/${options.appId}/appStoreVersions?limit=20&fields[appStoreVersions]=versionString,appStoreState,platform,createdDate,releaseType,earliestReleaseDate`,
  );
  const builds = await api(
    `/builds?filter[app]=${options.appId}&limit=10&sort=-uploadedDate&include=preReleaseVersion&fields[builds]=version,uploadedDate,processingState,expired,usesNonExemptEncryption,minOsVersion,preReleaseVersion&fields[preReleaseVersions]=version,platform`,
  );
  const infos = await api(
    `/apps/${options.appId}/appInfos?limit=10&fields[appInfos]=appStoreState,appStoreAgeRating,brazilAgeRating`,
  );
  const availability = await optional(
    api,
    `/apps/${options.appId}/appAvailabilityV2?include=territoryAvailabilities&limit[territoryAvailabilities]=50`,
  );
  const priceSchedule = await optional(
    api,
    `/apps/${options.appId}/appPriceSchedule?include=baseTerritory,manualPrices&limit[manualPrices]=50`,
  );
  const usaPricePoints = await optional(
    api,
    `/apps/${options.appId}/appPricePoints?filter[territory]=USA&include=territory&limit=200`,
  );
  const availabilityTerritories = availability.data
    ? await optional(
        api,
        `/appAvailabilities/${availability.data.id}/territoryAvailabilities?include=territory&limit=200`,
        { apiBase: "https://api.appstoreconnect.apple.com/v2" },
      )
    : availability;
  const manualAppPrices = priceSchedule.data
    ? await optional(
        api,
        `/appPriceSchedules/${priceSchedule.data.id}/manualPrices?include=appPricePoint,territory&limit=200`,
      )
    : priceSchedule;

  const versionDetails = [];
  for (const version of versions.data ?? []) {
    const localizations = await optional(
      api,
      `/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=50&fields[appStoreVersionLocalizations]=locale,description,keywords,marketingUrl,promotionalText,supportUrl,whatsNew`,
    );
    const localizationDetails = [];
    for (const localization of localizations.data ?? []) {
      const screenshotSets = await optional(
        api,
        `/appStoreVersionLocalizations/${localization.id}/appScreenshotSets?limit=50&include=appScreenshots&fields[appScreenshotSets]=screenshotDisplayType&fields[appScreenshots]=fileName,fileSize,sourceFileChecksum,assetDeliveryState`,
      );
      const screenshotCount = screenshotSets.included?.filter(
        (item) => item.type === "appScreenshots",
      ).length ?? 0;
      localizationDetails.push({
        id: localization.id,
        locale: localization.attributes?.locale,
        screenshotCount,
        screenshotSets: compact(screenshotSets),
      });
    }
    const reviewDetail = await optional(
      api,
      `/appStoreVersions/${version.id}/appStoreReviewDetail?fields[appStoreReviewDetails]=contactFirstName,contactLastName,contactPhone,contactEmail,demoAccountName,demoAccountRequired,notes`,
    );
    versionDetails.push({
      id: version.id,
      versionString: version.attributes?.versionString,
      state: version.attributes?.appStoreState,
      localizations: compact(localizations),
      localizationDetails,
      localizationCount: localizations.data?.length ?? 0,
      reviewDetail: reviewDetail.data
        ? {
            id: reviewDetail.data.id,
            ...reviewDetail.data.attributes,
            demoAccountName: reviewDetail.data.attributes?.demoAccountName ? "<configured>" : null,
            contactEmail: reviewDetail.data.attributes?.contactEmail ? "<configured>" : null,
            contactPhone: reviewDetail.data.attributes?.contactPhone ? "<configured>" : null,
          }
        : reviewDetail,
    });
  }

  const infoDetails = [];
  for (const info of infos.data ?? []) {
    const localizations = await optional(
      api,
      `/appInfos/${info.id}/appInfoLocalizations?limit=50&fields[appInfoLocalizations]=locale,name,subtitle,privacyPolicyUrl,privacyChoicesUrl`,
    );
    const categories = await optional(api, `/appInfos/${info.id}/primaryCategory`);
    const secondaryCategory = await optional(api, `/appInfos/${info.id}/secondaryCategory`);
    const ageRatingDeclaration = await optional(
      api,
      `/appInfos/${info.id}/ageRatingDeclaration`,
    );
    const territoryAgeRatings = await optional(
      api,
      `/appInfos/${info.id}/territoryAgeRatings?limit=200`,
    );
    infoDetails.push({
      id: info.id,
      ...info.attributes,
      localizations: compact(localizations),
      primaryCategory: categories.data?.id ?? null,
      secondaryCategory: secondaryCategory.data?.id ?? null,
      ageRatingDeclaration: ageRatingDeclaration.data
        ? {
            id: ageRatingDeclaration.data.id,
            ...ageRatingDeclaration.data.attributes,
          }
        : ageRatingDeclaration,
      territoryAgeRatings: compact(territoryAgeRatings),
    });
  }

  console.log(JSON.stringify({
    auditedAt: new Date().toISOString(),
    app: { id: app.data.id, ...app.data.attributes },
    availability: availability.data
      ? {
          id: availability.data.id,
          ...availability.data.attributes,
          territoryCount: availabilityTerritories.data?.length ?? null,
          availableTerritories: (availabilityTerritories.data ?? [])
            .filter((item) => item.attributes?.available)
            .map((item) => item.relationships?.territory?.data?.id)
            .filter(Boolean)
            .sort(),
          preOrderTerritories: (availabilityTerritories.data ?? [])
            .filter((item) => item.attributes?.preOrderEnabled)
            .map((item) => item.relationships?.territory?.data?.id)
            .filter(Boolean)
            .sort(),
        }
      : availability,
    priceSchedule: priceSchedule.data
      ? {
          id: priceSchedule.data.id,
          ...priceSchedule.data.attributes,
          included: compact({ data: priceSchedule.included ?? [] }),
          manualPrices: (manualAppPrices.data ?? []).map((price) => {
            const pricePointId = price.relationships?.appPricePoint?.data?.id;
            const territoryId = price.relationships?.territory?.data?.id;
            const pricePoint = manualAppPrices.included?.find(
              (item) => item.type === "appPricePoints" && item.id === pricePointId,
            );
            return {
              territory: territoryId ?? null,
              customerPrice: pricePoint?.attributes?.customerPrice ?? null,
              startDate: price.attributes?.startDate ?? null,
              endDate: price.attributes?.endDate ?? null,
            };
          }),
        }
      : priceSchedule,
    usaPricePoints: usaPricePoints.data
      ? compact(usaPricePoints)
      : usaPricePoints,
    appInfos: infoDetails,
    versions: compact(versions),
    versionDetails,
    builds: compact(builds).map((build) => ({
      ...build,
      marketingVersion: builds.included?.find(
        (item) => item.type === "preReleaseVersions"
          && item.id === builds.data?.find((candidate) => candidate.id === build.id)
            ?.relationships?.preReleaseVersion?.data?.id,
      )?.attributes?.version ?? null,
    })),
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  if (error.body) console.error(JSON.stringify(error.body, null, 2));
  process.exitCode = 1;
});
