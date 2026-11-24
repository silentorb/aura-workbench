---
name: CLAP plugin hosting
overview: "Host third-party CLAP instruments and effects as Imp node types in Aura. A protocol-neutral hosting seam turns stateful, block-streaming plugins into shared live instances for streaming mode (CLAP's native model) and render-cached samplers for deterministic mode; CLAP is the first backend behind it. Phased: both modes for offline/streaming first, then automation/per-note params, then real-time transport render-ahead, then Imp Lab UX."
todos:
  - id: docs-intent
    content: "aura-engine: scoping (docs/scoping/plugin-hosting.md) + design (docs/design/plugin-hosting.md), crate docs for aura_plugin_host / aura_clap; amend playback-modes, imp-execution, notation-synthesis Rule 1, architecture, product non-goals"
    status: completed
  - id: phase1-host-seam
    content: "Phase 1: aura_plugin_host crate — Processor trait, RenderCache (forward render + rewind), score→event scheduler, mono fold"
    status: completed
  - id: phase1-clap-backend
    content: "Phase 1: aura_clap crate on clack-host — discovery, load, instance lifecycle, process, state, latency, tail, render-offline"
    status: completed
  - id: phase1-fixture-plugin
    content: "Phase 1: aura_clap_fixture cdylib (clack-plugin) — deterministic sine synth + gain effect for tests"
    status: completed
  - id: phase1-nodes
    content: "Phase 1: aura.plugin node library (plugin_instrument, plugin_effect) + deterministic translation in aura_integration; CLI --plugin-path; demo graph"
    status: completed
  - id: phase1-streaming-stage
    content: "Phase 1: streaming PluginStage — StreamingProgram splits voice graphs at plugin nodes; shared instance fed by VoiceCommands; effects on the voice mix; per-voice fallback for plugin output feeding per-note nodes; audition/MIDI through plugins"
    status: completed
  - id: phase2-params
    content: "Phase 2: plugin parameters as embedded node data (params literal: CLAP param id → plain value), applied after state at frame 0; ProcessorFactory::params; aura plugin-params listing; fixture param"
    status: completed
  - id: phase3-realtime
    content: "Phase 3: Sampler::prepare hook; RenderCache lock-free chunked output + render-ahead worker; real-time reader thread tag (silence + underrun count on miss); translator wraps roots with plugin caches; PlaybackEngine prepares before opening the stream"
    status: completed
  - id: phase4-lab-ux
    content: "Phase 4: imp-lab generic kinds (node-literal-options, node-action, node edits topic); aura_clap plugin GUI sessions (floating + embedded window on a winit main thread), state capture on mark_dirty; Lab pack plugin list topics, Open plugin GUI action, debounced state edits"
    status: completed
  - id: verify-full-suites
    content: "Full-suite verification — After implementation, run full verify for every plan-affected repo and its direct dependents (see the project's verify matrix, typically AGENTS.md). Fix failures or get an explicit user waiver before await-commit. Reason about CI; never defer suite confidence to a future CI run."
    status: completed
  - id: windows-editor-build
    content: "Run scripts/run-imp-lab-windows-build.sh (lab-pack playback DLL links the host), report AURA_EDITOR_WIN_OUT output path, confirm success"
    status: completed
  - id: commit-await-approval
    content: "Commit (await user approval) — After full-suite verification for affected + dependents (incl. CI considered), re-run git status/diff per repo, reconcile with this strategy, commit only when the user explicitly requests it."
    status: completed
isProject: false
---

# CLAP plugin hosting

## User request

Let Aura use third-party synthesizers and effects through CLAP. Expect translation between Aura's declarative, deterministic model and CLAP's streaming model. Other protocols (VST3, …) are likely later, possibly through CLAP adapters.

In scope: hosting CLAP instruments and effects in Imp graphs, in both playback modes, plus the Imp Lab surface needed to pick and tweak plugins. Out of scope for now: other protocols (but leave room for them), out-of-process sandboxing, multichannel Aura audio.

## High-level design

### Problem

Aura and CLAP disagree about what an instrument is.

| | Aura (deterministic) | CLAP |
|---|---|---|
| Unit | Pure `at(t) → f32`, seekable, any order | Stateful object, `process(block)` forward only |
| Notes | Full score known up front, with lengths | Note-on/off events arriving in time order |
| Polyphony | One graph instance per note (Rule 1) | One plugin instance, voices inside |
| Params | Imp inputs, often time-varying signals | Param values and modulation events, block-scheduled |
| Channels | Mono | Mostly stereo |
| Reproducibility | Bit-for-bit | Whatever the plugin does (RNG, threading, version) |
| Persistence | Declarative graph data | Opaque, plugin-versioned state blob |

Three of these are hard:

1. **Seekability.** A plugin's internal DSP state can't be snapshotted (CLAP `state` saves presets, not filter history). To sample time `t` you have to have run the plugin from a known start up to `t`.
2. **Real-time pulls.** Transport playback calls `Sampler::at(t)` on the audio thread. If a plugin has to catch up there, the audio glitches.
3. **Per-note instancing in streaming.** CLAP itself is a natural fit for streaming: note-on/off map one-to-one onto CLAP note events, and block processing matches `BlockSource`. The friction is on Aura's side: `StreamingProgram` builds a fresh graph per live note, so a plugin node inside it would load one plugin per note. Streaming needs a shared stage, not a translation of the plugin.

The rest (event scheduling, latency, tails, mono folding, state storage) is plumbing, but it has to be decided once.

### Solution

**A plugin is a frozen region of the graph.** A plugin node is still an Imp node with a deterministic implementation and an optional streaming one ([playback modes](../../.mnt/aura-engine/docs/design/playback-modes.md)). Its deterministic implementation is a **render cache**: a sampler that owns the plugin instance and renders forward, block by block, into a retained buffer. `at(t)` reads from the buffer.

- Sampling ahead of what's rendered renders more blocks first. Sampling behind the retained range resets the plugin (deactivate/activate, reload state) and re-renders from `t = 0`. Within one translation the whole render is kept, so out-of-order and repeated sampling cost nothing after the first pass.
- Upstream inputs stay pure. An effect's audio input and any automated params are ordinary Aura samplers that the cache pulls over each block's frame range. Seeking never needs anything upstream to be stateful.
- **Look-ahead is a win, not a cost.** Because the score is fully known, Aura sends each note-on/off at its exact sample offset, adds the plugin's reported latency before the first block, and renders the reported tail past the last note. Deterministic output is latency-compensated for free, which a streaming host can't do.
- Plugins render with CLAP's offline render mode where they support it. That lets them use their best quality and stops them from dropping work to keep up in real time.

**Instruments consume scores, not notes.** A plugin instrument node takes a `score` input, like `poly_sine_score`. The plugin does the polyphony itself. This is a deliberate exception to Rule 1 ("by default, each note is a distinct instance"). The rule's intent, per-note parameters, carries over through CLAP's per-note modulation and note expressions: a note's `NoteParams` (for example `cutoff_mult`) become per-note-id modulation of a mapped plugin parameter. Velocity maps to note-on velocity.

**Node types come from scanning.** Aura scans the standard CLAP paths (plus `CLAP_PATH` and a configured list) and generates a node type for each installed plugin, with one optional input port per plugin parameter. Imp's registry, typing, and node picker then work unchanged. An unwired param port keeps the value from the stored state. A wired one is automated from its signal at a control rate (a fixed small block, events sent only on change). Two generic node types, `plugin_instrument` and `plugin_effect` (selected by plugin id, no param ports), cover the first phase and plugins that haven't been scanned.

**The declarative record of a plugin node** is: plugin id, the plugin version it was saved with, the state blob (as a node asset or base64 literal), and any wired params. Aura treats the blob as opaque. A version mismatch at load is a warning, not an error. A missing plugin is a translation error that names the plugin id.

**Streaming mode shares one instance, with almost no translation.** Streaming is CLAP's native model, so here the plugin runs essentially as-is: a shared `PluginStage` (a `BlockSource`) holding one instance, fed note-on/off straight from the `VoiceCommand`s that drive `VoiceMixer`. Audition and live MIDI go through real third-party synths from Phase 1. What Aura does supply is the graph split, decided once in `StreamingProgram`:

- **Instrument on the score** (`notation → plugin_instrument → … → output`): nothing is per-note. Commands become events and the stage is the whole voice. This is the common case.
- **Effect on Aura voices** (`per-note DSP → plugin_effect → output`): everything upstream of the effect's audio input stays per-note in `VoiceMixer`, the mix feeds the effect, and the effect runs once. Plugin stages can chain.
- **Plugin output feeding per-note nodes** (for example, a plugin times a per-note envelope): one shared instance can't be per-note. This case falls back to one plugin instance per voice, which is costly but correct, so streaming still never fails because of the mode.

This is a streaming implementation in the existing sense: same declarative data, different evaluation, chosen at translation.

**Real-time transport needs preparation.** Before `PlaybackEngine::start_at(t)`, the host prepares the graph's plugin caches: it renders from 0 to `t` plus a margin on a worker thread, then a render-ahead worker stays ahead of the playhead while the audio thread only reads. If the worker falls behind, the audio thread outputs silence for that block instead of blocking, and an underrun is reported. Imp Lab shows a brief "preparing" state on play.

**A protocol-neutral seam, CLAP first.** All of the above (render cache, event scheduling from scores, automation sampling, latency/tail, mono folding, the shared streaming stage) is written against a small `Processor` trait in a new `aura_plugin_host` crate. CLAP is one backend in `aura_clap`. A later VST3 (or LV2) backend implements the same trait directly. Mature VST3-inside-a-CLAP-host adapters don't appear to exist (adapters like clap-wrapper go the other way), so the design shouldn't depend on one. A CLAP-wrapped plugin would still work automatically, since it's just a CLAP plugin.

**Channels.** Aura is mono end to end. v1 folds the plugin's main output to mono (average of channels) and feeds mono input by duplicating to all input channels. Stereo Aura is a separate, larger effort; the `Processor` trait carries channel counts, so it isn't foreclosed.

**Imp Lab.** A plugin browser (scan results in the existing node picker), opening the plugin's own GUI in a floating window (CLAP `gui`), and capturing a new state blob into the node when the plugin marks its state dirty. The GUI runs on the main thread owned by the Lab pack's playback extension. On Windows this is routine. In the WSL dev container, X11 plugin GUIs may or may not show.

**Crate placement.**

| Crate | Owns |
|---|---|
| `aura_plugin_host` (new) | `Processor` trait, render cache, score→event scheduling, automation sampling, mono fold, shared streaming stage. No protocol code, no Imp. |
| `aura_clap` (new) | CLAP backend on `clack-host`: discovery, loading, main/audio-thread lifecycle, process, params, state, latency, tail, render mode, GUI. |
| `aura_imp` | `aura.plugin` node library (generic types) and the generator for per-plugin node types. |
| `aura_integration` | Translation of plugin nodes in both modes; scan/registry wiring for hosts. |
| `aura_render` / `aura_io_cpal` | A prepare / render-ahead hook for transport playback. |
| `aura_imp_lab_playback` + imp-lab | Browser, GUI windows, state capture. |

## Objective analysis

### Pros

- It's the biggest available expansion of Aura's sound palette. Mature synths and effects (Surge XT, Vital-class wavetable synths, commercial reverbs and compressors) become usable without Aura reimplementing them.
- The deterministic model gets a real advantage over DAWs: exact note timing, automatic latency compensation, and offline-quality rendering, all from look-ahead Aura already has.
- It fits existing concepts: a node type with deterministic plus streaming implementations, chosen at translation. No mode flags at sample time, no new graph semantics.
- The protocol-neutral seam keeps VST3 or LV2 a backend swap rather than a redesign, and doesn't bet on adapters that don't exist.

### Cons

- **Determinism weakens.** "Bit-for-bit reproducible" becomes "as reproducible as the plugins in the graph". Plugins with unseeded randomness, background threads, or a different installed version will render differently. Design docs have to say this outright. Aura's tests can only assert determinism with the fixture plugin.
- **Seeking costs time.** Rewinding past the cache, or starting transport late in a long song, re-renders from 0. Heavy plugins over long songs mean seconds of "preparing" on play. Checkpointing isn't possible in general. Silence points (resetting the plugin where the score is silent and the tail has ended) could later bound the cost, with a small fidelity risk.
- **Rule 1 and the streaming voice model bend.** A plugin instrument is one shared polyphonic instance, and `StreamingProgram` gains a graph split instead of instantiating whole voice graphs per note. Per-note params survive only to the extent the plugin supports per-note modulation or expressions. Many plugins support neither, and then `NoteParams` can't reach them.
- **Memory.** The cache keeps whole renders: about 11 MB per plugin node per minute of mono f32 at 48 kHz. That's fine for songs, but it adds up with many plugin nodes. A bounded window plus rewind is the fallback.
- **Stability and trust.** In-process plugins can crash or hang Imp Lab and run arbitrary native code. Sandboxing (out-of-process) is deferred, not solved.
- **Mono.** Stereo instruments and effects lose their width. Reverbs and choruses especially will sound wrong until Aura has multichannel.
- **Dependency risk.** `clack-host` is the only real Rust CLAP host library. It's low-level and has historically been consumed from git; check its current release status before depending on it. `clap-sys` is the fallback.
- **Dev environment.** Most commercial CLAP plugins are Windows/macOS. In WSL, testing uses the fixture plugin and Linux builds such as Surge XT. Real listening happens on the Windows export, as with CPAL today.

### Worth doing

Yes, but stage it, and treat mono and determinism as stated limits rather than surprises.

- **Phases 1–2 (both modes, automation, per-note params) carry most of the value and almost all the design risk.** Streaming is the cheaper half and is audible on the Windows export immediately. Deterministic WAV output is testable headlessly in WSL, and streaming stages are testable by pulling blocks into a buffer. Approve and build these first.
- **Phase 3 (deterministic transport render-ahead)** should start only after phase 1 shows real render costs on real plugins.
- **Phase 4 (Lab UX)** is needed to be useful day to day, because nobody wants to author state blobs by hand. It's mostly imp-lab work and can overlap phase 3.
- **Stereo** will likely be the first thing that sounds wrong with real effects. Expect a multichannel-Aura plan soon after phase 1, rather than treating mono as permanent.
- Don't plan around "VST3 via CLAP adapters". Plan around the `Processor` seam.

## Low-level design

Phase 1 is specified in full. Later phases are outlined here and get their own detailed plan updates when they start.

### Docs (first, per aura-engine AGENTS durable-intent rule)

- `docs/scoping/plugin-hosting.md`: motivation (third-party palette), the model mismatch table, VST3-later intent, the decision against relying on adapters.
- `docs/design/plugin-hosting.md`: requirements. Render-cache semantics, a declared reproducibility caveat, the score-consumer exception to Rule 1, the declarative record (id, version, state, params), the mono fold, the missing-plugin error, the version-mismatch warning, in-process hosting as the current limit. Avoided approaches: plugins per note in streaming (except the documented fallback), blocking catch-up on the audio thread, depending on VST3→CLAP adapters.
- Amend `design/playback-modes.md` (plugin streaming stage row; shared-instance exception), `design/imp-execution.md` (render-cached nodes are referentially transparent per translation but not stateless; seekability via rewind), `design/notation-synthesis.md` Rule 1 (score-consumer exception), `design/architecture.md` (crate table and audio stack), `design/product.md` (Rendering bullet on plugins).
- `docs/crates/aura_plugin_host/{design/overview.md,scoping/motivation.md}` and the same for `aura_clap`. Add rows to the AGENTS.md crate docs table.

### `aura_plugin_host` (new crate)

- `Processor` trait (audio-thread object, `Send`): `activate(sample_rate, max_block) -> Result`, `reset()`, `process(&mut self, inputs: &[&[f32]], outputs: &mut [&mut [f32]], events: &[Event]) -> ProcessStatus`, `latency_frames()`, `tail_frames() -> Option<u64>`, `channel_layout()`.
- `Event`: `NoteOn { frame, note_id, key, velocity }`, `NoteOff { frame, note_id, key }`, `Param { frame, param_id, value }`, `ParamMod { frame, param_id, note_id: Option, amount }`.
- `ProcessorFactory`: creates a fresh activated `Processor` with state applied. Used for rewinds and for per-translation instances.
- `schedule_score_events(&NoteSchedule-like input, sample_rate) -> Vec<Event>`, sorted by frame, with stable note_ids by score order. Takes `aura_sequencing` types, not `aura_integration`'s `NoteSchedule`. If needed, move the minimal schedule into `aura_scheduler` or take plain `(start_secs, duration_secs, key, velocity, params)` rows.
- `RenderCache` implements `aura_render::Sampler`: `Mutex<CacheState { processor, rendered: Vec<f32>, next_frame, events_cursor }>`, block size 256. `at(t)`: frame = round(t·sr) (linear interpolation when t is off-grid); if frame ≥ rendered.len(), render blocks until covered; if a rewind is needed (bounded mode only), recreate through the factory. Latency: pre-roll `latency_frames` and drop them from the head. Tail: after the last event, render until `tail_frames` (cap 30 s), or until quiet for 0.25 s when the tail is unknown or infinite.
- Mono fold for outputs; duplicate for inputs.
- Unit tests with an in-crate fake `Processor` (counter or sine): out-of-order `at` equals sequential, latency is compensated, tail rendered, rewind is exact.

### `aura_clap` (new crate)

- Dependency: `clack-host` (+ `clack-extensions` for params/state/latency/tail/render/note-ports/audio-ports). Pin the version, or the git rev if it's still unreleased. Check this first.
- `discover(paths) -> Vec<PluginDescriptor { id, name, vendor, version, features, bundle_path }>`: standard paths per OS (Linux `~/.clap`, `/usr/lib/clap`; Windows `%COMMONPROGRAMFILES%\CLAP`, `%LOCALAPPDATA%\Programs\Common\CLAP`; plus `CLAP_PATH`).
- `ClapFactory` implements `ProcessorFactory`: loads the bundle once (`Arc` entry), instantiates, applies the state blob, sets render mode offline when deterministic, activates, then start_processing. The main-thread vs audio-thread split follows clack's types. In deterministic offline rendering the calling thread acts as both, which is permitted for offline hosts. Document the rationale in code.
- `ClapProcessor` implements `Processor`: converts `Event` to CLAP input events, sets up audio port buffers, and maps the CLAP status.
- Host callbacks: `request_restart` / `request_process` / `request_callback` are recorded and serviced on the owning thread; log output goes through `log`.
- Errors per `docs/rust-style.md#errors` (`thiserror`): `BundleLoad`, `PluginNotFound { id }`, `Instantiate`, `Activate`, `StateLoad`.

### `aura_clap_fixture` (new cdylib, test-only, `publish = false`)

- Built with `clack-plugin`. Exports two plugins: `aura.fixture.sine` (deterministic polyphonic sine, note-id aware, honours velocity, 64-frame latency, 0.1 s release tail) and `aura.fixture.gain` (stereo gain, one param).
- Tests in `aura_clap` build it (cargo builds workspace cdylibs) and load it from `target/<profile>/`. Locate it with `env!("CARGO_TARGET_DIR")` or a build.rs helper.

### Nodes and translation

- `aura_imp`: new `aura.plugin` library (`crates/aura_imp/src/plugin.rs` + registration in `registry.rs`). Two node types:
  - `plugin_instrument`: inputs `score: score`, `plugin: string` literal, `state: string` literal (optional, base64); output `value: signal`.
  - `plugin_effect`: inputs `input: signal`, `plugin`, `state`; output `value: signal`.
- `aura_integration/src/translate/mod.rs`: add match arms that resolve inputs and look up the factory through a new `TranslateOptions.plugins: Option<&dyn PluginResolver>` (trait in `aura_plugin_host`; the CLAP implementation lives in `aura_clap`; `aura_integration` depends on both). A missing resolver or plugin gives `TranslateError::PluginUnavailable { node, plugin }`.
### Streaming stage (phase 1)

- `aura_plugin_host::PluginStage: BlockSource`: holds one `Processor` (activated with real-time render mode), an optional input `BlockSource`, and a lock-free command queue. Converts `VoiceCommand::{NoteOn, NoteOff, AllOff}` into `Event`s at block-relative frame 0 (or a timestamp offset if commands carry one). Mono fold/dup as in deterministic. No allocation on the audio thread; event buffers are preallocated.
- `aura_integration/src/translate/streaming.rs`: `StreamingProgram::prepare` classifies plugin nodes:
  - the score input traces to the notation node and the plugin output doesn't feed live-note-dependent nodes → **shared**;
  - otherwise → **per-voice fallback** (the plugin node is translated per instance, using a streaming `Processor`-backed sampler stepping forward).
- For shared plugins, the prepared program becomes a small block pipeline: the `VoiceMixer` of the per-note subgraph (if any, feeding a `plugin_effect` input) → plugin stages in topological order → the remaining mode-agnostic nodes downstream, sampled at voice-free stage time. Expose it as one `BlockSource`, so `StreamingOutput` and `aura_imp_lab_playback` audition/MIDI need no changes beyond constructing it.
- Tests: the fixture sine stage plays note-on → non-silent blocks, note-off → tail → silence; effect-on-voices graph sums before the gain; the fallback path translates and renders.
- `aura_cli`: `--plugin-path <dir>` (repeatable). `aura plugins` lists discovered descriptors.
- `demos/demo-03-plugin.json`: arpeggio into `plugin_instrument` (fixture sine) into `plugin_effect` (fixture gain). Add it to `render-all.sh` only if it can locate the fixture build. Otherwise keep it as a test fixture graph.
- Integration tests: render the demo graph twice and get bit-identical output. Sparse `at(t)` equals the sequential pass. Note onsets land on exact frames (± latency compensation verified against the fixture's 64 frames).

### Phase 2 (as decided at start: parameters are embedded node data, not ports)

User decision: keep it simple. Support soft synths with their parameters as embedded node data; plugin nodes keep only generic inputs (`score`, `audio`), nothing plugin-specific. Wired parameter values, when they come, are **plain values** (the plugin's own units, clamped to range).

- `plugin_instrument` / `plugin_effect` gain a `params` literal: a JSON object string mapping CLAP parameter id (decimal) to plain value, e.g. `{"0": 0.4}`. Empty means none.
- Applied after the stored `state`: values override it. Delivered as parameter-value events at frame 0 of the first processed block (every plugin must handle those). Values are clamped to the parameter's range. Unknown or read-only ids fail translation with the node and id.
- Seam: `PluginResolver::resolve(id, &PluginSettings { state, params })`; `ProcessorFactory::params()` returns `ParamDescription`s (id, name, module, min, max, default, flags).
- CLAP: params extension on the host side (info, validation, `ParamValueEvent`s); host declares a no-op `HostParams` for compatibility.
- CLI: `aura plugin-params <plugin-id> [--plugin-path PATH]...` lists a plugin's parameters (id, name, module, range, default, flags), so ids can be authored.
- Fixture: `aura.fixture.sine` gains a `level` parameter (id 0, 0–1, default 0.25).
- Deferred (not in Phase 2): parameter ports and signal automation, per-note parameters (`NoteParams` → per-note modulation), generated per-plugin node types.

### Phase 3 (render-ahead for transport playback)

- `aura_render`: `Sampler::prepare(start_secs, ahead_secs)` (default no-op) and `Sampler::underruns()` (default 0). A thread-local real-time reader tag: `mark_realtime_reader()` / `is_realtime_reader()`.
- `aura_io_cpal::PlaybackEngine::start_at` calls `prepare(start, PREPARE_AHEAD_SECS)` on the calling (control) thread before opening the device; its audio callback marks itself a real-time reader. `StreamingOutput` does not (streaming voices render inline, as before).
- `RenderCache`: output in append-only chunks of atomics (`len` published with release/acquire), so reads never wait on rendering. The plugin and its event state stay behind a mutex used only by renderers. `at(t)` from a real-time reader returns silence for an unrendered frame and counts an underrun; any other reader renders inline as before (offline export, chained plugins, streaming voices). `prepare` renders synchronously to `start + ahead`, then starts one worker thread (per cache, once) that keeps `ahead` past the furthest real-time read; the worker holds a weak reference and exits when the cache is dropped or finished.
- Translator: plugin caches are shared (`Arc`); translation collects them, and a graph with any wraps its root in a sampler whose `prepare`/`underruns` reach every cache. Other samplers are untouched.
- Deterministic output is unchanged: the same frames render in the same order whichever thread renders them.
- Not in scope: reusing renders across plays, Lab 'preparing' UI (a play request just takes longer to return), choosing real-time render mode for transport.

### Phase 4 (Imp Lab plugin UX)

User decisions: generic declared Lab kinds (Lab stays protocol-agnostic); GUI edits reach the graph live, merged into one undo step per GUI session; the sound changes on the next note / next Play (the GUI edits its own instance).

**imp-lab (generic, no Aura or CLAP knowledge)** in `imp_lab_extensions` + the Tauri app:
- `node-literal-options`: `params { nodeType, port, optionsTopic }`. Properties draws that literal as a searchable dropdown of the topic's `[{value, label}]` (an unknown current value stays listed).
- `node-action`: `label`; `params { nodeType, serviceId, action, editsTopic?, order }`. Properties shows a button for nodes of that type; clicking sends `service_request {type: "node_action", action, node: {id, type, inputs}}`; an error reply (`{error}`) shows inline.
- Node edits: an action's `editsTopic` carries `{seq, session, node, inputs}`; Lab applies each new `seq` to the open graph holding `node` (`null` removes a literal), coalescing one `session` into one undo step.
- Tauri `get_node_ui` returns the declarations; tests for parsing and edit application.

**aura_clap**
- Plugin GUI sessions (`ClapHost::open_editor`): instantiate on the CLAP main thread with the node's settings, prefer embedding in a host window (winit, created on the CLAP main thread), else the plugin's floating window. Host `gui` (resize / closed) and `state` (`mark_dirty`) extensions. On `mark_dirty`, save state (debounced 300 ms) and call the session's listener; final save when the window closes.
- The CLAP main thread runs a winit event loop when a display is available (`with_any_thread`; pumps Win32 messages) and the current headless loop otherwise. Embedding needs the winit loop; floating works either way.
- Fixture: `aura.fixture.gain` gains a floating fake GUI and a test hook that simulates a GUI edit (set gain + `mark_dirty`).

**aura_imp_lab_playback + lab-pack**
- Publishes `aura.plugins.instruments` / `aura.plugins.effects` options (scanned off the startup path).
- Answers `node_action` `plugin.open_gui`; publishes `aura.plugins.edits` with `inputs {state: base64, params: null}` (state now holds every parameter).
- `extensions.json`: two `node-literal-options` rows (instrument and effect `plugin`) and two `node-action` rows (Open plugin GUI).

**Verification limits:** headless tests cover the floating path and state capture; embedded windows and real plugin GUIs are verified on the Windows export only.

### Verification

- aura-engine: `cargo test`, `cargo clippy` (engine service); `demos/render-all.sh` if demos change.
- Phase 4: imp-lab desktop build + `cargo check -p imp_lab`; Windows export.

## Commit strategy

### Baseline (plan created)

- aura-workbench: dirty, with only `?? .claude/` (local Claude settings; unrelated, exclude). This plan file is new.
- aura-engine: clean at `9434ee4`.
- imp-lab: clean at `624b1bb` (affected in phase 4 only).

### Intended commits

#### aura-workbench

- Include: `.cursor/plans/clap_plugin_hosting_7c2e91a4.plan.md`
- Exclude: `.claude/`
- Draft message: "Plan CLAP plugin hosting for Aura behind a protocol-neutral seam, staged from offline deterministic rendering to live playback."

#### aura-engine

- Include (phase 1, as built): new crates `crates/aura_plugin_host/`, `crates/aura_clap/`, `crates/aura_clap_fixture/`; `crates/aura_imp/src/{plugin.rs,lib.rs,registry.rs}`; `crates/aura_integration/` (`Cargo.toml`, `src/lib.rs`, `src/tome_source.rs`, `src/translate/{mod.rs,streaming.rs,plugin.rs}`); `crates/aura_cli/` (`Cargo.toml`, `src/main.rs`); `crates/aura_imp_lab_catalogs/src/lib.rs`; `crates/aura_imp_lab_playback/` (`Cargo.toml`, `src/lib.rs`, `src/audition.rs`); `Cargo.toml`, `Cargo.lock`; `demos/demo-03-plugin.json`, `demos/render-all.sh`; `AGENTS.md`; `lab-pack/README.md`; docs (`docs/scoping/plugin-hosting.md`, `docs/design/plugin-hosting.md`, `docs/crates/aura_plugin_host/`, `docs/crates/aura_clap/`, and edits to `docs/design/{README,architecture,imp-execution,notation-synthesis,playback-modes,product}.md`, `docs/scoping/README.md`, `docs/crates/{README.md,aura_cli,aura_imp,aura_integration}`).
- Exclude: `output/`, `target/`
- Draft message (phase 1): "Host CLAP instruments and effects as render-cached Imp nodes so deterministic renders can use third-party plugins, with exact note timing and latency compensation from the known score."

#### imp-lab (phase 4)

- Include: plugin browser / GUI / state capture changes.
- Draft message: TBD at phase 4.

#### Phase 2 commits
- aura-engine (baseline clean at `8cd166d`): `crates/aura_plugin_host/src/lib.rs`, `crates/aura_clap/{Cargo.toml,src/host.rs,src/lib.rs,src/processor.rs,src/tests.rs}`, `crates/aura_clap_fixture/{Cargo.toml,src/lib.rs}`, `crates/aura_imp/src/plugin.rs`, `crates/aura_integration/src/translate/{mod.rs,plugin.rs}`, `crates/aura_cli/{Cargo.toml,src/main.rs}`, `Cargo.lock`, `demos/demo-03-plugin.json`, docs (`design/plugin-hosting.md`, `scoping/plugin-hosting.md`, `crates/{aura_plugin_host,aura_clap,aura_imp,aura_cli}/design/overview.md`), `lab-pack/README.md`. Draft message: "Configure plugins entirely from embedded node data: parameter values in plain units applied over the saved state from the first frame, with a CLI listing of plugin parameters, and no plugin-specific ports."
- aura-workbench: this plan file. Draft message: "Record the Phase 2 decision to configure plugins by embedded node data instead of parameter ports."

#### Phase 3 commits
- aura-engine (baseline clean at `d5a5c5e`): `crates/aura_render/src/lib.rs`, `crates/aura_io_cpal/src/lib.rs`, `crates/aura_plugin_host/src/cache.rs`, `crates/aura_integration/src/translate/{mod.rs,plugin.rs,streaming.rs}`, docs (`design/{plugin-hosting,architecture}.md`, `scoping/plugin-hosting.md`, `crates/{aura_render,aura_io_cpal,aura_plugin_host}/design/overview.md`). Draft message: "Render plugins ahead of transport playback so the audio thread only reads: samplers prepare before the device opens, a background worker keeps two seconds ahead, and real-time reads of anything unrendered are silent and counted instead of blocking."
- aura-workbench: this plan file. Draft message: "Record Phase 3 of CLAP hosting: render-ahead for transport playback."

#### Phase 4 commits
- imp-lab (baseline clean at `624b1bb`): `crates/imp_lab_extensions/src/{config.rs,settings.rs,lib.rs,node_ui.rs}`, `apps/tauri/src-tauri/src/{extensions.rs,lib.rs}`, `apps/tauri/src/{App.tsx,nodeUi.ts,nodeUi.test.ts,NodeUiControls.tsx}`, `apps/tauri/package.json`, `docs/features/extensions.md`, `AGENTS.md`. Draft message: "Let extensions give node types UI in Properties: literal dropdowns fed by topics, action buttons that send a service request, and service edits of node literals applied as one undo step per session."
- aura-engine (baseline clean at `9f70957`): `crates/aura_clap/` (`Cargo.toml`, `src/{lib.rs,host.rs,main_thread.rs,windowing.rs,editor.rs,processor.rs,tests.rs}`), `crates/aura_clap_fixture/{Cargo.toml,src/lib.rs}`, `crates/aura_plugin_host/src/lib.rs`, `crates/aura_integration/src/{lib.rs,translate/mod.rs,translate/plugin.rs}`, `crates/aura_imp_lab_playback/{Cargo.toml,src/lib.rs,src/plugins.rs}`, `lab-pack/{extensions.json,README.md}`, `Cargo.toml`, `Cargo.lock`, docs (`design/plugin-hosting.md`, `scoping/plugin-hosting.md`, `crates/aura_clap/design/overview.md`). Draft message: "Choose and edit plugins in Imp Lab: installed plugins as node dropdowns, and each plugin's own GUI opened from Properties on the CLAP main thread's window loop, with its edits saved into the node's state."
- aura-workbench: this plan file. Draft message: "Record Phase 4 of CLAP hosting: plugin choice and GUI editing in Imp Lab."

### User trigger

Say **commit** (or **commit per the plan**) after review.

Sources consulted for dependency/adapter status: [clack-host docs](https://docs.rs/clack-host), [Clack repo](https://www.github.com/prokopyl/clack), [clap-wrapper](https://awesome.ecosyste.ms/projects/github.com%2Ffree-audio%2Fclap-wrapper), [KVR thread on VST3→CLAP host wrappers](https://www.kvraudio.com/forum/viewtopic.php?p=9189650).
