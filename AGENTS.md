# Aura Workbench — Agent Instructions

## Project

`aura-workbench` is the primary Aura development workspace. It owns Docker Compose, the Dev Container entrypoint, and multi-repo mounts. It does **not** own engine product code or editor UI code.

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

Run from `/workspaces/aura-workbench/.mnt/aura-engine`:

```bash
cargo build
cargo test
cargo clippy
./demos/render-all.sh
```

## Commits

This workspace spans multiple git repositories. Plan and execute **one commit per affected repo**. Do not commit until the user explicitly asks.

## Naming

Repos and projects use **kebab-case** (`aura-engine`). Rust crates use **snake_case** (`aura_scheduler`).
