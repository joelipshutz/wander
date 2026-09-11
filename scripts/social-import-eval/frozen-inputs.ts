import type { DiagnosticOperations } from "./production-parity.ts";

// Evaluation only: acquire each input once, then fail closed on any drift.
// Byte arrays are cloned because the production runner clears them after use.
export function frozenInputs(base: DiagnosticOperations) {
  let sealed = false;
  let totalBytes = 0;
  const media = new Map<
    string,
    Promise<Awaited<ReturnType<DiagnosticOperations["ingestAcquiredMedia"]>>>
  >();
  const aliases = new Map<
    string,
    Promise<
      Awaited<
        ReturnType<DiagnosticOperations["acquireInstagramProfileAliases"]>
      >
    >
  >();
  const evidence = new Map<string, string>();
  const hashes: { kind: string; sha256: string; byteCount: number }[] = [];
  const digest = async (bytes: Uint8Array) =>
    [
      ...new Uint8Array(
        await crypto.subtle.digest("SHA-256", new Uint8Array(bytes)),
      ),
    ].map((n) => n.toString(16).padStart(2, "0")).join("");
  const operations: DiagnosticOperations = {
    ...base,
    normalizeApifyDataset(items, source) {
      const result = base.normalizeApifyDataset(items, source);
      const key = JSON.stringify(source);
      const value = JSON.stringify(result);
      if (evidence.has(key) && evidence.get(key) !== value) {
        throw new Error("frozen_acquisition_drift");
      }
      if (!evidence.has(key) && sealed) {
        throw new Error("frozen_acquisition_missing");
      }
      evidence.set(key, value);
      return result;
    },
    async ingestAcquiredMedia(...args) {
      const key = JSON.stringify([args[0], args[1]]);
      if (!media.has(key)) {
        if (sealed) throw new Error("frozen_media_missing");
        media.set(
          key,
          (async () => {
            const rows = await base.ingestAcquiredMedia(...args);
            if (
              rows.length !== args[0].length ||
              rows.some((row) =>
                row.status !== "ok" || !row.bytes?.length ||
                row.byteCount !== row.bytes.length
              )
            ) throw new Error("frozen_media_incomplete");
            for (const row of rows) {
              totalBytes += row.bytes!.length;
              if (totalBytes > 256 * 1024 * 1024) {
                throw new Error("frozen_media_memory_limit");
              }
              hashes.push({
                kind: row.kind,
                sha256: await digest(row.bytes!),
                byteCount: row.bytes!.length,
              });
            }
            return structuredClone(rows);
          })(),
        );
      }
      return structuredClone(await media.get(key)!);
    },
    async acquireInstagramProfileAliases(...args) {
      const key = JSON.stringify(args[0]);
      if (!aliases.has(key)) {
        if (sealed) throw new Error("frozen_aliases_missing");
        aliases.set(
          key,
          (async () => {
            const rows = await base.acquireInstagramProfileAliases(...args);
            const bytes = new TextEncoder().encode(JSON.stringify(rows));
            hashes.push({
              kind: "profile_aliases",
              sha256: await digest(bytes),
              byteCount: bytes.length,
            });
            return structuredClone(rows);
          })(),
        );
      }
      return structuredClone(await aliases.get(key)!);
    },
  };
  return {
    operations,
    async seal() {
      // Close admission before awaiting work, so preparation cannot race sealing.
      sealed = true;
      await Promise.all([...media.values(), ...aliases.values()]);
      const acquisitionHashes = await Promise.all(
        [...evidence.values()].map(async (value) => {
          const bytes = new TextEncoder().encode(value);
          return {
            kind: "acquisition",
            sha256: await digest(bytes),
            byteCount: bytes.length,
          };
        }),
      );
      return {
        schemaVersion: 1,
        mediaByteCount: totalBytes,
        hashes: [...acquisitionHashes, ...structuredClone(hashes)],
      };
    },
  };
}
