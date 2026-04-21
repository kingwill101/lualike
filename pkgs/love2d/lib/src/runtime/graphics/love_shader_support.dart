part of '../love_runtime.dart';

enum LoveShaderKind { generic, radialGradient }

class LoveShader {
  LoveShader({
    required this.pixelCode,
    this.vertexCode,
    required this.kind,
    Map<String, Object?>? uniforms,
  }) : _uniforms = uniforms == null
           ? <String, Object?>{}
           : uniforms.map(
               (key, value) => MapEntry(key, _cloneLoveShaderUniform(value)),
             );

  factory LoveShader.fromSource(String pixelCode, {String? vertexCode}) {
    return LoveShader(
      pixelCode: pixelCode,
      vertexCode: vertexCode,
      kind: _detectLoveShaderKind(pixelCode, vertexCode: vertexCode),
    );
  }

  final String pixelCode;
  final String? vertexCode;
  final LoveShaderKind kind;
  final Map<String, Object?> _uniforms;

  Map<String, Object?> get uniforms => Map<String, Object?>.unmodifiable(
    _uniforms.map(
      (key, value) => MapEntry(key, _cloneLoveShaderUniform(value)),
    ),
  );

  Object? uniform(String name) => _cloneLoveShaderUniform(_uniforms[name]);

  void send(String name, Object? value) {
    _uniforms[name] = _cloneLoveShaderUniform(value);
  }

  LoveShader snapshot() {
    return LoveShader(
      pixelCode: pixelCode,
      vertexCode: vertexCode,
      kind: kind,
      uniforms: _uniforms,
    );
  }
}

LoveShaderKind _detectLoveShaderKind(String pixelCode, {String? vertexCode}) {
  final source = '${vertexCode ?? ''}\n$pixelCode'.toLowerCase();
  final isRadialGradient =
      source.contains('extern number innerradius') &&
      source.contains('extern number outerradius') &&
      source.contains('extern vec2 center') &&
      source.contains('extern vec4 colorinner') &&
      source.contains('extern vec4 colorouter') &&
      source.contains('distance(screen_coords, center)') &&
      source.contains('smoothstep(innerradius, outerradius, dist)') &&
      source.contains('mix(colorinner, colorouter, t)');
  return isRadialGradient
      ? LoveShaderKind.radialGradient
      : LoveShaderKind.generic;
}

Object? _cloneLoveShaderUniform(Object? value) {
  return switch (value) {
    final List<Object?> list => List<Object?>.unmodifiable(
      list.map(_cloneLoveShaderUniform),
    ),
    final Map<Object?, Object?> map => Map<Object?, Object?>.unmodifiable(
      map.map((key, item) => MapEntry(key, _cloneLoveShaderUniform(item))),
    ),
    _ => value,
  };
}
