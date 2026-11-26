# Source from other scripts: source "$(dirname "${BASH_SOURCE[0]}")/lib/paths.sh"
# Sibling repos live next to this workbench on the host (../<repo>) and at
# /workspaces/<repo> inside Compose containers.
WORKBENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ -f /.dockerenv ]]; then
  DEV_ROOT="${DEV_ROOT:-/workspaces}"
else
  DEV_ROOT="${DEV_ROOT:-$(cd "${WORKBENCH_ROOT}/.." && pwd)}"
fi
CONTAINER_ROOT=/workspaces
COMPOSE_PROJECT="${COMPOSE_PROJECT:-aura-workbench_devcontainer}"
COMPOSE_FILE="${WORKBENCH_ROOT}/.devcontainer/docker-compose.yml"

AURA_ENGINE="${AURA_ENGINE:-${DEV_ROOT}/aura-engine}"
AURA_EDITOR="${AURA_EDITOR:-${DEV_ROOT}/aura-editor}"
IMP_RS="${IMP_RS:-${DEV_ROOT}/imp-rs}"
IMP_SPEC="${IMP_SPEC:-${DEV_ROOT}/imp-spec}"
IMP_LAB="${IMP_LAB:-${DEV_ROOT}/imp-lab}"
IMP_TS="${IMP_TS:-${DEV_ROOT}/imp-ts}"
IMP_GRAPH_VIEW="${IMP_GRAPH_VIEW:-${DEV_ROOT}/imp-graph-view}"
TOME_RUST_SERVER="${TOME_RUST_SERVER:-${DEV_ROOT}/tome-rust-server}"
MIR="${MIR:-${DEV_ROOT}/mir}"
