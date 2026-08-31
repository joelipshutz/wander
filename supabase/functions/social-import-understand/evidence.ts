import { inventoryInstagramCaption } from "./caption-inventory.ts";
import { cleanString } from "./source.ts";
import type {
  AcquisitionEvidence,
  EvidenceCatalog,
  EvidenceModality,
  InstagramProfileAlias,
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
const nonListCountNouns = new Set([
  "carousel",
  "carousels",
  "clip",
  "clips",
  "day",
  "days",
  "episode",
  "episodes",
  "frame",
  "frames",
  "hour",
  "hours",
  "image",
  "images",
  "minute",
  "minutes",
  "month",
  "months",
  "night",
  "nights",
  "page",
  "pages",
  "part",
  "parts",
  "photo",
  "photos",
  "picture",
  "pictures",
  "post",
  "posts",
  "reel",
  "reels",
  "second",
  "seconds",
  "slide",
  "slides",
  "story",
  "stories",
  "video",
  "videos",
  "week",
  "weeks",
  "year",
  "years",
]);
const genericListTitlePrefixes = new Set([
  "best",
  "favorite",
  "favorites",
  "favourite",
  "favourites",
  "my",
  "our",
  "the",
  "top",
  "ultimate",
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
  directEvidenceIDs: string[];
  entityType: ModelCandidate["entityType"];
  itemIndex: number;
  sourceIdentity: string | null;
  usesProfileAlias: boolean;
  usesLiteralHandleFallback: boolean;
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
  profileAliases: InstagramProfileAlias[] = [],
): {
  hints: PlaceHint[];
  rejectedCount: number;
  excludedCount: number;
  intentionalExcludedCount: number;
  expectedCount: number | null;
  missingExpectedCount: number;
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
  const profileAliasNames = profileAliasNameMap(profileAliases);
  const prepared: PreparedHint[] = [];
  const preparedIndexes = new Map<string, number>();
  let rejectedCount = 0;
  let excludedCount = 0;
  let intentionalExcludedCount = 0;

  for (const candidate of candidates.slice(0, 320)) {
    const sourceMention = cleanString(candidate.sourceMention, 200);
    const classification = promotedClassification(
      candidate.classification,
      sourceMention,
      candidate.evidenceIds,
      textByID,
    );
    if (!acceptedClassifications.has(classification)) {
      if (
        intentionalExclusionClassifications.has(classification)
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
          .map((value) =>
            value ? canonicalEvidenceID(value, textByID, mediaByID) : null
          )
          .filter((value): value is string => value !== null),
      ),
    ]
      .slice(0, 8);
    const groundedName = name && sourceMention
      ? groundedCandidateName(
        name,
        sourceMention,
        candidate.modality,
        evidenceIDs,
        textByID,
        mediaByID,
        ingestionByID,
        context.globalArea,
        profileAliasNames,
        !acceptedClassifications.has(candidate.classification),
      )
      : null;
    if (
      !name ||
      !acceptedModalities.has(candidate.modality) ||
      !Number.isFinite(candidate.confidence) ||
      candidate.confidence < minimumGroundedConfidence ||
      candidate.confidence > 1 || evidenceIDs.length === 0 ||
      !groundedName
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
        mediaByID,
        ingestionByID,
      )
      : area;
    const usesGlobalArea = !geographyEntityTypes.has(candidate.entityType) &&
      !attestedArea && context.globalArea !== null;
    const hint: PlaceHint = {
      name: groundedName,
      area: attestedArea ?? (usesGlobalArea ? context.globalArea : null),
      classification: classification as "destination" | "itinerary",
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
    const identity = normalizedIdentity(groundedName, hint.area);
    const existingIndex = preparedIndexes.get(identity);
    const textualSourceMention = textualModality(candidate.modality) &&
        sourceMention
      ? sourceMention
      : null;
    const sourceHandle = textualSourceMention
      ? exactHandle(textualSourceMention)
      : null;
    const usesProfileAlias = textualSourceMention
      ? profileAliasSupportsName(
        name,
        textualSourceMention,
        profileAliasNames,
      )
      : false;
    const value: PreparedHint = {
      hint,
      directEvidenceIDs: evidenceIDs,
      entityType: candidate.entityType,
      itemIndex: candidate.itemIndex,
      sourceIdentity: textualSourceMention
        ? normalizedSourceIdentity(textualSourceMention)
        : null,
      usesProfileAlias,
      usesLiteralHandleFallback: groundedName !== name ||
        (sourceHandle !== null &&
          name.normalize("NFKC").trim().toLocaleLowerCase("en-US") ===
            sourceHandle.normalize("NFKC").toLocaleLowerCase("en-US") &&
          !usesProfileAlias),
    };
    if (existingIndex === undefined) {
      preparedIndexes.set(identity, prepared.length);
      prepared.push(value);
    } else {
      excludedCount += 1;
      const existing = prepared[existingIndex];
      prepared[existingIndex] = hint.confidence > existing.hint.confidence
        ? mergePreparedHints(value, existing)
        : mergePreparedHints(existing, value);
    }
  }

  const sourceIndexes = new Map<string, number[]>();
  const withoutDuplicateSources: PreparedHint[] = [];
  for (const candidate of prepared) {
    const sourceIdentity = candidate.sourceIdentity;
    if (!sourceIdentity) {
      withoutDuplicateSources.push(candidate);
      continue;
    }
    const matchingIndexes = sourceIndexes.get(sourceIdentity) ?? [];
    const existingIndex = matchingIndexes.find((index) => {
      const existing = withoutDuplicateSources[index];
      return sourceAreasReferToSamePlace(
        existing.hint.area,
        candidate.hint.area,
      ) && sourceNamesReferToSamePlace(existing, candidate);
    });
    if (existingIndex === undefined) {
      sourceIndexes.set(sourceIdentity, [
        ...matchingIndexes,
        withoutDuplicateSources.length,
      ]);
      withoutDuplicateSources.push(candidate);
      continue;
    }
    excludedCount += 1;
    const existing = withoutDuplicateSources[existingIndex];
    withoutDuplicateSources[existingIndex] = preferredDuplicateSourceCandidate(
        existing,
        candidate,
      )
      ? mergePreparedHints(candidate, existing)
      : mergePreparedHints(existing, candidate);
  }

  const withoutRedundantLiteralHandles = withoutDuplicateSources.filter(
    (candidate, index, values) => {
      if (
        !candidate.usesLiteralHandleFallback || candidate.itemIndex < 0
      ) return true;
      const hasHumanCandidateForItem = values.some((other, otherIndex) =>
        otherIndex !== index && other.itemIndex === candidate.itemIndex &&
        !other.usesLiteralHandleFallback &&
        classificationSelectionRank(other.hint.classification) <=
          classificationSelectionRank(candidate.hint.classification)
      );
      if (!hasHumanCandidateForItem) return true;
      excludedCount += 1;
      return false;
    },
  );

  const withoutGeographyContext = withoutRedundantLiteralHandles.filter(
    (candidate, index, values) => {
      if (context.intent === "geography_list") return true;
      if (
        context.intent === "place_list" && context.declaredCount === null &&
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
        classificationSelectionRank(other.hint.classification) <=
          classificationSelectionRank(candidate.hint.classification) &&
        nameIdentity === normalizedValue(other.hint.area)
      );
      const unknownMatchesPOIArea = candidate.entityType === "unknown" &&
        values.some((other, otherIndex) =>
          otherIndex !== index && other.entityType === "poi" &&
          classificationSelectionRank(other.hint.classification) <=
            classificationSelectionRank(candidate.hint.classification) &&
          candidate.itemIndex >= 0 && candidate.itemIndex === other.itemIndex &&
          other.hint.area !== null &&
          nameIdentity === normalizedValue(other.hint.area)
        );
      const sameItemMistypedGeography = context.intent === "place_list" &&
        candidate.entityType === "poi" && candidate.itemIndex >= 0 &&
        values.some((other, otherIndex) =>
          otherIndex !== index && other.entityType === "poi" &&
          classificationSelectionRank(other.hint.classification) <=
            classificationSelectionRank(candidate.hint.classification) &&
          candidate.itemIndex === other.itemIndex &&
          other.hint.area !== null &&
          nameIdentity === normalizedValue(other.hint.area) &&
          sharesDirectEvidence(candidate, other)
        );
      const likelyMistypedGeography = context.intent === "place_list" &&
        context.declaredCount !== null &&
        values.length > context.declaredCount &&
        values.some((other, otherIndex) =>
          otherIndex !== index && other.entityType === "poi" &&
          classificationSelectionRank(other.hint.classification) <=
            classificationSelectionRank(candidate.hint.classification) &&
          other.hint.area !== null &&
          nameIdentity === normalizedValue(other.hint.area) &&
          sharesDirectEvidence(candidate, other)
        );
      if (
        !matchesGlobalArea && !matchesAnotherArea && !unknownMatchesPOIArea &&
        !sameItemMistypedGeography && !likelyMistypedGeography
      ) return true;
      excludedCount += 1;
      return false;
    },
  );

  // In a grounded declared-count list, a non-negative item index is Gemini's
  // identity for one enumerated result. Caption and media support for that item
  // enrich one result; they must not consume separate count slots. Uncounted
  // itineraries may intentionally offer several destinations in one step, so
  // only conservative name variants with matching item/evidence/area identity
  // are folded there.
  const itemIndexes = new Map<number, number[]>();
  const withoutDuplicateItems: PreparedHint[] = [];
  for (const candidate of withoutGeographyContext) {
    if (candidate.itemIndex < 0) {
      withoutDuplicateItems.push(candidate);
      continue;
    }
    const matchingIndexes = itemIndexes.get(candidate.itemIndex) ?? [];
    const existingIndex = context.declaredCount === null
      ? matchingIndexes.find((index) =>
        sameUncountedLogicalItemVariant(
          withoutDuplicateItems[index],
          candidate,
        )
      )
      : matchingIndexes[0];
    if (existingIndex === undefined) {
      itemIndexes.set(candidate.itemIndex, [
        ...matchingIndexes,
        withoutDuplicateItems.length,
      ]);
      withoutDuplicateItems.push(candidate);
      continue;
    }
    excludedCount += 1;
    const existing = withoutDuplicateItems[existingIndex];
    withoutDuplicateItems[existingIndex] = preferredSameItemCandidate(
        existing,
        candidate,
      )
      ? mergePreparedHints(candidate, existing)
      : mergePreparedHints(existing, candidate);
  }

  const usesDeclaredCount = context.declaredCount !== null;
  const groundedLimit = !usesDeclaredCount
    ? limit
    : Math.min(limit, context.declaredCount as number);
  const sourceOrdered = withoutDuplicateItems
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
  // A declared count describes primary destinations, not every supporting
  // venue mentioned alongside them. Gemini deliberately distinguishes those
  // with `destination` versus `itinerary`. When primary coverage is incomplete,
  // return the grounded primaries and report the gap instead of filling it with
  // supporting rows.
  const selected = usesDeclaredCount
    ? sourceOrdered
      .filter((candidate) => candidate.hint.classification === "destination")
      .slice(0, groundedLimit)
    : sourceOrdered.slice(0, groundedLimit);
  const hints = selected.map((value) => value.hint);
  excludedCount += Math.max(0, sourceOrdered.length - selected.length);
  const expectedCount = context.declaredCount;
  return {
    hints,
    rejectedCount,
    excludedCount,
    intentionalExcludedCount,
    expectedCount,
    missingExpectedCount: expectedCount === null
      ? 0
      : Math.max(0, expectedCount - hints.length),
  };
}

function preferredDuplicateSourceCandidate(
  existing: PreparedHint,
  candidate: PreparedHint,
): boolean {
  // A raw handle is only a last-resort query. It must never replace a human
  // venue name merely because the fallback inherited a more specific area.
  if (
    existing.usesLiteralHandleFallback !== candidate.usesLiteralHandleFallback
  ) return existing.usesLiteralHandleFallback;

  if (existing.usesProfileAlias && candidate.usesProfileAlias) {
    const candidateIsCanonicalRefinement = profileAliasCanonicalRefinement(
      candidate.hint.name,
      existing.hint.name,
    );
    const existingIsCanonicalRefinement = profileAliasCanonicalRefinement(
      existing.hint.name,
      candidate.hint.name,
    );
    if (
      candidateIsCanonicalRefinement !== existingIsCanonicalRefinement
    ) return candidateIsCanonicalRefinement;
  }

  const existingHasArea = existing.hint.area !== null;
  const candidateHasArea = candidate.hint.area !== null;
  const equallySpecificAreas = existingHasArea === candidateHasArea;
  if (!existingHasArea && candidateHasArea) return true;
  if (!equallySpecificAreas) return false;
  if (existing.usesProfileAlias !== candidate.usesProfileAlias) {
    return candidate.usesProfileAlias;
  }
  return candidate.hint.confidence > existing.hint.confidence;
}

function preferredSameItemCandidate(
  existing: PreparedHint,
  candidate: PreparedHint,
): boolean {
  if (
    existing.usesLiteralHandleFallback !== candidate.usesLiteralHandleFallback
  ) return existing.usesLiteralHandleFallback;
  const classificationDifference = classificationSelectionRank(
    candidate.hint.classification,
  ) - classificationSelectionRank(existing.hint.classification);
  if (classificationDifference !== 0) return classificationDifference < 0;
  if (existing.usesProfileAlias !== candidate.usesProfileAlias) {
    return candidate.usesProfileAlias;
  }
  const existingHasArea = existing.hint.area !== null;
  const candidateHasArea = candidate.hint.area !== null;
  if (existingHasArea !== candidateHasArea) return candidateHasArea;
  return candidate.hint.confidence > existing.hint.confidence;
}

function sameUncountedLogicalItemVariant(
  left: PreparedHint,
  right: PreparedHint,
): boolean {
  return left.itemIndex >= 0 && left.itemIndex === right.itemIndex &&
    sourceAreasReferToSamePlace(left.hint.area, right.hint.area) &&
    sharesDirectEvidence(left, right) &&
    sameOrSimpleSingularPluralName(left.hint.name, right.hint.name);
}

function sameOrSimpleSingularPluralName(left: string, right: string): boolean {
  const leftWords = words(left);
  const rightWords = words(right);
  if (leftWords.length === 0 || leftWords.length !== rightWords.length) {
    return false;
  }
  const finalIndex = leftWords.length - 1;
  if (
    !leftWords.slice(0, finalIndex).every((word, index) =>
      word === rightWords[index]
    )
  ) return false;
  const leftFinal = leftWords[finalIndex];
  const rightFinal = rightWords[finalIndex];
  return leftFinal === rightFinal ||
    simpleEnglishPluralOf(leftFinal, rightFinal) ||
    simpleEnglishPluralOf(rightFinal, leftFinal);
}

function simpleEnglishPluralOf(singular: string, plural: string): boolean {
  if (singular.length < 3) return false;
  if (plural === `${singular}s`) return true;
  if (
    /(?:s|x|z|ch|sh)$/u.test(singular) && plural === `${singular}es`
  ) return true;
  return /[^aeiou]y$/u.test(singular) &&
    plural === `${singular.slice(0, -1)}ies`;
}

function mergePreparedHints(
  preferred: PreparedHint,
  supporting: PreparedHint,
): PreparedHint {
  const sameName = normalizedValue(preferred.hint.name) ===
    normalizedValue(supporting.hint.name);
  return {
    ...preferred,
    directEvidenceIDs: mergedEvidenceIDs(
      preferred.directEvidenceIDs,
      supporting.directEvidenceIDs,
    ),
    hint: {
      ...preferred.hint,
      area: preferred.hint.area ??
        (sameName ? supporting.hint.area : null),
      classification: classificationSelectionRank(
          preferred.hint.classification,
        ) <= classificationSelectionRank(supporting.hint.classification)
        ? preferred.hint.classification
        : supporting.hint.classification,
      evidence_ids: mergedEvidenceIDs(
        preferred.hint.evidence_ids,
        supporting.hint.evidence_ids,
      ),
      confidence: Math.max(
        preferred.hint.confidence,
        supporting.hint.confidence,
      ),
      start_ms: preferred.hint.start_ms ?? supporting.hint.start_ms,
      end_ms: preferred.hint.end_ms ?? supporting.hint.end_ms,
    },
  };
}

function mergedEvidenceIDs(primary: string[], supporting: string[]): string[] {
  return [...new Set([...primary, ...supporting])].slice(0, 8);
}

function classificationSelectionRank(
  classification: PlaceHint["classification"],
): number {
  return classification === "destination" ? 0 : 1;
}

function sourceNamesReferToSamePlace(
  left: PreparedHint,
  right: PreparedHint,
): boolean {
  if (normalizedValue(left.hint.name) === normalizedValue(right.hint.name)) {
    return true;
  }
  // Collapse a literal handle only when the human venue name is actually
  // represented inside that handle. Sharing a source mention is not enough:
  // @rorys_place_ojai can accompany both Rory's Place and the distinct
  // Rory's Other Place in the same post.
  if (left.usesLiteralHandleFallback || right.usesLiteralHandleFallback) {
    const literal = left.usesLiteralHandleFallback ? left : right;
    const named = left.usesLiteralHandleFallback ? right : left;
    if (named.usesProfileAlias) return true;
    const literalIdentity = normalizedValue(literal.hint.name);
    const namedIdentity = normalizedValue(named.hint.name);
    return namedIdentity.length >= 4 &&
      (literalIdentity.includes(namedIdentity) ||
        namedIdentity.includes(literalIdentity));
  }
  if (
    left.usesProfileAlias && right.usesProfileAlias &&
    (sameProfileAliasName(left.hint.name, right.hint.name) ||
      profileAliasCanonicalRefinement(left.hint.name, right.hint.name) ||
      profileAliasCanonicalRefinement(right.hint.name, left.hint.name))
  ) return true;
  if (
    left.itemIndex >= 0 && right.itemIndex >= 0 &&
    left.itemIndex !== right.itemIndex
  ) return false;
  // Distinct human venue names are not duplicates. In particular,
  // containment is not identity: `Gjusta` and `Gjusta Goods`, or `Rory's
  // Place` and `Rory's Other Place`, must survive.
  return false;
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
  const evidenceWords = new Set(words(evidence.text));
  const compactArea = normalizedValue(globalArea);
  if (compactArea.length >= 6 && evidenceWords.has(compactArea)) return true;
  if (primaryWords.length < 2) return false;
  const compactPrimary = primaryWords.join("");
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
        .map((value) =>
          value ? canonicalEvidenceID(value, textByID, mediaByID) : null
        )
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

function canonicalEvidenceID(
  value: string,
  textByID: Map<string, EvidenceCatalog["texts"][number]>,
  mediaByID: Map<string, EvidenceCatalog["media"][number]>,
): string | null {
  if (textByID.has(value) || mediaByID.has(value)) return value;
  for (const mediaID of mediaByID.keys()) {
    if (!value.startsWith(`${mediaID}.`)) continue;
    const suffix = value.slice(mediaID.length);
    if (/^\.(?:\d{1,3}:){1,2}\d{1,3}(?:\.\d{1,3})?$/u.test(suffix)) {
      return mediaID;
    }
  }
  return null;
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
      const subjectWindow = lineWords.slice(index + 1, index + 5);
      const declaredNounIndex = subjectWindow.findIndex((word) =>
        declaredCountNouns.has(word)
      );
      const nonListUnitIndex = subjectWindow.findIndex((word) =>
        nonListCountNouns.has(word)
      );
      if (
        nonListUnitIndex >= 0 &&
        (declaredNounIndex < 0 || nonListUnitIndex < declaredNounIndex)
      ) continue;
      if (declaredNounIndex >= 0) return true;
      if (genericListTitleContainsCount(line, lineWords, index)) return true;
    }
  }

  return false;
}

function genericListTitleContainsCount(
  line: string,
  lineWords: string[],
  countIndex: number,
): boolean {
  // Generic nouns are safe only in a compact title shape: either the count
  // opens the line (`10 TOTALLY TEXAS THINGS`) or follows a bounded title
  // prefix (`TOP 10 PIZZAS`). Ordinary prose cannot establish a cap.
  if (line.length > 180 || lineWords.length > 14) return false;
  const prefix = lineWords.slice(0, countIndex);
  const hasTitlePrefix = prefix.length > 0 && prefix.length <= 3 &&
    prefix.every((word) => genericListTitlePrefixes.has(word)) &&
    prefix.some((word) =>
      word === "top" || word === "best" || word === "favorite" ||
      word === "favorites" || word === "favourite" ||
      word === "favourites" || word === "ultimate"
    );
  if (countIndex !== 0 && !hasTitlePrefix) return false;

  const subjectWindow = lineWords.slice(countIndex + 1, countIndex + 6);
  if (
    subjectWindow.length === 0 ||
    subjectWindow.some((word) => nonListCountNouns.has(word))
  ) return false;
  return subjectWindow.some((word) => /\p{L}/u.test(word));
}

export function deterministicFallbackHints(
  catalog: EvidenceCatalog,
  limit = 150,
  profileAliases: InstagramProfileAlias[] = [],
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
  const inventory = inventoryInstagramCaption(caption.text);
  const secondaryLineIndexes = new Set(
    inventory.mentions
      .filter((mention) =>
        mention.structuralRole !== "primary_list_item" &&
        mention.structuralRole !== "unstructured"
      )
      .map((mention) => mention.lineIndex),
  );
  const lines = caption.text.split(/\r?\n/).map((line) => line.trim());
  for (const [lineIndex, line] of lines.entries()) {
    if (!line || secondaryLineIndexes.has(lineIndex)) continue;
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

  // Keep the existing conservative numbered-list fallback, but use the
  // structural inventory to ensure rows under honorable-mention, credit, or
  // partner headings can never become destinations merely because they are
  // numbered.
  const numbered = inventory.listItems
    .filter((item) => {
      if (!item.isPrimary || item.marker !== "numbered") return false;
      const sourceLine = lines[item.lineIndex] ?? "";
      return /^\s*\d{1,3}[.)]\s+.{3,180}$/u.test(sourceLine);
    })
    .map((item) => item.text);
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
  mergePrimaryCaptionProfileAliasHints(
    hints,
    primaryCaptionProfileAliasEntries(catalog, profileAliases, limit),
    limit,
  );
  return hints;
}

type CaptionProfileAliasHint = {
  username: string;
  hint: PlaceHint;
};

/**
 * Returns only deterministic caption-list destinations whose Instagram
 * handle resolved to exactly one public profile name. Unstructured handles
 * and handles in honorable-mention, credit, and partner sections are excluded
 * even if profile enrichment resolved them successfully.
 */
export function primaryCaptionProfileAliasHints(
  catalog: EvidenceCatalog,
  profileAliases: InstagramProfileAlias[],
  limit = 150,
): PlaceHint[] {
  return primaryCaptionProfileAliasEntries(catalog, profileAliases, limit).map(
    (entry) => entry.hint,
  );
}

function primaryCaptionProfileAliasEntries(
  catalog: EvidenceCatalog,
  profileAliases: InstagramProfileAlias[],
  limit: number,
): CaptionProfileAliasHint[] {
  const caption = catalog.texts.find((item) => item.modality === "caption");
  if (!caption) return [];
  const names = profileAliasNameMap(profileAliases);
  const seen = new Set<string>();
  const entries: CaptionProfileAliasHint[] = [];
  const boundedLimit = Number.isFinite(limit)
    ? Math.max(0, Math.min(150, Math.trunc(limit)))
    : 0;
  if (boundedLimit === 0) return entries;
  for (
    const mention of inventoryInstagramCaption(caption.text).handleMentions
  ) {
    if (!mention.isPrimary || seen.has(mention.username)) continue;
    seen.add(mention.username);
    const name = names.get(mention.username);
    if (!name) continue;
    entries.push({
      username: mention.username,
      hint: {
        name,
        area: null,
        classification: "destination",
        modality: "caption",
        evidence_ids: [caption.id],
        confidence: 0.92,
        start_ms: null,
        end_ms: null,
      },
    });
    if (entries.length >= boundedLimit) break;
  }
  return entries;
}

function mergePrimaryCaptionProfileAliasHints(
  hints: PlaceHint[],
  aliases: CaptionProfileAliasHint[],
  limit: number,
): void {
  for (const alias of aliases) {
    const rawHandleIndexes = hints.flatMap((hint, index) =>
      hint.modality === "caption" &&
        containsExactHandle(hint.name, alias.username)
        ? [index]
        : []
    );
    const canonicalName = normalizedValue(alias.hint.name);
    const rawHandleIndexSet = new Set(rawHandleIndexes);
    const canonicalIndex = hints.findIndex((hint, index) =>
      !rawHandleIndexSet.has(index) &&
      normalizedValue(hint.name) === canonicalName
    );

    if (canonicalIndex >= 0) {
      hints[canonicalIndex] = rawHandleIndexes.reduce(
        (merged, index) => mergeFallbackHint(merged, hints[index]),
        mergeFallbackHint(hints[canonicalIndex], alias.hint),
      );
      removeHintIndexes(hints, rawHandleIndexes, canonicalIndex);
      continue;
    }

    const rawHandleIndex = rawHandleIndexes[0];
    if (rawHandleIndex !== undefined) {
      hints[rawHandleIndex] = {
        ...mergeFallbackHint(hints[rawHandleIndex], alias.hint),
        name: alias.hint.name,
      };
      removeHintIndexes(hints, rawHandleIndexes.slice(1));
      continue;
    }

    if (hints.length < limit) hints.push(alias.hint);
  }
}

function mergeFallbackHint(
  preferred: PlaceHint,
  supporting: PlaceHint,
): PlaceHint {
  return {
    ...preferred,
    area: preferred.area ?? supporting.area,
    evidence_ids: [
      ...new Set([
        ...preferred.evidence_ids,
        ...supporting.evidence_ids,
      ]),
    ].slice(0, 8),
    confidence: Math.max(preferred.confidence, supporting.confidence),
  };
}

function removeHintIndexes(
  hints: PlaceHint[],
  indexes: number[],
  preservedIndex = -1,
): void {
  for (
    const index of [...new Set(indexes)].sort((left, right) => right - left)
  ) {
    if (index !== preservedIndex) hints.splice(index, 1);
  }
}

function textualModality(modality: EvidenceModality): boolean {
  return ["caption", "tagged_location", "alt_text"].includes(modality);
}

function textAttestedArea(
  area: string | null,
  modality: EvidenceModality,
  evidenceIDs: string[],
  textByID: Map<string, EvidenceCatalog["texts"][number]>,
  mediaByID: Map<string, EvidenceCatalog["media"][number]>,
  ingestionByID: Map<string, MediaIngestion>,
): string | null {
  if (!area) return null;
  const textAttestsArea = evidenceIDs.some((id) => {
    const evidence = textByID.get(id);
    return evidence?.modality === modality &&
      containsTokenSequence(evidence.text, area);
  });
  return textAttestsArea || hasIngestedMediaEvidence(
      evidenceIDs,
      mediaByID,
      ingestionByID,
    )
    ? area
    : null;
}

function groundedCandidateName(
  name: string,
  sourceMention: string,
  modality: EvidenceModality,
  evidenceIDs: string[],
  textByID: Map<string, EvidenceCatalog["texts"][number]>,
  mediaByID: Map<string, EvidenceCatalog["media"][number]>,
  ingestionByID: Map<string, MediaIngestion>,
  globalArea: string | null,
  profileAliasNames: Map<string, string>,
  requiresCaptionVenueGrammar: boolean,
): string | null {
  if (["caption", "tagged_location", "alt_text"].includes(modality)) {
    const handle = exactHandle(sourceMention);
    const hasExactEvidence = evidenceIDs.some((id) => {
      const evidence = textByID.get(id);
      if (evidence?.modality !== modality) return false;
      if (handle) {
        return containsExactHandle(evidence.text, handle) &&
          (modality !== "caption" ||
            (requiresCaptionVenueGrammar
              ? captionRecommendsHandle(evidence.text, handle)
              : captionAllowsModelAcceptedHandle(evidence.text, handle)));
      }
      return containsTokenSequence(evidence.text, sourceMention);
    });
    if (!hasExactEvidence) return null;
    const hasExplicitNameEvidence = evidenceIDs.some((id) => {
      const evidence = textByID.get(id);
      return evidence?.modality === modality &&
        containsTokenSequence(
          handle
            ? textWithoutExactHandle(evidence.text, handle)
            : evidence.text,
          name,
        );
    });
    if (
      sourceMentionSupportsName(name, sourceMention, globalArea) ||
      profileAliasSupportsName(name, sourceMention, profileAliasNames) ||
      hasExplicitNameEvidence ||
      (!requiresCaptionVenueGrammar && hasIngestedMediaEvidence(
        evidenceIDs,
        mediaByID,
        ingestionByID,
      ))
    ) return name;
    return handle;
  }

  return evidenceIDs.some((id) => {
      const media = mediaByID.get(id);
      const ingestion = ingestionByID.get(id);
      if (!media || ingestion?.status !== "ok") return false;
      if (modality === "image_text") return media.kind === "image";
      return media.kind === "video";
    })
    ? name
    : null;
}

function hasIngestedMediaEvidence(
  evidenceIDs: string[],
  mediaByID: Map<string, EvidenceCatalog["media"][number]>,
  ingestionByID: Map<string, MediaIngestion>,
): boolean {
  return evidenceIDs.some((id) =>
    mediaByID.has(id) && ingestionByID.get(id)?.status === "ok"
  );
}

function promotedClassification(
  classification: ModelCandidate["classification"],
  sourceMention: string | null,
  evidenceIDs: string[],
  textByID: Map<string, EvidenceCatalog["texts"][number]>,
): ModelCandidate["classification"] {
  if (acceptedClassifications.has(classification) || !sourceMention) {
    return classification;
  }
  const handle = exactHandle(sourceMention);
  if (!handle) return classification;
  const isRecommended = evidenceIDs.some((id) => {
    const evidence = textByID.get(id);
    return evidence?.modality === "caption" &&
      captionRecommendsHandle(evidence.text, handle);
  });
  return isRecommended ? "itinerary" : classification;
}

export function captionRecommendsHandle(
  caption: string,
  handle: string,
): boolean {
  const lines = caption.split(/\r?\n/u);
  const negativeLines = negativeCaptionHandleLines(caption, handle);
  return lines.some((line, lineIndex) => {
    return exactHandleIndexes(line, handle).some((index) => {
      if (negativeLines.has(lineIndex)) return false;
      const beforeLine = line.slice(0, index).toLocaleLowerCase("en-US");
      const boundary = captionClauseBoundary(beforeLine);
      const clause = beforeLine.slice(boundary + 1);
      const afterHandle = line.slice(index + handle.length + 1);
      if (captionDigitalCallToActionAfterHandle(afterHandle)) return false;
      const hasDirectVenueMarker = captionVenueMarkerAtEnd(clause);
      const hasPhysicalFromMarker = captionPhysicalFromMarkerAtEnd(clause);
      if (
        !hasPhysicalFromMarker && captionAttributionBeforeHandle(clause)
      ) return false;
      if (hasDirectVenueMarker) return true;
      if (captionLineBelongsToVenueSection(lines, lineIndex)) return true;
      if (!/(?:,|\/|\bor\b|\band\b)\s*$/u.test(clause)) return false;

      const markerMatches = captionVenueMarkerMatches(clause);
      const marker = markerMatches.at(-1);
      if (!marker || marker.index === undefined) return false;
      const afterMarker = clause.slice(marker.index + marker[0].length);
      return afterMarker.trim().length > 0 &&
        !captionAttributionSinceVenueMarker(afterMarker);
    });
  });
}

function captionAllowsModelAcceptedHandle(
  caption: string,
  handle: string,
): boolean {
  const negativeLines = negativeCaptionHandleLines(caption, handle);
  return caption.split(/\r?\n/u).some((line, lineIndex) =>
    exactHandleIndexes(line, handle).some((index) => {
      if (negativeLines.has(lineIndex)) return false;
      const beforeLine = line.slice(0, index).toLocaleLowerCase("en-US");
      const boundary = captionClauseBoundary(beforeLine);
      const clause = beforeLine.slice(boundary + 1);
      const afterHandle = line.slice(index + handle.length + 1);
      if (captionDigitalCallToActionAfterHandle(afterHandle)) return false;
      return captionPhysicalFromMarkerAtEnd(clause) ||
        !captionAttributionBeforeHandle(clause);
    })
  );
}

function negativeCaptionHandleLines(
  caption: string,
  handle: string,
): Set<number> {
  const username = handle.toLocaleLowerCase("en-US");
  return new Set(
    inventoryInstagramCaption(caption).handleMentions
      .filter((mention) =>
        mention.username === username &&
        mention.structuralRole !== "primary_list_item" &&
        mention.structuralRole !== "unstructured"
      )
      .map((mention) => mention.lineIndex),
  );
}

function captionClauseBoundary(value: string): number {
  const withoutHandlePeriods = value.replace(
    /@[A-Za-z0-9_](?:[A-Za-z0-9_]|\.(?=[A-Za-z0-9_])){0,29}/gu,
    (handle) => handle.replaceAll(".", "_"),
  );
  return Math.max(
    withoutHandlePeriods.lastIndexOf("."),
    withoutHandlePeriods.lastIndexOf("!"),
    withoutHandlePeriods.lastIndexOf("?"),
    withoutHandlePeriods.lastIndexOf(";"),
  );
}

export function recommendedCaptionHandles(
  caption: string,
  limit = 20,
): string[] {
  return recommendedCaptionHandleMentions(caption, limit).map((value) =>
    value.username
  );
}

export function prioritizedCaptionProfileUsernames(caption: string): string[] {
  const preferred = recommendedCaptionHandles(caption, 20);
  const all = inventoryInstagramCaption(caption).profileUsernames;
  return [...new Set([...preferred, ...all])].slice(0, 20);
}

export function profileAliasCandidates(
  aliases: InstagramProfileAlias[],
  catalog: EvidenceCatalog,
): ModelCandidate[] {
  const caption = catalog.texts.find((item) => item.modality === "caption");
  if (!caption) return [];
  const aliasNames = profileAliasNameMap(aliases);
  return recommendedCaptionHandleMentions(caption.text, 20).flatMap(
    (mention, itemIndex) => {
      const fullName = aliasNames.get(mention.username);
      if (!fullName) return [];
      return [{
        name: fullName,
        sourceMention: mention.sourceMention,
        area: "",
        entityType: "poi" as const,
        itemIndex,
        // Synthetic aliases must independently pass deterministic venue
        // grammar. Model-accepted destinations use the less restrictive
        // exact-mention grounding path above, while explicit credits and
        // digital calls to action remain blocked in both paths.
        classification: "attribution" as const,
        modality: "caption" as const,
        evidenceIds: [caption.id],
        confidence: 0.96,
        startMs: -1,
        endMs: -1,
      }];
    },
  );
}

function recommendedCaptionHandleMentions(
  caption: string,
  limit: number,
): Array<{ username: string; sourceMention: string }> {
  const mentions: Array<{ username: string; sourceMention: string }> = [];
  const seen = new Set<string>();
  const expression =
    /(^|[^A-Za-z0-9._@])@([A-Za-z0-9_](?:[A-Za-z0-9_]|\.(?=[A-Za-z0-9_])){0,29})(?![A-Za-z0-9_]|\.[A-Za-z0-9_])/gu;
  for (const match of caption.matchAll(expression)) {
    const sourceMention = `@${match[2]}`;
    const username = match[2].toLocaleLowerCase("en-US");
    if (
      seen.has(username) ||
      !captionRecommendsHandle(caption, match[2])
    ) continue;
    seen.add(username);
    mentions.push({ username, sourceMention });
    if (mentions.length >= Math.max(0, Math.min(20, limit))) break;
  }
  return mentions;
}

function profileAliasNameMap(
  aliases: InstagramProfileAlias[],
): Map<string, string> {
  const names = new Map<string, string>();
  const duplicated = new Set<string>();
  for (const alias of aliases.slice(0, 20)) {
    const username = cleanString(alias.username, 64)?.toLocaleLowerCase(
      "en-US",
    );
    const fullName = cleanString(alias.fullName, 160);
    if (
      !username ||
      !/^[a-z0-9_](?:[a-z0-9_]|\.(?=[a-z0-9_])){0,29}$/u.test(username) ||
      !fullName ||
      duplicated.has(username)
    ) continue;
    if (names.has(username)) {
      names.delete(username);
      duplicated.add(username);
      continue;
    }
    names.set(username, fullName);
  }
  return names;
}

function profileAliasSupportsName(
  name: string,
  sourceMention: string,
  profileAliasNames: Map<string, string>,
): boolean {
  const handle = exactHandle(sourceMention)?.toLocaleLowerCase("en-US");
  const alias = handle ? profileAliasNames.get(handle) : null;
  if (alias === null || alias === undefined) return false;
  if (sameProfileAliasName(name, alias)) return true;

  // A public profile name can omit an optional article and the physical-site
  // qualifier used by map providers. Preserve Gemini's provider-ready name
  // only when the complete profile name remains the unchanged leading venue
  // identity and the sole addition is a bounded `at …` qualifier. This keeps
  // the alias useful for `Sixth Floor Museum` -> `The Sixth Floor Museum at
  // Dealey Plaza` without allowing an unrelated or freely extended model name
  // to borrow the handle's trust.
  return profileAliasCanonicalRefinement(name, alias);
}

function sameProfileAliasName(left: string, right: string): boolean {
  const leftWords = withoutLeadingDefiniteArticle(words(left));
  const rightWords = withoutLeadingDefiniteArticle(words(right));
  return leftWords.length > 0 && leftWords.length === rightWords.length &&
    leftWords.every((word, index) => word === rightWords[index]);
}

function profileAliasCanonicalRefinement(
  name: string,
  alias: string,
): boolean {
  const aliasWords = withoutLeadingDefiniteArticle(words(alias));
  const nameWords = withoutLeadingDefiniteArticle(words(name));
  if (
    aliasWords.length < 2 || nameWords.length <= aliasWords.length ||
    !aliasWords.every((word, index) => nameWords[index] === word)
  ) return false;
  const qualifierWords = nameWords.slice(aliasWords.length);
  return qualifierWords[0] === "at" && qualifierWords.length >= 2 &&
    qualifierWords.length <= 6 &&
    !qualifierWords.some((word) => word === "and" || word === "or");
}

function withoutLeadingDefiniteArticle(values: string[]): string[] {
  return values[0] === "the" ? values.slice(1) : values;
}

function captionAttributionBeforeHandle(value: string): boolean {
  return /(?:\b(?:photo|video|filmed|shot|created|posted|hosted|guided)\s+by|\bcredit\s+goes\s+to|\b(?:huge\s+)?shout[\s-]*out\s+(?:to|for)|\bthanks(?:\s+so\s+much)?\s+(?:to|for)|\b(?:credit|credits|thank\s+you|courtesy)\s+(?:to|by|of)|(?:\b(?:photo(?:\s+credit)?|video|credit|credits)\b|[📷📸🎥])\s*[:\-–—]?|\b(?:by|with|via|from|follow|guide|creator|photographer|videographer|host|sponsor(?:ed)?)\b(?:\s+(?:to|by|of|local|our|the|travel|food))*)[\s,:-]*$/u
    .test(value);
}

function captionAttributionSinceVenueMarker(value: string): boolean {
  return /\b(?:photo|video|filmed|shot|created|posted|hosted|guided|credit|credits|thanks|thank\s+you|courtesy|with|via|follow|guide|creator|photographer|videographer|host|sponsor(?:ed)?)\b/u
    .test(value);
}

function captionVenueMarkerAtEnd(value: string): boolean {
  return /\b(?:at|to|visit|explore|try|book|stay(?:\s+at)?|stop(?:\s+at)?|check\s+in(?:\s+at)?|(?:breakfast|lunch|dinner)(?:\s+at)?\s*[:\-]?|(?:breakfast|brunch|lunch|dinner|coffee|tea|food|drinks?|cocktails?|desserts?|pastries|takeout|orders?)\s+from|(?:attractions?|bars?|beaches|caf(?:e|é)s?|coffee\s+shops?|destinations?|eats|food|hikes?|hotels?|museums?|parks?|places?|restaurants?|shops?|spots?|stays?|stops?|stores?|things\s+to\s+do|trails?|venues?|where\s+to\s+(?:eat|drink|stay|shop))\s*[:\-–—]?)\s*$/u
    .test(value);
}

function captionPhysicalFromMarkerAtEnd(value: string): boolean {
  return /\b(?:breakfast|brunch|lunch|dinner|coffee|tea|food|drinks?|cocktails?|desserts?|pastries|takeout|orders?)\s+from\s*$/u
    .test(value);
}

function captionVenueMarkerMatches(value: string): RegExpMatchArray[] {
  return [
    ...value.matchAll(
      /\b(?:at|to|visit|explore|try|book|stay(?:\s+at)?|stop(?:\s+at)?|check\s+in(?:\s+at)?|(?:breakfast|lunch|dinner)(?:\s+at)?\s*[:\-]?|(?:breakfast|brunch|lunch|dinner|coffee|tea|food|drinks?|cocktails?|desserts?|pastries|takeout|orders?)\s+from|(?:attractions?|bars?|beaches|caf(?:e|é)s?|coffee\s+shops?|destinations?|eats|food|hikes?|hotels?|museums?|parks?|places?|restaurants?|shops?|spots?|stays?|stops?|stores?|things\s+to\s+do|trails?|venues?|where\s+to\s+(?:eat|drink|stay|shop))\s*[:\-–—]?)\s+/gu,
    ),
  ];
}

function captionLineBelongsToVenueSection(
  lines: string[],
  lineIndex: number,
): boolean {
  if (!captionHandleListLine(lines[lineIndex] ?? "")) return false;
  for (let index = lineIndex - 1; index >= 0; index -= 1) {
    const prior = lines[index]?.trim() ?? "";
    if (!prior) continue;
    if (captionVenueHeadingLine(prior)) return true;
    if (captionHandleListLine(prior)) continue;
    return false;
  }
  return false;
}

function captionHandleListLine(value: string): boolean {
  if (!/@[A-Za-z0-9_]/u.test(value)) return false;
  const withoutNumber = value.replace(/^\s*\d{1,3}[.)]\s*/u, "");
  const withoutHandles = withoutNumber.replace(
    /@[A-Za-z0-9_](?:[A-Za-z0-9_]|\.(?=[A-Za-z0-9_])){0,29}/gu,
    "",
  );
  const withoutSeparators = withoutHandles.replace(/\b(?:or|and)\b/giu, "");
  return !/[\p{L}\p{N}]/u.test(withoutSeparators);
}

function captionVenueHeadingLine(value: string): boolean {
  return /^[^\p{L}\p{N}@]*(?:(?:best|favorite|favourite|my|our|top)\s+)?(?:attractions?|bars?|beaches|caf(?:e|é)s?|coffee\s+shops?|destinations?|eats|food|hikes?|hotels?|museums?|parks?|places?|restaurants?|shops?|spots?|stays?|stops?|stores?|things\s+to\s+do|trails?|venues?|where\s+to\s+(?:eat|drink|stay|shop))\s*[:\-–—]?\s*$/iu
    .test(value);
}

function captionDigitalCallToActionAfterHandle(value: string): boolean {
  return /^\s*(?:[,;:!\-–—]\s*)?(?:for(?:\s+more)?(?:\s+[\p{L}\p{N}&'’\-]+){0,4}\s+(?:content|details?|guides?|ideas?|info(?:rmation)?|inspiration|inspo|recommendations?|suggestions?|tips?|updates?)\b|for\s+more\s*[.!?]?(?:\s|$)|to\s+(?:browse|discover|find|get|learn|read|see|watch)(?:\s+more)?\b|(?:check|click|see|tap)\s+(?:the\s+)?(?:bio|link|page|profile)\b|(?:on|via)\s+(?:instagram|tiktok|youtube)\b|(?:['’]s\s+)?(?:account|bio|channel|page|profile)\b)/iu
    .test(value);
}

function sourceMentionSupportsName(
  name: string,
  sourceMention: string,
  globalArea: string | null,
): boolean {
  const handle = exactHandle(sourceMention);
  if (!handle) return containsTokenSequence(sourceMention, name);
  const canonicalVariants = normalizedNameVariants(name);
  if (canonicalVariants.size === 0) return false;
  let core = normalizedValue(handle);
  const suffixes = new Set(["official"]);
  for (const word of words(globalArea ?? "")) {
    if (word.length >= 3) suffixes.add(word);
  }
  let changed = true;
  while (changed) {
    changed = false;
    for (const suffix of suffixes) {
      if (core.length >= suffix.length + 2 && core.endsWith(suffix)) {
        core = core.slice(0, -suffix.length);
        changed = true;
        break;
      }
    }
  }
  const coreVariants = new Set([core]);
  if (core.startsWith("its") && core.length > 3) {
    coreVariants.add(core.slice(3));
  }
  for (const value of [...coreVariants]) {
    if ([...value.matchAll(/flr/gu)].length === 1) {
      coreVariants.add(value.replace("flr", "floor"));
    }
  }
  return [...coreVariants].some((value) => canonicalVariants.has(value));
}

function normalizedNameVariants(name: string): Set<string> {
  const nameWords = words(name);
  const variants = new Set<string>();
  if (nameWords.length === 0) return variants;
  variants.add(nameWords.join(""));
  if (nameWords[0] === "the" && nameWords.length > 1) {
    variants.add(nameWords.slice(1).join(""));
  }
  return variants;
}

function exactHandle(value: string): string | null {
  const match = value.trim().match(
    /^@([A-Za-z0-9_](?:[A-Za-z0-9_]|\.(?=[A-Za-z0-9_])){0,29})$/u,
  );
  return match?.[1] ?? null;
}

function exactHandleIndexes(value: string, handle: string): number[] {
  const escaped = handle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const expression = new RegExp(
    `(^|[^A-Za-z0-9._@])@${escaped}(?![A-Za-z0-9_]|\\.[A-Za-z0-9_])`,
    "giu",
  );
  const indexes: number[] = [];
  for (const match of value.matchAll(expression)) {
    if (match.index === undefined) continue;
    indexes.push(match.index + match[1].length);
  }
  return indexes;
}

function containsExactHandle(value: string, handle: string): boolean {
  return exactHandleIndexes(value, handle).length > 0;
}

function textWithoutExactHandle(value: string, handle: string): string {
  const escaped = handle.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return value.replace(
    new RegExp(
      `(^|[^A-Za-z0-9._@])@${escaped}(?![A-Za-z0-9_]|\\.[A-Za-z0-9_])`,
      "giu",
    ),
    "$1 ",
  );
}

function normalizedSourceIdentity(sourceMention: string): string | null {
  const handle = exactHandle(sourceMention);
  if (handle) return `handle:${handle.toLocaleLowerCase("en-US")}`;
  const value = normalizedValue(sourceMention);
  return value ? `text:${value}` : null;
}

function sourceAreasReferToSamePlace(
  left: string | null,
  right: string | null,
): boolean {
  if (!left || !right) return true;
  if (normalizedValue(left) === normalizedValue(right)) return true;
  const leftPrimary = normalizedValue(left.split(",", 1)[0] ?? "");
  const rightPrimary = normalizedValue(right.split(",", 1)[0] ?? "");
  return leftPrimary.length > 0 && leftPrimary === rightPrimary;
}

function sharesDirectEvidence(
  left: PreparedHint,
  right: PreparedHint,
): boolean {
  const leftEvidence = new Set(left.directEvidenceIDs);
  return right.directEvidenceIDs.some((id) => leftEvidence.has(id));
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
  return value.normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase("en-US")
    .match(/[\p{L}\p{N}]+/gu) ?? [];
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
