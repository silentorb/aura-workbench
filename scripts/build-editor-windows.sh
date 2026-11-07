#!/usr/bin/env bash
# Cross-compile aura-editor for Windows (MSVC) and copy the release exe + demos to /out.
set -euo pipefail

OUT_DIR=/out
TARGET=x86_64-pc-windows-msvc
EXE_NAME=aura-editor.exe
EDITOR_DIR=/workspaces/aura-workbench/.mnt/aura-editor
DEMOS_SRC=/workspaces/aura-workbench/.mnt/aura-engine/demos
DEMOS_DST="$OUT_DIR/demos"

if [[ ! -d "$OUT_DIR" ]]; then
  echo "error: $OUT_DIR is not mounted. Set AURA_EDITOR_WIN_OUT in .devcontainer/.env" >&2
  exit 1
fi
if [[ ! -w "$OUT_DIR" ]]; then
  echo "error: $OUT_DIR is not writable (check AURA_EDITOR_WIN_OUT host path permissions)" >&2
  exit 1
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

cp -f "$SRC" "$OUT_DIR/"
# Drop preserved/stale mtime so Explorer and `ls` show this export time.
touch "$OUT_DIR/$EXE_NAME"
echo "Wrote $OUT_DIR/$EXE_NAME ($(stat -c '%y %s bytes' "$OUT_DIR/$EXE_NAME"))"

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

mkdir -p "$DEMOS_DST"
# Refresh destination so removed demos do not linger from a prior export.
rm -f "$DEMOS_DST"/*.json
cp -f "${demo_json[@]}" "$DEMOS_DST/"
echo "Wrote ${#demo_json[@]} demo project(s) to $DEMOS_DST"
