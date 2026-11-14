#!/usr/bin/env bash
# Clean aura-editor's Cargo target/ when it exceeds a size cap.
# Oversized target/ from stale debug fingerprints is a defect, not expected.
#
# Usage:
#   bash scripts/clean-editor-target-if-large.sh [--dry-run]
#
# Env:
#   AURA_EDITOR_TARGET_MAX_GIB  Max allowed size in GiB before clean (default: 8)
#
# The editor Compose service runs as root; prefer cleaning inside that service
# so root-owned artifacts from editor builds are removable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=mnt-paths.sh
source "$SCRIPT_DIR/mnt-paths.sh"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $arg (try --dry-run)" >&2
      exit 2
      ;;
  esac
done

EDITOR_ROOT="${AURA_EDITOR}"
TARGET_DIR="${EDITOR_ROOT}/target"
MAX_GIB="${AURA_EDITOR_TARGET_MAX_GIB:-8}"
COMPOSE_FILE="${WORKBENCH_ROOT}/.devcontainer/docker-compose.yml"

if ! [[ "$MAX_GIB" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "error: AURA_EDITOR_TARGET_MAX_GIB must be a positive number (got: $MAX_GIB)" >&2
  exit 2
fi

if [[ ! -d "$EDITOR_ROOT" ]]; then
  echo "error: editor root not found: $EDITOR_ROOT" >&2
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "aura-editor target/: absent (nothing to clean)"
  exit 0
fi

# Bytes via du -sb; fall back to block estimate if -b unsupported.
if size_bytes="$(du -sb "$TARGET_DIR" 2>/dev/null | awk '{print $1}')"; then
  :
else
  size_kb="$(du -sk "$TARGET_DIR" | awk '{print $1}')"
  size_bytes=$((size_kb * 1024))
fi

# awk for float compare without bc dependency.
# Exit 0 from awk => over threshold; exit 1 => under (still prints GiB on stdout).
set +e
size_gib="$(awk -v bytes="$size_bytes" -v max_gib="$MAX_GIB" 'BEGIN {
  gib = bytes / (1024 * 1024 * 1024)
  printf "%.2f", gib
  exit (gib > max_gib + 0 ? 0 : 1)
}')"
is_over=$?
set -e

echo "aura-editor target/: ${size_gib} GiB (threshold ${MAX_GIB} GiB)"

if [[ "$is_over" -ne 0 ]]; then
  echo "under threshold; leaving target/ in place"
  exit 0
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run: would run 'cargo clean' in $EDITOR_ROOT"
  exit 0
fi

run_cargo_clean() {
  if command -v docker >/dev/null 2>&1 \
    && docker compose -f "$COMPOSE_FILE" ps --status running --services 2>/dev/null | grep -qx editor
  then
    echo "over threshold; running cargo clean via editor Compose service"
    docker compose -f "$COMPOSE_FILE" exec -T editor \
      bash -lc "cd /workspaces/aura-workbench/.mnt/aura-editor && cargo clean"
    return
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found on PATH and editor Compose service is not running" >&2
    exit 1
  fi

  echo "over threshold; running cargo clean in $EDITOR_ROOT"
  (
    cd "$EDITOR_ROOT"
    cargo clean
  )
}

if ! run_cargo_clean; then
  echo "error: cargo clean failed (often root-owned files from the editor service)." >&2
  echo "Retry with the editor service up, or remove target/ with sufficient privileges." >&2
  exit 1
fi

if [[ -d "$TARGET_DIR" ]]; then
  after_kb="$(du -sk "$TARGET_DIR" | awk '{print $1}')"
  after_gib="$(awk -v kb="$after_kb" 'BEGIN { printf "%.2f\n", kb / (1024 * 1024) }')"
  echo "aura-editor target/ after clean: ${after_gib} GiB"
else
  echo "aura-editor target/ after clean: absent"
fi
