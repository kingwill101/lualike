import 'package:flutter_gpu/gpu.dart' as gpu;

/// Loads and caches the LOVE2D GPU shader bundle.
///
/// The shader bundle is a compiled `.shaderbundle` asset produced by `impellerc`
/// from the GLSL sources in `lib/src/shader/`. It contains three pipelines:
///
/// | Pipeline Name | Vertex | Fragment | Use Case |
/// |---|---|---|---|
/// | `UnlitPipeline` | love_base.vert | love_unlit.frag | Untextured meshes, shapes |
/// | `TexturedPipeline` | love_base.vert | love_textured.frag | Textured meshes, images |
/// | `SpriteBatchPipeline` | love_sprite_batch.vert | love_textured.frag | Sprite batches |
///
/// See `tools/compile_shaders.sh` to regenerate the bundle.
class LoveShaderBundles {
  LoveShaderBundles._();

  static bool _loaded = false;

  /// The base vertex shader (position + UV + color passthrough).
  static late final gpu.Shader baseVertex;

  /// The sprite batch vertex shader with instance-rate transforms and tint.
  static late final gpu.Shader spriteBatchVertex;

  /// The unlit fragment shader (solid vertex color output).
  static late final gpu.Shader unlitFragment;

  /// The textured fragment shader (texture sample * vertex color).
  static late final gpu.Shader texturedFragment;

  /// Loads the shader bundle from the asset path.
  ///
  /// Must be called once before any rendering. Throws if the bundle cannot be
  /// loaded (e.g., the asset was not compiled or the app is running on a
  /// Flutter SDK without flutter_gpu support).
  ///
  /// The loader tries a few common asset keys so the package works both when
  /// run from this repo and when consumed as a dependency.
  static Future<void> load({
    String assetPath = 'packages/love2d_gpu/assets/love2d_gpu.shaderbundle',
  }) async {
    if (_loaded) return;

    final candidates = <String>{
      assetPath,
      'love2d_gpu/assets/love2d_gpu.shaderbundle',
      'assets/love2d_gpu.shaderbundle',
      'build/shaderbundles/love2d_gpu.shaderbundle',
      'packages/love2d_gpu/assets/love2d_gpu.shaderbundle',
      'packages/love2d_gpu/build/shaderbundles/love2d_gpu.shaderbundle',
      'flutter_gpu_shaders/shaderbundles/love2d_gpu.shaderbundle',
      'packages/love2d_gpu/flutter_gpu_shaders/shaderbundles/love2d_gpu.shaderbundle',
    }.toList(growable: false);

    gpu.ShaderLibrary? library;
    for (final candidate in candidates) {
      try {
        library = await gpu.ShaderLibrary.fromAsset(candidate);
      } catch (_) {
        library = null;
      }
      if (library != null) break;
    }
    if (library == null) {
      throw StateError(
        'Failed to load LOVE2D GPU shader bundle.\n'
        'Tried: ${candidates.join(', ')}\n'
        'Make sure the shaders are compiled (run tools/compile_shaders.sh) '
        'and the asset is declared in pubspec.yaml under flutter: assets:.',
      );
    }

    baseVertex = _requireShader(library, 'LoveBaseVertex');
    spriteBatchVertex = _requireShader(library, 'LoveSpriteBatchVertex');
    unlitFragment = _requireShader(library, 'LoveUnlitFragment');
    texturedFragment = _requireShader(library, 'LoveTexturedFragment');

    _loaded = true;
  }

  static gpu.Shader _requireShader(gpu.ShaderLibrary library, String name) {
    final shader = library[name];
    if (shader == null) {
      throw StateError(
        'Shader "$name" not found in the LOVE2D GPU bundle.\n'
        'Check that tools/compile_shaders.sh produces a bundle with this entry.',
      );
    }
    return shader;
  }
}
