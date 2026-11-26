# Aura Workbench

Primary development workspace for Aura. Owns the Docker Compose stack and helper scripts. Expects sibling checkouts next to this repo (`../aura-engine`, `../aura-editor`, `../imp-lab`, `../imp-rs`, `../imp-spec`, `../imp-ts`, `../imp-graph-view`, `../tome-rust-server`, `../mir`, `../silentorb-agents`).

## Usage

Work from WSL: Claude Code in this directory, or Cursor via `aura-workbench.code-workspace`. Toolchains run in Compose services:

- **engine**: Rust + ALSA, for the engine build and test suite
- **imp-lab**: Imp Lab desktop host (Bun + WebKitGTK). Its Dockerfile is owned by imp-lab. It also builds and tests aura-editor and assembles the Aura pack
- **editor-windows**: on demand, cross-compiles `imp-lab.exe` plus the Aura pack for Windows

```bash
scripts/run -C ../aura-engine engine cargo test
scripts/run -C ../aura-editor imp-lab bun run test
scripts/assemble-aura-pack.sh            # -> .aura-pack/
scripts/run-imp-lab-windows-build.sh     # -> AURA_EDITOR_WIN_OUT
scripts/compose build                    # rebuild images
```

Optional: **Reopen in Container** attaches to `engine`. Inside it, siblings are at `/workspaces/<repo>`.

## Configuration

`.devcontainer/.env` (template `.env.example`) holds sibling path overrides and `AURA_EDITOR_WIN_OUT`. Point that at a Windows-visible path such as `/mnt/e/dev/aura` to run exports from Explorer. The Windows host needs **WebView2** (normally present via Edge).

Agent docs: [`AGENTS.md`](./AGENTS.md).

## License

MIT — see sibling product repos. Copyright (c) 2026 Silent Orb.
