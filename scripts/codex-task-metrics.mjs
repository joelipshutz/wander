#!/usr/bin/env node

import { createReadStream } from "node:fs";
import readline from "node:readline";
import { pathToFileURL } from "node:url";

const TOKEN_FIELDS = [
  "input_tokens",
  "cached_input_tokens",
  "cache_write_input_tokens",
  "output_tokens",
  "reasoning_output_tokens",
  "total_tokens",
];

function emptyUsage() {
  return Object.fromEntries(TOKEN_FIELDS.map((field) => [field, 0]));
}

function parseTimestamp(value, flag) {
  if (value == null) return null;
  const timestamp = Date.parse(value);
  if (!Number.isFinite(timestamp)) {
    throw new Error(`${flag} must be an ISO-8601 timestamp`);
  }
  return timestamp;
}

function usageFrom(event) {
  return event?.payload?.info?.total_token_usage ?? null;
}

function subtractUsage(end, start) {
  if (!end) return null;
  const baseline = start ?? emptyUsage();
  return Object.fromEntries(TOKEN_FIELDS.map((field) => [
    field,
    Math.max(0, Number(end[field] ?? 0) - Number(baseline[field] ?? 0)),
  ]));
}

function percentile(values, percentage) {
  if (values.length === 0) return null;
  const sorted = [...values].sort((left, right) => left - right);
  const index = Math.max(0, Math.ceil((percentage / 100) * sorted.length) - 1);
  return sorted[index];
}

function durationMs(duration) {
  if (!duration) return 0;
  return (Number(duration.secs ?? 0) * 1000) + (Number(duration.nanos ?? 0) / 1_000_000);
}

function toolFailed(payload) {
  const result = payload?.result;
  if (!result || typeof result !== "object") return false;
  if (Object.hasOwn(result, "Err")) return true;
  return result.Ok?.isError === true;
}

function toolName(payload) {
  const app = payload.app_name ?? payload.invocation?.server ?? "unknown";
  const action = payload.action_name ?? payload.invocation?.tool ?? "unknown";
  return `${app}.${action}`;
}

export function createMetricsAccumulator({ from = null, to = null } = {}) {
  const fromMs = parseTimestamp(from, "--from");
  const toMs = parseTimestamp(to, "--to");
  if (fromMs != null && toMs != null && fromMs > toMs) {
    throw new Error("--from must be earlier than --to");
  }

  const counts = {
    taskStarts: 0,
    taskCompletes: 0,
    userMessages: 0,
    agentMessages: 0,
    toolCalls: 0,
    toolFailures: 0,
    compactions: 0,
    patches: 0,
    webSearches: 0,
    imageGenerations: 0,
    subAgentEvents: 0,
    abortedTurns: 0,
    tokenCountEvents: 0,
    malformedLines: 0,
  };
  const toolCalls = new Map();
  const timeToFirstToken = [];
  let activeTaskMs = 0;
  let humanGateWaitMs = 0;
  let toolCallMs = 0;
  let firstEventMs = null;
  let lastEventMs = null;
  let baselineUsage = null;
  let endUsage = null;
  let lastUsageBeforeTo = null;
  let lastTaskCompleteMs = null;

  function accept(event) {
    const timestampMs = Date.parse(event?.timestamp);
    if (!Number.isFinite(timestampMs)) return;

    const payload = event?.type === "event_msg" ? event.payload : null;
    if (payload?.type === "token_count") {
      const usage = usageFrom(event);
      if (usage && fromMs != null && timestampMs < fromMs) baselineUsage = usage;
      if (usage && (toMs == null || timestampMs <= toMs)) lastUsageBeforeTo = usage;
      if (usage && (fromMs == null || timestampMs >= fromMs) && (toMs == null || timestampMs <= toMs)) {
        endUsage = usage;
      }
    }

    if (fromMs != null && timestampMs < fromMs) return;
    if (toMs != null && timestampMs > toMs) return;
    firstEventMs = firstEventMs == null ? timestampMs : Math.min(firstEventMs, timestampMs);
    lastEventMs = lastEventMs == null ? timestampMs : Math.max(lastEventMs, timestampMs);
    if (!payload) return;

    switch (payload.type) {
      case "task_started":
        counts.taskStarts += 1;
        break;
      case "task_complete":
        counts.taskCompletes += 1;
        activeTaskMs += Number(payload.duration_ms ?? 0);
        lastTaskCompleteMs = timestampMs;
        if (Number.isFinite(payload.time_to_first_token_ms)) {
          timeToFirstToken.push(payload.time_to_first_token_ms);
        }
        break;
      case "user_message":
        counts.userMessages += 1;
        if (lastTaskCompleteMs != null && timestampMs >= lastTaskCompleteMs) {
          humanGateWaitMs += timestampMs - lastTaskCompleteMs;
          lastTaskCompleteMs = null;
        }
        break;
      case "agent_message":
        counts.agentMessages += 1;
        break;
      case "mcp_tool_call_end": {
        counts.toolCalls += 1;
        const failed = toolFailed(payload);
        if (failed) counts.toolFailures += 1;
        const elapsedMs = durationMs(payload.duration);
        toolCallMs += elapsedMs;
        const name = toolName(payload);
        const aggregate = toolCalls.get(name) ?? { calls: 0, failures: 0, durationMs: 0 };
        aggregate.calls += 1;
        aggregate.failures += failed ? 1 : 0;
        aggregate.durationMs += elapsedMs;
        toolCalls.set(name, aggregate);
        break;
      }
      case "context_compacted":
        counts.compactions += 1;
        break;
      case "patch_apply_end":
        counts.patches += 1;
        break;
      case "web_search_end":
        counts.webSearches += 1;
        break;
      case "image_generation_end":
        counts.imageGenerations += 1;
        break;
      case "sub_agent_activity":
        counts.subAgentEvents += 1;
        break;
      case "turn_aborted":
        counts.abortedTurns += 1;
        break;
      case "token_count":
        counts.tokenCountEvents += 1;
        break;
      default:
        break;
    }
  }

  function finish() {
    const tokenUsage = subtractUsage(endUsage ?? lastUsageBeforeTo, baselineUsage);
    const inputTokens = tokenUsage?.input_tokens ?? 0;
    const cachedInputTokens = tokenUsage?.cached_input_tokens ?? 0;
    const freshInputTokens = Math.max(0, inputTokens - cachedInputTokens);
    const topTools = [...toolCalls.entries()]
      .map(([name, value]) => ({
        name,
        calls: value.calls,
        failures: value.failures,
        durationMs: Math.round(value.durationMs),
      }))
      .sort((left, right) => right.calls - left.calls || right.durationMs - left.durationMs)
      .slice(0, 12);

    return {
      window: {
        from: from ?? (firstEventMs == null ? null : new Date(firstEventMs).toISOString()),
        to: to ?? (lastEventMs == null ? null : new Date(lastEventMs).toISOString()),
        wallClockMs: firstEventMs == null || lastEventMs == null
          ? 0
          : Math.max(0, lastEventMs - firstEventMs),
      },
      tokenUsage: tokenUsage == null ? null : {
        rawTotalTokens: tokenUsage.total_tokens,
        inputTokens,
        cachedInputTokens,
        freshInputTokens,
        outputTokens: tokenUsage.output_tokens,
        reasoningOutputTokens: tokenUsage.reasoning_output_tokens,
        cacheHitPercent: inputTokens === 0 ? 0 : Number(((cachedInputTokens / inputTokens) * 100).toFixed(2)),
      },
      counts,
      timing: {
        activeTaskMs,
        humanGateWaitMs,
        toolCallMs: Math.round(toolCallMs),
        timeToFirstTokenP50Ms: percentile(timeToFirstToken, 50),
        timeToFirstTokenP95Ms: percentile(timeToFirstToken, 95),
      },
      topTools,
      privacy: "Only aggregate counters, tool names, status, and duration are read; message, argument, and result content is ignored.",
    };
  }

  function malformedLine() {
    counts.malformedLines += 1;
  }

  return { accept, finish, malformedLine };
}

export async function summarizeSession(path, options = {}) {
  const accumulator = createMetricsAccumulator(options);
  const input = createReadStream(path, { encoding: "utf8" });
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  let lineNumber = 0;
  for await (const line of lines) {
    lineNumber += 1;
    if (!line.trim()) continue;
    try {
      accumulator.accept(JSON.parse(line));
    } catch {
      accumulator.malformedLine();
    }
  }
  return accumulator.finish();
}

function formatNumber(value) {
  return new Intl.NumberFormat("en-US").format(Math.round(value ?? 0));
}

function formatDuration(milliseconds) {
  const seconds = Math.round((milliseconds ?? 0) / 1000);
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return [hours ? `${hours}h` : null, minutes ? `${minutes}m` : null, `${remainder}s`]
    .filter(Boolean)
    .join(" ");
}

export function formatSummary(summary, { reportedTokens = null } = {}) {
  const tokens = summary.tokenUsage;
  const lines = [
    "Codex task metrics",
    `Window: ${summary.window.from ?? "unknown"} to ${summary.window.to ?? "unknown"}`,
    `Wall clock: ${formatDuration(summary.window.wallClockMs)} · active task time: ${formatDuration(summary.timing.activeTaskMs)}`,
  ];
  if (reportedTokens != null) {
    lines.push(`App-reported/goal usage: ${formatNumber(reportedTokens)} tokens`);
  }
  if (tokens) {
    lines.push(
      `Raw rollout tokens: ${formatNumber(tokens.rawTotalTokens)}`,
      `Input: ${formatNumber(tokens.inputTokens)} · cached: ${formatNumber(tokens.cachedInputTokens)} (${tokens.cacheHitPercent}%) · fresh: ${formatNumber(tokens.freshInputTokens)}`,
      `Output: ${formatNumber(tokens.outputTokens)} · reasoning output: ${formatNumber(tokens.reasoningOutputTokens)}`,
    );
  } else {
    lines.push("Raw rollout tokens: unavailable");
  }
  lines.push(
    `Events: ${summary.counts.taskCompletes} completed tasks · ${summary.counts.toolCalls} tool calls · ${summary.counts.toolFailures} tool failures · ${summary.counts.compactions} compactions`,
    `Messages: ${summary.counts.userMessages} user · ${summary.counts.agentMessages} agent`,
    `Human-gate wait estimate: ${formatDuration(summary.timing.humanGateWaitMs)}`,
    `Tool time: ${formatDuration(summary.timing.toolCallMs)} · TTFT p50/p95: ${formatNumber(summary.timing.timeToFirstTokenP50Ms)}/${formatNumber(summary.timing.timeToFirstTokenP95Ms)} ms`,
  );
  if (summary.counts.malformedLines > 0) {
    lines.push(`Rollout integrity: ${summary.counts.malformedLines} malformed JSONL line(s) skipped.`);
  }
  if (summary.topTools.length > 0) {
    lines.push("Top tools:");
    for (const tool of summary.topTools) {
      lines.push(`- ${tool.name}: ${tool.calls} calls, ${tool.failures} failures, ${formatDuration(tool.durationMs)}`);
    }
  }
  lines.push("Token note: raw rollout counters and app-reported goal usage are different measures; do not compare them as identical billing units.");
  lines.push("Wait note: human-gate wait is estimated from each completed task to the next user message; it does not inspect message content.");
  return `${lines.join("\n")}\n`;
}

function usage() {
  return `Usage:
  node scripts/codex-task-metrics.mjs --session <rollout.jsonl> [options]

Options:
  --from <timestamp>       Start of the measured window, inclusive.
  --to <timestamp>         End of the measured window, inclusive.
  --reported-tokens <n>    Optional app-reported/goal token total for side-by-side display.
  --json                   Print machine-readable JSON.
  --help                   Show this help.

The command emits aggregate measurements only. It never prints message text,
tool arguments, tool results, credentials, or environment values.`;
}

function parseArgs(argv) {
  const options = { from: null, json: false, reportedTokens: null, session: null, to: null };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) throw new Error(`Missing value after ${arg}`);
      return argv[index];
    };
    switch (arg) {
      case "--session": options.session = next(); break;
      case "--from": options.from = next(); break;
      case "--to": options.to = next(); break;
      case "--reported-tokens": options.reportedTokens = Number.parseInt(next(), 10); break;
      case "--json": options.json = true; break;
      case "--help":
      case "-h": options.help = true; break;
      default: throw new Error(`Unknown option: ${arg}`);
    }
  }
  if (!options.help && !options.session) throw new Error("--session is required");
  if (options.reportedTokens != null && (!Number.isInteger(options.reportedTokens) || options.reportedTokens < 0)) {
    throw new Error("--reported-tokens must be a non-negative integer");
  }
  return options;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  const summary = await summarizeSession(options.session, options);
  if (options.json) {
    process.stdout.write(`${JSON.stringify({ ...summary, reportedTokens: options.reportedTokens }, null, 2)}\n`);
  } else {
    process.stdout.write(formatSummary(summary, options));
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
