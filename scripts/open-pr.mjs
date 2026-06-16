#!/usr/bin/env node

import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";

function usage() {
  console.log(`Usage:
  node scripts/open-pr.mjs [options]

Options:
  --base <branch>       Target branch. Default: main.
  --title <title>       PR title. Defaults to the latest commit subject.
  --body <body>         PR body. Defaults to a concise generated summary.
  --body-file <path>    Read PR body from a file.
  --draft               Create the PR as a draft.
  --env <path>          Local env file with GITHUB_TOKEN or GH_TOKEN.
  --remote <name>       Git remote to push. Default: origin.
  --dry-run             Print the resolved plan without pushing or creating a PR.
  --help                Show this help.

Auth:
  Uses GitHub CLI if available. Otherwise uses GITHUB_TOKEN or GH_TOKEN from
  the shell, .env.local, .env.github, ~/.config/wander/github.env, or --env.
  Tokens need repo write permission for private repos.`);
}

function parseArgs(argv) {
  const options = {
    base: "main",
    body: null,
    bodyFile: null,
    draft: false,
    dryRun: false,
    envPath: null,
    remote: "origin",
    title: null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) throw new Error(`Missing value after ${arg}`);
      return argv[index];
    };

    switch (arg) {
      case "--base":
        options.base = next();
        break;
      case "--body":
        options.body = next();
        break;
      case "--body-file":
        options.bodyFile = next();
        break;
      case "--draft":
        options.draft = true;
        break;
      case "--env":
        options.envPath = next();
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--remote":
        options.remote = next();
        break;
      case "--title":
        options.title = next();
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  return options;
}

function git(args, options = {}) {
  return execFileSync("git", args, {
    encoding: "utf8",
    stdio: options.stdio ?? ["ignore", "pipe", "pipe"],
  }).trim();
}

function runGit(args, options = {}) {
  return spawnSync("git", args, {
    encoding: "utf8",
    stdio: options.stdio ?? ["ignore", "pipe", "pipe"],
  });
}

function resolveCommand(command, extraPaths = []) {
  const result = spawnSync("which", [command], { encoding: "utf8" });
  if (result.status === 0 && result.stdout.trim()) return result.stdout.trim();

  for (const path of extraPaths.map(expandHome)) {
    if (fs.existsSync(path)) return path;
  }

  return "";
}

function readFile(path) {
  return fs.readFileSync(path, "utf8").trim();
}

function expandHome(path) {
  if (!path.startsWith("~/")) return path;
  return `${process.env.HOME}${path.slice(1)}`;
}

function tokenFromEnvText(text) {
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const index = line.indexOf("=");
    const key = line.slice(0, index).trim();
    if (key !== "GITHUB_TOKEN" && key !== "GH_TOKEN") continue;

    let value = line.slice(index + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (value) return value;
  }

  return "";
}

function tokenFromEnvFiles(explicitPath) {
  const paths = explicitPath
    ? [explicitPath]
    : [".env.local", ".env.github", "~/.config/wander/github.env"];

  for (const path of paths.map(expandHome)) {
    if (!fs.existsSync(path)) continue;
    const token = tokenFromEnvText(fs.readFileSync(path, "utf8"));
    if (token) return { path, token };
  }

  return { path: null, token: "" };
}

function repoFromRemote(remoteUrl) {
  const ssh = remoteUrl.match(/^git@github\.com:(.+\/.+?)(?:\.git)?$/);
  if (ssh) return ssh[1];

  const https = remoteUrl.match(/^https:\/\/github\.com\/(.+\/.+?)(?:\.git)?$/);
  if (https) return https[1];

  throw new Error(`Cannot infer GitHub repo from remote URL: ${remoteUrl}`);
}

function assertCleanWorktree() {
  const status = git(["status", "--porcelain"]);
  if (status) {
    throw new Error(`Worktree has uncommitted changes. Commit or stash them before opening a PR:\n${status}`);
  }
}

function currentBranch() {
  const branch = git(["branch", "--show-current"]);
  if (!branch) throw new Error("Detached HEAD: create or switch to a branch before opening a PR.");
  if (branch === "main") throw new Error("Refusing to open a PR from main. Create a short-lived branch first.");
  return branch;
}

function pushWithGit(remote, branch) {
  const result = runGit(["push", "-u", remote, branch], { stdio: ["ignore", "inherit", "pipe"] });
  if (result.status === 0) return true;
  if (result.stderr) process.stderr.write(result.stderr);
  return false;
}

function pushWithToken(repo, branch, token) {
  const result = runGit(
    [
      "-c",
      `http.extraHeader=Authorization: Bearer ${token}`,
      "push",
      `https://github.com/${repo}.git`,
      `${branch}:${branch}`,
    ],
    { stdio: ["ignore", "inherit", "pipe"] },
  );
  if (result.status === 0) return true;
  if (result.stderr) process.stderr.write(result.stderr);
  return false;
}

async function githubRequest(repo, path, token, options = {}) {
  const response = await fetch(`https://api.github.com/repos/${repo}${path}`, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(options.headers ?? {}),
    },
  });
  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(`GitHub API ${response.status}: ${payload?.message ?? text}`);
  }
  return payload;
}

async function existingPr(repo, branch, token) {
  const [owner] = repo.split("/");
  const pulls = await githubRequest(
    repo,
    `/pulls?head=${encodeURIComponent(`${owner}:${branch}`)}&state=open`,
    token,
  );
  return pulls[0] ?? null;
}

async function createPrWithToken({ repo, branch, base, title, body, draft, token }) {
  const existing = await existingPr(repo, branch, token);
  if (existing) return existing;

  return githubRequest(repo, "/pulls", token, {
    method: "POST",
    body: JSON.stringify({
      base,
      body,
      draft,
      head: branch,
      maintainer_can_modify: true,
      title,
    }),
  });
}

function createPrWithGh({ ghPath, repo, branch, base, title, body, draft }) {
  const args = [
    "pr",
    "create",
    "--repo",
    repo,
    "--base",
    base,
    "--head",
    branch,
    "--title",
    title,
    "--body",
    body,
  ];
  if (draft) args.push("--draft");

  const result = spawnSync(ghPath, args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] });
  if (result.status !== 0) {
    const alreadyExists = `${result.stderr}\n${result.stdout}`.match(/pull request.*already exists/i);
    if (!alreadyExists) throw new Error(result.stderr || result.stdout || "gh pr create failed");

    const view = spawnSync(
      ghPath,
      ["pr", "view", branch, "--repo", repo, "--json", "url", "--jq", ".url"],
      { encoding: "utf8" },
    );
    if (view.status === 0 && view.stdout.trim()) return { html_url: view.stdout.trim() };
    throw new Error(result.stderr || result.stdout || "PR exists, but gh pr view failed");
  }

  return { html_url: result.stdout.trim() };
}

function authLabel({ hasGh, token, envFilePath }) {
  if (hasGh) return "gh";
  if (!token) return "missing";
  return envFilePath ? `token file (${envFilePath})` : "GITHUB_TOKEN/GH_TOKEN";
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    usage();
    return;
  }

  assertCleanWorktree();
  const branch = currentBranch();
  const remoteUrl = git(["remote", "get-url", options.remote]);
  const repo = repoFromRemote(remoteUrl);
  const title = options.title ?? git(["log", "-1", "--pretty=%s"]);
  const body = options.bodyFile
    ? readFile(options.bodyFile)
    : options.body ?? `Automated PR from \`${branch}\`.\n\nVerification: see \`docs/agent-log.md\`.`;
  const envFileToken = tokenFromEnvFiles(options.envPath);
  const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN || envFileToken.token;
  const ghPath = resolveCommand("gh", ["~/.local/bin/gh"]);
  const hasGh = Boolean(ghPath);

  console.log(`Branch: ${branch}`);
  console.log(`Repository: ${repo}`);
  console.log(`Base: ${options.base}`);
  console.log(`Title: ${title}`);
  console.log(`Auth: ${authLabel({ hasGh, token, envFilePath: envFileToken.path })}`);

  if (options.dryRun) return;

  if (!pushWithGit(options.remote, branch)) {
    if (!token) {
      throw new Error(
        "git push failed and no GITHUB_TOKEN/GH_TOKEN is set. Set a token with repo write permission or install/authenticate gh.",
      );
    }
    if (!pushWithToken(repo, branch, token)) {
      throw new Error("git push failed even with token-backed HTTPS push.");
    }
  }

  const pr = hasGh
    ? createPrWithGh({ ghPath, repo, branch, base: options.base, title, body, draft: options.draft })
    : await createPrWithToken({ repo, branch, base: options.base, title, body, draft: options.draft, token });

  console.log(`PR: ${pr.html_url}`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
