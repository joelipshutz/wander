import { withReadOnlySupabase } from "./supabase.mjs";

export const allowedRealAttributeKeys = [
  "bar_tags",
  "best_for",
  "coffee_tags",
  "hike_tags",
  "occasion",
  "park_tags",
  "place_tags",
  "price",
  "restaurant_cuisine",
  "restaurant_tags",
  "restaurants_food_tags",
  "stays_tags",
  "strenuousness",
  "work_setup",
];

const query = (id, text, intent, plan = {}) => ({
  id,
  text,
  intent,
  relevant: {},
  plan: {
    lexicalQuery: text,
    categories: [],
    neighborhoods: [],
    owner: null,
    maxPrice: null,
    openTonight: false,
    vegetarianFriendly: false,
    groupFriendly: false,
    childFriendly: false,
    personalization: 0,
    community: 0.45,
    ...plan,
  },
});

export const realQueries = [
  query("real-q01", "coffee shop in Santa Monica", "lexical", {
    lexicalQuery: "coffee OR cafe",
    categories: ["coffee_tea_sweets"],
    neighborhoods: ["Santa Monica"],
  }),
  query("real-q02", "date-night restaurant in Los Angeles", "semantic", {
    lexicalQuery: "date night",
    categories: ["restaurants_food"],
    neighborhoods: ["Los Angeles"],
  }),
  query("real-q03", "quiet coffee shop where I can work", "semantic", {
    lexicalQuery: "quiet work",
    categories: ["coffee_tea_sweets"],
  }),
  query("real-q04", "cocktails in West Hollywood", "constraint", {
    lexicalQuery: "cocktail",
    categories: ["bars_nightlife"],
    neighborhoods: ["West Hollywood"],
  }),
  query("real-q05", "outdoor drinks in Santa Monica", "semantic", {
    lexicalQuery: "outdoor drinks",
    categories: ["bars_nightlife"],
    neighborhoods: ["Santa Monica"],
  }),
  query("real-q06", "bakery or dessert worth a trip", "semantic", {
    lexicalQuery: "bakery OR dessert",
    categories: ["coffee_tea_sweets"],
  }),
  query("real-q07", "special-occasion restaurant in Los Angeles", "semantic", {
    lexicalQuery: "special occasion",
    categories: ["restaurants_food"],
    neighborhoods: ["Los Angeles"],
  }),
  query("real-q08", "healthy lunch in Santa Monica", "semantic", {
    lexicalQuery: "healthy lunch",
    categories: ["restaurants_food"],
    neighborhoods: ["Santa Monica"],
  }),
  query("real-q09", "casual group dinner in Los Angeles", "semantic", {
    lexicalQuery: "casual group",
    categories: ["restaurants_food"],
    neighborhoods: ["Los Angeles"],
  }),
  query("real-q10", "hike or nature escape", "semantic", {
    lexicalQuery: "hike OR hiking OR nature",
    categories: ["outdoors_nature"],
  }),
  query("real-q11", "the community's favorite restaurant in Santa Monica", "community", {
    lexicalQuery: "restaurant",
    categories: ["restaurants_food"],
    neighborhoods: ["Santa Monica"],
    community: 0.9,
  }),
  query("real-q12", "cozy coffee or tea for a rainy afternoon", "semantic", {
    lexicalQuery: "cozy",
    categories: ["coffee_tea_sweets"],
  }),
];

const placeQuery = `
  with active_saves as (
    select *
    from public.user_places
    where deleted_at is null
  ), allowed_attributes as (
    select
      user_place.place_id,
      jsonb_agg(
        jsonb_build_object(
          'question_key', attribute.question_key,
          'value_type', attribute.value_type,
          'value', attribute.value
        ) order by attribute.question_key
      ) as attributes
    from public.place_attributes as attribute
    join active_saves as user_place on user_place.id = attribute.user_place_id
    where attribute.question_key = any($1::text[])
      and attribute.value_type <> 'text'
    group by user_place.place_id
  )
  select
    place.id::text,
    place.canonical_name,
    coalesce(place.primary_category, place.category, 'place') as category,
    coalesce(place.subcategory, '') as subcategory,
    coalesce(place.locality, '') as locality,
    coalesce(place.region, '') as region,
    coalesce(place.country, '') as country,
    count(distinct save.user_id)::integer as community_support,
    count(*) filter (where save.status = 'been')::integer as been_count,
    count(*) filter (where save.status = 'wanna_go')::integer as wanna_count,
    count(save.rating_score)::integer as rating_count,
    round(avg(save.rating_score)::numeric, 2)::double precision as community_rating,
    greatest(0, extract(epoch from (now() - max(save.updated_at))) / 86400)::integer as freshness_days,
    coalesce(attribute_rollup.attributes, '[]'::jsonb) as attributes
  from public.places as place
  join active_saves as save on save.place_id = place.id
  left join allowed_attributes as attribute_rollup on attribute_rollup.place_id = place.id
  group by
    place.id,
    place.canonical_name,
    place.primary_category,
    place.category,
    place.subcategory,
    place.locality,
    place.region,
    place.country,
    attribute_rollup.attributes
  order by place.canonical_name, place.id;
`;

const statsQuery = `
  select
    (select count(*)::integer from public.places) as total_places,
    (select count(*)::integer from public.user_places where deleted_at is null) as active_saves,
    (select count(*)::integer from public.user_places where deleted_at is null and rating_score is not null) as rated_saves,
    (select count(*)::integer from public.place_attributes) as attributes,
    (select count(*)::integer from public.profiles where deleted_at is null) as active_profiles,
    (
      select count(*)::integer
      from (
        select user_id
        from public.user_places
        where deleted_at is null and rating_score is not null
        group by user_id
        having count(*) >= 5
      ) eligible_profiles
    ) as profiles_with_5_ratings;
`;

function humanize(value) {
  return String(value ?? "")
    .replaceAll("_", " ")
    .replace(/\s+/g, " ")
    .trim();
}

function safeString(value) {
  if (typeof value !== "string") return null;
  const cleaned = humanize(value);
  if (
    cleaned.length === 0
    || cleaned.length > 80
    || /https?:\/\//i.test(cleaned)
    || /\S+@\S+/.test(cleaned)
  ) return null;
  return cleaned;
}

function flattenValue(value, output = []) {
  if (typeof value === "string") {
    const cleaned = safeString(value);
    if (cleaned) output.push(cleaned);
  } else if (Array.isArray(value)) {
    for (const item of value) flattenValue(item, output);
  } else if (value && typeof value === "object") {
    for (const item of Object.values(value)) flattenValue(item, output);
  }
  return output;
}

export function sanitizeRealPlaceRow(row) {
  const attributeTags = (row.attributes ?? [])
    .filter((attribute) => allowedRealAttributeKeys.includes(attribute.question_key))
    .flatMap((attribute) => flattenValue(attribute.value));
  const tags = [...new Set([
    humanize(row.category),
    humanize(row.subcategory),
    ...attributeTags,
  ].filter(Boolean))].slice(0, 40);
  const communityRating = row.community_rating === null
    ? 3
    : Number(row.community_rating);

  return {
    id: String(row.id),
    name: String(row.canonical_name),
    category: String(row.category),
    subcategory: humanize(row.subcategory),
    neighborhood: String(row.locality),
    city: String(row.region),
    country: String(row.country),
    description: "",
    tags,
    owner: "Community",
    relationship: "community",
    status: Number(row.been_count) > 0 ? "been" : "wanna_go",
    rating: communityRating,
    visits: Number(row.been_count),
    communityRating,
    communitySupport: Number(row.community_support),
    ratingCount: Number(row.rating_count),
    distanceKm: 0,
    freshnessDays: Number(row.freshness_days),
    price: 2,
    openTonight: true,
    vegetarianFriendly: false,
    groupFriendly: false,
    childFriendly: false,
  };
}

function canonicalPlaceKey(place) {
  return [place.name, place.category, place.neighborhood, place.city]
    .map((value) => value.toLocaleLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, ""))
    .join("|");
}

export function deduplicateRealPlaces(places) {
  const grouped = new Map();
  for (const place of places) {
    const key = canonicalPlaceKey(place);
    const existing = grouped.get(key);
    if (!existing) {
      grouped.set(key, { ...place, tags: [...place.tags] });
      continue;
    }

    const ratingCount = existing.ratingCount + place.ratingCount;
    const weightedRating = ratingCount === 0
      ? 3
      : (
        existing.communityRating * existing.ratingCount
        + place.communityRating * place.ratingCount
      ) / ratingCount;
    grouped.set(key, {
      ...existing,
      id: [existing.id, place.id].sort()[0],
      tags: [...new Set([...existing.tags, ...place.tags])].slice(0, 40),
      status: existing.status === "been" || place.status === "been" ? "been" : "wanna_go",
      rating: weightedRating,
      communityRating: weightedRating,
      communitySupport: existing.communitySupport + place.communitySupport,
      ratingCount,
      visits: existing.visits + place.visits,
      freshnessDays: Math.min(existing.freshnessDays, place.freshnessDays),
    });
  }
  return [...grouped.values()].sort(
    (left, right) => left.name.localeCompare(right.name) || left.id.localeCompare(right.id),
  );
}

export async function loadSanitizedRealCorpus() {
  return withReadOnlySupabase(async (client) => {
    const [placeResult, statsResult] = await Promise.all([
      client.query(placeQuery, [allowedRealAttributeKeys]),
      client.query(statsQuery),
    ]);
    return {
      places: deduplicateRealPlaces(placeResult.rows.map(sanitizeRealPlaceRow)),
      stats: statsResult.rows[0],
    };
  });
}
