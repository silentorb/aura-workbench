#!/usr/bin/env bash
# Build Imp Lab for Windows via the on-demand editor-windows service.
# Writes a portable imp-lab.exe plus the Aura pack to AURA_EDITOR_WIN_OUT (see
# .devcontainer/.env.example). Requires WebView2 on the Windows host (Edge).
#
# Host (default): compose resolves the relative sibling paths itself.
# Inside the Dev Container (docker-outside-of-docker): the host daemon cannot see
# container paths, so host paths are exported from LOCAL_WORKSPACE_FOLDER first.
set -euo pipefail
# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"

if [[ -f /.dockerenv ]]; then
  if [[ -z "${LOCAL_WORKSPACE_FOLDER:-}" ]]; then
    echo "error: LOCAL_WORKSPACE_FOLDER is unset (set by devcontainer.json remoteEnv)." >&2
    echo "Run this script on the WSL host instead." >&2
    exit 1
  fi
  host_dev_root="$(dirname "$LOCAL_WORKSPACE_FOLDER")"
  export WORKBENCH_PATH="$LOCAL_WORKSPACE_FOLDER"
  for pair in AURA_ENGINE:aura-engine AURA_EDITOR:aura-editor IMP_RS:imp-rs IMP_SPEC:imp-spec \
    IMP_LAB:imp-lab IMP_TS:imp-ts IMP_GRAPH_VIEW:imp-graph-view MIR:mir \
    TOME_RUST_SERVER:tome-rust-server SILENTORB_AGENTS:silentorb-agents; do
    export "${pair%%:*}_PATH=${host_dev_root}/${pair#*:}"
  done
  out="$(grep -E '^AURA_EDITOR_WIN_OUT=' "$WORKBENCH_ROOT/.devcontainer/.env" 2>/dev/null | tail -n1 | cut -d= -f2- || true)"
  case "$out" in
    /*) export AURA_EDITOR_WIN_OUT="$out" ;;
    *) export AURA_EDITOR_WIN_OUT="$LOCAL_WORKSPACE_FOLDER/.win-out" ;;
  esac
fi

mkdir -p "$WORKBENCH_ROOT/.win-out"
compose=(docker compose -p "$COMPOSE_PROJECT" -f "$COMPOSE_FILE")

echo "Building editor-windows image (cargo-xwin / MSVC + Bun)..."
"${compose[@]}" build editor-windows

echo "Running Imp Lab Windows cross-compile..."
"${compose[@]}" run --rm --no-deps -T editor-windows \
  bash /workspaces/aura-workbench/scripts/build-imp-lab-windows.sh

# Verifying a flaky host mount (e.g. /mnt/e) can hang; bound the check.
VERIFY_TIMEOUT_SECS="${AURA_EDITOR_WIN_VERIFY_TIMEOUT_SECS:-30}"
if ! timeout "$VERIFY_TIMEOUT_SECS" "${compose[@]}" run --rm --no-deps -T --entrypoint ls editor-windows \
  -l --full-time /out/imp-lab.exe; then
  echo "warning: could not list /out/imp-lab.exe within ${VERIFY_TIMEOUT_SECS}s" >&2
  echo "warning: build may have written a fallback under the workbench .win-out" >&2
fi
