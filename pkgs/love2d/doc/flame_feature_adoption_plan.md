# Flame Feature Adoption Plan

## Status

- Date: `2026-04-22`
- Package: `pkgs/love2d`
- Current runtime baseline: `flame ^1.37.0`, `flame_forge2d ^0.19.2+6`
- Goal: use more of Flame's built-in camera, widget, component, batching, input, and asset-caching capabilities without weakening `LÖVE 11.5` parity, while also reducing pauses, stutter, and first-use hitches.

## Why This Plan Exists

The current `love2d` Flame harness is functionally strong, but it still uses Flame mostly as a host for the game loop, asset cache, and canvas access. Several responsibilities that Flame already solves are implemented manually in our compatibility layer:

- viewport fit and coordinate conversion
- focus, cursor, and overlay ownership around `GameWidget`
- presentation-layer composition
- common-case sprite batching
- controller/device integration
- whole-surface post-processing

That duplication increases maintenance cost, makes resize/input/presentation behavior easier to break, and keeps too much expensive work close to interactive frames. The point of this plan is not to rewrite the LOVE renderer into "pure Flame." The point is to move repeated infrastructure concerns onto Flame where Flame is already the better owner, and to make performance work explicit instead of incidental.

## Non-Goals

- Do not rewrite the full recorded-command renderer into one Flame component per LOVE draw call.
- Do not replace LOVE per-draw shader semantics with Flame post-processing. Those are different layers.
- Do not trade away conformance or deterministic testing just to use more engine features.
- Do not remove fallback paths for unsupported blend, shader, scissor, or texture cases.

## Current Implementation Status

- Phase 1 is effectively landed:
  - the LOVE presentation surface now sits behind `CameraComponent.withFixedResolution`
  - pointer conversion now goes through camera-backed presentation geometry
  - overlay placement uses the same presentation source of truth
  - host viewport size is tracked separately from LOVE logical mode size
- Phase 2 is partly landed:
  - `GameWidget` now owns the focus node and live video overlay registration
  - key delivery is routed through Flame keyboard integration
  - text-input and cursor synchronization are now event-driven rather than frame-polled
  - the remaining wrapper code is mostly there for LOVE-specific pointer enter/exit behavior and image-backed cursor hotspots
- The startup warmup slice is now partly landed:
  - bundle-backed source-root images are discovered through `LoveAssetBundleFilesystemAdapter` and prewarmed into Flame's image cache before the harness reports `Running`
  - the harness now exposes an explicit `Prewarming` phase and waits for `game.images.ready()` plus requested first-frame shader warmup before interaction begins
  - registered fragment shaders still keep their background warmup queue
- The biggest remaining performance gap is now scene-level image warmup and common-path cache ownership:
  - startup/root-bundle image warmup exists, but scene manifests and transitions do not yet drive preload sets
  - bundled LOVE images still construct host-side wrappers lazily on first `newImage` / `newImageData` use, even when the underlying Flame image is already cached
- The next highest-return work is:
  - add benchmark traces for existing example scenes
  - wire the new frame-timing and renderer layer/fallback counters into benchmark capture
  - extend preload from startup/root discovery into scene-level manifests
  - lower eligible sprite-batch and particle paths to Flame batching
  - audit remaining `saveLayer` hotspots with parity coverage

## Review Summary

| Priority | Current issue | Existing local implementation | Flame feature to adopt | Expected benefit |
| --- | --- | --- | --- | --- |
| High | Viewport and logical-coordinate math are duplicated | `love_flame_harness_renderer.dart`, `love_flame_harness.dart`, `love_flame_input.dart`, `love_flame_live_video_overlay.dart`, `love_flame_viewport_geometry.dart` | `CameraComponent.withFixedResolution`, `FixedResolutionViewport`, camera `globalToLocal` / `localToGlobal` | One source of truth for presentation geometry |
| Medium | Harness reimplements widget responsibilities | Outer `Focus`, `MouseRegion`, `Listener`, per-frame sync in `love_flame_harness.dart` | `GameWidget` focus, cursor, overlays, and keyboard integration | Less widget glue and fewer event-order bugs |
| Medium | LOVE surface is not modeled as a Flame component | `LoveFlameHarnessGame` plus large custom render switch | `CustomPainterComponent`, world/camera layering, `Snapshot` where useful | Simpler composition, easier HUD/effect attachment |
| Medium | Sprite batches and particles render via per-entry loops | `_renderSpriteBatchCommand`, `_renderParticleSystemCommand` | `SpriteBatch`, `HasAutoBatchedChildren` where safe | Better performance in common texture-atlas paths |
| Medium | Controller support is mostly synthesized from keyboard input | `love_flame_gamepad_bridge.dart` | `flame_gamepads`, `gamepads` | Real controller parity and less custom device plumbing |
| High | Frame pacing and warmup still need scene-level coverage and measurement | Startup bundle-image prewarm in `love_flame_harness.dart`, cache seeding in `love_flame_host.dart`, targeted first-frame shader readiness in `love_registered_fragment_shader_cache.dart`, repeated `TextPainter` / `saveLayer` hotspots, per-entry sprite and particle loops | `Images.add`, future scene-level `Images.loadAll`, `images.ready()`, targeted `Snapshot`, plus the existing shader warmup queue | Fewer first-use pauses and lower frame-time variance |
| Low | Whole-surface effects are harder than they need to be | Custom rendering only | `CameraComponent.postProcess`, `PostProcessComponent` | Cleaner support for CRT/bloom/scanline-style screen effects |

## Current Code-Backed Findings

- Image loading is still the main Flame underuse point:
  - The harness now prewarms bundle-backed source-root images into Flame's cache before it reports `Running`.
  - `LoveFlameHost.loadImage` also accepts resolved asset keys, so mounted LOVE-relative paths can reuse already-cached Flame images instead of decoding the same UI image twice.
  - The remaining gap is that scene-specific preload sets are still implicit:
    - startup/root discovery exists
    - scene manifests and `Images.loadAll(...)`-style bulk preload are still future work
- The filesystem layer already gives us the asset inventory we need for preload planning:
  - `LoveAssetBundleFilesystemAdapter` loads `AssetManifest` and builds normalized file and directory indexes
  - that means scene preload manifests can be validated against mounted LOVE-visible paths without maintaining a separate Flutter-only list
- Shader warmup is already ahead of image warmup:
  - the harness already calls `prewarmShaderAssetsInBundle(...)` during initialization
  - presented frames already mark fragment assets as requested
  - startup now has an explicit readiness barrier for the presented frame's requested shader assets
  - scene transitions still need the same hook once preload manifests exist
- Event-driven synchronization is no longer a future task, it is current architecture:
  - keyboard and mouse state are now `ChangeNotifier`-driven
  - the old frame-polled text-input ticker is gone
  - future harness work should preserve that direction rather than reintroducing polling
- Text layout now has bounded cache ownership in the existing architecture:
  - the renderer now reuses laid-out `TextPainter` instances for stable rich-text draw inputs
  - the text-layout render counters now include both `love.graphics.print`
    commands and `Text` object commands
  - host-side true-type font measurement now reuses cached font metrics and measured widths for repeated wrap and kerning queries
  - text-heavy scenes should still be part of the benchmark set so we validate cache hit rate and eviction behavior under real content
- The `Modern Pong` CPU profiler captures showed a different text hotspot:
  - sampled cost was concentrated in `LoveTextCommand` construction through
    `LoveFont.copy`, not in repeated Flutter text layout
  - `LoveTextCommand` now snapshots the font through a private fast path that
    preserves public `LoveFont.copy()` semantics while avoiding repeated
    cloning of already-immutable glyph and kerning maps
  - the command still owns an isolated font object and copied fallback list, so
    later `Font:setFallbacks(...)` or graphics-font mutation does not affect a
    recorded draw command
- The `Pocket Bomber` captures showed the next font-copy source:
  - `love.graphics.push` and `love.graphics.setNewFont` were spending time in
    `LoveGraphicsState.copy -> LoveFont.copy -> _immutableGlyphMetricMap`
  - graphics state stack copies now preserve the current `Font` object by
    reference, which removes repeated glyph-map cloning and better matches LOVE
    object semantics for `push("all")` / `pop`
- The `Pocket Bomber` in-game captures also exposed mesh setup allocation:
  - `love.graphics.draw(mesh)` was spending time in
    `LoveMeshCommand -> LoveMesh.copyForDraw -> LoveMesh.copy`
  - `LoveMesh` now caches draw snapshot vertices and effective draw vertices by
    revision, and command snapshots use copy-on-write protection so recorded
    commands stay isolated from later mesh mutation without copying every vertex
    on every draw call
- The renderer now exposes per-frame counters for the biggest remaining hot paths:
  - command blend layers
  - shader-filter layers
  - radial-mask layers
  - image and mesh composition layers
  - software surface fallbacks
  - that gives us a code-backed way to compare scenes before trying riskier `saveLayer` removals
- The harness game now keeps a rolling frame-timing window for benchmark capture:
  - average, p95, and worst-frame delta/update/render CPU timings are available from one place
  - recent frame samples still carry the per-frame render counters, so benchmark scenes can aggregate layer and fallback behavior without re-instrumenting draw code
- The repo now has the first example-scene benchmark smoke coverage:
  - `example/test/flame_example_benchmark_smoke_test.dart` mounts `Modern Pong` and the default `LOVE Test Bed`
  - each scene is run twice so the test can report separate cold and warm startup/frame summaries before we set real budgets
  - the Flame renderer now uses bounded software patch regions for unsupported commands when their affected bounds are known, instead of forcing the whole surface through CPU rasterization
  - the first real win is already measurable: on `2026-04-22`, the `LOVE Test Bed` smoke run dropped from roughly `295-317 ms` average CPU frame cost under whole-surface fallback to roughly `31-32 ms` after moving additive arc blending and the scissored masked text path onto bounded software patches
  - a second renderer-bound win is now also measured: later on `2026-04-22`, the `Modern Pong` smoke run dropped from roughly `81-83 ms` average CPU frame cost to roughly `0.44-0.50 ms` after keeping source-backed images on the native-image rendering path instead of forcing live rendering through decoded `ImageData`
  - eligible sprite-batch and particle-system draws now opportunistically lower to Flame `SpriteBatch` whenever a decoded `ui.Image` is available, even if the source `LoveImage` still keeps `preferImageDataRendering` enabled for parity elsewhere
  - `Canvas:newImageData()` on `LoveFlameHost` now prefers the existing Flutter/Flame surface painter plus `ui.Image.toByteData(...)` before falling back to the software rasterizer, which matters because the default `LOVE Test Bed` scene performs a canvas readback every frame
  - immutable `LoveCanvasSnapshot` instances are now reused within one canvas surface revision, and the Flame renderer lowers repeated snapshot draws onto cached `ui.Picture` recordings instead of replaying the nested canvas surface every time
  - the benchmark smoke now reports atlas-batch usage directly; in the latest `2026-04-22` smoke runs, `LOVE Test Bed` held at `avg_atlas_batches=2.0` and `avg_atlas_items=10.0` while `Modern Pong` correctly stayed at `0.0`
  - that host-side canvas-readback change remains the last clearly measurable follow-on win; after the snapshot/picture reuse work, `LOVE Test Bed` still sits roughly in the `29.7-30.9 ms` average CPU frame band, which is directionally fine but not yet a decisive new step down
  - the `avg_commands` metric for `LOVE Test Bed` now reports roughly `21.0` instead of the earlier `29.0` because repeated canvas snapshot draws no longer replay their nested surface command list through the hot render loop
  - after extending text counters to include `love.graphics.print`, the latest
    `Modern Pong` smoke run reported `0.465 ms` cold average CPU,
    `0.564 ms` warm average CPU, `avg_text_hits=2.0`,
    `avg_text_misses=0.0`, and `avg_text_layout_ms=0.000`
  - the contrast between `Modern Pong` and `LOVE Test Bed` is now even sharper: some scenes were dominated by unnecessary CPU image blits, some kept paying for host-side canvas readback, and the remaining `LOVE Test Bed` cost is now more clearly elsewhere
  - the latest `LOVE Test Bed` smoke run reported `avg_text_hits=5.0`,
    `avg_text_misses=0.0`, `avg_text_layout_ms=0.000`, `29.312 ms` cold
    average CPU, and `32.394 ms` warm average CPU, so the next Test Bed
    investigation should focus on remaining replay/render cost rather than
    text-layout misses
  - heavier examples such as `Shader Explorer` still need follow-up automation work before they are stable benchmark targets in widget tests
- The remaining hot rendering paths are concrete and localizable:
  - `saveLayer` is still used in command-level blending, image tint/shader composition, mesh tint paths, and surface clears
  - unsupported draw states still exist, but we no longer need to choose only between "fully wrong fast path" and "whole-surface CPU fallback" when the affected region is bounded
  - ineligible sprite-batch and particle-system draws still render entry-by-entry through `_renderResolvedImage(...)`
  - mutable and generated images can now stay on the native-image path on the Flame host when the host successfully refreshes their decoded texture, but headless/runtime-only hosts still correctly fall back to `ImageData`
  - those are the best next targets for reducing frame-time variance
- Some Flame features are valuable now, and some only become valuable after more structure:
  - `SpriteBatch` is immediately relevant for eligible atlas-backed sprite and particle draws
  - `HasAutoBatchedChildren` is probably not an immediate win for the recorded-command renderer because the LOVE surface is not yet represented as a tree of sprite components
  - `CameraComponent.postProcess` becomes the clean whole-surface effect hook after the LOVE surface is a first-class component in the camera-managed world

## Adoption Principles

- Preserve LOVE semantics first. Flame is the implementation aid, not the compatibility target.
- Move responsibilities to Flame only when Flame can become the clear owner.
- Treat first-use hitches and steady-state frame cost as separate performance problems with separate fixes.
- Keep one canonical source of truth for each concern:
  - logical game resolution
  - host widget/window size
  - presented destination rect
  - pointer coordinate conversion
- Prefer additive migrations with fallback paths over flag-day rewrites.
- Prefer preload, warmup, and event-driven synchronization over doing expensive work during interactive frames.
- Require parity tests before deleting the old path.
- If a Flame integration only makes the code look more "engine-native" but does not reduce risk or complexity, do not take it.

## Performance Objectives

- Define explicit budgets for representative scenes:
  - average frame time
  - p95 frame time
  - worst-frame spikes
- Measure cold-cache and warm-cache behavior separately.
- Move known first-use work behind preload or scene-readiness boundaries where practical:
  - image decode and cache fill
  - shader warmup
  - text layout warmup when predictable
  - scene/bootstrap initialization
- Reduce avoidable interactive-frame work:
  - frame-polled synchronization
  - repeated layout/allocation on hot paths
  - avoidable `saveLayer` usage
  - avoidable per-entry draw loops
- Do not accept "faster on average" if frame-time variance or visible stutter gets worse.

## Success Criteria

We should consider this plan successful when all of the following are true:

- viewport fit math is centralized behind the Flame camera/viewport layer instead of repeated across renderer, input, and overlay code
- the harness wrapper delegates most focus, overlay, and cursor ownership to `GameWidget`
- the presented LOVE surface exists as a Flame component within a camera-managed world
- common sprite-batch and particle paths can use Flame batching when the render state allows it
- real gamepads can drive `love.joystick` / `love.gamepad*` callbacks through a platform backend
- optional whole-surface effects can be added without threading custom effect code through every draw path
- frame-time budgets exist for representative scenes and target platforms
- known first-use work is moved behind preload/warmup boundaries where practical
- steady-state hot paths reduce avoidable polling, allocation, and layer creation enough to lower visible stutter, not just average cost

## Performance Workstream

### Goal

Make frame pacing, hitch reduction, and hot-path cost explicit acceptance criteria across all phases instead of assuming they will improve automatically.

### Main performance risks today

- bundled LOVE image loads now have a startup warmup path, but the common runtime path still relies on lazy wrapper creation and does not yet use scene manifests
- shader warmup support now has a startup readiness barrier, but scene transitions do not yet reuse it
- text layout is now cached in both the renderer and host measurement path, but it still needs real-scene tracing to confirm hit rates and eviction sizing
- the renderer has multiple `saveLayer` paths that should be justified individually
- sprite-batch and particle rendering still rely on per-entry loops in the common path
- the benchmarking story is no longer implicit for the first two scenes because we now have repeatable cold-cache and warm-cache widget-test traces for `Modern Pong` and the default `LOVE Test Bed`, but the scene set is still too small to treat those traces as global budgets

### Flame features and local hooks to adopt

- `Images.add`
- `Images.loadAll`
- `Images.ready()`
- direct `SpriteBatch`
- targeted `Snapshot` caching where invalidation is simple
- existing registered shader prewarm queue in `love_registered_fragment_shader_cache.dart`

### Likely files

- `lib/src/runtime/flame/love_flame_host.dart`
- `lib/src/runtime/flame/love_registered_fragment_shader_cache.dart`
- `lib/src/runtime/flame/love_flame_harness.dart`
- `lib/src/runtime/flame/love_flame_harness_renderer.dart`
- `lib/src/runtime/filesystem/love_asset_bundle_filesystem.dart`
- any benchmark or profiling harness files added under `example/`, `tool/`, or `test/`

### Concrete tasks

- Extend the landed rolling frame-timing and renderer layer/fallback counters with before/after traces for representative scenes.
- Capture both cold-cache and warm-cache runs for:
  - startup
  - first scene entry
  - dense sprite scenes
  - dense particle scenes
  - text-heavy scenes
- Introduce scene-level preload manifests where the upcoming content is predictable.
- Add a LOVE-path-to-Flame-asset resolver so a mounted LOVE asset can be:
  - preloaded with `game.images.loadAll(...)` when it maps cleanly to a Flame asset key
  - seeded into the Flame cache with `game.images.add(...)` when we only have raw mounted bytes
- Keep `LoveFlameHost._images` and `game.images` aligned so we do not decode the same image twice into two ownership paths.
- Wait on `game.images.ready()` before interactive frames where the preload set is known.
- Extend the existing registered-shader warmup path so scene startup can request or await fragment assets that will be needed immediately.
- Preserve the new event-driven synchronization model and replace any newly discovered polling with notifier-driven paths where platform behavior allows it.
- Trace the new text-layout caches under representative text-heavy scenes and tune cache sizing only if the hit rate justifies it.
- Audit every `saveLayer` site and narrow or remove layers that are not required for correctness.
- Track allocation churn in sprite, particle, mesh, and text-heavy scenes and cache or pool short-lived objects only when ownership and invalidation are clear.

### Immediate execution order

1. Build the image preload path first.
   - Startup/root-bundle preload is now landed.
   - The next step is to move from source-root discovery to explicit scene manifests.
   - Make asset resolution explicit:
     - LOVE logical path
     - mounted/bundled asset key
     - Flame image-cache key
2. Add an awaitable readiness barrier.
   - Startup now waits for:
     - image preload completion
     - `game.images.ready()`
     - requested registered-shader warmup completion
   - The next step is to reuse the same barrier shape for scene transitions so we do not show "running" for the next scene while predictable work is still pending.
3. Reuse existing example apps as the initial benchmark set.
   - `example/lib/main_pong.dart` for steady 2D gameplay and resize behavior
   - `example/lib/main_shader_explorer.dart` for fragment shader and effect startup
   - `example/lib/main_example_video.dart` for video composition and overlay behavior
   - `example/lib/main_pocket_bomber.dart` or `example/lib/main_example_browser.dart` for broader content coverage
4. Attack the render hot paths that remain after preload.
   - text layout allocation
   - `saveLayer` overuse
   - per-entry sprite and particle loops
5. Only then decide whether the next higher-return Flame-native move is:
   - direct `SpriteBatch` lowering
   - selective `Snapshot` caching
   - deeper component extraction from Phase 3

### Guardrails

- Do not preload every asset globally; preload by scene, feature, or known hotspot so memory growth stays bounded.
- Do not assume every LOVE image path is a valid Flame cache key; make path normalization and cache-key ownership explicit.
- Do not introduce caches that can leak mutable render state across draws.
- Do not remove `saveLayer` or layout work unless parity tests prove the rendered result is still correct.
- Always evaluate cold-start and warm-cache performance separately.

### Tests to require

- benchmark scenes with cold-cache and warm-cache runs
- scene-startup and scene-transition smoke tests that wait for preload barriers
- visual parity tests around any `saveLayer` removal or text-layout caching
- profiling notes from at least one representative desktop target and one additional target class when available

### Exit criteria

- representative scenes have defined budgets and before/after timing traces
- first-use image and shader hitches are either eliminated or deliberately isolated behind loading/readiness boundaries
- no known harness-level frame polling remains where an event-driven path can provide equivalent behavior
- frame-time variance improves alongside average cost

## Phase 0: Baseline And Decision Record

### Goal

Create a stable baseline so we can refactor aggressively without losing parity, accidentally changing resolution semantics, or losing track of frame-time behavior.

### Why this comes first

The largest architectural risk is that the current harness mixes two ideas:

- host window size from Flutter
- a persistent LOVE logical presentation size

Today those concerns are close enough together that resize handling can fight the intended logical-resolution model. We need a written decision before we move camera ownership into Flame.

### Scope

- define the source of truth for logical resolution versus host window metrics
- capture current behavior with tests and a short architecture note
- capture current performance behavior with traces and benchmark scenes
- decide which existing helper APIs are transitional and which should remain public

### Likely files

- `lib/src/runtime/flame/love_flame_harness.dart`
- `lib/src/runtime/flame/love_flame_viewport_geometry.dart`
- `test/love_flame_viewport_geometry_test.dart`
- `test/love_flame_input_test.dart`
- `test/love_flame_live_video_overlay_geometry_test.dart`
- `test/love_flame_harness_presentation_notifier_test.dart`
- `doc/flame_feature_adoption_plan.md`
- any new benchmark scenes or profiling helpers under `example/`, `tool/`, or `test/`

### Concrete tasks

- Write a short internal note for these invariants:
  - what `love.window` width and height mean
  - what the logical render surface size means
  - which layer owns letterboxing and scaling
  - which layer owns pointer conversion
- Add or extend tests that pin:
  - resize behavior
  - letterbox destination rect behavior
  - logical-to-viewport and viewport-to-logical conversion
  - video overlay alignment
- Add a small benchmark scene or smoke harness for:
  - resize stress
  - dense sprite batch
  - dense particle system
- Seed the first benchmark runs from existing examples before creating synthetic scenes from scratch:
  - `example/lib/main_pong.dart`
  - `example/lib/main_shader_explorer.dart`
  - `example/lib/main_example_video.dart`
  - `example/lib/main_pocket_bomber.dart` or `example/lib/main_example_browser.dart`
- Capture baseline traces for:
  - cold start
  - warm start
  - first scene entry
  - first-use shader/image paths
- Define initial target budgets for the benchmark scenes, even if they are provisional and platform-specific.

### Acceptance criteria

- the team has a single written definition for logical size, host size, and presented size
- current behavior is pinned well enough that later phases can refactor safely
- at least one benchmark scene exists for sprite-heavy and particle-heavy content
- baseline timing traces and initial frame/hitch budgets exist before major refactors start

## Phase 1: Camera And Viewport Normalization

### Goal

Move presentation geometry ownership to Flame's camera and fixed-resolution viewport support.

### Flame features to adopt

- `CameraComponent.withFixedResolution`
- `FixedResolutionViewport`
- camera `globalToLocal`
- camera `localToGlobal`

### Current pain points

- logical viewport fitting is duplicated in multiple files
- overlay placement and pointer conversion each re-derive the same destination rect
- resize changes can leak into runtime metrics in ways that are easy to misinterpret

### Likely files

- `lib/src/runtime/flame/love_flame_harness_renderer.dart`
- `lib/src/runtime/flame/love_flame_harness.dart`
- `lib/src/runtime/flame/love_flame_input.dart`
- `lib/src/runtime/flame/love_flame_live_video_overlay.dart`
- `lib/src/runtime/flame/love_flame_viewport_geometry.dart`

### Concrete tasks

- Introduce a camera-owned presentation model for the LOVE surface.
- Keep a clear split between:
  - logical surface size
  - host widget/window size
  - actual viewport destination rect
- Replace manual destination-rect consumers with camera conversions.
- Convert pointer mapping to use camera coordinate conversion instead of duplicated geometry helpers.
- Update video overlay placement to query the same presentation source of truth.
- Reduce `love_flame_viewport_geometry.dart` to a thin adapter layer or remove it once call sites are migrated.

### Guardrails

- Do not let camera normalization change LOVE-facing width and height semantics without an explicit compatibility decision.
- Preserve existing letterboxing behavior.
- Preserve pixel-stable coordinate conversion for mouse, touch, and video overlay placement.

### Tests to require

- `test/love_flame_viewport_geometry_test.dart`
- `test/love_flame_input_test.dart`
- `test/love_flame_live_video_overlay_geometry_test.dart`
- new resize-source-of-truth tests in the harness layer

### Exit criteria

- no production code outside the camera/presentation adapter computes destination rects independently
- pointer conversion, overlay placement, and presentation sizing all come from the same camera-owned geometry

## Phase 2: `GameWidget` Ownership Cleanup

### Goal

Let `GameWidget` own more of the focus, overlay, and keyboard surface, keeping custom wrapper logic only where Flame cannot express the required LOVE behavior.

### Flame features to adopt

- `GameWidget.focusNode`
- `GameWidget.overlayBuilderMap`
- `GameWidget.mouseCursor`
- Flame keyboard/event integration from `events.dart`

### Current pain points

- the harness wraps `GameWidget` with extra `Focus`, `MouseRegion`, and `Listener` layers
- text-input and cursor synchronization does more polling than it should
- overlay ownership is split across widget-level code and game-level state

### Likely files

- `lib/src/runtime/flame/love_flame_harness.dart`
- `lib/src/runtime/flame/love_flame_input.dart`
- `lib/src/runtime/flame/love_flame_live_video_overlay.dart`

### Concrete tasks

- Move overlay registration to `GameWidget.overlayBuilderMap` where the overlay is conceptually game-owned.
- Route focus management through a dedicated `GameWidget` focus node.
- Use Flame's keyboard event integration for the game-facing part of the pipeline, and keep custom dispatch only for LOVE-specific translation.
- Replace per-frame synchronization with event-driven updates wherever platform APIs allow it.
- Keep the custom wrapper only for concerns that still exceed `GameWidget`:
  - IME editing rectangle integration
  - image-backed cursor hotspots
  - any platform event types Flame does not surface directly

### Guardrails

- Preserve keypress ordering relative to the LOVE event queue.
- Preserve web and desktop focus reacquisition behavior.
- Do not regress cursor fallback behavior for platforms that cannot use custom image cursors.

### Tests to require

- existing harness input and focus tests
- new focus reacquisition tests
- new overlay lifecycle tests
- new cursor-behavior tests for supported fallback paths

### Exit criteria

- the harness no longer duplicates `GameWidget` behavior unless a LOVE-specific requirement forces it
- text-input and cursor synchronization are mostly event-driven rather than frame-polled

## Phase 3: Represent The LOVE Surface As A Flame Component

### Goal

Keep the recorded-command renderer, but host it inside a proper Flame world/camera/component structure.

### Flame features to adopt

- `CustomPainterComponent`
- world plus camera composition
- `Snapshot` mixin in targeted caching scenarios

### Why this matters

Right now the LOVE surface is effectively a large custom render procedure attached to the game. That works, but it makes it harder to use Flame for composition. Turning the presented surface into a component is the smallest refactor that unlocks:

- camera-managed world placement
- clearer separation between scene content and Flutter overlays
- optional snapshot caching for stable subtrees
- later post-processing around the entire presented output

### Likely files

- `lib/src/runtime/flame/love_flame_harness_renderer.dart`
- `lib/src/runtime/flame/love_flame_harness.dart`
- new component file such as `lib/src/runtime/flame/love_flame_surface_component.dart`

### Concrete tasks

- Extract the recorded-command presentation layer into a dedicated Flame component.
- Keep the command interpreter intact initially; only move its ownership boundary.
- Mount the component in a world controlled by the fixed-resolution camera from Phase 1.
- Separate HUD-style attachments from the presented LOVE surface where that reduces widget coupling.
- Evaluate `Snapshot` only for expensive content with simple invalidation rules, such as cached static presentation layers or infrequently changing surfaces.

### Guardrails

- Do not explode the renderer into hundreds of tiny components.
- Do not introduce caching without an invalidation story.
- Keep deterministic rendering tests as the authority, not component purity.

### Tests to require

- existing render goldens around transforms, scissor, shaders, meshes, and video composition
- new mount/unmount lifecycle tests for the surface component
- new snapshot invalidation tests if any caching is added

### Exit criteria

- the LOVE surface is rendered by a dedicated Flame component inside a camera-managed world
- the giant render switch still exists only where it adds compatibility value, not because composition is missing

## Phase 4: Batching And Hot-Path Lowering

### Goal

Use Flame's batching features for common cases while preserving the current renderer as the fallback path.

### Flame features to adopt

- `SpriteBatch`
- `HasAutoBatchedChildren` where component composition makes it practical

### Current pain points

- sprite-batch commands render entry-by-entry even when they share atlas state
- particle rendering also loops entry-by-entry
- safe batching opportunities are likely being left on the table

### Likely files

- `lib/src/runtime/flame/love_flame_harness_renderer.dart`
- any new internal batch cache or adapter file under `lib/src/runtime/flame/`
- `test/love_sprite_batch_advanced_test.dart`
- `test/love_particle_system_state_test.dart`

### Concrete tasks

- Add a backend path that lowers eligible sprite-batch draws to Flame `SpriteBatch`.
- Prefer direct `SpriteBatch` construction from already-resolved atlas images instead of routing everything back through asset-path loading helpers.
- Define a strict eligibility check for batching:
  - shared texture/atlas
  - compatible blend mode
  - no unsupported shader state
  - no per-entry state that breaks batching
- Add a similar opportunistic path for particle-system draws when the same restrictions hold.
- Keep the existing per-entry path as the compatibility fallback.
- Treat `HasAutoBatchedChildren` as a later optimization for any newly componentized sprite groups, not as the first batching move for the recorded-command renderer.
- Add instrumentation counters so we can see how often content uses the fast path versus fallback, and compare frame-time variance before and after batching.

### Status on 2026-04-22

- The renderer now has conservative `SpriteBatch` lowering for sprite-batch and particle-system commands in `love_flame_harness_renderer.dart`.
- Source-backed images loaded through `LoveFlameHost` no longer get forced onto the CPU image-data path merely because decoded `ImageData` is also available.
- `love.graphics.newImage(imageData)` and `Image:replacePixels(...)` now attempt to refresh a native image through the active host; when that succeeds on the Flame host, live rendering can stay on the fast path without losing updated pixels.
- `Canvas:newImageData()` on `LoveFlameHost` now first tries to read back through the same Flutter/Flame surface rendering path used by the harness renderer, and only falls back to the software canvas rasterizer when that host path is unavailable.
- `LoveGraphicsSurface` and `LoveCanvas` now reuse immutable snapshot objects until the recorded surface revision changes, and the Flame renderer reuses cached `ui.Picture` recordings for repeated `LoveCanvasSnapshot` draws.
- `LoveMesh` now reuses revision-backed draw snapshot vertices and effective draw vertices, avoiding repeated per-vertex copies when stable meshes are drawn every frame.
- Eligibility is still intentionally narrow:
  - only decoded `ui.Image` atlases
  - one shared atlas and filter mode across the batch
  - no registered fragment shader path
  - no radial-gradient image overlay path
  - no attached custom sprite-batch attributes
  - only transforms representable as Flame/Flutter `RSTransform` values
- The compatibility fallback remains the existing per-entry `_renderResolvedImage(...)` loop.
- We now record `atlasBatchCommands` and `atlasBatchItems` in both per-frame render stats and rolling frame-timing summaries.
- Correctness coverage now includes:
  - render-stats tests for sprite-batch and particle-system batch counters
  - frame-timing aggregation tests for the new counters
  - visual render tests for atlas-batched sprite-batch and particle-system draws
  - host-specific tests that source-backed and mutable `Image` objects keep a fresh native image on `LoveFlameHost`
  - example benchmark smoke assertions that `LOVE Test Bed` actually exercises the atlas path
- The benchmark evidence now splits into two categories:
  - removing accidental CPU image rendering can produce order-of-magnitude wins, as shown by `Modern Pong`
  - even with those wins, with atlas batching active, with host-side canvas readback in place, and with repeated canvas snapshot draws compiled to cached pictures, `LOVE Test Bed` still spends roughly `30 ms` per sampled CPU frame, so the follow-on work should stay focused on the remaining replay-heavy paths rather than assuming Phase 4 solved the stutter problem by itself

### Guardrails

- Never batch across incompatible blend, shader, scissor, or texture state.
- Prefer a conservative fallback over a visually wrong optimization.
- Keep benchmarking separate from correctness tests, but require both before calling the phase complete.

### Tests to require

- current sprite-batch and particle tests
- new visual parity tests for batched versus fallback rendering
- benchmark scene runs recorded before and after the change

### Exit criteria

- eligible sprite-batch and particle paths can use Flame batching without visual regressions
- the fallback path remains intact for edge cases

## Phase 5: Real Gamepad Backend Integration

### Goal

Replace the keyboard-only virtual pad as the primary backend with actual controller/device support.

### Flame features to adopt

- `flame_gamepads`
- platform `gamepads` integration where needed

### Current pain points

- the current bridge mostly maps keyboard input into a synthesized controller
- the LOVE joystick adapter is generic enough to accept a better backend, but we are not using that leverage yet

### Likely files

- `lib/src/runtime/flame/love_flame_gamepad_bridge.dart`
- `lib/src/runtime/input/love_joystick_input_adapter.dart`
- `lib/src/runtime/flame/love_flame_harness.dart`
- any new backend adapter files under `lib/src/runtime/flame/`

### Concrete tasks

- Introduce a real gamepad backend that reports connect, disconnect, button, axis, and hat changes.
- Map platform controller concepts onto LOVE joystick/gamepad naming consistently.
- Keep the keyboard-synthesized virtual pad as a fallback or test helper.
- Route backend events through `LoveJoystickInputAdapter` so the rest of the runtime stays unchanged.
- Add deadzone handling and hotplug lifecycle rules.

### Guardrails

- Treat platform support as a matrix, not a yes/no capability. Desktop, web, Android, and iOS may differ.
- Do not let backend-specific ids leak into LOVE-facing stable ids unless that mapping is deliberate.
- Preserve deterministic testability by keeping a synthetic backend.

### Tests to require

- new adapter tests for connect/disconnect
- new axis deadzone tests
- new mapping tests for LOVE button and axis names
- smoke tests for keyboard-virtual fallback

### Exit criteria

- real controllers can drive the LOVE joystick and gamepad callbacks
- the virtual keyboard backend remains available for environments without controller APIs

## Phase 6: Post-Processing And Shader Boundary Cleanup

### Goal

Use Flame post-processing for whole-surface effects only, and document the boundary between those effects and LOVE's per-draw shader semantics.

### Flame features to adopt

- `CameraComponent.postProcess`
- `PostProcessComponent`

### Why this is later

This only becomes clean once the presented LOVE surface has a clear component boundary from Phase 3.

### Likely files

- component/presentation files introduced in Phase 3
- `lib/src/runtime/flame/love_flame_harness_renderer.dart`
- any new effect-stack file under `lib/src/runtime/flame/`

### Concrete tasks

- Introduce an optional post-process wrapper around the presented LOVE surface.
- Prefer `CameraComponent.postProcess` for whole-surface effects once the LOVE surface is mounted inside the camera-managed world.
- Use `PostProcessComponent` only when the effect should apply to a localized subtree instead of the whole presented output.
- Limit the first use cases to effects that are naturally whole-surface:
  - CRT filter
  - bloom
  - pause/menu blur
  - scanlines
  - color grading
- Document that LOVE per-draw shader behavior still belongs in the custom renderer path.
- Ensure overlays and video layers have explicit ordering rules relative to post-processing.

### Guardrails

- Do not misuse post-processing as a substitute for LOVE material/shader semantics.
- Keep the effect stack optional and easy to disable.
- Make ordering rules explicit before enabling multiple effect layers.

### Tests to require

- new ordering tests covering surface, overlays, and video composition
- new enable/disable tests for the effect stack
- performance smoke checks for representative screen effects

### Exit criteria

- whole-surface effects can be attached without touching every draw command path
- shader responsibilities are split clearly between LOVE draw-time shaders and Flame post-process effects

## Recommended Sequencing

1. Complete Phase 0 and write down the size/viewport invariants plus initial frame-time and hitch budgets.
2. Start the Performance Workstream immediately after baseline capture and keep it active through every later phase.
3. Land Phase 1 before any major overlay or input cleanup.
4. Land Phase 2 once camera ownership is stable.
5. Land Phase 3 before adding post-processing or broad caching.
6. Use the performance traces to decide whether Phase 4 batching or more direct hot-path cleanup should be the next highest-return step.
7. Land Phase 5 when platform coverage and test harness support are ready.
8. Land Phase 6 only after the presented surface is a first-class component.

## Cross-Cutting Engineering Rules

- Every phase should reduce one of:
  - duplicated geometry logic
  - duplicated widget ownership
  - duplicated device/input plumbing
  - duplicated batching infrastructure
- Every phase should have a visible performance hypothesis:
  - which hitch or hot path it should improve
  - how that improvement will be measured
- Every phase should add or strengthen tests before deleting the old path.
- Every optimization phase must preserve a conservative fallback.
- Every new Flame feature should have a named owner in the architecture:
  - camera owns presentation geometry
  - `GameWidget` owns focus/overlay plumbing
  - surface component owns LOVE presentation
  - batching adapter owns hot-path lowering
  - joystick adapter owns controller translation
  - post-process wrapper owns whole-surface effects

## Tracking Checklist

- [ ] Phase 0: size and presentation invariants documented
- [x] Phase 0: resize, pointer, and overlay geometry tests pinned
- [ ] Phase 0: sprite and particle benchmark scenes added
- [ ] Performance budgets defined for representative scenes and target classes
- [ ] Cold-cache and warm-cache traces captured before major refactors
- [x] Phase 1: fixed-resolution camera owns presentation geometry
- [x] Phase 1: pointer conversion moved to camera conversions
- [x] Phase 1: overlay placement uses the same presentation source of truth
- [x] Phase 2: `GameWidget` owns focus and overlay registration
- [x] Phase 2: text input and cursor sync made event-driven where possible
- [ ] Phase 3: LOVE surface extracted into a dedicated Flame component
- [ ] Phase 3: any snapshot caching has explicit invalidation tests
- [x] Startup harness prewarms bundle-backed source images into the Flame cache
- [x] Startup readiness waits for `game.images.ready()` and first-frame shader warmup
- [ ] Scene-level image preload uses `game.images.loadAll(...)` where practical
- [ ] Scene readiness waits for `game.images.ready()` and shader warmup where needed
- [ ] `saveLayer` audit completed with parity coverage
- [ ] Harness-level frame polling removed or explicitly justified
- [x] Phase 4: sprite-batch lowering path added with fallback
- [x] Phase 4: particle-system lowering path added with fallback
- [x] Phase 4: batching telemetry/benchmarking in place
- [ ] Phase 5: real gamepad backend integrated
- [ ] Phase 5: keyboard virtual pad kept as fallback/test backend
- [ ] Phase 6: whole-surface post-process wrapper integrated
- [ ] Phase 6: ordering rules for overlays and video documented and tested
- [ ] Frame-time variance improved on representative benchmark scenes

## Suggested References

- Flame camera docs: `https://docs.flame-engine.org/latest/flame/camera.html`
- Flame `GameWidget` API: `https://pub.dev/documentation/flame/latest/game/GameWidget-class.html`
- Flame input docs: `https://docs.flame-engine.org/latest/flame/inputs/inputs.html`
- Flame image/rendering docs: `https://docs.flame-engine.org/latest/flame/rendering/images.html`
- Flame post-processing docs: `https://docs.flame-engine.org/latest/flame/rendering/post_processing.html`
- `flame_gamepads`: `https://pub.dev/packages/flame_gamepads`
- `gamepads`: `https://pub.dev/packages/gamepads`

## Bottom Line

The most important shift is architectural, not cosmetic: let Flame own camera/presentation geometry first, then let `GameWidget` own more widget concerns, then make the LOVE surface a real Flame component. That gives us the right structure for performance work as well: preload assets before interaction, reduce frame-polled work, batch safe draw paths, and treat first-use hitches and steady-state stutter as tracked outcomes instead of hoping they fall out of cleanup.
