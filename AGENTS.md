# Aura Workbench — Agent Instructions

`aura-workbench` is the primary Aura development workspace. It owns Docker Compose (`.devcontainer/`, `docker/`), the helper `scripts/`, and these docs. Engine product code and editor UI code live in the sibling repos below. Follow the nearest repo's `AGENTS.md` and `docs/` when working in it.

Aura's editor UI is **aura-editor**: Imp Lab extensions (a UI library) plus the Aura pack configuration, run inside Imp Lab. Imp Lab stays domain-neutral, so audio-specific UI goes in aura-editor.

## Repos

All are siblings of this workbench (`../<repo>`, or `/workspaces/<repo>` inside containers).

| Repo | Role |
| --- | --- |
| `../aura-engine` | Procedural music engine (Rust); the Aura pack's extension libraries and `lab-pack/` data |
| `../aura-editor` | Aura editor UI as Imp Lab extensions (TypeScript) and the pack configuration |
| `../imp-lab` | Domain-neutral desktop host for Imp graphs and Tome records, with the extension system; owns the `imp-lab` image (`docker/Dockerfile`) |
| `../imp-rs`, `../imp-spec`, `../imp-ts` | Imp (Rust, specs, TypeScript) |
| `../imp-graph-view` | Imp ↔ React Flow converters |
| `../tome-rust-server` | Hosts the `imp_mir` crate (aura-engine path-deps it) |
| `../mir` | Read-only reference: don't edit it |
| `../imp-workbench` | Sibling workbench (reference) |

## Running things

The toolchains live in Compose services, not on the host. `scripts/run [-C <dir>] <service> <cmd...>` starts a service if it isn't running (it never recreates one) and maps `<dir>` (default `$PWD`; `-C` works like `git -C`) to `/workspaces/...`.

| Service | Owns | Example |
| --- | --- | --- |
| `engine` | Rust + ALSA: aura-engine build/clippy/tests | `scripts/run -C ../aura-engine engine cargo test` |
| `imp-lab` | Bun + WebKitGTK: Imp Lab, aura-editor, imp-graph-view, pack assembly. Derived from the engine image | `scripts/run -C ../aura-editor imp-lab bun run test` |
| `editor-windows` | On-demand (profile `windows`) MSVC cross-compile | `scripts/run-imp-lab-windows-build.sh` |

```bash
scripts/compose ps | logs <svc> | config -q
scripts/compose build               # imp-lab/editor-windows build FROM engine via additional_contexts
scripts/compose rebuild <svc>       # after Dockerfile changes (build + recreate)
scripts/assemble-aura-pack.sh       # Aura pack -> .aura-pack/ (runs in imp-lab)
scripts/run -C ../imp-lab/apps/tauri imp-lab env IMP_LAB_EXTENSIONS=/workspaces/aura-workbench/.aura-pack/extensions.json bun run tauri dev
scripts/run-imp-lab-windows-build.sh  # imp-lab.exe + Aura pack -> AURA_EDITOR_WIN_OUT
```

- Ask before running `down` or recreating `engine`/`imp-lab`, because Cursor may be attached to them.
- `.devcontainer/.env` holds local path overrides; its template is `.env.example`. `AURA_EDITOR_WIN_OUT` sets the Windows export dir. Exports to flaky `/mnt/*` mounts time out and fall back to `.win-out/`.
- If the engine image picks up heavy deps that imp-lab doesn't need, extract a shared base image instead of deriving imp-lab from engine.

## Plan verification

| Repo | Full verify (via `scripts/run`) |
| --- | --- |
| workbench | `scripts/compose config -q`; rebuild images when Dockerfiles change |
| `aura-engine` | `engine`: `cargo test` and `cargo clippy` |
| `aura-editor` | `imp-lab`: `bun run test` and `bun run build` (needs sibling imp-lab) |
| `imp-lab` | `engine` or `imp-lab`: `cargo test` and `cargo clippy -- -D warnings`. Desktop app (`imp-lab`): `cd apps/tauri && bun run test && bun run build`, `cargo test -p imp_lab`, `cargo check -p imp_lab`. If the extension contract changed, also verify aura-editor and the aura-engine pack crates |
| `imp-graph-view` | `imp-lab`: `bun run test` (needs sibling imp-ts) |
| `tome-rust-server` | see its `AGENTS.md`. If `imp_mir` changed, also run `cargo test` in aura-engine |
| `imp-rs`, `imp-spec`, `imp-ts` | see each repo's `AGENTS.md` |
| `mir` | none (read-only) |

**Windows editor build gate:** run `scripts/run-imp-lab-windows-build.sh` after full verification and before asking to commit when a change touches any of these:

- aura-editor
- Imp Lab's desktop app
- the Aura pack (aura-editor `pack/`, aura-engine `lab-pack/` and the pack crates, `scripts/assemble-aura-pack.sh`)
- the Windows build path (`docker/editor-windows`, `scripts/*windows-build*.sh`)

Report the output path and confirm the build succeeded.

## Cross-repo Rust agent docs

Some agent-doc rules apply equally to all the Rust repos here (`aura-engine`, `imp-rs`, `imp-lab`). Apply those across all of them in the same effort:

- Use durable links such as GitHub URLs, or mirrored wording where a reverse dependency would be wrong. For example, Imp must not point at Aura.
- Don't hardcode sibling checkout paths in product-repo docs.

## Commits

Each affected repo gets its own commit. Don't commit until the user asks. `scripts/push` pushes in dependency order.

## Naming

Repos use **kebab-case** (`aura-engine`). Rust crates use **snake_case** (`aura_scheduler`).

## Dev Container (optional)

Cursor's "Reopen in Container" attaches to `engine`, which adds docker-outside-of-docker. Inside it, never recreate the live stack: see `.cursor/rules/live-compose-stack.mdc`.
