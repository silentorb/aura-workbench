#!/usr/bin/env bash
# Cross-compile experimental aura_editor_tauri for Windows (MSVC) and copy the
# portable release exe to /out. Frontend is built with Bun first; assets embed via
# tauri-build. Export I/O to flaky host mounts is time-bounded and falls back to
# the workbench .win-out when /out cannot be written promptly.
set -euo pipefail

OUT_DIR=/out
FALLBACK_OUT=/workspaces/aura-workbench/.win-out
TARGET=x86_64-pc-windows-msvc
EXE_NAME=aura-editor-tauri.exe
CARGO_EXE_NAME=aura_editor_tauri.exe
EDITOR_DIR=/workspaces/aura-workbench/.mnt/aura-editor
TAURI_APP="$EDITOR_DIR/apps/tauri"
# Bound flaky 9p/drvfs I/O so a wedged mount cannot hang the whole export.
COPY_TIMEOUT_SECS="${AURA_EDITOR_WIN_COPY_TIMEOUT_SECS:-20}"
IO_TIMEOUT_SECS="${AURA_EDITOR_WIN_IO_TIMEOUT_SECS:-5}"

io_ok() {
  timeout "$IO_TIMEOUT_SECS" "$@"
}

# Copy one file into dest_dir with a hard time bound. Returns 0 on success.
# Optional third arg overrides destination basename (for Cargo → export rename).
timed_cp_file() {
  local src="$1"
  local dest_dir="$2"
  local name="${3:-$(basename "$src")}"
  if ! timeout "$COPY_TIMEOUT_SECS" cp -f "$src" "$dest_dir/$name"; then
    return 1
  fi
  # Best-effort mtime refresh; ignore touch failures on odd mounts.
  io_ok touch "$dest_dir/$name" >/dev/null 2>&1 || true
  return 0
}

describe_file() {
  local path="$1"
  if ! io_ok stat -c '%y %s bytes' "$path" 2>/dev/null; then
    echo "(stat timed out or failed)"
  fi
}

export_exe() {
  local dest_root="$1"

  if ! io_ok test -d "$dest_root"; then
    echo "warning: cannot access $dest_root (I/O timeout or missing)" >&2
    return 1
  fi
  if ! io_ok test -w "$dest_root"; then
    echo "warning: $dest_root is not writable" >&2
    return 1
  fi

  if ! timed_cp_file "$SRC" "$dest_root" "$EXE_NAME"; then
    echo "warning: timed out or failed copying $EXE_NAME to $dest_root" >&2
    return 1
  fi
  echo "Wrote $dest_root/$EXE_NAME ($(describe_file "$dest_root/$EXE_NAME"))"
  return 0
}

if ! io_ok test -d "$OUT_DIR"; then
  echo "warning: $OUT_DIR is not mounted or not reachable within ${IO_TIMEOUT_SECS}s." >&2
  echo "warning: Set AURA_EDITOR_WIN_OUT in .devcontainer/.env; will try fallback $FALLBACK_OUT after build." >&2
  OUT_REACHABLE=0
else
  OUT_REACHABLE=1
fi

if [[ ! -d "$TAURI_APP" ]]; then
  echo "error: Tauri app not found: $TAURI_APP" >&2
  exit 1
fi

echo "Building Tauri frontend (Bun, TAURI_ENV_PLATFORM=windows)..."
cd "$TAURI_APP"
bun install
TAURI_ENV_PLATFORM=windows bun run build

cd "$EDITOR_DIR"

echo "Building aura_editor_tauri for $TARGET (release, custom-protocol)..."
# Bind mounts can leave mtimes/fingerprint stale across the docker-outside-of-docker
# hop; clean the package so this export always rebuilds Tauri host sources.
# custom-protocol is what `tauri build` enables so the WebView serves embedded
# frontendDist instead of build.devUrl (localhost:1420).
cargo clean -p aura_editor_tauri --release --target "$TARGET"
cargo xwin build -p aura_editor_tauri --release --target "$TARGET" --features custom-protocol

SRC="target/${TARGET}/release/${CARGO_EXE_NAME}"
if [[ ! -f "$SRC" ]]; then
  echo "error: expected binary not found: $SRC" >&2
  exit 1
fi

EXPORT_OK=0
if [[ "$OUT_REACHABLE" -eq 1 ]]; then
  if export_exe "$OUT_DIR"; then
    EXPORT_OK=1
  else
    echo "warning: primary export to $OUT_DIR failed; trying fallback $FALLBACK_OUT" >&2
  fi
fi

if [[ "$EXPORT_OK" -eq 0 ]]; then
  mkdir -p "$FALLBACK_OUT"
  if export_exe "$FALLBACK_OUT"; then
    EXPORT_OK=1
    echo "warning: exported to fallback $FALLBACK_OUT because $OUT_DIR was unreachable or flaky." >&2
    echo "warning: fix AURA_EDITOR_WIN_OUT (or close handles locking that path) and re-run to publish there." >&2
  fi
fi

if [[ "$EXPORT_OK" -eq 0 ]]; then
  echo "warning: build succeeded but export failed." >&2
  echo "warning: binary remains at $EDITOR_DIR/$SRC" >&2
  exit 0
fi
