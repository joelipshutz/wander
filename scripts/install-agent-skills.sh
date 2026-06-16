#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/agent-skills"
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
updated=0
present=0
missing=0
stale=0
conflicts=0

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
      elif [[ -L "$dest" && "$(readlink "$dest")" == */agent-skills/"$skill_name" ]]; then
        echo "stale: $dest -> $(readlink "$dest")"
        stale=$((stale + 1))
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
    elif [[ -L "$dest" && "$(readlink "$dest")" == */agent-skills/"$skill_name" ]]; then
      ln -sfn "$skill_dir" "$dest"
      echo "updated: $dest -> $skill_dir"
      updated=$((updated + 1))
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

echo "summary: created=$created updated=$updated present=$present missing=$missing stale=$stale conflicts=$conflicts"

if [[ "$conflicts" -gt 0 ]]; then
  exit 1
fi
