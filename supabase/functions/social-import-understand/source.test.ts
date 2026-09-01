import { parseSocialSource, sourceValueMatches } from "./source.ts";

Deno.test("Instagram reel permalinks accept singular and plural paths", () => {
  const singular = parseSocialSource(
    "https://www.instagram.com/reel/DWfBSUgAQ6x/",
  );
  const plural = parseSocialSource(
    "https://www.instagram.com/reels/DWfBSUgAQ6x/?hl=en#ignored",
  );

  assertEquals(singular, {
    platform: "instagram",
    contentType: "reel",
    url: "https://www.instagram.com/reel/DWfBSUgAQ6x",
    sourceID: "DWfBSUgAQ6x",
  });
  assertEquals(plural, {
    platform: "instagram",
    contentType: "reel",
    url: "https://www.instagram.com/reels/DWfBSUgAQ6x",
    sourceID: "DWfBSUgAQ6x",
  });
});

Deno.test("plural and singular Instagram reel paths share source identity", () => {
  const source = parseSocialSource(
    "https://www.instagram.com/reels/DWfBSUgAQ6x/",
  );
  if (!source) throw new Error("Expected a supported Instagram reel source");

  assertEquals(
    sourceValueMatches(
      "https://www.instagram.com/reel/DWfBSUgAQ6x/",
      source,
    ),
    true,
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
