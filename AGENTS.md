# Aura Workbench — Agent Instructions

## Project

`aura-workbench` is the primary Aura development workspace. It owns Docker Compose, the Dev Container entrypoint, and multi-repo mounts. It does **not** own engine product code or editor UI code.

## Services

| Service | Role |
|---------|------|
| `engine` | Cursor attach target. Engine build, clippy, and **engine test suite**. Lean Rust + ALSA image. Includes docker-outside-of-docker for host Docker CLI access. |
| `imp-lab` | Imp Lab desktop host (Bun + WebKitGTK), plus **aura-editor** build/test (Bun) and Aura pack assembly. Image Dockerfile is owned by **imp-lab** (`docker/Dockerfile`); Compose only wires the build. Derived from the engine image. **Not** for engine tests. |
| `editor-windows` | On-demand Windows MSVC cross-compile (`cargo-xwin` + Bun). Builds portable `imp-lab.exe` and the Aura pack into `AURA_EDITOR_WIN_OUT`. Derived from the engine image. **Not** in `runServices`. |

Aura's editor UI is **aura-editor**: Imp Lab extensions (a UI library) plus the Aura pack configuration, run inside Imp Lab. There is no separate editor application or editor service. Imp Lab stays domain-neutral; audio-specific UI goes in aura-editor.

If the engine image later accumulates substantial deps the imp-lab image does not need, extract a shared base image instead of deriving imp-lab from engine.

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
| `.mnt/imp-graph-view` | `imp-graph-view` (Imp ↔ React Flow converters) |
| `.mnt/imp-workbench` | `imp-workbench` (temporary) |
| `.mnt/mir` | `mir` (read-only) |
| `.mnt/tome-rust-server` | `tome-rust-server` (hosts the `imp_mir` crate) |

Imp and tome-rust-server are also bind-mounted at `.mnt/aura-engine/.mnt/imp-*` and `.mnt/aura-engine/.mnt/tome-rust-server` so Cargo path deps inside the engine tree keep working.

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
| `.mnt/aura-editor` | `bun run test` and `bun run build` from that repo (run in **imp-lab**; needs sibling `imp-lab`) |
| `.mnt/imp-rs` | see that repo’s `AGENTS.md` |
| `.mnt/tome-rust-server` | see that repo’s `AGENTS.md` (`imp_mir` changes: also `cargo test` in aura-engine) |
| `.mnt/imp-spec` | see that repo’s `AGENTS.md` |
| `.mnt/imp-lab` | Library crates: `cargo test` / `cargo clippy -- -D warnings`. Desktop app: in **imp-lab**, `cd apps/tauri && bun run test && bun run build`, `cargo test -p imp_lab` and `cargo check -p imp_lab`. Extension contract changes: also verify `aura-editor` and the pack crates in `aura-engine` |
| `.mnt/imp-ts` | see that repo’s `AGENTS.md` |
| `.mnt/imp-graph-view` | `bun run test` from that repo (run in **imp-lab**; needs sibling `imp-ts`) |
| `.mnt/imp-workbench` | see that repo’s `AGENTS.md` |
| `.mnt/mir` | none — read-only mount |

When a plan touches `aura-editor`, Imp Lab’s desktop app, the Aura pack (aura-editor `pack/`, aura-engine `lab-pack/` and pack crates, `scripts/assemble-aura-pack.sh`), or the Windows editor build path (`.devcontainer` `editor-windows` image, `scripts/run-imp-lab-windows-build.sh`, `scripts/build-imp-lab-windows.sh`, related env/task wiring), add frontmatter todo `windows-editor-build` after full-suite verification and before `commit-await-approval`: run `run-imp-lab-windows-build.sh`, report the output path (`AURA_EDITOR_WIN_OUT` / `.win-out`), and confirm success so the exported `.exe` matches the tree just built.

## Cross-repo Rust agent docs

When changing agent docs (or linked style docs that agents are told to follow) with rules that are equally applicable to other **Rust** repos in this workspace (`aura-engine`, `imp-rs`, `imp-lab`), apply those changes across **all** of those repos in the same effort — via durable links (e.g. GitHub URLs) where practical, or mirrored wording where a reverse dependency would be wrong (e.g. Imp must not point at Aura for ownership). Do **not** hardcode co-located relative paths (`.mnt/…`, `../imp-*`, `../aura-*`); product repos should not assume sibling checkout layout. Prefer nearest-repo docs remaining the entry point; shared substance must still be reachable from each Rust repo’s `AGENTS.md` / `docs/rust-style.md`.

Rust repos in scope today: `aura-engine`, `imp-rs`, `imp-lab`. Not `imp-spec` or `aura-editor` (non-Rust) unless a change is language-neutral and separately warranted.

## Live Compose stack — hang avoidance (hard rules)

Agents attach to the **engine** service of the running Dev Container stack
(`aura-workbench_devcontainer`). Mutating that live stack from inside the session
**hangs the agent** (docker-outside-of-docker + Compose recreate/stop of sibling
or attach services). This has already stalled plan execution mid-flight.

**Never** run these against the live workbench Compose project from an agent
session (with or without `timeout`):

- `docker compose … up` / `down` / `stop` / `restart` / `kill`
- any `--force-recreate`, `--renew-anon-volumes`, or recreate-by-`run` of
  `engine` or `imp-lab`
- recreating containers “so a new mount appears”

**Do instead:**

| Need | Safe approach |
|------|----------------|
| Run Imp Lab / aura-editor commands | `docker compose … exec -T <service> bash -lc '…'` (service already up) |
| New/changed bind mounts or `.env` paths | Tell the user to **rebuild/reopen** the Dev Container; do not recreate services yourself |
| Verify when `exec` is wrong/unavailable | One-off `docker run --rm` with **host** bind mounts (same pattern as `scripts/run-*-windows-build.sh`); never `compose up` |
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

## Commands (aura-editor)

Run **in the imp-lab service**, from `/workspaces/aura-workbench/.mnt/aura-editor`:

```bash
bun install
bun run test
bun run build
```

From the attached engine context:

```bash
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T imp-lab bash -lc 'cd /workspaces/aura-workbench/.mnt/aura-editor && bun run test'
```

## Aura pack (local run)

The Aura pack is aura-editor's `pack/extensions.json` and UI library plus aura-engine's pack cdylibs and `lab-pack/` data. Assemble it into `.aura-pack/` (git-ignored) in the **imp-lab** service (or the VS Code / Cursor task **Assemble Aura pack (Linux)**), then run Imp Lab with it:

```bash
bash /workspaces/aura-workbench/scripts/assemble-aura-pack.sh
cd /workspaces/aura-workbench/.mnt/imp-lab/apps/tauri
IMP_LAB_EXTENSIONS=/workspaces/aura-workbench/.aura-pack/extensions.json bun run tauri dev
```

`CARGO_TARGET_DIR` overrides where the engine cdylibs are built.

## Commands (imp-lab)

Dockerfile: `imp-lab/docker/Dockerfile`. Run **in the imp-lab service**:

```bash
cd /workspaces/aura-workbench/.mnt/imp-lab/apps/tauri
bun install
bun run tauri dev
```

From the attached engine context:

```bash
docker compose -f /workspaces/aura-workbench/.devcontainer/docker-compose.yml exec -T imp-lab bash -lc 'cd /workspaces/aura-workbench/.mnt/imp-lab/apps/tauri && bun run build'
```

Rebuild the Imp Lab image (pulls in engine via `additional_contexts`):

```bash
docker compose -f .devcontainer/docker-compose.yml build imp-lab
```

Building the image does **not** require recreating the live `imp-lab`
container mid-session. Use `exec -T` on the running service, or a one-off
`docker run --rm`, until the user rebuilds/reopens.

## Commands (editor Windows cross-compile)

On-demand `editor-windows` image (not started with the Dev Container). Artifacts go to the host path in `AURA_EDITOR_WIN_OUT` (mounted at `/out`; see `.devcontainer/.env.example`):

- **Imp Lab + Aura pack:** portable `imp-lab.exe` plus the Aura pack (`extensions.json` from aura-editor, `extensions/aura_imp_lab_catalogs.dll`, `extensions/aura_imp_lab_playback.dll`, `extensions/aura_editor.js`, `catalogs/`, and `demo-project/` when not already present). Needs **WebView2** on the Windows host (normally present via Edge).

The engine Dev Container includes **docker-outside-of-docker** so the Docker CLI can talk to the host daemon. After changing `devcontainer.json` features, rebuild/reopen the container.

From the attached engine context (or the VS Code / Cursor task **Build Imp Lab (Windows)**):

```bash
bash /workspaces/aura-workbench/scripts/run-imp-lab-windows-build.sh
```

That wrapper builds `editor-windows` and runs the cross-compile with host bind mounts (nested `docker compose run` would pass container paths the host daemon cannot mount).

## Image rebuild

imp-lab and editor-windows derive from `aura-workbench-engine:local`. Compose wires that with
`additional_contexts`, so a single build is safe (and what Dev Containers runs for engine+imp-lab):

```bash
docker compose -f .devcontainer/docker-compose.yml build
```

To build the Imp Lab or Windows image only (pulls in engine via `additional_contexts`):

```bash
docker compose -f .devcontainer/docker-compose.yml build imp-lab
docker compose -f .devcontainer/docker-compose.yml build editor-windows
```

## Commits

This workspace spans multiple git repositories. Plan and execute **one commit per affected repo**. Do not commit until the user explicitly asks.

## Naming

Repos and projects use **kebab-case** (`aura-engine`). Rust crates use **snake_case** (`aura_scheduler`).
