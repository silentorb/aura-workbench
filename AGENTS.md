# Aura Workbench — Agent Instructions

## Project

`aura-workbench` is the primary Aura development workspace. It owns Docker Compose, the Dev Container entrypoint, and multi-repo mounts. It does **not** own engine product code or editor UI code.

## Services

| Service | Role |
|---------|------|
| `engine` | Cursor attach target. Engine build, clippy, and **engine test suite**. Lean Rust + ALSA image. Includes docker-outside-of-docker for host Docker CLI access. |
| `editor` | Editor build, test, and run only (Rust + Iced GUI system deps). Derived from the engine image. **Not** for running engine tests. |
| `editor-windows` | On-demand Windows MSVC cross-compile for the editor (`cargo-xwin`). Derived from the engine image. **Not** in `runServices`. |

If the engine image later accumulates substantial deps the editor does not need, extract a shared base image instead of deriving editor from engine.

## Mounted repositories

Expected container paths when attached to the **engine** service (`workspaceFolder` = `/workspaces/aura-workbench`):

| Path | Repo |
|------|------|
| `/workspaces/aura-workbench` | this repo |
| `.mnt/aura-engine` | `aura-engine` |
| `.mnt/aura-editor` | `aura-editor` |
| `.mnt/imp-rs` | `imp-rs` |
| `.mnt/imp-spec` | `imp-spec` |
| `.mnt/imp-ts` | `imp-ts` (read-only) |

Imp is also bind-mounted at `.mnt/aura-engine/.mnt/imp-*` so Cargo path deps inside the engine tree keep working.

Each mounted repo may have its own `AGENTS.md` and `docs/`. Prefer the nearest `AGENTS.md` and that repo’s `docs/` when working in a given tree.

## Cross-repo Rust agent docs

When changing agent docs (or linked style docs that agents are told to follow) with rules that are equally applicable to other **Rust** repos in this workspace (`aura-engine`, `aura-editor`, `imp-rs`), apply those changes across **all** of those repos in the same effort — via durable links (e.g. GitHub URLs) where practical, or mirrored wording where a reverse dependency would be wrong (e.g. Imp must not point at Aura for ownership). Do **not** hardcode co-located relative paths (`.mnt/…`, `../imp-*`, `../aura-*`); product repos should not assume sibling checkout layout. Prefer nearest-repo docs remaining the entry point; shared substance must still be reachable from each Rust repo’s `AGENTS.md` / `docs/rust-style.md`.

Rust repos in scope today: `aura-engine`, `aura-editor`, `imp-rs`. Not `imp-spec` / `imp-ts` (non-Rust) unless a change is language-neutral and separately warranted.

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

## Commands (editor Windows cross-compile)

On-demand `editor-windows` image (not started with the Dev Container). Output `.exe` is written to the host path in `AURA_EDITOR_WIN_OUT` (mounted at `/out`; see `.devcontainer/.env.example`).

The engine Dev Container includes **docker-outside-of-docker** so the Docker CLI can talk to the host daemon. After changing `devcontainer.json` features, rebuild/reopen the container.

From the attached engine context (or the VS Code / Cursor task **Build editor (Windows)**):

```bash
bash /workspaces/aura-workbench/scripts/run-editor-windows-build.sh
```

That wrapper builds `editor-windows` and runs the cross-compile with host bind mounts (nested `docker compose run` would pass container paths the host daemon cannot mount).

## Image rebuild

Editor and editor-windows derive from `aura-workbench-engine:local`. Compose wires that with
`additional_contexts`, so a single build is safe (and what Dev Containers runs for engine+editor):

```bash
docker compose -f .devcontainer/docker-compose.yml build
```

To build the Windows image only (pulls in engine via `additional_contexts`):

```bash
docker compose -f .devcontainer/docker-compose.yml build editor-windows
```

## Commits

This workspace spans multiple git repositories. Plan and execute **one commit per affected repo**. Do not commit until the user explicitly asks.

## Naming

Repos and projects use **kebab-case** (`aura-engine`). Rust crates use **snake_case** (`aura_scheduler`).
