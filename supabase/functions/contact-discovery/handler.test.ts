import { handleRequest, type Dependencies } from "./handler.ts";
import { normalizeIdentifier, normalizedIdentifiers, verifiedIdentifiers } from "../_shared/contact-identifiers.ts";

function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}
const token = `header.${btoa(JSON.stringify({ sub: "user_clerk", iss: "https://clerk.getrec.me" }))}.signature`;
const request = (body: unknown, bearer = token) => new Request("https://example.test/contact-discovery", {
  method: "POST", headers: { Authorization: `Bearer ${bearer}` }, body: JSON.stringify(body),
});
function fixture(overrides: Record<string, unknown> = {}) {
  const calls: { endpoint: string; body: any; authorization: string | null }[] = [];
  const responses: Record<string, unknown> = {
    current_profile: { id: "user_canonical" }, own_contact_discovery_enabled: true,
    set_contact_discovery_enabled: true, admit_contact_discovery: true,
    sync_contact_discovery_identity: null, match_contact_discovery: [{ id: "user_friend" }],
    user_clerk: { id: "user_clerk", updated_at: 1790000000000, email_addresses: [
      { email_address: "Member@example.test", verification: { status: "verified" } },
      { email_address: "unverified@example.test", verification: { status: "unverified" } },
    ] }, ...overrides,
  };
  const deps: Dependencies = {
    env: key => ({ SUPABASE_URL: "https://rugmtlgufrhlxwfkumhw.supabase.co", SUPABASE_ANON_KEY: "test_anon",
      SUPABASE_SERVICE_ROLE_KEY: "test_service", ASTIR_FEEDBACK_CLERK_SECRET_KEY: "test_clerk" }[key]),
    fetch: ((url: string | URL | Request, init?: RequestInit) => {
      const endpoint = String(url).split("/").pop()!;
      calls.push({ endpoint, body: init?.body ? JSON.parse(String(init.body)) : null,
        authorization: new Headers(init?.headers).get("Authorization") });
      const value = responses[endpoint];
      if (value instanceof Response) return Promise.resolve(value);
      if (value instanceof Error) return Promise.reject(value);
      if (!(endpoint in responses)) throw new Error(`Unexpected endpoint ${endpoint}`);
      return Promise.resolve(Response.json(value));
    }) as typeof fetch,
  };
  return { deps, calls };
}

Deno.test("phone normalization is country-aware, exact, and rejects extensions", () => {
  equal(normalizeIdentifier({ kind: "phone", value: "(213) 373-4253" }, "US"), "phone:+12133734253");
  equal(normalizeIdentifier({ kind: "phone", value: "020 7946 0018" }, "GB"), "phone:+442079460018");
  equal(normalizeIdentifier({ kind: "phone", value: "+44 20 7946 0018" }, "US"), "phone:+442079460018");
  equal(normalizeIdentifier({ kind: "phone", value: "020 7946 0018" }), undefined);
  equal(normalizeIdentifier({ kind: "phone", value: "+1 213 373 4253 ext 12" }), undefined);
  equal(normalizeIdentifier({ kind: "phone", value: "call 2133734253 please" }, "US"), undefined);
  equal(normalizeIdentifier({ kind: "phone", value: "12345" }, "US"), undefined);
});
Deno.test("email matching preserves dots, plus tags and relay identities", () => {
  equal(normalizeIdentifier({ kind: "email", value: " Maya.Chen+home@Gmail.com " }), "email:maya.chen+home@gmail.com");
  equal(normalizeIdentifier({ kind: "email", value: "invalid @example.test" }), undefined);
  equal(normalizeIdentifier({ kind: "email", value: "relay@privaterelay.appleid.com" }), "email:relay@privaterelay.appleid.com");
});
Deno.test("all verified identifiers are indexed and duplicates collapse", () => {
  equal(verifiedIdentifiers({ id: "user_test", email_addresses: [
    { email_address: "one@example.test", verification: { status: "verified" } },
    { email_address: "ONE@example.test", verification: { status: "verified" } },
    { email_address: "two@example.test" },
  ], phone_numbers: [
    { phone_number: "+12133734253", verification: { status: "verified" } },
    { phone_number: "+442079460018", verification: { status: "verified" } },
    { phone_number: "+14155552671", verification: { status: "unverified" } },
  ] }), ["email:one@example.test", "phone:+12133734253", "phone:+442079460018"]);
  equal(normalizedIdentifiers([{ kind: "phone", value: "+12133734253" }, { kind: "phone", value: "213 373 4253" }], "US"), ["phone:+12133734253"]);
});
Deno.test("missing or rejected authentication never reaches private matching", async () => {
  const f = fixture({ current_profile: new Response("denied", { status: 401 }) });
  equal((await handleRequest(request({ action: "match", identifiers: [] }), f.deps)).status, 401);
  equal(f.calls.map(c => c.endpoint), ["current_profile"]);
  const missing = await handleRequest(new Request("https://example.test", { method: "POST", body: "{}" }), f.deps);
  equal(missing.status, 401);
});
Deno.test("authenticated canonical profile owns lookup, never client-supplied ID", async () => {
  const f = fixture();
  const response = await handleRequest(request({ action: "match", user_id: "attacker_selected", region: "US",
    identifiers: [{ kind: "phone", value: "(213) 373-4253" }] }), f.deps);
  equal(response.status, 200); equal(response.headers.get("Cache-Control"), "private, no-store");
  const call = f.calls.find(c => c.endpoint === "match_contact_discovery")!;
  equal(call.body, { input_viewer_id: "user_canonical", input_identifiers: ["phone:+12133734253"] });
  equal(call.authorization, "Bearer test_service");
  equal(f.calls.filter(c => c.endpoint === "user_clerk").length, 0);
});
Deno.test("consent is checked before rate admission and private matching", async () => {
  const f = fixture({ own_contact_discovery_enabled: false });
  equal((await handleRequest(request({ action: "match", identifiers: [] }), f.deps)).status, 403);
  equal(f.calls.map(c => c.endpoint), ["current_profile", "own_contact_discovery_enabled"]);
});
Deno.test("quota rejection prevents lookup", async () => {
  const f = fixture({ admit_contact_discovery: false });
  equal((await handleRequest(request({ action: "match", identifiers: [] }), f.deps)).status, 429);
  equal(f.calls.some(c => c.endpoint === "match_contact_discovery"), false);
});
Deno.test("enable gets only the signed-in member from Clerk and indexes only verified identifiers", async () => {
  const f = fixture();
  equal((await handleRequest(request({ action: "enable" }), f.deps)).status, 200);
  equal(f.calls.find(c => c.endpoint === "sync_contact_discovery_identity")?.body, {
    input_clerk_user_id: "user_clerk", input_user_id: "user_canonical",
    input_updated_at: new Date(1790000000000).toISOString(), input_identifiers: ["email:member@example.test"],
  });
});
Deno.test("Clerk failure cannot enable or register guessed identity", async () => {
  const f = fixture({ user_clerk: new Response("private details", { status: 503 }) });
  const response = await handleRequest(request({ action: "enable" }), f.deps);
  equal(response.status, 503); equal(await response.json(), { error: "unavailable" });
  equal(f.calls.some(c => c.endpoint === "sync_contact_discovery_identity"), false);
});
Deno.test("disable bypasses matching quotas and sends no contacts", async () => {
  const f = fixture({ set_contact_discovery_enabled: false });
  equal((await handleRequest(request({ action: "disable" }), f.deps)).status, 200);
  equal(f.calls.map(c => c.endpoint), ["current_profile", "set_contact_discovery_enabled"]);
  equal(f.calls[1].body, { input_enabled: false });
});
Deno.test("malformed, oversized and unsupported inputs fail before matching", async () => {
  for (const identifiers of [[{ kind: "name", value: "Friend" }], [{ kind: "email", value: 4 }], Array(5001).fill({ kind: "email", value: "a@b.test" })]) {
    const f = fixture(); equal((await handleRequest(request({ action: "match", identifiers }), f.deps)).status, 400);
    equal(f.calls.some(c => c.endpoint === "match_contact_discovery"), false);
  }
  const f = fixture(); equal((await handleRequest(request({ action: "match", ignored: "x".repeat(310000) }), f.deps)).status, 413);
});
Deno.test("wrong project or issuer cannot use the member index", async () => {
  const f = fixture(); const original = f.deps.env;
  f.deps.env = key => key === "SUPABASE_URL" ? "https://other.supabase.co" : original(key);
  equal((await handleRequest(request({ action: "enable" }), f.deps)).status, 503); equal(f.calls.length, 0);
  const g = fixture(); const wrong = `h.${btoa(JSON.stringify({ sub: "user_clerk", iss: "https://wrong.clerk.test" }))}.s`;
  equal((await handleRequest(request({ action: "enable" }, wrong), g.deps)).status, 401);
});
Deno.test("private service errors are never reflected in responses", async () => {
  const f = fixture({ match_contact_discovery: new Error("email:private@example.test secret") });
  const response = await handleRequest(request({ action: "match", identifiers: [] }), f.deps);
  equal(response.status, 503); equal(await response.json(), { error: "unavailable" });
});
