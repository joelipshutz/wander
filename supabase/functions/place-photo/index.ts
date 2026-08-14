import "@supabase/functions-js/edge-runtime.d.ts";

import { handleRequest } from "./handler.ts";

Deno.serve(async (request) => {
  try {
    return await handleRequest(request);
  } catch (error) {
    console.error(
      "place_photo_error",
      error instanceof Error ? error.message : "unknown_error",
    );
    return Response.json({ error: "internal_error" }, {
      status: 500,
      headers: { "Cache-Control": "private, no-store, max-age=0" },
    });
  }
});
