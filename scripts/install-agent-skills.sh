#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GIT_COMMON_DIR="$(git -C "$ROOT_DIR" rev-parse --git-common-dir 2>/dev/null || true)"

if [[ -n "$GIT_COMMON_DIR" ]]; then
  if [[ "$GIT_COMMON_DIR" != /* ]]; then
    GIT_COMMON_DIR="$ROOT_DIR/$GIT_COMMON_DIR"
  fi
  CANONICAL_ROOT="$(cd "$(dirname "$GIT_COMMON_DIR")" && pwd)"
else
  CANONICAL_ROOT="$ROOT_DIR"
fi

# Keep indexed skills on the stable primary checkout, even when this installer
# is invoked from a short-lived worktree that will later be removed.
SOURCE_DIR="$CANONICAL_ROOT/agent-skills"
MODE="${1:-install}"

DESTINATIONS=(
  "$HOME/.codex/skills"
  "$HOME/.claude/skills"
  "$HOME/.openclaw/workspace/skills"
)

if [[ "$MODE" != "install" && "$MODE" != "--check" && "$MODE" != "check" ]]; then
  echo "usage: scripts/install-agent-skills.sh [install|--check]" >&2
  exit 2
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "missing source directory: $SOURCE_DIR" >&2
  exit 1
fi

created=0
present=0
missing=0
conflicts=0
repointed=0

for skill_dir in "$SOURCE_DIR"/*; do
  [[ -d "$skill_dir" ]] || continue
  [[ -f "$skill_dir/SKILL.md" ]] || continue

  skill_name="$(basename "$skill_dir")"

  for dest_root in "${DESTINATIONS[@]}"; do
    dest="$dest_root/$skill_name"

    if [[ "$MODE" == "--check" || "$MODE" == "check" ]]; then
      if [[ -L "$dest" && "$(readlink "$dest")" == "$skill_dir" ]]; then
        echo "ok: $dest -> $skill_dir"
        present=$((present + 1))
      elif [[ -L "$dest" ]]; then
        echo "stale: $dest -> $(readlink "$dest") (expected $skill_dir)"
        missing=$((missing + 1))
      elif [[ -e "$dest" ]]; then
        echo "conflict: $dest exists and is not the expected symlink"
        conflicts=$((conflicts + 1))
      else
        echo "missing: $dest"
        missing=$((missing + 1))
      fi
      continue
    fi

    mkdir -p "$dest_root"

    if [[ -L "$dest" && "$(readlink "$dest")" == "$skill_dir" ]]; then
      present=$((present + 1))
    elif [[ -L "$dest" ]]; then
      prior_target="$(readlink "$dest")"
      ln -sfn "$skill_dir" "$dest"
      echo "repointed: $dest ($prior_target -> $skill_dir)"
      repointed=$((repointed + 1))
    elif [[ -e "$dest" ]]; then
      echo "conflict: $dest exists and was left unchanged"
      conflicts=$((conflicts + 1))
    else
      ln -s "$skill_dir" "$dest"
      echo "created: $dest -> $skill_dir"
      created=$((created + 1))
    fi
  done
done

echo "summary: created=$created repointed=$repointed present=$present missing=$missing conflicts=$conflicts"

if [[ "$conflicts" -gt 0 || ( ( "$MODE" == "--check" || "$MODE" == "check" ) && "$missing" -gt 0 ) ]]; then
  exit 1
fi
