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
  "a", "an", "and", "at", "best", "cafe", "coffee", "coffeehouse", "food",
  "for", "in", "instagram", "local", "new", "of", "place", "restaurant",
  "shop", "spot", "the", "tiktok", "to", "try", "viral", "visit",
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
  "bar", "cafe", "coffee", "deli", "eatery", "grill", "kitchen", "restaurant",
]);

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
    .replace(/[^a-z0-9]+/g, " ")
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
  const name = trimPhrase(hint.name);
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
  const value = { ...hint, name, area: hint.area || null };
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
  const itineraryPatterns = [
    /\b(?:called|at|visited|visit|trying|place is)\s+(@?[^#\n.!?]{3,90}?)(?=\s+(?:(?:and|then|afterwards?)[^#\n.!?]{0,60}\b(?:at|from|visited|visit)\s+|(?:\d{1,3}\s*(?:-\s*)?(?:minutes?|mins?|hours?|hrs?)\s+)?(?:drive|head|go|hike|walk|travel|return)(?:\s+back)?\s+to\b)|[#\n.!?]|$)/giu,
    /\b(?:\d{1,3}\s*(?:-\s*)?(?:minutes?|mins?|hours?|hrs?)\s+)?(?:drive|head|go|hike|walk|travel|return)(?:\s+back)?\s+to\s+(@?[^#\n.!?]{3,90}?)(?=\s+(?:(?:and|then|afterwards?|before|after|for|where|which|with)\b|(?:\d{1,3}\s*(?:-\s*)?(?:minutes?|mins?|hours?|hrs?)\s+)?(?:drive|head|go|hike|walk|travel|return)(?:\s+back)?\s+to\b|make\s+sure\b)|[#\n.!?]|$)/giu,
  ];
  for (const pattern of itineraryPatterns) {
    for (const value of captures(text, pattern)) {
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
    text,
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
  for (const line of text.split(/\r?\n/)) {
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
  for (const handle of captures(text, /@([A-Za-z0-9._]{3,40})/gu)) {
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
  for (const line of text.split(/\r?\n/)) {
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

export function normalizeEvidence(value) {
  return {
    title: value?.title ?? null,
    caption: value?.caption ?? null,
    authorName: value?.authorName ?? null,
    taggedLocations: Array.isArray(value?.taggedLocations) ? value.taggedLocations : [],
    media: Array.isArray(value?.media) ? value.media : [],
    transcript: value?.transcript ?? null,
    sceneDescription: value?.sceneDescription ?? null,
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
  return output.slice(0, limit).map((hint) => ({
    ...hint,
    area: hint.area ?? area,
  }));
}

function labelMatchesPrediction(label, prediction) {
  const predictionKey = canonicalPlaceName(prediction).replaceAll(" ", "");
  const predictionCore = coreName(prediction);
  return [label.name, ...(label.aliases ?? [])].some((name) => {
    const labelKey = canonicalPlaceName(name).replaceAll(" ", "");
    if (labelKey && labelKey === predictionKey) return true;
    // A hint can preserve surrounding creator text (for example
    // "Yintang Spicy Hotpot, Convoy") and still contain the full labeled name.
    // Keep this deliberately one-way: a fragment such as "Caption" must never
    // satisfy "Caption by Hyatt Namba".
    if (labelKey.length >= 5 && predictionKey.includes(labelKey)) return true;
    const labelCore = coreName(name);
    return Boolean(labelCore && labelCore === predictionCore);
  });
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
    const predictionCore = coreName(prediction);
    if (!uniquePredictions.some((item) => {
      const itemKey = canonicalPlaceName(item).replaceAll(" ", "");
      const itemCore = coreName(item);
      return itemKey === predictionKey
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
  const forbiddenHits = labels.forbidden.filter((label) =>
    uniquePredictions.some((prediction) => labelMatchesPrediction(label, prediction))
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
    return { precision: null, recall: null, f1: null };
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
    summaries.push({
      variant,
      casesAttempted: items.length,
      acquisitionTransportSuccessRate: average(transportSuccess),
      completeAcquisitionRate: average(completeAcquisition),
      understandingSuccessRate: average(items.map((item) => item.understanding.status === "ok" ? 1 : 0)),
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
    "| Variant | Transport | Complete acquisition | Understanding | Hint macro P/R | Hint micro P/R | Post ≥1 | Exact set | Selected-name macro P/R | POI lookup health | POI selection | Mean latency |",
    "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
  ];
  for (const item of summary.variants) {
    lines.push(
      "| " + item.variant
      + " | " + percentage(item.acquisitionTransportSuccessRate)
      + " | " + percentage(item.completeAcquisitionRate)
      + " | " + percentage(item.understandingSuccessRate)
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
