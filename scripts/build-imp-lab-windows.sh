#!/usr/bin/env bash
# Cross-compile Imp Lab for Windows (MSVC) and copy the portable release exe
# to /out. Frontend is built with Bun first; assets embed via tauri-build.
# Export I/O to flaky host mounts is time-bounded and falls back to the
# workbench .win-out when /out cannot be written promptly.
set -euo pipefail

OUT_DIR=/out
FALLBACK_OUT=/workspaces/aura-workbench/.win-out
TARGET=x86_64-pc-windows-msvc
EXE_NAME=imp-lab.exe
CARGO_EXE_NAME=imp-lab.exe
LAB_DIR=/workspaces/aura-workbench/.mnt/imp-lab
ENGINE_DIR=/workspaces/aura-workbench/.mnt/aura-engine
TAURI_APP="$LAB_DIR/apps/tauri"
LAB_PACK_SRC="$ENGINE_DIR/lab-pack"
CATALOG_DLL_NAME=aura_imp_lab_catalogs.dll
PLAYBACK_DLL_NAME=aura_imp_lab_playback.dll
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

export_lab_pack() {
  local dest_root="$1"

  if [[ ! -f "$LAB_PACK_SRC/extensions.json" ]]; then
    echo "warning: Lab pack missing at $LAB_PACK_SRC (skipping extensions sidecar)" >&2
    return 0
  fi
  if [[ ! -f "$CATALOG_DLL_SRC" ]]; then
    echo "warning: Aura catalog dll missing at $CATALOG_DLL_SRC (skipping extensions sidecar)" >&2
    return 0
  fi

  if ! timed_cp_file "$LAB_PACK_SRC/extensions.json" "$dest_root"; then
    echo "warning: failed copying extensions.json to $dest_root" >&2
    return 1
  fi
  if ! io_ok mkdir -p "$dest_root/extensions" "$dest_root/catalogs"; then
    echo "warning: failed creating pack dirs under $dest_root" >&2
    return 1
  fi
  if ! timed_cp_file "$CATALOG_DLL_SRC" "$dest_root/extensions" "$CATALOG_DLL_NAME"; then
    echo "warning: failed copying $CATALOG_DLL_NAME to $dest_root/extensions" >&2
    return 1
  fi
  if [[ -n "$PLAYBACK_DLL_SRC" && -f "$PLAYBACK_DLL_SRC" ]]; then
    if ! timed_cp_file "$PLAYBACK_DLL_SRC" "$dest_root/extensions" "$PLAYBACK_DLL_NAME"; then
      echo "warning: failed copying $PLAYBACK_DLL_NAME to $dest_root/extensions" >&2
      return 1
    fi
  else
    echo "warning: Aura playback dll missing; Play menu will not load until rebuilt" >&2
  fi
  if [[ -f "$LAB_PACK_SRC/catalogs/instruments.json" ]]; then
    if ! timed_cp_file "$LAB_PACK_SRC/catalogs/instruments.json" "$dest_root/catalogs"; then
      echo "warning: failed copying instruments.json" >&2
      return 1
    fi
  fi
  echo "Wrote Lab pack under $dest_root (extensions.json + catalogs/playback dlls)"
  export_demo_project "$dest_root" || true
  return 0
}

# Sample Imp Lab project (a Tome data store of the Aura demos). Never overwrites an
# existing export: the user may have edited records in it.
export_demo_project() {
  local dest_root="$1"
  local src="$LAB_PACK_SRC/demo-project"
  local dest="$dest_root/demo-project"

  if [[ ! -f "$src/imp-project.json" ]]; then
    echo "warning: demo project missing at $src (skipping)" >&2
    return 0
  fi
  if io_ok test -e "$dest"; then
    echo "Kept existing $dest (delete it to re-export the demo project)"
    return 0
  fi
  if ! timeout "$COPY_TIMEOUT_SECS" cp -r "$src" "$dest"; then
    echo "warning: failed copying demo project to $dest" >&2
    return 1
  fi
  echo "Wrote demo project to $dest (File > Open Project..., pick imp-project.json)"
  return 0
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
  export_lab_pack "$dest_root" || true
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
  echo "error: Imp Lab app not found: $TAURI_APP" >&2
  exit 1
fi

echo "Building Imp Lab frontend (Bun, TAURI_ENV_PLATFORM=windows)..."
cd "$TAURI_APP"
bun install
TAURI_ENV_PLATFORM=windows bun run build

cd "$LAB_DIR"

echo "Building imp_lab for $TARGET (release, custom-protocol)..."
# Bind mounts can leave mtimes/fingerprint stale across the docker-outside-of-docker
# hop; clean the package so this export always rebuilds Imp Lab host sources.
# custom-protocol is what `tauri build` enables so the WebView serves embedded
# frontendDist instead of build.devUrl (localhost:1420).
cargo clean -p imp_lab --release --target "$TARGET"
cargo xwin build -p imp_lab --release --target "$TARGET" --features custom-protocol

SRC="$LAB_DIR/target/${TARGET}/release/${CARGO_EXE_NAME}"
if [[ ! -f "$SRC" ]]; then
  echo "error: expected binary not found: $SRC" >&2
  exit 1
fi

CATALOG_DLL_SRC=""
PLAYBACK_DLL_SRC=""
if [[ ! -d "$ENGINE_DIR" ]]; then
  echo "warning: aura-engine not found at $ENGINE_DIR; skipping Aura pack dlls" >&2
else
  echo "Building aura_imp_lab_catalogs + aura_imp_lab_playback cdylibs for $TARGET (release)..."
  if (cd "$ENGINE_DIR" && cargo xwin build -p aura_imp_lab_catalogs -p aura_imp_lab_playback --release --target "$TARGET"); then
    CATALOG_DLL_SRC="$ENGINE_DIR/target/${TARGET}/release/${CATALOG_DLL_NAME}"
    PLAYBACK_DLL_SRC="$ENGINE_DIR/target/${TARGET}/release/${PLAYBACK_DLL_NAME}"
    if [[ ! -f "$CATALOG_DLL_SRC" ]]; then
      echo "warning: expected dll not found: $CATALOG_DLL_SRC" >&2
      CATALOG_DLL_SRC=""
    fi
    if [[ ! -f "$PLAYBACK_DLL_SRC" ]]; then
      echo "warning: expected dll not found: $PLAYBACK_DLL_SRC" >&2
      PLAYBACK_DLL_SRC=""
    fi
  else
    echo "warning: Aura Lab pack Windows build failed; skipping pack dlls" >&2
    CATALOG_DLL_SRC=""
    PLAYBACK_DLL_SRC=""
  fi
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
  echo "warning: binary remains at $LAB_DIR/$SRC" >&2
  exit 0
fi
