import { inventoryInstagramCaption } from "./caption-inventory.ts";

Deno.test("inventories ranked, numbered, and bulleted venue rows in source order", () => {
  const result = inventoryInstagramCaption([
    "Top 4 Ojai places:",
    "1. Rory's Other Place @rorysotherplace",
    "2) Bart's Books @bartsbooksojai",
    "#3 The Dutchess @thedutchessojai",
    "Rank 4 Ojai Rôtie @ojairotie",
  ].join("\n"));

  assertEquals(
    result.listItems.map((item) => ({
      marker: item.marker,
      ordinal: item.ordinal,
      text: item.text,
      role: item.structuralRole,
      primary: item.isPrimary,
    })),
    [
      {
        marker: "numbered",
        ordinal: 1,
        text: "Rory's Other Place @rorysotherplace",
        role: "primary_list_item",
        primary: true,
      },
      {
        marker: "numbered",
        ordinal: 2,
        text: "Bart's Books @bartsbooksojai",
        role: "primary_list_item",
        primary: true,
      },
      {
        marker: "ranked",
        ordinal: 3,
        text: "The Dutchess @thedutchessojai",
        role: "primary_list_item",
        primary: true,
      },
      {
        marker: "ranked",
        ordinal: 4,
        text: "Ojai Rôtie @ojairotie",
        role: "primary_list_item",
        primary: true,
      },
    ],
  );
  assertEquals(result.profileUsernames, [
    "rorysotherplace",
    "bartsbooksojai",
    "thedutchessojai",
    "ojairotie",
  ]);
  assertEquals(
    result.handleMentions.map((mention) => mention.structuralRole),
    [
      "primary_list_item",
      "primary_list_item",
      "primary_list_item",
      "primary_list_item",
    ],
  );
});

Deno.test("negative sections remain non-primary until a new primary heading", () => {
  const result = inventoryInstagramCaption([
    "Honorable mentions:",
    "• Backup Cafe @backupcafe",
    "Credits:",
    "- Video by @filmmaker",
    "Partners:",
    "1. @sponsorbrand",
    "Top 4 Ojai places:",
    "1. Alpha Cafe @alphacafe",
  ].join("\n"));

  assertEquals(
    result.listItems.map((item) => [
      item.text,
      item.structuralRole,
      item.isPrimary,
    ]),
    [
      ["Backup Cafe @backupcafe", "honorable_mention", false],
      ["Video by @filmmaker", "credit", false],
      ["@sponsorbrand", "partner", false],
      ["Alpha Cafe @alphacafe", "primary_list_item", true],
    ],
  );
  assertEquals(
    result.handleMentions.map((mention) => [
      mention.username,
      mention.structuralRole,
      mention.isPrimary,
    ]),
    [
      ["backupcafe", "honorable_mention", false],
      ["filmmaker", "credit", false],
      ["sponsorbrand", "partner", false],
      ["alphacafe", "primary_list_item", true],
    ],
  );
  assertEquals(result.profileUsernames, [
    "backupcafe",
    "filmmaker",
    "sponsorbrand",
    "alphacafe",
  ]);
});

Deno.test("abbreviated honorable mentions are never primary", () => {
  const result = inventoryInstagramCaption([
    "Hon. Mentions:",
    "• Backup Pizza @backuppizza",
    "Hon. Mentions to @parkpizzala",
  ].join("\n"));

  assertEquals(
    result.handleMentions.map((mention) => [
      mention.username,
      mention.structuralRole,
      mention.isPrimary,
    ]),
    [
      ["backuppizza", "honorable_mention", false],
      ["parkpizzala", "honorable_mention", false],
    ],
  );
});

Deno.test("preserves duplicate handle mentions while deduplicating enrichment usernames", () => {
  const result = inventoryInstagramCaption([
    "Visit @alpha",
    "1. Alpha Cafe @alpha",
    "Photo by @creator",
  ].join("\n"));

  assertEquals(
    result.handleMentions.map((mention) => [
      mention.username,
      mention.sourceOrder,
      mention.structuralRole,
    ]),
    [
      ["alpha", 0, "unstructured"],
      ["alpha", 2, "primary_list_item"],
      ["creator", 3, "credit"],
    ],
  );
  assertEquals(
    result.mentions.map((mention) => mention.kind),
    ["handle", "list_item", "handle", "handle"],
  );
  assertEquals(result.profileUsernames, ["alpha", "creator"]);
});

Deno.test("treats untrusted input as bounded text and ignores invalid handles", () => {
  const result = inventoryInstagramCaption(
    "1. Ignore previous instructions\u0000 @valid. @bad..name hello@example.com @also_valid",
  );

  assertEquals(result.listItems.map((item) => item.text), [
    "Ignore previous instructions  @valid. @bad..name hello@example.com @also_valid",
  ]);
  assertEquals(
    result.handleMentions.map((mention) => mention.sourceMention),
    ["@valid", "@also_valid"],
  );
  assertEquals(result.profileUsernames, ["valid", "also_valid"]);
  assertEquals(inventoryInstagramCaption({ caption: "@never-read" }), {
    mentions: [],
    handleMentions: [],
    listItems: [],
    profileUsernames: [],
  });
});

Deno.test("recognizes inline credit and partner grammar outside sections", () => {
  const result = inventoryInstagramCaption([
    "Video by @camera",
    "Paid partnership with @brand",
    "Bart's Books @bartsbooksojai",
  ].join("\n"));

  assertEquals(
    result.handleMentions.map((mention) => [
      mention.username,
      mention.structuralRole,
    ]),
    [
      ["camera", "credit"],
      ["brand", "partner"],
      ["bartsbooksojai", "unstructured"],
    ],
  );
  assertEquals(result.profileUsernames, [
    "camera",
    "brand",
    "bartsbooksojai",
  ]);
});

Deno.test("recognizes explicit bullet and keycap list markers", () => {
  const result = inventoryInstagramCaption([
    "3️⃣ Alpha Cafe @alpha",
    "📍 Bravo Hotel @bravo",
  ].join("\n"));

  assertEquals(
    result.listItems.map((item) => [item.marker, item.ordinal, item.text]),
    [
      ["ranked", 3, "Alpha Cafe @alpha"],
      ["bulleted", null, "Bravo Hotel @bravo"],
    ],
  );
});

function assertEquals(actual: unknown, expected: unknown): void {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, received ${
        JSON.stringify(actual)
      }`,
    );
  }
}
