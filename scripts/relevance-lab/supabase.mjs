import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import pg from "pg";

const { Client } = pg;
const currentDirectory = dirname(fileURLToPath(import.meta.url));
const defaultEnvPath = join(homedir(), ".openclaw", "workspace", ".env.keys");
const certificatePath = join(currentDirectory, "..", "certs", "prod-ca-2021.crt");

const allowedEnvironmentKeys = new Set([
  "WANDER_SUPABASE_DB_PASSWORD",
  "WANDER_SUPABASE_PROJECT_REF",
  "WANDER_SUPABASE_DB_URL",
]);

function unquote(value) {
  if (
    (value.startsWith('"') && value.endsWith('"'))
    || (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

export function loadLocalEnvironment(envPath = defaultEnvPath) {
  if (!existsSync(envPath)) return;
  const lines = readFileSync(envPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const match = line.match(/^\s*(?:export\s+)?([A-Z0-9_]+)=(.*)$/);
    if (!match || !allowedEnvironmentKeys.has(match[1]) || process.env[match[1]]) continue;
    process.env[match[1]] = unquote(match[2].trim());
  }
}

function databaseUrl() {
  if (process.env.WANDER_SUPABASE_DB_URL) return process.env.WANDER_SUPABASE_DB_URL;
  const password = process.env.WANDER_SUPABASE_DB_PASSWORD;
  const projectRef = process.env.WANDER_SUPABASE_PROJECT_REF;
  if (!password || !projectRef) {
    throw new Error(
      `Missing WANDER_SUPABASE_DB_PASSWORD or WANDER_SUPABASE_PROJECT_REF. Add them to ${defaultEnvPath}.`,
    );
  }
  return `postgresql://postgres:${encodeURIComponent(password)}@db.${projectRef}.supabase.co:5432/postgres`;
}

function assertSafeDatabaseUrl(value) {
  const parsed = new URL(value);
  if (parsed.protocol !== "postgresql:" && parsed.protocol !== "postgres:") {
    throw new Error("The evaluator only accepts a PostgreSQL connection URL.");
  }
  if (!parsed.hostname.endsWith(".supabase.co")) {
    throw new Error("The evaluator only connects to a Supabase host.");
  }
}

const setupSql = `
  create temporary table relevance_places (
    id text primary key,
    name text not null,
    category text not null,
    subcategory text not null,
    neighborhood text not null,
    city text not null,
    description text not null,
    tag_text text not null,
    owner_name text not null,
    price integer not null,
    open_tonight boolean not null,
    vegetarian_friendly boolean not null,
    group_friendly boolean not null,
    child_friendly boolean not null,
    embedding double precision[] not null,
    search_vector tsvector generated always as (
      setweight(to_tsvector('simple'::regconfig, coalesce(name, '')), 'A') ||
      setweight(to_tsvector('simple'::regconfig, coalesce(category, '') || ' ' || coalesce(subcategory, '')), 'B') ||
      setweight(to_tsvector('simple'::regconfig, coalesce(neighborhood, '') || ' ' || coalesce(city, '') || ' ' || coalesce(tag_text, '')), 'C') ||
      setweight(to_tsvector('simple'::regconfig, coalesce(description, '')), 'D')
    ) stored
  ) on commit drop;

  create index relevance_places_search_idx
    on relevance_places using gin (search_vector);
`;

const insertSql = `
  insert into relevance_places (
    id, name, category, subcategory, neighborhood, city, description,
    tag_text, owner_name, price, open_tonight, vegetarian_friendly,
    group_friendly, child_friendly, embedding
  )
  select
    record.id,
    record.name,
    record.category,
    record.subcategory,
    record.neighborhood,
    record.city,
    record.description,
    record.tag_text,
    record.owner_name,
    record.price,
    record.open_tonight,
    record.vegetarian_friendly,
    record.group_friendly,
    record.child_friendly,
    record.embedding
  from jsonb_to_recordset($1::jsonb) as record(
    id text,
    name text,
    category text,
    subcategory text,
    neighborhood text,
    city text,
    description text,
    tag_text text,
    owner_name text,
    price integer,
    open_tonight boolean,
    vegetarian_friendly boolean,
    group_friendly boolean,
    child_friendly boolean,
    embedding double precision[]
  );
`;

const searchSql = `
  with parsed_query as (
    select websearch_to_tsquery('simple'::regconfig, $1::text) as value
  )
  select
    place.id,
    ts_rank_cd(place.search_vector, parsed_query.value, 32) as score
  from relevance_places as place
  cross join parsed_query
  where place.search_vector @@ parsed_query.value
    and (cardinality($2::text[]) = 0 or place.category = any($2::text[]))
    and (cardinality($3::text[]) = 0 or place.neighborhood = any($3::text[]))
    and ($4::text is null or lower(place.owner_name) = lower($4::text))
    and ($5::integer is null or place.price <= $5::integer)
    and (not $6::boolean or place.open_tonight)
    and (not $7::boolean or place.vegetarian_friendly)
    and (not $8::boolean or place.group_friendly)
    and (not $9::boolean or place.child_friendly)
  order by score desc, place.id asc
  limit 12;
`;

const semanticSearchSql = `
  select
    place.id,
    coalesce(
      sum(component.place_value * component.query_value)
      / nullif(
        sqrt(sum(component.place_value * component.place_value))
        * sqrt(sum(component.query_value * component.query_value)),
        0
      ),
      0
    ) as score
  from relevance_places as place
  cross join lateral unnest(place.embedding, $1::double precision[])
    as component(place_value, query_value)
  where (cardinality($2::text[]) = 0 or place.category = any($2::text[]))
    and (cardinality($3::text[]) = 0 or place.neighborhood = any($3::text[]))
    and ($4::text is null or lower(place.owner_name) = lower($4::text))
    and ($5::integer is null or place.price <= $5::integer)
    and (not $6::boolean or place.open_tonight)
    and (not $7::boolean or place.vegetarian_friendly)
    and (not $8::boolean or place.group_friendly)
    and (not $9::boolean or place.child_friendly)
  group by place.id
  order by score desc, place.id asc
  limit 12;
`;

function databaseRows(places, placeEmbeddings) {
  return places.map((place) => ({
    id: place.id,
    name: place.name,
    category: place.category,
    subcategory: place.subcategory,
    neighborhood: place.neighborhood,
    city: place.city,
    description: place.description,
    tag_text: place.tags.join(" "),
    owner_name: place.owner,
    price: place.price,
    open_tonight: place.openTonight,
    vegetarian_friendly: place.vegetarianFriendly,
    group_friendly: place.groupFriendly,
    child_friendly: place.childFriendly,
    embedding: placeEmbeddings.get(place.id),
  }));
}

export async function withSupabaseProviders(
  places,
  placeEmbeddings,
  queryEmbeddings,
  task,
) {
  loadLocalEnvironment();
  const connectionString = databaseUrl();
  assertSafeDatabaseUrl(connectionString);
  const client = new Client({
    connectionString,
    ssl: existsSync(certificatePath)
      ? { ca: readFileSync(certificatePath, "utf8"), rejectUnauthorized: true }
      : { rejectUnauthorized: true },
    application_name: "recme_relevance_lab",
    connectionTimeoutMillis: 15_000,
    query_timeout: 10_000,
  });

  await client.connect();
  let transactionStarted = false;
  try {
    await client.query("begin");
    transactionStarted = true;
    await client.query(setupSql);
    await client.query(insertSql, [JSON.stringify(databaseRows(places, placeEmbeddings))]);

    const lexicalProvider = async (query) => {
      const plan = query.plan;
      const result = await client.query(searchSql, [
        plan.lexicalQuery,
        plan.categories,
        plan.neighborhoods,
        plan.owner,
        plan.maxPrice,
        plan.openTonight,
        plan.vegetarianFriendly,
        plan.groupFriendly,
        plan.childFriendly,
      ]);
      return result.rows.map((row) => ({ id: row.id, score: Number(row.score) }));
    };

    const semanticProvider = async (query) => {
      const plan = query.plan;
      const result = await client.query(semanticSearchSql, [
        queryEmbeddings.get(query.id),
        plan.categories,
        plan.neighborhoods,
        plan.owner,
        plan.maxPrice,
        plan.openTonight,
        plan.vegetarianFriendly,
        plan.groupFriendly,
        plan.childFriendly,
      ]);
      return result.rows.map((row) => ({ id: row.id, score: Number(row.score) }));
    };

    return await task({ lexicalProvider, semanticProvider });
  } finally {
    if (transactionStarted) {
      try {
        await client.query("rollback");
      } catch {
        // Closing the connection below still drops the temporary table.
      }
    }
    await client.end().catch(() => {});
  }
}
