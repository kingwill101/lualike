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

## Review Summary

| Priority | Current issue | Existing local implementation | Flame feature to adopt | Expected benefit |
| --- | --- | --- | --- | --- |
| High | Viewport and logical-coordinate math are duplicated | `love_flame_harness_renderer.dart`, `love_flame_harness.dart`, `love_flame_input.dart`, `love_flame_live_video_overlay.dart`, `love_flame_viewport_geometry.dart` | `CameraComponent.withFixedResolution`, `FixedResolutionViewport`, camera `globalToLocal` / `localToGlobal` | One source of truth for presentation geometry |
| Medium | Harness reimplements widget responsibilities | Outer `Focus`, `MouseRegion`, `Listener`, per-frame sync in `love_flame_harness.dart` | `GameWidget` focus, cursor, overlays, and keyboard integration | Less widget glue and fewer event-order bugs |
| Medium | LOVE surface is not modeled as a Flame component | `LoveFlameHarnessGame` plus large custom render switch | `CustomPainterComponent`, world/camera layering, `Snapshot` where useful | Simpler composition, easier HUD/effect attachment |
| Medium | Sprite batches and particles render via per-entry loops | `_renderSpriteBatchCommand`, `_renderParticleSystemCommand` | `SpriteBatch`, `HasAutoBatchedChildren` where safe | Better performance in common texture-atlas paths |
| Medium | Controller support is mostly synthesized from keyboard input | `love_flame_gamepad_bridge.dart` | `flame_gamepads`, `gamepads` | Real controller parity and less custom device plumbing |
| High | Frame pacing and warmup are not first-class plan items yet | On-demand `game.images.load(...)` in `love_flame_host.dart`, partial shader prewarm in `love_registered_fragment_shader_cache.dart`, per-frame `_textInputTicker`, repeated `TextPainter` / `saveLayer` hotspots | `Images.loadAll`, `images.ready()`, targeted `Snapshot`, plus the existing shader warmup queue | Fewer first-use pauses and lower frame-time variance |
| Low | Whole-surface effects are harder than they need to be | Custom rendering only | `PostProcessComponent` | Cleaner support for CRT/bloom/scanline-style screen effects |

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

- image loads can still happen on demand through `game.images.load(...)` in `love_flame_host.dart`
- shader warmup support already exists, but scene startup does not yet treat it as a formal readiness barrier
- `_textInputTicker` still performs frame-polled synchronization
- `TextPainter` is created in hot paths in `love_flame_harness_renderer.dart` and `love_flame_host.dart`
- the renderer has multiple `saveLayer` paths that should be justified individually
- sprite-batch and particle rendering still rely on per-entry loops in the common path

### Flame features and local hooks to adopt

- `Images.loadAll`
- `Images.ready()`
- targeted `Snapshot` caching where invalidation is simple
- `SpriteBatch`
- existing registered shader prewarm queue in `love_registered_fragment_shader_cache.dart`

### Likely files

- `lib/src/runtime/flame/love_flame_host.dart`
- `lib/src/runtime/flame/love_registered_fragment_shader_cache.dart`
- `lib/src/runtime/flame/love_flame_harness.dart`
- `lib/src/runtime/flame/love_flame_harness_renderer.dart`
- any benchmark or profiling harness files added under `example/`, `tool/`, or `test/`

### Concrete tasks

- Add lightweight frame-timing instrumentation and keep before/after traces for representative scenes.
- Capture both cold-cache and warm-cache runs for:
  - startup
  - first scene entry
  - dense sprite scenes
  - dense particle scenes
  - text-heavy scenes
- Introduce scene-level preload manifests where the upcoming content is predictable.
- Warm image sets through Flame's image cache using `game.images.loadAll(...)`, and wait on `game.images.ready()` before interactive frames where the preload set is known.
- Extend the existing registered-shader warmup path so scene startup can request or await fragment assets that will be needed immediately.
- Replace remaining frame-polled synchronization with event-driven paths where platform behavior allows it.
- Audit repeated `TextPainter` creation and introduce scoped caching only when the layout inputs are stable and invalidation is obvious.
- Audit every `saveLayer` site and narrow or remove layers that are not required for correctness.
- Track allocation churn in sprite, particle, mesh, and text-heavy scenes and cache or pool short-lived objects only when ownership and invalidation are clear.

### Guardrails

- Do not preload every asset globally; preload by scene, feature, or known hotspot so memory growth stays bounded.
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
- Define a strict eligibility check for batching:
  - shared texture/atlas
  - compatible blend mode
  - no unsupported shader state
  - no per-entry state that breaks batching
- Add a similar opportunistic path for particle-system draws when the same restrictions hold.
- Keep the existing per-entry path as the compatibility fallback.
- Add instrumentation counters so we can see how often content uses the fast path versus fallback, and compare frame-time variance before and after batching.

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

- `PostProcessComponent`

### Why this is later

This only becomes clean once the presented LOVE surface has a clear component boundary from Phase 3.

### Likely files

- component/presentation files introduced in Phase 3
- `lib/src/runtime/flame/love_flame_harness_renderer.dart`
- any new effect-stack file under `lib/src/runtime/flame/`

### Concrete tasks

- Introduce an optional post-process wrapper around the presented LOVE surface.
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
- [ ] Phase 0: resize, pointer, and overlay geometry tests pinned
- [ ] Phase 0: sprite and particle benchmark scenes added
- [ ] Performance budgets defined for representative scenes and target classes
- [ ] Cold-cache and warm-cache traces captured before major refactors
- [ ] Phase 1: fixed-resolution camera owns presentation geometry
- [ ] Phase 1: pointer conversion moved to camera conversions
- [ ] Phase 1: overlay placement uses the same presentation source of truth
- [ ] Phase 2: `GameWidget` owns focus and overlay registration
- [ ] Phase 2: text input and cursor sync made event-driven where possible
- [ ] Phase 3: LOVE surface extracted into a dedicated Flame component
- [ ] Phase 3: any snapshot caching has explicit invalidation tests
- [ ] Scene-level image preload uses `game.images.loadAll(...)` where practical
- [ ] Scene readiness waits for `game.images.ready()` and shader warmup where needed
- [ ] `saveLayer` audit completed with parity coverage
- [ ] Harness-level frame polling removed or explicitly justified
- [ ] Phase 4: sprite-batch lowering path added with fallback
- [ ] Phase 4: particle-system lowering path added with fallback
- [ ] Phase 4: batching telemetry/benchmarking in place
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
