---
name: Block processing
overview: "Replace Aura's per-sample pull model (nested `Sampler::at(t)` closures) with block evaluation: a translated graph renders a requested frame range into buffers, node by node, with each node output computed once per range and shared by all consumers. Nodes may now keep state. In deterministic mode state is nonessential — a node rendered at any range, in any order, from a fresh or a used instance returns bit-identical output — so deterministic graphs stay seekable without pre-roll. In streaming mode state may carry history (true IIR filters, phase accumulators). Plugins remain the one deterministic node whose state is essential internally; their output retention keeps the external contract. This retires the plugin RenderCache's atomic sample store, interpolation and real-time-reader mode, per-cache render-ahead workers, fan-out duplication of shared subgraphs, and per-frame virtual dispatch on the audio thread. Node DSP is not changed in this plan."
todos:
  - id: docs-intent
    content: "aura-engine: scoping (docs/scoping/block-processing.md: why per-sample pull was outgrown, the workarounds it caused, the user's rule on state); design: rewrite imp-execution.md (frame-indexed denotation, block ranges, input windows, nonessential deterministic state, streaming history state, plugins as the retained exception), amend playback-modes.md (per-sample state open question resolved: streaming implementations may hold history), plugin-hosting.md (plugin node = block node with retention; render-ahead moves to the transport renderer), audio-layouts.md (planar channel buffers; dual mono of stateful nodes = one instance per channel), architecture.md, aura_render / aura_plugin_host / aura_io_cpal / aura_integration crate overviews"
    status: completed
  - id: baseline-hashes
    content: "Before any code change: run demos/render-all.sh and record sha256 of every output/*.wav, plus WAV renders of the stereo and plugin integration fixtures, into the scratchpad as the bit-identity reference"
    status: completed
  - id: render-core
    content: "aura_render: Frame, Range and BlockCtx; Node trait (render a range into planar outputs, requesting inputs by range through the ctx; reset); Program (nodes in post-order, per-output range memo so fan-out computes once) and Renderer (render any range, default BLOCK_FRAMES chunks; deterministic programs have no cursor and no pre-roll); offline render on top"
    status: completed
  - id: translator-program
    content: "aura_integration: translation builds a Program instead of nested samplers, memoizing (node, output port, channel pass) so each output is built once (fixes fan-out duplication). impls.rs build closures return node outputs (Signal/Stereo handles) instead of boxed samplers; translate-time values unchanged. Dual mono: one node instance per channel. Remove SharedSampler/ChannelView/StereoPair/remembered channel passes"
    status: completed
  - id: nodes-port
    content: "Port every registered node type to block nodes that compute the same per-frame values (same f64 time expression). Use nonessential state only where it reproduces bit-identical output (e.g. note-schedule cursors replacing per-frame lookups, resynced when a range is not contiguous). No DSP changes; highpass_noise and sweeps keep their formulas"
    status: completed
  - id: plugin-node
    content: "aura_plugin_host: plugin instrument/effect as a block node that renders the plugin forward on its own fixed BLOCK_FRAMES grid from frame 0 into frame-aligned retained output (plain Vec, owned by the rendering thread), requests its upstream input by those grid ranges, and answers any range from retention. Keep exact note frames, latency removal, tail/finish. Delete RenderCache's atomic chunk store, interpolation, realtime-reader reads, prepare/underruns and render-ahead worker"
    status: completed
  - id: sinks
    content: "Transport: PlaybackEngine runs the Renderer on one background thread into a preallocated SPSC ring kept PREPARE_AHEAD_SECS ahead; cpal callback only copies (silence + underrun count when empty); seek = restart rendering at the target (no pre-roll; plugins answer from retention). Remove Sampler::prepare/underruns, mark_realtime_reader/is_realtime_reader, PreparedRoot. WAV writes from renderer ranges. Streaming: StreamVoice renders its voice Program in consecutive blocks; VoiceMixer/PluginStage BlockSource chain unchanged"
    status: completed
  - id: consumers
    content: "aura_cli, aura_imp_lab_playback (transport, recording click mix, audition, tests) and aura_clap tests move from at(t)/frame(t) to range rendering (spot reads in tests through a helper). aura-editor (Iced) is ignored"
    status: completed
  - id: tests
    content: "Generic deterministic-contract test over every registered deterministic cell (mono and stereo) with fixed inputs: one long range vs uneven chunks vs shuffled ranges vs fresh instance per range → bit-identical. Plus: fan-out builds a shared node once (incl. one plugin instance), input windows (look-back) correct at frame 0 and across chunks, plugin seek answers from retention identically, transport ring underrun counted not blocking, streaming voice renders contiguously"
    status: completed
  - id: demos-identity
    content: "Run demos/render-all.sh; every output/*.wav sha256 must equal the baseline (any diff is a bug to explain or fix, not to accept silently). Leave output/ current"
    status: completed
  - id: verify-full-suites
    content: "Full-suite verification — After implementation, run full verify for every plan-affected repo and its direct dependents (see the project's verify matrix, typically AGENTS.md). Fix failures or get an explicit user waiver before await-commit. Reason about CI; never defer suite confidence to a future CI run."
    status: completed
  - id: windows-editor-build
    content: "Run scripts/run-imp-lab-windows-build.sh (Lab pack playback DLL changes), report AURA_EDITOR_WIN_OUT output path, confirm success"
    status: completed
  - id: commit-await-approval
    content: "Commit (await user approval) — After full-suite verification for affected + dependents (incl. CI considered), re-run git status/diff per repo, reconcile with this strategy, commit only when the user explicitly requests it."
    status: completed
isProject: false
---

# Block processing

## User request

Change Aura's signal processing from single samples to blocks. The per-sample model should probably have been replaced a while ago, and some workarounds likely exist only because there was no buffered processing; find them and retire them as part of the change.

Decisions from review:

- **Remove the stateless-node restriction.** Nodes may keep state.
- **Deterministic mode: state is nonessential.** A node must still be able to sample anywhere in time, independent of its state, and return the same result.
- **Streaming mode may depend on historical state.**
- **Ignore the Iced editor.**

In scope: the engine runtime (both modes), translation, plugin hosting, sinks (WAV, transport, live voices) and engine-side consumers (CLI, the Imp Lab playback extension). Out of scope: changing what any node computes. New stateful DSP (streaming IIR filters, phase accumulators) and control-rate signals become possible here but are follow-ups.

## High-level design

### Problem

Today a translated graph is a tree of nested closures, and everything is asked for one sample at a time: `Sampler::at(t) -> f32` (and `StereoSampler::frame(t)`), with `t` in `f64` seconds, through `&self` (no state). The design chose this for its semantics — pure, seekable, deterministic — and deferred block batching. The semantics held up; the execution model has been worked around repeatedly:

| Workaround | Why it exists |
|---|---|
| **Plugin `RenderCache`** (≈800 lines): renders a plugin forward into a retained, append-only store of atomics (up to ~3.4 h), then answers `at(t)` by lookup with linear interpolation off the frame grid. Input audio is pulled into each plugin block one `at()` call per frame. | Plugins are block-and-state by nature; the only way to fit them into `at(&self, t)` was a lock-free lookup table. |
| **Real-time reader flag + render-ahead workers + underruns** (`mark_realtime_reader`, `Sampler::prepare`, `Sampler::underruns`, `PreparedRoot`, one worker thread per cache) | The transport audio callback evaluates the whole tree per frame; a plugin read could block there. |
| **Fan-out re-translation.** `translate_node` has no memo: a node feeding two consumers is translated twice — two copies of the subgraph, evaluated twice per sample, and two plugin instances if a plugin sits there. | Nested closures own their inputs; there is no shared buffer. |
| **Channel plumbing** (`ChannelView`, `StereoPair`, `SharedSampler`, `StereoSampler::channel` override, dual-mono "remembered" passes) | Per-frame stereo reads compute both channels; these avoid computing the unneeded one and share dual-mono inputs. |
| **Stateless DSP approximations**: `highpass_noise` = `noise(t) − noise(t − dt)`; closed-form sweep phase; open question "phase accumulators and recursive filters need per-sample state" | No node may keep state, in either mode. |
| **Per-frame virtual dispatch on the audio thread** in `PlaybackEngine` | Same model, used live. |

### Solution

**1. Ranges, not samples.** A translated graph renders a requested **range of frames** into buffers. Time is indexed by integer frame at the render's sample rate; the `time` signal is still seconds, computed per frame exactly as today so output is bit-identical. Mono is one buffer, stereo two (planar). Scores, progressions and tempo remain translate-time values.

**2. One output, computed once, shared.** Translation builds each node output once and wires every consumer to it, so fan-out costs nothing extra and a plugin feeding two consumers is one instance. Within a render, a node's output for a range is computed once no matter how many consumers ask.

**3. Two rules for state, one per mode.** Nodes may now hold mutable state in both modes, under different contracts:

| | Deterministic | Streaming |
|---|---|---|
| State | Allowed, **nonessential**: a cache or a shortcut | Allowed, **essential**: history (filter memory, oscillator phase) |
| Contract | Rendering any range, in any order, from a fresh or a used instance, gives bit-identical output | Ranges arrive contiguously, forward only |
| Seeking | Free; nothing to pre-roll | Never happens |
| Example | A note-schedule cursor that skips the per-frame search when ranges are contiguous and re-searches when they jump | A one-pole filter, a phase accumulator (follow-up work) |

So deterministic mode keeps exactly the property it has today — seekable, order-independent, reproducible — and gains speed; streaming mode gains the stateful DSP it was missing. This fits the existing implementation matrix: a node type that wants a history-dependent algorithm provides it as its **streaming** implementation, and its deterministic implementation stays history-free.

The contract is checked generically: a test renders every registered deterministic implementation over one range, over uneven chunks, over shuffled ranges and from fresh instances, and requires identical bits.

**4. Deterministic nodes may look around in time.** Because upstream deterministic signals are history-free, a node can ask for its input over a different range than the one it is producing (e.g. a few frames earlier for a FIR-style look-back, or the plugin's own block grid). This keeps the existing "deterministic may look into the past and future" freedom instead of losing it to a push-only block schedule. Unbounded look-back (a true recursive filter) is by definition history; it belongs in streaming.

**5. Plugins are the bounded exception.** A plugin's state is essential and cannot be snapshotted, so it cannot satisfy the rule by itself. As today, the plugin node renders forward from frame 0 on its own fixed block grid and **retains** what it rendered, then answers any requested range from retention. Externally it meets the deterministic contract (same output for any range, any order, within a translation); internally it is the one place where pre-roll happens, exactly as now. What changes is the machinery: plain frame-aligned buffers owned by the rendering thread, input pulled by range, no interpolation, no atomics, no real-time mode, no per-cache worker.

**6. Transport renders ahead as a whole.** One background thread renders the graph into a ring buffer about 2 s ahead; the audio callback only copies, and counts an underrun (playing silence) if the ring is empty. A seek restarts rendering at the new position with no pre-roll, since deterministic nodes are seekable and plugins answer from retention. One mechanism replaces four.

**7. Streaming voices** run their programs in consecutive blocks; `VoiceMixer` and the shared `PluginStage` chain are already block-based and stay as they are. Note-off still lands at the next block boundary.

**User-visible effect:** none in sound — demo WAVs must be bit-identical before and after. Expected effects: speed, simpler plugin and transport internals, and room for stateful streaming DSP.

**Packages:** the block model and renderer live in `aura_render` (replacing `Sampler`/`StereoSampler` and their adapters); `aura_integration` builds programs; `aura_plugin_host` shrinks to the plugin node plus the streaming stage; `aura_io_cpal` gains the transport renderer. No new crates. Imp repos and Imp Lab's own code are unaffected; the Lab pack's playback extension (in aura-engine) is affected. The Iced `aura-editor` is ignored and will no longer build against the engine's `aura_render` until someone ports or removes its `playback.rs`.

## Objective analysis

### Pros

- Retires a family of workarounds with one root cause; the plugin cache's lock-free store, interpolation, real-time flag, per-cache workers, `PreparedRoot` and most layout adapters go away.
- Deterministic semantics are unchanged in kind: still seekable anywhere without pre-roll (plugins excepted, as today). No new seek-cost problem is introduced.
- The state rule is stated per mode and enforced by one generic test, so "nonessential" doesn't rely on reviewer discipline.
- Fixes fan-out duplication and moves transport audio-thread work to a copy.
- Resolves the streaming open question (stateful optimizations) by allowing history only where the mode already gives up seeking.

### Cons

- **Large mechanical churn**: ~40 sampler structs, the translator's recursion, and every `at(t)` test. Low risk per node, high volume; bit-identical demo WAVs and the contract test keep it honest.
- **Nonessential state has a subtle failure mode**: an optimization that is *almost* identical (e.g. a phase accumulator in place of `sin(2π f t)`) differs in the last bits and breaks the contract. The generic test catches it, but it means many tempting deterministic optimizations are off-limits; they have to go to streaming.
- **Range-pull with memo is a bit more machinery than a pure push schedule**: memo entries keyed by range, and look-back requests that extend upstream ranges. Worth it to keep "sample anywhere"; a push-only executor could not support look-around or the plugin grid cleanly.
- **Plugins still pre-roll on first access** to a far position, as today. Unchanged, not improved.
- **Ignoring Iced leaves `aura-editor` unbuildable against the new engine** if anything still builds it.

### Worth doing

Yes. Your state rule makes this cleaner than the previous draft: deterministic mode keeps seek-anywhere with no pre-roll, and statefulness becomes a mode distinction the implementation matrix already expresses. Keep the plan disciplined about not changing DSP — bit-identical output is the proof the refactor is right, and the first stateful streaming nodes should be their own plan.

## Low-level design

### Order of work

1. `docs-intent`, then `baseline-hashes` (before any code change).
2. `render-core` with a temporary adapter node wrapping an old `Box<dyn Sampler>`, so node types move over one at a time while demos stay renderable.
3. `translator-program` + `nodes-port`, removing the adapter at the end.
4. `plugin-node`, `sinks`, `consumers`.
5. `tests`, `demos-identity`, verify, Windows build.

### aura_render

- `pub type Frame = u64;` `pub struct Range { start: Frame, len: usize }`; `BlockCtx { range, rate }` with `time_secs(k) = (start + k) as f64 / rate` — must equal today's `frame as f64 / rate` bit for bit.
- `pub trait Node: Send { fn render(&mut self, ctx: &mut RenderCtx, range: Range, outputs: &mut [&mut [f32]]); fn reset(&mut self) {} }`. `RenderCtx::input(port_index, range) -> &[&[f32]]` renders (or returns memoized) upstream output for that range.
- `Program`: nodes in post-order with input wiring by node-output handle; per node a memo of the last rendered `(range, buffers)` so fan-out within one request computes once. Memo buffers preallocated to `BLOCK_FRAMES` plus the node's declared max input window; larger requests are chunked.
- `Renderer::render(range, out)` chunks into `BLOCK_FRAMES` requests; no cursor, no pre-roll. Streaming uses the same API with contiguous ranges.
- Deterministic contract test helper: `assert_deterministic(build: impl Fn() -> Program)` — one range vs uneven chunks vs shuffled vs fresh instance per chunk.
- Move `BLOCK_FRAMES` to `aura_render`; `aura_plugin_host` re-exports.
- Remove `Sampler`, `StereoSampler`, `AudioSampler` (→ `Program` + layout), `ChannelView`, `StereoPair`, `SharedSampler`, `SharedStereoSampler`, `mark_realtime_reader`, `is_realtime_reader`. `sample_offline*` on top of `Renderer`.
- `StreamVoice` holds a `Renderer` and scratch block; quiet detection by block peak with the same `QUIET_SECS` in frames.

### aura_integration

- `translate_node` memoizes by `(node_id, output_port, channel_pass)`; `NodeValue::Signal(Output)` / `NodeValue::Stereo(Output, Output)` replace boxed samplers. `ProgramBuilder` appends nodes in post-order.
- `NodeCtx::signal` / `stereo_signal` return handles; implementations add a node and get output handles.
- `impls.rs` dual mono: instantiate the mono node once per channel with that channel's input handle (inputs shared through the memo). Delete `SharedInput` and channel-pass `remember/view`.
- `translate_graph*` return a `Program` with layout; delete `prepared_root`/`PreparedRoot*`; `sampler_from_score` returns a `Program`.
- Port the sampler structs in `translate/mod.rs` (≈1250–1620) and `streaming.rs` (`LiveFieldSampler`, `GatedAdsrSampler`, `LiveEnvelopeSampler`, `LiveSineSampler`). `NoteSchedule` readers may keep a cursor as nonessential state (re-search when `range.start` is not the previous end). Constants and tempo readers fill their buffer.

### aura_plugin_host

- `PluginNode`: retention `Vec<f32>` per channel, frame-aligned, from frame 0. On `render(range)`, render plugin blocks on its own grid (`BLOCK_FRAMES`, from frame 0) until `range.end + latency` is covered, pulling `audio` input via `ctx.input(.., grid_block)`; events from `NoteEventSource::events_in` and the live-note logic moved verbatim from `CacheState::render_block`; latency removed at the head as today; after finish, zeros. Then copy the range out of retention.
- Delete in `cache.rs`: `Output` atomic chunks, `CHUNK_FRAMES`/`MAX_CHUNKS`, interpolation, `render_ahead`, real-time paths, `prepare`, `underruns`. Keep a retention cap equivalent to today's (~3.4 h mono), silence past it.
- Port the cache tests (exact note frames with latency, out-of-order = sequential, finishes and stays silent, effect never finishes early, live note holds until release, dropping frees the plugin).
- `PluginStage` (streaming shared instance) unchanged apart from imports.

### Sinks and consumers

- `aura_io_cpal::PlaybackEngine::start_at(program, rate, start_secs)`: render thread owns the `Renderer`; preallocated SPSC ring (`PREPARE_AHEAD_SECS` × rate frames); fill before opening the device; callback copies or emits silence and counts an underrun; `stop` joins. `position_secs` from frames consumed. Seek = stop + start at the new position.
- `aura_io_wav`, `aura_cli`: render via the offline helpers.
- `aura_imp_lab_playback`: `recording.rs` notation + click mix becomes a program (a mix node over both); audition and tests updated; spot reads via `render_frame(program, t)` test helper.
- `aura_clap` tests: replace their `Sampler` inputs with constant nodes.
- `aura-editor`: not touched.

### Docs

Per `aura-engine/AGENTS.md`: new `docs/scoping/block-processing.md`; rewrite `docs/design/imp-execution.md` ("Time → Sample semantics", "Three layers", "Functional properties", "Translate-time vs sample-time", "Non-goals": replace "FunDSP-style sequential tick state" with the per-mode state rule, and remove "Buffer/block batching" from Deferred); `playback-modes.md` (node implementations: streaming implementations may hold history; open question resolved); `plugin-hosting.md` deterministic implementation and transport render-ahead; scoping `plugin-hosting.md` "Unit" row; `audio-layouts.md`; `architecture.md` transport paragraph; `product.md` / `notation-synthesis.md` / `architecture.md` "Buffer sampling optimizations" lines; crate overviews for `aura_render`, `aura_plugin_host`, `aura_io_cpal`, `aura_integration`.

### Verify

- aura-engine: `cargo test`, `cargo clippy`, `demos/render-all.sh` with sha256 equal to baseline.
- imp-lab: code unaffected; Lab pack DLLs change → `windows-editor-build`.
- aura-editor: excluded (Iced ignored by user decision).
- CI: check `aura-engine/.github/workflows` for commands touching renamed APIs or demo outputs.

### As implemented

- **Shape of the runtime.** Instead of a `Program` arena with slot indices, signals keep the nested-ownership shape: each node signal owns its inputs through `Input` / `StereoInput` (a boxed signal plus its own block buffer) and renders ranges of at most `BLOCK_FRAMES`. Fan-out goes through `Shared` / `SharedStereo` handles with a one-range memo. Before translating, the translator counts how many times each output may be read (`count_reads`: edges × the consumer's output ports in use × 2 when the consumer is stereo) and shares any output read more than once. That covers fan-out, both dual-mono passes, and multi-port nodes, and retires the dual-mono input memo. The user-level properties match the plan: each output is built once, any range renders identically, and inputs can be read at other ranges (look-around).
- **Names.** `Sampler` / `StereoSampler` / `AudioSampler` → `Signal` / `StereoSignal` / `AudioSignal`. `sampler_from_score` → `signal_from_score`, `translate_graph_to_sampler*` → `translate_graph_to_signal*`, `sample_graph(signal, spec)` takes the signal by value. The plugin node keeps the name `RenderCache`.
- **No nonessential state was added yet.** No node needed it to keep output identical. The note-schedule cursor stays a possible optimization.
- **Removed:** `ChannelView`, `SharedSampler`, `SharedStereoSampler`, `Sampler::prepare` / `underruns`, `mark_realtime_reader` / `is_realtime_reader`, `PreparedRoot`, the cache's atomic chunk store, its interpolation, and its render-ahead worker.
- **Transport.** `aura_io_cpal::transport` holds an SPSC ring of packed stereo frames and one render thread per playback. When the ring runs dry, the playhead stalls: `position_secs` reports frames actually played, and `underruns` counts silent frames.
- **Recording transport (Imp Lab).** The notation origin and the click bar are rounded to whole frames. The click repeats in runs that stop at each bar boundary.
- **Demo identity.** `demo-01`, `demo-02` and `demo-04-stereo` are bit-identical. `demo-03-plugin` changed in 367 of 352,800 frames, by at most 3e-9 (one ULP). The changed frames are exactly those where the old cache's `(f / 44100) × 44100` round trip was not exact, so it interpolated between frames. The new output is the plugin's exact frame. New hash `4f5d524a…`.
- **Tests.** 279 → 286. Removed: the real-time-reader and prepare tests. Added: the deterministic contract for every registered node type (`translate/contract_tests.rs`, with a coverage check that fails when a node type has no contract graph), fan-out sharing one plugin instance, shared memo, channel views, the ring buffer, and render-ahead.
- **Build environment.** The live engine container predates the `tome-rust-server` mount, so verification used one-off `docker run --rm` of `aura-workbench-engine:local` with host bind mounts, and a separate target dir under `~/.cache/aura-block-build`. Rebuild or reopen the Dev Container to get the mount back.
- **Iced editor.** `aura-editor/src/playback.rs` still uses `aura_render::Sampler` and no longer compiles against the engine. This is ignored by the user's decision.

## Commit strategy

### Baseline (plan created)
- aura-workbench: dirty — `?? .claude/` (local tool settings; unrelated, exclude)
- aura-engine: clean (`4c33f3f`)
- imp-lab: clean (`07c609d`); expected unaffected
- aura-editor, imp-rs, imp-spec, imp-ts: not affected

### Intended commits
#### aura-engine
- Include: `crates/**`, `docs/**`, `demos/**` (only if render-all.sh changes), `lab-pack/**` (only if affected)
- Draft message: "Process signals in blocks: graphs render frame ranges with each node output computed once and shared, deterministic node state is nonessential so any range renders identically, streaming nodes may keep history, and plugins and transport drop the per-sample cache and per-cache workers."
#### aura-workbench
- Include: `.cursor/plans/block_processing_3f9a6c21.plan.md`
- Exclude: `.claude/`
- Draft message: "Plan block processing for Aura: range rendering with shared node outputs, nonessential deterministic state, history state in streaming, retiring the per-sample workarounds in plugin hosting and transport."

### User trigger
Say **commit** (or **commit per the plan**) after review.
