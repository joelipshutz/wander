export type SocialPlatform = "instagram" | "tiktok";

export type SocialContentType = "post" | "reel" | "video";

export type SocialSource = {
  platform: SocialPlatform;
  contentType: SocialContentType;
  url: string;
  sourceID: string | null;
};

export type TaggedLocation = {
  name: string;
  area: string | null;
};

export type InstagramTaggedProfile = {
  username: string;
  fullName: string | null;
};

export type AcquiredMedia = {
  id: string;
  index: number;
  kind: "image" | "video";
  url: string;
  thumbnailURL: string | null;
  altText: string | null;
  taggedProfiles?: InstagramTaggedProfile[];
};

export type AcquisitionEvidence = {
  title: string | null;
  caption: string | null;
  taggedLocations: TaggedLocation[];
  media: AcquiredMedia[];
};

export type EvidenceModality =
  | "caption"
  | "tagged_location"
  | "tagged_profile"
  | "alt_text"
  | "image_text"
  | "video_text"
  | "speech";

export type PublicEvidenceModality = Exclude<
  EvidenceModality,
  "tagged_profile"
>;

export type EvidenceText = {
  id: string;
  modality: "caption" | "tagged_location" | "tagged_profile" | "alt_text";
  text: string;
  area: string | null;
  mediaID: string | null;
};

export type EvidenceCatalog = {
  texts: EvidenceText[];
  media: AcquiredMedia[];
};

export type InstagramProfileAlias = {
  username: string;
  fullName: string;
  businessCategoryName?: string | null;
  isBusinessAccount?: boolean | null;
};

export type MediaIngestion = {
  mediaID: string;
  kind: "image" | "video";
  status: "ok" | "failed";
  byteCount: number | null;
  mimeType: string | null;
  bytes?: Uint8Array;
  errorCode: string | null;
};

export type ModelCandidate = {
  name: string;
  sourceMention: string;
  area: string;
  entityType: "poi" | "locality" | "region" | "country" | "route" | "unknown";
  itemIndex: number;
  classification:
    | "destination"
    | "itinerary"
    | "ambiguous"
    | "incidental"
    | "attribution"
    | "not_a_place";
  modality: EvidenceModality;
  evidenceIds: string[];
  confidence: number;
  startMs: number;
  endMs: number;
};

export type ModelMediaAssessment = {
  mediaEvidenceId: string;
  disposition: "place_mentions" | "no_place_mentions";
  candidateItemIndexes: number[];
};

export type ModelPostContext = {
  intent: "place_list" | "geography_list" | "mixed" | "unknown";
  declaredCount: number;
  declaredCountEvidenceIds: string[];
  globalArea: string;
  globalAreaEvidenceIds: string[];
};

export type PlaceHint = {
  name: string;
  area: string | null;
  classification: "destination" | "itinerary";
  modality: PublicEvidenceModality;
  evidence_ids: string[];
  confidence: number;
  start_ms: number | null;
  end_ms: number | null;
  resolved_places?: ResolvedPlace[];
};

export type ResolvedPlace = {
  provider: "google_places";
  provider_place_id: string;
  name: string;
  formatted_address: string | null;
  locality: string | null;
  region: string | null;
  country: string | null;
  latitude: number;
  longitude: number;
  primary_type: string | null;
  types: string[];
};

export type PublicFallbackReason =
  | "configuration_unavailable"
  | "admission_unavailable"
  | "feature_disabled"
  | "duplicate_request"
  | "retry_required"
  | "capacity_limited"
  | "quota_exceeded"
  | "acquisition_unavailable"
  | "media_unavailable"
  | "media_incomplete"
  | "understanding_unavailable"
  | "grounding_rejected"
  | "grounding_incomplete"
  | "deadline_exceeded";

export type UnderstandResponse = {
  schema_version: 1;
  outcome: "ok" | "partial" | "no_places" | "fallback";
  provider_path: "apify_gemini" | "apify_deterministic";
  hints: PlaceHint[];
  media_count: number;
  model_attempt_count: number;
  failure_category: PublicFallbackReason | null;
  declared_count_complete?: boolean;
};

export type Environment = (name: string) => string | undefined;

export type RuntimeDependencies = {
  fetch: typeof fetch;
  env: Environment;
  now: () => number;
  sleep: (milliseconds: number) => Promise<void>;
  random: () => number;
};

export class SocialImportError extends Error {
  readonly code: string;
  readonly attemptCount: number;

  constructor(code: string, attemptCount = 0) {
    super(code);
    this.name = "SocialImportError";
    this.code = code;
    this.attemptCount = attemptCount;
  }
}

export class Deadline {
  readonly startedAt: number;
  readonly expiresAt: number;
  private readonly now: () => number;

  constructor(durationMilliseconds: number, now: () => number) {
    this.now = now;
    this.startedAt = now();
    this.expiresAt = this.startedAt + durationMilliseconds;
  }

  remaining(capMilliseconds = Number.POSITIVE_INFINITY): number {
    const remaining = Math.floor(this.expiresAt - this.now());
    if (remaining <= 0) throw new SocialImportError("deadline_exceeded");
    return Math.max(1, Math.min(remaining, capMilliseconds));
  }

  assertAvailable(): void {
    this.remaining();
  }

  elapsed(): number {
    return Math.max(0, Math.round(this.now() - this.startedAt));
  }
}
