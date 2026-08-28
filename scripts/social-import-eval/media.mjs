const mediaUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) "
  + "AppleWebKit/605.1.15 Mobile/15E148";

const imageMIMETypes = new Set([
  "image/heic",
  "image/heif",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

const videoMIMETypes = new Set([
  "video/3gpp",
  "video/avi",
  "video/mp4",
  "video/mpeg",
  "video/quicktime",
  "video/webm",
  "video/x-flv",
  "video/x-ms-wmv",
  "video/x-msvideo",
]);

const tiktokPrivateHeaderDomains = [
  "tiktok.com",
  "tiktokcdn.com",
  "tiktokcdn-us.com",
  "ibytedtos.com",
  "byteoversea.com",
  "muscdn.com",
];

const acquiredMediaDomains = [
  ...tiktokPrivateHeaderDomains,
  "cdninstagram.com",
  "fbcdn.net",
  "instagram.com",
  "tiktok.com",
  "api.apify.com",
  "apifyusercontent.com",
  "brightdata.com",
  "storage.googleapis.com",
  "googleusercontent.com",
  "amazonaws.com",
  "cloudfront.net",
];

const allowedPrivateHeaderNames = new Set([
  "accept-language",
  "cookie",
  "referer",
  "user-agent",
]);

function mediaError(code, message, details = {}) {
  return { error: { code, message }, ...details };
}

function normalizedMIMEType(value) {
  return String(value ?? "").split(";", 1)[0].trim().toLowerCase();
}

function MIMEKind(value) {
  if (imageMIMETypes.has(value)) return "image";
  if (videoMIMETypes.has(value)) return "video";
  return null;
}

function hostIs(host, domain) {
  return host === domain || host.endsWith("." + domain);
}

function isUnsafeHost(hostname) {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, "");
  if (
    !host
    || host === "localhost"
    || host.endsWith(".localhost")
    || host.endsWith(".local")
    || host.endsWith(".internal")
  ) return true;

  // Acquired media should use a named HTTPS CDN/storage endpoint. Rejecting
  // literal addresses closes loopback, link-local, and private-address forms.
  if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host) || host.includes(":")) return true;
  return false;
}

function publicHTTPSURL(value) {
  try {
    const url = new URL(value);
    const host = url.hostname.toLowerCase();
    if (
      url.protocol !== "https:"
      || url.username
      || url.password
      || isUnsafeHost(host)
      || !acquiredMediaDomains.some((domain) => hostIs(host, domain))
    ) return null;
    return url;
  } catch {
    return null;
  }
}

function samePageURL(candidate, pageValue) {
  const page = publicHTTPSURL(pageValue);
  if (!page) return false;
  const normalizedPath = (value) => value.pathname.replace(/\/+$/, "") || "/";
  return candidate.origin === page.origin
    && normalizedPath(candidate) === normalizedPath(page);
}

function isKnownSocialPageURL(url) {
  const host = url.hostname.toLowerCase();
  const path = url.pathname;
  if (hostIs(host, "instagram.com")) {
    return /^\/(?:p|reel|reels|stories|tv)\//i.test(path);
  }
  if (host === "vm.tiktok.com" || host === "vt.tiktok.com") return true;
  if (hostIs(host, "tiktok.com")) {
    return /^\/@[^/]+\/video\/\d+/i.test(path)
      || /^\/(?:share\/video|t)\//i.test(path);
  }
  return false;
}

function mayReceiveTikTokPrivateHeaders(destination, socialPageURL) {
  const page = publicHTTPSURL(socialPageURL);
  if (!page || !hostIs(page.hostname.toLowerCase(), "tiktok.com")) return false;
  const host = destination.hostname.toLowerCase();
  return tiktokPrivateHeaderDomains.some((domain) => hostIs(host, domain));
}

function safeHeaderValue(value, maximumLength) {
  if (typeof value !== "string" || value.length > maximumLength || /[\r\n]/.test(value)) {
    return null;
  }
  return value;
}

function mediaRequestHeaders(media, destination, socialPageURL, expectedKind) {
  const headers = {
    accept: expectedKind === "video"
      ? "video/*;q=1.0,application/octet-stream;q=0.2"
      : "image/*;q=1.0,application/octet-stream;q=0.2",
    "user-agent": mediaUserAgent,
  };
  const page = publicHTTPSURL(socialPageURL);
  if (page) headers.referer = page.origin + "/";

  // Acquisition-scoped cookies/referers are never sent to arbitrary vendor
  // URLs. They are allowed only for a TikTok page -> TikTok media-domain flow.
  if (!mayReceiveTikTokPrivateHeaders(destination, socialPageURL)) return headers;
  const privateHeaders = media?.privateRequestHeaders;
  const entries = privateHeaders instanceof Headers
    ? privateHeaders.entries()
    : Object.entries(privateHeaders ?? {});
  for (const [rawName, rawValue] of entries) {
    const name = String(rawName).toLowerCase();
    if (!allowedPrivateHeaderNames.has(name)) continue;
    const maximumLength = name === "cookie" ? 16_384 : 4_096;
    const value = safeHeaderValue(rawValue, maximumLength);
    if (value) headers[name] = value;
  }
  return headers;
}

function sniffMIMEType(bytes) {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return "image/jpeg";
  }
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  )) return "image/png";
  if (
    bytes.length >= 12
    && bytes.subarray(0, 4).toString("ascii") === "RIFF"
    && bytes.subarray(8, 12).toString("ascii") === "WEBP"
  ) return "image/webp";
  if (
    bytes.length >= 12
    && bytes.subarray(0, 4).toString("ascii") === "RIFF"
    && bytes.subarray(8, 12).toString("ascii") === "AVI "
  ) return "video/x-msvideo";
  if (bytes.length >= 12 && bytes.subarray(4, 8).toString("ascii") === "ftyp") {
    const brand = bytes.subarray(8, 12).toString("ascii").toLowerCase();
    if (["avif", "avis", "heic", "heix", "hevc", "hevx", "mif1", "msf1"].includes(brand)) {
      return brand.startsWith("av") ? "image/heif" : "image/heic";
    }
    return brand.startsWith("qt") ? "video/quicktime" : "video/mp4";
  }
  if (
    bytes.length >= 4
    && bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3
  ) return "video/webm";
  if (bytes.length >= 3 && bytes.subarray(0, 3).toString("ascii") === "FLV") {
    return "video/x-flv";
  }
  if (
    bytes.length >= 4
    && bytes[0] === 0x00 && bytes[1] === 0x00 && bytes[2] === 0x01
    && [0xb3, 0xba].includes(bytes[3])
  ) return "video/mpeg";
  const textPrefix = bytes.subarray(0, 256).toString("utf8").trimStart().toLowerCase();
  if (
    textPrefix.startsWith("<!doctype html")
    || textPrefix.startsWith("<html")
    || textPrefix.startsWith("<?xml")
  ) return "text/html";
  if (textPrefix.startsWith("{") || textPrefix.startsWith("[")) return "application/json";
  return null;
}

function validatedMIMEType(bytes, declaredValue, expectedKind) {
  const declared = normalizedMIMEType(declaredValue);
  const sniffed = sniffMIMEType(bytes);
  const sniffedKind = MIMEKind(sniffed);
  if (sniffed && !sniffedKind) {
    return mediaError("unsupported_media_type", "Downloaded response was not supported media", {
      declaredMIMEType: declared || null,
      detectedMIMEType: sniffed,
    });
  }
  if (sniffedKind && sniffedKind !== expectedKind) {
    return mediaError("media_kind_mismatch", "Downloaded media kind did not match the acquired asset", {
      declaredMIMEType: declared || null,
      detectedMIMEType: sniffed,
    });
  }
  if (sniffedKind === expectedKind) return { mimeType: sniffed };
  if (MIMEKind(declared) === expectedKind) return { mimeType: declared };
  return mediaError("unsupported_media_type", "Downloaded response had no supported media MIME type", {
    declaredMIMEType: declared || null,
    detectedMIMEType: sniffed,
  });
}

async function readBoundedBody(response, maximumBytes) {
  const declaredValue = response.headers.get("content-length");
  if (declaredValue && /^\d+$/.test(declaredValue) && Number(declaredValue) > maximumBytes) {
    return mediaError("media_too_large", "Declared media length exceeded the inline limit", {
      maximumBytes,
    });
  }
  if (!response.body) return mediaError("empty_media", "Media response had no body");

  const reader = response.body.getReader();
  const chunks = [];
  let byteCount = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    byteCount += value.byteLength;
    if (byteCount > maximumBytes) {
      await reader.cancel().catch(() => {});
      return mediaError("media_too_large", "Downloaded media exceeded the inline limit", {
        maximumBytes,
      });
    }
    chunks.push(Buffer.from(value));
  }
  if (byteCount === 0) return mediaError("empty_media", "Media response was empty");
  return { bytes: Buffer.concat(chunks, byteCount), byteCount };
}

function redirectHeaders(headers, nextURL, socialPageURL) {
  if (mayReceiveTikTokPrivateHeaders(nextURL, socialPageURL)) return headers;
  const next = { ...headers };
  delete next.cookie;
  const page = publicHTTPSURL(socialPageURL);
  if (page) next.referer = page.origin + "/";
  else delete next.referer;
  return next;
}

export function boundedMediaByteLimit(name, fallback, hardMaximum) {
  const configured = Number(process.env[name]);
  const value = Number.isFinite(configured) && configured > 0 ? configured : fallback;
  return Math.min(Math.floor(value), hardMaximum);
}

export async function fetchAcquiredMediaBytes(media, {
  expectedKind,
  maximumBytes,
  socialPageURL,
  timeoutMs = 60_000,
} = {}) {
  if (!media || !["image", "video"].includes(expectedKind)) {
    return mediaError("invalid_media_descriptor", "Acquired media descriptor was invalid");
  }
  if (!Number.isFinite(maximumBytes) || maximumBytes <= 0) {
    return mediaError("invalid_media_limit", "Media byte limit was invalid");
  }
  const sourceValue = media.persistentURL ?? media.url;
  let url = publicHTTPSURL(sourceValue);
  if (!url) return mediaError("unsafe_media_url", "Acquired media URL was not safe public HTTPS");
  if (samePageURL(url, socialPageURL) || isKnownSocialPageURL(url)) {
    return mediaError("social_page_url", "Acquisition returned a social page URL instead of a media asset");
  }

  let headers = mediaRequestHeaders(media, url, socialPageURL, expectedKind);
  let response;
  for (let redirectCount = 0; redirectCount <= 5; redirectCount += 1) {
    try {
      response = await fetch(url, {
        headers,
        redirect: "manual",
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      return mediaError("media_download_failed", "Media download failed");
    }
    if (![301, 302, 303, 307, 308].includes(response.status)) break;
    if (redirectCount === 5) {
      return mediaError("media_redirect_limit", "Media download exceeded the redirect limit");
    }
    const location = response.headers.get("location");
    let nextURL;
    try {
      nextURL = location ? publicHTTPSURL(new URL(location, url).toString()) : null;
    } catch {
      nextURL = null;
    }
    if (!nextURL || samePageURL(nextURL, socialPageURL) || isKnownSocialPageURL(nextURL)) {
      return mediaError("unsafe_media_redirect", "Media download redirected to an unsafe or non-media URL");
    }
    headers = redirectHeaders(headers, nextURL, socialPageURL);
    url = nextURL;
  }
  if (!response?.ok) {
    return mediaError("media_http_error", "Media download returned HTTP " + (response?.status ?? 0), {
      statusCode: response?.status ?? 0,
    });
  }

  const body = await readBoundedBody(response, maximumBytes);
  if (body.error) return body;
  const MIME = validatedMIMEType(body.bytes, response.headers.get("content-type"), expectedKind);
  if (MIME.error) return { ...MIME, byteCount: body.byteCount };
  return {
    bytes: body.bytes,
    byteCount: body.byteCount,
    mimeType: MIME.mimeType,
    finalHost: url.hostname,
  };
}

async function readProbeBody(response, maximumBytes) {
  if (!response.body) return mediaError("empty_media", "Media response had no body");
  const reader = response.body.getReader();
  const chunks = [];
  let byteCount = 0;
  while (byteCount < maximumBytes) {
    const { done, value } = await reader.read();
    if (done) break;
    const remaining = maximumBytes - byteCount;
    chunks.push(Buffer.from(value.subarray(0, remaining)));
    byteCount += Math.min(value.byteLength, remaining);
    if (value.byteLength > remaining || byteCount >= maximumBytes) {
      await reader.cancel().catch(() => {});
      break;
    }
  }
  if (byteCount === 0) return mediaError("empty_media", "Media response was empty");
  return { bytes: Buffer.concat(chunks, byteCount), byteCount };
}

/**
 * Performs a bounded range probe so acquisition completeness is based on a
 * fetchable media response, not merely a nonempty (possibly expired) URL.
 * The returned diagnostics intentionally omit response bytes and source URLs.
 */
export async function probeAcquiredMediaAsset(media, {
  expectedKind,
  socialPageURL,
  maximumProbeBytes = 65_536,
  timeoutMs = 30_000,
} = {}) {
  if (!media || !["image", "video"].includes(expectedKind)) {
    return mediaError("invalid_media_descriptor", "Acquired media descriptor was invalid");
  }
  const sourceValue = media.persistentURL ?? media.url;
  let url = publicHTTPSURL(sourceValue);
  if (!url) return mediaError("unsafe_media_url", "Acquired media URL was not safe public HTTPS");
  if (samePageURL(url, socialPageURL) || isKnownSocialPageURL(url)) {
    return mediaError("social_page_url", "Acquisition returned a social page URL instead of a media asset");
  }
  let headers = {
    ...mediaRequestHeaders(media, url, socialPageURL, expectedKind),
    range: "bytes=0-" + Math.max(0, Math.floor(maximumProbeBytes) - 1),
  };
  let response;
  for (let redirectCount = 0; redirectCount <= 5; redirectCount += 1) {
    try {
      response = await fetch(url, {
        headers,
        redirect: "manual",
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch {
      return mediaError("media_download_failed", "Media probe failed");
    }
    if (![301, 302, 303, 307, 308].includes(response.status)) break;
    if (redirectCount === 5) {
      return mediaError("media_redirect_limit", "Media probe exceeded the redirect limit");
    }
    const location = response.headers.get("location");
    let nextURL;
    try {
      nextURL = location ? publicHTTPSURL(new URL(location, url).toString()) : null;
    } catch {
      nextURL = null;
    }
    if (!nextURL || samePageURL(nextURL, socialPageURL) || isKnownSocialPageURL(nextURL)) {
      return mediaError("unsafe_media_redirect", "Media probe redirected to an unsafe or non-media URL");
    }
    headers = {
      ...redirectHeaders(headers, nextURL, socialPageURL),
      range: headers.range,
    };
    url = nextURL;
  }
  if (!response?.ok) {
    return mediaError("media_http_error", "Media probe returned HTTP " + (response?.status ?? 0), {
      statusCode: response?.status ?? 0,
    });
  }
  const body = await readProbeBody(response, maximumProbeBytes);
  if (body.error) return body;
  const MIME = validatedMIMEType(body.bytes, response.headers.get("content-type"), expectedKind);
  if (MIME.error) return { ...MIME, byteCount: body.byteCount };
  return {
    byteCount: body.byteCount,
    mimeType: MIME.mimeType,
    finalHost: url.hostname,
    statusCode: response.status,
  };
}
