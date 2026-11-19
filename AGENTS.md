# Aura Workbench — Agent Instructions

## Project

`aura-workbench` is the primary Aura development workspace. It owns Docker Compose, the Dev Container entrypoint, and multi-repo mounts. It does **not** own engine product code or editor UI code.

## Services

| Service | Role |
|---------|------|
| `engine` | Cursor attach target. Engine build, clippy, and **engine test suite**. Lean Rust + ALSA image. Includes docker-outside-of-docker for host Docker CLI access. |
| `editor` | Editor build, test, and run only (Rust + Iced GUI system deps). Derived from the engine image. **Not** for running engine tests. |
| `editor-tauri` | **Experimental** Tauri+React editor UI (Bun + WebKitGTK). Image Dockerfile is owned by **aura-editor** (`docker/Dockerfile`); Compose only wires the build. Derived from the engine image. **Not** for Iced or engine tests. |
| `editor-windows` | On-demand Windows MSVC cross-compile (`cargo-xwin` + Bun). Builds Iced `aura-editor.exe` and experimental portable `aura-editor-tauri.exe` into `AURA_EDITOR_WIN_OUT`. Derived from the engine image. **Not** in `runServices`. |

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
| `.mnt/imp-lab` | `imp-lab` |
| `.mnt/imp-ts` | `imp-ts` |
| `.mnt/imp-graph-editor` | `imp-graph-editor` (React/TS Imp canvas; not the Iced crate in `imp-lab`) |
| `.mnt/imp-graph-view` | `imp-graph-view` (Imp ↔ React Flow converters) |
| `.mnt/imp-workbench` | `imp-workbench` (temporary) |
| `.mnt/mir` | `mir` (read-only) |
| `.mnt/tome` | `tome` (temporary, read-only) |

Imp is also bind-mounted at `.mnt/aura-engine/.mnt/imp-*` so Cargo path deps inside the engine tree keep working.

`imp-graph-editor` is the shared **React** Imp operator canvas. The Iced Rust crate `imp_graph_editor` remains in `imp-lab`.

Each mounted repo may have its own `AGENTS.md` and `docs/`. Prefer the nearest `AGENTS.md` and that repo’s `docs/` when working in a given tree.

## Installed agent packages

Silentorb agent skill packages are baked into the engine image under `/opt/silentorb-agents/`. Skills are exposed via `.agents/skills/` symlinks. Follow each package’s `AGENTS.md`:

| Package | AGENTS.md |
| --- | --- |
| `silentorb-agents-publishing` | [`/opt/silentorb-agents/silentorb-agents-publishing/AGENTS.md`](/opt/silentorb-agents/silentorb-agents-publishing/AGENTS.md) |
| `silentorb-agents-planning` | [`/opt/silentorb-agents/silentorb-agents-planning/AGENTS.md`](/opt/silentorb-agents/silentorb-agents-planning/AGENTS.md) |

## Plan verification

| Repo | Full verify |
| --- | --- |
| workbench (this repo) | none — tooling/docs only; rebuild compose images when Dockerfiles change |
| `.mnt/aura-engine` | `cargo test` and `cargo clippy` from that repo |
| `.mnt/aura-editor` | Iced: `cargo test` / `cargo clippy` with `--workspace --exclude aura_editor_tauri` (editor service). Experimental Tauri: in **editor-tauri**, `cd apps/tauri && bun run build` and `cargo check -p aura_editor_tauri` |
| `.mnt/imp-rs` | see that repo’s `AGENTS.md` |
| `.mnt/imp-spec` | see that repo’s `AGENTS.md` |
| `.mnt/imp-lab` | see that repo’s `AGENTS.md` |
| `.mnt/imp-ts` | see that repo’s `AGENTS.md` |
| `.mnt/imp-graph-editor` | `bun run test` from that repo (run in **editor-tauri**; needs sibling `imp-ts`) |
| `.mnt/imp-graph-view` | `bun run test` from that repo (run in **editor-tauri**; needs sibling `imp-ts`) |
| `.mnt/imp-workbench` | see that repo’s `AGENTS.md` |
| `.mnt/mir` | none — read-only mount |
| `.mnt/tome` | none — temporary read-only mount |

When a plan touches `aura-editor` or the Windows editor build path (`.devcontainer` `editor-windows` image, `scripts/run-editor-windows-build.sh`, `scripts/build-editor-windows.sh`, `scripts/run-editor-tauri-windows-build.sh`, `scripts/build-editor-tauri-windows.sh`, related env/task wiring), add frontmatter todo `windows-editor-build` after full-suite verification and before `commit-await-approval`: run the affected wrapper (`run-editor-windows-build.sh` and/or `run-editor-tauri-windows-build.sh`), report the output path (`AURA_EDITOR_WIN_OUT` / `.win-out`), and confirm success so the exported `.exe` matches the tree just built.

## Cross-repo Rust agent docs

When changing agent docs (or linked style docs that agents are told to follow) with rules that are equally applicable to other **Rust** repos in this workspace (`aura-engine`, `aura-editor`, `imp-rs`, `imp-lab`), apply those changes across **all** of those repos in the same effort — via durable links (e.g. GitHub URLs) where practical, or mirrored wording where a reverse dependency would be wrong (e.g. Imp must not point at Aura for ownership). Do **not** hardcode co-located relative paths (`.mnt/…`, `../imp-*`, `../aura-*`); product repos should not assume sibling checkout layout. Prefer nearest-repo docs remaining the entry point; shared substance must still be reachable from each Rust repo’s `AGENTS.md` / `docs/rust-style.md`.

Rust repos in scope today: `aura-engine`, `aura-editor`, `imp-rs`, `imp-lab`. Not `imp-spec` (non-Rust) unless a change is language-neutral and separately warranted.

## Live Compose stack — hang avoidance (hard rules)

Agents attach to the **engine** service of the running Dev Container stack
(`aura-workbench_devcontainer`). Mutating that live stack from inside the session
**hangs the agent** (docker-outside-of-docker + Compose recreate/stop of sibling
or attach services). This has already stalled plan execution mid-flight.

**Never** run these against the live workbench Compose project from an agent
session (with or without `timeout`):

- `docker compose … up` / `down` / `stop` / `restart` / `kill`
- any `--force-recreate`, `--renew-anon-volumes`, or recreate-by-`run` of
  `engine`, `editor`, or `editor-tauri`
- recreating containers “so a new mount appears”

**Do instead:**

| Need | Safe approach |
|------|----------------|
| Run editor / editor-tauri commands | `docker compose … exec -T <service> bash -lc '…'` (service already up) |
| New/changed bind mounts or `.env` paths | Tell the user to **rebuild/reopen** the Dev Container; do not recreate services yourself |
| Verify when `exec` is wrong/unavailable | One-off `docker run --rm` with **host** bind mounts (same pattern as `scripts/run-editor-*-windows-build.sh`); never `compose up` |
| Image Dockerfile / feature changes | `docker compose … build <service>` is OK; applying it still needs user rebuild/reopen for the attach target |

Always pass `-T` on `exec`. Prefer `timeout` on any Docker CLI call that is not a
trivial `ps`/`images` query. Read-only `docker compose ps` / `build` / `config`
are fine.

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
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T editor bash -lc 'cd /workspaces/aura-workbench/.mnt/aura-editor && cargo test'
```

An oversized editor `target/` (stale debug fingerprints) is a **defect**, not expected. Default cap is **8 GiB**. Measure and clean when over:

```bash
bash /workspaces/aura-workbench/scripts/clean-editor-target-if-large.sh
# or VS Code / Cursor task: Clean editor target if large
```

Override the threshold with `AURA_EDITOR_TARGET_MAX_GIB`. Pass `--dry-run` to report without cleaning.

## Commands (editor-tauri, experimental)

Dockerfile: `aura-editor/docker/Dockerfile`. Run **in the editor-tauri service**:

```bash
cd /workspaces/aura-workbench/.mnt/aura-editor/apps/tauri
bun install
bun run tauri dev
```

From the attached engine context:

```bash
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T editor-tauri bash -lc 'cd /workspaces/aura-workbench/.mnt/aura-editor/apps/tauri && bun run build'
```

Rebuild the experimental image (pulls in engine via `additional_contexts`):

```bash
docker compose -f .devcontainer/docker-compose.yml build editor-tauri
```

Building the image does **not** require recreating the live `editor-tauri`
container mid-session. Use `exec -T` on the running service, or a one-off
`docker run --rm`, until the user rebuilds/reopens.

## Commands (editor Windows cross-compile)

On-demand `editor-windows` image (not started with the Dev Container). Artifacts go to the host path in `AURA_EDITOR_WIN_OUT` (mounted at `/out`; see `.devcontainer/.env.example`):

- **Iced:** `aura-editor.exe` plus a `demos/` copy of `aura-engine/demos/*.json`
- **Experimental Tauri:** portable `aura-editor-tauri.exe` only (no installer). Needs **WebView2** on the Windows host (normally present via Edge).

The engine Dev Container includes **docker-outside-of-docker** so the Docker CLI can talk to the host daemon. After changing `devcontainer.json` features, rebuild/reopen the container.

From the attached engine context (or the VS Code / Cursor tasks **Build editor (Windows)** / **Build editor Tauri (Windows)**):

```bash
bash /workspaces/aura-workbench/scripts/run-editor-windows-build.sh
bash /workspaces/aura-workbench/scripts/run-editor-tauri-windows-build.sh
```

Those wrappers build `editor-windows` and run the cross-compile with host bind mounts (nested `docker compose run` would pass container paths the host daemon cannot mount).

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
