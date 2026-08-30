import { cleanString } from "./source.ts";
import type {
  AcquisitionEvidence,
  EvidenceCatalog,
  EvidenceModality,
  MediaIngestion,
  ModelCandidate,
  PlaceHint,
} from "./types.ts";

const acceptedClassifications = new Set(["destination", "itinerary"]);
export const minimumGroundedConfidence = 0.55;
const acceptedModalities = new Set<EvidenceModality>([
  "caption",
  "tagged_location",
  "alt_text",
  "image_text",
  "video_text",
  "speech",
]);

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
): { hints: PlaceHint[]; rejectedCount: number } {
  const textByID = new Map(catalog.texts.map((item) => [item.id, item]));
  const mediaByID = new Map(catalog.media.map((item) => [item.id, item]));
  const ingestionByID = new Map(ingestions.map((item) => [item.mediaID, item]));
  const hints: PlaceHint[] = [];
  const indexes = new Map<string, number>();
  let rejectedCount = 0;

  for (const candidate of candidates.slice(0, 300)) {
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
      !name || !acceptedClassifications.has(candidate.classification) ||
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

    const hint: PlaceHint = {
      name,
      area: textualModality(candidate.modality)
        ? textAttestedArea(
          area,
          candidate.modality,
          evidenceIDs,
          textByID,
        )
        : area,
      classification: candidate.classification as "destination" | "itinerary",
      // The iOS contract treats accessibility text as image-derived text.
      modality: candidate.modality === "alt_text"
        ? "image_text"
        : candidate.modality,
      evidence_ids: evidenceIDs,
      confidence: candidate.confidence,
      start_ms: finiteTimestamp(candidate.startMs),
      end_ms: finiteTimestamp(candidate.endMs),
    };
    const identity = normalizedIdentity(name, hint.area);
    const existingIndex = indexes.get(identity);
    if (existingIndex === undefined) {
      if (hints.length >= limit) break;
      indexes.set(identity, hints.length);
      hints.push(hint);
    } else if (hint.confidence > hints[existingIndex].confidence) {
      hints[existingIndex] = hint;
    }
  }
  return { hints, rejectedCount };
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
  return `${words(name).join("")}|${words(area ?? "").join("")}`;
}

function finiteTimestamp(value: number): number | null {
  return Number.isFinite(value) && value >= 0 ? Math.round(value) : null;
}
