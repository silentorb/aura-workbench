---
name: Stereo signals
overview: "Add stereo alongside mono in Aura. Audio layout becomes an Imp type parameter (`A: Audio` = audio_mono | audio_stereo) so most DSP node types are polymorphic and mismatched layouts are Imp type errors. Node types move from a translator `match` into registered implementations; once loaded, every layout-polymorphic node type has all four functions of the mono/stereo × deterministic/streaming matrix, with stereo defaulting to a preloaded dual-mono wrapper and streaming defaulting to deterministic. Runtime, sinks, voices and plugin hosting carry stereo frames. Imp needs two inference fixes and (recommended) generic graph-backed definitions."
todos:
  - id: docs-intent
    content: "aura-engine: scoping + design for audio layouts (docs/scoping/stereo.md, docs/design/audio-layouts.md); amend imp-execution (Time → Frame), playback-modes (implementation matrix), plugin-hosting (no mono fold), architecture. imp-spec: type-system.md (any as assignability top, variadic under instantiation, generic graph-backed definitions)"
    status: completed
  - id: imp-any-top
    content: "imp-rs + imp-ts: an edge into an `any`-typed port accepts without binding the source's type variables (fixes order-dependent inference poisoning); tests incl. mono+stereo mix that also feeds an `any` port"
    status: completed
  - id: imp-variadic-instantiate
    content: "imp-rs + imp-ts: instantiate_node_definition preserves Port.variadic; test explicit typeArgs on a variadic generic"
    status: completed
  - id: imp-conflict-message
    content: "imp-rs + imp-ts: when two inputs bind one type param to different types, report both (\"A: audio_mono (from a) conflicts with audio_stereo (from b)\") instead of the order-dependent \"cannot assign\""
    status: completed
  - id: imp-generic-definitions
    content: "imp-rs + imp-ts: generic graph-backed definitions — body boundary nodes may take typeArgs referencing the definition's typeParams; check_definition treats them as rigid vars carrying bounds; flatten substitutes use-site type args. (In scope: user decision)"
    status: completed
  - id: imp-found-fixes
    content: "imp-rs + imp-ts (found while implementing): catalog_port_type no longer instantiates a node's definition twice when the node has typeArgs (TS threw, Rust silently returned None); resolve_type_args resolves a parameter bound to another variable (long generic chains lost their types)"
    status: completed
  - id: aura-types-runtime
    content: "aura_imp: audio_stereo signal + Audio constraint. aura_render: StereoSampler (frame + per-channel read), AudioSampler enum, channel views and pair; NodeValue::Stereo"
    status: completed
  - id: aura-impl-registry
    content: "aura_integration: NodeTypeImpls registry replacing translate_deterministic match + streaming_implementation table; finalize() fills streaming=deterministic and stereo=dual_mono(mono); translator resolves layout once per graph from Imp type args and picks the matrix cell"
    status: completed
  - id: aura-nodes
    content: "Generic nodes: multiply, add, plugin_effect, output passthrough. New fixed-layout nodes: pan, stereo_to_mono, stereo_join, stereo_split. plugin_instrument → audio_stereo"
    status: completed
  - id: aura-plugin-host
    content: "aura_plugin_host: MonoStage → LayoutStage (adapts plugin layout to mono or stereo); RenderCache stores 1 or 2 channels; streaming PluginStage stereo"
    status: completed
  - id: aura-sinks
    content: "sample_graph renders frames by output layout; aura_io_wav writes 1/2 channels; aura_render BlockSource/StreamVoice/VoiceMixer stereo-internal (mono voices duplicated); aura_io_cpal maps mono/stereo onto device channels; PlaybackEngine stereo"
    status: completed
  - id: aura-cli-lab-demos
    content: "CLI renders stereo WAV when the graph output is stereo; lab-pack catalogs/instruments.json updated; aura_imp_lab_playback stereo transport + audition; demos/demo-04-stereo.json + render-all.sh; regenerate output/"
    status: completed
  - id: verify-full-suites
    content: "Full-suite verification — After implementation, run full verify for every plan-affected repo and its direct dependents (see the project's verify matrix, typically AGENTS.md). Fix failures or get an explicit user waiver before await-commit. Reason about CI; never defer suite confidence to a future CI run."
    status: completed
  - id: windows-editor-build
    content: "Run scripts/run-imp-lab-windows-build.sh (lab-pack playback DLL changes), report AURA_EDITOR_WIN_OUT output path, confirm success"
    status: completed
  - id: commit-await-approval
    content: "Commit (await user approval) — After full-suite verification for affected + dependents (incl. CI considered), re-run git status/diff per repo, reconcile with this strategy, commit only when the user explicitly requests it."
    status: completed
isProject: false
---

# Stereo signals

## User request

Aura should support mono and stereo signals and graphs that mix both. A node type may be exclusively mono or stereo, but most DSP node types should accept either and resolve polymorphically: the input layout decides the output layout, and inputs bound to the same type parameter must agree. A mono input and a stereo input on `(Signal<A>, Signal<A>) → Signal<A>` is an Imp type error for now (no implicit up-mix).

Each dual node type provides a mono function and optionally a stereo one. Without a stereo function, stereo runs the mono function per channel ("dual mono"), prepared when the node type is loaded rather than during translation. The mono/stereo dimension crosses the existing deterministic/streaming dimension; once a node type is loaded, all four cells of that 2×2 matrix are ready, with the optional streaming function also prepared ahead of time.

In scope: types, Imp inference, node implementation registration, runtime frames, sinks (WAV, device, voices), plugin hosting, demos, the Lab pack. Out of scope: more than two channels (left room for it), implicit mono↔stereo conversion, mid/side, stereo-aware UI beyond what type errors already give.

## High-level design

### Problem

**Aura is mono end to end.** A graph denotes `Time → f32`; `Sampler::at` returns one sample; WAV export hard-codes one channel; the voice mixer and device output move mono blocks; plugins, usually stereo, are folded to mono (`MonoStage`).

**Imp mostly already does what's asked.** I probed imp-rs's checker with a generic `mix<A: Audio>(a: A, b: A) → A`:

| Case | Result today |
|---|---|
| mono + mono, stereo + stereo | ✅ `A` resolves to the input layout; the output follows |
| mono + stereo | ✅ type error |
| variadic `add<A>(inputs: A…)`, mono + stereo | ✅ type error |
| mono + stereo, where `mix`'s output **also** feeds an `any`-typed port (e.g. a noise `seed`) | ❌ **no error**; `A` resolves to `any`. Depends on edge ordering |
| explicit `typeArgs` on a variadic generic | ❌ the port loses `variadic`, so a second edge is rejected |
| graph-backed definition (an `instruments.json` entry) generic over `A` | ❌ rejected: body type variables never resolve, and boundary `typeArgs` must be concrete |

So the core semantics exist (type params, `TypeConstraint` bounds, per-node-scoped unification, overloads, `implementation.dispatch`). The gaps are two inference bugs and one missing feature.

**The 2×2 matrix has no home.** Node types aren't "loaded" with functions today. Deterministic implementations are one big `match` in `aura_integration`'s translator. Streaming implementations are a second `match` table, looked up per node during translation, falling back to deterministic on a miss. There's nowhere to put a precomputed stereo function or a precomputed streaming fallback.

**Few node types process audio yet.** Of today's nodes only `multiply`, `add`, `plugin_effect` and `output` take audio inputs. Everything else is a source (`sine`, noise, saw, plugin instruments) or a control/score node. The polymorphism machinery is mostly for future effects (filters, delays, reverbs), and today's graphs gain little until stereo sources exist.

### Solution

**Layout as a type parameter.** Add `audio_stereo` next to `audio_mono` and an Aura constraint `Audio = audio_mono | audio_stereo`. A layout-polymorphic node declares `A: Audio` and types its audio ports `A`. Controls stay `control`. `multiply` becomes `(a: A, b: control) → A` and `add` becomes `(inputs: A…) → A`. Inference runs through the graph as it does today, so a chain of polymorphic nodes fed by a stereo source is stereo all the way to `output`. Flat type ids are kept instead of `audio<C>`, so saved graphs and catalogs keep `audio_mono` unchanged. A later surround layout is another member of `Audio`.

**Exclusive layouts are ordinary fixed signatures.** Sources stay mono (`sine → audio_mono`). The following explicit converters make mixed workflows possible without implicit conversion:

| Node | Signature |
|---|---|
| `pan` | `(audio: audio_mono, position: control) → audio_stereo`, equal-power |
| `stereo_to_mono` | `audio_stereo → audio_mono`, average |
| `stereo_join` | `(left: audio_mono, right: audio_mono) → audio_stereo` |
| `stereo_split` | `audio_stereo → left, right: audio_mono` |

`plugin_instrument` outputs `audio_stereo` (a mono plugin is duplicated). `plugin_effect` is `A → A`.

**Node type implementations become registrations with a full matrix.** Each node type registers implementations in `aura_integration`, keyed by node type id:

| | deterministic | streaming |
|---|---|---|
| **mono** | required | optional, defaults to mono deterministic |
| **stereo** | optional, defaults to dual-mono(mono deterministic) | optional, defaults to stereo deterministic if given, else dual-mono(mono streaming) |

`finalize()` runs once when the registry is built. It fills every empty cell, so the translator reads one cell and never branches on fallbacks. That covers your preload preference for both dimensions. A node type that isn't generic over layout has just its own row (two cells). An implementation is still a translate-time builder (it composes samplers from its inputs), so "preloaded" means the wrapper builder exists at load and only builds samplers at translation. The translator resolves each node's layout once per graph from Imp's inferred type args, then picks the cell for (layout, mode).

**Dual mono, done safely.** The wrapper translates each stereo input once, then runs the mono builder twice. Each run sees left or right *channel views* of the shared stereo inputs, and both runs get the same non-audio inputs. The result is a stereo pair. Two rules keep it sound:
- A channel view reads one channel only, so a chain of N dual-mono nodes costs about 2× mono rather than 2^N.
- Upstream nodes are translated once, not once per channel, so a plugin upstream isn't instantiated twice.

Stateful node types (plugins) never take the dual-mono default. They register a true stereo implementation.

**Runtime frames.** `Sampler` (mono, `at(t) → f32`) stays. `StereoSampler` adds `frame(t) → [f32; 2]` and a one-channel read. Translation yields mono or stereo values. The graph's output layout decides what sinks receive:
- WAV writes 1 or 2 channels.
- Device output maps mono to every channel and stereo to left/right.
- The streaming voice mixer works in stereo internally and duplicates mono voices.

Deterministic purity and seekability are unchanged: a frame is a pure function of `t`.

**Plugin hosting stops folding.** `MonoStage` becomes a layout adapter: it feeds a mono or stereo input to the plugin's channels and returns mono (average) or stereo, as the node's resolved layout asks. Render caches store one or two channels.

**Imp work (yes, some is needed):**
1. **`any` as an assignability top.** An edge *into* an `any` port is accepted without binding the source's type variables. That removes the order-dependent poisoning, which would otherwise let mono + stereo through silently.
2. **Instantiation keeps `variadic`.**
3. **A clearer conflict message.** Report both bindings (`A: audio_mono from a conflicts with audio_stereo from b`), not whichever edge came second.
4. **Generic graph-backed definitions (in scope).** Boundary nodes in a definition body may reference the definition's own type params, the body is checked with those params as rigid variables carrying their bounds, and use-site type args are substituted when flattening.

Each change goes into imp-rs and imp-ts together (they share one spec), with imp-spec updated first.

**Imp Lab.** No new UI is required: the Lab registry already loads Aura's constraint library from the pack, and type errors surface as they do today. Generic ports show no resolved layout in the graph view; that polish is deferred.

## Objective analysis

### Pros

- Polymorphism comes almost entirely from existing Imp machinery. The type-level ask (agreement on `A`, an error on mismatch) already works, and the Imp work is targeted bug fixes plus one feature.
- The matrix refactor gives node types the registration seam that `playback-modes.md` already anticipates ("can move into node-type registrations without a redesign"). Extension node types will need the same seam.
- Dual mono by default means every future effect gets stereo for free. Only effects that are truly stereo (pan law, stereo width, plugins) write a second function.
- Explicit converters keep mixing deliberate and visible in the graph.

### Cons

- **Broad runtime blast radius.** Sinks, the voice mixer, device output, render caches and plugin stages all change shape. Most of the effort is here, not in the type system.
- **Explicit conversion means friction.** Every mono source feeding a stereo bus needs a `pan` or `stereo_join`. That's the intended rule for now, but busy graphs will feel it.
- **The dual-mono wrapper has sharp edges.** It needs the single-translation and per-channel-read rules above. If either is missed, it doubles plugins or blows up cost exponentially. Both rules get dedicated tests.
- **Pre-existing:** the translator re-translates a node once per consumer (there's no DAG memoization). Stereo doesn't make this worse, but it shows up in the same code and is out of scope here.
- **Behavior change for plugin graphs:** `demo-03-plugin` becomes a stereo WAV.

### Worth doing

Yes. The type-level half is cheap thanks to existing Imp generics. The real cost is the runtime plumbing, which any stereo support needs regardless of design.

Two judgments:
- **Do the registry/matrix refactor first, before any stereo runtime.** It's mechanical but touches every node type, and doing it inside the stereo work would tangle two large diffs.
- **Generic graph-backed definitions:** included in this effort (user decision). Without them, any reusable effect chain in `instruments.json` has to be authored twice (mono and stereo), which undercuts "workflows that mix both." They're the only real Imp feature here. Land them in the Imp phase, before Aura depends on them, so the demo and Lab pack can ship a generic stereo-capable effect chain definition.

### Deferred: join inference (auto-promotion)

A later session may let `(A, A) → A` resolve to stereo when *any* input is stereo, instead of erroring. The clean form is **join inference over a layout order `audio_mono ≤ audio_stereo`**: each inbound edge adds a lower bound on `A`, and `A` resolves to the least upper bound; Aura's translator inserts an up-mix wherever a resolved-mono source feeds a resolved-stereo port. Signatures, converters and the implementation matrix in this plan stay valid; only inference and coercion insertion change.

Open decisions for that session:
- **Scope:** global `mono ≤ stereo` silently turns every mismatch into an up-mix. Prefer opt-in per type parameter (a "promote" flag on `TypeParam`) so only nodes that want promotion get it.
- **Up-mix policy:** plain duplication vs. center pan at −3 dB (changes loudness).

Avoided alternatives: enumerated mono/stereo overloads (2ⁿ growth, no variadic support, ambiguous selection with unresolved neighbors) and `I1, I2, O` with a relational constraint `O = max(I1, I2)` (needs multi-parameter constraints for the same result).

## Low-level design

### Imp (imp-spec → imp-rs + imp-ts, parity)

- `imp-spec/docs/packages/imp-typecheck/type-system.md`: assignability to `any` doesn't bind; instantiation preserves `variadic`; type-param conflict errors; a "Generic graph-backed definitions" section (boundary `typeArgs` may be `{param}` of the enclosing definition; rigid vars; bounds satisfied by a rigid var whose bounds imply the target bound).
- `imp_typecheck/src/assignable.rs` (+ `imp-ts/packages/imp-typecheck/src/assignable.ts`): if the target is `any`, return `subst` unchanged before `unify`. Keep `unify`'s `any` handling for source-side `any` (parameter `value` literals).
- `imp_typecheck/src/instantiate.rs::substitute_ports`: `variadic: port.variadic` (+ ts `instantiate.ts`).
- Conflict message: in `check_graph`'s edge loop, when `assignable` fails and the target port's template is a scoped var already bound, emit the bound type, the incoming type, and both ports.
- Generic definitions: `assert_concrete_args` allows vars named in the enclosing definition's `type_params` during `check_definition`. `check_definition` seeds a substitution that treats `__def__{id}::A` as rigid (it may unify only with itself) and checks body bounds against the param's declared bounds. `imp_graph_resolve::flatten_graph` substitutes the use-site node's resolved type args into inlined boundary `typeArgs`.
- Tests: port the scratch probe's six cases (mono+mono, stereo+stereo, mono+stereo, variadic mixed, `any` poisoning, explicit variadic) plus generic definitions (valid, a bound violation, a mixed use site) into `imp_typecheck/tests/` and `imp-typecheck/src/typecheck.test.ts`.

### Aura types and runtime

- `aura_imp/src/signals.rs`: `AUDIO_STEREO = "audio_stereo"`. `constraints.rs`: `AUDIO = "Audio"` constraint.
- `aura_render`: `trait StereoSampler: Send + Sync { fn frame(&self, t) -> [f32; 2]; fn channel(&self, ch: Channel, t) -> f32 { self.frame(t)[ch] } ; prepare/underruns like Sampler }`; `enum AudioSampler { Mono(Box<dyn Sampler>), Stereo(Box<dyn StereoSampler>) }`; `ChannelView(Arc<dyn StereoSampler>, Channel): Sampler`; `StereoPair(Box<dyn Sampler>, Box<dyn Sampler>): StereoSampler` (overrides `channel` to read one side).
- `aura_integration/src/translate/mod.rs`: `NodeValue::Stereo(Box<dyn StereoSampler>)`; `PreparedGraph` stores `layouts: BTreeMap<NodeId, Layout>`, computed once after `check_graph` from the selected definitions and type args. Add an imp_typecheck API returning type args for all nodes in one pass, since `resolve_type_args` currently recomputes selections per call.

### Implementation registry (do first, mono-only, no behavior change)

- New `aura_integration/src/translate/impls.rs`: `type Build = Arc<dyn Fn(&mut NodeCtx) -> Result<NodeValue, TranslateError> + Send + Sync>`; `struct NodeTypeImpls { mono: ModePair, stereo: Option<ModePair> }` / `ModePair { deterministic: Build, streaming: Option<Build> }`. `Registered::finalize` produces `Matrix { cells: [[Build; 2]; 2] }` or a single-row form for fixed-layout types.
- Move every `translate_deterministic` arm into a `fn` registered by id, and every `streaming_implementation` entry into the same registration. Delete both `match`es. `translate_node` becomes lookup → cell → call.
- `dual_mono(mono: Build) -> Build`: translates the stereo-typed inputs once into an `Arc<dyn StereoSampler>` memo on `NodeCtx`, runs `mono` twice with `NodeCtx::channel = Some(L | R)` so that `ctx.signal(port)` on a stereo-typed port returns a `ChannelView`, and wraps the result in `StereoPair`. Memoize non-audio inputs too, so both runs share them.
- Tests: the matrix is complete after finalize for every registered id. A dual-mono chain of 16 `multiply`s evaluates each upstream `at` count linearly (counting sampler). A dual-mono node over a plugin builds one `RenderCache`. Streaming falls back to deterministic via the cell, with no lookup at translate time.

### Nodes

- `aura_imp/src/dsp.rs`: `multiply`, `add` generic `A: Audio`. New `pan`, `stereo_to_mono`, `stereo_join`, `stereo_split`. `plugin.rs`: `plugin_effect` `A → A`, `plugin_instrument` → `audio_stereo`.
- `aura_dsp`: `pan_equal_power(x, pos) -> [f32; 2]`.
- `multiply`/`add`: mono implementations only (stereo via dual mono, which exercises the default path). `pan` etc.: fixed-layout implementations. Plugin nodes: explicit mono and stereo implementations in both modes.

### Plugin host

- `aura_plugin_host/src/mono.rs` → `layout.rs`: `LayoutStage::new(processor, max_block, Layout)` maps input/output channels for mono and stereo. `RenderCache` stores `Vec<[f32; N]>`-style channel buffers and implements both `Sampler` and `StereoSampler` by layout. `stage.rs` streaming stage: stereo blocks.

### Sinks and streaming

- `aura_integration::sample_graph` (and `SampleSpec` consumers) returns `Rendered { layout, frames }`.
- `aura_io_wav`: `channels` from layout (the header code already parameterizes it).
- `aura_render/src/streaming.rs`: `BlockSource::render_block(&mut self, out: &mut [f32], channels: usize)` interleaved. `StreamVoice` renders mono or stereo voice graphs. `VoiceMixer` sums into stereo.
- `aura_io_cpal`: `PlaybackEngine` and `StreamingOutput` write mono to all device channels and stereo to the first two (the rest stay silent).

### CLI, Lab pack, demos

- `aura_cli`: no flag needed; the output layout comes from the graph. Print the layout in the render summary.
- `lab-pack/catalogs/instruments.json`, `demos/instruments.json`: unchanged types (mono sources). Add a stereo effect chain definition once generic definitions land.
- `aura_imp_lab_playback`: transport and audition use stereo blocks.
- `demos/demo-04-stereo.json`: two sines panned apart, summed by generic `add`, gained by generic `multiply`. Add it to `render-all.sh` and regenerate `output/`. A test asserts that a mismatched variant fails type check.

### Docs

- `aura-engine/docs/scoping/stereo.md` (why: plugins and mixing, explicit conversion for now), `docs/design/audio-layouts.md` (layouts, `Audio` constraint, matrix, dual-mono rules, converters, non-goals: implicit up-mix, >2 channels for now).
- Amend `docs/design/imp-execution.md` (`Time → Frame`), `playback-modes.md` (§Node implementations → the matrix; remove "currently live in the translator's match"), `plugin-hosting.md` (layout adapter), `architecture.md`, `docs/crates/aura_render|aura_integration|aura_plugin_host|aura_imp` overviews.

### Verify

Verify matrix: imp-rs and imp-ts per their AGENTS.md; aura-engine `cargo test` and `cargo clippy` (dependent of imp-rs and tome-rust-server's imp_mir, which needs no change but rebuilds); imp-lab library crates and the desktop build (dependent of imp-ts through imp-graph-view); imp-graph-view `bun run test`. Regenerate `output/` with `demos/render-all.sh`, then run the Windows build.

### As implemented

- Public API: `translate_graph*` and `StreamingProgram::instantiate` return `AudioSampler`; rendering returns `Pcm { layout, samples }` (interleaved); `write_pcm_to_wav` writes its channel count; the CLI's "Wrote …" line names the layout.
- Streaming is stereo internally: `BlockSource::render_block(&mut [[f32; 2]])`; `StreamVoice` holds an `AudioSampler`; `PluginStage` runs a stereo `LayoutStage`.
- `RenderCache` has inherent `prepare`/`underruns` (it implements both sampler traits); a stereo frame read counts one underrun.
- Device output: mono device = average of left/right; devices with more than two channels get left/right on the first two and silence on the rest (previously a mono graph was copied to every channel).
- Constant-only `add` (all `parameter` inputs) has no layout to infer; it needs `typeArgs` (one test updated).
- Graph-backed definitions inline their `output` boundary node, so a graph using one titles its own output `out` (existing `find_output_node` rule).
- `demo-03-plugin.wav` is now stereo (the instrument is stereo); new `demo-04-stereo` pans demo-01's parts.

## Commit strategy

### Baseline (plan created)
- aura-workbench: dirty — `?? .claude/` (local tool settings; unrelated, exclude)
- aura-engine: clean (`ef053a5`)
- imp-rs: clean (`19a3884`)
- imp-ts: clean (`5cf4114`)
- imp-spec: clean (`23388c3`)
- imp-lab: clean (`07c609d`); expected unaffected

### Intended commits
#### imp-spec
- Include: `docs/packages/imp-typecheck/type-system.md`, `docs/packages/imp-graph-resolve/resolve.md`
- Draft message: "Specify `any` as an assignability top, variadic-preserving instantiation, type-param conflict errors, and generic graph-backed definitions."
#### imp-rs
- Include: `crates/imp_typecheck/**` (incl. new `tests/generic_inference.rs`), `crates/imp_graph_resolve/**` (incl. new `tests/generic_definitions.rs`)
- Draft message: "Stop `any` ports from poisoning type inference, report type-parameter conflicts by name, keep variadic ports under explicit type args, resolve long generic chains, and allow graph-backed definitions to be generic."
#### imp-ts
- Include: `packages/imp-typecheck/**` (incl. new `generic-inference.test.ts`), `packages/imp-graph-resolve/**` (incl. new `generic-definitions.test.ts`)
- Draft message: same intent as imp-rs, for parity.
#### aura-engine
- Include: `crates/**`, `docs/**`, `demos/**`, `lab-pack/**`
- Draft message: "Add stereo: audio layout as an Imp type parameter, node types registered with a full mono/stereo × deterministic/streaming matrix (dual-mono and deterministic fallbacks prepared at load), and stereo frames through sinks, voices and plugin hosting."
#### aura-workbench
- Include: `.cursor/plans/stereo_signals_5b8e3d17.plan.md`
- Exclude: `.claude/`
- Draft message: "Plan stereo signals for Aura: layout polymorphism through Imp generics and a preloaded node implementation matrix."

### User trigger
Say **commit** (or **commit per the plan**) after review.
