import type { SocialSource } from "./types.ts";

const instagramHosts = new Set([
  "instagram.com",
  "www.instagram.com",
  "m.instagram.com",
]);
const tiktokHosts = new Set([
  "tiktok.com",
  "www.tiktok.com",
  "m.tiktok.com",
  "vm.tiktok.com",
  "vt.tiktok.com",
]);

export function parseSocialSource(value: unknown): SocialSource | null {
  if (typeof value !== "string" || value.length > 2_048) return null;
  let url: URL;
  try {
    url = new URL(value.trim());
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password || url.port) {
    return null;
  }

  const host = url.hostname.toLowerCase();
  const path = url.pathname.replace(/\/{2,}/g, "/");
  if (instagramHosts.has(host)) {
    const match = path.match(
      /^\/(p|reels?|tv)\/([A-Za-z0-9_-]{5,30})(?:\/|$)/i,
    );
    if (!match) return null;
    return {
      platform: "instagram",
      contentType: match[1].toLowerCase().startsWith("reel") ? "reel" : "post",
      url: canonicalURL(url),
      sourceID: match[2],
    };
  }

  if (tiktokHosts.has(host)) {
    const direct = path.match(/^\/@[^/]{1,64}\/video\/(\d{10,30})(?:\/|$)/i);
    const shortPath = /^\/(?:t|share\/video)\/[A-Za-z0-9_-]{3,128}(?:\/|$)/i
      .test(path);
    const shortHost = (host === "vm.tiktok.com" || host === "vt.tiktok.com") &&
      path.length > 1 && path.length <= 160;
    if (!direct && !shortPath && !shortHost) return null;
    return {
      platform: "tiktok",
      contentType: "video",
      url: canonicalURL(url),
      sourceID: direct?.[1] ?? null,
    };
  }

  return null;
}

export function sourceValueMatches(
  value: unknown,
  source: SocialSource,
): boolean {
  if (typeof value !== "string" && typeof value !== "number") return false;
  const candidate = String(value).trim();
  if (!candidate) return false;
  if (source.sourceID && candidate === source.sourceID) return true;

  const parsed = parseSocialSource(candidate);
  if (source.sourceID && parsed?.sourceID === source.sourceID) return true;
  return canonicalSourceIdentity(candidate) ===
    canonicalSourceIdentity(source.url);
}

export function cleanString(
  value: unknown,
  maximumLength: number,
): string | null {
  if (typeof value !== "string") return null;
  const cleaned = replaceControlCharacters(value, false)
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maximumLength);
  return cleaned || null;
}

export function cleanMultilineString(
  value: unknown,
  maximumLength: number,
): string | null {
  if (typeof value !== "string") return null;
  const cleaned = replaceControlCharacters(value.replace(/\r\n?/g, "\n"), true)
    .split("\n")
    .map((line) => line.replace(/[\t ]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
    .slice(0, maximumLength);
  return cleaned || null;
}

function replaceControlCharacters(
  value: string,
  preserveNewlines: boolean,
): string {
  let output = "";
  for (const character of value) {
    const code = character.charCodeAt(0);
    const isControl = code <= 0x1f || code === 0x7f;
    output += isControl && !(preserveNewlines && character === "\n")
      ? " "
      : character;
  }
  return output;
}

export function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function canonicalURL(url: URL): string {
  const normalized = new URL(url);
  normalized.hash = "";
  normalized.search = "";
  normalized.hostname = normalized.hostname.toLowerCase();
  normalized.pathname = normalized.pathname.replace(/\/+$/, "") || "/";
  return normalized.toString();
}

function canonicalSourceIdentity(value: string): string | null {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase().replace(/^www\./, "");
    const path = url.pathname.replace(/\/+$/, "") || "/";
    return `${host}${path}`;
  } catch {
    return null;
  }
}
