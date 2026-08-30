import type {
  AcquiredMedia,
  MediaIngestion,
  RuntimeDependencies,
  SocialSource,
} from "./types.ts";
import { Deadline, SocialImportError } from "./types.ts";

export const maximumImageBytes = 10 * 1_024 * 1_024;
export const maximumVideoBytes = 60 * 1_024 * 1_024;
export const maximumTotalMediaBytes = 60 * 1_024 * 1_024;

const mediaDomains = [
  "cdninstagram.com",
  "fbcdn.net",
  "tiktokcdn.com",
  "tiktokcdn-us.com",
  "ibytedtos.com",
  "byteoversea.com",
  "muscdn.com",
  "apifyusercontent.com",
];
const redirectStatuses = new Set([301, 302, 303, 307, 308]);

type DownloadedMedia = {
  bytes: Uint8Array;
  byteCount: number;
  mimeType: string;
};

export async function ingestAcquiredMedia(
  media: AcquiredMedia[],
  source: SocialSource,
  apifyToken: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
): Promise<MediaIngestion[]> {
  const results: MediaIngestion[] = [];
  let totalBytes = 0;
  for (const item of media.slice(0, 150)) {
    deadline.assertAvailable();
    const remaining = maximumTotalMediaBytes - totalBytes;
    if (remaining <= 0) {
      results.push(failed(item, "media_total_too_large"));
      continue;
    }
    try {
      const perItem = item.kind === "video"
        ? maximumVideoBytes
        : maximumImageBytes;
      const downloaded = await fetchMediaBytes(
        item.url,
        item.kind,
        Math.min(perItem, remaining),
        source,
        apifyToken,
        deadline,
        dependencies,
      );
      totalBytes += downloaded.byteCount;
      results.push({
        mediaID: item.id,
        kind: item.kind,
        status: "ok",
        byteCount: downloaded.byteCount,
        mimeType: downloaded.mimeType,
        bytes: downloaded.bytes,
        errorCode: null,
      });
    } catch (error) {
      results.push(failed(
        item,
        error instanceof SocialImportError ? error.code : "media_fetch_failed",
      ));
    }
  }
  return results;
}

export async function fetchMediaBytes(
  value: string,
  expectedKind: "image" | "video",
  maximumBytes: number,
  source: SocialSource,
  apifyToken: string,
  deadline: Deadline,
  dependencies: RuntimeDependencies,
): Promise<DownloadedMedia> {
  let url = validatedMediaURL(value);
  for (let redirectCount = 0; redirectCount <= 4; redirectCount += 1) {
    const response = await dependencies.fetch(url, {
      method: "GET",
      redirect: "manual",
      headers: mediaHeaders(url, expectedKind, source, apifyToken),
      signal: AbortSignal.timeout(deadline.remaining(30_000)),
    });
    if (redirectStatuses.has(response.status)) {
      const location = response.headers.get("location");
      await response.body?.cancel().catch(() => undefined);
      if (!location || redirectCount === 4) {
        throw new SocialImportError("media_redirect_invalid");
      }
      url = validatedMediaURL(new URL(location, url).toString());
      continue;
    }
    if (!response.ok) {
      await response.body?.cancel().catch(() => undefined);
      throw new SocialImportError("media_http_error");
    }
    const declaredLength = Number(response.headers.get("content-length"));
    if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
      await response.body?.cancel().catch(() => undefined);
      throw new SocialImportError("media_too_large");
    }
    const bytes = await boundedBytes(response, maximumBytes);
    const mimeType = validatedMIMEType(
      bytes,
      response.headers.get("content-type"),
      expectedKind,
    );
    return { bytes, byteCount: bytes.byteLength, mimeType };
  }
  throw new SocialImportError("media_redirect_invalid");
}

export function validatedMediaURL(value: string): URL {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw new SocialImportError("unsafe_media_url");
  }
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (
    url.protocol !== "https:" || url.username || url.password || url.port ||
    isUnsafeHost(host) || !isAllowedMediaDestination(url)
  ) {
    throw new SocialImportError("unsafe_media_url");
  }
  return url;
}

export function mayReceiveApifyAuthorization(url: URL): boolean {
  return url.hostname.toLowerCase() === "api.apify.com" &&
    /^\/v2\/key-value-stores\/[^/]+\/records\/[^/]+$/.test(url.pathname);
}

function isAllowedMediaDestination(url: URL): boolean {
  const host = url.hostname.toLowerCase();
  if (mayReceiveApifyAuthorization(url)) return true;
  return mediaDomains.some((domain) =>
    host === domain || host.endsWith(`.${domain}`)
  );
}

function isUnsafeHost(host: string): boolean {
  if (
    !host || host === "localhost" || host.endsWith(".localhost") ||
    host.endsWith(".local") || host.endsWith(".internal")
  ) return true;
  return /^\d{1,3}(?:\.\d{1,3}){3}$/.test(host) || host.includes(":");
}

function mediaHeaders(
  destination: URL,
  expectedKind: "image" | "video",
  source: SocialSource,
  apifyToken: string,
): Record<string, string> {
  const sourceURL = new URL(source.url);
  const headers: Record<string, string> = {
    accept: expectedKind === "video" ? "video/*" : "image/*",
    referer: `${sourceURL.origin}/`,
    "user-agent": "rec.me social import/1.0",
  };
  if (mayReceiveApifyAuthorization(destination)) {
    headers.authorization = `Bearer ${apifyToken}`;
  }
  return headers;
}

async function boundedBytes(
  response: Response,
  maximumBytes: number,
): Promise<Uint8Array> {
  if (!response.body) throw new SocialImportError("empty_media");
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let count = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    count += value.byteLength;
    if (count > maximumBytes) {
      await reader.cancel().catch(() => undefined);
      throw new SocialImportError("media_too_large");
    }
    chunks.push(value);
  }
  if (count === 0) throw new SocialImportError("empty_media");
  const bytes = new Uint8Array(count);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function validatedMIMEType(
  bytes: Uint8Array,
  declaredValue: string | null,
  expectedKind: "image" | "video",
): string {
  const sniffed = sniffMIMEType(bytes);
  const declared = declaredValue?.split(";", 1)[0].trim().toLowerCase() ?? "";
  if (!sniffed) {
    if (declared === "text/html" || declared === "application/json") {
      throw new SocialImportError("unsupported_media_type");
    }
    throw new SocialImportError("unverified_media_type");
  }
  if (!sniffed.startsWith(`${expectedKind}/`)) {
    throw new SocialImportError("media_kind_mismatch");
  }
  return sniffed;
}

function sniffMIMEType(bytes: Uint8Array): string | null {
  if (
    bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 &&
    bytes[2] === 0xff
  ) {
    return "image/jpeg";
  }
  if (
    bytes.length >= 8 && bytes[0] === 0x89 && bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a
  ) return "image/png";
  if (
    bytes.length >= 12 && ascii(bytes, 0, 4) === "RIFF" &&
    ascii(bytes, 8, 12) === "WEBP"
  ) return "image/webp";
  if (bytes.length >= 12 && ascii(bytes, 4, 8) === "ftyp") {
    const brand = ascii(bytes, 8, 12).toLowerCase();
    if (["avif", "avis"].includes(brand)) return "image/avif";
    if (["heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(brand)) {
      return "image/heic";
    }
    return brand.startsWith("qt") ? "video/quicktime" : "video/mp4";
  }
  if (
    bytes.length >= 4 && bytes[0] === 0x1a && bytes[1] === 0x45 &&
    bytes[2] === 0xdf && bytes[3] === 0xa3
  ) {
    return "video/webm";
  }
  return null;
}

function ascii(bytes: Uint8Array, start: number, end: number): string {
  return String.fromCharCode(...bytes.subarray(start, end));
}

function failed(item: AcquiredMedia, errorCode: string): MediaIngestion {
  return {
    mediaID: item.id,
    kind: item.kind,
    status: "failed",
    byteCount: null,
    mimeType: null,
    errorCode,
  };
}
