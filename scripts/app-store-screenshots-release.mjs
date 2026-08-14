#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const DEFAULTS = {
  apiBase: "https://api.appstoreconnect.apple.com/v1",
  appId: "6776850787",
  displayType: "APP_IPHONE_67",
  envPath: "/Users/joelipshutz/.openclaw/workspace/.env.keys",
  locale: "en-US",
  screenshotsPath: "docs/app-store/concepts/v1",
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
      case "--display-type":
        options.displayType = next();
        break;
      case "--env":
        options.envPath = next();
        break;
      case "--locale":
        options.locale = next();
        break;
      case "--screenshots":
        options.screenshotsPath = next();
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

function loadEnv(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return;
  for (const rawLine of fs.readFileSync(filePath, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const separator = line.indexOf("=");
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"'))
      || (value.startsWith("'") && value.endsWith("'"))
    ) value = value.slice(1, -1);
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
    return part.length === keySize
      ? part
      : Buffer.concat([Buffer.alloc(keySize - part.length), part]);
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
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = { iss: issuerId, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const privateKey = fs.readFileSync(keyPath, "utf8");
  const signature = crypto.createSign("SHA256").update(signingInput).sign(privateKey);
  return `${signingInput}.${base64url(derToJose(signature))}`;
}

function createClient(token) {
  return async function api(resourcePath, options = {}) {
    const response = await fetch(`${DEFAULTS.apiBase}${resourcePath}`, {
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
      const error = new Error(`ASC ${response.status} ${response.statusText} for ${resourcePath}`);
      error.body = body;
      throw error;
    }
    return body;
  };
}

function pngMetadata(buffer, fileName) {
  const pngSignature = "89504e470d0a1a0a";
  if (buffer.subarray(0, 8).toString("hex") !== pngSignature) {
    throw new Error(`${fileName} is not a PNG`);
  }
  const width = buffer.readUInt32BE(16);
  const height = buffer.readUInt32BE(20);
  const colorType = buffer[25];
  const hasAlpha = colorType === 4 || colorType === 6 || buffer.includes(Buffer.from("tRNS"));
  if (hasAlpha) throw new Error(`${fileName} contains transparency`);
  return { width, height };
}

function loadScreenshots(directory) {
  const files = fs.readdirSync(directory)
    .filter((fileName) => /^\d{2}-.*\.png$/i.test(fileName))
    .sort();
  if (files.length < 1 || files.length > 10) {
    throw new Error(`Expected 1-10 ordered PNG screenshots, found ${files.length}`);
  }
  return files.map((fileName) => {
    const filePath = path.resolve(directory, fileName);
    const bytes = fs.readFileSync(filePath);
    const dimensions = pngMetadata(bytes, fileName);
    if (dimensions.width !== 1320 || dimensions.height !== 2868) {
      throw new Error(`${fileName} must be 1320x2868, got ${dimensions.width}x${dimensions.height}`);
    }
    return {
      bytes,
      fileName,
      filePath,
      fileSize: bytes.length,
      md5: crypto.createHash("md5").update(bytes).digest("hex"),
      ...dimensions,
    };
  });
}

async function resolveState(api, options) {
  const versions = await api(
    `/apps/${options.appId}/appStoreVersions?filter[versionString]=${encodeURIComponent(options.version)}&filter[platform]=IOS&limit=10`,
  );
  const version = versions.data?.find((item) => item.attributes?.versionString === options.version);
  if (!version) throw new Error(`No iOS App Store version ${options.version} found`);
  const localizations = await api(
    `/appStoreVersions/${version.id}/appStoreVersionLocalizations?filter[locale]=${encodeURIComponent(options.locale)}&limit=10`,
  );
  const localization = localizations.data?.find((item) => item.attributes?.locale === options.locale);
  if (!localization) throw new Error(`No ${options.locale} localization found for version ${options.version}`);
  const sets = await api(
    `/appStoreVersionLocalizations/${localization.id}/appScreenshotSets?filter[screenshotDisplayType]=${encodeURIComponent(options.displayType)}&limit=10`,
  );
  const screenshotSet = sets.data?.find(
    (item) => item.attributes?.screenshotDisplayType === options.displayType,
  ) ?? null;
  let screenshots = [];
  if (screenshotSet) {
    const response = await api(
      `/appScreenshotSets/${screenshotSet.id}/appScreenshots?fields[appScreenshots]=fileName,fileSize,sourceFileChecksum,imageAsset,assetDeliveryState&limit=10`,
    );
    screenshots = response.data ?? [];
  }
  return { localization, screenshotSet, screenshots, version };
}

async function createScreenshotSet(api, localizationId, displayType) {
  const response = await api("/appScreenshotSets", {
    method: "POST",
    body: {
      data: {
        type: "appScreenshotSets",
        attributes: { screenshotDisplayType: displayType },
        relationships: {
          appStoreVersionLocalization: {
            data: { type: "appStoreVersionLocalizations", id: localizationId },
          },
        },
      },
    },
  });
  return response.data;
}

async function uploadScreenshot(api, screenshotSetId, screenshot) {
  let reservation;
  try {
    const response = await api("/appScreenshots", {
      method: "POST",
      body: {
        data: {
          type: "appScreenshots",
          attributes: { fileName: screenshot.fileName, fileSize: screenshot.fileSize },
          relationships: {
            appScreenshotSet: {
              data: { type: "appScreenshotSets", id: screenshotSetId },
            },
          },
        },
      },
    });
    reservation = response.data;
    for (const operation of reservation.attributes?.uploadOperations ?? []) {
      const body = screenshot.bytes.subarray(operation.offset, operation.offset + operation.length);
      const headers = Object.fromEntries(
        (operation.requestHeaders ?? []).map(({ name, value }) => [name, value]),
      );
      const uploadResponse = await fetch(operation.url, {
        method: operation.method,
        headers,
        body,
      });
      if (!uploadResponse.ok) {
        throw new Error(`Asset upload failed with ${uploadResponse.status} ${uploadResponse.statusText}`);
      }
    }
    await api(`/appScreenshots/${reservation.id}`, {
      method: "PATCH",
      body: {
        data: {
          type: "appScreenshots",
          id: reservation.id,
          attributes: { uploaded: true, sourceFileChecksum: screenshot.md5 },
        },
      },
    });
    return reservation.id;
  } catch (error) {
    if (reservation?.id) {
      await api(`/appScreenshots/${reservation.id}`, { method: "DELETE" }).catch(() => {});
    }
    throw error;
  }
}

async function waitForProcessing(api, ids) {
  const deadline = Date.now() + 3 * 60 * 1000;
  while (Date.now() < deadline) {
    const states = await Promise.all(ids.map(async (id) => {
      const response = await api(
        `/appScreenshots/${id}?fields[appScreenshots]=fileName,sourceFileChecksum,imageAsset,assetDeliveryState`,
      );
      return {
        id,
        fileName: response.data.attributes?.fileName,
        state: response.data.attributes?.assetDeliveryState?.state,
      };
    }));
    const failure = states.find((item) => item.state === "FAILED");
    if (failure) throw new Error(`${failure.fileName} failed App Store processing`);
    if (states.every((item) => item.state === "COMPLETE")) return states;
    await new Promise((resolve) => setTimeout(resolve, 5_000));
  }
  throw new Error("Timed out waiting for App Store screenshot processing");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log("Usage: node scripts/app-store-screenshots-release.mjs [--apply] [--app-id <id>] [--version <version>] [--locale <locale>] [--display-type <type>] [--screenshots <directory>]");
    console.log("Defaults to a read-only dry run. Apply refuses to overwrite or delete existing screenshots.");
    return;
  }
  loadEnv(options.envPath);
  const screenshots = loadScreenshots(options.screenshotsPath);
  const api = createClient(createToken());
  const before = await resolveState(api, options);
  const summary = {
    mode: options.apply ? "apply" : "dry-run",
    version: before.version.attributes?.versionString,
    locale: before.localization.attributes?.locale,
    displayType: options.displayType,
    existingSetId: before.screenshotSet?.id ?? null,
    existingScreenshots: before.screenshots.map((item) => ({
      fileName: item.attributes?.fileName,
      state: item.attributes?.assetDeliveryState?.state,
    })),
    localScreenshots: screenshots.map(({ fileName, fileSize, md5, width, height }) => ({
      fileName, fileSize, md5, width, height,
    })),
  };
  console.log(JSON.stringify(summary, null, 2));
  if (!options.apply) return;
  if (before.screenshots.length > 0) {
    throw new Error("Refusing to overwrite or delete existing App Store screenshots");
  }
  const screenshotSet = before.screenshotSet
    ?? await createScreenshotSet(api, before.localization.id, options.displayType);
  const ids = [];
  for (const screenshot of screenshots) {
    ids.push(await uploadScreenshot(api, screenshotSet.id, screenshot));
  }
  await api(`/appScreenshotSets/${screenshotSet.id}/relationships/appScreenshots`, {
    method: "PATCH",
    body: { data: ids.map((id) => ({ type: "appScreenshots", id })) },
  });
  const processed = await waitForProcessing(api, ids);
  const after = await resolveState(api, options);
  if (after.screenshots.length !== screenshots.length) {
    throw new Error(`Expected ${screenshots.length} uploaded screenshots, found ${after.screenshots.length}`);
  }
  console.log(JSON.stringify({ applied: true, screenshotSetId: screenshotSet.id, processed }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  if (error.body) console.error(JSON.stringify(error.body, null, 2));
  process.exitCode = 1;
});
