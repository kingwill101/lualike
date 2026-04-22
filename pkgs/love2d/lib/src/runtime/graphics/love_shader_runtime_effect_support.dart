part of '../love_runtime.dart';

const String _loveShaderFlutterFragmentAssetMetadataKey =
    'LOVE2D_FLUTTER_FRAGMENT_ASSET';

final RegExp _loveShaderFlutterFragmentAssetPattern = RegExp(
  '(?:^|\\n)\\s*//\\s*'
  '$_loveShaderFlutterFragmentAssetMetadataKey'
  r'\s*:\s*(\S+)\s*(?:$|\n)',
);

String? _extractLoveShaderFlutterFragmentAssetKey(String source) {
  final match = _loveShaderFlutterFragmentAssetPattern.firstMatch(source);
  return match?.group(1);
}

bool loveShaderUsesFlutterFragmentAsset(LoveShader shader) =>
    shader.flutterFragmentAssetKey != null;

LoveImage? loveShaderSamplerUniformImage(LoveShader shader, String name) {
  final value = shader.uniform(name);
  return switch (value) {
    final LoveImage image => image,
    _ => null,
  };
}
