import assert from "node:assert/strict";
import { test } from "node:test";
import { appSelectionForHints } from "./app-selection.mjs";

const candidate = (id, name, locality = "Los Angeles", region = "CA", country = "US") => ({
  provider: "google_places", provider_place_id: id, name,
  formatted_address: `${locality}, ${region}, ${country}`, locality, region, country,
  latitude: 34.05, longitude: -118.24,
});
const hint = (name, area, places, modality = "caption") => ({
  name, area, classification: "destination", modality, resolved_places: places,
});

test("compiles actual production matcher and country logic, preserving LA and explicit Laos", async () => {
  const result = await appSelectionForHints([
    hint("Maru Coffee", "LA", [candidate("maru", "Maru Coffee")]),
    hint("Maru Coffee", "Laos", [candidate("wrong-country", "Maru Coffee")]),
  ]);
  assert.match(result.sourceHashes.matcher, /^[a-f0-9]{64}$/);
  assert.match(result.sourceHashes.country, /^[a-f0-9]{64}$/);
  assert.equal(result.rows[0].selectedCandidateID, "google-places-maru");
  assert.equal(result.rows[1].status, "needs_lookup");
});

test("actual matcher applies social venue descriptors and preserves separate Rory venues", async () => {
  const result = await appSelectionForHints([
    hint("Rory's Place", "Ojai", [candidate("rory", "Rory's Place", "Ojai"), candidate("other", "Rory's Other Place", "Ojai")]),
    hint("Rory's Other Place", "Ojai", [candidate("rory", "Rory's Place", "Ojai"), candidate("other", "Rory's Other Place", "Ojai")]),
    hint("Cowdog", "Vancouver", [candidate("cowdog", "Cowdog Coffee", "Vancouver", "BC", "CA")]),
  ]);
  assert.deepEqual(result.rows.map(row => row.selectedCandidateID), ["google-places-rory", "google-places-other", "google-places-cowdog"]);
  assert.equal(result.selectedCount, 3);
});

test("ambiguous branches remain reviewable and duplicate provider selections do not inflate counts", async () => {
  const result = await appSelectionForHints([
    hint("Maru Coffee", "LA", [candidate("one", "Maru Coffee"), { ...candidate("two", "Maru Coffee"), latitude: 34.09 }]),
    hint("Cowdog", "Vancouver", [candidate("cowdog", "Cowdog Coffee", "Vancouver", "BC", "CA")]),
    hint("Cowdog Coffee", "Vancouver", [candidate("cowdog", "Cowdog Coffee", "Vancouver", "BC", "CA")]),
  ]);
  assert.equal(result.rows[0].status, "needs_review");
  assert.equal(result.rows[0].selectedCandidateID, undefined);
  assert.equal(result.selectedCount, 1);
  assert.equal(result.duplicateSelectedCount, 1);
});

test("adapter rejects non-grounded classifications and preserves missing lookup status", async () => {
  const result = await appSelectionForHints([
    { ...hint("Los Angeles", "California", []), classification: "incidental" },
    hint("Missing venue", "Los Angeles", []),
  ]);
  assert.equal(result.rows.length, 1);
  assert.equal(result.rows[0].status, "needs_lookup");
  assert.equal(result.selectedCount, 0);
});

test("provider neighborhoods select the correct branch without ignoring a conflicting neighborhood", async () => {
  const correct = { ...candidate("correct", "Fixture Coffee"), area_components: ["Downtown Los Angeles"] };
  const wrong = { ...candidate("wrong", "Fixture Coffee"), latitude: 34.09, area_components: ["Echo Park"] };
  const result = await appSelectionForHints([
    hint("Fixture Coffee", "Downtown Los Angeles", [wrong, correct]),
    hint("Fixture Coffee", "Downtown LA", [wrong]),
  ]);
  assert.equal(result.rows[0].selectedCandidateID, "google-places-correct");
  assert.equal(result.rows[1].selectedCandidateID, undefined);
  assert.equal(result.rows[1].status, "needs_review");
});

test("confirmed area agreement has the same score for an accepted locality abbreviation", async () => {
  const place = { ...candidate("correct", "Fixture Coffee - Downtown"), area_components: ["Downtown Los Angeles"] };
  const result = await appSelectionForHints([
    hint("Fixture Coffee", "Downtown Los Angeles", [place]),
    hint("Fixture Coffee", "Downtown LA", [place]),
  ]);
  assert.equal(result.rows[0].selectedCandidateID, "google-places-correct");
  assert.equal(result.rows[1].selectedCandidateID, "google-places-correct");
  assert.equal(result.rows[0].bestScore, result.rows[1].bestScore);
});

test("short distinctive cafe brands are scored consistently without merging branches or other businesses", async () => {
  const cafe = candidate("cafe", "SUD café", "Vancouver", "BC", "CA");
  const restaurant = candidate("other", "SUD SOI", "Vancouver", "BC", "CA");
  const inputs = [
    hint("Sud", "Vancouver", [restaurant, cafe]),
    hint("Noct", "Vancouver", [candidate("noct", "Noct. Coffee", "Vancouver", "BC", "CA")]),
    hint("Sud", "Vancouver", [restaurant]),
    hint("Sud", "Vancouver", [cafe, { ...cafe, provider_place_id: "branch", latitude: 49.24 }]),
  ];
  // Separate imports: the wire adapter correctly deduplicates identical hints
  // within a single import, which would hide these independent negative cases.
  const results = await Promise.all(inputs.map(input => appSelectionForHints([input])));
  assert.equal(results[0].rows[0].selectedCandidateID, "google-places-cafe");
  assert.equal(results[1].rows[0].selectedCandidateID, "google-places-noct");
  assert.equal(results[2].rows[0].selectedCandidateID, undefined);
  assert.equal(results[3].rows[0].selectedCandidateID, undefined);
});
