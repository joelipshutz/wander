import { assertEquals, assertRejects } from "jsr:@std/assert";
import {
  canonicalProfileIDFromPayload,
  registerClerkIdentityMapping,
  resolveCanonicalProfileID,
} from "./identity.ts";

Deno.test("canonicalProfileIDFromPayload prefers Clerk external_id", () => {
  assertEquals(
    canonicalProfileIDFromPayload({
      id: "user_production",
      external_id: " user_original ",
      public_metadata: { canonical_user_id: "user_metadata" },
    }),
    "user_original",
  );
});

Deno.test("canonicalProfileIDFromPayload accepts protected public metadata", () => {
  assertEquals(
    canonicalProfileIDFromPayload({
      id: "user_production",
      public_metadata: { canonical_user_id: "user_original" },
    }),
    "user_original",
  );
});

Deno.test("resolveCanonicalProfileID uses the durable mapping for a sparse delete payload", async () => {
  const calls: string[] = [];
  const resolved = await resolveCanonicalProfileID(
    { id: "user_production" },
    async (path) => {
      calls.push(path);
      return Response.json([{ profile_id: "user_original" }]);
    },
  );

  assertEquals(resolved, "user_original");
  assertEquals(
    calls,
    ["/rest/v1/clerk_identity_mappings?select=profile_id&clerk_user_id=eq.user_production&limit=1"],
  );
});

Deno.test("resolveCanonicalProfileID fails closed when a delete mapping is missing", async () => {
  await assertRejects(
    () => resolveCanonicalProfileID(
      { id: "user_unmapped" },
      async () => Response.json([]),
    ),
    Error,
    "clerk_identity_mapping_not_found",
  );
});

Deno.test("registerClerkIdentityMapping upserts the Clerk-to-profile mapping", async () => {
  const requests: Array<{ path: string; init: RequestInit }> = [];
  await registerClerkIdentityMapping(
    "user_production",
    "user_original",
    async (path, init) => {
      requests.push({ path, init });
      return init.method === "POST"
        ? new Response(null, { status: 201 })
        : Response.json([{ profile_id: "user_original" }]);
    },
  );

  assertEquals(requests[0]?.path, "/rest/v1/clerk_identity_mappings?on_conflict=clerk_user_id");
  assertEquals(requests[0]?.init.method, "POST");
  assertEquals(
    new Headers(requests[0]?.init.headers).get("Prefer"),
    "resolution=ignore-duplicates,return=minimal",
  );
  assertEquals(
    JSON.parse(String(requests[0]?.init.body)),
    { clerk_user_id: "user_production", profile_id: "user_original" },
  );
  assertEquals(
    requests[1]?.path,
    "/rest/v1/clerk_identity_mappings?select=profile_id&clerk_user_id=eq.user_production&limit=1",
  );
  assertEquals(requests[1]?.init.method, "GET");
});

Deno.test("registerClerkIdentityMapping fails closed instead of remapping an account", async () => {
  await assertRejects(
    () => registerClerkIdentityMapping(
      "user_production",
      "user_original",
      async (_path, init) => init.method === "POST"
        ? new Response(null, { status: 201 })
        : Response.json([{ profile_id: "user_different" }]),
    ),
    Error,
    "clerk_identity_mapping_conflict",
  );
});
