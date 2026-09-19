import { handleRequest } from "./handler.ts";
Deno.serve((request: Request) => handleRequest(request, { fetch, env: (key) => Deno.env.get(key) }));
