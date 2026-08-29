import { spawn } from "node:child_process";
import { chmod, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const allowedEnvironmentNames = [
  "DEVELOPER_DIR",
  "HOME",
  "LANG",
  "LC_ALL",
  "PATH",
  "SDKROOT",
  "TMPDIR",
];

export function credentialFreeSubprocessEnvironment(source = process.env) {
  const environment = {
    PATH: source.PATH ?? "/usr/bin:/bin:/usr/sbin:/sbin",
  };
  for (const name of allowedEnvironmentNames) {
    if (name === "PATH") continue;
    if (typeof source[name] === "string" && source[name]) environment[name] = source[name];
  }
  return environment;
}

export function runCredentialFreeProcess(command, args, {
  input = null,
  timeoutMs = 120_000,
} = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      env: credentialFreeSubprocessEnvironment(),
      stdio: ["pipe", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    let settled = false;
    const timeout = setTimeout(() => {
      if (settled) return;
      settled = true;
      child.kill("SIGTERM");
      reject(new Error(command + " timed out after " + timeoutMs + " ms"));
    }, timeoutMs);
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", (error) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      reject(error);
    });
    child.on("close", (code) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      const output = Buffer.concat(stdout).toString("utf8");
      const diagnostics = Buffer.concat(stderr).toString("utf8");
      if (code === 0) {
        resolve({ output, diagnostics });
      } else {
        reject(new Error(
          command + " exited " + code + (diagnostics ? ": " + diagnostics.slice(0, 4_000) : ""),
        ));
      }
    });
    child.stdin.end(input ?? undefined);
  });
}

export async function secureTemporaryToolDirectory(prefix) {
  const directory = await mkdtemp(join(tmpdir(), prefix));
  await chmod(directory, 0o700);
  return directory;
}
