import "@supabase/functions-js/edge-runtime.d.ts";

type WorkerJob = {
  id: string;
  source_type: string;
  status: string;
  attempt_count: number;
  provider_steps_json: string[];
  extracted_candidates_json: ExtractedCandidate[];
  confidence: number;
  error_code?: string | null;
  error_message?: string | null;
};

type SourceArtifact = {
  id: string;
  type: string;
  original_input: string;
  normalized_input: string;
  normalized_source_hash: string;
  local_asset_ref?: string | null;
  remote_asset_ref?: string | null;
};

type WorkerPayload = {
  job: WorkerJob;
  source_artifact: SourceArtifact;
};

type ExtractedCandidate = {
  id: string;
  name: string;
  category: string;
  address?: string | null;
  locality?: string | null;
  region?: string | null;
  country?: string | null;
  latitude: number;
  longitude: number;
  source_provider: string;
  source_provider_place_id: string;
  confidence: number;
};

type ExtractionResult = {
  status: "needs_confirmation" | "failed" | "no_place_found";
  candidates: ExtractedCandidate[];
  confidence: number;
  providerSteps: string[];
  errorCode?: string | null;
  errorMessage?: string | null;
};

const jsonHeaders = { "Content-Type": "application/json" };

Deno.serve(async (req) => {
  try {
    return await handleRequest(req);
  } catch (error) {
    console.error("extraction_worker_error", error instanceof Error ? error.message : "unknown_error");
    return Response.json({ error: "internal_error" }, { status: 500 });
  }
});

async function handleRequest(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, { status: 405 });
  }

  const body = await readBody(req);
  const jobId = stringValue(body.job_id);

  if (jobId) {
    const authorization = req.headers.get("authorization");
    if (!authorization) {
      return Response.json({ error: "missing_authorization" }, { status: 401 });
    }

    const payload = await authenticatedRpc<WorkerPayload>("claim_extraction_job", { input_job_id: jobId }, authorization);
    const result = await processPayload(payload);
    return Response.json(result);
  }

  if (!isAuthorizedWorker(req)) {
    return Response.json({ error: "missing_worker_secret" }, { status: 401 });
  }

  const limit = Math.min(Math.max(Number(body.limit ?? 1) || 1, 1), 10);
  const processed = [];
  for (let index = 0; index < limit; index += 1) {
    const payload = await serviceRpc<WorkerPayload | null>("claim_next_extraction_job", {});
    if (!payload) break;
    processed.push(await processPayload(payload));
  }

  return Response.json({ processed_count: processed.length, processed });
}

async function readBody(req: Request): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (!text.trim()) return {};

  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

function isAuthorizedWorker(req: Request): boolean {
  const workerSecret = Deno.env.get("WANDER_WORKER_SECRET");
  if (!workerSecret) return false;
  const header = req.headers.get("x-wander-worker-secret");
  const bearer = req.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return header === workerSecret || bearer === workerSecret;
}

async function processPayload(payload: WorkerPayload): Promise<unknown> {
  if (payload.job.status !== "running") {
    return resultFromPayload(payload);
  }

  const result = await extract(payload.source_artifact);
  return await serviceRpc("complete_extraction_job", {
    input_job_id: payload.job.id,
    input_status: result.status,
    input_candidates: result.candidates,
    input_confidence: result.confidence,
    input_provider_steps: result.providerSteps,
    input_error_code: result.errorCode ?? null,
    input_error_message: result.errorMessage ?? null,
  });
}

function resultFromPayload(payload: WorkerPayload): unknown {
  return {
    extraction_job_id: payload.job.id,
    status: payload.job.status,
    attempt_count: payload.job.attempt_count,
    provider_steps_json: payload.job.provider_steps_json,
    extracted_candidates_json: payload.job.extracted_candidates_json,
    confidence: payload.job.confidence,
    error_code: payload.job.error_code ?? null,
    error_message: payload.job.error_message ?? null,
  };
}

async function extract(source: SourceArtifact): Promise<ExtractionResult> {
  const steps = ["worker_started"];

  if (source.type === "url") {
    const url = normalizedURL(source.normalized_input);
    if (!url) {
      return noPlace(["worker_started", "invalid_url"], "invalid_url", "That link is not a valid URL.");
    }

    const resolvedURL = await resolveRedirect(url, steps);
    const googleCandidate = googleMapsCandidate(resolvedURL, source, steps);
    if (googleCandidate) {
      return {
        status: "needs_confirmation",
        candidates: [googleCandidate],
        confidence: googleCandidate.confidence,
        providerSteps: steps,
      };
    }

    const appleCandidate = appleMapsCandidate(resolvedURL, source, steps);
    if (appleCandidate) {
      return {
        status: "needs_confirmation",
        candidates: [appleCandidate],
        confidence: appleCandidate.confidence,
        providerSteps: steps,
      };
    }

    const metadataCandidate = await webMetadataCoordinateCandidate(resolvedURL, source, steps);
    if (metadataCandidate) {
      return {
        status: "needs_confirmation",
        candidates: [metadataCandidate],
        confidence: metadataCandidate.confidence,
        providerSteps: steps,
      };
    }

    return noPlace(
      steps.concat("no_coordinate_backed_candidate"),
      "needs_manual_resolution",
      "I could not find a coordinate-backed place in that link yet.",
    );
  }

  if (source.type === "image") {
    return noPlace(
      steps.concat("photo_ocr_not_configured"),
      "photo_ocr_not_configured",
      "Photo OCR is not wired yet. Add the place manually for now.",
    );
  }

  return noPlace(
    steps.concat("unsupported_source_type"),
    "unsupported_source_type",
    `Extraction is not wired for ${source.type}.`,
  );
}

function normalizedURL(raw: string): URL | null {
  try {
    return new URL(raw.trim());
  } catch {
    return null;
  }
}

async function resolveRedirect(url: URL, steps: string[]): Promise<URL> {
  if (!isShortMapHost(url.hostname)) return url;

  steps.push("short_url_redirect_lookup");
  try {
    const response = await fetch(url, {
      redirect: "follow",
      headers: { "User-Agent": "Wander extraction worker" },
    });
    if (response.url) {
      steps.push("short_url_redirect_resolved");
      return new URL(response.url);
    }
  } catch (error) {
    steps.push("short_url_redirect_failed");
    console.warn("short_url_redirect_failed", error instanceof Error ? error.message : "unknown_error");
  }

  return url;
}

function googleMapsCandidate(url: URL, source: SourceArtifact, steps: string[]): ExtractedCandidate | null {
  if (!isGoogleMapsHost(url.hostname) && !isShortMapHost(url.hostname)) return null;

  steps.push("google_maps_url_adapter");
  const coordinates = coordinatesFromGoogleURL(url);
  const name = placeNameFromGoogleURL(url) ?? placeNameFromQuery(url);

  if (!coordinates || !name) {
    steps.push("google_maps_missing_name_or_coordinates");
    return null;
  }

  steps.push("google_maps_coordinate_candidate");
  return {
    id: `extracted_${source.normalized_source_hash}`,
    name,
    category: inferredCategory(name),
    latitude: coordinates.latitude,
    longitude: coordinates.longitude,
    source_provider: "google_maps_link",
    source_provider_place_id: `${url.origin}${url.pathname}`,
    confidence: 0.86,
  };
}

function appleMapsCandidate(url: URL, source: SourceArtifact, steps: string[]): ExtractedCandidate | null {
  if (!isAppleMapsHost(url.hostname)) return null;

  steps.push("apple_maps_url_adapter");
  const coordinates = coordinatesFromAppleURL(url);
  const name = placeNameFromQuery(url);

  if (!coordinates || !name) {
    steps.push("apple_maps_missing_name_or_coordinates");
    return null;
  }

  steps.push("apple_maps_coordinate_candidate");
  return {
    id: `extracted_${source.normalized_source_hash}`,
    name,
    category: inferredCategory(name),
    latitude: coordinates.latitude,
    longitude: coordinates.longitude,
    source_provider: "apple_maps_link",
    source_provider_place_id: url.toString(),
    confidence: 0.84,
  };
}

async function webMetadataCoordinateCandidate(url: URL, source: SourceArtifact, steps: string[]): Promise<ExtractedCandidate | null> {
  steps.push("web_metadata_lookup");
  try {
    const response = await fetch(url, {
      redirect: "follow",
      headers: { "User-Agent": "Wander extraction worker" },
    });
    const contentType = response.headers.get("content-type") ?? "";
    if (!contentType.includes("text/html")) {
      steps.push("web_metadata_non_html");
      return null;
    }

    const html = (await response.text()).slice(0, 250_000);
    const coordinates = coordinatesFromHTML(html);
    const name = firstNonEmpty([
      metaContent(html, "og:title"),
      metaContent(html, "twitter:title"),
      titleContent(html),
    ]);

    if (!coordinates || !name) {
      steps.push("web_metadata_missing_name_or_coordinates");
      return null;
    }

    steps.push("web_metadata_coordinate_candidate");
    return {
      id: `extracted_${source.normalized_source_hash}`,
      name: cleanTitle(name),
      category: inferredCategory(name),
      latitude: coordinates.latitude,
      longitude: coordinates.longitude,
      source_provider: "web_metadata",
      source_provider_place_id: url.toString(),
      confidence: 0.72,
    };
  } catch (error) {
    steps.push("web_metadata_failed");
    console.warn("web_metadata_failed", error instanceof Error ? error.message : "unknown_error");
    return null;
  }
}

function coordinatesFromGoogleURL(url: URL): { latitude: number; longitude: number } | null {
  const text = decodeURIComponent(url.toString());
  const atMatch = text.match(/@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)/);
  if (atMatch) return coordinatesFromParts(atMatch[1], atMatch[2]);

  const dataMatch = text.match(/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/);
  if (dataMatch) return coordinatesFromParts(dataMatch[1], dataMatch[2]);

  const query = firstNonEmpty([url.searchParams.get("q"), url.searchParams.get("query")]);
  const queryMatch = query?.match(/(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/);
  if (queryMatch) return coordinatesFromParts(queryMatch[1], queryMatch[2]);

  return null;
}

function coordinatesFromAppleURL(url: URL): { latitude: number; longitude: number } | null {
  const coordinateValue = firstNonEmpty([
    url.searchParams.get("ll"),
    url.searchParams.get("sll"),
    url.searchParams.get("center"),
  ]);
  const coordinateMatch = coordinateValue?.match(/(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/);
  if (coordinateMatch) return coordinatesFromParts(coordinateMatch[1], coordinateMatch[2]);

  const query = firstNonEmpty([url.searchParams.get("q"), url.searchParams.get("query")]);
  const queryMatch = query?.match(/(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/);
  if (queryMatch) return coordinatesFromParts(queryMatch[1], queryMatch[2]);

  return null;
}

function coordinatesFromHTML(html: string): { latitude: number; longitude: number } | null {
  const latitude = firstNonEmpty([
    metaContent(html, "place:location:latitude"),
    metaContent(html, "geo.position")?.split(";")[0],
    metaContent(html, "ICBM")?.split(",")[0],
  ]);
  const longitude = firstNonEmpty([
    metaContent(html, "place:location:longitude"),
    metaContent(html, "geo.position")?.split(";")[1],
    metaContent(html, "ICBM")?.split(",")[1],
  ]);
  if (!latitude || !longitude) return null;
  return coordinatesFromParts(latitude.trim(), longitude.trim());
}

function coordinatesFromParts(latitudeValue: string, longitudeValue: string): { latitude: number; longitude: number } | null {
  const latitude = Number(latitudeValue);
  const longitude = Number(longitudeValue);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}

function placeNameFromGoogleURL(url: URL): string | null {
  const parts = url.pathname.split("/").map((part) => decodeURIComponent(part.replaceAll("+", " ")));
  const placeIndex = parts.findIndex((part) => part === "place" || part === "search");
  if (placeIndex >= 0 && parts[placeIndex + 1]) {
    return cleanTitle(parts[placeIndex + 1]);
  }
  return null;
}

function placeNameFromQuery(url: URL): string | null {
  const query = firstNonEmpty([
    url.searchParams.get("q"),
    url.searchParams.get("query"),
    url.searchParams.get("destination"),
    url.searchParams.get("daddr"),
    url.searchParams.get("address"),
  ]);
  if (!query || /^-?\d+(?:\.\d+)?,\s*-?\d+(?:\.\d+)?$/.test(query)) return null;
  return cleanTitle(query);
}

function metaContent(html: string, key: string): string | null {
  const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const patterns = [
    new RegExp(`<meta[^>]+property=["']${escapedKey}["'][^>]+content=["']([^"']+)["'][^>]*>`, "i"),
    new RegExp(`<meta[^>]+name=["']${escapedKey}["'][^>]+content=["']([^"']+)["'][^>]*>`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+property=["']${escapedKey}["'][^>]*>`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']+)["'][^>]+name=["']${escapedKey}["'][^>]*>`, "i"),
  ];

  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match?.[1]) return decodeHTML(match[1]);
  }
  return null;
}

function titleContent(html: string): string | null {
  const match = html.match(/<title[^>]*>([^<]+)<\/title>/i);
  return match?.[1] ? decodeHTML(match[1]) : null;
}

function cleanTitle(value: string): string {
  return decodeHTML(value)
    .replace(/\s[-|–—]\s.*$/, "")
    .replace(/\s+/g, " ")
    .trim();
}

function decodeHTML(value: string): string {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&apos;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">");
}

function inferredCategory(name: string): string {
  const lowered = name.toLowerCase();
  if (/(coffee|cafe|espresso|roaster|bakery)/.test(lowered)) return "coffee";
  if (/(park|playground|garden|plaza|beach|lake)/.test(lowered)) return "park";
  if (/(trail|hike|canyon|mountain|observatory)/.test(lowered)) return "hike";
  if (/(restaurant|noodle|pizza|taco|sushi|grill|kitchen|diner)/.test(lowered)) return "restaurant";
  if (/(bar|wine|brewery|cocktail|pub)/.test(lowered)) return "bar";
  return "place";
}

function noPlace(providerSteps: string[], errorCode: string, errorMessage: string): ExtractionResult {
  return {
    status: "no_place_found",
    candidates: [],
    confidence: 0,
    providerSteps,
    errorCode,
    errorMessage,
  };
}

function isGoogleMapsHost(hostname: string): boolean {
  const host = hostname.toLowerCase();
  return host === "google.com" || host.endsWith(".google.com");
}

function isAppleMapsHost(hostname: string): boolean {
  const host = hostname.toLowerCase();
  return host === "maps.apple.com";
}

function isShortMapHost(hostname: string): boolean {
  const host = hostname.toLowerCase();
  return host === "maps.app.goo.gl" || host === "goo.gl" || host === "g.co";
}

function firstNonEmpty(values: Array<string | null | undefined>): string | null {
  for (const value of values) {
    const trimmed = value?.trim();
    if (trimmed) return trimmed;
  }
  return null;
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

async function authenticatedRpc<T>(name: string, body: Record<string, unknown>, authorization: string): Promise<T> {
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("WANDER_SUPABASE_ANON_KEY");
  if (!anonKey) throw new Error("missing_anon_key");
  return await supabaseRpc<T>(name, body, anonKey, authorization);
}

async function serviceRpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const serviceKey = Deno.env.get("WANDER_SUPABASE_SERVICE_ROLE_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) throw new Error("missing_service_role_key");
  return await supabaseRpc<T>(name, body, serviceKey, `Bearer ${serviceKey}`);
}

async function supabaseRpc<T>(
  name: string,
  body: Record<string, unknown>,
  apiKey: string,
  authorization: string,
): Promise<T> {
  const supabaseURL = Deno.env.get("WANDER_SUPABASE_URL") ?? Deno.env.get("SUPABASE_URL");
  if (!supabaseURL) throw new Error("missing_supabase_url");

  const response = await fetch(`${supabaseURL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      ...jsonHeaders,
      apikey: apiKey,
      authorization,
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`rpc_${name}_failed:${response.status}:${await response.text()}`);
  }

  return await response.json() as T;
}
