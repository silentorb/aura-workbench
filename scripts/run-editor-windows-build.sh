#!/usr/bin/env bash
# Build aura-editor for Windows via the editor-windows image.
# Safe to run from the host or from the engine container (docker-outside-of-docker).
#
# Nested `docker compose run` would resolve bind mounts against container paths the
# host daemon cannot see. This script builds with compose, then `docker run`s with
# host paths derived from LOCAL_WORKSPACE_FOLDER + .devcontainer/.env.
set -euo pipefail

WORKSPACE_CONTAINER=/workspaces/aura-workbench
COMPOSE_FILE_CONTAINER="$WORKSPACE_CONTAINER/.devcontainer/docker-compose.yml"
ENV_FILE_CONTAINER="$WORKSPACE_CONTAINER/.devcontainer/.env"
IMAGE=aura-workbench-editor-windows:local
CONTAINER_SCRIPT=/workspaces/aura-workbench/scripts/build-editor-windows.sh

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker CLI not found." >&2
  echo "Rebuild/reopen the Dev Container so the docker-outside-of-docker feature is installed," >&2
  echo "or run this script on the host where Docker is available." >&2
  exit 1
fi

if [[ -z "${LOCAL_WORKSPACE_FOLDER:-}" ]]; then
  echo "error: LOCAL_WORKSPACE_FOLDER is unset." >&2
  echo "It should be injected via devcontainer.json remoteEnv (\${localWorkspaceFolder})" >&2
  echo "and tasks.json. Rebuild/reopen the Dev Container, or export it to the host workbench path." >&2
  exit 1
fi

# Resolve a .env path (possibly relative to .devcontainer/) against the host workbench root.
host_path_from_env() {
  local raw="$1"
  python3 -c "import os,sys; base=sys.argv[1]; p=sys.argv[2]; print(p if os.path.isabs(p) else os.path.normpath(os.path.join(base, '.devcontainer', p)))" \
    "$LOCAL_WORKSPACE_FOLDER" "$raw"
}

load_env() {
  local key="$1"
  local default="$2"
  if [[ -f "$ENV_FILE_CONTAINER" ]]; then
    local val
    val=$(python3 -c "
import re, sys
key, default, path = sys.argv[1], sys.argv[2], sys.argv[3]
val = default
with open(path, encoding='utf-8') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)=(.*)', line)
        if m and m.group(1) == key:
            val = m.group(2).strip().strip('\"').strip(\"'\")
print(val)
" "$key" "$default" "$ENV_FILE_CONTAINER")
    printf '%s' "$val"
  else
    printf '%s' "$default"
  fi
}

AURA_ENGINE_PATH=$(load_env AURA_ENGINE_PATH ../../aura-engine)
AURA_EDITOR_PATH=$(load_env AURA_EDITOR_PATH ../../aura-editor)
IMP_RS_PATH=$(load_env IMP_RS_PATH ../../imp-rs)
IMP_SPEC_PATH=$(load_env IMP_SPEC_PATH ../../imp-spec)
IMP_TS_PATH=$(load_env IMP_TS_PATH ../../imp-ts)
AURA_EDITOR_WIN_OUT=$(load_env AURA_EDITOR_WIN_OUT ../.win-out)

HOST_ENGINE=$(host_path_from_env "$AURA_ENGINE_PATH")
HOST_EDITOR=$(host_path_from_env "$AURA_EDITOR_PATH")
HOST_IMP_RS=$(host_path_from_env "$IMP_RS_PATH")
HOST_IMP_SPEC=$(host_path_from_env "$IMP_SPEC_PATH")
HOST_IMP_TS=$(host_path_from_env "$IMP_TS_PATH")
HOST_OUT=$(host_path_from_env "$AURA_EDITOR_WIN_OUT")

# Ensure default in-repo output dir exists on the workbench mount.
if [[ "$HOST_OUT" == "$LOCAL_WORKSPACE_FOLDER/.win-out" ]]; then
  mkdir -p "$WORKSPACE_CONTAINER/.win-out"
fi

echo "Building image $IMAGE (cargo-xwin / MSVC)..."
docker compose -f "$COMPOSE_FILE_CONTAINER" build editor-windows

echo "Running Windows cross-compile; host output -> $HOST_OUT"
docker run --rm \
  -v "$LOCAL_WORKSPACE_FOLDER:/workspaces/aura-workbench" \
  -v "$HOST_ENGINE:/workspaces/aura-workbench/.mnt/aura-engine" \
  -v "$HOST_EDITOR:/workspaces/aura-workbench/.mnt/aura-editor" \
  -v "$HOST_IMP_RS:/workspaces/aura-workbench/.mnt/imp-rs" \
  -v "$HOST_IMP_SPEC:/workspaces/aura-workbench/.mnt/imp-spec" \
  -v "$HOST_IMP_TS:/workspaces/aura-workbench/.mnt/imp-ts:ro" \
  -v "$HOST_IMP_RS:/workspaces/aura-workbench/.mnt/aura-engine/.mnt/imp-rs" \
  -v "$HOST_IMP_SPEC:/workspaces/aura-workbench/.mnt/aura-engine/.mnt/imp-spec" \
  -v "$HOST_IMP_TS:/workspaces/aura-workbench/.mnt/aura-engine/.mnt/imp-ts:ro" \
  -v "$HOST_OUT:/out" \
  -w /workspaces/aura-workbench/.mnt/aura-editor \
  "$IMAGE" \
  bash "$CONTAINER_SCRIPT"
