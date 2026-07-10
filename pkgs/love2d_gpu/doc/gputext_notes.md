# gputext notes

Cloned reference: `pkgs/love2d_gpu/third_party/gputext`

## flutter_gpu patterns worth borrowing

- **Load paths are resilient**: gputext tries multiple shader-bundle asset keys before failing.
- **Explicit support gating**: widgets/engines detect `gpu.gpuContext` and degrade cleanly when flutter_gpu/Impeller is unavailable.
- **Pipeline + texture caches are generation-aware**: atlas uploads only rebuild when the underlying data generation changes.
- **Avoid resizing live surfaces**: create a fresh offscreen surface and retire the old image until the compositor is done with it.
- **Avoid shared host-buffer reuse for nested renders**: gputext prefers immutable per-render uniform buffers when a child render can happen during the parent paint.
- **Keep render code split from widget code**: a thin public API, a stateful engine, and a lower-level renderer make the lifecycle easier to reason about.

## Shader architecture notes

- Their GPU text path is built around **one frame uniform block + one instance layout + two data textures**.
- Vertex shader computes clip-space and passes all glyph-local state through.
- Fragment shader does the expensive work: analytic coverage, minification guard, and styling.
- This is a good pattern for any future LOVE2D text or vector-shape shader: keep the draw path data-driven, and move complexity into a compact shader contract.

## Likely next improvements for `love2d_gpu`

- Keep shader bundle loading resilient (multiple asset keys), like gputext.
- Add an explicit GPU-ready / unsupported state instead of assuming availability.
- Keep the offscreen surface lifecycle retire-safe across resize and retained layers.
- Review HostBuffer reuse in nested render paths.
- Add cache generation invalidation for textures/pipelines if asset data can change.
- For any future text/vector work, prefer a gputext-style contract: a small uniform block, per-instance data, and lookup textures instead of large ad-hoc uniform payloads.
