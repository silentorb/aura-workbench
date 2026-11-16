#!/usr/bin/env bash
# Cross-compile aura-editor for Windows (MSVC) and copy the release exe + demos to /out.
# Export I/O to flaky host mounts (e.g. /mnt/e under WSL) is time-bounded and falls back
# to the workbench .win-out when /out cannot be written promptly.
set -euo pipefail

OUT_DIR=/out
FALLBACK_OUT=/workspaces/aura-workbench/.win-out
TARGET=x86_64-pc-windows-msvc
EXE_NAME=aura-editor.exe
EDITOR_DIR=/workspaces/aura-workbench/.mnt/aura-editor
DEMOS_SRC=/workspaces/aura-workbench/.mnt/aura-engine/demos
# Bound flaky 9p/drvfs I/O so a wedged mount cannot hang the whole export.
COPY_TIMEOUT_SECS="${AURA_EDITOR_WIN_COPY_TIMEOUT_SECS:-20}"
IO_TIMEOUT_SECS="${AURA_EDITOR_WIN_IO_TIMEOUT_SECS:-5}"

io_ok() {
  timeout "$IO_TIMEOUT_SECS" "$@"
}

# Copy one file into dest_dir with a hard time bound. Returns 0 on success.
timed_cp_file() {
  local src="$1"
  local dest_dir="$2"
  local name
  name=$(basename "$src")
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

export_tree() {
  local dest_root="$1"
  local demos_dst="$dest_root/demos"

  if ! io_ok test -d "$dest_root"; then
    echo "warning: cannot access $dest_root (I/O timeout or missing)" >&2
    return 1
  fi
  if ! io_ok test -w "$dest_root"; then
    echo "warning: $dest_root is not writable" >&2
    return 1
  fi

  if ! timed_cp_file "$SRC" "$dest_root"; then
    echo "warning: timed out or failed copying $EXE_NAME to $dest_root" >&2
    return 1
  fi
  echo "Wrote $dest_root/$EXE_NAME ($(describe_file "$dest_root/$EXE_NAME"))"

  if ! io_ok mkdir -p "$demos_dst"; then
    echo "warning: could not create $demos_dst" >&2
    return 1
  fi
  # Refresh destination so removed demos do not linger; tolerate I/O failures.
  io_ok bash -c "rm -f \"$demos_dst\"/*.json" >/dev/null 2>&1 || true
  if ! timeout "$COPY_TIMEOUT_SECS" cp -f "${demo_json[@]}" "$demos_dst/"; then
    echo "warning: timed out or failed copying demos to $demos_dst" >&2
    return 1
  fi
  echo "Wrote ${#demo_json[@]} demo project(s) to $demos_dst"
  return 0
}

if ! io_ok test -d "$OUT_DIR"; then
  echo "warning: $OUT_DIR is not mounted or not reachable within ${IO_TIMEOUT_SECS}s." >&2
  echo "warning: Set AURA_EDITOR_WIN_OUT in .devcontainer/.env; will try fallback $FALLBACK_OUT after build." >&2
  OUT_REACHABLE=0
else
  OUT_REACHABLE=1
fi

cd "$EDITOR_DIR"

echo "Building aura-editor for $TARGET (release)..."
# Bind mounts can leave mtimes/fingerprint stale across the docker-outside-of-docker
# hop; clean the package so this export always rebuilds editor sources.
cargo clean -p aura_editor --release --target "$TARGET"
cargo xwin build --release --target "$TARGET"

SRC="target/${TARGET}/release/${EXE_NAME}"
if [[ ! -f "$SRC" ]]; then
  echo "error: expected binary not found: $SRC" >&2
  exit 1
fi

if [[ ! -d "$DEMOS_SRC" ]]; then
  echo "error: demo projects not found: $DEMOS_SRC" >&2
  exit 1
fi

shopt -s nullglob
demo_json=("$DEMOS_SRC"/*.json)
if (( ${#demo_json[@]} == 0 )); then
  echo "error: no demo JSON files in $DEMOS_SRC" >&2
  exit 1
fi

EXPORT_OK=0
if [[ "$OUT_REACHABLE" -eq 1 ]]; then
  if export_tree "$OUT_DIR"; then
    EXPORT_OK=1
  else
    echo "warning: primary export to $OUT_DIR failed; trying fallback $FALLBACK_OUT" >&2
  fi
fi

if [[ "$EXPORT_OK" -eq 0 ]]; then
  mkdir -p "$FALLBACK_OUT"
  if export_tree "$FALLBACK_OUT"; then
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
