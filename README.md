# Aura Workbench

Primary development workspace for Aura. Opens as a Dev Container that starts Compose services:

- **engine** — Rust toolchain + ALSA; Cursor attaches here; home for the **engine test suite**
- **imp-lab** — Imp Lab desktop host (Bun + WebKitGTK); Dockerfile owned by **imp-lab** (`docker/Dockerfile`). Also builds and tests **aura-editor** (Aura's editor UI as Imp Lab extensions) and assembles the Aura pack

An on-demand **editor-windows** service cross-compiles Windows MSVC binaries (`cargo-xwin` plus Bun): portable `imp-lab.exe` with the Aura pack. It is not started with the Dev Container.

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
  imp-graph-view/  # Imp ↔ React Flow converters
  mir/
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
    imp-graph-view/
    mir/
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

### Imp Lab and aura-editor (imp-lab service)

```bash
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T imp-lab bash -lc 'cd /workspaces/aura-workbench/.mnt/aura-editor && bun run test'
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T imp-lab bash -lc 'bash /workspaces/aura-workbench/scripts/assemble-aura-pack.sh'
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T imp-lab bash -lc 'cd /workspaces/aura-workbench/.mnt/imp-lab/apps/tauri && IMP_LAB_EXTENSIONS=/workspaces/aura-workbench/.aura-pack/extensions.json bun run tauri dev'
```

The second command assembles the Aura pack (aura-editor configuration + UI library, aura-engine cdylibs and data) into `.aura-pack/`; the third runs Imp Lab with it.

Do **not** `docker compose up --force-recreate` (or `down`/`restart`) the live
Dev Container stack from inside the engine session — it hangs agents. New mounts
need a rebuild/reopen; one-off `docker run --rm` is fine for verify. See
[`AGENTS.md`](./AGENTS.md) § Live Compose stack.

### Rebuild images

imp-lab and editor-windows `FROM` `aura-workbench-engine:local`. Compose declares that build dependency,
so one command is enough for the images Dev Containers builds by default:

```bash
docker compose -f .devcontainer/docker-compose.yml build
```

To build the Imp Lab image only:

```bash
docker compose -f .devcontainer/docker-compose.yml build imp-lab
```

### Windows editor binaries

Set `AURA_EDITOR_WIN_OUT` in `.devcontainer/.env` to a host directory for output `.exe` files
(default `../.win-out`). Point it at a Windows-visible path (e.g. `/mnt/d/AuraEditor`) to run
binaries from Windows Explorer.

- **Imp Lab** (`run-imp-lab-windows-build.sh` / task **Build Imp Lab (Windows)**):
  portable `imp-lab.exe` plus the Aura pack (aura-editor's `extensions.json` and UI library, aura-engine's catalog / playback `.dll`s, `catalogs/`, `demo-project/`).
  The Windows host needs **WebView2** (normally present via Edge on Win10/11).

Export I/O is time-bounded: if the configured mount is flaky or locked (common with some
`/mnt/e/...` WSL paths), the script warns and falls back to the workbench `.win-out`
instead of hanging; the release build itself is still considered successful.

The engine container uses **docker-outside-of-docker** so this works from the attached Dev Container
(rebuild/reopen after feature changes). Prefer the wrapper (or the build task) over raw
`docker compose run`, which would bind-mount container paths the host daemon cannot see:

```bash
bash /workspaces/aura-workbench/scripts/run-imp-lab-windows-build.sh
```

## Agent docs

See [`AGENTS.md`](./AGENTS.md). Planning and publishing skills come from silentorb-agents packages baked into the engine image (`/opt/silentorb-agents/`); rebuild the engine image to bump package versions.

## Paths

Compose reads host paths from `.devcontainer/.env`. Defaults point at sibling repos (`../../aura-engine`, etc.).
`AURA_EDITOR_WIN_OUT` controls where Windows exports land (`imp-lab.exe` and the Aura pack).

## Repos

| Repo | Role |
|------|------|
| `aura-workbench` | Orchestration (Compose, Dev Container) |
| `aura-engine` | Procedural music engine (Rust); the Aura pack's extension libraries and data |
| `aura-editor` | Aura's editor UI as Imp Lab extensions (TypeScript UI library) and the Aura pack configuration |
| `imp-lab` | Imp Lab: domain-neutral desktop host for Imp graphs and Tome records, with the extension system |

End users target Windows; daily development is WSL Linux containers. Use the on-demand **editor-windows** service to produce portable Windows binaries.

## License

MIT — see sibling product repos. Copyright (c) 2026 Silent Orb.
