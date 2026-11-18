# Aura Workbench

Primary development workspace for Aura. Opens as a Dev Container that starts Compose services:

- **engine** — Rust toolchain + ALSA; Cursor attaches here; home for the **engine test suite**
- **editor** — derives from the engine image, adds Linux GUI deps for **Iced**; editor build/test/run only (not engine tests)
- **editor-tauri** — **experimental** Tauri+React UI (Bun + WebKitGTK); Dockerfile owned by **aura-editor** (`docker/Dockerfile`)

An on-demand **editor-windows** service cross-compiles Windows MSVC binaries (`cargo-xwin`, plus Bun for Tauri): Iced `aura-editor.exe` and experimental portable `aura-editor-tauri.exe`. It is not started with the Dev Container.

## Host layout

```text
~/dev/
  aura-workbench/   # this repo — open in Cursor
  aura-engine/
  aura-editor/
  imp-rs/
  imp-spec/
  imp-lab/
  imp-ts/
  imp-graph-editor/  # React Imp canvas (distinct from Iced imp_graph_editor in imp-lab)
  imp-graph-view/
  mir/
  tome/           # temporary read-only mount
```

Inside the container, siblings appear under the workbench `.mnt/` tree:

```text
/workspaces/aura-workbench/
  .mnt/
    aura-engine/
    aura-editor/
    imp-rs/
    imp-spec/
    imp-lab/
    imp-ts/
    imp-graph-editor/
    imp-graph-view/
    mir/
    tome/         # temporary, read-only
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
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T editor bash -lc 'cd /workspaces/aura-workbench/.mnt/aura-editor && cargo test'
```

### Editor Tauri (experimental, editor-tauri service)

```bash
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T editor-tauri bash -lc 'cd /workspaces/aura-workbench/.mnt/aura-editor/apps/tauri && bun run tauri dev'
```

Do **not** `docker compose up --force-recreate` (or `down`/`restart`) the live
Dev Container stack from inside the engine session — it hangs agents. New mounts
need a rebuild/reopen; one-off `docker run --rm` is fine for verify. See
[`AGENTS.md`](./AGENTS.md) § Live Compose stack.

### Rebuild images

Editor, editor-tauri, and editor-windows `FROM` `aura-workbench-engine:local`. Compose declares that build dependency,
so one command is enough for the images Dev Containers builds by default:

```bash
docker compose -f .devcontainer/docker-compose.yml build
```

To build the experimental Tauri image only:

```bash
docker compose -f .devcontainer/docker-compose.yml build editor-tauri
```

### Windows editor binaries

Set `AURA_EDITOR_WIN_OUT` in `.devcontainer/.env` to a host directory for output `.exe` files
(default `../.win-out`). Point it at a Windows-visible path (e.g. `/mnt/d/AuraEditor`) to run
binaries from Windows Explorer. Both Iced and experimental Tauri exports share this mount.

- **Iced** (`run-editor-windows-build.sh` / task **Build editor (Windows)**): `aura-editor.exe`
  plus engine demo graphs (`aura-engine/demos/*.json`, including `instruments.json`) under `demos/`.
- **Experimental Tauri** (`run-editor-tauri-windows-build.sh` / task **Build editor Tauri (Windows)**):
  portable `aura-editor-tauri.exe` only (no installer). The Windows host needs **WebView2**
  (normally present via Edge on Win10/11).

Export I/O is time-bounded: if the configured mount is flaky or locked (common with some
`/mnt/e/...` WSL paths), the script warns and falls back to the workbench `.win-out`
instead of hanging; the release build itself is still considered successful.

The engine container uses **docker-outside-of-docker** so this works from the attached Dev Container
(rebuild/reopen after feature changes). Prefer the wrappers (or the build tasks) over raw
`docker compose run`, which would bind-mount container paths the host daemon cannot see:

```bash
bash /workspaces/aura-workbench/scripts/run-editor-windows-build.sh
bash /workspaces/aura-workbench/scripts/run-editor-tauri-windows-build.sh
```

## Agent docs

See [`AGENTS.md`](./AGENTS.md). Planning and publishing skills come from silentorb-agents packages baked into the engine image (`/opt/silentorb-agents/`); rebuild the engine image to bump package versions.

## Paths

Compose reads host paths from `.devcontainer/.env`. Defaults point at sibling repos (`../../aura-engine`, etc.).
`AURA_EDITOR_WIN_OUT` controls where Windows exports land (`aura-editor.exe` + `demos/`, and/or `aura-editor-tauri.exe`).

## Repos

| Repo | Role |
|------|------|
| `aura-workbench` | Orchestration (Compose, Dev Container) |
| `aura-engine` | Procedural music engine (Rust) |
| `aura-editor` | Editor UI (Rust / Iced) |

End users target Windows; daily development is WSL Linux containers. Use the on-demand **editor-windows** service to produce portable Windows binaries.

## License

MIT — see sibling product repos. Copyright (c) 2026 Silent Orb.
