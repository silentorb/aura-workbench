# Aura Workbench

Primary development workspace for Aura. Opens as a Dev Container that starts two Compose services:

- **engine** — Rust toolchain + ALSA; Cursor attaches here; home for the **engine test suite**
- **editor** — derives from the engine image, adds Linux GUI deps for **Iced**; editor build/test/run only (not engine tests)

## Host layout

```text
~/dev/
  aura-workbench/   # this repo — open in Cursor
  aura-engine/
  aura-editor/
  imp-rs/
  imp-spec/
  imp-ts/
```

Inside the container, siblings appear under the workbench `.mnt/` tree:

```text
/workspaces/aura-workbench/
  .mnt/
    aura-engine/
    aura-editor/
    imp-rs/
    imp-spec/
    imp-ts/
```

## Quick start

1. Copy `.devcontainer/.env.example` to `.devcontainer/.env` if needed (local `.env` is gitignored).
2. Open this folder in Cursor.
3. Reopen in Container.

### Engine (default attach)

```bash
cd /workspaces/aura-workbench/.mnt/aura-engine
cargo build
cargo test
cargo clippy
./demos/render-all.sh
```

### Editor (editor service)

```bash
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec editor bash -lc 'cd /workspaces/aura-workbench/.mnt/aura-editor && cargo test'
```

### Rebuild images

Editor `FROM`s `aura-workbench-engine:local`. Compose declares that build dependency,
so one command is enough:

```bash
docker compose -f .devcontainer/docker-compose.yml build
```

## Paths

Compose reads host paths from `.devcontainer/.env`. Defaults point at sibling repos (`../../aura-engine`, etc.).

## Repos

| Repo | Role |
|------|------|
| `aura-workbench` | Orchestration (Compose, Dev Container) |
| `aura-engine` | Procedural music engine (Rust) |
| `aura-editor` | Editor UI (Rust / Iced) |

End users target Windows; daily development is WSL Linux containers. A dedicated Windows cross-compile container is planned later.

## License

MIT — see sibling product repos. Copyright (c) 2026 Silent Orb.
