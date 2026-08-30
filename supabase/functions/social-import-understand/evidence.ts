import { cleanString } from "./source.ts";
import type {
  AcquisitionEvidence,
  EvidenceCatalog,
  EvidenceModality,
  MediaIngestion,
  ModelCandidate,
  ModelPostContext,
  PlaceHint,
} from "./types.ts";

const acceptedClassifications = new Set(["destination", "itinerary"]);
const intentionalExclusionClassifications = new Set([
  "incidental",
  "attribution",
  "not_a_place",
]);
export const minimumGroundedConfidence = 0.55;
const acceptedModalities = new Set<EvidenceModality>([
  "caption",
  "tagged_location",
  "alt_text",
  "image_text",
  "video_text",
  "speech",
]);
const geographyEntityTypes = new Set<ModelCandidate["entityType"]>([
  "locality",
  "region",
  "country",
]);
const declaredCountNouns = new Set([
  "attraction",
  "attractions",
  "bar",
  "bars",
  "beach",
  "beaches",
  "cafe",
  "cafes",
  "city",
  "cities",
  "country",
  "countries",
  "destination",
  "destinations",
  "hike",
  "hikes",
  "hotel",
  "hotels",
  "location",
  "locations",
  "museum",
  "museums",
  "park",
  "parks",
  "place",
  "places",
  "recommendation",
  "recommendations",
  "restaurant",
  "restaurants",
  "shop",
  "shops",
  "spot",
  "spots",
  "state",
  "states",
  "stop",
  "stops",
  "store",
  "stores",
  "town",
  "towns",
  "trail",
  "trails",
  "venue",
  "venues",
]);
const declaredCountNames = [
  "zero",
  "one",
  "two",
  "three",
  "four",
  "five",
  "six",
  "seven",
  "eight",
  "nine",
  "ten",
  "eleven",
  "twelve",
  "thirteen",
  "fourteen",
  "fifteen",
  "sixteen",
  "seventeen",
  "eighteen",
  "nineteen",
  "twenty",
];

type PreparedHint = {
  hint: PlaceHint;
  entityType: ModelCandidate["entityType"];
  itemIndex: number;
};

type GroundedPostContext = {
  intent: ModelPostContext["intent"];
  declaredCount: number | null;
  globalArea: string | null;
  globalAreaEvidenceIDs: string[];
};

export function evidenceCatalog(
  evidence: AcquisitionEvidence,
): EvidenceCatalog {
  const texts: EvidenceCatalog["texts"] = [];
  if (evidence.caption) {
    texts.push({
      id: "caption:0",
      modality: "caption",
      text: evidence.caption,
      area: null,
      mediaID: null,
    });
  }
  for (const [index, location] of evidence.taggedLocations.entries()) {
    texts.push({
      id: `tagged_location:${index}`,
      modality: "tagged_location",
      text: location.name,
      area: location.area,
      mediaID: null,
    });
  }
  for (const media of evidence.media) {
    if (!media.altText) continue;
    texts.push({
      id: `alt_text:${media.index}`,
      modality: "alt_text",
      text: media.altText,
      area: null,
      mediaID: media.id,
    });
  }
  return { texts, media: evidence.media };
}

export function groundedHints(
  candidates: ModelCandidate[],
  catalog: EvidenceCatalog,
  ingestions: MediaIngestion[],
  limit = 150,
  postContext?: ModelPostContext,
): {
  hints: PlaceHint[];
  rejectedCount: number;
  excludedCount: number;
  intentionalExcludedCount: number;
} {
  const textByID = new Map(catalog.texts.map((item) => [item.id, item]));
  const mediaByID = new Map(catalog.media.map((item) => [item.id, item]));
  const ingestionByID = new Map(ingestions.map((item) => [item.mediaID, item]));
  const context = groundedPostContext(
    postContext,
    textByID,
    mediaByID,
    ingestionByID,
  );
  const prepared: PreparedHint[] = [];
  const preparedIndexes = new Map<string, number>();
  let rejectedCount = 0;
  let excludedCount = 0;
  let intentionalExcludedCount = 0;

  for (const candidate of candidates.slice(0, 300)) {
    if (!acceptedClassifications.has(candidate.classification)) {
      if (
        intentionalExclusionClassifications.has(candidate.classification)
      ) {
        excludedCount += 1;
        intentionalExcludedCount += 1;
      } else {
        rejectedCount += 1;
      }
      continue;
    }
    const name = cleanString(candidate.name, 160);
    const area = cleanString(candidate.area, 160);
    const evidenceIDs = [
      ...new Set(
        candidate.evidenceIds
          .map((value) => cleanString(value, 80))
          .filter((value): value is string => value !== null),
      ),
    ]
      .slice(0, 8);
    if (
      !name ||
      !acceptedModalities.has(candidate.modality) ||
      !Number.isFinite(candidate.confidence) ||
      candidate.confidence < minimumGroundedConfidence ||
      candidate.confidence > 1 || evidenceIDs.length === 0 ||
      !isGrounded(
        name,
        candidate.modality,
        evidenceIDs,
        textByID,
        mediaByID,
        ingestionByID,
      )
    ) {
      rejectedCount += 1;
      continue;
    }

    const attestedArea = textualModality(candidate.modality)
      ? textAttestedArea(
        area,
        candidate.modality,
        evidenceIDs,
        textByID,
      )
      : area;
    const usesGlobalArea = !geographyEntityTypes.has(candidate.entityType) &&
      !attestedArea && context.globalArea !== null;
    const hint: PlaceHint = {
      name,
      area: attestedArea ?? (usesGlobalArea ? context.globalArea : null),
      classification: candidate.classification as "destination" | "itinerary",
      // The iOS contract treats accessibility text as image-derived text.
      modality: candidate.modality === "alt_text"
        ? "image_text"
        : candidate.modality,
      evidence_ids: usesGlobalArea
        ? [...new Set([...evidenceIDs, ...context.globalAreaEvidenceIDs])]
          .slice(
            0,
            8,
          )
        : evidenceIDs,
      confidence: candidate.confidence,
      start_ms: finiteTimestamp(candidate.startMs),
      end_ms: finiteTimestamp(candidate.endMs),
    };
    const identity = normalizedIdentity(name, hint.area);
    const existingIndex = preparedIndexes.get(identity);
    const value: PreparedHint = {
      hint,
      entityType: candidate.entityType,
      itemIndex: candidate.itemIndex,
    };
    if (existingIndex === undefined) {
      preparedIndexes.set(identity, prepared.length);
      prepared.push(value);
    } else {
      excludedCount += 1;
      if (hint.confidence > prepared[existingIndex].hint.confidence) {
        prepared[existingIndex] = value;
      }
    }
  }

  const withoutGeographyContext = prepared.filter(
    (candidate, index, values) => {
      if (context.intent === "geography_list") return true;
      if (
        context.intent === "place_list" &&
        geographyEntityTypes.has(candidate.entityType)
      ) {
        excludedCount += 1;
        return false;
      }
      const nameIdentity = normalizedValue(candidate.hint.name);
      if (!nameIdentity) return true;
      const matchesGlobalArea = context.globalArea !== null &&
        isGlobalAreaVariant(candidate.hint.name, context.globalArea);
      const matchesAnotherArea = geographyEntityTypes.has(
        candidate.entityType,
      ) && values.some((other, otherIndex) =>
        otherIndex !== index && other.hint.area !== null &&
        nameIdentity === normalizedValue(other.hint.area)
      );
      if (!matchesGlobalArea && !matchesAnotherArea) return true;
      excludedCount += 1;
      return false;
    },
  );

  const onePerItem: PreparedHint[] = [];
  const itemIndexes = new Map<number, number>();
  for (const candidate of withoutGeographyContext) {
    if (candidate.itemIndex < 0) {
      onePerItem.push(candidate);
      continue;
    }
    const existingIndex = itemIndexes.get(candidate.itemIndex);
    if (existingIndex === undefined) {
      itemIndexes.set(candidate.itemIndex, onePerItem.length);
      onePerItem.push(candidate);
      continue;
    }
    excludedCount += 1;
    if (
      candidate.hint.confidence > onePerItem[existingIndex].hint.confidence
    ) {
      onePerItem[existingIndex] = candidate;
    }
  }

  const usesDeclaredCount = context.intent === "place_list" ||
    context.intent === "geography_list";
  const groundedLimit = context.declaredCount === null || !usesDeclaredCount
    ? limit
    : Math.min(limit, context.declaredCount);
  const ordered = onePerItem
    .map((candidate, stableIndex) => ({ candidate, stableIndex }))
    .sort((left, right) => {
      const leftIndex = left.candidate.itemIndex;
      const rightIndex = right.candidate.itemIndex;
      if (leftIndex < 0 && rightIndex < 0) {
        return left.stableIndex - right.stableIndex;
      }
      if (leftIndex < 0) return 1;
      if (rightIndex < 0) return -1;
      return leftIndex - rightIndex || left.stableIndex - right.stableIndex;
    })
    .map(({ candidate }) => candidate);
  const hints = ordered.slice(0, groundedLimit).map((value) => value.hint);
  excludedCount += Math.max(0, ordered.length - groundedLimit);
  return {
    hints,
    rejectedCount,
    excludedCount,
    intentionalExcludedCount,
  };
}

function isGlobalAreaVariant(name: string, globalArea: string): boolean {
  const nameIdentity = normalizedValue(name);
  if (!nameIdentity) return false;
  if (nameIdentity === normalizedValue(globalArea)) return true;
  const primaryWords = words(globalArea.split(",", 1)[0] ?? "");
  if (primaryWords.length < 2) return false;
  if (nameIdentity === primaryWords.join("")) return true;
  const acronym = primaryWords.map((word) => word[0]).join("");
  return words(name).length === 1 && nameIdentity === acronym;
}

function groundedPostContext(
  context: ModelPostContext | undefined,
  textByID: Map<string, EvidenceCatalog["texts"][number]>,
  mediaByID: Map<string, EvidenceCatalog["media"][number]>,
  ingestionByID: Map<string, MediaIngestion>,
): GroundedPostContext {
  const intent = context?.intent ?? "unknown";
  const declaredCount = context?.declaredCount ?? -1;
  const declaredEvidenceIDs = contextEvidenceIDs(
    context?.declaredCountEvidenceIds ?? [],
    textByID,
    mediaByID,
    ingestionByID,
    (evidence) => textContainsDeclaredCount(evidence.text, declaredCount),
  );
  const globalArea = cleanString(context?.globalArea, 160);
  const globalAreaEvidenceIDs = globalArea
    ? contextEvidenceIDs(
      context?.globalAreaEvidenceIds ?? [],
      textByID,
      mediaByID,
      ingestionByID,
      (evidence) => textAttestsGlobalArea(evidence, globalArea),
    )
    : [];
  return {
    intent,
    declaredCount: Number.isInteger(declaredCount) && declaredCount >= 0 &&
        declaredCount <= 150 && declaredEvidenceIDs.length > 0
      ? declaredCount
      : null,
    globalArea: globalArea && globalAreaEvidenceIDs.length > 0
      ? globalArea
      : null,
    globalAreaEvidenceIDs,
  };
}

function textAttestsGlobalArea(
  evidence: EvidenceCatalog["texts"][number],
  globalArea: string,
): boolean {
  if (
    containsTokenSequence(evidence.text, globalArea) ||
    (evidence.area !== null &&
      containsTokenSequence(evidence.area, globalArea))
  ) return true;
  const primaryArea = globalArea.split(",", 1)[0]?.trim() ?? "";
  const primaryWords = words(primaryArea);
  if (primaryWords.length < 2) return false;
  const compactPrimary = primaryWords.join("");
  const evidenceWords = new Set(words(evidence.text));
  if (compactPrimary.length >= 6 && evidenceWords.has(compactPrimary)) {
    return true;
  }
  const acronym = primaryWords.map((word) => word[0]).join("").toUpperCase();
  if (acronym.length < 2 || acronym.length > 5) return false;
  const escaped = acronym.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(?:^|[^A-Za-z])${escaped}(?:$|[^A-Za-z])`).test(
    evidence.text,
  );
}

function contextEvidenceIDs(
  values: string[],
  textByID: Map<string, EvidenceCatalog["texts"][number]>,
  mediaByID: Map<string, EvidenceCatalog["media"][number]>,
  ingestionByID: Map<string, MediaIngestion>,
  textMatches: (evidence: EvidenceCatalog["texts"][number]) => boolean,
): string[] {
  return [
    ...new Set(
      values
        .map((value) => cleanString(value, 80))
        .filter((value): value is string => value !== null),
    ),
  ].filter((id) => {
    const text = textByID.get(id);
    if (text) return textMatches(text);
    const media = mediaByID.get(id);
    const ingestion = ingestionByID.get(id);
    return media !== undefined && ingestion?.status === "ok";
  }).slice(0, 8);
}

function textContainsDeclaredCount(value: string, count: number): boolean {
  if (!Number.isInteger(count) || count < 0) return false;
  const countTokens = new Set([String(count)]);
  if (count < declaredCountNames.length) {
    countTokens.add(declaredCountNames[count]);
  }
  for (const line of value.split(/\r?\n/u)) {
    const lineWords = words(line);
    for (const [index, token] of lineWords.entries()) {
      if (!countTokens.has(token)) continue;
      const isNumberedMarker = token === String(count) && index === 0 &&
        new RegExp(`^\\s*${count}[.)]\\s+`, "u").test(line);
      if (isNumberedMarker) continue;
      if (
        lineWords.slice(index + 1, index + 5).some((word) =>
          declaredCountNouns.has(word)
        )
      ) return true;
    }
  }

  if (count < 2) return false;
  const numberedItems = value.split(/\r?\n/u).flatMap((line) => {
    const match = line.match(/^\s*(\d{1,3})[.)]\s+\S/u);
    return match ? [Number(match[1])] : [];
  });
  return numberedItems.length === count &&
    numberedItems.every((item, index) => item === index + 1);
}

export function deterministicFallbackHints(
  catalog: EvidenceCatalog,
  limit = 150,
): PlaceHint[] {
  const hints: PlaceHint[] = [];
  const identities = new Set<string>();
  const append = (hint: PlaceHint) => {
    const identity = normalizedIdentity(hint.name, hint.area);
    if (!identity || !identities.add(identity) || hints.length >= limit) return;
    hints.push(hint);
  };

  for (
    const text of catalog.texts.filter((item) =>
      item.modality === "tagged_location"
    )
  ) {
    const name = cleanString(text.text, 160);
    if (!name) continue;
    append({
      name,
      area: cleanString(text.area, 160),
      classification: "destination",
      modality: "tagged_location",
      evidence_ids: [text.id],
      confidence: 0.95,
      start_ms: null,
      end_ms: null,
    });
  }

  const caption = catalog.texts.find((item) => item.modality === "caption");
  if (!caption) return hints;
  const lines = caption.text.split(/\r?\n/).map((line) => line.trim()).filter(
    Boolean,
  );
  for (const line of lines) {
    const explicit = line.match(
      /^(?:📍|(?:location|located)\s*[:\-])\s*(.{3,180})$/iu,
    );
    if (!explicit) continue;
    const parsed = parseNameAndArea(explicit[1]);
    if (!parsed) continue;
    append({
      ...parsed,
      classification: "destination",
      modality: "caption",
      evidence_ids: [caption.id],
      confidence: 0.88,
      start_ms: null,
      end_ms: null,
    });
  }

  const numbered = lines.flatMap((line) => {
    const match = line.match(/^\s*\d{1,3}[.)]\s+(.{3,180})$/u);
    return match ? [match[1]] : [];
  });
  if (numbered.length >= 2) {
    for (const value of numbered) {
      const parsed = parseNameAndArea(value);
      if (!parsed) continue;
      append({
        ...parsed,
        classification: "itinerary",
        modality: "caption",
        evidence_ids: [caption.id],
        confidence: 0.78,
        start_ms: null,
        end_ms: null,
      });
    }
  }
  return hints;
}

function textualModality(modality: EvidenceModality): boolean {
  return ["caption", "tagged_location", "alt_text"].includes(modality);
}

function textAttestedArea(
  area: string | null,
  modality: EvidenceModality,
  evidenceIDs: string[],
  textByID: Map<string, EvidenceCatalog["texts"][number]>,
): string | null {
  if (!area) return null;
  return evidenceIDs.some((id) => {
      const evidence = textByID.get(id);
      return evidence?.modality === modality &&
        containsTokenSequence(evidence.text, area);
    })
    ? area
    : null;
}

function isGrounded(
  name: string,
  modality: EvidenceModality,
  evidenceIDs: string[],
  textByID: Map<string, EvidenceCatalog["texts"][number]>,
  mediaByID: Map<string, EvidenceCatalog["media"][number]>,
  ingestionByID: Map<string, MediaIngestion>,
): boolean {
  if (["caption", "tagged_location", "alt_text"].includes(modality)) {
    return evidenceIDs.some((id) => {
      const evidence = textByID.get(id);
      return evidence?.modality === modality &&
        containsTokenSequence(evidence.text, name);
    });
  }

  return evidenceIDs.some((id) => {
    const media = mediaByID.get(id);
    const ingestion = ingestionByID.get(id);
    if (!media || ingestion?.status !== "ok") return false;
    if (modality === "image_text") return media.kind === "image";
    return media.kind === "video";
  });
}

function parseNameAndArea(
  value: string,
): { name: string; area: string | null } | null {
  const withoutTags = value.replace(/\s+#\S.*$/u, "").trim();
  const pieces = withoutTags.split(/\s+(?:[-–—|]|in)\s+/iu, 2);
  const name = cleanString(pieces[0], 160);
  const area = cleanString(pieces[1], 160);
  if (!name || words(name).length === 0 || words(name).length > 18) return null;
  return { name, area };
}

function containsTokenSequence(haystack: string, needle: string): boolean {
  const source = words(haystack);
  const expected = words(needle);
  if (expected.length === 0 || expected.length > source.length) return false;
  for (let start = 0; start <= source.length - expected.length; start += 1) {
    if (expected.every((word, offset) => source[start + offset] === word)) {
      return true;
    }
  }
  return false;
}

function words(value: string): string[] {
  return value.toLocaleLowerCase("en-US").match(/[\p{L}\p{N}]+/gu) ?? [];
}

function normalizedIdentity(name: string, area: string | null): string {
  return `${normalizedValue(name)}|${normalizedValue(area ?? "")}`;
}

function normalizedValue(value: string): string {
  return words(value).join("");
}

function finiteTimestamp(value: number): number | null {
  return Number.isFinite(value) && value >= 0 ? Math.round(value) : null;
}
