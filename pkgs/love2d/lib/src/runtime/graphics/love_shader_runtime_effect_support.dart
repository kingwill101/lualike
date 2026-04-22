part of '../love_runtime.dart';

/// The shader-source metadata key that names a Flutter fragment asset.
const String _loveShaderFlutterFragmentAssetMetadataKey =
    'LOVE2D_FLUTTER_FRAGMENT_ASSET';

/// Matches inline Flutter fragment asset metadata embedded in shader source.
final RegExp _loveShaderFlutterFragmentAssetPattern = RegExp(
  '(?:^|\\n)\\s*//\\s*'
  '$_loveShaderFlutterFragmentAssetMetadataKey'
  r'\s*:\s*(\S+)\s*(?:$|\n)',
);

/// Extracts a registered Flutter fragment asset key from [source].
String? _extractLoveShaderFlutterFragmentAssetKey(String source) {
  final match = _loveShaderFlutterFragmentAssetPattern.firstMatch(source);
  return match?.group(1);
}

/// Whether [shader] is backed by a registered Flutter fragment asset.
bool loveShaderUsesFlutterFragmentAsset(LoveShader shader) =>
    shader.flutterFragmentAssetKey != null;

/// Returns the sampler uniform image bound to [name] on [shader], if any.
LoveImage? loveShaderSamplerUniformImage(LoveShader shader, String name) {
  final value = shader.uniform(name);
  return switch (value) {
    final LoveImage image => image,
    _ => null,
  };
}
