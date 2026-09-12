#!/usr/bin/env bash
# Cross-compile aura-editor for Windows (MSVC) and copy the release exe to /out.
set -euo pipefail

OUT_DIR=/out
TARGET=x86_64-pc-windows-msvc
EXE_NAME=aura-editor.exe
EDITOR_DIR=/workspaces/aura-workbench/.mnt/aura-editor

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
cargo xwin build --release --target "$TARGET"

SRC="target/${TARGET}/release/${EXE_NAME}"
if [[ ! -f "$SRC" ]]; then
  echo "error: expected binary not found: $SRC" >&2
  exit 1
fi

cp -f "$SRC" "$OUT_DIR/"
echo "Wrote $OUT_DIR/$EXE_NAME"
