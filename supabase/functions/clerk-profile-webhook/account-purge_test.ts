import { assertEquals, assertRejects } from "jsr:@std/assert";
import { purgeAccountStorage } from "./account-purge.ts";

Deno.test("purgeAccountStorage deletes every inventoried object with encoded path segments", async () => {
  const calls: string[] = [];
  const deleted = await purgeAccountStorage("user_a", "2026-07-13T20:00:00Z", async (path) => {
    calls.push(path);
    if (path.includes("account_storage_objects")) {
      return Response.json([
        { bucket_id: "profile-avatars", object_path: "user_a/avatar.jpg" },
        { bucket_id: "visit-photos", object_path: "user_a/visit id/photo.jpg" },
      ]);
    }
    return new Response(null, { status: 200 });
  });

  assertEquals(deleted, 2);
  assertEquals(calls[1], "/storage/v1/object/profile-avatars/user_a/avatar.jpg");
  assertEquals(calls[2], "/storage/v1/object/visit-photos/user_a/visit%20id/photo.jpg");
});

Deno.test("purgeAccountStorage stops the profile purge when object deletion fails", async () => {
  await assertRejects(
    () => purgeAccountStorage("user_a", "2026-07-13T20:00:00Z", async (path) => {
      if (path.includes("account_storage_objects")) {
        return Response.json([{ bucket_id: "visit-photos", object_path: "user_a/v/p.jpg" }]);
      }
      return new Response("no", { status: 500 });
    }),
    Error,
    "account_storage_delete_failed",
  );
});
