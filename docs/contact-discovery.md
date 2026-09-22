# Contact-based friend discovery

REC-560 connects onboarding’s optional Find friends screen and Discover’s people suggestions. Matching does not follow anyone. A match appears first with “In your contacts”; the user presses Follow to create the normal social edge.

## Consent and data flow

A separate, explicit consent action is required even when iOS Contacts was previously granted for invitations. The consent text also explains being discoverable by verified email/phone. Consent is recorded per account on the server and per account/device locally. A grant on another device never permits reading this device’s contacts. Users can skip onboarding, keep using general suggestions and search, or turn matching off under Settings → Find friends from contacts.

The Contacts actor reads only permitted phone numbers and emails, including all values for contacts with multiple numbers. Full and limited access use Apple’s allowed contact subset. No names, organization, notes, photos, addresses or contact identifiers are sent. Inputs are held in memory, normalized in the authenticated Edge service and immediately matched; no address book, unmatched contact data or matched-contact graph is retained. Returned public profile shells use the app’s normal profile cache; their contact origin is not persisted.

Email normalization trims whitespace and lowercases, without stripping dots, plus tags or inferring real addresses from Apple relay addresses. Phone normalization uses pinned libphonenumber-js metadata, the device region for national numbers, and E.164 for exact matching. Ambiguous/invalid numbers and extensions are not matched. The request limit is 5,000 deduplicated identifiers; larger allowed subsets are rejected with instructions to select fewer contacts instead of silently truncating them.

Only verified Clerk account email/phone identifiers for opted-in members enter the server index, via a current user fetch when enabling and verified Clerk webhooks afterward. The database stores HMAC tokens with a database-private key, never a public identifier lookup table. Direct reads/writes of the index and matching RPCs are unavailable to clients. The Edge service first verifies the bearer token with PostgREST and derives the viewer’s canonical profile; a supplied viewer ID is never accepted. Matching is restricted to the fixed Astir production project and issuer.

Private, deleted, hidden, blocked (either direction), opted-out, self, and already-followed accounts are excluded. The normal follow-based recommendation path remains the fallback. Members without a matching verified email/phone, and members who have not enabled discovery, cannot be found through contacts. REC-571’s separate phone-entry design is not changed or treated as verified enrollment.

## Revocation and failure behavior

Turning matching off clears local consent immediately, drops in-flight results, removes the member identifier index on the server, and preserves existing follows. If offline, the account disable request is retried before further contact reads after reconnect/restart. Permission is checked before and after matching and on foreground refresh; selection changes are reflected on the next refresh. The server checks consent on every match and rejects stale identity updates. Soft/hard account deletion removes index and consent records.

Contact matching errors never block general follow suggestions or username search. No raw request bodies, identifiers, provider error messages or tokens are logged by the contact service. Requests are authenticated and limited by a rolling daily count and identifier budget; counters retain only counts and timing. Responses are private/no-store. No new user messages, invitations or follows are sent automatically.

## Validation and rollout

`supabase/tests/contact_discovery.sql` runs inside the standard hosted smoke runner using synthetic identities and rollback. It covers grants/RLS, consent isolation, matching/deduplication, exclusion rules, identity replacement/stale events, deletion and quotas. Edge tests cover verified-only extraction, phone/email normalization, auth/project boundaries, abuse bounds and response redaction. Native tests cover consent, denied/revoked/empty permissions, offline disable, account switching, late results, and ranking. UI tests exercise the real onboarding screens with explicit fictional fixture injection.

Apply `20260921070000_contact_discovery.sql`, deploy `contact-discovery` and `clerk-profile-webhook`, then run the normal hosted smoke and authenticated end-to-end probes. The contact Edge service uses the existing Astir production Clerk key under its historical `ASTIR_FEEDBACK_CLERK_SECRET_KEY` alias only to retrieve the signed-in member; contacts are never sent to Clerk. Record this additional consumer in the private credential registry.

Before a binary with REC-560 is distributed, reconcile the public privacy policy, privacy choices and App Review explanation with this explicit opt-in flow. The old local-only address-book statement describes invitations, not optional Find friends matching. App Store Contact Info and Contacts declarations already exist; recheck against the exact release candidate. Landing this change does not create or upload a TestFlight build.
