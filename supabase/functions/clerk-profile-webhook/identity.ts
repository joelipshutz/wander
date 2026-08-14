export type ClerkIdentityPayload = {
  id: string;
  external_id?: string | null;
  public_metadata?: Record<string, unknown> | null;
};

type ServiceFetch = (path: string, init: RequestInit) => Promise<Response>;

type ClerkIdentityMapping = {
  profile_id?: string;
};

const canonicalUserIDMetadataKey = "canonical_user_id";

export function canonicalProfileIDFromPayload(user: ClerkIdentityPayload): string | undefined {
  return normalizedID(user.external_id)
    ?? normalizedID(user.public_metadata?.[canonicalUserIDMetadataKey]);
}

export async function resolveCanonicalProfileID(
  user: ClerkIdentityPayload,
  serviceFetch: ServiceFetch,
): Promise<string> {
  const payloadID = canonicalProfileIDFromPayload(user);
  if (payloadID) {
    return payloadID;
  }

  const response = await serviceFetch(
    `/rest/v1/clerk_identity_mappings?select=profile_id&clerk_user_id=eq.${encodeURIComponent(user.id)}&limit=1`,
    { method: "GET" },
  );
  if (!response.ok) {
    throw new Error(`clerk_identity_mapping_lookup_failed:${response.status}:${await response.text()}`);
  }

  const mappings = await response.json() as ClerkIdentityMapping[];
  const mappedID = normalizedID(mappings[0]?.profile_id);
  if (!mappedID) {
    // Failing closed preserves account data if a create/update webhook was
    // missed. A retry or manual repair is safer than deleting the wrong ID.
    throw new Error("clerk_identity_mapping_not_found");
  }
  return mappedID;
}

export async function registerClerkIdentityMapping(
  clerkUserID: string,
  profileID: string,
  serviceFetch: ServiceFetch,
): Promise<void> {
  const insertResponse = await serviceFetch(
    "/rest/v1/clerk_identity_mappings?on_conflict=clerk_user_id",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        // Identity ownership is immutable. Ignore an existing row here, then
        // read it back and fail closed if the requested profile differs.
        "Prefer": "resolution=ignore-duplicates,return=minimal",
      },
      body: JSON.stringify({ clerk_user_id: clerkUserID, profile_id: profileID }),
    },
  );
  if (!insertResponse.ok) {
    throw new Error(
      `clerk_identity_mapping_write_failed:${insertResponse.status}:${await insertResponse.text()}`,
    );
  }

  const verifyResponse = await serviceFetch(
    `/rest/v1/clerk_identity_mappings?select=profile_id&clerk_user_id=eq.${encodeURIComponent(clerkUserID)}&limit=1`,
    { method: "GET" },
  );
  if (!verifyResponse.ok) {
    throw new Error(
      `clerk_identity_mapping_verify_failed:${verifyResponse.status}:${await verifyResponse.text()}`,
    );
  }

  const mappings = await verifyResponse.json() as ClerkIdentityMapping[];
  if (normalizedID(mappings[0]?.profile_id) !== profileID) {
    throw new Error("clerk_identity_mapping_conflict");
  }
}

function normalizedID(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}
