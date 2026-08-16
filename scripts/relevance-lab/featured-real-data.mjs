import { createHash } from "node:crypto";
import { allowedRealAttributeKeys } from "./real-data.mjs";
import { withReadOnlySupabase } from "./supabase.mjs";

const viewerQuery = `
  select
    profile.id,
    profile.handle,
    (select count(*)::integer from public.follows follow where follow.follower_user_id = profile.id) as following_count,
    (select count(*)::integer from public.user_places save where save.user_id = profile.id and save.deleted_at is null) as save_count,
    (select count(*)::integer from public.user_places save where save.user_id = profile.id and save.deleted_at is null and save.rating_score is not null) as rating_count
  from public.profiles profile
  where profile.search_handle = lower($1::text)
    and profile.deleted_at is null;
`;

const candidateRowsQuery = `
  with viewer as materialized (
    select profile.id
    from public.profiles profile
    where profile.search_handle = lower($1::text)
      and profile.deleted_at is null
  )
  select
    place.id::text as place_id,
    place.canonical_name,
    coalesce(place.primary_category, place.category, 'place') as category,
    coalesce(place.subcategory, '') as subcategory,
    coalesce(place.locality, '') as locality,
    coalesce(place.region, '') as region,
    coalesce(place.country, '') as country,
    place.latitude,
    place.longitude,
    coalesce(place.source_provider, '') as source_provider,
    coalesce(place.source_provider_place_id, '') as source_provider_place_id,
    save.user_id as contributor_id,
    save.user_id = viewer.id as is_self,
    app.can_read_user_place(viewer.id, save.user_id, save.visibility) as is_trusted,
    save.rating_score::double precision,
    greatest(0, extract(epoch from (now() - coalesce(save.visited_at, save.saved_at, save.updated_at))) / 86400)::integer as freshness_days,
    case
      when save.user_id = viewer.id then coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'question_key', attribute.question_key,
            'value_type', attribute.value_type,
            'value', attribute.value
          ) order by attribute.question_key
        )
        from public.place_attributes attribute
        where attribute.user_place_id = save.id
          and attribute.question_key = any($2::text[])
          and attribute.value_type <> 'text'
      ), '[]'::jsonb)
      else '[]'::jsonb
    end as trusted_attributes
  from viewer
  join public.user_places save
    on save.deleted_at is null
   and save.status = 'been'
  join public.profiles owner
    on owner.id = save.user_id
   and owner.deleted_at is null
  join public.places place on place.id = save.place_id
  where not app.is_blocked(viewer.id, save.user_id)
    and (
      app.can_read_user_place(viewer.id, save.user_id, save.visibility)
      or (
        save.visibility = 'followers'
        and not owner.is_private_profile
      )
    )
  order by place.id, save.user_id;
`;

const tasteRowsQuery = `
  with viewer as materialized (
    select profile.id
    from public.profiles profile
    where profile.search_handle = lower($1::text)
      and profile.deleted_at is null
  )
  select
    place.id::text as place_id,
    place.canonical_name,
    coalesce(save.category_override, place.primary_category, place.category, 'place') as category,
    coalesce(save.subcategory_override, place.subcategory, '') as subcategory,
    coalesce(place.locality, '') as locality,
    coalesce(place.region, '') as region,
    coalesce(place.country, '') as country,
    coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'question_key', attribute.question_key,
          'value_type', attribute.value_type,
          'value', attribute.value
        ) order by attribute.question_key
      )
      from public.place_attributes attribute
      where attribute.user_place_id = save.id
        and attribute.question_key = any($2::text[])
        and attribute.value_type <> 'text'
    ), '[]'::jsonb) as attributes
  from viewer
  join public.user_places save
    on save.user_id = viewer.id
   and save.deleted_at is null
  join public.places place on place.id = save.place_id
  where save.status = 'wanna_go'
     or coalesce(save.rating_score, 0) >= 4
  order by place.id;
`;

function humanize(value) {
  return String(value ?? "").replaceAll("_", " ").replace(/\s+/g, " ").trim();
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

function attributeTags(attributes) {
  return (attributes ?? [])
    .filter((attribute) => allowedRealAttributeKeys.includes(attribute.question_key))
    .flatMap((attribute) => flattenValue(attribute.value));
}

function opaqueContributorID(value) {
  return `contributor-${createHash("sha256").update(String(value)).digest("hex").slice(0, 12)}`;
}

function canonicalKey(row) {
  if (row.source_provider && row.source_provider_place_id) {
    return `${row.source_provider}:${row.source_provider_place_id}`.toLocaleLowerCase();
  }
  return [
    row.canonical_name,
    row.category,
    row.locality,
    Number(row.latitude).toFixed(4),
    Number(row.longitude).toFixed(4),
  ]
    .map((value) => String(value).toLocaleLowerCase().normalize("NFKD").replace(/[^a-z0-9.-]+/g, ""))
    .join("|");
}

export function sanitizeFeaturedRows(candidateRows) {
  const groups = new Map();
  for (const row of candidateRows) {
    const key = canonicalKey(row);
    const contributor = opaqueContributorID(row.contributor_id);
    const existing = groups.get(key) ?? {
      id: String(row.place_id),
      name: String(row.canonical_name),
      category: String(row.category),
      subcategory: humanize(row.subcategory),
      locality: String(row.locality),
      region: String(row.region),
      country: String(row.country),
      latitude: Number(row.latitude),
      longitude: Number(row.longitude),
      tags: new Set([humanize(row.category), humanize(row.subcategory)].filter(Boolean)),
      includesSelf: false,
      trustedContributorIds: new Set(),
      allContributorIds: new Set(),
      ratings: [],
      freshnessDays: Number.POSITIVE_INFINITY,
      status: "been",
      privacyEligible: true,
    };
    existing.includesSelf ||= Boolean(row.is_self);
    existing.allContributorIds.add(contributor);
    if (row.is_trusted && !row.is_self) existing.trustedContributorIds.add(contributor);
    if (row.is_self) {
      for (const tag of attributeTags(row.trusted_attributes)) existing.tags.add(tag);
    }
    if (row.rating_score != null) existing.ratings.push(Number(row.rating_score));
    existing.freshnessDays = Math.min(existing.freshnessDays, Number(row.freshness_days));
    groups.set(key, existing);
  }

  return [...groups.values()].map((group) => {
    const trustedContributorIds = [...group.trustedContributorIds].sort();
    return {
      id: group.id,
      name: group.name,
      category: group.category,
      subcategory: group.subcategory,
      locality: group.locality,
      region: group.region,
      country: group.country,
      latitude: group.latitude,
      longitude: group.longitude,
      tags: [...group.tags].sort().slice(0, 40),
      includesSelf: group.includesSelf,
      trustedContributorIds,
      primaryTrustedContributorId: trustedContributorIds[0] ?? null,
      communitySupport: group.allContributorIds.size,
      communityRating: group.ratings.length === 0
        ? null
        : group.ratings.reduce((sum, rating) => sum + rating, 0) / group.ratings.length,
      ratingCount: group.ratings.length,
      freshnessDays: Number.isFinite(group.freshnessDays) ? group.freshnessDays : 3650,
      status: group.status,
      privacyEligible: group.privacyEligible,
    };
  }).sort((left, right) => left.name.localeCompare(right.name) || left.id.localeCompare(right.id));
}

export function sanitizeTasteRows(tasteRows) {
  return tasteRows.map((row) => ({
    id: `taste:${row.place_id}`,
    name: String(row.canonical_name),
    category: String(row.category),
    subcategory: humanize(row.subcategory),
    neighborhood: String(row.locality),
    city: String(row.region),
    country: String(row.country),
    description: "",
    tags: [...new Set([
      humanize(row.category),
      humanize(row.subcategory),
      ...attributeTags(row.attributes),
    ].filter(Boolean))].slice(0, 40),
  }));
}

export async function loadFeaturedRealData(viewerHandle) {
  if (!viewerHandle || !String(viewerHandle).trim()) {
    throw new Error("Featured benchmark requires --viewer-handle or RECME_FEATURED_VIEWER_HANDLE.");
  }
  return withReadOnlySupabase(async (client) => {
    const viewerResult = await client.query(viewerQuery, [viewerHandle]);
    if (viewerResult.rows.length !== 1) {
      throw new Error(`Expected one active Featured viewer for handle ${viewerHandle}.`);
    }
    const candidateResult = await client.query(candidateRowsQuery, [viewerHandle, allowedRealAttributeKeys]);
    const tasteResult = await client.query(tasteRowsQuery, [viewerHandle, allowedRealAttributeKeys]);
    const candidates = sanitizeFeaturedRows(candidateResult.rows);
    const tastePlaces = sanitizeTasteRows(tasteResult.rows);
    return {
      candidates,
      tastePlaces,
      stats: {
        candidatePlaces: candidates.length,
        candidateSaves: candidateResult.rows.length,
        tastePlaces: tastePlaces.length,
        viewerSaves: Number(viewerResult.rows[0].save_count),
        viewerRatings: Number(viewerResult.rows[0].rating_count),
        following: Number(viewerResult.rows[0].following_count),
      },
    };
  });
}
