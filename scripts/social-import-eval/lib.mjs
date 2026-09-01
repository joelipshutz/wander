import { createHash } from "node:crypto";
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

const genericTerms = new Set([
  "food", "foodie", "foodtok", "foodtiktok", "restaurant", "restaurants",
  "reels", "reel", "viral", "fyp", "foryou", "foryoupage", "explore",
  "lafood", "lafoodie", "losangeles", "california", "travel", "creator",
  "coffee", "coffeeshop", "cafe", "localcoffee", "localcoffeeshop",
]);

const genericVenueTokens = new Set([
  "a", "all", "an", "and", "at", "best", "cafe", "coffee", "coffeehouse", "food",
  "for", "in", "instagram", "local", "new", "of", "place", "restaurant",
  "shop", "spot", "spots", "the", "these", "those", "tiktok", "to", "try", "viral", "visit",
]);

const strongPlaceDesignators = new Set([
  "aquarium", "bakery", "beach", "brewery", "brewing", "castle", "falls",
  "farms", "gallery", "garden", "gardens", "gorge", "hotel", "inn", "lake",
  "lakes", "lodge", "market", "mercantile", "mountain", "mountains", "museum",
  "observatory", "overlook", "park", "petroglyph", "petroglyphs", "plaza",
  "range", "resort", "river", "shrine", "springs", "store", "supply",
  "temple", "theater", "theatre", "tower", "trail", "zoo",
]);

const weakPlaceDesignators = new Set([
  "bar", "cafe", "coffee", "deli", "eatery", "grill", "izakaya", "kitchen", "restaurant",
]);

const numberedAreaVenueDesignators = new Set([
  "bakery", "bar", "brewery", "brewing", "cafe", "coffee", "deli", "eatery",
  "gallery", "grill", "hotel", "inn", "izakaya", "kitchen", "lodge", "market", "mercantile",
  "museum", "pub", "resort", "restaurant", "store", "supply", "tavern",
]);

const numberedLowercaseInstructionVerbs = new Set([
  "buy", "catch", "enjoy", "find", "get", "have", "look", "make", "see",
  "take", "try", "watch",
]);

// Keep this narrow and mirrored with SocialPlaceHintExtractor. These are
// common venue-name phrases where `in` belongs to the name, not an area split.
const numberedFixedInNameLeads = new Set(["baked", "made"]);

const geographyCountrySuffixes = [
  ["united", "states", "of", "america"],
  ["united", "states"],
  ["u", "s", "a"],
  ["usa"],
  ["us"],
];

const actionWords = new Set([
  "admiring", "adventure", "at", "because", "finish", "fishing", "grab",
  "hike", "make", "may", "off", "road", "stay", "through", "trip", "you",
  "your",
]);

const attributionPatterns = [
  /^(?:(?:the|a|an)\s+)?(?:creator|creators|founder|founders|owner|owners)\s+of\b/i,
  /^(?:(?:the|a|an)\s+)?team\s+(?:behind|from)\b/i,
  /^(?:(?:the|a|an)\s+)?veterans?\s+of\b/i,
  /^(?:my|our|a|an|the)\s+friends?\b/i,
  /^friends?\s+(?:behind|from|of|who)\b/i,
];

const stateNames = [
  "Alabama", "Alaska", "Arizona", "Arkansas", "California", "Colorado",
  "Connecticut", "Delaware", "Florida", "Hawaii", "Idaho", "Illinois",
  "Indiana", "Iowa", "Kansas", "Kentucky", "Louisiana", "Maine", "Maryland",
  "Massachusetts", "Michigan", "Minnesota", "Mississippi", "Missouri",
  "Montana", "Nebraska", "Nevada", "New Hampshire", "New Jersey", "New Mexico",
  "New York", "North Carolina", "North Dakota", "Ohio", "Oklahoma", "Oregon",
  "Pennsylvania", "Rhode Island", "South Carolina", "South Dakota", "Tennessee",
  "Texas", "Utah", "Vermont", "Virginia", "Washington", "West Virginia",
  "Wisconsin", "Wyoming",
];

export function parseList(value, fallback = []) {
  if (!value) return fallback;
  return value.split(",").map((item) => item.trim()).filter(Boolean);
}

export function stableHash(value) {
  return createHash("sha256").update(value).digest("hex");
}

export function buildRescoreProvenance({
  rebuildUnderstandingHints,
  reresolveMapKit,
  mapKitResolverID,
}) {
  return {
    appliedTransforms: [
      { kind: "scoring", revision: "score-contract-v4" },
      ...(rebuildUnderstandingHints
        ? [{ kind: "understanding_hints", revision: "grounded-hints-v3" }]
        : []),
      ...(reresolveMapKit
        ? [{ kind: "mapkit_resolution", revision: mapKitResolverID }]
        : []),
    ],
    mapKitHintSource: rebuildUnderstandingHints
      ? "rebuilt_understanding_hints"
      : "saved_understanding_hints",
  };
}

export function safeSegment(value) {
  return value.replace(/[^A-Za-z0-9._-]+/g, "-").replace(/^-+|-+$/g, "");
}

export async function readJSON(path) {
  return JSON.parse(await readFile(path, "utf8"));
}

export async function writeJSON(path, value) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = path + ".tmp";
  await writeFile(temporary, JSON.stringify(value, null, 2) + "\n");
  await rename(temporary, path);
}

export function canonicalPlaceName(value) {
  return String(value ?? "")
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLowerCase()
    .replace(/\bmerc\b/g, "mercantile")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
}

function coreName(value) {
  const ignored = new Set([
    "the", "restaurant", "restaurants", "eatery", "company", "co", "inc",
    "llc", "reservoir",
  ]);
  return canonicalPlaceName(value)
    .split(/\s+/)
    .filter((token) => token && !ignored.has(token))
    .sort()
    .join(" ");
}

export function namesEquivalent(lhs, rhs) {
  const left = canonicalPlaceName(lhs);
  const right = canonicalPlaceName(rhs);
  if (!left || !right) return false;
  if (left.replaceAll(" ", "") === right.replaceAll(" ", "")) return true;
  const leftCore = coreName(lhs);
  const rightCore = coreName(rhs);
  if (leftCore && leftCore === rightCore) return true;
  const shorter = left.length <= right.length ? left : right;
  const longer = left.length > right.length ? left : right;
  return shorter.length >= 5 && longer.includes(shorter);
}

function readableHandle(value) {
  const businessTokens = [
    "restaurant", "coffee", "bakery", "kitchen", "market", "farms",
    "tacos", "pizza", "sushi", "cafe", "grill", "deli", "hotel", "bar",
  ];
  let result = value.replace(/[_.]+/g, " ").replace(/([a-z0-9])([A-Z])/g, "$1 $2");
  for (const token of businessTokens) {
    const expression = new RegExp("(?<!^|\\s)" + token, "ig");
    result = result.replace(expression, " " + token);
  }
  return result.replace(/\s+/g, " ").trim();
}

function trimPhrase(value) {
  let result = value.trim();
  for (const ending of [" and ", " with ", " where ", " for ", " which ", " serving "]) {
    const index = result.toLowerCase().indexOf(ending);
    if (index >= 0) result = result.slice(0, index);
  }
  return result.replace(/^[\s,;:\-–—]+|[\s,;:\-–—]+$/g, "");
}

function isAttribution(value) {
  return attributionPatterns.some((pattern) => pattern.test(value.trim()));
}

function isGeneric(value) {
  const key = canonicalPlaceName(value).replaceAll(" ", "");
  return key.length < 3
    || genericTerms.has(key)
    || key.startsWith("instagram")
    || key.startsWith("tiktok");
}

function hasDistinctiveToken(value) {
  return canonicalPlaceName(value)
    .split(/\s+/)
    .some((token) => token.length >= 2 && !genericVenueTokens.has(token));
}

function splitNameAndArea(value) {
  const cleaned = trimPhrase(
    value
      .replaceAll("&quot;", "\"")
      .replace(/^[\s\"'()[\]]+|[\s\"'()[\]]+$/g, ""),
  );
  if (!cleaned) return null;
  const inMatches = [...cleaned.matchAll(/\s+in\s+/ig)];
  if (inMatches.length > 0) {
    const match = inMatches.at(-1);
    const name = cleaned.slice(0, match.index).trim();
    const area = cleaned.slice(match.index + match[0].length).trim();
    if (name && area) return { name, area };
  }
  const pipe = cleaned.split(/\s*[|/]\s*/, 2);
  if (pipe.length === 2 && pipe[0] && pipe[1]) {
    return { name: pipe[0], area: pipe[1] };
  }
  const comma = cleaned.split(",").map((part) => part.trim()).filter(Boolean);
  if (comma.length >= 2) {
    const last = comma.at(-1);
    if (
      /\b[A-Z]{2}(?:\s+\d{5})?\b/.test(last)
      || stateNames.some((state) => canonicalPlaceName(last).includes(canonicalPlaceName(state)))
      || /\b(?:USA|US|United States|Japan|Austria|Egypt|Mexico|Canada)\b/i.test(last)
    ) {
      return { name: comma[0], area: comma.slice(1).join(", ") };
    }
  }
  return { name: cleaned, area: null };
}

function isStrongVisibleName(value) {
  const words = canonicalPlaceName(value).split(/\s+/).filter(Boolean);
  if (words.length < 2 || words.length > 9) return false;
  if (words.some((word) => actionWords.has(word))) return false;
  const strong = words.some((word) => strongPlaceDesignators.has(word));
  const weak = words.some((word) => weakPlaceDesignators.has(word));
  const distinctive = words.filter(
    (word) => !genericVenueTokens.has(word)
      && !strongPlaceDesignators.has(word)
      && !weakPlaceDesignators.has(word),
  ).length;
  return strong ? distinctive > 0 : weak && distinctive >= 1;
}

function normalizedWords(value) {
  return canonicalPlaceName(value).split(/\s+/).filter(Boolean);
}

function containsTokenSequence(shorter, longer) {
  if (shorter.length === 0 || shorter.length > longer.length) return false;
  for (let start = 0; start <= longer.length - shorter.length; start += 1) {
    if (shorter.every((token, index) => token === longer[start + index])) return true;
  }
  return false;
}

function geographyWords(value) {
  const words = normalizedWords(value);
  for (const suffix of geographyCountrySuffixes) {
    if (suffix.length > words.length) continue;
    if (suffix.every((token, index) => token === words[words.length - suffix.length + index])) {
      return words.slice(0, -suffix.length);
    }
  }
  return words;
}

function hasVenueDesignator(value) {
  const words = new Set(normalizedWords(value));
  return [...strongPlaceDesignators, ...weakPlaceDesignators]
    .some((designator) => words.has(designator));
}

function hasKnownAdministrativeArea(value) {
  const words = normalizedWords(value);
  if (words.length === 0) return false;
  if (stateNames.some((state) => canonicalPlaceName(state) === words.join(" "))) return true;
  return geographyCountrySuffixes.some((country) => (
    country.length === words.length
    && country.every((token, index) => token === words[index])
  ));
}

function numberedItineraryLines(text) {
  if (!text) return [];
  return text.split(/\r?\n/).flatMap((line) => {
    const match = line.match(/^\s*\d{1,3}[.)]\s+(.{3,160}?)\s*$/u);
    return match ? [{ line, content: match[1].trim() }] : [];
  });
}

function isMultiStopNumberedItinerary(text) {
  return numberedItineraryLines(text).length >= 2;
}

function cleanNumberedObject(value) {
  return String(value ?? "")
    .replace(/^[\s"'\[\]{}:;,@\-–—]+/u, "")
    .replace(/[\s"',;:!?.\-–—]+$/u, "")
    .replace(/\s+/gu, " ")
    .trim();
}

function trimNumberedCommentary(value) {
  let result = cleanNumberedObject(value)
    .replace(/\s+(?:with|by)\s+@[A-Za-z0-9._]{3,40}(?=\s|$)/giu, "")
    .trim();
  for (const match of result.matchAll(/\s+for\s+(\S+)/gu)) {
    if (/^\p{Ll}/u.test(match[1])) {
      result = result.slice(0, match.index).trim();
      break;
    }
  }
  return cleanNumberedObject(result);
}

function splitNumberedNameAndArea(value) {
  const rawValue = String(value ?? "").replace(
    /^\s*(?:the|a|an)\s+(?=@)/iu,
    "",
  );
  const isHandle = /^\s*@/u.test(rawValue);
  let cleaned = trimNumberedCommentary(rawValue);
  if (!cleaned) return null;
  if (isHandle) {
    const handle = /^([A-Za-z0-9._]+)(.*)$/u.exec(cleaned);
    if (handle) cleaned = readableHandle(handle[1]) + handle[2];
  }
  const matches = [...cleaned.matchAll(/\s+in\s+/giu)];
  if (matches.length > 0) {
    const match = matches.at(-1);
    const name = cleanNumberedObject(cleaned.slice(0, match.index));
    const area = cleanNumberedObject(cleaned.slice(match.index + match[0].length));
    if (
      name
      && area
      && !numberedFixedInNameLeads.has(canonicalPlaceName(name))
      && normalizedWords(area).length <= 6
      && !normalizedWords(area).some((word) => numberedAreaVenueDesignators.has(word))
      && /^[\p{Lu}\d]/u.test(area)
    ) return { name, area, isHandle };
  }
  return { name: cleaned, area: null, isHandle };
}

function isNamedNumberedObject(value, {
  allowLowercaseDistinctiveToken = false,
  allowLowercaseMultiwordName = false,
} = {}) {
  const words = normalizedWords(value);
  if (words.length === 0 || words.length > 10) return false;
  if (isGeneric(value) || !hasDistinctiveToken(value) || isAttribution(value)) return false;
  const originalWords = value.match(/[\p{L}\p{N}]+/gu) ?? [];
  const genericObjectTokens = new Set([
    ...genericVenueTokens,
    ...strongPlaceDesignators,
    ...weakPlaceDesignators,
    "area", "areas", "cities", "city", "hotel", "hotels", "market", "markets",
    "neighborhood", "neighborhoods", "neighbourhood", "neighbourhoods", "place",
    "places", "town", "towns",
  ]);
  const hasDistinctiveObjectToken = originalWords.some((word) => (
    word.length >= 2
    && !genericObjectTokens.has(canonicalPlaceName(word))
  ));
  const hasDistinctiveProperToken = originalWords.some((word) => (
    word.length >= 2
    && /^[\p{Lu}\d]/u.test(word)
    && !genericObjectTokens.has(canonicalPlaceName(word))
  ));
  const hasPlaceDesignator = words.some((word) => (
    strongPlaceDesignators.has(word) || weakPlaceDesignators.has(word)
  ));
  const beginsWithLowercaseInstruction = numberedLowercaseInstructionVerbs.has(words[0]);
  const validLowercaseGrounding = allowLowercaseDistinctiveToken
    && !beginsWithLowercaseInstruction
    && (words.length === 1 || hasPlaceDesignator || allowLowercaseMultiwordName);
  return hasDistinctiveObjectToken
    && (validLowercaseGrounding || hasDistinctiveProperToken);
}

function isStrongPlainNumberedPlaceName(value) {
  const words = normalizedWords(value);
  if (words.length < 2 || words.length > 8) return false;
  if (!words.some((word) => strongPlaceDesignators.has(word))) return false;
  return words.some((word) => (
    !genericVenueTokens.has(word)
    && !strongPlaceDesignators.has(word)
    && !weakPlaceDesignators.has(word)
  ));
}

function numberedItineraryObjects(rawLine) {
  const nextAction = String.raw`(?:coffee|dinner|lunch|breakfast|brunch|dessert|drinks?|stop|visit|visited|base\s+camp|stroll|walk|go|head|drive|hike|return|take\s+(?:a\s+)?(?:photo|picture)|photo|picture|grab|buy|pick(?:ed|ing)?\s+up|eat|fish|drink|shop|stay|base|explore|gawk|look)`;
  const tail = String.raw`(?=\s*(?:(?:,\s*)?(?:(?:and\s+)?then|and)\s+${nextAction}\b|with\s+@[A-Za-z0-9._]+\b|[#\n.!?]|$))`;
  const patterns = [
    [new RegExp(String.raw`\bstop(?:\s+for\s+[^#\n.!?]{0,30})?\s+at\s+(.+?)${tail}`, "giu"), true],
    [new RegExp(String.raw`\bstay\s+(?:at|in)\s+(.+?)${tail}`, "giu"), true],
    [new RegExp(String.raw`\b(?:coffee|dinner|lunch|breakfast|brunch|dessert|drinks?|visit|visited|base\s+camp)\s+(?:at\s+)?(.+?)${tail}`, "giu"), true],
    [new RegExp(String.raw`\b(?:stroll|walk)\b[^#\n.!?]{0,35}?\b(?:down|through|around|to)\s+(.+?)${tail}`, "giu"), true],
    [new RegExp(String.raw`\b(?:go|head|drive|hike|return)\s+(?:back\s+)?to\s+(.+?)${tail}`, "giu"), true],
    [new RegExp(String.raw`\b(?:take\s+(?:a\s+)?(?:photo|picture)|photo|picture)\s+(?:with|at|of)\s+(?:the\s+)?(.+?)${tail}`, "giu"), false],
    [new RegExp(String.raw`\b(?:grab|buy|pick(?:ed|ing)?\s+up|eat|fish|drink)\b[^#\n.!?]{0,55}?\b(?:from|at|through)\s+(.+?)${tail}`, "giu"), true],
    [new RegExp(String.raw`\bshop\b[^#\n.!?]{0,60}?\bin\s+(.+?)${tail}`, "giu"), false],
    [new RegExp(String.raw`\bexplore\s+(.+?)${tail}`, "giu"), false],
  ];
  const values = [];
  if (/\b(?:base|stay)\b/iu.test(rawLine)) {
    const destinationHandleLine = rawLine.replace(
      /\s+(?:with|by)\s+@[A-Za-z0-9._]{3,40}\b/giu,
      "",
    );
    const displayName = /@([\p{L}\p{N}][^#\n.!?]{2,90}?)(?=\s+(?:to\s+(?:explore|visit|walk|see)|while|where)\b|\s+for\s+\p{Ll}[\p{L}\p{N}'’&-]*\b|[#\n.!?]|$)/iu.exec(destinationHandleLine)?.[1];
    const parsed = displayName ? splitNumberedNameAndArea("@" + displayName) : null;
    if (parsed && isNamedNumberedObject(parsed.name, {
      allowLowercaseDistinctiveToken: true,
    })) values.push(parsed);
  }
  for (const [expression, allowLowercaseMultiwordName] of patterns) {
    for (const match of rawLine.matchAll(expression)) {
      const parsed = splitNumberedNameAndArea(match[1]);
      if (parsed && isNamedNumberedObject(parsed.name, {
        allowLowercaseDistinctiveToken: true,
        allowLowercaseMultiwordName,
      })) values.push(parsed);
    }
  }
  return values.filter((value, index) => values.findIndex((other) => (
    canonicalPlaceName(other.name) === canonicalPlaceName(value.name)
    && canonicalPlaceName(other.area) === canonicalPlaceName(value.area)
  )) === index);
}

function containsNumberedItineraryAction(value) {
  return /^\s*(?:coffee|dinner|lunch|breakfast|brunch|dessert|drinks?|stop|visit|visited|base\s+camp|stroll|walk|go|head|drive|hike|return|take\s+(?:a\s+)?(?:photo|picture)|photo|picture|grab|buy|pick(?:ed|ing)?\s+up|eat|fish|drink|shop|stay|base|explore)\b/iu.test(value);
}

function extractNumberedItineraryHints(text, output, source) {
  const lines = numberedItineraryLines(text);
  if (lines.length < 2) return { active: false, residualText: text };
  const numberedByLine = new Map(lines.map((item) => [item.line, item.content]));
  const residualLines = [];
  for (const line of text.split(/\r?\n/)) {
    const content = numberedByLine.get(line);
    if (!content) {
      residualLines.push(line);
      continue;
    }
    const parsedValues = numberedItineraryObjects(content);
    if (parsedValues.length === 0 && !containsNumberedItineraryAction(content)) {
      const directName = splitNumberedNameAndArea(content);
      if (
        directName
        && isNamedNumberedObject(directName.name)
        && isStrongPlainNumberedPlaceName(directName.name)
      ) parsedValues.push(directName);
    }
    if (parsedValues.length === 0 && !containsNumberedItineraryAction(content)) {
      residualLines.push(content);
    }
    for (const parsed of parsedValues) {
      const usesVisibleMediaTrust = ["ocr", "video_text", "accessibility_text"]
        .includes(source);
      addHint(output, {
        name: parsed.name,
        area: parsed.area,
        modality: source,
        evidence: parsed.isHandle
          ? "itinerary_handle"
          : (usesVisibleMediaTrust ? "image_or_video_text" : "numbered_itinerary"),
        classification: "destination",
        durable: !parsed.isHandle,
        trustRank: parsed.isHandle ? 1 : (usesVisibleMediaTrust ? 3 : 4),
        preserveStructuredName: true,
      });
    }
  }
  return { active: true, residualText: residualLines.join("\n") };
}

function demoteGeographyContexts(hints, { hasNumberedItinerary = false } = {}) {
  const contexts = [];
  const retained = hints.filter((hint, index) => {
    const words = geographyWords(hint.name);
    if (words.length === 0 || words.length > 4 || hasVenueDesignator(hint.name)) return true;
    // Without an explicit semantic geography type, only platform-tagged
    // locations are safe to demote. A short attraction/neighborhood extracted
    // from caption or media must not disappear merely because another venue
    // repeats it as an area.
    const hasAdministrativeProvenance = hint.modality === "tagged_location"
      || hint.classification === "itinerary"
      || hasKnownAdministrativeArea(hint.area);
    const usedByAnotherDestination = hasAdministrativeProvenance
      && hints.some((other, otherIndex) => (
      otherIndex !== index
      && other.durable !== false
      && containsTokenSequence(words, geographyWords(other.area))
      ));
    const administrativeNumberedTag = hasNumberedItinerary
      && hint.modality === "tagged_location"
      && hints.some((other, otherIndex) => otherIndex !== index && other.durable !== false)
      && containsTokenSequence(words, geographyWords(hint.area));
    if (!usedByAnotherDestination && !administrativeNumberedTag) return true;
    contexts.push({ name: hint.name, area: hint.area ?? null, modality: hint.modality });
    return false;
  });
  return { hints: retained, contexts };
}

function postWideArea(text) {
  const matches = stateNames.filter((state) =>
    new RegExp("\\b" + state.replaceAll(" ", "\\s+") + "\\b", "i").test(text)
  );
  if (matches.length !== 1) return null;
  const travelContext = /\b(?:road\s+trip|trip|travel(?:ing|ling)?|journey|tour|adventure|itinerary|guide|explore|exploring|visit|visiting)\b/i;
  return travelContext.test(text) ? matches[0] : null;
}

function addHint(output, hint) {
  if (!hint?.name) return;
  const {
    preserveStructuredName = false,
    ...persistedHint
  } = hint;
  const name = preserveStructuredName
    ? cleanNumberedObject(hint.name)
    : trimPhrase(hint.name);
  if (
    name.length < 3
    || name.length > 100
    || isGeneric(name)
    || !hasDistinctiveToken(name)
    || isAttribution(name)
  ) return;
  const normalized = canonicalPlaceName(name) + "|" + canonicalPlaceName(hint.area);
  const existingIndex = output.findIndex((item) =>
    canonicalPlaceName(item.name) + "|" + canonicalPlaceName(item.area) === normalized
  );
  const value = { ...persistedHint, name, area: hint.area || null };
  if (existingIndex < 0) {
    output.push(value);
    return;
  }
  if ((hint.trustRank ?? 0) > (output[existingIndex].trustRank ?? 0)) {
    output[existingIndex] = value;
  }
}

function addParsedHint(output, value, metadata) {
  let cleaned = trimPhrase(value);
  if (!cleaned || isAttribution(cleaned)) return;
  if (cleaned.startsWith("@")) {
    const handle = cleaned.slice(1).split(/\s+/)[0];
    cleaned = readableHandle(handle);
  }
  const parsed = splitNameAndArea(cleaned);
  if (!parsed) return;
  addHint(output, {
    ...metadata,
    name: parsed.name,
    area: parsed.area,
  });
}

function captures(text, expression) {
  const values = [];
  expression.lastIndex = 0;
  for (const match of text.matchAll(expression)) {
    if (match[1]) values.push(match[1]);
  }
  return values;
}

function extractFromCreatorText(text, output, source) {
  if (!text) return;
  for (const value of captures(text, /📍\s*([^#\n]{3,120})/gu)) {
    addParsedHint(output, value, {
      modality: source,
      evidence: "explicit_location",
      classification: "destination",
      durable: true,
      trustRank: 5,
    });
  }
  for (const value of captures(
    text,
    /(?:location|located)\s*[:\-]\s*([^#\n]{3,120})/giu,
  )) {
    addParsedHint(output, value, {
      modality: source,
      evidence: "explicit_location",
      classification: "destination",
      durable: true,
      trustRank: 5,
    });
  }
  const numberedItinerary = extractNumberedItineraryHints(text, output, source);
  const phraseText = numberedItinerary.residualText;
  const itineraryPatterns = [
    /\b(?:called|at|visited|visit|trying|place is)\s+(@?[^#\n.!?]{3,90}?)(?=\s+(?:(?:and|then|afterwards?)[^#\n.!?]{0,60}\b(?:at|from|visited|visit)\s+|(?:\d{1,3}\s*(?:-\s*)?(?:minutes?|mins?|hours?|hrs?)\s+)?(?:drive|head|go|hike|walk|travel|return)(?:\s+back)?\s+to\b)|[#\n.!?]|$)/giu,
    /\b(?:\d{1,3}\s*(?:-\s*)?(?:minutes?|mins?|hours?|hrs?)\s+)?(?:drive|head|go|hike|walk|travel|return)(?:\s+back)?\s+to\s+(@?[^#\n.!?]{3,90}?)(?=\s+(?:(?:and|then|afterwards?|before|after|for|where|which|with)\b|(?:\d{1,3}\s*(?:-\s*)?(?:minutes?|mins?|hours?|hrs?)\s+)?(?:drive|head|go|hike|walk|travel|return)(?:\s+back)?\s+to\b|make\s+sure\b)|[#\n.!?]|$)/giu,
  ];
  for (const pattern of itineraryPatterns) {
    for (const value of captures(phraseText, pattern)) {
      addParsedHint(output, value, {
        modality: source,
        evidence: "itinerary_phrase",
        classification: "destination",
        durable: true,
        trustRank: 4,
      });
    }
  }
  for (const value of captures(
    phraseText,
    /\b(?:grab|grabbing|get|getting|order|ordering|buy|buying|pick(?:ed|ing)?\s+up|rent|renting|eat|eating|drink|drinking|try|trying)\b[^#\n.!?]{0,70}?\bfrom\s+(@?[^#\n.!?]{3,90}?)(?=[#\n.!?]|$)/giu,
  )) {
    addParsedHint(output, value, {
      modality: source,
      evidence: "acquisition_phrase",
      classification: "destination",
      durable: false,
      trustRank: 2,
    });
  }
  for (const line of phraseText.split(/\r?\n/)) {
    const stripped = line
      .replace(/^\s*(?:[-*•▪︎◦]|\d{1,3}[.)]|[^\p{L}\p{N}@#]{1,3})\s*/u, "")
      .trim();
    if (
      stripped !== line.trim()
      && stripped.length >= 3
      && stripped.length <= 120
      && (isStrongVisibleName(stripped) || /^[\p{Lu}\d][^.!?]{2,80}$/u.test(stripped))
    ) {
      addParsedHint(output, stripped, {
        modality: source,
        evidence: "structured_line",
        classification: "destination",
        durable: source !== "transcript",
        trustRank: source === "caption" ? 4 : 3,
      });
    }
  }
  const handleText = numberedItinerary.active
    ? text.split(/\r?\n/).map((line) => {
      const numbered = line.match(/^\s*\d{1,3}[.)]\s+(.{3,160}?)\s*$/u);
      if (!numbered) return line;
      let filtered = line.replace(/\s+(?:with|by)\s+@[A-Za-z0-9._]{3,40}\b/giu, "");
      if (/\b(?:base|stay)\b/iu.test(numbered[1])) {
        const acceptedNames = numberedItineraryObjects(numbered[1]).map((item) => (
          canonicalPlaceName(item.name)
        ));
        filtered = filtered.replace(/@([A-Za-z0-9._]{3,40})/gu, (match, handle) => {
          const handleKey = canonicalPlaceName(readableHandle(handle));
          return acceptedNames.some((name) => name.startsWith(handleKey)) ? handle : match;
        });
      }
      return filtered;
    }).join("\n")
    : text;
  for (const handle of captures(handleText, /@([A-Za-z0-9._]{3,40})/gu)) {
    addHint(output, {
      name: readableHandle(handle),
      area: null,
      modality: source,
      evidence: "social_handle",
      classification: "ambiguous",
      durable: false,
      trustRank: 0,
    });
  }
}

function extractFromVisibleText(text, output, source) {
  if (!text) return;
  const itineraryLines = numberedItineraryLines(text);
  const numberedLineSet = itineraryLines.length >= 2
    ? new Set(itineraryLines.map((item) => item.line))
    : new Set();
  for (const line of text.split(/\r?\n/)) {
    if (numberedLineSet.has(line)) continue;
    const stripped = line
      .replace(/^\s*(?:[-*•▪︎◦]|\d{1,3}[.)])\s*/u, "")
      .trim();
    if (!stripped) continue;
    const parsed = splitNameAndArea(stripped);
    if (parsed && (parsed.area || isStrongVisibleName(parsed.name))) {
      addHint(output, {
        name: parsed.name,
        area: parsed.area,
        modality: source,
        evidence: "image_or_video_text",
        classification: "destination",
        durable: true,
        trustRank: 3,
      });
    }
  }
  extractFromCreatorText(text, output, source);
}

function normalizedEvidenceText(value) {
  if (typeof value === "string") return value.trim() || null;
  if (typeof value === "number") return String(value);
  if (Array.isArray(value)) {
    const joined = value.map(normalizedEvidenceText).filter(Boolean).join("\n");
    return joined || null;
  }
  if (value && typeof value === "object") {
    for (const key of ["text", "description", "sceneDescription", "caption", "value"]) {
      const normalized = normalizedEvidenceText(value[key]);
      if (normalized) return normalized;
    }
  }
  return null;
}

export function normalizeEvidence(value) {
  return {
    title: normalizedEvidenceText(value?.title),
    caption: normalizedEvidenceText(value?.caption),
    authorName: normalizedEvidenceText(value?.authorName),
    taggedLocations: Array.isArray(value?.taggedLocations) ? value.taggedLocations : [],
    media: Array.isArray(value?.media) ? value.media : [],
    transcript: value?.transcript ?? null,
    sceneDescription: normalizedEvidenceText(value?.sceneDescription),
    vendorModelEvidence: Array.isArray(value?.vendorModelEvidence)
      ? value.vendorModelEvidence
      : [],
    modelCandidates: Array.isArray(value?.modelCandidates) ? value.modelCandidates : [],
  };
}

export function extractDeterministicHints(rawEvidence, limit = 150) {
  const evidence = normalizeEvidence(rawEvidence);
  const output = [];
  for (const location of evidence.taggedLocations) {
    addHint(output, {
      name: location.name,
      area: location.address ?? location.area ?? null,
      modality: "tagged_location",
      evidence: "explicit_location",
      classification: "destination",
      durable: true,
      trustRank: 6,
    });
  }
  for (const media of evidence.media) {
    extractFromVisibleText(media.ocrText, output, "ocr");
    extractFromVisibleText(media.videoText, output, "video_text");
    extractFromVisibleText(media.altText, output, "accessibility_text");
  }
  extractFromCreatorText(evidence.caption, output, "caption");
  extractFromCreatorText(evidence.title, output, "title");
  extractFromCreatorText(evidence.transcript?.text, output, "transcript");
  extractFromCreatorText(evidence.sceneDescription, output, "scene_description");
  for (const candidate of evidence.modelCandidates) {
    if (["incidental", "attribution", "not_a_place"].includes(candidate.classification)) {
      continue;
    }
    addHint(output, {
      name: candidate.name,
      area: candidate.area ?? null,
      modality: candidate.modality ?? "model",
      evidence: candidate.evidence ?? "model_grounded",
      classification: candidate.classification ?? "ambiguous",
      durable: candidate.classification !== "ambiguous",
      trustRank: candidate.classification === "destination" ? 5 : 3,
      startMs: candidate.startMs ?? null,
      endMs: candidate.endMs ?? null,
      providerConfidence: candidate.confidence ?? null,
    });
  }
  const combinedText = [evidence.caption, evidence.title].filter(Boolean).join("\n");
  const area = postWideArea(combinedText);
  const contextualHints = output.map((hint) => ({
    ...hint,
    area: hint.area ?? area,
  }));
  const collapsedHints = collapseAliasHints(contextualHints);
  return demoteGeographyContexts(collapsedHints, {
    hasNumberedItinerary: isMultiStopNumberedItinerary(combinedText),
  }).hints.slice(0, limit);
}

function modelGroundingText(evidence) {
  return [
    evidence.title,
    evidence.caption,
    ...evidence.taggedLocations.flatMap((location) => [
      location.name,
      location.address,
      location.area,
    ]),
    ...evidence.media.flatMap((media) => [
      media.ocrText,
      media.videoText,
      media.altText,
    ]),
    evidence.transcript?.text,
    evidence.sceneDescription,
  ].filter(Boolean).join("\n");
}

function groundingContainsName(name, value) {
  const nameWords = normalizedWords(name);
  const valueWords = normalizedWords(value);
  const compactName = nameWords.join("");
  return compactName.length >= 3 && (
    containsTokenSequence(nameWords, valueWords)
    || valueWords.includes(compactName)
  );
}

function modelCandidateGrounding(candidate, evidence, mediaIngestion) {
  if (groundingContainsName(candidate.name, modelGroundingText(evidence))) {
    return { grounding: "independent_text_evidence", rejectionReason: null };
  }
  if (["image_text", "video_text", "speech"].includes(candidate.modality)
      && groundingContainsName(candidate.name, candidate.evidence)) {
    const requiredMediaType = candidate.modality === "image_text" ? "image" : "video";
    const matchingMediaWasIngested = mediaIngestion.some((item) => (
      item?.status === "ok" && item?.type === requiredMediaType
    ));
    if (!matchingMediaWasIngested) {
      return { grounding: null, rejectionReason: "missing_ingested_media" };
    }
    // The model directly inspected media bytes, so no independent OCR/STT text
    // may exist. Keep this path explicit: it is model-attested media evidence,
    // not independently verified grounding.
    return { grounding: "model_attested_media_evidence", rejectionReason: null };
  }
  return { grounding: null, rejectionReason: null };
}

function modelCandidateRejectionReason(candidate) {
  if (!candidate || typeof candidate.name !== "string") return "missing_name";
  if (!["destination", "itinerary"].includes(candidate.classification)) {
    return "non_destination_classification";
  }
  if (![
    "caption", "tagged_location", "image_text", "video_text", "speech",
  ].includes(candidate.modality)) {
    return "unsupported_modality";
  }
  if (!Number.isFinite(candidate.confidence)
      || candidate.confidence < 0
      || candidate.confidence > 1) {
    return "invalid_confidence";
  }
  if (typeof candidate.evidence !== "string" || candidate.evidence.trim().length < 3) {
    return "missing_evidence";
  }
  if (candidate.name.length > 100 || isGeneric(candidate.name)
      || !hasDistinctiveToken(candidate.name) || isAttribution(candidate.name)) {
    return "invalid_place_name";
  }
  return null;
}

function modelHintsAreAliases(lhs, rhs) {
  if (lhs.area && rhs.area && canonicalPlaceName(lhs.area) !== canonicalPlaceName(rhs.area)) {
    return false;
  }
  const first = canonicalPlaceName(lhs.name).split(/\s+/).filter(Boolean);
  const second = canonicalPlaceName(rhs.name).split(/\s+/).filter(Boolean);
  if (first.length === 0 || second.length === 0) return false;
  if (first.join(" ") === second.join(" ")) return true;
  const ignoredEntitySuffixes = new Set(["co", "company", "inc", "llc", "restaurant"]);
  const withoutSuffixes = (tokens) => {
    const result = [...tokens];
    while (result.length > 0 && ignoredEntitySuffixes.has(result.at(-1))) result.pop();
    return result;
  };
  return withoutSuffixes(first).join(" ") === withoutSuffixes(second).join(" ");
}

function preferredModelHint(lhs, rhs) {
  const actionWrapper = (value) => /^(?:base|drive|eat|explore|finish|fish|go|grab|head|hike|shop|stay|stroll|take|walk)\b/i
    .test(value.trim());
  if (actionWrapper(lhs.name) !== actionWrapper(rhs.name)) {
    return actionWrapper(rhs.name) ? lhs : rhs;
  }
  const specificity = (value) => normalizedWords(value).reduce((score, token) => (
    score + (strongPlaceDesignators.has(token) ? 2 : (weakPlaceDesignators.has(token) ? 1 : 0))
  ), 0);
  const lhsSpecificity = specificity(lhs.name);
  const rhsSpecificity = specificity(rhs.name);
  if (lhsSpecificity !== rhsSpecificity) {
    return rhsSpecificity > lhsSpecificity ? rhs : lhs;
  }
  if (lhs.trustRank !== rhs.trustRank) return rhs.trustRank > lhs.trustRank ? rhs : lhs;
  if (Boolean(lhs.area) !== Boolean(rhs.area)) return rhs.area ? rhs : lhs;
  return normalizedWords(rhs.name).length < normalizedWords(lhs.name).length ? rhs : lhs;
}

function collapseAliasHints(hints) {
  const collapsed = [];
  for (const hint of hints) {
    const existingIndex = collapsed.findIndex((item) => modelHintsAreAliases(item, hint));
    if (existingIndex < 0) collapsed.push(hint);
    else collapsed[existingIndex] = preferredModelHint(collapsed[existingIndex], hint);
  }
  return collapsed;
}

/**
 * Converts a successful structured-model response into the only hints that may
 * reach POI lookup. Raw caption/OCR heuristics are deliberately not merged back
 * into a successful semantic result: doing so reintroduced the source chrome,
 * creator handles, geography, and instruction fragments the model classified.
 */
export function extractGroundedModelHints(
  rawEvidence,
  limit = 150,
  { mediaIngestion = [] } = {},
) {
  const evidence = normalizeEvidence(rawEvidence);
  const hints = [];
  const rejections = [];
  let mergedAliasCount = 0;
  let independentlyGroundedCount = 0;
  let modelAttestedMediaCount = 0;
  for (const candidate of evidence.modelCandidates) {
    let reason = modelCandidateRejectionReason(candidate);
    const groundingSelection = reason
      ? { grounding: null, rejectionReason: null }
      : modelCandidateGrounding(candidate, evidence, mediaIngestion);
    const grounding = groundingSelection.grounding;
    if (!reason && groundingSelection.rejectionReason) {
      reason = groundingSelection.rejectionReason;
    }
    if (!reason && !grounding) reason = "ungrounded_name";
    if (reason) {
      rejections.push({
        name: typeof candidate?.name === "string" ? candidate.name : null,
        classification: candidate?.classification ?? null,
        reason,
      });
      continue;
    }
    const hint = {
      // The structured candidate name is already a dedicated field. Creator-
      // text phrase trimming would corrupt legitimate names such as "Atte for
      // Coffee" and "Story and Soil Coffee".
      name: candidate.name.trim(),
      area: candidate.area || null,
      modality: candidate.modality,
      evidence: candidate.evidence,
      classification: candidate.classification,
      durable: true,
      trustRank: candidate.classification === "destination" ? 5 : 3,
      startMs: candidate.startMs ?? null,
      endMs: candidate.endMs ?? null,
      providerConfidence: candidate.confidence,
      grounding,
    };
    if (grounding === "independent_text_evidence") independentlyGroundedCount += 1;
    if (grounding === "model_attested_media_evidence") modelAttestedMediaCount += 1;
    const existingIndex = hints.findIndex((item) => modelHintsAreAliases(item, hint));
    if (existingIndex < 0) hints.push(hint);
    else {
      hints[existingIndex] = preferredModelHint(hints[existingIndex], hint);
      mergedAliasCount += 1;
    }
  }
  const contextSelection = demoteGeographyContexts(hints);
  return {
    hints: contextSelection.hints.slice(0, limit),
    validation: {
      candidateCount: evidence.modelCandidates.length,
      acceptedCount: Math.min(contextSelection.hints.length, limit),
      rejectedCount: rejections.length,
      mergedAliasCount,
      independentlyGroundedCount,
      modelAttestedMediaCount,
      demotedContextCount: contextSelection.contexts.length,
      truncatedCount: Math.max(0, contextSelection.hints.length - limit),
      rejections,
      demotedContexts: contextSelection.contexts,
    },
  };
}

function labelMatchesPrediction(label, prediction) {
  const predictionKey = canonicalPlaceName(prediction).replaceAll(" ", "");
  const predictionSupplementalKey = scoringSupplementalKey(prediction);
  const predictionCore = coreName(prediction);
  return [label.name, ...(label.aliases ?? [])].some((name) => {
    const labelKey = canonicalPlaceName(name).replaceAll(" ", "");
    const labelSupplementalKey = scoringSupplementalKey(name);
    if (labelKey && labelKey === predictionKey) return true;
    if (
      labelSupplementalKey &&
      labelSupplementalKey === predictionSupplementalKey
    ) return true;
    // A hint can preserve surrounding creator text (for example
    // "Yintang Spicy Hotpot, Convoy") and still contain the full labeled name.
    // Keep this deliberately one-way: a fragment such as "Caption" must never
    // satisfy "Caption by Hyatt Namba".
    if (labelKey.length >= 5 && predictionKey.includes(labelKey)) return true;
    if (
      labelSupplementalKey.length >= 5 &&
      predictionSupplementalKey.includes(labelSupplementalKey)
    ) return true;
    const labelCore = coreName(name);
    return Boolean(labelCore && labelCore === predictionCore);
  });
}

function scoringSupplementalKey(value) {
  const aliasAware = String(value ?? "")
    .normalize("NFKD")
    .replace(/&/gu, " and ")
    // Providers commonly expand an official apostrophe-year brand such as
    // `Since '93` to `Since 1993`. Limit this equivalence to a four-digit year
    // immediately following `since`; ordinary numbers and different years
    // remain distinct.
    .replace(/\bsince\s+(?:19|20)(\d{2})\b/giu, "since $1");
  return canonicalPlaceName(aliasAware).replaceAll(" ", "");
}

export function scorePredictions(labels, predictions) {
  if (!labels || !["labeled", "provisional"].includes(labels.status)) {
    return { scorable: false, labelStatus: labels?.status ?? "missing" };
  }
  const uniquePredictions = [];
  for (const prediction of predictions.filter(Boolean)) {
    // Dedupe only genuinely equivalent renderings. `namesEquivalent` also
    // supports containment for provider spelling variants; using it here can
    // let an early fragment ("Caption") erase a later complete prediction
    // ("Caption by Hyatt Namba Osaka") before ground-truth scoring.
    const predictionKey = canonicalPlaceName(prediction).replaceAll(" ", "");
    const predictionSupplementalKey = scoringSupplementalKey(prediction);
    const predictionCore = coreName(prediction);
    if (!uniquePredictions.some((item) => {
      const itemKey = canonicalPlaceName(item).replaceAll(" ", "");
      const itemSupplementalKey = scoringSupplementalKey(item);
      const itemCore = coreName(item);
      return itemKey === predictionKey
        || Boolean(
          itemSupplementalKey &&
          itemSupplementalKey === predictionSupplementalKey
        )
        || Boolean(itemCore && predictionCore && itemCore === predictionCore);
    })) {
      uniquePredictions.push(prediction);
    }
  }
  // Match labels and predictions one-to-one. Without an injective match, one
  // combined prediction such as "Alpha Cafe and Bravo Hotel" can satisfy two
  // required labels while counting as only one precise prediction. Required
  // labels get first claim on predictions; acceptable labels use only what is
  // left after the maximum required-label matching has been found.
  const matchLabels = (candidateLabels, availablePredictionIndexes) => {
    const predictionToLabel = new Map();
    const visit = (labelIndex, visitedPredictions) => {
      for (const predictionIndex of availablePredictionIndexes) {
        if (visitedPredictions.has(predictionIndex)) continue;
        if (!labelMatchesPrediction(
          candidateLabels[labelIndex],
          uniquePredictions[predictionIndex],
        )) continue;
        visitedPredictions.add(predictionIndex);
        const previousLabelIndex = predictionToLabel.get(predictionIndex);
        if (previousLabelIndex == null || visit(previousLabelIndex, visitedPredictions)) {
          predictionToLabel.set(predictionIndex, labelIndex);
          return true;
        }
      }
      return false;
    };
    for (const labelIndex of candidateLabels.keys()) visit(labelIndex, new Set());
    const labelToPrediction = new Map(
      [...predictionToLabel].map(([predictionIndex, labelIndex]) => [labelIndex, predictionIndex]),
    );
    return { labelToPrediction, predictionToLabel };
  };
  const allPredictionIndexes = uniquePredictions.map((_, index) => index);
  const requiredMatching = matchLabels(labels.required, allPredictionIndexes);
  const unusedPredictionIndexes = allPredictionIndexes.filter(
    (index) => !requiredMatching.predictionToLabel.has(index),
  );
  const acceptableMatching = matchLabels(labels.acceptable, unusedPredictionIndexes);
  const requiredHits = labels.required.filter((_, index) =>
    requiredMatching.labelToPrediction.has(index)
  );
  const acceptableHits = labels.acceptable.filter((_, index) =>
    acceptableMatching.labelToPrediction.has(index)
  );
  const correctPredictionIndexes = new Set([
    ...requiredMatching.predictionToLabel.keys(),
    ...acceptableMatching.predictionToLabel.keys(),
  ]);
  const correctPredictions = uniquePredictions.filter((_, index) =>
    correctPredictionIndexes.has(index)
  );
  const falsePredictions = uniquePredictions.filter((_, index) =>
    !correctPredictionIndexes.has(index)
  );
  // Forbidden labels describe standalone false-positive predictions. A venue
  // already consumed by required/acceptable matching must not be penalized a
  // second time merely because its proper name contains a forbidden geography
  // (for example "Billy Bob's Texas" or "Sake House Malibu").
  const forbiddenHits = labels.forbidden.filter((label) =>
    falsePredictions.some((prediction) => labelMatchesPrediction(label, prediction))
  );
  const precision = uniquePredictions.length === 0
    ? (labels.required.length === 0 ? 1 : 0)
    : correctPredictions.length / uniquePredictions.length;
  const recall = labels.required.length === 0
    ? 1
    : requiredHits.length / labels.required.length;
  const f1 = precision + recall === 0 ? 0 : (2 * precision * recall) / (precision + recall);
  return {
    scorable: true,
    labelStatus: labels.status,
    requiredCount: labels.required.length,
    requiredHitCount: requiredHits.length,
    acceptableHitCount: acceptableHits.length,
    forbiddenHitCount: forbiddenHits.length,
    predictionCount: uniquePredictions.length,
    precision,
    recall,
    f1,
    postSuccess: labels.required.length === 0 || requiredHits.length > 0,
    exactRequiredSet: requiredHits.length === labels.required.length
      && falsePredictions.length === 0,
    requiredMisses: labels.required
      .filter((label) => !requiredHits.includes(label))
      .map((label) => label.name),
    forbiddenHits: forbiddenHits.map((label) => label.name),
    falsePredictions,
  };
}

function average(values) {
  return values.length === 0 ? null : values.reduce((sum, value) => sum + value, 0) / values.length;
}

function microScore(scores) {
  if (scores.length === 0) {
    return {
      required: 0,
      requiredHits: 0,
      predictions: 0,
      correctPredictions: 0,
      precision: null,
      recall: null,
      f1: null,
    };
  }
  const totals = scores.reduce((output, score) => {
    output.required += score.requiredCount;
    output.requiredHits += score.requiredHitCount;
    output.predictions += score.predictionCount;
    output.correctPredictions += score.predictionCount - score.falsePredictions.length;
    return output;
  }, { required: 0, requiredHits: 0, predictions: 0, correctPredictions: 0 });
  const precision = totals.predictions === 0
    ? (totals.required === 0 ? 1 : 0)
    : totals.correctPredictions / totals.predictions;
  const recall = totals.required === 0 ? 1 : totals.requiredHits / totals.required;
  const f1 = precision + recall === 0 ? 0 : (2 * precision * recall) / (precision + recall);
  return { ...totals, precision, recall, f1 };
}

function expectedModalityBreakdown(items) {
  const modalities = [...new Set(items.flatMap((item) => item.case.modalitiesExpected ?? []))].sort();
  return modalities.map((modality) => {
    const grouped = items.filter((item) => item.case.modalitiesExpected?.includes(modality));
    const scores = grouped
      .map((item) => item.scores?.extraction)
      .filter((score) => score?.scorable);
    const micro = microScore(scores);
    return {
      modality,
      caseCount: grouped.length,
      completeAcquisitionRate: average(grouped.map((item) =>
        item.acquisition.status === "ok" && item.acquisition.modalityCoverage?.complete === true
          ? 1
          : 0
      )),
      extractionPrecision: average(scores.map((score) => score.precision)),
      extractionRecall: average(scores.map((score) => score.recall)),
      extractionMicroPrecision: micro.precision,
      extractionMicroRecall: micro.recall,
      postSuccessRate: average(scores.map((score) => score.postSuccess ? 1 : 0)),
      exactSetRate: average(scores.map((score) => score.exactRequiredSet ? 1 : 0)),
      requiredPlaceCount: micro.required,
      requiredPlaceHitCount: micro.requiredHits,
    };
  });
}

export function buildSummary(results) {
  const variants = new Map();
  for (const result of results) {
    const key = result.variant;
    if (!variants.has(key)) variants.set(key, []);
    variants.get(key).push(result);
  }
  const summaries = [];
  for (const [variant, items] of variants) {
    const primary = items.filter((item) => item.case.labels.status === "labeled");
    const provisional = items.filter((item) => item.case.labels.status === "provisional");
    const extractionScored = primary
      .map((item) => item.scores?.extraction)
      .filter((score) => score?.scorable);
    const selectedNameScoredItems = primary.filter((item) =>
      item.scores?.endToEndStage === "selected_mapkit_names"
    );
    const scored = selectedNameScoredItems
      .map((item) => item.scores?.endToEnd)
      .filter((score) => score?.scorable);
    const provisionalScores = provisional
      .filter((item) => item.scores?.endToEndStage === "selected_mapkit_names")
      .map((item) => item.scores?.endToEnd)
      .filter((score) => score?.scorable);
    const poiLookups = items.flatMap((item) => item.poiResolution?.response?.results ?? []);
    const poiLookupHealth = [
      ...poiLookups.map((lookup) => lookup.error ? 0 : 1),
      // A helper crash/timeout has no per-hint response to flatten, but it is
      // still a failed POI-stage attempt and must remain in the denominator.
      ...items
        .filter((item) => item.poiResolution?.status === "failed")
        .map(() => 0),
    ];
    const transportSuccess = items.map((item) => item.acquisition.status === "ok" ? 1 : 0);
    const completeAcquisition = items.map((item) =>
      item.acquisition.status === "ok" && item.acquisition.modalityCoverage?.complete === true
        ? 1
        : 0
    );
    const extractionMicro = microScore(extractionScored);
    const placeMicro = microScore(scored);
    const fallbackAssistedItems = primary.filter((item) => item.understanding?.fallback?.used === true);
    const modelSuccessScores = primary
      .filter((item) => item.understanding?.fallback?.used !== true
        && ["ok", "partial"].includes(item.understanding?.status))
      .map((item) => item.scores?.extraction)
      .filter((score) => score?.scorable);
    const modelSuccessMicro = microScore(modelSuccessScores);
    summaries.push({
      variant,
      casesAttempted: items.length,
      acquisitionTransportSuccessRate: average(transportSuccess),
      completeAcquisitionRate: average(completeAcquisition),
      understandingSuccessRate: average(items.map((item) => item.understanding.status === "ok" ? 1 : 0)),
      fallbackAssistedCaseCount: fallbackAssistedItems.length,
      fallbackAssistedCaseRate: average(primary.map((item) =>
        item.understanding?.fallback?.used === true ? 1 : 0
      )),
      modelSuccessLabeledCaseCount: modelSuccessScores.length,
      modelSuccessExtractionPrecision: average(modelSuccessScores.map((score) => score.precision)),
      modelSuccessExtractionRecall: average(modelSuccessScores.map((score) => score.recall)),
      modelSuccessExtractionMicroPrecision: modelSuccessMicro.precision,
      modelSuccessExtractionMicroRecall: modelSuccessMicro.recall,
      modelSuccessRequiredPlaceCount: modelSuccessMicro.required,
      modelSuccessRequiredPlaceHitCount: modelSuccessMicro.requiredHits,
      primaryLabeledCaseCount: extractionScored.length,
      selectedNameLabeledCaseCount: scored.length,
      extractionPrecision: average(extractionScored.map((score) => score.precision)),
      extractionRecall: average(extractionScored.map((score) => score.recall)),
      extractionMicroPrecision: extractionMicro.precision,
      extractionMicroRecall: extractionMicro.recall,
      extractionMicroF1: extractionMicro.f1,
      extractionPostSuccessRate: average(extractionScored.map((score) => score.postSuccess ? 1 : 0)),
      extractionExactSetRate: average(extractionScored.map((score) => score.exactRequiredSet ? 1 : 0)),
      selectedNamePrecision: average(scored.map((score) => score.precision)),
      selectedNameRecall: average(scored.map((score) => score.recall)),
      selectedNameF1: average(scored.map((score) => score.f1)),
      selectedNameMicroPrecision: placeMicro.precision,
      selectedNameMicroRecall: placeMicro.recall,
      selectedNameMicroF1: placeMicro.f1,
      selectedNamePostSuccessRate: average(scored.map((score) => score.postSuccess ? 1 : 0)),
      selectedNameExactSetRate: average(scored.map((score) => score.exactRequiredSet ? 1 : 0)),
      selectedNameRequiredCount: placeMicro.required,
      selectedNameRequiredHitCount: placeMicro.requiredHits,
      selectedNameForbiddenHits: scored.reduce((sum, score) => sum + score.forbiddenHitCount, 0),
      poiLookupSuccessRate: average(poiLookupHealth),
      poiSelectionRate: average(poiLookups.map((lookup) => lookup.selectedCandidateID ? 1 : 0)),
      meanLatencyMs: average(items.map((item) => item.timing.totalMs)),
      byExpectedModality: expectedModalityBreakdown(primary),
      provisional: {
        caseCount: provisionalScores.length,
        selectedNamePrecision: average(provisionalScores.map((score) => score.precision)),
        selectedNameRecall: average(provisionalScores.map((score) => score.recall)),
      },
    });
  }
  return {
    schemaVersion: 3,
    generatedAt: new Date().toISOString(),
    metricDefinitions: {
      macro: "Average of per-post scores; each post has equal weight.",
      micro: "Counts all labeled place mentions together; dense posts have proportionally more weight.",
      postSuccess: "At least one required place was extracted from the post.",
      exactSet: "Every required place and no false-positive place was extracted from the post.",
      acquisitionTransport: "The source/provider request returned usable evidence, even if some required modalities were missing.",
      completeAcquisition: "Every expected modality and minimum expected media asset passed a bounded fetch/MIME probe.",
      fallbackAssisted: "Cases where failed model understanding was replaced by explicitly recorded deterministic extraction from acquired evidence.",
      modelSuccessQuality: "Extraction quality restricted to labeled cases with successful/partial model understanding and no deterministic failure fallback.",
      byExpectedModality: "Case-group metrics for posts declaring that expected modality; individual labels are not assigned to one modality.",
      selectedName: "Name/alias accuracy for candidates selected by MapKit. The corpus does not yet validate physical branch identity, address, provider ID, or coordinates.",
    },
    variants: summaries,
  };
}

function percentage(value) {
  return value == null ? "—" : (value * 100).toFixed(1) + "%";
}

export function renderSummaryMarkdown(summary) {
  const lines = [
    "# Social importer evaluation summary",
    "",
    "Only corpus cases marked 'labeled' contribute to primary quality metrics. Provisional and pending-label cases remain visible in raw results but cannot silently inflate the score.",
    "",
    "Hint and selected-name P/R are shown as macro (equal post weight), then micro (equal place-mention weight). Selected-name quality does not validate physical POI identity.",
    "",
    "| Variant | Transport | Complete acquisition | Understanding | Fallback-assisted | Hint macro P/R | Hint micro P/R | Post ≥1 | Exact set | Selected-name macro P/R | POI lookup health | POI selection | Mean latency |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
  ];
  for (const item of summary.variants) {
    lines.push(
      "| " + item.variant
      + " | " + percentage(item.acquisitionTransportSuccessRate)
      + " | " + percentage(item.completeAcquisitionRate)
      + " | " + percentage(item.understandingSuccessRate)
      + " | " + percentage(item.fallbackAssistedCaseRate)
      + " | " + percentage(item.extractionPrecision) + " / " + percentage(item.extractionRecall)
      + " | " + percentage(item.extractionMicroPrecision) + " / " + percentage(item.extractionMicroRecall)
      + " | " + percentage(item.extractionPostSuccessRate)
      + " | " + percentage(item.extractionExactSetRate)
      + " | " + percentage(item.selectedNamePrecision) + " / " + percentage(item.selectedNameRecall)
      + " | " + percentage(item.poiLookupSuccessRate)
      + " | " + percentage(item.poiSelectionRate)
      + " | " + (item.meanLatencyMs == null ? "—" : Math.round(item.meanLatencyMs) + " ms")
      + " |",
    );
  }
  lines.push("");
  lines.push("## Expected-modality case groups");
  lines.push("");
  lines.push("A post can appear in more than one group. These are case-group metrics; labels are not individually attributed to a modality.");
  lines.push("");
  lines.push("| Variant | Expected modality | Cases | Complete acquisition | Hint macro P/R | Hint micro P/R | Post ≥1 | Exact set |");
  lines.push("|---|---|---:|---:|---:|---:|---:|---:|");
  for (const item of summary.variants) {
    for (const group of item.byExpectedModality ?? []) {
      lines.push(
        "| " + item.variant
        + " | " + group.modality
        + " | " + group.caseCount
        + " | " + percentage(group.completeAcquisitionRate)
        + " | " + percentage(group.extractionPrecision) + " / " + percentage(group.extractionRecall)
        + " | " + percentage(group.extractionMicroPrecision) + " / " + percentage(group.extractionMicroRecall)
        + " | " + percentage(group.postSuccessRate)
        + " | " + percentage(group.exactSetRate)
        + " |",
      );
    }
  }
  lines.push("");
  lines.push("Stage-level details, misses, false positives, provider errors, POI candidates, and timings are in results.json.");
  lines.push("");
  return lines.join("\n");
}

export function defaultOutputDirectory(rootDirectory) {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  return join(rootDirectory, "runs", timestamp);
}
