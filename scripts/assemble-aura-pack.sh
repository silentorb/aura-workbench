#!/usr/bin/env bash
# Assemble the Aura pack for a local (Linux) Imp Lab run:
#   extensions.json           <- aura-editor/pack/extensions.json (pack configuration)
#   extensions/*.so           <- aura-engine cdylibs (catalogs, playback)
#   extensions/aura_editor.js <- aura-editor UI library (bun run build)
#   catalogs/                 <- aura-engine/lab-pack/catalogs
#   demo-project/             <- aura-engine/lab-pack/demo-project (never overwritten)
#
# Runs in the imp-lab service (Cargo + Bun); on the host it re-execs itself there.
# Then start Imp Lab with IMP_LAB_EXTENSIONS=<dest>/extensions.json.
#
# Usage: scripts/assemble-aura-pack.sh [dest] (default: <workbench>/.aura-pack)
set -euo pipefail
# shellcheck source=lib/paths.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"
if [[ ! -f /.dockerenv ]]; then
  exec "$WORKBENCH_ROOT/scripts/run" imp-lab bash /workspaces/aura-workbench/scripts/assemble-aura-pack.sh "$@"
fi

ENGINE_DIR="$AURA_ENGINE"
EDITOR_DIR="$AURA_EDITOR"
DEST="${1:-$WORKBENCH_ROOT/.aura-pack}"
ENGINE_TARGET_DIR="${CARGO_TARGET_DIR:-$ENGINE_DIR/target}"
PROFILE_DIR=debug

for dir in "$ENGINE_DIR" "$EDITOR_DIR"; do
  if [[ ! -d "$dir" ]]; then
    echo "error: $dir not found" >&2
    exit 1
  fi
done

echo "Building aura_imp_lab_catalogs + aura_imp_lab_playback cdylibs..."
(cd "$ENGINE_DIR" && cargo build -p aura_imp_lab_catalogs -p aura_imp_lab_playback)

echo "Building the aura-editor UI library..."
(cd "$EDITOR_DIR" && bun install && bun run build)

mkdir -p "$DEST/extensions" "$DEST/catalogs"
cp -f "$EDITOR_DIR/pack/extensions.json" "$DEST/extensions.json"
cp -f "$ENGINE_TARGET_DIR/$PROFILE_DIR/libaura_imp_lab_catalogs.so" "$DEST/extensions/"
cp -f "$ENGINE_TARGET_DIR/$PROFILE_DIR/libaura_imp_lab_playback.so" "$DEST/extensions/"
cp -f "$EDITOR_DIR/dist/aura_editor.js" "$DEST/extensions/"
cp -rf "$ENGINE_DIR/lab-pack/catalogs/." "$DEST/catalogs/"
if [[ -e "$DEST/demo-project" ]]; then
  echo "Kept existing $DEST/demo-project (delete it to copy the demo project again)"
else
  cp -r "$ENGINE_DIR/lab-pack/demo-project" "$DEST/demo-project"
fi

echo "Wrote the Aura pack to $DEST"
echo "Run Imp Lab with: IMP_LAB_EXTENSIONS=$DEST/extensions.json"
