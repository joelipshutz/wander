import assert from "node:assert/strict";
import test from "node:test";
import {
  auditClerkExport,
  auditClerkInstances,
  parseCSV,
  prepareClerkImportRecords,
} from "./clerk-account-continuity-audit.mjs";

test("parseCSV handles quoted commas, escaped quotes, and embedded newlines", () => {
  const rows = parseCSV('id,metadata,note\r\nuser_1,"{""role"":""owner,admin""}","line one\nline two"\r\n');
  assert.deepEqual(rows, [{ id: "user_1", metadata: '{"role":"owner,admin"}', note: "line one\nline two" }]);
});

test("auditClerkExport requires password and stable-ID continuity for every user", () => {
  const records = ["user_1", "user_2"].map((id, index) => ({
    id,
    primary_email_address: `owner${index}@example.com`,
    verified_email_addresses: `owner${index}@example.com`,
    password_digest: "$2b$10$abcdefghijklmnopqrstuvwxyz",
    password_hasher: "bcrypt",
    public_metadata: JSON.stringify({ canonical_user_id: id }),
  }));
  assert.deepEqual(auditClerkExport(records, 2), {
    users: 2,
    passwordDigests: 2,
    verifiedPrimaryEmails: 2,
    stableIdentityTags: 2,
    hashers: { bcrypt: 2 },
  });
  assert.throws(
    () => auditClerkExport([{ ...records[0], password_digest: "" }, records[1]], 2),
    /password digest is missing/,
  );
});

test("auditClerkInstances proves remapped production users retain source identity", () => {
  const source = {
    data: ["user_old_1", "user_old_2"].map((id, index) => ({
      id,
      password_enabled: true,
      public_metadata: { canonical_user_id: id },
      primary_email_address_id: `email_${index}`,
      email_addresses: [{ id: `email_${index}`, email_address: `owner${index}@example.com` }],
    })),
  };
  const target = {
    data: source.data.map((user, index) => ({
      id: `user_new_${index}`,
      external_id: user.id,
      password_enabled: true,
      public_metadata: { canonical_user_id: user.id },
      primary_email_address_id: user.primary_email_address_id,
      email_addresses: user.email_addresses,
    })),
  };
  assert.deepEqual(auditClerkInstances(source, target, 2), {
    sourceUsers: 2,
    productionUsers: 2,
    stableMappings: 2,
    passwordEnabled: 2,
    emailMatches: 2,
  });
  target.data[0].external_id = "user_unknown";
  assert.throws(() => auditClerkInstances(source, target, 2), /unknown source ID/);
});

test("prepareClerkImportRecords restores object metadata missing from Dashboard CSV", () => {
  const records = ["user_1", "user_2"].map((id, index) => ({
    id,
    primary_email_address: `owner${index}@example.com`,
    verified_email_addresses: `owner${index}@example.com,alternate${index}@example.com`,
    password_digest: "$2b$10$abcdefghijklmnopqrstuvwxyz",
    password_hasher: "bcrypt",
  }));
  const source = {
    data: records.map((record, index) => ({
      id: record.id,
      password_enabled: true,
      public_metadata: { canonical_user_id: record.id, role: index === 0 ? "owner" : "member" },
      private_metadata: { internal: index },
      unsafe_metadata: { preference: "map" },
      primary_email_address_id: `email_${index}`,
      email_addresses: [{ id: `email_${index}`, email_address: record.primary_email_address }],
    })),
  };

  const prepared = prepareClerkImportRecords(records, source, 2);
  assert.equal(prepared[0].public_metadata.canonical_user_id, "user_1");
  assert.equal(prepared[0].public_metadata.role, "owner");
  assert.deepEqual(prepared[1].private_metadata, { internal: 1 });
  assert.deepEqual(auditClerkExport(prepared, 2).stableIdentityTags, 2);
});
