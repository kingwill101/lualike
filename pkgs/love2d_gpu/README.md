# love2d_gpu

[![GitHub release](https://img.shields.io/github/release/kingwill101/lualike?include_prereleases=&sort=semver&color=blue)](https://github.com/kingwill101/lualike/releases/)
[![issues - lualike](https://img.shields.io/github/issues/kingwill101/lualike)](https://github.com/kingwill101/lualike/issues)
[![License](https://img.shields.io/badge/License-MIT-blue)](https://github.com/kingwill101/lualike/blob/master/LICENSE)


Experimental Flutter GPU rendering backend for [package:love2d](https://github.com/kingwill101/lualike/tree/main/pkgs/love2d).

Renders LOVE2D draw commands through [package:flutter_gpu] instead of the standard Flutter Canvas 2D pipeline.

## Requirements

- Flutter **master** channel
- Impeller enabled (`--enable-impeller`)
- Native assets enabled (`flutter config --enable-native-assets`)

## Quick Start

```dart
import 'package:love2d/love2d.dart';
import 'package:love2d_gpu/love2d_gpu.dart';

void main() {
  final backend = LoveGpuRenderBackend.create();

  // Use with LoveFlameHarnessGame:
  final game = LoveFlameHarness(
    entryAsset: 'assets/main.lua',
    renderBackend: backend ?? LoveCanvasRenderBackend(),
    // ...
  );
}
```

## Architecture

See [doc/gpu_renderer_overview.md](doc/gpu_renderer_overview.md) for the full architecture and render pipeline documentation.

## Shader build

The shader bundle is built by the package hook in `hook/build.dart`.
To regenerate it manually:

```sh
cd pkgs/love2d_gpu
flutter pub get
./tools/build_shaders.sh
```

The bundle is loaded from either the legacy build path or the Flutter data asset
path, so the package works in both local checkout and dependency mode.

## Current Status

**Step 1 — Clear pass** ✅
- [x] Render backend abstraction
- [x] Offscreen texture pool (GpuSurfaceManager)
- [x] Command renderer with clear pass
- [x] Hybrid fallback toggle

**Step 2 — Mesh command** 🔜
- [ ] Vertex/index buffer upload
- [ ] Mesh pipeline with vertex format matching
- [ ] Draw modes (triangles, strip, fan)

**Step 3 — Image/Textured quad** 🔜
- [ ] Texture upload from ui.Image
- [ ] Image command with UV sampling

**Step 4 — Sprite batch** 🔜
- [ ] Instanced draw for sprite batching
- [ ] Texture atlas support

**Step 5 — Shader pipeline** 🔜
- [x] GLSL → .shaderbundle compilation hook
- [ ] Uniform binding translation
- [ ] LOVE compatibility shaders (radial gradient, desaturation tint)

**Step 6 — Hybrid fallback** 🔜
- [ ] Per-command Canvas overlay
- [ ] Compositing GPU + software layers

## License

Same as [love2d](../love2d).
