import assert from "node:assert/strict";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  createMetricsAccumulator,
  formatSummary,
  summarizeSession,
} from "./codex-task-metrics.mjs";

function event(timestamp, type, payload = {}) {
  return { timestamp, type: "event_msg", payload: { type, ...payload } };
}

function tokenEvent(timestamp, total) {
  return event(timestamp, "token_count", {
    info: {
      total_token_usage: total,
    },
  });
}

test("summarizes a bounded task window from cumulative token counters", () => {
  const accumulator = createMetricsAccumulator({
    from: "2026-08-16T10:00:00.000Z",
    to: "2026-08-16T10:10:00.000Z",
  });
  const events = [
    tokenEvent("2026-08-16T09:59:59.000Z", {
      input_tokens: 100,
      cached_input_tokens: 60,
      cache_write_input_tokens: 0,
      output_tokens: 10,
      reasoning_output_tokens: 4,
      total_tokens: 110,
    }),
    event("2026-08-16T10:00:01.000Z", "task_started"),
    event("2026-08-16T10:00:02.000Z", "user_message", { message: "secret-user-content" }),
    event("2026-08-16T10:00:03.000Z", "agent_message", { message: "secret-agent-content" }),
    event("2026-08-16T10:00:04.000Z", "mcp_tool_call_end", {
      app_name: "GitHub",
      action_name: "get_pr_info",
      invocation: { arguments: { token: "secret-tool-content" } },
      duration: { secs: 2, nanos: 500_000_000 },
      result: { Ok: { isError: false, private: "secret-result-content" } },
    }),
    event("2026-08-16T10:00:05.000Z", "mcp_tool_call_end", {
      app_name: "GitHub",
      action_name: "get_pr_info",
      duration: { secs: 1, nanos: 0 },
      result: { Err: "private failure" },
    }),
    event("2026-08-16T10:00:06.000Z", "context_compacted"),
    event("2026-08-16T10:00:07.000Z", "task_complete", {
      duration_ms: 6_000,
      time_to_first_token_ms: 750,
      last_agent_message: "secret-final-content",
    }),
    tokenEvent("2026-08-16T10:00:08.000Z", {
      input_tokens: 500,
      cached_input_tokens: 360,
      cache_write_input_tokens: 0,
      output_tokens: 50,
      reasoning_output_tokens: 14,
      total_tokens: 550,
    }),
    event("2026-08-16T10:00:09.000Z", "user_message", { message: "secret-human-gate-response" }),
    tokenEvent("2026-08-16T10:11:00.000Z", {
      input_tokens: 900,
      cached_input_tokens: 700,
      cache_write_input_tokens: 0,
      output_tokens: 90,
      reasoning_output_tokens: 20,
      total_tokens: 990,
    }),
  ];
  for (const item of events) accumulator.accept(item);
  const summary = accumulator.finish();

  assert.deepEqual(summary.tokenUsage, {
    rawTotalTokens: 440,
    inputTokens: 400,
    cachedInputTokens: 300,
    freshInputTokens: 100,
    outputTokens: 40,
    reasoningOutputTokens: 10,
    cacheHitPercent: 75,
  });
  assert.equal(summary.counts.taskCompletes, 1);
  assert.equal(summary.counts.toolCalls, 2);
  assert.equal(summary.counts.toolFailures, 1);
  assert.equal(summary.counts.compactions, 1);
  assert.equal(summary.timing.toolCallMs, 3_500);
  assert.equal(summary.timing.humanGateWaitMs, 2_000);
  assert.equal(summary.timing.timeToFirstTokenP50Ms, 750);
  assert.deepEqual(summary.topTools, [{
    name: "GitHub.get_pr_info",
    calls: 2,
    failures: 1,
    durationMs: 3_500,
  }]);

  const output = formatSummary(summary, { reportedTokens: 123 });
  assert.match(output, /App-reported\/goal usage: 123 tokens/);
  assert.match(output, /cached: 300 \(75%\)/);
  assert.match(output, /Human-gate wait estimate: 2s/);
  assert.doesNotMatch(output, /secret-/);
  assert.doesNotMatch(JSON.stringify(summary), /secret-/);
});

test("rejects an inverted measurement window", () => {
  assert.throws(
    () => createMetricsAccumulator({
      from: "2026-08-16T10:10:00.000Z",
      to: "2026-08-16T10:00:00.000Z",
    }),
    /--from must be earlier than --to/,
  );
});

test("skips an interrupted JSONL line and reports the integrity gap", async () => {
  const directory = mkdtempSync(join(tmpdir(), "codex-task-metrics-"));
  const path = join(directory, "rollout.jsonl");
  writeFileSync(path, [
    JSON.stringify(tokenEvent("2026-08-16T10:00:00.000Z", {
      input_tokens: 10,
      cached_input_tokens: 5,
      cache_write_input_tokens: 0,
      output_tokens: 2,
      reasoning_output_tokens: 1,
      total_tokens: 12,
    })),
    "{\"interrupted\":\"secret-content",
    JSON.stringify(event("2026-08-16T10:00:01.000Z", "task_complete", {
      duration_ms: 1_000,
      time_to_first_token_ms: 100,
    })),
  ].join("\n"));

  try {
    const summary = await summarizeSession(path);
    assert.equal(summary.counts.malformedLines, 1);
    assert.doesNotMatch(formatSummary(summary), /secret-content/);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
