---
name: Aura Editor as an Imp Lab extension
overview: "Remove Iced from imp-lab and aura-editor, and move the audio-specific Tauri UI (the notation editor: piano roll with audition and recording) out of Imp Lab into aura-editor, which ships it as an Imp Lab extension. There are no document types: everything Lab opens is a Tome node, and what it is comes from its Tome node type (type-table membership). Imp Lab keeps its structure; it drops its built-in document-kind layer (imp-graph / notation / other) in favour of Tome node types, and gains the extension support needed to host the moved pieces: the reserved clientModule field is implemented, and an extension can register an editor for a Tome node type plus default bindings. The Imp graph editor stays built in as the editor for the Imp Graphs node type. imp-lab's Iced crate and aura-editor's Iced app and extension crates are deleted. Docs that call aura-editor deprecated are corrected, the Iced editor image is dropped, and the Windows export ships Imp Lab with the Aura pack (engine cdylibs + aura-editor UI)."
todos:
  - id: docs-intent
    content: "Durable intent first. imp-lab: AGENTS.md, README.md, docs state Imp Lab has no audio/music concepts and no document types (records are Tome nodes; editors are chosen by Tome node type); drop the Backend/Frontend (Iced) split and deprecated-editor wording; projects-and-records.md drops the built-in Notations table and kind filter; extensions.md documents clientModule loading and the node-type-editor and binding kinds (remove the 'full client-side TS extension runtime' non-goal and the piano-roll sections). aura-editor: rewrite AGENTS.md, README.md, docs/README.md, design/scoping product docs as Aura's editor UI delivered as an Imp Lab extension (not deprecated); move piano-roll, audition, recording and notation-binding requirements here from imp-lab docs; delete or rewrite Iced-only docs. aura-engine: lab-pack/README.md and aura_imp design overview say the pack configuration is owned by aura-editor; the engine supplies the cdylibs and data. Workbench and imp-lab 'Product packs' docs: Aura pack = aura-editor configuration + UI library + aura-engine cdylibs and data. Workbench AGENTS.md/README.md: services and Windows export."
    status: completed
  - id: remove-iced
    content: "Delete crates/imp_graph_editor from imp-lab (only consumer was the Iced aura-editor) and the iced / native-theme-iced / iced_test deps; delete aura-editor's Iced app (src/**, tests/**, Iced-only assets) and crates aura_interfaces / aura_ext_builtin / aura_ext_notation, with their Cargo workspace and lockfile"
    status: completed
  - id: node-types-not-kinds
    content: "imp-lab: replace the document-kind layer with Tome node types. Records carry their type-table ids and node-stored columns (per the store's table schemas) instead of kind + graph/notation fields; lab_model drops KIND_* / table_for_kind / kind_for_tables and the built-in Notations table (only the Imp Graphs table stays well-known); explorer and Go to Record filter by node type; File > New lists node types that have an editor (Imp Graph built in); seed.rs maps a standalone JSON document's `type` to a node type that has a registered editor (Imp graph built in) and otherwise reports unsupported. Behaviour for Imp graphs unchanged. Tests updated."
    status: completed
  - id: extension-support
    content: "imp-lab extension additions, following the existing model (extensions are libraries of implementations; components in extensions.json select an implementationId and wire it with params): (1) webview implementations: an extension's UI library (the existing reserved clientModule field) exports named implementations only — no register hook, no wiring in code — exactly as the cdylib registers catalog/service implementations by id. Host loads it, resolves each enabled component's implementationId against it, and provides shared react / react-dom / @mantine/core / @tauri-apps/api through an import map. (2) node-type-editor component kind: params nodeTypeId (Tome type-table id) and column; its implementation is an editor (empty value, parse/validate, summary, undo history hooks, Panel). Which node type an editor edits is configuration, not code. Lab opens nodes of that type in it and offers New for it. (3) binding component kind: key → command, optional editor-component scope, merged under user bindings. (4) implementations receive a host context (services/requests/topics, per-component user state, the component's params). Tests with a fixture extension."
    status: completed
  - id: move-notation
    content: "Move src/piano-roll/** (notation model, edits, history, audition, recording, PianoRollPanel + tests) from imp-lab into aura-editor as a library of implementations (bun package built to one ESM bundle; e.g. a `piano-roll` editor implementation; audition and recording stay parts of it unless they earn their own components). The Lab pack declares a node-type-editor component (implementationId piano-roll) for the Notations node type 01M80M9N0TAT00000000000001 (kept equal to aura_imp::NOTATION_NODE_TYPE; existing projects and the Lab pack demo project carry that type table in their Tome model) plus notation bindings (D/S/E/N/R). Audition/recording keep using the generic service event/request channels to the Lab pack's playback service. Then remove every notation/piano trace from imp-lab; grep -iE 'notation|piano|semitone|audition' over imp-lab is clean."
    status: completed
  - id: pack-assembly
    content: "aura-editor owns the Aura pack configuration. Move aura-engine/lab-pack/extensions.json (and the pack-facing README content) to aura-editor (e.g. pack/extensions.json), adding the aura-editor extension row (UI library extensions/aura_editor/index.js), its node-type-editor and binding components. aura-engine keeps the cdylib crates and the engine data they and its tests use (lab-pack/catalogs, lab-pack/demo-project; consider renaming lab-pack to reflect that). The two engine tests that read the pack config (aura_imp_lab_playback lib.rs pack_registers_midi_settings_that_resolve, plugins.rs the_pack_declares_plugin_choices_and_gui_actions) move to aura-editor as config checks (component references resolve; service ids / topics match what the engine extensions declare), with the engine keeping tests of its own ids. Pack assembly (extensions.json from aura-editor, cdylibs built from aura-engine, catalogs + demo project from aura-engine, aura-editor UI bundle) moves into a workbench script used for both local Linux runs (replacing the hand-copied .so files in lab-pack/extensions) and the Windows export beside imp-lab.exe."
    status: completed
  - id: workbench-tooling
    content: "aura-workbench: aura-editor no longer needs Iced/winit/wgpu, so drop the editor service and docker/editor/Dockerfile (aura-editor builds/tests with bun in the imp-lab service); editor-windows builds aura-editor's bundle into the pack; remove clean-editor-target-if-large.sh and its task if no Rust target remains; update devcontainer.json runServices, docker-compose.yml, .vscode/tasks.json, AGENTS.md (services, verify matrix, commands, editor Windows section). Do not recreate live services (hang rules): user rebuilds/reopens."
    status: completed
  - id: verify-full-suites
    content: "Full-suite verification — After implementation, run full verify for every plan-affected repo and its direct dependents (see the project's verify matrix, typically AGENTS.md). imp-lab: cargo test, cargo clippy -- -D warnings, bun run test, cd apps/tauri && bun run build, cargo check -p imp_lab. aura-editor: bun run test and bun run build (in imp-lab service). imp-graph-view: bun run test. aura-engine: cargo test. Fix failures or get an explicit user waiver before await-commit. Reason about CI; never defer suite confidence to a future CI run."
    status: completed
  - id: windows-editor-build
    content: "Run scripts/run-imp-lab-windows-build.sh, report AURA_EDITOR_WIN_OUT output path, confirm imp-lab.exe and the Aura pack (catalog + playback DLLs + aura-editor client module) were built from this tree"
    status: completed
  - id: commit-await-approval
    content: "Commit (await user approval) — After full-suite verification for affected + dependents (incl. CI considered), re-run git status/diff per repo, reconcile with this strategy, commit only when the user explicitly requests it."
    status: completed
isProject: false
---

# Aura Editor as an Imp Lab extension

## User request

Remove any use of Iced from imp-lab and Aura.

Decisions from review:

- **Imp Lab is not audio-specific.** The notation editor should never have been put there. All audio-specific Tauri UI belongs in **aura-editor** — that was always the plan.
- **No foundational refactor of imp-lab.** It may need additional extension support to integrate the pieces moved to aura-editor, nothing more.
- **No document types.** With Tome, every "document" is a Tome node type.
- **Modular extensions.** aura-editor provides one or more extensions of modular components, wired by configuration (no imperative client entry point).
- **Export as documented:** `imp-lab.exe` with extension configuration that adds all Aura audio functionality. **That configuration moves to aura-editor.**

## High-level design

### Problem

- Iced lives in imp-lab's `crates/imp_graph_editor` (~3k lines) and the whole of aura-editor (Iced app plus `aura_interfaces` / `aura_ext_builtin` / `aura_ext_notation`). aura-engine has no Iced use.
- The Tauri notation editor was built into Imp Lab (`apps/tauri/src/piano-roll/`; commits `816cf7d`, `387cd49`, `b73953d`).
- Imp Lab still keeps a document-kind layer on top of Tome (`KIND_IMP_GRAPH` / `KIND_NOTATION`, `table_for_kind`, `kind` on records, explorer kind filter), and that layer hard-codes notation, including a built-in Notations type table in every new project.
- Docs drifted: aura-editor's AGENTS.md calls it deprecated and replaced by Imp Lab + the Lab pack.
- Extensions can't contribute UI yet: `clientModule` is parsed but reserved.

### Solution

```text
Tome node  --type-table membership-->  node type  --registered editor-->  panel
  Imp Graphs type     -> built-in Imp graph editor (imp-lab)
  Notations type      -> piano roll (aura-editor client module, via Aura pack)
  any other type      -> listed, not openable
```

- **Delete all Iced** from imp-lab and aura-editor.
- **Node types, not kinds.** Lab picks an editor from a node's Tome type. The kind layer goes; Imp graphs keep working through the same path with a built-in editor.
- **Extension support:** extensions can supply webview implementations the same way their cdylibs supply catalog and service implementations, selected and wired by components in `extensions.json`. New component kinds: `node-type-editor` (Tome type id + column it edits) and `binding`. That is the whole extension surface added.
- **Move notation** to aura-editor as that module. The Notations node type is defined by the Tome model of the stores that use it (the Lab pack demo project already carries it), not by Lab.
- **aura-editor owns the Aura pack configuration.** The export stays `imp-lab.exe` + Aura pack; the pack's `extensions.json` lives in aura-editor and wires the engine's cdylibs (catalogs, playback) and aura-editor's UI library together. aura-engine supplies the cdylibs and the catalog/demo data.
- **Without the pack**, Notations nodes are ordinary Tome nodes: listed, not openable.

## Objective analysis

### Pros

- Restores the layering with a small change to imp-lab, and removes a redundant layer instead of adding one.
- `clientModule` was always planned; this delivers it with a real first user.
- Removes the Iced/wgpu dependency tree and the Iced editor image.

### Cons

- Runtime loading of UI modules needs shared React/Mantine instances; that is the main technical risk.
- A fresh Lab project no longer gets a Notations table automatically (see open choices).

### Worth doing

Yes.

## Low-level design

### Order of work

1. `docs-intent`.
2. `remove-iced` (pure deletion; imp-lab stays green).
3. `node-types-not-kinds` (notation still handled inside Lab temporarily, now keyed by node type).
4. `extension-support` with a fixture extension in tests.
5. `move-notation`: piano roll into aura-editor and the pack; strip imp-lab.
6. `pack-assembly`, `workbench-tooling`, verify, Windows build.

### imp-lab

- Records: payload is node id, title, type-table ids, and node-stored column values (JSON); the graph editor reads the Imp Graphs `graph` column, an extension editor reads the column its component names.
- Webview implementations mirror the cdylib side: the extension's UI library exports implementations by id; components in `extensions.json` choose them by `implementationId` and configure them with `params`. The library contains no wiring. Host exposes pack files to the webview (asset protocol or a command returning module source) and `import()`s the library of any extension with an enabled UI component; shared deps through an import map.
- `node-type-editor` implementation shape: `{ empty, parse, summarize, history hooks, Panel }`; Panel gets a host context (services/requests/topics, per-component user state, params).

### aura-editor

- Repo becomes a bun package (no Rust workspace) depending only on Lab's published register types; nothing Iced.
- Owns the Aura pack `extensions.json` (engine extension rows moved from aura-engine, plus its own UI extension, node-type-editor and binding components) and its config checks.
- Contents: moved `piano-roll/**` with tests, an `index.ts` exporting implementations by id, build to one ESM bundle. Can grow into more than one extension (separate libraries) as pieces become independently useful.

### aura-engine

- `lab-pack/extensions.json` moves to aura-editor; the two pack-config tests move with it. Catalogs and demo project stay (used by engine tests and `demos/render-all.sh`). README / design overview updated.

### aura-workbench

- Drop `editor` service and `docker/editor/Dockerfile`.
- A pack assembly script builds the pack from aura-editor (config, UI bundle) and aura-engine (cdylibs, catalogs, demo project), for local Linux runs and the Windows export.

### Verify

- See `verify-full-suites`. Grep checks: no `iced` in imp-lab, aura-editor, aura-engine, workbench (excluding `.git`, `target`, `node_modules`, lockfiles, the word "voiced"); no notation/piano in imp-lab.
- Manual: open the Lab pack demo project in Imp Lab with the pack — graphs and notations open, Play, audition, Record work, New offers Notation; without the pack — graphs open, notations listed but not openable.

### Open choices (defaults taken unless the user says otherwise)

- **How a new project gets the Notations type.** Default: Lab doesn't add it; Aura projects (the pack's demo project / a project template in the pack) carry it in their Tome model. Alternative: a Tome-level way for an extension to contribute types, if Tome has or should have one.
- Drop the `editor` Compose service (vs. keeping it for future aura-editor Rust code).
- Delete `aura_interfaces` / `aura_ext_builtin` / `aura_ext_notation` outright.

## Commit strategy

### Baseline (plan created)

- aura-workbench: `1e098b2`, dirty — `?? .claude/` (local tool settings; exclude)
- aura-editor: clean (`624010c`)
- imp-lab: clean (`07c609d`)
- aura-engine: clean (`0cfe0ae`)
- imp-graph-view, imp-ts, imp-rs, tome-rust-server: not expected to change

### Intended commits

#### imp-lab
- Include: `Cargo.toml`, `Cargo.lock`, `crates/**`, `apps/tauri/**`, `docs/**`, `AGENTS.md`, `README.md`, `docker/Dockerfile`
- Draft message: "Open records by Tome node type instead of document kinds, let extensions register editors for node types through clientModule UI, delete the Iced graph editor crate, and move the notation editor out to aura-editor."

#### aura-editor
- Include: everything (Iced app and crates removed, extension package added, docs rewritten)
- Draft message: "Rebuild Aura Editor as an Imp Lab extension: drop Iced and provide the notation editor (piano roll, audition, recording) moved from Imp Lab."

#### aura-engine
- Include: `lab-pack/**`, `crates/aura_imp_lab_playback/**` (pack-config tests moved out), `docs/**`
- Draft message: "Hand the Aura pack configuration to aura-editor; the engine keeps supplying the pack's extension libraries and data."

#### aura-workbench
- Include: `.cursor/plans/aura_editor_on_imp_lab_e4a17c09.plan.md`, `.devcontainer/**`, `docker/**`, `scripts/**`, `.vscode/tasks.json`, `AGENTS.md`, `README.md`
- Exclude: `.claude/`
- Draft message: "Plan Aura Editor as an Imp Lab extension, drop the Iced editor image, and add the Aura Editor bundle to the Windows pack export."

### User trigger

Say **commit** (or **commit per the plan**) after review.

### As implemented

- **Extension UI libraries:** the reserved `clientModule` field was replaced by `uiLibraryPath`, mirroring `libraryPath`. A library exports `implementations` only; Lab reads it (`read_ui_library`, path confined to the pack root) and imports it from a blob URL. React, `react/jsx-runtime` and Mantine are shared on `globalThis.__impLabShared` (`packages/imp-lab-ui`), and aura-editor's Vite build rewrites those imports to that object, so the library has no imports of its own.
- **Node types:** records carry `nodeType` + `value` (the column the node type names). `lab_model::NodeType` replaces `KIND_*`; a new project only gets the Imp Graphs table. An extension node type's table (schema + hub) is added to the primary store the first time a record of it is created or saved (`ensure_node_types`). That settles "how a new project gets the Notations type".
- **Commands:** Lab offers every command to the active document's extension editor first (`EditorHost.onCommand`). `binding` components join the bundled defaults; their commands become known commands. Default bindings lost the notation keys and Space; Ctrl+N is now New graph (the pack does not rebind it).
- **User state:** `piano-roll-ui` was replaced by per-component `component:<id>` entries (piano prefs reset once).
- **Seed tool:** `--extensions <extensions.json>` maps a document's `type` to an editor's `documentType`.
- **Tests moved:** imp-lab's `loads_aura_lab_pack_when_cdylib_present` smoke test was removed (it reached into aura-engine). The engine's two pack-config tests became `aura-editor/pack/extensions.test.ts`.
- **Verification:** imp-lab `cargo test` / `cargo clippy -- -D warnings` / `cargo test -p imp_lab` / `cargo clippy -p imp_lab -- -D warnings` / `cargo check -p imp_lab`, `bun run test` (40) / `bun run build`; aura-editor `bun run test` (21) / `bun run build`; imp-graph-view `bun run test` (50); aura-engine `cargo test` all green. `cargo clippy` in aura-engine has only pre-existing warnings, in crates this plan did not touch. `clippy --all-targets` in imp-lab reports a pre-existing `items_after_test_module` in `loader.rs`. Assembled pack checked headlessly: seeding the Aura demos through it yields three Imp graphs and one Notation that keeps its id. The GUI (opening a notation, Play, audition, Record) is not yet exercised; the user still needs to run that.
- Verification used one-off `docker run --rm` containers with host mounts and a separate `CARGO_TARGET_DIR`: the running imp-lab container predates the tome-rust-server mount, and part of aura-engine's `target/` is root-owned.
- **Windows export:** `run-imp-lab-windows-build.sh` succeeded. It wrote `/mnt/e/dev/aura/imp-lab.exe` (14,116,864 bytes, 2026-11-25 07:48 UTC), `extensions.json` (from aura-editor), and `extensions/` with `aura_imp_lab_catalogs.dll`, `aura_imp_lab_playback.dll` and `aura_editor.js`. The existing `demo-project/` there was kept, as designed.
