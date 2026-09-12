#!/usr/bin/env bash
# Push all writable mounted repos in dependency order (dependencies before dependents).
# Skips read-only mounts (imp-ts) and repos with no configured remote.
#
# Order rationale:
#   imp-spec      — language-neutral Imp specs
#   imp-rs        — Rust Imp implementation of those specs
#   aura-engine   — path-depends on imp-rs
#   aura-editor   — path-depends on imp-rs
#   aura-workbench — orchestration; no product path deps, pushed last
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Workbench-relative paths. imp-ts is omitted (:ro in Compose).
REPOS=(
  ".mnt/imp-spec"
  ".mnt/imp-rs"
  ".mnt/aura-engine"
  ".mnt/aura-editor"
  "."
)

repo_label() {
  local rel="$1"
  if [[ "$rel" == "." ]]; then
    printf '%s' "aura-workbench"
  else
    basename "$rel"
  fi
}

push_repo() {
  local rel="$1"
  local path="$ROOT/$rel"
  local name
  name=$(repo_label "$rel")

  if [[ ! -d "$path" ]]; then
    echo "skip  $name (missing: $path)"
    return 0
  fi

  if [[ ! -w "$path" ]]; then
    echo "skip  $name (not writable)"
    return 0
  fi

  if ! git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "skip  $name (not a git repo)"
    return 0
  fi

  if ! git -C "$path" remote get-url origin >/dev/null 2>&1; then
    echo "skip  $name (no origin remote)"
    return 0
  fi

  local branch
  branch=$(git -C "$path" rev-parse --abbrev-ref HEAD)
  if [[ "$branch" == "HEAD" ]]; then
    echo "error: $name is in detached HEAD; refuse to push" >&2
    return 1
  fi

  echo "push  $name ($branch)..."
  git -C "$path" push -u origin "HEAD:refs/heads/$branch"
  echo "ok    $name"
}

echo "Pushing writable mounted repos (dependency order)..."
for rel in "${REPOS[@]}"; do
  push_repo "$rel"
done
echo "Done."
