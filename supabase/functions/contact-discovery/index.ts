import { handleRequest } from "./handler.ts";
Deno.serve(request => handleRequest(request, { fetch, env: key => Deno.env.get(key) }));
