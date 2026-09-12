# Aura Workbench

Primary development workspace for Aura. Opens as a Dev Container that starts two Compose services:

- **engine** — Rust toolchain + ALSA; Cursor attaches here; home for the **engine test suite**
- **editor** — derives from the engine image, adds Linux GUI deps for **Iced**; editor build/test/run only (not engine tests)

An on-demand **editor-windows** service cross-compiles the editor for Windows (`x86_64-pc-windows-msvc` via cargo-xwin). It is not started with the Dev Container.

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

Editor and editor-windows `FROM` `aura-workbench-engine:local`. Compose declares that build dependency,
so one command is enough for the images Dev Containers builds by default:

```bash
docker compose -f .devcontainer/docker-compose.yml build
```

### Windows editor binary

Set `AURA_EDITOR_WIN_OUT` in `.devcontainer/.env` to a host directory for the output `.exe`
(default `../.win-out`). Point it at a Windows-visible path (e.g. `/mnt/d/AuraEditor`) to run
the binary from Windows Explorer.

The engine container uses **docker-outside-of-docker** so this works from the attached Dev Container
(rebuild/reopen after feature changes). Prefer the wrapper (or the **Build editor (Windows)** task)
over raw `docker compose run`, which would bind-mount container paths the host daemon cannot see:

```bash
bash /workspaces/aura-workbench/scripts/run-editor-windows-build.sh
```

## Paths

Compose reads host paths from `.devcontainer/.env`. Defaults point at sibling repos (`../../aura-engine`, etc.).
`AURA_EDITOR_WIN_OUT` controls where `aura-editor.exe` is written.

## Repos

| Repo | Role |
|------|------|
| `aura-workbench` | Orchestration (Compose, Dev Container) |
| `aura-engine` | Procedural music engine (Rust) |
| `aura-editor` | Editor UI (Rust / Iced) |

End users target Windows; daily development is WSL Linux containers. Use the on-demand **editor-windows** service to produce a Windows build.

## License

MIT — see sibling product repos. Copyright (c) 2026 Silent Orb.
