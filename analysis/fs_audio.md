Non-graphics mechanical-port review (love2d)

Scope: hot paths only (frame loop, input events, readFile/read, audio create/play, physics step). Cold paths (7z/ISO archives) ignored.

───

0. Frame loop / host glue (baseline for everything)

Call chain

Flame tick → LoveFlameHarnessGame.onTick
  → _LoveFlameHarnessController.onFrame
  → _runFrame(dt)
      → input.flush / joystick flush
      → LoveScriptRuntime.processMainLoopEvents
      → context.stepExternal(dt)
      → callUpdateIfDefined(dt)
      → beginDrawFrame / callDrawIfDefined
      → _commitPresentedFrame (graphics.snapshotScreenSurface + presentFrame)

Key files:
• /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/flame/love_flame_harness.dart
• /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/love_script_runtime.dart
• /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/flame/love_flame_host.dart

Smells

┌─────────────────┬──────────┬───────────────────────────────────────┐
│ Smell           │ Severity │ Notes                                 │
├─────────────────┼──────────┼───────────────────────────────────────┤
│ Per-frame       │ High     │ _loveTraceRuntimeLeak defaults to     │
│ tracing work    │          │ true. For update / touch,             │
│ with default on │          │ callLoveCallbackIfDefined builds      │
│                 │          │ maps, getTouches(), pressedScancodes  │
│                 │          │ .toList(), arg description strings,   │
│                 │          │ then discards them (prints            │
│                 │          │ commented). Same pattern in _         │
│                 │          │ queueLoveEvent / poll path.           │
├─────────────────┼──────────┼───────────────────────────────────────┤
│ Callback lookup │ Medium   │ userLoveCallback('update') re-walks   │
│ every frame     │          │ love global map each frame; no cached │
│                 │          │ Value? for user callbacks.            │
├─────────────────┼──────────┼───────────────────────────────────────┤
│ Fully async     │ Medium   │ Entire frame is async/await even when │
│ main loop       │          │ most steps are sync-capable; extra    │
│                 │          │ microtask churn under load.           │
├─────────────────┼──────────┼───────────────────────────────────────┤
│ _updateInFlight │ Medium   │ Overlapping frames are dropped        │
│ frame drop      │          │ entirely rather than coalesced; long  │
│                 │          │ update stalls can skip input/draw     │
│                 │          │ ticks.                                │
├─────────────────┼──────────┼───────────────────────────────────────┤
│ Dual dispatch   │ Low      │ dispatch* pushes and calls            │
│ APIs            │          │ immediately; queue* only enqueues.    │
│                 │          │ Harness correctly uses queue* + main- │
│                 │          │ loop poll (no double callback).       │
│                 │          │ dispatch* is still a footgun.         │
├─────────────────┼──────────┼───────────────────────────────────────┤
│ Profile regions │ Low      │ Profile start/stop are awaited each   │
│ always          │          │ frame until disabled; fails closed    │
│ attempted       │          │ after first config exception.         │
└─────────────────┴──────────┴───────────────────────────────────────┘

Middle layers
Harness does real scheduling/backpressure. LoveScriptRuntime is a thin but allocation-prone callback façade. Host is a real adapter (not pure re-wrap).

Direction
1. Default all runtime/input traces off; if left on, skip map/string construction when sink is dead.
2. Cache resolved love.update / love.draw / event callback Values until globals change.
3. Prefer sync event drain + sync timer step; only await when a callback actually returns a Future.

───

1. filesystem/

Call chain (read hot path)

love.filesystem.read
  → factory (dispatch) → _LoveFilesystemBindings.read()
  → LoveFilesystemState.readAllBytesOrThrow
  → extension LoveFilesystemRuntimeReadWrite
      → _readableFileCandidate (scan roots + fileExists)
      → _readCandidateBytesOrThrow (fileExists again + read)
  → adapter (AssetBundle / Flutter / Lualike)
  → _readResult → Lua string / FileData wrapper

Relevant files under
/run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/filesystem/:
• love_filesystem_binding_dispatch.dart — pure factory indirection
• love_filesystem_binding_module_methods.dart — real arg parse + call
• love_filesystem_runtime.dart — public pass-through to extensions
• love_filesystem_runtime_read_write.dart — real read work
• love_filesystem_mount_resolution.dart — candidate building
• love_filesystem_path_model.dart — path objects / byte helpers
• love_asset_bundle_filesystem.dart — host adapter

Smells

┌─────────────┬──────────┬───────────────────────────────────────────┐
│ Smell       │ Severity │ Notes                                     │
├─────────────┼──────────┼───────────────────────────────────────────┤
│ Defensive   │ High     │ Virtual node: List<int>.from(node.        │
│ byte copies │          │ bytes!). LoveFilesystemFileData always    │
│ on every    │          │ does List.unmodifiable(bytes) (another    │
│ read        │          │ copy). IO device path: _                  │
│             │          │ bytesFromIODeviceValue always List.from.  │
│             │          │ Read → FileData can copy 2–3×.            │
├─────────────┼──────────┼───────────────────────────────────────────┤
│ Double      │ High     │ _readableFileCandidate checks fileExists; │
│ existence   │          │ _readCandidateBytesOrThrow checks again;  │
│ checks      │          │ open path may also open device after      │
│             │          │ readFileBytes miss. Multiple async hops   │
│             │          │ per file.                                 │
├─────────────┼──────────┼───────────────────────────────────────────┤
│ Linear      │ Medium   │ _readCandidatesResolved allocates a new   │
│ mount scan  │          │ List<_LoveResolvedPath> and walks all     │
│ every read  │          │ roots; no per-path cache / hash prefix    │
│             │          │ index. Fine for 1–2 roots; costly with    │
│             │          │ many mounts.                              │
├─────────────┼──────────┼───────────────────────────────────────────┤
│ Pass-       │ Low–     │ LoveFilesystemState.readAllBytes /        │
│ through API │ Medium   │ readFileData* / readAllBytesOrThrow are   │
│ surface     │          │ thin re-exports of extension methods;     │
│             │          │ readFileData ≡                            │
│             │          │ readFileDataIfExistsOrThrow. Not alloc-   │
│             │          │ heavy (extension apply), but cognitive/   │
│             │          │ maintenance noise.                        │
├─────────────┼──────────┼───────────────────────────────────────────┤
│ Binding     │ Low (    │ Each symbol does _LoveFilesystemBindings  │
│ dispatch    │ cold)    │ (context).method() at install time.       │
│ factories   │          │ Wrappers/methods do real work at call     │
│             │          │ time; Expando wrapper caches are good.    │
├─────────────┼──────────┼───────────────────────────────────────────┤
│ Mount data  │ Medium ( │ _dataBytes / mount prep use List<int>.    │
│ helpers     │ mount)   │ from even when source is already          │
│ always copy │          │ immutable Uint8List / FileData.           │
└─────────────┴──────────┴───────────────────────────────────────────┘

Does middle work?
Mount resolution and adapters do real work. Runtime public methods and binding dispatch are mostly re-wrap. Path-model readFileBytes on virtual nodes is a pure defensive copy with no extra logic.

Direction
1. Prefer zero-copy: store Uint8List, use Uint8List.sublistView / share immutable buffers; make FileData hold the buffer without List.unmodifiable copy when already unmodifiable.
2. Collapse resolve+read into one pass (exists check once, or open-or-null).
3. Cache last-hit root / physical path for hot logical paths (game assets).
4. Collapse duplicate readFileData* / extension façade into methods on the class.

───

2. audio/ + sound/ + flame audio

Call chain

love.audio.newSource
  → audio_bindings (_resolveAudioSourceInput)
  → filesystem read / FileData / SoundData / Decoder
  → LoveAudioSource (bytes copy) + host.createAudioSourceBackend
      → LoveFlutterAudioSourceBackend (another bytes copy)  OR
      → LoveFlameMediaKitAudioSourceBackend (stream)
  → Source.play → backend.setLooping/setVolume/seek/play

Files:
• .../audio/love_audio_support.dart
• .../love_api_bindings/audio_bindings.dart
• .../flame/love_flame_audio.dart
• .../flame/love_flame_media_kit_audio.dart
• .../sound/love_sound_support.dart

Smells

┌──────────────┬──────────┬──────────────────────────────────────────┐
│ Smell        │ Severity │ Notes                                    │
├──────────────┼──────────┼──────────────────────────────────────────┤
│ Triple+ byte │ High     │ FileData path: Uint8List.fromList(       │
│ copy on      │          │ fileData.bytes) in bindings →            │
│ newSource    │          │ LoveAudioSource constructor Uint8List.   │
│              │          │ fromList(bytes) → Flutter backend        │
│              │          │ Uint8List.fromList(bytes) again.         │
│              │          │ SoundData path re-encodes PCM to WAV (   │
│              │          │ loveEncodeSoundDataAsWaveBytes) before   │
│              │          │ playback.                                │
├──────────────┼──────────┼──────────────────────────────────────────┤
│ Metadata     │ High (   │ _tryDecodeAudioMetadata calls            │
│ decode may   │ load)    │ loveDecodeSoundFile on full bytes just   │
│ fully decode │          │ for duration/sampleRate; can allocate    │
│ file         │          │ full PCM on load for formats that need   │
│              │          │ full decode.                             │
├──────────────┼──────────┼──────────────────────────────────────────┤
│ Backend      │ Low      │ LoveAudioSourceBackend is a useful host  │
│ interface is │          │ seam, not empty.                         │
│ fine         │          │                                          │
├──────────────┼──────────┼──────────────────────────────────────────┤
│ Spatial/     │ Low      │ Vectors/effects live in Dart; no clear   │
│ effect state │          │ per-frame update loop for positional mix │
│ mostly CPU   │          │ (attenuation not applied every frame in  │
│ bookkeeping  │          │ support layer).                          │
├──────────────┼──────────┼──────────────────────────────────────────┤
│ SoundData    │ Medium   │ Builds ByteData.sublistView per sample;  │
│ getSample    │ if       │ fine for occasional use, bad if Lua      │
│              │ abused   │ samples every sample in a loop.          │
└──────────────┴──────────┴──────────────────────────────────────────┘

Middle layers
Bindings + LoveAudioSource do real policy (queue, offsets, clock). Host backends do real I/O. Extra copies between them are pure cost.

Direction
1. Pass ownership of one Uint8List from FS → source → backend (no re-copy if already Uint8List).
2. Prefer header-only metadata probes; avoid full PCM decode for duration.
3. For SoundData sources, feed PCM-capable backend path instead of WAV re-encode when possible.

───

3. input/ + flame input bridges

Call chain

Flutter key/pointer
  → LoveFlameInputAdapter (state update + geometry)
  → _dispatch → Future chain
  → LoveScriptRuntime.queue*
  → events.pushMessage
  → (later) processMainLoopEvents → love.* callback

Joystick:

LoveJoystickInputAdapter → queueJoystick* → same event queue

Files:
• .../flame/love_flame_input.dart
• .../input/love_joystick_input_adapter.dart
• .../input/love_input_support.dart
• .../input/love_touch_support.dart

Smells

┌──────────────────┬──────────┬──────────────────────────────────────┐
│ Smell            │ Severity │ Notes                                │
├──────────────────┼──────────┼──────────────────────────────────────┤
│ Per-event Future │ High     │ _dispatch does _dispatchQueue = _    │
│ chain            │          │ dispatchQueue.then(...) for every    │
│                  │          │ key/move/touch. High-rate pointer    │
│                  │          │ .move builds long Future chains;     │
│                  │          │ flush() must drain all of them each  │
│                  │          │ frame.                               │
├──────────────────┼──────────┼──────────────────────────────────────┤
│ Presentation     │ Medium   │ _logicalPoint / _logicalDelta call   │
│ geometry rebuilt │          │ loveFlamePresentationGeometry(...)   │
│ per pointer      │          │ and allocate Vector2s every time; no │
│ event            │          │ cached geometry for the frame.       │
├──────────────────┼──────────┼──────────────────────────────────────┤
│ Trace default on │ Medium   │ Same as runtime: builds detail maps  │
│ for touch        │          │ (including getTouches() → new list   │
│                  │          │ every call) even with prints         │
│                  │          │ disabled.                            │
├──────────────────┼──────────┼──────────────────────────────────────┤
│ Dual adapter     │ Low      │ Flame adapter + joystick adapter     │
│ layers           │          │ both own async queues; harness       │
│                  │          │ flushes both every frame — correct,  │
│                  │          │ but two serial waits.                │
├──────────────────┼──────────┼──────────────────────────────────────┤
│ LoveEventMessage │ Low      │ List.unmodifiable(arguments) per     │
│ always copies    │          │ event; fine at low rate, wasteful    │
│ args             │          │ for mousemove storms.                │
└──────────────────┴──────────┴──────────────────────────────────────┘

Middle layers
Adapters do real mapping (Flutter key → LOVE key/scancode, touch IDs, virtual gamepad). Queueing layer is necessary for LOVE main-loop semantics. The Future serial queue is the main mechanical cost.

Direction
1. Make queue* synchronous (only pushMessage); drop per-event Future unless callback is immediate.
2. Cache presentation geometry per frame / on viewport change.
3. Default touch traces off; getTouches() should return a reusable view or fill a caller buffer.

───

4. event/

Call chain

pushMessage → ListQueue
poll / processMainLoopEvents → callback name map → callLoveCallbackIfDefined
love.event.* bindings → same LoveEventState

Files:
• .../event/love_event_support.dart
• .../love_api_bindings/event_bindings.dart

Smells

┌────────────────┬──────────┬────────────────────────────────────────┐
│ Smell          │ Severity │ Notes                                  │
├────────────────┼──────────┼────────────────────────────────────────┤
│ pump() is a    │ Low      │ Production is elsewhere (input         │
│ no-op          │          │ adapters); correct for this            │
│                │          │ architecture, but love.event.pump does │
│                │          │ nothing useful.                        │
├────────────────┼──────────┼────────────────────────────────────────┤
│ toValues()     │ Low      │ Spreads new list for poll return; only │
│ allocates      │          │ when Lua polls.                        │
├────────────────┼──────────┼────────────────────────────────────────┤
│ String event   │ Low      │ _mainLoopCallbackName is a large       │
│ names + big    │          │ string switch; fine at event rates.    │
│ switch         │          │                                        │
├────────────────┼──────────┼────────────────────────────────────────┤
│ Double API     │ Medium   │ If any host path used dispatch*,       │
│ with dispatch* │          │ callbacks would run twice (immediate + │
│                │          │ later poll). Harness uses queue-only.  │
└────────────────┴──────────┴────────────────────────────────────────┘

Middle layers
Event state is real (queue + waiters). Bindings are thin and appropriate.

Direction
Keep queue-only path as the only production API; mark/remove dispatch* from hot host paths. Optionally pool event argument lists.

───

5. physics/

Call chain

World:update (Lua)
  → optional prepareContactFilterDecisions (async O(n²) pairs)
  → LovePhysicsWorld.update → forge2d World.stepDt
  → sync or queued contact callbacks → Lua via wrappers

Files:
• .../physics/love_physics_support.dart
• .../physics/love_physics_callback_support.dart
• .../physics/love_physics_contact_filter_support.dart
• .../love_api_bindings/physics_callback_object_wrappers.dart

Smells

┌─────────────────────┬──────────┬───────────────────────────────────┐
│ Smell               │ Severity │ Notes                             │
├─────────────────────┼──────────┼───────────────────────────────────┤
│ Async contact-      │ High     │ prepareDecisions nested loops all │
│ filter prep is O(   │          │ active fixtures, may await Lua    │
│ fixtures²)          │          │ filter per overlapping pair       │
│                     │          │ before step when sync Lua invoke  │
│                     │          │ is unavailable. Catastrophic with │
│                     │          │ many fixtures.                    │
├─────────────────────┼──────────┼───────────────────────────────────┤
│ bodies getter       │ Medium   │ List.unmodifiable(_bodies.        │
│ allocates every use │          │ where(...)); bodyCount uses       │
│                     │          │ bodies.length (filter+list just   │
│                     │          │ for count). Used by query/        │
│                     │          │ raycast/filter prep.              │
├─────────────────────┼──────────┼───────────────────────────────────┤
│ queryBoundingBox /  │ Medium   │ Nested body×fixture loops;        │
│ rayCast not using   │          │ correct but not forge2d query     │
│ broadphase          │          │ APIs.                             │
├─────────────────────┼──────────┼───────────────────────────────────┤
│ Per-contact wrapper │ Medium   │ Post-solve allocates impulse      │
│ + impulse lists     │          │ List.generate; fixtures re-       │
│                     │          │ wrapped for Lua each callback.    │
│                     │          │ Expando caches help identity but  │
│                     │          │ still table/arg churn.            │
├─────────────────────┼──────────┼───────────────────────────────────┤
│ Scale helpers       │ Low      │ scaleDownVector / scaleUpVector   │
│ allocate vectors    │          │ create new Vector2s; hot if used  │
│                     │          │ in Lua every body.                │
└─────────────────────┴──────────┴───────────────────────────────────┘

Middle layers
LovePhysicsWorld is a real forge2d adapter (meter scale, callbacks, filters). Binding layer is not empty — chooses sync vs async callback strategy for real runtime constraints.

Direction
1. Prefer/always use sync contact filter + callbacks when engine allows (avoid prep pass).
2. If async prep remains, use forge2d AABB broadphase / contact graph, not all-pairs.
3. bodyCount → O(1) counter; avoid allocating bodies for internal iteration (iterate _bodies with isDestroyed skip).

───

6. math/

Call chain

love.math.* bindings → love_math_support / LoveRandomGenerator / LoveBezierCurve
  → Expando-wrapped Lua tables (curves/generators)

Files:
• .../math/love_math_support.dart
• .../math/love_random_support.dart
• .../love_api_bindings/math_bindings.dart
• .../love_api_bindings/math_object_wrappers.dart

Smells

┌────────────────────┬─────────────┬─────────────────────────────────┐
│ Smell              │ Severity    │ Notes                           │
├────────────────────┼─────────────┼─────────────────────────────────┤
│ Color/gamma        │ Low         │ results + Value.multi per call; │
│ helpers allocate   │             │ only hot if used every draw     │
│ result lists       │             │ from Lua.                       │
├────────────────────┼─────────────┼─────────────────────────────────┤
│ Bezier render      │ Medium if   │ Copies control points,          │
│ allocates heavily  │ used live   │ subdivides into new lists,      │
│                    │             │ returns unmodifiable copy.      │
├────────────────────┼─────────────┼─────────────────────────────────┤
│ RNG / transform    │ Low         │ Expando caches good; thin       │
│ wrappers           │             │ bindings with real math         │
│                    │             │ underneath.                     │
└────────────────────┴─────────────┴─────────────────────────────────┘

Middle layers
Support code is real math. Wrappers are appropriate identity glue, not pure pass-through.

Direction
Only worth optimizing if games spam color conversion / Bezier render per frame; reuse scratch lists for multi-return color APIs.

───

7. font/

Call chain

Lua font APIs → font support / true type
  → LoveFlameHost text metrics (TextPainter + LRU caches)

Files:
• .../font/love_font_support.dart (+ true_type / default)
• host measurement in love_flame_host.dart

Smells

┌──────────────┬───────────┬─────────────────────────────────────────┐
│ Smell        │ Severity  │ Notes                                   │
├──────────────┼───────────┼─────────────────────────────────────────┤
│ Text wrap    │ High if   │ _wrapText measures per codepoint and    │
│ path is      │ wrap used │ kerning via full TextPainter.layout     │
│ extremely    │           │ through _measureTextWidth; cache helps  │
│ chatty       │           │ repeats but wrap of long strings still  │
│              │           │ does many unique keys (single char,     │
│              │           │ pairs).                                 │
├──────────────┼───────────┼─────────────────────────────────────────┤
│ Glyph/data   │ Low–      │ LoveGlyphData construction paths copy   │
│ objects copy │ Medium    │ pixel buffers; load-time cost.          │
│ bytes        │           │                                         │
├──────────────┼───────────┼─────────────────────────────────────────┤
│ Caches exist │ Positive  │ Metrics cache 64, text width 512 — good │
│ and are      │           │ structural choice.                      │
│ sized        │           │                                         │
└──────────────┴───────────┴─────────────────────────────────────────┘

Middle layers
Host measurement is real work. Font support models are real, not wrappers-only.

Direction
Use Paragraph/TextPainter once per wrap pass (or measure runs), not per-codepoint string measure. Cache advances/kerning by glyph id, not by full text substrings only.

───

8. window / system / thread / video / data

window
• Mostly constants + message-box types in love_window_support.dart; metrics live on host (LoveFlameHost.windowMetrics).
• Hot path risk: low. Host rebuilds displays list if override null (loveDefaultWindowDisplaysForMetrics) — avoid calling every frame from Lua.
• Indirection: thin; host is real.

system
• LoveSystemState holds OS/power/clipboard handlers — simple state bag.
• Hot path risk: low. Clipboard handlers async only when used.
• Indirection: appropriate.

thread
• In-process channels (LoveThreadChannel) with queues/completers — not OS threads.
• Hot path risk: low unless polling channels every frame with large payloads (values stored as-is; no deep copy, good).
• Smell: supply/demand use Future.any + delayed timeout Futures (alloc on wait).

video
• Metadata + delta sync are light; frame provider is factory-injected (createVideoFrameProvider).
• Hot path: frame snapshot path lives more in graphics/overlay (out of non-graphics deep review); backend not no-op when configured.
• Media-kit init is cold.

data
• Smell (Medium): _loveDataBytes / binding extractors routinely List<int>.from / copy into Uint8List for compress/encode/hash.
• Correct for immutability; wasteful for large buffers or repeated encode.
• Direction: accept Uint8List without copy; use views for slices (loveDataSlice already uses sublistView after normalize).

───

Cross-cutting severity ranking

Fix first (real hot-path cost)
1. Runtime/input tracing defaults allocating on every update/touch while doing nothing.
2. Filesystem read double-check + multi-copy bytes (List.from / unmodifiable / audio re-copies).
3. Audio newSource byte-copy chain (and optional full decode for metadata).
4. Input _dispatch Future chain on high-frequency pointer moves.
5. Physics async contact-filter all-pairs prep when sync callbacks unavailable.

Fix next
6. Per-frame callback field lookup without cache.
7. Physics bodies / bodyCount allocation.
8. Font wrap per-codepoint TextPainter usage.
9. Presentation geometry rebuild per pointer event.

Mostly structure / cold
10. Filesystem binding dispatch + extension pass-through façade.
11. window/system/thread thin layers (acceptable).
12. Archive 7z/ISO paths (intentionally heavy).

───

Layering summary

┌──────────────┬───────────────────┬─────────────────────────────────┐
│ Subsystem    │ Real work layers  │ Pass-through / re-wrap          │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ Frame loop   │ harness           │ LoveScriptRuntime callback      │
│              │ scheduling, host  │ helpers (thin)                  │
│              │ graphics snapshot │                                 │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ filesystem   │ mount resolve,    │ dispatch factories;             │
│              │ adapter I/O,      │ LoveFilesystemState → extension │
│              │ archive decode    │ re-exports; many byte re-wraps  │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ audio        │ source state      │ repeated Uint8List.fromList     │
│              │ machine, backends │ between layers                  │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ input        │ Flutter→LOVE      │ async queue wrapper around      │
│              │ mapping           │ already-queued events           │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ event        │ queue             │ pump no-op; bindings thin       │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ physics      │ forge2d + scale + │ Lua object wrappers (needed);   │
│              │ callbacks         │ all-pairs filter prep is extra  │
│              │                   │ policy layer                    │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ math         │ math impl         │ Expando tables (needed)         │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ font         │ raster/metrics    │ host cache is valuable          │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ data         │ compress/hash     │ copy-happy normalizers          │
├──────────────┼───────────────────┼─────────────────────────────────┤
│ window/      │ state + host      │ mostly thin, OK                 │
│ system/      │ hooks             │                                 │
│ thread/video │                   │                                 │
└──────────────┴───────────────────┴─────────────────────────────────┘

───

Suggested consolidation direction (mechanical)

1. One buffer ownership rule: Uint8List moves FS → FileData → Sound/Audio without copy unless mutation is required.
2. One event path: sync push from input; only main loop invokes Lua; delete or quarantine dispatch*.
3. One physics step path: sync filters/callbacks by default; treat async prep as fallback, never all-pairs.
4. One frame-time debug switch: compile-time off by default; zero work when off (not “build strings then no-op”).
5. Collapse FS public API onto methods that implement work directly; keep adapters as the only host boundary.
