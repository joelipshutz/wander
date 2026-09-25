// Execute the actual percentage query with fictional SQL rows. No events are
// ingested. Temporary, unsaved insights are soft-deleted even on failure.
import assert from "node:assert/strict";
import { notificationPromptClickSQL } from "./posthog-notification-prompts.mjs";
if (process.env.WANDER_POSTHOG_PROJECT_ID !== "557259") throw new Error("Expected Astir project 557259");
const key = process.env.WANDER_POSTHOG_PERSONAL_API_KEY;
if (!key) throw new Error("Missing scoped API key");
async function api(path, method = "GET", body) {
  const response = await fetch(`https://us.posthog.com/api/projects/557259/${path}`, {
    method, headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined
  });
  if (!response.ok) throw new Error(`PostHog fixture ${method} failed: ${response.status}`);
  return response.json();
}
const rows = [
  ["a", "one", "shown", ""], ["a", "one", "shown", ""],
  ["a", "one", "button_clicked", "continue"], ["a", "one", "button_clicked", "continue"],
  ["a", "two", "shown", ""], ["a", "two", "button_clicked", "open_settings"],
  ["a", "two", "button_clicked", "open_settings"], ["a", "two", "button_clicked", "not_now"],
  ["b", "three", "shown", ""], ["c", "four", "shown", ""],
  ["a", "orphan", "button_clicked", "continue"], ["other", "one", "button_clicked", "continue"]
];
const source = rows.map(([person, presentation, event, button]) => `select '${person}' as person_id, '${presentation}' as presentation_id,
 'product_upsell_${event}' as event, '${button}' as button, 'notification_app_open' as campaign,
 'app_opened' as trigger, '1' as impression_number`).join("\nunion all\n");
let assertions = 0;
for (const button of ["continue", "open_settings", "not_now", "empty"]) {
  let id;
  try {
    const query = notificationPromptClickSQL("", button === "empty" ? "continue" : button,
      button === "empty" ? `select * from (${source}) where 1 = 0` : source);
    const insight = await api("insights/", "POST", {
      name: `REC-593 temporary prompt percentage fixture: ${button}`,
      query: { kind: "HogQLQuery", query }, saved: false, tags: ["recme:validation-only"]
    });
    id = insight.id;
    const result = await api(`insights/${id}/?refresh=force_blocking`);
    assert.equal(Boolean(result.error), false);
    if (button === "empty") {
      assert.deepEqual(result.result, []);
      assertions += 1;
    } else {
      assert.equal(result.result.length, 1);
      const row = Object.fromEntries(result.columns.map((column, index) => [column, result.result[0][index]]));
      assert.equal(Number(row.shown_prompts), 4);
      assert.equal(Number(row.clicked_prompts), 1);
      assert.equal(Number(row.total_clicks), button === "not_now" ? 1 : 2);
      assert.equal(Number(row.click_percent), 25);
      assertions += 5;
    }
  } finally {
    if (id) await api(`insights/${id}/`, "PATCH", { deleted: true });
  }
}
console.log(JSON.stringify({ result: "PASS", assertions, scope: "Repeated shows/taps deduplicate; separate reminders and people stay separate; orphan clicks excluded; empty is unavailable; no events ingested; temporary insights soft-deleted." }));
