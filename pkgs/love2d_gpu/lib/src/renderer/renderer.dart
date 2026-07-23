/// GPU rendering pipeline for LOVE2D draw commands.
///
/// This library provides the concrete implementation of [LoveGpuRenderBackend],
/// translating [LoveDrawCommand] instances into flutter_gpu API calls.
///
/// ## Architecture
///
/// ```
/// ┌────────────────────────────────────────────────────────────┐
/// │  LoveGpuRenderBackend           (public entry point)       │
/// ├────────────────────────────────────────────────────────────┤
/// │  GpuCommandRenderer             (core render engine)       │
/// │  ├── GpuSurfaceManager          (offscreen texture pool)   │
/// │  ├── GpuPipelineCache           (render pipeline cache)   │
/// │  ├── GpuTextureCache            (image → gpu.Texture)     │
/// │  ├── GpuHostBufferPool          (per-frame bump allocator)│
/// │  ├── GpuMeshHandler             (LoveMeshCommand)         │
/// │  ├── GpuImageHandler            (LoveImageCommand)        │
/// │  ├── GpuSpriteBatchHandler      (LoveSpriteBatchCommand)  │
/// │  └── GpuFallbackHandler         (Canvas fallback overlay) │
/// └────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Render flow (per frame)
///
/// 1. **Pre-warm** — [GpuTextureCache.preWarmCommands] uploads all textures
///    referenced by the frame's commands to GPU memory (async).
/// 2. **Acquire** — [GpuSurfaceManager.acquire] returns a [Frame] with color
///    and depth-stencil textures sized to the viewport.
/// 3. **Command buffer** — [gpu.Context.createCommandBuffer] starts a new
///    GPU command recording.
/// 4. **Render pass** — A [gpu.RenderPass] is created with the snapshot's
///    clear color as `LoadAction.clear`.
/// 5. **Dispatch** — Each [LoveDrawCommand] is dispatched via a sealed-class
///    switch to the appropriate handler (mesh, image, sprite batch). Shape
///    commands and text fall back to Canvas.
/// 6. **Submit** — [gpu.CommandBuffer.submit] executes the GPU work.
/// 7. **Present** — [gpu.Texture.asImage] converts the color attachment to a
///    [ui.Image], drawn onto the Flutter canvas.
/// 8. **Fallback** — [GpuFallbackHandler.renderFallback] overlays any
///    unsupported commands via the Canvas path.
///
/// ## Resource lifecycle
///
/// | Resource | Lifetime | Owner |
/// |---|---|---|
/// | gpu.Texture (color) | Pooled, resized on viewport change | GpuSurfaceManager |
/// | gpu.Texture (depth) | Pooled, resized on viewport change | GpuSurfaceManager |
/// | gpu.CommandBuffer | Per-frame, submitted then collected | GpuCommandRenderer |
/// | gpu.RenderPipeline | Cached, cleared on dispose | GpuPipelineCache |
/// | gpu.Texture (image) | Cached, cleared on reset | GpuTextureCache |
/// | gpu.HostBuffer | Frame-cyclic (4 frames) | GpuHostBufferPool |
library;

export 'gpu_command_renderer.dart';
export 'gpu_fallback_handler.dart';
export 'gpu_host_buffer_pool.dart';
export 'gpu_image_handler.dart';
export 'gpu_mesh_handler.dart';
export 'gpu_pipeline_cache.dart';
export 'gpu_shape_handler.dart';
export 'gpu_sprite_batch_handler.dart';
export 'gpu_surface_manager.dart';
export 'gpu_texture_cache.dart';
