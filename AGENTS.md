# Aura Workbench — Agent Instructions

## Project

`aura-workbench` is the primary Aura development workspace. It owns Docker Compose, the Dev Container entrypoint, and multi-repo mounts. It does **not** own engine product code or editor UI code.

## Services

| Service | Role |
|---------|------|
| `engine` | Cursor attach target. Engine build, clippy, and **engine test suite**. Lean Rust + ALSA image. |
| `editor` | Editor build, test, and run only (Rust + Iced GUI system deps). Derived from the engine image. **Not** for running engine tests. |

If the engine image later accumulates substantial deps the editor does not need, extract a shared base image instead of deriving editor from engine.

A dedicated **Windows cross-compile** container for shipping the editor to Windows users is planned later; it is not present yet.

## Mounted repositories

Expected container paths when attached to the **engine** service (`workspaceFolder` = `/workspaces/aura-workbench`):

| Path | Repo |
|------|------|
| `/workspaces/aura-workbench` | this repo |
| `.mnt/aura-engine` | `aura-engine` |
| `.mnt/aura-editor` | `aura-editor` |
| `.mnt/imp-rust` | `imp-rust` |
| `.mnt/imp-spec` | `imp-spec` |
| `.mnt/imp-ts` | `imp-ts` (read-only) |

Imp is also bind-mounted at `.mnt/aura-engine/.mnt/imp-*` so Cargo path deps inside the engine tree keep working.

Each mounted repo may have its own `AGENTS.md` and `docs/`. Prefer the nearest `AGENTS.md` and that repo’s `docs/` when working in a given tree.

## Commands (engine)

Run from `/workspaces/aura-workbench/.mnt/aura-engine` (engine service / default attach):

```bash
cargo build
cargo test
cargo clippy
./demos/render-all.sh
```

## Commands (editor)

Run **in the editor service**, from `/workspaces/aura-workbench/.mnt/aura-editor`:

```bash
cargo build
cargo test
cargo clippy
cargo run
```

From the attached engine context:

```bash
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec editor bash -lc 'cd /workspaces/aura-workbench/.mnt/aura-editor && cargo test'
```

## Image rebuild

Editor derives from `aura-workbench-engine:local`. Compose wires that with
`additional_contexts`, so a single build is safe (and what Dev Containers runs):

```bash
docker compose -f .devcontainer/docker-compose.yml build
```

## Commits

This workspace spans multiple git repositories. Plan and execute **one commit per affected repo**. Do not commit until the user explicitly asks.

## Naming

Repos and projects use **kebab-case** (`aura-engine`). Rust crates use **snake_case** (`aura_scheduler`).
