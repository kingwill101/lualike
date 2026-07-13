Love2D graphics/render path — performance smell review

Architecture summary

Recording model
Lua does not draw immediately. Bindings append deferred LoveDrawCommands onto a LoveGraphicsSurface (screen or active canvas). Each command embeds a full graphics-state snapshot (color, blend, scissor, shader, wireframe, line style, copied Matrix4 transform, etc.). Flame later replays the frozen list onto a Flutter Canvas.

love.graphics.setColor

Lua call
  → _bindGraphicsSetColor
  → _requireColor (unwrap Value; scalar or color table)
  → LoveGraphicsFrame.color = value.clamped()  // new LoveColor every set
No command is queued; only mutable LoveGraphicsState is updated.

love.graphics.draw (typical image/quad path)

Lua call
  → _bindGraphicsDraw
  → sequential drawable probes (Text → Mesh → SpriteBatch → Particle → Video)
  → _requireImage / optional canvas.snapshot()
  → new LoveImageCommand(
        color/line/blend/scissor from runtime.graphics,
        shader: runtime.graphics.shader,     // already a snapshot
        transform: copyTransform(),          // Matrix4.copy
        drawTransform: standard/transform,   // another Matrix4
      )
  → LoveDrawCommand ctor: shader?.snapshot() again + Matrix4.copy(transform)
  → LoveImageCommand: Matrix4.copy(drawTransform), quad?.copy()
  → LoveGraphicsFrame.addCommand (stencil mask rewrite)
  → LoveGraphicsSurface.addCommand

love.graphics.print

Lua call
  → parse colored text spans
  → resolve font (explicit or ensureCurrentGraphicsFontOrFuture)
  → LoveTextCommand(
        full state snapshot,
        copyTransform(),
        textTransform Matrix4,
        font._snapshotForDrawCommand(),
        unmodifiable spans,
      )
  → double matrix/shader copy in LoveDrawCommand ctor (same as draw)

Frame present / replay

LoveFlameHarness._commitPresentedFrame
  → graphics.snapshotScreenSurface()   // List.from + unmodifiable list
  → game.presentFrame(snapshot)
LoveFlameHarnessGame.render
  → always new LoveRenderStatsAccumulator
  → LoveCanvasRenderBackend.renderSurface  // pure pass-through
  → renderSurfaceSnapshot                 // stats adapter only
  → _renderSurfaceSnapshot
       → scan for software fallbacks
       → clear
       → per command: _renderRecordedCommand
            save → clip → optional saveLayer(s) → transform → draw → restore stack

Key files:
• Bindings: /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/love_api_bindings/graphics_draw_bindings.dart, graphics_state_bindings.dart, binding_helpers.dart
• State/commands: /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/love_runtime.dart
• Replay: /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/flame/love_flame_harness_renderer.dart
• Backend wrapper: /run/media/kingwill101/disk2/code/code/dart_packages/lualike/pkgs/love2d/lib/src/runtime/renderer/love_canvas_render_backend.dart

───

Concrete smells

1. Double (often triple) matrix copies on every draw — HIGH
Bindings call runtime.graphics.copyTransform() then LoveDrawCommand always does Matrix4.copy(transform) again.

    required Matrix4 transform,
    ...
  }) : shader = shader?.snapshot(),
       transform = Matrix4.copy(transform),

        transform: runtime.graphics.copyTransform(),

Same pattern for drawTransform / textTransform: _matrixFromTransformArgumentOrStandardTransform may already Matrix4.copy(transform.matrix), then subclass ctors copy again (LoveImageCommand 2689–2690, LoveTextCommand 2637, etc.).

Impact: ~2–4 Matrix4 (16-float) allocations per draw/print on the record path alone.

───

2. Double shader snapshot/clone when a shader is bound — HIGH
LoveGraphicsFrame.shader already snapshots:

  LoveShader? get shader => _state.shader?.snapshot();

Bindings pass shader: runtime.graphics.shader, then LoveDrawCommand snapshots again (shader?.snapshot() at 2559).

LoveShader.snapshot() rebuilds a LoveShader and deep-clones every uniform via _cloneLoveShaderUniform (maps/lists recursively) in love_shader_support.dart 218–226, 150–154, 283–292.

Impact: With an active shader, every draw clones uniform maps twice. Dominant cost if samplers/matrices are sent often.

───

3. Full graphics state embedded on every command (boilerplate + over-copy) — HIGH
Every draw primitive constructor manually repeats ~10 state fields (color, lineWidth/style/join, blend modes, colorMask, wireframe, scissor, shader, transform). Example: rectangle at graphics_draw_bindings.dart 68–88; image at 497–518.

This is a mechanical deferred-port pattern: correctness for later mutation, but no shared “state stamp” and no dirty/versioned state sharing. Even when state is unchanged across 1000 draws, each command re-copies transform/shader/scissor references.

Impact: GC pressure proportional to draw count × state size; hurts dense tile/UI loops most.

───

4. Drawable type discrimination chain on every draw — MED–HIGH
love.graphics.draw probes Text, Mesh, SpriteBatch, ParticleSystem, Video before Image (graphics_draw_bindings.dart 325–484). Each probe unwraps Value and map-key lookups (_rawValue + table key). The common image path pays for all failed probes first.

Impact: Fixed overhead per draw; worse when most draws are images (typical games).

───

5. Particle / sprite-batch / mesh deep copies on record — HIGH (when used)
┌─────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Path        │ Extra work                                                                                                                                           │
├─────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Particle    │ snapshotForDraw() builds entries (Matrix4.copy in LoveParticleDrawEntry ctor) then LoveParticleSystemSnapshot maps particle.copy() again (extra      │
│             │ matrix/quad copy), then command ctor calls particleSystem.copy() → third pass (love_particle_system_support.dart 43–44, 71–73, 82–84;                │
│             │ LoveParticleSystemCommand 2759–2760)                                                                                                                 │
├─────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ SpriteBatch │ copyForDraw() maps every sprite through sprite.copy() → another Matrix4.copy per sprite (love_sprite_batch_support.dart 65, 16–17, 248–264)          │
├─────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Mesh        │ copyForDraw() snapshots vertices (vertex.copy() each) (love_mesh_support.dart 338–365)                                                               │
├─────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Text object │ textObject.copy() on draw (LoveTextObjectCommand 2666)                                                                                               │
├─────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ Font text   │ font._snapshotForDrawCommand() clones fallback list every print (love_runtime.dart 2031–2057, 1667)                                                  │
└─────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

Impact: Batch/particle draws can allocate O(n) matrices/entries before Flame atlas batching even starts.

───

6. Surface snapshot double-list allocation every frame — MED

    final snapshot = LoveGraphicsSurfaceSnapshot(
      ...
      commands: List<LoveDrawCommand>.unmodifiable(
        List<LoveDrawCommand>.from(_commands),
      ),
    );
Revision cache helps only if snapshot is taken twice without new commands. Frame end always creates a new unmodifiable list copy.

───

7. Per-command Flutter overhead: save/restore + always-new Paint — HIGH (replay)
_renderRecordedCommand (love_flame_harness_renderer.dart 739–940):
• Outer canvas.save / optional clip / up to 3 saveLayers / inner save / transform / restores
• New Paint() for essentially every shape and many images
• Line/polygon: new Path every time; points.skip(1) allocates an iterator view each command
• Points: new Paint per point (844–847)

Impact: Replay cost scales poorly with command count even when content is simple.

───

8. Always-on render stats allocation/conversion — MED
LoveFlameHarnessGame.render always allocates LoveRenderStatsAccumulator, converts via renderSurfaceSnapshot into _LoveFlameRenderStatsAccumulator, then copies fields into LoveRenderStats / LoveFlameRenderStats (606–672, 3111–3142).

Three nearly identical stats types exist (LoveRenderStats, LoveFlameRenderStats, internal accumulator).

───

9. Pass-through abstraction layers with little work — LOW–MED (indirection tax)
• LoveCanvasRenderBackend.renderSurface → renderSurfaceSnapshot → _renderSurfaceSnapshot (only stats remapping in the middle)
• LoveGpuRenderBackend is a stub (isAvailable => false, empty body) but still part of the abstraction surface
• Many LoveGraphicsFrame getters/setters are 1-line forwards to _state (3132–3276) — fine for API, but command construction reads them field-by-field instead of one state stamp

───

10. Color clamping allocates on every set (and again on render) — MED

  set color(LoveColor value) {
    _state.color = value.clamped();
  }
_toFlutterColor clamps again (2961–2968). modulate always ends with .clamped() (2520–2526).

Impact: setColor every sprite + modulate in batch/particles → many short-lived LoveColors; not free under AOT GC.

───

11. Transform stack: full-state copy on every push — MED
LoveGraphicsStackFrame always state.copy() including full transform and all fields (3085–3090, 3441–3447), even for push('transform') where only matrix is restored on pop.

shear allocates a temporary Matrix4.identity() every call (3478–3482).

inverseTransformPoint copies + inverts every call (3513–3521).

───

12. Software fallback planning rescans command list — MED (conditional)
_softwareFallbackPlan walks all commands; then render walks again (2650–2682, 2637–2643). Special blends / color masks / stencils force full software rasterize of the surface (LoveCanvasRasterizer) — catastrophic vs Canvas path if triggered often.

───

13. Canvas snapshot on every canvas draw — MED (correctness-driven)
canvas.snapshot() on draw (graphics_draw_bindings.dart 487–489) freezes command lists for later replay. Slice cache by revision helps, but drawing the same canvas many times still materializes LoveCanvasSnapshot objects and nested surface snapshots when revision bumps.

Nested canvas-as-texture then builds/caches ui.Picture (_pictureForCanvasSnapshot) — good, but first-use hitchy.

───

14. Per-pixel image path still present — HIGH when hit
preferImageDataRendering / missing ui.Image walks every pixel with individual drawRect (1507–1517 in harness renderer). Not the common path if native images exist, but a severe trap for uncached ImageData.

───

15. Enum string parse on state setters — LOW (not hot unless called every frame)
setBlendMode / setLineStyle / etc. parse strings every call (binding_helpers.dart 154–196). Acceptable if rare; wasteful if Lua toggles blend every draw.

No int/const opcode fast path from Lua.

───

16. Value unwrap ceremony on hot helpers — MED
_requireNumber / _rawValue / _valueAt on every numeric arg (binding_helpers.dart 409–455). _standardTransform issues up to 9 optional number parses even for draw(img, x, y) defaults (1186–1235), still constructing a full Matrix4 with cos/sin of 0.

Identity transforms are not short-circuited.

───

17. Duplicate stats / backend plumbing as mechanical-port residue — LOW
LoveFlameRenderStats vs LoveRenderStats near-duplicates; conversion every frame. GPU backend skeleton without implementation adds API surface without benefit today.

───

18. LoveDrawCommand copies unused-for-draw fields into every command — MED
Shape commands store lineWidth/lineJoin even for filled rects; text stores line style; image stores line fields. Replay largely ignores many of them per command type. Pays construction cost for parity/stencil plumbing.

───

Severity rollup (performance impact)

┌──────────┬─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Severity │ Themes                                                                                                                                                  │
├──────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ HIGH     │ Double matrix + double shader snapshot; full state per command; particle/batch/mesh deep copy chains; per-command Paint/saveLayer; software/full-       │
│          │ surface fallback; per-pixel ImageData path                                                                                                              │
├──────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ MED      │ Drawable probe chain; surface snapshot list copy; always-on stats; color clamp allocs; push full-state copy; transform default Matrix4; Value unwrap +  │
│          │ 9-arg standard transform; canvas snapshot frequency                                                                                                     │
├──────────┼─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
│ LOW      │ Pass-through backend wrappers; enum string parse on rare setters; getter forwarding; GPU stub                                                           │
└──────────┴─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

───

Suggested consolidation / refactor directions (no code)

A. State versioning instead of full stamp per command
Keep a mutable LoveGraphicsState with a monotonically increasing revision. Commands store stateRevision + deltas that matter for that op (or a shared immutable state node when revision changes).
Alternatively: record state-change commands (SetColor, SetBlend, SetTransform) and only geometry ops after, closer to a real GL/command-buffer model.

B. Single ownership of matrix/shader freezing
• Pass storage/Float64List or take ownership of one Matrix4 into the command (no double copy).
• Use currentShader (live ref) at bind time and snapshot once in addCommand only if shader revision changed; or store shader id + uniform generation counter.
• Short-circuit identity/local draw(x,y) to translation-only fields instead of always building a full affine Matrix4.

C. Specialized fast command types
LoveImageDrawFast { image, quad?, x, y, color, ... } without line/blend clutter when defaults apply. Keep full commands for uncommon state.

D. Drawable dispatch table
On userdata creation, stash a small type tag / draw closure on the Lua wrapper (or a single _loveDrawableKey pointing to a sealed drawable handle). One map lookup instead of 5 probes.

E. Copy-on-write / freeze-once for batches/particles/meshes
• Particle: build draw entries once into an unmodifiable list; do not copy() again in snapshot ctor and command ctor.
• SpriteBatch: share immutable sprite array if batch not mutated after draw (or revision-based freeze).
• Mesh: already caches vertex snapshot by revision — keep that pattern; avoid extra layers.

F. Replay: paint/state pooling + batch consecutive state
• Reuse Paint objects when color/style unchanged.
• Coalesce consecutive commands with same transform/scissor/blend to avoid save/restore storms.
• Optional: multiply world×local once at record time for images so replay does one transform.
• Gate stats behind a debug flag / sampling so production frames skip accumulators and dual stats types.

G. Snapshot cheaper end-of-frame
• snapshot() can expose List.unmodifiable(_commands) only if the surface is then treated as frozen, or transfer ownership of the list and start a new buffer (beginFrame already clears).
• Avoid List.from + unmodifiable double wrap.

H. Color as value type without re-clamp
Clamp at Lua boundary once; store already-clamped components; _toFlutterColor skip clamp if a flag/LoveColor invariant holds. Consider packing to ARGB int for replay.

I. Collapse pass-through layers carefully
• Let Flame call _renderSurfaceSnapshot (or one public entry) with a single stats type.
• Keep LoveRenderBackend only if GPU path becomes real; until then the Canvas backend is pure indirection.

J. Transform stack
For push('transform'), store only Matrix4.copy(transform) (or a small stack of matrices), not full LoveGraphicsState.copy().

───

What already looks good
• Canvas slice snapshot revision cache (LoveCanvas._snapshotForSlice)
• Mesh vertex snapshot revision cache
• Surface snapshot revision cache (when reused)
• TextPainter LRU cache (256)
• Flame SpriteBatch atlas path for particles/sprite batches when native ui.Image is available
• Full software raster only when blend/stencil/mask require it

───

Highest-ROI first targets (order)
1. Eliminate double matrix + double shader snapshot on the record path.
2. Stop triple-copying particle/sprite-batch draw data.
3. Reduce per-command embedded state (versioned stamp or state commands).
4. Cut replay Paint/saveLayer churn for default alpha/srcOver draws.
5. Single-tag drawable dispatch for love.graphics.draw.
6. Make frame stats optional; cheapen surface snapshot list ownership.
