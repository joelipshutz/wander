import assert from "node:assert/strict";
import test from "node:test";
import {
  cosineSimilarity,
  createInMemoryLexicalProvider,
  ndcgAt,
  passesFilters,
  reciprocalRank,
  runExperiment,
} from "./core.mjs";
import { places, queries, viewerProfile } from "./fixtures.mjs";

test("fixtures are fixed, internally valid, and intentionally small", () => {
  assert.equal(places.length, 40);
  assert.equal(queries.length, 15);
  const placeIds = new Set(places.map((place) => place.id));
  assert.equal(placeIds.size, places.length);
  for (const query of queries) {
    assert.ok(Object.keys(query.relevant).length > 0, `${query.id} has no relevance judgments`);
    for (const id of Object.keys(query.relevant)) {
      assert.ok(placeIds.has(id), `${query.id} references missing place ${id}`);
    }
  }
});

test("hard constraints reject ineligible candidates before ranking", () => {
  const plan = {
    categories: ["restaurant"],
    neighborhoods: ["Park Slope"],
    owner: null,
    maxPrice: 2,
    openTonight: true,
    vegetarianFriendly: false,
    groupFriendly: false,
    childFriendly: true,
  };
  assert.equal(passesFilters(places.find(({ id }) => id === "p37"), plan), true);
  assert.equal(passesFilters(places.find(({ id }) => id === "p40"), plan), false);
  assert.equal(passesFilters(places.find(({ id }) => id === "p05"), plan), false);
});

test("cosine similarity handles aligned, orthogonal, and invalid vectors", () => {
  assert.equal(cosineSimilarity([1, 0], [1, 0]), 1);
  assert.equal(cosineSimilarity([1, 0], [0, 1]), 0);
  assert.equal(cosineSimilarity([1], [1, 2]), 0);
});

test("ranking metrics reward useful order", () => {
  const relevance = { ideal: 3, useful: 1 };
  const best = [{ id: "ideal" }, { id: "useful" }];
  const reversed = [{ id: "useful" }, { id: "ideal" }];
  assert.equal(ndcgAt(best, relevance), 1);
  assert.ok(ndcgAt(best, relevance) > ndcgAt(reversed, relevance));
  assert.equal(reciprocalRank([{ id: "noise" }, { id: "ideal" }], relevance), 0.5);
});

test("experiment keeps semantic retrieval modular and preserves constraints", async () => {
  const selectedQueries = queries.filter(({ id }) => ["q03", "q15"].includes(id));
  const lexicalProvider = createInMemoryLexicalProvider(places);
  const semanticProvider = async (query) => {
    if (query.id === "q15") return [{ id: "p03", score: 0.99 }, { id: "p01", score: 0.7 }];
    return [{ id: "p02", score: 0.9 }, { id: "p06", score: 0.8 }, { id: "p01", score: 1 }];
  };
  const result = await runExperiment({
    places,
    queries: selectedQueries,
    lexicalProvider,
    semanticProvider,
    viewerProfile,
  });

  assert.equal(result.perQuery[1].pipelines.hybrid.results[0].id, "p03");
  assert.ok(result.perQuery[1].pipelines.hybrid.ndcgAt5 > result.perQuery[1].pipelines.reranked.ndcgAt5);
  assert.equal(result.pipelines.hybrid.constraintFailures, 0);
  assert.ok(
    result.perQuery[0].pipelines.hybrid.results.every(({ id }) => places.find((place) => place.id === id).owner === "Joe"),
  );
});
