part of '../love_runtime.dart';

/// The shader handling path selected for a LOVE shader on the Flutter backend.
enum LoveShaderKind { generic, radialGradient, desaturationTint }

/// The binding category inferred from a parsed shader uniform declaration.
enum LoveShaderUniformValueKind {
  unknown,
  float,
  matrix,
  int,
  uint,
  bool_,
  sampler,
}

final RegExp _loveShaderBlockCommentPattern = RegExp(r'/\*[\s\S]*?\*/');
final RegExp _loveShaderLineCommentPattern = RegExp(r'//.*$', multiLine: true);
final RegExp _loveShaderUniformDeclarationPattern = RegExp(
  r'\b(?:extern|uniform)\s+([A-Za-z_]\w*)\s+([A-Za-z_]\w*)(?:\s*\[\s*(\d+)\s*\])?\s*;',
);

/// Metadata parsed from a LOVE shader uniform declaration.
///
/// This is extracted from author-provided shader source when available, but it
/// is also used with compiled Flutter fragment metadata. In that compiled
/// form, sampler uniforms may appear as `uniform shader name;` instead of a
/// GLSL `sampler*` type.
class LoveShaderUniformDescriptor {
  /// Creates a descriptor for a declared uniform type.
  const LoveShaderUniformDescriptor({required this.typeName, this.arrayLength});

  /// Creates a descriptor for an unrecognized uniform declaration.
  const LoveShaderUniformDescriptor.unknown()
    : typeName = 'unknown',
      arrayLength = null;

  /// The normalized declared type name.
  final String typeName;

  /// The declared array length, if this uniform is an array.
  final int? arrayLength;

  /// Whether this uniform can accept a LOVE color payload directly.
  bool get isColorCompatible => typeName == 'vec3' || typeName == 'vec4';

  /// The number of scalar components in this uniform, if it is vector-like.
  int? get componentCount => switch (typeName) {
    'number' || 'float' || 'int' || 'uint' || 'bool' => 1,
    'vec2' || 'ivec2' || 'uvec2' || 'bvec2' => 2,
    'vec3' || 'ivec3' || 'uvec3' || 'bvec3' => 3,
    'vec4' || 'ivec4' || 'uvec4' || 'bvec4' => 4,
    _ => null,
  };

  /// The matrix dimension when this uniform is a square matrix.
  int? get squareMatrixDimension => switch (typeName) {
    'mat2' || 'mat2x2' => 2,
    'mat3' || 'mat3x3' => 3,
    'mat4' || 'mat4x4' => 4,
    _ => null,
  };

  /// The binding path implied by [typeName].
  ///
  /// Compiled Flutter fragment metadata may encode sampled images as the
  /// `shader` type, which still maps to [LoveShaderUniformValueKind.sampler].
  LoveShaderUniformValueKind get valueKind {
    if (squareMatrixDimension != null) {
      return LoveShaderUniformValueKind.matrix;
    }

    return switch (typeName) {
      'number' ||
      'float' ||
      'vec2' ||
      'vec3' ||
      'vec4' => LoveShaderUniformValueKind.float,
      'int' || 'ivec2' || 'ivec3' || 'ivec4' => LoveShaderUniformValueKind.int,
      'uint' ||
      'uvec2' ||
      'uvec3' ||
      'uvec4' => LoveShaderUniformValueKind.uint,
      'bool' ||
      'bvec2' ||
      'bvec3' ||
      'bvec4' => LoveShaderUniformValueKind.bool_,
      'shader' ||
      'image' ||
      'arrayimage' ||
      'cubeimage' ||
      'volumeimage' ||
      'depthimage' ||
      'deptharrayimage' ||
      'depthcubeimage' => LoveShaderUniformValueKind.sampler,
      _ when typeName.startsWith('sampler') || typeName.endsWith('image') =>
        LoveShaderUniformValueKind.sampler,
      _ => LoveShaderUniformValueKind.unknown,
    };
  }
}

/// A LOVE shader definition together with its current uniform values.
///
/// When [flutterFragmentAssetKey] is set, this shader binds against a
/// precompiled Flutter fragment asset instead of going through runtime shader
/// translation on the Flutter backend.
class LoveShader {
  /// Creates a LOVE shader instance.
  LoveShader({
    required this.pixelCode,
    this.vertexCode,
    required this.kind,
    String? flutterFragmentAssetKey,
    Map<String, Object?>? uniforms,
    Map<String, LoveShaderUniformDescriptor>? uniformDeclarations,
  }) : flutterFragmentAssetKey =
           flutterFragmentAssetKey ??
           _extractLoveShaderFlutterFragmentAssetKey(pixelCode) ??
           (vertexCode == null
               ? null
               : _extractLoveShaderFlutterFragmentAssetKey(vertexCode)),
       _uniforms = uniforms == null
           ? <String, Object?>{}
           : uniforms.map(
               (key, value) => MapEntry(key, _cloneLoveShaderUniform(value)),
             ),
       _uniformDeclarations = uniformDeclarations == null
           ? _extractLoveShaderUniformDeclarations(
               pixelCode,
               vertexCode: vertexCode,
             )
           : Map<String, LoveShaderUniformDescriptor>.unmodifiable(
               uniformDeclarations,
             );

  /// Creates a shader from source and infers [kind] from supported
  /// compatibility patterns.
  factory LoveShader.fromSource(String pixelCode, {String? vertexCode}) {
    return LoveShader(
      pixelCode: pixelCode,
      vertexCode: vertexCode,
      kind: _detectLoveShaderKind(pixelCode, vertexCode: vertexCode),
    );
  }

  /// The pixel-stage source that defines this shader.
  final String pixelCode;

  /// The vertex-stage source for this shader, if one was provided.
  final String? vertexCode;

  /// The detected backend handling mode for this shader.
  final LoveShaderKind kind;

  /// The registered Flutter fragment asset used to instantiate this shader.
  final String? flutterFragmentAssetKey;
  final Map<String, Object?> _uniforms;
  final Map<String, LoveShaderUniformDescriptor> _uniformDeclarations;

  /// The current uniform values stored on this shader.
  Map<String, Object?> get uniforms => Map<String, Object?>.unmodifiable(
    _uniforms.map(
      (key, value) => MapEntry(key, _cloneLoveShaderUniform(value)),
    ),
  );

  /// The parsed uniform declarations available for binding.
  Map<String, LoveShaderUniformDescriptor> get uniformDeclarations =>
      Map<String, LoveShaderUniformDescriptor>.unmodifiable(
        _uniformDeclarations,
      );

  /// Returns the current value stored for the uniform named [name].
  Object? uniform(String name) => _cloneLoveShaderUniform(_uniforms[name]);

  /// Returns the parsed declaration for the uniform named [name].
  LoveShaderUniformDescriptor? uniformDeclaration(String name) =>
      _uniformDeclarations[name];

  /// Stores [value] for the uniform named [name].
  void send(String name, Object? value) {
    _uniforms[name] = _cloneLoveShaderUniform(value);
  }

  /// Creates an immutable snapshot of this shader state.
  LoveShader snapshot() {
    return LoveShader(
      pixelCode: pixelCode,
      vertexCode: vertexCode,
      kind: kind,
      flutterFragmentAssetKey: flutterFragmentAssetKey,
      uniforms: _uniforms,
      uniformDeclarations: _uniformDeclarations,
    );
  }
}

LoveShaderKind _detectLoveShaderKind(String pixelCode, {String? vertexCode}) {
  final source = _normalizedLoveShaderDetectionSource(
    pixelCode,
    vertexCode: vertexCode,
  );
  if (_isLoveRadialGradientShaderSource(source)) {
    return LoveShaderKind.radialGradient;
  }
  if (_isLoveDesaturationTintShaderSource(source)) {
    return LoveShaderKind.desaturationTint;
  }
  return LoveShaderKind.generic;
}

String _normalizedLoveShaderDetectionSource(
  String pixelCode, {
  String? vertexCode,
}) {
  return '${vertexCode ?? ''}\n$pixelCode'
      .replaceAll(_loveShaderBlockCommentPattern, ' ')
      .replaceAll(_loveShaderLineCommentPattern, '')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

bool _isLoveRadialGradientShaderSource(String source) {
  return source.contains('extern number innerradius') &&
      source.contains('extern number outerradius') &&
      source.contains('extern vec2 center') &&
      source.contains('extern vec4 colorinner') &&
      source.contains('extern vec4 colorouter') &&
      source.contains('distance(screen_coords, center)') &&
      source.contains('smoothstep(innerradius, outerradius, dist)') &&
      source.contains('mix(colorinner, colorouter, t)');
}

bool _isLoveDesaturationTintShaderSource(String source) {
  return RegExp(r'extern\s+vec4\s+tint\s*;').hasMatch(source) &&
      RegExp(r'extern\s+(?:number|float)\s+strength\s*;').hasMatch(source) &&
      source.contains('dot(vec3(0.299') &&
      source.contains('0.587') &&
      source.contains('0.114') &&
      RegExp(
        r'return\s+mix\s*\(\s*color\s*,\s*tint\s*\*\s*luma\s*,\s*strength\s*\)',
      ).hasMatch(source);
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

/// Parses uniform declarations from author source and compiled fragment
/// metadata.
Map<String, LoveShaderUniformDescriptor> _extractLoveShaderUniformDeclarations(
  String pixelCode, {
  String? vertexCode,
}) {
  final declarations = <String, LoveShaderUniformDescriptor>{};

  void addDeclarationsFrom(String source) {
    final strippedSource = source
        .replaceAll(_loveShaderBlockCommentPattern, ' ')
        .replaceAll(_loveShaderLineCommentPattern, '');
    for (final match in _loveShaderUniformDeclarationPattern.allMatches(
      strippedSource,
    )) {
      final rawType = match.group(1);
      final name = match.group(2);
      if (rawType == null || name == null || declarations.containsKey(name)) {
        continue;
      }

      declarations[name] = LoveShaderUniformDescriptor(
        typeName: rawType.toLowerCase(),
        arrayLength: switch (match.group(3)) {
          final String length => int.tryParse(length),
          null => null,
        },
      );
    }
  }

  addDeclarationsFrom(pixelCode);
  if (vertexCode case final String vertexSource?) {
    addDeclarationsFrom(vertexSource);
  }

  return Map<String, LoveShaderUniformDescriptor>.unmodifiable(declarations);
}
