# Love2D GPU Renderer Overview

## Architecture

The GPU renderer connects LOVE2D draw commands to [package:flutter_gpu],
Flutter's low-level GPU API (Impeller backend). The key insight is that
flutter_gpu has **no swapchain** — all rendering is offscreen. The rendered
result is extracted as a [ui.Image] via `Texture.asImage()` and then drawn
onto the Flutter Canvas with `Canvas.drawImageRect()`.

```
┌──────────────────────────────────────────────────────────────────┐
│                       Frame Render Loop                           │
│                                                                   │
│  LoveGraphicsSurfaceSnapshot                                      │
│    ├─ clearColor (LoveColor)                                      │
│    └─ commands (List<LoveDrawCommand>)                            │
│         ├─ LoveRectangleCommand                                   │
│         ├─ LoveImageCommand                                       │
│         ├─ LoveMeshCommand                                        │
│         └─ ...                                                    │
│         │                                                         │
│         ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │  GpuCommandRenderer.renderFrame()                        │     │
│  │                                                          │     │
│  │  1. GpuSurfaceManager.acquire(w, h) → Frame              │     │
│  │     (reuses pooled color + depth-stencil textures)       │     │
│  │                                                          │     │
│  │  2. GpuContext.createCommandBuffer()                     │     │
│  │                                                          │     │
│  │  3. RenderTarget.singleColor(                            │     │
│  │       ColorAttachment(clearValue: clearColor))           │     │
│  │                                                          │     │
│  │  4. commandBuffer.createRenderPass(renderTarget)         │     │
│  │                                                          │     │
│  │  5. For each command:                                    │     │
│  │     switch (command) {                                   │     │
│  │       // GPU-supported → render pass draw call           │     │
│  │       // Unsupported    → skip (fallback)                │     │
│  │     }                                                    │     │
│  │                                                          │     │
│  │  6. Frame.present(cmdBuf, canvas, viewport)              │     │
│  │     ├─ commandBuffer.submit()                            │     │
│  │     ├─ colorTexture.asImage() → ui.Image                │     │
│  │     └─ canvas.drawImageRect(image, src, dst, Paint())   │     │
│  └─────────────────────────────────────────────────────────┘     │
└──────────────────────────────────────────────────────────────────┘
```

## Key files

| File | Purpose |
|---|---|
| `lib/src/love2d_gpu_render_backend.dart` | Public entry point, implements LoveRenderBackend |
| `lib/src/renderer/gpu_surface_manager.dart` | Pools offscreen color + depth textures |
| `lib/src/renderer/gpu_command_renderer.dart` | Core render loop, command dispatch |
| `lib/src/renderer/renderer.dart` | Barrel export + architecture docs |

## Resource Lifecycle

| Resource | Lifetime | Owner |
|---|---|---|
| `gpu.Texture` (color) | Pooled, resized on viewport change | `GpuSurfaceManager` |
| `gpu.Texture` (depth-stencil) | Pooled, resized on viewport change | `GpuSurfaceManager` |
| `gpu.CommandBuffer` | Per-frame, submitted then collected | `GpuCommandRenderer` |
| `gpu.RenderPipeline` | Cached per shader variant | `GpuPipelineCache` (future) |
| `gpu.Texture` (image) | Uploaded from `ui.Image`, cached | `GpuTextureCache` (future) |
| `gpu.HostBuffer` | Frame-cyclic bump allocator | `GpuCommandRenderer` (future) |

## Harness integration

The demo and tests should keep using `LoveFlameHarness`; the harness now
accepts an optional `renderBackend` override so GPU and canvas paths can be
swapped without changing the app shell.

## Hybrid Fallback Model

Not all LOVE draw commands can (or should) go through the GPU path.
Commands that require software rendering (radial gradient shaders, complex
stencil operations, narrow-phase features) are skipped by the GPU path and
re-rendered via the Canvas fallback.

The `LoveGpuRenderBackend.hybridFallback` toggle controls this:

- `true` (default) — unsupported commands are invisible (skipped). The
  `_applyFallbackCommands` method will eventually re-render them on top.
- `false` — unsupported commands produce visual gaps, making it obvious
  what is missing during development.

## Mapping LOVE concepts to flutter_gpu

| LOVE Concept | flutter_gpu Equivalent |
|---|---|
| Clear color | `ColorAttachment.clearValue` |
| Draw mode (triangles/fan/strip) | `RenderPass.setPrimitiveType()` |
| Vertex attributes | `VertexLayout` + `VertexBuffer` |
| Textures | `gpu.Texture` created via `GpuContext.createTexture()` → uploaded via `overwrite()` |
| Shader (GLSL) | Compiled `.shaderbundle` asset → `ShaderLibrary.fromAsset()` |
| Uniforms | `Shader.getUniformSlot()` + `RenderPass.bindUniform()` |
| Blend mode | `RenderPass.setColorBlendEnable()` + `setColorBlendEquation()` |
| Scissor rect | `RenderPass.setScissor()` |
| Viewport | `RenderPass.setViewport()` |

## Requirements

- Flutter **master** channel
- Impeller enabled (`--enable-impeller`)
- Native assets enabled (`flutter config --enable-native-assets`)

## References

- [flutter_gpu API docs](https://api.flutter.dev/flutter/gpu/gpu-library.html)
- [flutter_scene](https://github.com/bdero/flutter_scene) — reference implementation using the same Texture + CommandBuffer + HostBuffer pattern
- [impellerc](https://docs.flutter.dev/platform-integration/gpu#shaders) — shader compilation tool for .shaderbundle assets
