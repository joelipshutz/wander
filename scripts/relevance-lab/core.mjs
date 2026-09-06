import { performance } from "node:perf_hooks";

const TOP_K = 5;
const CANDIDATE_K = 12;

const clamp = (value, minimum = 0, maximum = 1) =>
  Math.min(maximum, Math.max(minimum, value));

const normalized = (value, minimum, maximum) =>
  maximum === minimum ? 1 : clamp((value - minimum) / (maximum - minimum));

export function buildLexicalPlaceDocument(place) {
  return [
    place.name,
    place.category,
    place.subcategory,
    place.neighborhood,
    place.city,
    place.description,
    ...place.tags,
  ]
    .filter(Boolean)
    .join(" | ");
}

export function buildSemanticPlaceDocument(place) {
  return [
    place.name,
    place.category,
    place.subcategory,
    place.neighborhood,
    place.city,
  ]
    .filter(Boolean)
    .join(" | ");
}

export function passesFilters(place, plan) {
  if (plan.categories.length > 0 && !plan.categories.includes(place.category)) return false;
  if (plan.neighborhoods.length > 0 && !plan.neighborhoods.includes(place.neighborhood)) return false;
  if (plan.owner && place.owner.toLocaleLowerCase() !== plan.owner.toLocaleLowerCase()) return false;
  if (plan.maxPrice !== null && place.price > plan.maxPrice) return false;
  if (plan.openTonight && !place.openTonight) return false;
  if (plan.vegetarianFriendly && !place.vegetarianFriendly) return false;
  if (plan.groupFriendly && !place.groupFriendly) return false;
  if (plan.childFriendly && !place.childFriendly) return false;
  return true;
}

export function cosineSimilarity(left, right) {
  if (!left || !right || left.length !== right.length || left.length === 0) return 0;
  let dot = 0;
  let leftMagnitude = 0;
  let rightMagnitude = 0;
  for (let index = 0; index < left.length; index += 1) {
    dot += left[index] * right[index];
    leftMagnitude += left[index] ** 2;
    rightMagnitude += right[index] ** 2;
  }
  if (leftMagnitude === 0 || rightMagnitude === 0) return 0;
  return dot / Math.sqrt(leftMagnitude * rightMagnitude);
}

export function createInMemoryLexicalProvider(places) {
  const tokens = (value) =>
    value
      .toLocaleLowerCase()
      .replace(/[^a-z0-9]+/g, " ")
      .trim()
      .split(/\s+/)
      .filter(Boolean);

  return async (query) => {
    const queryTokens = tokens(query.plan.lexicalQuery);
    return places
      .filter((place) => passesFilters(place, query.plan))
      .map((place) => {
        const documentTokens = tokens(buildLexicalPlaceDocument(place));
        const tokenSet = new Set(documentTokens);
        const matched = queryTokens.filter((token) => tokenSet.has(token)).length;
        return {
          id: place.id,
          score: queryTokens.length > 0 && matched === queryTokens.length
            ? matched / queryTokens.length
            : 0,
        };
      })
      .filter((candidate) => candidate.score > 0)
      .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
      .slice(0, CANDIDATE_K);
  };
}

export function createInMemorySemanticProvider(places, placeEmbeddings, queryEmbeddings) {
  return async (query) => places
    .filter((place) => passesFilters(place, query.plan))
    .map((place) => ({
      id: place.id,
      score: cosineSimilarity(queryEmbeddings.get(query.id), placeEmbeddings.get(place.id)),
    }))
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
    .slice(0, CANDIDATE_K);
}

const relationshipScore = (place) => ({
  self: 1,
  mutual: 0.92,
  following: 0.68,
  community: 0.12,
}[place.relationship] ?? 0);

function tasteScore(place, viewerProfile) {
  if (!viewerProfile) return 0;
  const normalizedTags = new Set(place.tags.map((tag) => tag.toLocaleLowerCase()));
  const preferredMatches = viewerProfile.preferredTags.filter((tag) => normalizedTags.has(tag)).length;
  const avoidedMatches = viewerProfile.avoidedTags.filter((tag) => normalizedTags.has(tag)).length;
  const neighborhoodMatch = viewerProfile.preferredNeighborhoods.includes(place.neighborhood) ? 0.2 : 0;
  return clamp(preferredMatches / 3 + neighborhoodMatch - avoidedMatches / 2);
}

const personalScore = (place, viewerProfile) =>
  0.36 * relationshipScore(place)
  + 0.22 * normalized(place.rating, 1, 5)
  + 0.12 * normalized(Math.log1p(place.visits), 0, Math.log1p(12))
  + 0.3 * tasteScore(place, viewerProfile);

const communityScore = (place) =>
  0.68 * normalized(place.communityRating, 1, 5)
  + 0.32 * normalized(Math.log1p(place.communitySupport), 0, Math.log1p(140));

const proximityScore = (place) => 1 - normalized(place.distanceKm, 0, 8);

const contextScore = (place, plan, viewerProfile) => {
  const totalWeight = plan.personalization + plan.community;
  if (totalWeight === 0) return 0;
  return (
    plan.personalization * personalScore(place, viewerProfile)
    + plan.community * communityScore(place)
  ) / totalWeight;
};

const topIds = (places, score, count) =>
  [...places]
    .sort((left, right) => score(right) - score(left) || left.id.localeCompare(right.id))
    .slice(0, count)
    .map((place) => place.id);

function buildContextCandidateIds(eligiblePlaces, query, viewerProfile) {
  const ids = new Set();

  if (query.plan.owner) {
    for (const place of eligiblePlaces) ids.add(place.id);
  }

  // Each enabled source contributes a bounded candidate set. The weights tune
  // final ordering, not whether the source is allowed to recover lexical misses.
  if (query.plan.personalization > 0) {
    for (const id of topIds(eligiblePlaces, (place) => personalScore(place, viewerProfile), 4)) ids.add(id);
  }
  if (query.plan.community > 0) {
    for (const id of topIds(eligiblePlaces, communityScore, 4)) ids.add(id);
  }
  return ids;
}

const maxScore = (scoreMap) => Math.max(0, ...scoreMap.values());

function rankCandidates({
  candidateIds,
  placesById,
  lexicalScores,
  semanticScores = new Map(),
  plan,
  viewerProfile,
  pipeline,
}) {
  const lexicalMaximum = maxScore(lexicalScores);
  const ranked = [];

  for (const id of candidateIds) {
    const place = placesById.get(id);
    if (!place || !passesFilters(place, plan)) continue;

    const lexical = lexicalMaximum > 0 ? (lexicalScores.get(id) ?? 0) / lexicalMaximum : 0;
    const semantic = clamp(semanticScores.get(id) ?? 0);
    const context = contextScore(place, plan, viewerProfile);
    const proximity = proximityScore(place);
    const exactNameBoost = plan.lexicalQuery
      .toLocaleLowerCase()
      .includes(place.name.toLocaleLowerCase()) ? 1 : 0;

    const score = pipeline === "hybrid"
      ? 0.34 * lexical + 0.34 * semantic + 0.24 * context + 0.05 * proximity + 0.03 * exactNameBoost
      : 0.58 * lexical + 0.33 * context + 0.06 * proximity + 0.03 * exactNameBoost;

    ranked.push({
      id,
      score,
      features: { lexical, semantic, context, proximity, exactNameBoost },
    });
  }

  return ranked
    .sort((left, right) => right.score - left.score || left.id.localeCompare(right.id))
    .slice(0, TOP_K);
}

function discount(index) {
  return 1 / Math.log2(index + 2);
}

export function ndcgAt(results, relevance, at = TOP_K) {
  const gains = results.slice(0, at).reduce((sum, result, index) => {
    const grade = relevance[result.id] ?? 0;
    return sum + (2 ** grade - 1) * discount(index);
  }, 0);
  const idealGrades = Object.values(relevance).sort((left, right) => right - left).slice(0, at);
  const ideal = idealGrades.reduce(
    (sum, grade, index) => sum + (2 ** grade - 1) * discount(index),
    0,
  );
  return ideal === 0 ? 0 : gains / ideal;
}

export function reciprocalRank(results, relevance) {
  const index = results.findIndex((result) => (relevance[result.id] ?? 0) > 0);
  return index === -1 ? 0 : 1 / (index + 1);
}

export function constraintFailures(results, placesById, plan) {
  return results.filter((result) => {
    const place = placesById.get(result.id);
    return !place || !passesFilters(place, plan);
  }).length;
}

function aggregatePipeline(perQuery, pipeline) {
  const rows = perQuery.map((row) => row.pipelines[pipeline]);
  return {
    ndcgAt5: rows.reduce((sum, row) => sum + row.ndcgAt5, 0) / rows.length,
    mrr: rows.reduce((sum, row) => sum + row.reciprocalRank, 0) / rows.length,
    constraintFailures: rows.reduce((sum, row) => sum + row.constraintFailures, 0),
    meanLatencyMs: rows.reduce((sum, row) => sum + row.latencyMs, 0) / rows.length,
  };
}

function aggregateSlice(perQuery, pipeline, intent) {
  const matching = perQuery.filter((row) => row.intent === intent);
  if (matching.length === 0) return null;
  return matching.reduce((sum, row) => sum + row.pipelines[pipeline].ndcgAt5, 0) / matching.length;
}

export async function runExperiment({
  places,
  queries,
  lexicalProvider,
  semanticProvider,
  viewerProfile = null,
}) {
  const placesById = new Map(places.map((place) => [place.id, place]));
  const perQuery = [];

  for (const query of queries) {
    const eligiblePlaces = places.filter((place) => passesFilters(place, query.plan));

    const lexicalStartedAt = performance.now();
    const lexicalCandidates = await lexicalProvider(query);
    const lexicalScores = new Map(lexicalCandidates.map(({ id, score }) => [id, Number(score)]));
    const lexicalResults = lexicalCandidates.slice(0, TOP_K).map(({ id, score }) => ({
      id,
      score: Number(score),
      features: { lexical: Number(score), semantic: 0, context: 0, proximity: 0 },
    }));
    const lexicalLatency = performance.now() - lexicalStartedAt;

    const rerankStartedAt = performance.now();
    const rerankCandidateIds = new Set(lexicalCandidates.map(({ id }) => id));
    for (const id of buildContextCandidateIds(eligiblePlaces, query, viewerProfile)) rerankCandidateIds.add(id);
    const rerankedResults = rankCandidates({
      candidateIds: rerankCandidateIds,
      placesById,
      lexicalScores,
      plan: query.plan,
      viewerProfile,
      pipeline: "reranked",
    });
    const rerankLatency = lexicalLatency + performance.now() - rerankStartedAt;

    const hybridStartedAt = performance.now();
    const semanticCandidates = await semanticProvider(query);
    const semanticScores = new Map(
      semanticCandidates.map(({ id, score }) => [id, Number(score)]),
    );
    const semanticCandidateIds = semanticCandidates.map(({ id }) => id);
    const hybridCandidateIds = new Set([...rerankCandidateIds, ...semanticCandidateIds]);
    const hybridResults = rankCandidates({
      candidateIds: hybridCandidateIds,
      placesById,
      lexicalScores,
      semanticScores,
      plan: query.plan,
      viewerProfile,
      pipeline: "hybrid",
    });
    const hybridLatency = lexicalLatency + performance.now() - hybridStartedAt;

    const pipelineResults = {
      lexical: { results: lexicalResults, latencyMs: lexicalLatency },
      reranked: { results: rerankedResults, latencyMs: rerankLatency },
      hybrid: { results: hybridResults, latencyMs: hybridLatency },
    };

    for (const value of Object.values(pipelineResults)) {
      value.ndcgAt5 = ndcgAt(value.results, query.relevant);
      value.reciprocalRank = reciprocalRank(value.results, query.relevant);
      value.constraintFailures = constraintFailures(value.results, placesById, query.plan);
    }

    perQuery.push({
      id: query.id,
      text: query.text,
      intent: query.intent,
      pipelines: pipelineResults,
    });
  }

  const pipelines = Object.fromEntries(
    ["lexical", "reranked", "hybrid"].map((pipeline) => [
      pipeline,
      {
        ...aggregatePipeline(perQuery, pipeline),
        semanticNdcgAt5: aggregateSlice(perQuery, pipeline, "semantic"),
        namedPersonNdcgAt5: aggregateSlice(perQuery, pipeline, "named-person"),
        communityNdcgAt5: aggregateSlice(perQuery, pipeline, "community"),
      },
    ]),
  );

  const semanticGain = pipelines.hybrid.semanticNdcgAt5 - pipelines.reranked.semanticNdcgAt5;
  const namedPersonRegression = pipelines.reranked.namedPersonNdcgAt5 - pipelines.hybrid.namedPersonNdcgAt5;
  const vectorDecision = semanticGain >= 0.05 && namedPersonRegression <= 0.02
    ? "keep"
    : "defer";

  return {
    pipelines,
    perQuery,
    decision: {
      vectorDecision,
      peopleVectorDecision: "defer",
      semanticGain,
      namedPersonRegression,
      rule: "Keep vectors only if semantic nDCG@5 gains at least 0.05 without more than 0.02 named-person nDCG@5 regression.",
      peopleVectorReason: "Synthetic fixtures cannot validate learned person-to-place affinity. Use explicit taste and relationship features until real interaction judgments exist.",
    },
  };
}
