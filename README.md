# Aura Workbench

Primary development workspace for Aura. Opens as a Dev Container that starts two Compose services:

- **engine** — Rust toolchain; mounts siblings under `.mnt/`
- **editor** — Node toolchain; same `.mnt/` layout

## Host layout

```text
~/dev/
  aura-workbench/   # this repo — open in Cursor
  aura-engine/
  aura-editor/
  imp-rust/
  imp-spec/
  imp-ts/
```

Inside the container, siblings appear under the workbench `.mnt/` tree:

```text
/workspaces/aura-workbench/
  .mnt/
    aura-engine/
    aura-editor/
    imp-rust/
    imp-spec/
    imp-ts/
```

## Quick start

1. Copy `.devcontainer/.env.example` to `.devcontainer/.env` if needed (local `.env` is gitignored).
2. Open this folder in Cursor.
3. Reopen in Container.

In the engine service:

```bash
cd /workspaces/aura-workbench/.mnt/aura-engine
cargo build
cargo test
cargo clippy
./demos/render-all.sh
```

## Paths

Compose reads host paths from `.devcontainer/.env`. Defaults point at sibling repos (`../../aura-engine`, etc.).

## Repos

| Repo | Role |
|------|------|
| `aura-workbench` | Orchestration (Compose, Dev Container) |
| `aura-engine` | Procedural music engine (Rust) |
| `aura-editor` | Editor UI (placeholder) |

## License

MIT — see sibling product repos. Copyright (c) 2026 Silent Orb.
