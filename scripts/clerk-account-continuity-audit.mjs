#!/usr/bin/env node

import { chmodSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

export function parseCSV(source) {
  const rows = [];
  let row = [];
  let cell = "";
  let quoted = false;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    if (quoted) {
      if (character === '"' && source[index + 1] === '"') {
        cell += '"';
        index += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        cell += character;
      }
      continue;
    }

    if (character === '"') {
      quoted = true;
    } else if (character === ",") {
      row.push(cell);
      cell = "";
    } else if (character === "\n" || character === "\r") {
      if (character === "\r" && source[index + 1] === "\n") {
        index += 1;
      }
      row.push(cell);
      cell = "";
      if (row.some((value) => value.length > 0)) {
        rows.push(row);
      }
      row = [];
    } else {
      cell += character;
    }
  }

  if (quoted) {
    throw new Error("CSV contains an unterminated quoted field.");
  }
  if (cell.length > 0 || row.length > 0) {
    row.push(cell);
    if (row.some((value) => value.length > 0)) {
      rows.push(row);
    }
  }
  if (rows.length === 0) {
    throw new Error("CSV is empty.");
  }

  const headers = rows[0].map((header) => header.trim());
  if (new Set(headers).size !== headers.length) {
    throw new Error("CSV contains duplicate headers.");
  }
  return rows.slice(1).map((values, rowIndex) => {
    if (values.length !== headers.length) {
      throw new Error(`CSV row ${rowIndex + 2} has ${values.length} fields; expected ${headers.length}.`);
    }
    return Object.fromEntries(headers.map((header, columnIndex) => [header, values[columnIndex]]));
  });
}

export function auditClerkExport(records, expectedCount, { requireStableIdentityTags = true } = {}) {
  const requiredColumns = [
    "id",
    "primary_email_address",
    "verified_email_addresses",
    "password_digest",
    "password_hasher",
  ];
  if (records.length !== expectedCount) {
    throw new Error(`Clerk export has ${records.length} users; expected ${expectedCount}.`);
  }

  const ids = new Set();
  const emails = new Set();
  const hashers = new Map();
  for (const [index, record] of records.entries()) {
    for (const column of requiredColumns) {
      if (!(column in record)) {
        throw new Error(`Clerk export is missing required column ${column}.`);
      }
    }
    const rowLabel = `row ${index + 2}`;
    const id = nonEmpty(record.id, `${rowLabel} id`);
    const email = nonEmpty(record.primary_email_address, `${rowLabel} primary email`).toLowerCase();
    const digest = nonEmpty(record.password_digest, `${rowLabel} password digest`);
    const hasher = nonEmpty(record.password_hasher, `${rowLabel} password hasher`);
    if (ids.has(id)) throw new Error(`${rowLabel} duplicates a Clerk user ID.`);
    if (emails.has(email)) throw new Error(`${rowLabel} duplicates a primary email.`);
    ids.add(id);
    emails.add(email);
    hashers.set(hasher, (hashers.get(hasher) ?? 0) + 1);

    if (digest.length < 8) {
      throw new Error(`${rowLabel} has an implausibly short password digest.`);
    }
    const verifiedEmails = record.verified_email_addresses
      .split(/[,|]/)
      .map((value) => value.trim().toLowerCase())
      .filter(Boolean);
    if (!verifiedEmails.includes(email)) {
      throw new Error(`${rowLabel} does not preserve its primary email as verified.`);
    }

    const publicMetadata = metadataObject(record.public_metadata, `${rowLabel} public metadata`);
    if (requireStableIdentityTags && publicMetadata?.canonical_user_id !== id) {
      throw new Error(`${rowLabel} canonical_user_id does not match its existing Clerk ID.`);
    }
  }

  return {
    users: records.length,
    passwordDigests: records.length,
    verifiedPrimaryEmails: records.length,
    stableIdentityTags: records.filter((record) => {
      const metadata = metadataObject(record.public_metadata, "public metadata");
      return metadata?.canonical_user_id === record.id?.trim();
    }).length,
    hashers: Object.fromEntries([...hashers.entries()].sort(([left], [right]) => left.localeCompare(right))),
  };
}

export function prepareClerkImportRecords(records, sourcePayload, expectedCount) {
  auditClerkExport(records, expectedCount, { requireStableIdentityTags: false });
  const sourceUsers = userArray(sourcePayload, "source");
  if (sourceUsers.length !== expectedCount) {
    throw new Error(`Source Clerk instance has ${sourceUsers.length} users; expected ${expectedCount}.`);
  }

  const sourceByID = new Map();
  for (const user of sourceUsers) {
    const id = nonEmpty(user.id, "source user id");
    if (sourceByID.has(id)) throw new Error("Source Clerk instance contains a duplicate user ID.");
    if (user.public_metadata?.canonical_user_id !== id) {
      throw new Error("A source Clerk user is missing its matching canonical_user_id.");
    }
    if (user.password_enabled !== true) {
      throw new Error("A source Clerk user no longer has a password enabled.");
    }
    sourceByID.set(id, user);
  }

  const prepared = records.map((record, index) => {
    const rowLabel = `row ${index + 2}`;
    const id = nonEmpty(record.id, `${rowLabel} id`);
    const sourceUser = sourceByID.get(id);
    if (!sourceUser) {
      throw new Error(`${rowLabel} does not match a source Clerk user.`);
    }
    const exportEmail = nonEmpty(record.primary_email_address, `${rowLabel} primary email`).toLowerCase();
    if (primaryEmail(sourceUser) !== exportEmail) {
      throw new Error(`${rowLabel} primary email does not match the source Clerk inventory.`);
    }

    // Clerk's migration tool accepts JSON objects for metadata. Build a JSON
    // import file even when Dashboard's CSV omits metadata or serializes it as
    // strings, so the canonical identity cannot disappear in translation.
    return {
      ...record,
      public_metadata: sourceUser.public_metadata ?? {},
      private_metadata: sourceUser.private_metadata ?? {},
      unsafe_metadata: sourceUser.unsafe_metadata ?? {},
    };
  });

  if (prepared.length !== sourceByID.size) {
    throw new Error("The Clerk export and source inventory do not contain the same users.");
  }
  auditClerkExport(prepared, expectedCount);
  return prepared;
}

export function auditClerkInstances(sourcePayload, targetPayload, expectedCount) {
  const sourceUsers = userArray(sourcePayload, "source");
  const targetUsers = userArray(targetPayload, "target");
  if (sourceUsers.length !== expectedCount) {
    throw new Error(`Source Clerk instance has ${sourceUsers.length} users; expected ${expectedCount}.`);
  }
  if (targetUsers.length !== expectedCount) {
    throw new Error(`Production Clerk instance has ${targetUsers.length} users; expected ${expectedCount}.`);
  }

  const sourceByID = new Map();
  for (const user of sourceUsers) {
    const id = nonEmpty(user.id, "source user id");
    if (sourceByID.has(id)) throw new Error("Source Clerk instance contains a duplicate user ID.");
    if (user.public_metadata?.canonical_user_id !== id) {
      throw new Error("A source Clerk user is missing its matching canonical_user_id.");
    }
    if (user.password_enabled !== true) {
      throw new Error("A source Clerk user no longer has a password enabled.");
    }
    sourceByID.set(id, primaryEmail(user));
  }

  const mappedIDs = new Set();
  for (const user of targetUsers) {
    const externalID = nonEmpty(user.external_id, "production external_id");
    if (mappedIDs.has(externalID)) throw new Error("Production Clerk contains a duplicate external_id.");
    mappedIDs.add(externalID);
    if (!sourceByID.has(externalID)) {
      throw new Error("A production Clerk user maps to an unknown source ID.");
    }
    if (user.public_metadata?.canonical_user_id !== externalID) {
      throw new Error("A production Clerk user has mismatched canonical_user_id metadata.");
    }
    if (user.password_enabled !== true) {
      throw new Error("A production Clerk user does not have a migrated password enabled.");
    }
    if (primaryEmail(user) !== sourceByID.get(externalID)) {
      throw new Error("A production Clerk user email does not match its source account.");
    }
  }

  return {
    sourceUsers: sourceUsers.length,
    productionUsers: targetUsers.length,
    stableMappings: mappedIDs.size,
    passwordEnabled: targetUsers.filter((user) => user.password_enabled === true).length,
    emailMatches: mappedIDs.size,
  };
}

function userArray(payload, label) {
  if (!payload || !Array.isArray(payload.data)) {
    throw new Error(`${label} Clerk JSON must contain a data array.`);
  }
  return payload.data;
}

function primaryEmail(user) {
  const primary = user.email_addresses?.find((address) => address.id === user.primary_email_address_id)
    ?? user.email_addresses?.[0];
  return nonEmpty(primary?.email_address, "Clerk primary email").toLowerCase();
}

function metadataObject(value, label) {
  if (value === undefined || value === null || value === "") return undefined;
  if (typeof value === "object" && !Array.isArray(value)) return value;
  if (typeof value !== "string") throw new Error(`${label} is not an object.`);
  try {
    const parsed = JSON.parse(value);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("not an object");
    }
    return parsed;
  } catch {
    throw new Error(`${label} is not valid JSON.`);
  }
}

function nonEmpty(value, label) {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${label} is missing.`);
  }
  return value.trim();
}

function parseArguments(args) {
  const options = { expectedCount: 6 };
  for (let index = 0; index < args.length; index += 1) {
    const flag = args[index];
    if (flag === "--export-csv") options.exportCSV = requiredArgument(args, ++index, flag);
    else if (flag === "--source-json") options.sourceJSON = requiredArgument(args, ++index, flag);
    else if (flag === "--target-json") options.targetJSON = requiredArgument(args, ++index, flag);
    else if (flag === "--prepare-import-json") options.prepareImportJSON = requiredArgument(args, ++index, flag);
    else if (flag === "--expected-count") options.expectedCount = Number(requiredArgument(args, ++index, flag));
    else if (flag === "--help" || flag === "-h") options.help = true;
    else throw new Error(`Unknown argument: ${flag}`);
  }
  if (!Number.isInteger(options.expectedCount) || options.expectedCount < 1) {
    throw new Error("--expected-count must be a positive integer.");
  }
  return options;
}

function requiredArgument(args, index, flag) {
  const value = args[index];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value.`);
  return value;
}

function printHelp() {
  console.log(`Usage:
  node scripts/clerk-account-continuity-audit.mjs --export-csv /private/path/users.csv [--expected-count 6]
  node scripts/clerk-account-continuity-audit.mjs --export-csv /private/path/users.csv --source-json /private/path/dev.json --prepare-import-json /private/path/import.json [--expected-count 6]
  node scripts/clerk-account-continuity-audit.mjs --source-json /private/path/dev.json --target-json /private/path/prod.json [--expected-count 6]

The audit prints counts only. It never prints emails, password digests, or user IDs.`);
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }
  if (options.exportCSV) {
    const records = parseCSV(readFileSync(resolve(options.exportCSV), "utf8"));
    if (options.prepareImportJSON) {
      if (!options.sourceJSON) {
        throw new Error("--prepare-import-json also requires --source-json.");
      }
      const source = JSON.parse(readFileSync(resolve(options.sourceJSON), "utf8"));
      const prepared = prepareClerkImportRecords(records, source, options.expectedCount);
      const outputPath = resolve(options.prepareImportJSON);
      writeFileSync(outputPath, `${JSON.stringify(prepared, null, 2)}\n`, { flag: "wx", mode: 0o600 });
      chmodSync(outputPath, 0o600);
      console.log(JSON.stringify({
        export: auditClerkExport(prepared, options.expectedCount),
        importFile: { users: prepared.length, mode: "0600", path: outputPath },
      }, null, 2));
      return;
    }
    console.log(JSON.stringify({
      export: auditClerkExport(records, options.expectedCount, { requireStableIdentityTags: false }),
    }, null, 2));
    return;
  }
  if (options.sourceJSON && options.targetJSON) {
    const source = JSON.parse(readFileSync(resolve(options.sourceJSON), "utf8"));
    const target = JSON.parse(readFileSync(resolve(options.targetJSON), "utf8"));
    console.log(JSON.stringify({ instances: auditClerkInstances(source, target, options.expectedCount) }, null, 2));
    return;
  }
  throw new Error("Provide --export-csv, or both --source-json and --target-json.");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  });
}
