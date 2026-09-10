love2d mechanical-port review

I went through the package structure (~80k lines under lib/src/runtime), the graphics record/replay path, the Lua binding/wrapper layer, and the non-graphics subsystems. Below is a subsystem-by-subsystem smell audit focused on unnecessary wrappers, indirection, and hot-path cost — not API completeness.

───

Architecture (what the port actually is)

Almost every subsystem is the same mechanical stack:

Lua call
  → love_api_bindings / *_bindings (coerce args)
  → object wrappers (table-as-userdata + method map)
  → *_support host model
  → Flame / Flutter / forge2d adapter

Graphics is deferred, not immediate:

love.graphics.*  →  LoveDrawCommand list  →  end of frame snapshot  →  Flame Canvas replay

That deferred model is fine for correctness. The cost comes from how much is copied and re-validated on every call.

───

Cross-cutting systemic smells

1. Full method tables per object instance (High)

Wrappers like _wrapFont, _wrapImage, _wrapCanvas, Source, Mesh, ParticleSystem, etc. build a new table with one BuiltinFunction per method, then cache the whole table on the host object via Expando.

That is the opposite of native LOVE (shared metatable / method table per type). Expando caching avoids rebuild on re-wrap, but memory still scales roughly as objects × methods, not types × methods.

Partial consolidations already exist (_physicsObjectEntries, _wrapLoveDataObject, _textureEntries) — they should be the pattern for everything.

2. Receiver re-validation on every method (High)

Even Font:getHeight does:

args[0] → _valueAt → _rawValue → map key lookup → released Expando → field

Trusted methods on a known wrapper table should not re-run full type probing every time.

3. Graphics records a full state stamp per draw (High)

Every rectangle/image/text command manually packs ~10 state fields and:

• copyTransform() then another Matrix4.copy in LoveDrawCommand
• runtime.graphics.shader (already a snapshot) then shader?.snapshot() again
• fonts/particles/batches often deep-copy again in the command ctor

So a dense draw loop pays multi-matrix + multi-shader clone cost even when state did not change.

4. Dual surfaces for the same API (Medium)

Many object methods are implemented both as:

• methods on the per-instance wrapper table, and
• entries in loveApiBindingFactories / module factories

Audio Source:play is a clear example. That is pure mechanical residue: “register every wiki symbol” + “build full method table”.

5. Debug paths that still allocate with prints disabled (High)

In love_script_runtime.dart:

const bool _loveTraceRuntimeLeak = bool.fromEnvironment(
  'LOVE2D_TRACE_TOUCH_LEAK',
  defaultValue: true,  // on by default
);

For update / touch events, callLoveCallbackIfDefined still builds detail maps, describes args, copies scancodes, and calls getTouches() — then _loveTraceRuntime joins strings even though the prints are commented out. Same default-on pattern in love_flame_input.dart.

This is free money: turn default off and never build details when the sink is dead.

───

Subsystem-by-subsystem

Graphics / renderer / Flame present

Call chain: bindings → LoveGraphicsFrame.addCommand → surface command list → snapshotScreenSurface → Flame render → LoveCanvasRenderBackend (pass-through) → harness renderer replay.

┌─────────────────────────────┬──────────┬─────────────────────────────────┐
│ Smell                       │ Severity │ Notes                           │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Double/triple matrix copies │ High     │ binding copyTransform + command │
│ per draw                    │          │ ctor Matrix4.copy; local draw   │
│                             │          │ transform often copied again    │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Double shader snapshot      │ High     │ getter already snapshots;       │
│                             │          │ command snapshots again (deep-  │
│                             │          │ clones uniforms)                │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Full state on every command │ High     │ color/line/blend/scissor/       │
│                             │          │ shader/transform stamped even   │
│                             │          │ when identical across 1000      │
│                             │          │ draws                           │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Drawable probe chain in     │ High     │ Text → Mesh → SpriteBatch →     │
│ draw                        │          │ Particle → Video → Image;       │
│                             │          │ images pay all failures first   │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Particle/SpriteBatch/Mesh   │ High     │ multi-pass copy() / matrix-per- │
│ deep copy on record         │ when     │ entry before replay             │
│                             │ used     │                                 │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Surface snapshot List.from  │ Medium   │ every present; ownership        │
│ + unmodifiable              │          │ transfer would be cheaper       │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Replay: new Paint / save-   │ High     │ no paint pooling; points        │
│ restore per command         │          │ allocate paint per point        │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Always-on dual stats types  │ Medium   │ LoveRenderStats ↔               │
│                             │          │ LoveFlameRenderStats conversion │
│                             │          │ every frame                     │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ LoveCanvasRenderBackend     │ Low      │ pure forwarder to harness       │
│                             │          │ renderer functions              │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Canvas draw via canvas.     │ Medium   │ revision-cached (good) but      │
│ snapshot()                  │          │ still materializes snapshot     │
│                             │          │ objects                         │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Font _                      │ Medium   │ clones font/fallback graph into │
│ snapshotForDrawCommand on   │          │ command                         │
│ every print                 │          │                                 │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ push always full            │ Medium   │ even for transform-only stack   │
│ LoveGraphicsState.copy()    │          │                                 │
└─────────────────────────────┴──────────┴─────────────────────────────────┘

Best shape for graphics: state-change commands or versioned shared state stamps; single freeze of transform/shader; O(1) drawable tag; copy-on-write freeze for batch/particle; replay paint/state pooling.

───

Lua bindings / object wrappers

┌──────────────────────────────┬──────────┬────────────────────────────────┐
│ Smell                        │ Severity │ Notes                          │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ Per-instance method tables   │ High     │ no shared __index prototype    │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ _requireX on self every call │ High     │ map-key “userdata” model       │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ release/type/typeOf paste    │ Medium   │ physics already centralized    │
│                              │          │ this                           │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ Dual Source methods +        │ Medium   │ two sources of truth           │
│ factories                    │          │                                │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ bindLoveApiFunction extra    │ Medium   │ factory already is the impl;   │
│ closure                      │          │ another wrap for non-inlined   │
│                              │          │ APIs                           │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ Filesystem reimplements _    │ Medium   │ drift risk vs binding_helpers  │
│ valueAt / _rawValue          │          │                                │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ args.skip(1).toList() /      │ Medium   │ polygon, some canvas ops       │
│ sublist on hot paths         │          │                                │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ _tableIndexedEntry linear    │ Low–Med  │ OK for dense int keys;         │
│ scan fallback                │          │ expensive on miss              │
├──────────────────────────────┼──────────┼────────────────────────────────┤
│ async on methods that only   │ Low–Med  │ extra async machinery          │
│ return a Future              │          │                                │
└──────────────────────────────┴──────────┴────────────────────────────────┘

Best shape: one shared method table per type; thin instance table (object key + release); trusted-receiver extract; factories only for module-level APIs.

───

Frame loop (LoveFlameHarness / LoveScriptRuntime)

┌─────────────────────────────┬──────────┬─────────────────────────────────┐
│ Smell                       │ Severity │ Notes                           │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Trace default on + map      │ High     │ confirmed: allocates even with  │
│ build every update          │          │ prints dead                     │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Callback lookup every frame │ Medium   │ re-walks love global; no cached │
│                             │          │ love.update/love.draw           │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Fully async frame           │ Medium   │ many steps are sync-capable;    │
│                             │          │ microtask churn                 │
├─────────────────────────────┼──────────┼─────────────────────────────────┤
│ Frame drop when _           │ Medium   │ long update skips ticks instead │
│ updateInFlight              │          │ of coalescing                   │
└─────────────────────────────┴──────────┴─────────────────────────────────┘

───

Filesystem

Lots of files, but hot path is clear: read → resolve mounts → adapter → wrap bytes.

┌─────────────────────────┬──────────┬─────────────────────────────────────┐
│ Smell                   │ Severity │ Notes                               │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ Multi-copy bytes        │ High     │ virtual node List.from, FileData    │
│                         │          │ List.unmodifiable, IO helper List.  │
│                         │          │ from                                │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ Double existence checks │ High     │ candidate scan fileExists, then     │
│                         │          │ read path checks again              │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ Linear mount scan       │ Medium   │ new candidate list every read; no   │
│                         │          │ last-hit cache                      │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ Dispatch → Bindings     │ Low–Med  │ install-time factory noise; runtime │
│ class → extension re-   │          │ mostly real work after that         │
│ exports                 │          │                                     │
└─────────────────────────┴──────────┴─────────────────────────────────────┘

Best shape: one Uint8List ownership rule; resolve+open once; hot-path root cache.

───

Audio / sound

┌───────────────────────────┬────────────┬─────────────────────────────────┐
│ Smell                     │ Severity   │ Notes                           │
├───────────────────────────┼────────────┼─────────────────────────────────┤
│ Triple Uint8List.fromList │ High       │ FileData → LoveAudioSource →    │
│ on newSource              │            │ Flutter backend                 │
├───────────────────────────┼────────────┼─────────────────────────────────┤
│ Full decode for metadata  │ High on    │ duration/sampleRate may decode  │
│                           │ load       │ entire file                     │
├───────────────────────────┼────────────┼─────────────────────────────────┤
│ SoundData → WAV re-encode │ Medium     │ avoid when backend can take PCM │
│ for play                  │ –High      │                                 │
├───────────────────────────┼────────────┼─────────────────────────────────┤
│ Backend interface itself  │ Low        │ useful host seam, not empty     │
└───────────────────────────┴────────────┴─────────────────────────────────┘

───

Input / event

┌──────────────────────┬──────────┬────────────────────────────────────────┐
│ Smell                │ Severity │ Notes                                  │
├──────────────────────┼──────────┼────────────────────────────────────────┤
│ Per-event Future     │ High     │ _dispatchQueue = _dispatchQueue        │
│ chain                │          │ .then(...) on every move/key/touch     │
├──────────────────────┼──────────┼────────────────────────────────────────┤
│ Geometry rebuild per │ Medium   │ presentation geometry + new Vector2s   │
│ pointer event        │          │                                        │
├──────────────────────┼──────────┼────────────────────────────────────────┤
│ Trace default on for │ Medium   │ same dead-print allocation pattern     │
│ touch                │          │                                        │
├──────────────────────┼──────────┼────────────────────────────────────────┤
│ dispatch* vs queue*  │ Medium   │ footgun (double callback if misused);  │
│ dual API             │          │ harness correctly uses queue           │
├──────────────────────┼──────────┼────────────────────────────────────────┤
│ love.event.pump no-  │ Low      │ OK for this architecture               │
│ op                   │          │                                        │
└──────────────────────┴──────────┴────────────────────────────────────────┘

Best shape: sync pushMessage from adapters; only main loop invokes Lua; no Future chain for queue-only work.

───

Physics

┌─────────────────────────┬──────────┬─────────────────────────────────────┐
│ Smell                   │ Severity │ Notes                               │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ Async contact-filter    │ High     │ nested fixture loops + await Lua    │
│ prep O(fixtures²)       │          │ before step when sync path          │
│                         │          │ unavailable                         │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ bodies getter allocates │ Medium   │ bodyCount even uses that path       │
│ filtered unmodifiable   │          │                                     │
│ list                    │          │                                     │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ query/raycast scan all  │ Medium   │ not forge2d broadphase queries      │
│ bodies×fixtures         │          │                                     │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ Per-contact Lua wrapper │ Medium   │ Expando helps identity, still arg/  │
│ churn                   │          │ table cost                          │
├─────────────────────────┼──────────┼─────────────────────────────────────┤
│ Lifecycle helpers       │ Positive │ _physicsObjectEntries is the model  │
│                         │          │ others should follow                │
└─────────────────────────┴──────────┴─────────────────────────────────────┘

───

Font

┌────────────────────┬───────────────┬─────────────────────────────────────┐
│ Smell              │ Severity      │ Notes                               │
├────────────────────┼───────────────┼─────────────────────────────────────┤
│ Wrap path measures │ High if wrap  │ many TextPainter.layouts via width  │
│ too finely         │ is hot        │ measure of tiny strings             │
├────────────────────┼───────────────┼─────────────────────────────────────┤
│ Host metrics       │ Positive      │ sized caches exist; still wrong     │
│ caches             │               │ granularity for wrap                │
├────────────────────┼───────────────┼─────────────────────────────────────┤
│ Glyph pixel buffer │ Low–Med       │ load-time                           │
│ copies             │               │                                     │
└────────────────────┴───────────────┴─────────────────────────────────────┘

───

Math / data / window / system / thread / video

Mostly thinner and colder:

• math: real work; Bezier render and color multi-returns allocate if spammed
• data: copy-happy normalizers (List.from / encode paths) — medium for large buffers
• window/system: thin state bags + host hooks — fine
• thread: in-process channels; Future.any + timeout futures on wait — low unless polled hard
• video: factory-injected frame provider; cost mostly on graphics/overlay path

───

Priority roadmap (ROI order)

P0 — do first (measurable frame/load wins)

1. Kill default-on dead tracing (defaultValue: false; never build details when off).
2. Single matrix + single shader freeze on draw-command construction.
3. Zero-copy / single-copy buffers for FS read and newSource.
4. Sync input queue (drop per-event Future chain).
5. Shared method metatables for Image/Font/Source/Canvas/Body (memory + wrap time).
6. O(1) drawable tag for love.graphics.draw.

P1 — structural cleanup that unblocks further speed

7. State versioning or state-change commands instead of full stamp per draw.
8. Collapse particle/sprite-batch multi-copy freezes.
9. Unify lifecycle (release/type/typeOf) like physics.
10. One coercion helper module (bindings + filesystem).
11. Cache love.update / love.draw callback Values.
12. Physics: prefer sync filters; never all-pairs prep.

P2 — replay / secondary

13. Paint pooling + coalesce consecutive same-state commands in harness renderer.
14. Optional/debug-only render stats.
15. Font wrap via one Paragraph pass / glyph-id metrics.
16. Surface snapshot ownership transfer (no double list wrap).
17. Remove or quarantine dispatch* from host paths.

───

What is already in good shape

• Expando identity caches for wrappers
• Canvas slice / mesh / surface revision caches
• TextPainter LRU caches
• Flame atlas batching for sprite batch / particles when ui.Image exists
• Hot love.graphics.* bytecode-inline allowlist (right idea; needs thinner bodies)
• Real host adapters (Flame, forge2d, media_kit) — not pure empty shells everywhere
• Physics/data lifecycle helpers as a consolidation template

───

Suggested way to work this “fine tooth comb”

Treat this as a series of small, measurable cleanups, not a big rewrite. AGENTS.md is right: preserve 11.5 behavior, keep tests authoritative, separate first-use hitch from steady-state.

Recommended attack order:

1. Tracing defaults + input Future queue (low risk, instant win)
2. Draw-command freeze (matrix/shader/state stamp)
3. Buffer ownership FS→audio
4. Shared method tables + drawable tag
5. Physics filter path
6. Replay paint pooling

I did not change code in this pass — this is the audit map.

If you want to proceed next, pick one lane and we can start implementing with targeted tests:

• A) P0 dead-trace + input queue
• B) graphics command freeze (highest draw FPS impact)
• C) FS/audio zero-copy
• D) shared method metatables for object wrappers
