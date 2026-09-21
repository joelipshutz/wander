import { parsePhoneNumberFromString, isSupportedCountry, type CountryCode } from "npm:libphonenumber-js@1.12.31/max";

export type ContactIdentifier = { kind: "phone" | "email"; value: string };
export type VerifiedContactUser = {
  id: string;
  updated_at?: number;
  email_addresses?: { email_address?: string; verification?: { status?: string } }[];
  phone_numbers?: { phone_number?: string; verification?: { status?: string } }[];
};

export function normalizeIdentifier(identifier: ContactIdentifier, region?: string): string | undefined {
  const value = identifier.value.trim();
  if (identifier.kind === "email") {
    // Exact address matching. Never strip +tags or Gmail dots or match an
    // Apple private relay address to an inferred real address.
    const email = value.toLowerCase();
    return email.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? `email:${email}` : undefined;
  }
  if (value.length > 80) return undefined;
  const country = region && isSupportedCountry(region) ? region as CountryCode : undefined;
  const phone = parsePhoneNumberFromString(value, { defaultCountry: country, extract: false });
  // Extensions identify a different endpoint, so do not collapse one onto the
  // owner's main number. Numbers without a known country stay unmatched.
  return phone?.isValid() && !phone.ext ? `phone:${phone.number}` : undefined;
}

export function normalizedIdentifiers(values: ContactIdentifier[], region?: string): string[] {
  return [...new Set(values.map(v => normalizeIdentifier(v, region)).filter((v): v is string => Boolean(v)))].sort();
}

export function verifiedIdentifiers(user: VerifiedContactUser): string[] {
  return normalizedIdentifiers([
    ...(user.email_addresses ?? []).filter(v => v.verification?.status === "verified" && typeof v.email_address === "string")
      .map(v => ({ kind: "email" as const, value: v.email_address! })),
    ...(user.phone_numbers ?? []).filter(v => v.verification?.status === "verified" && typeof v.phone_number === "string")
      .map(v => ({ kind: "phone" as const, value: v.phone_number! })),
  ]).slice(0, 100);
}
