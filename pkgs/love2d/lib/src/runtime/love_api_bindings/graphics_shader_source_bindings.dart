part of '../love_api_bindings.dart';

/// Matches the source header used to associate LOVE shader source with a
/// registered Flutter fragment asset.
final RegExp _registeredFlutterFragmentAssetSourcePattern = RegExp(
  r'(?:^|\n)\s*//\s*LOVE2D_FLUTTER_FRAGMENT_ASSET\s*:\s*(\S+)\s*(?:$|\n)',
);

/// Resolved shader source text plus the filename it came from, when any.
class _ResolvedShaderSourceArgument {
  /// Creates resolved shader source text with optional filename context.
  const _ResolvedShaderSourceArgument({
    required this.source,
    this.resolvedFilename,
  });

  /// The decoded shader source text.
  final String source;

  /// The resolved filename used to load [source], if it came from the
  /// filesystem.
  final String? resolvedFilename;
}

/// Builds a [LoveShader] from `love.graphics.newShader`-style arguments.
///
/// When the resolved source contains a registered Flutter fragment asset
/// marker, this returns a shader that binds against that precompiled asset
/// instead of attempting runtime translation.
Future<LoveShader> _createShaderFromSourceArguments(
  LibraryRegistrationContext context, {
  required Object? firstValue,
  Object? secondValue,
  required String symbol,
  required int firstArgumentIndex,
  required bool gles,
}) async {
  final first = await _resolveShaderSourceArgument(
    context,
    firstValue,
    symbol: symbol,
    argumentIndex: firstArgumentIndex,
  );
  final second = secondValue == null
      ? null
      : await _resolveShaderSourceArgument(
          context,
          secondValue,
          symbol: symbol,
          argumentIndex: firstArgumentIndex + 1,
        );

  final registeredFragmentAssetKey = second == null
      ? _registeredFlutterFragmentAssetKeyFromResolvedSource(context, first) ??
            _registeredFlutterFragmentAssetKeyFromSource(first.source)
      : null;
  if (registeredFragmentAssetKey != null) {
    final shader = LoveShader(
      pixelCode: first.source,
      kind: LoveShaderKind.generic,
      flutterFragmentAssetKey: registeredFragmentAssetKey,
    );
    return shader;
  }

  final selection = _resolveShaderStageSourcesForBackend(
    firstSource: first.source,
    secondSource: second?.source,
    gles: gles,
  );
  return LoveShader.fromSource(
    selection.pixelSource ?? '',
    vertexCode: selection.vertexSource,
  );
}

/// Returns the backend error message for unsupported runtime shader source.
String? _unsupportedShaderSourceMessage(
  LoveShader shader, {
  required String symbol,
}) {
  if (shader.kind == LoveShaderKind.radialGradient ||
      shader.kind == LoveShaderKind.desaturationTint ||
      loveShaderUsesFlutterFragmentAsset(shader)) {
    return null;
  }

  return switch (symbol) {
    'love.graphics.newShader' => _loveGraphicsNewShaderUnsupportedMessage,
    'love.graphics.validateShader' =>
      _loveGraphicsValidateShaderUnsupportedMessage,
    _ =>
      '$symbol does not support arbitrary runtime shader source on the Flutter backend yet',
  };
}

/// Returns a validation error for a registered Flutter fragment shader asset,
/// if one is reported by the host backend.
Future<String?> _registeredFragmentShaderValidationError(
  LibraryContext context,
  LoveShader shader,
) async {
  final assetKey = shader.flutterFragmentAssetKey;
  if (assetKey == null) {
    return null;
  }

  final runtime = _runtimeContext(context);
  return await runtime.host.validateRegisteredFragmentShaderAsset(assetKey);
}

/// Binds `love.graphics.newShader`.
///
/// This resolves LOVE's one-source or two-source shader arguments, rejects
/// runtime GLSL that the Flutter backend cannot compile yet, validates any
/// registered fragment asset reference, and returns a wrapped `Shader`.
LoveApiImplementation _bindGraphicsNewShader(
  LibraryRegistrationContext context,
) {
  return (args) async {
    const symbol = 'love.graphics.newShader';
    final shader = await _createShaderFromSourceArguments(
      context,
      firstValue: _valueAt(args, 0),
      secondValue: args.length >= 2 ? _valueAt(args, 1) : null,
      symbol: symbol,
      firstArgumentIndex: 1,
      gles: false,
    );
    final unsupportedMessage = _unsupportedShaderSourceMessage(
      shader,
      symbol: symbol,
    );
    if (unsupportedMessage != null) {
      throw LuaError(unsupportedMessage);
    }

    final validationError = await _registeredFragmentShaderValidationError(
      context,
      shader,
    );
    if (validationError != null) {
      throw LuaError(validationError);
    }
    return _wrapShader(context, shader);
  };
}

/// Resolves one shader source argument into source text.
Future<_ResolvedShaderSourceArgument> _resolveShaderSourceArgument(
  LibraryRegistrationContext context,
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) async {
  final fileData = _filesystemFileDataCompatIfPresent(value);
  if (fileData != null) {
    return _ResolvedShaderSourceArgument(
      source: utf8.decode(fileData.bytes),
      resolvedFilename: fileData.filename,
    );
  }

  final source = _stringLike(value);
  if (source != null) {
    if (_looksLikeInlineShaderSourceText(source)) {
      return _ResolvedShaderSourceArgument(source: source);
    }

    final mounted = await _readMountedResourceFileData(
      context,
      source,
      symbol: symbol,
    );
    if (mounted != null) {
      return _ResolvedShaderSourceArgument(
        source: utf8.decode(mounted.bytes),
        resolvedFilename: mounted.filename,
      );
    }

    if (_looksLikeShaderFilePath(source)) {
      throw LuaError('Could not open file $source. Does not exist.');
    }

    return _ResolvedShaderSourceArgument(source: source);
  }

  final coerced = await _coerceResourceFileDataViaFilesystem(
    context,
    value,
    symbol,
  );
  if (coerced != null) {
    return _ResolvedShaderSourceArgument(
      source: utf8.decode(coerced.bytes),
      resolvedFilename: coerced.filename,
    );
  }

  throw LuaError(
    '$symbol expected shader source, filename, FileData, or File at argument $argumentIndex',
  );
}

/// Resolves the backend pixel and vertex shader sources for the current
/// renderer capabilities.
LoveShaderStageSelection _resolveShaderStageSourcesForBackend({
  required String? firstSource,
  required String? secondSource,
  required bool gles,
}) {
  try {
    return loveResolveShaderStageSources(
      firstSource: firstSource,
      secondSource: secondSource,
      gles: gles,
      supportsGlsl3: _loveGraphicsSupportedFeatures['glsl3'] ?? false,
      gammaCorrect: false,
    );
  } on LoveShaderTranslationException catch (error) {
    throw LuaError(error.message);
  }
}

/// Returns whether [source] looks more like a shader filename than inline
/// shader text.
bool _looksLikeShaderFilePath(String source) {
  if (source.isEmpty || source.length >= 64) {
    return false;
  }

  if (source.contains('\n') || source.contains('\r')) {
    return false;
  }

  final dotIndex = source.indexOf('.');
  if (dotIndex < 0) {
    return false;
  }

  final extension = source.substring(dotIndex);
  return !extension.contains(';') && !extension.contains(' ');
}

/// Returns the registered Flutter fragment asset key embedded in [source].
String? _registeredFlutterFragmentAssetKeyFromSource(String source) {
  final match = _registeredFlutterFragmentAssetSourcePattern.firstMatch(source);
  return match?.group(1);
}

/// Infers a Flutter fragment asset key from a resolved shader file source.
///
/// This accepts explicit asset-style filenames directly and can also infer an
/// asset key relative to the mounted LOVE source directory when the loaded file
/// already looks like Flutter runtime-effect source.
String? _registeredFlutterFragmentAssetKeyFromResolvedSource(
  LibraryRegistrationContext context,
  _ResolvedShaderSourceArgument source,
) {
  final filename = source.resolvedFilename;
  if (filename == null ||
      !_looksLikeFlutterShaderAssetFilename(filename) ||
      !_looksLikeFlutterFragmentShaderSource(source.source)) {
    return null;
  }

  final normalizedFilename = _normalizeForwardSlashPath(filename);
  if (_looksLikeExplicitFlutterAssetKey(normalizedFilename)) {
    return normalizedFilename;
  }

  final interpreter = context.interpreter;
  if (interpreter == null) {
    return null;
  }

  final mountedSource = LoveFilesystemState.of(interpreter).source;
  if (mountedSource.isEmpty) {
    return null;
  }

  final mountedDirectory = _mountedSourceDirectory(mountedSource);
  if (mountedDirectory.isEmpty) {
    return null;
  }

  final inferredAssetKey = _normalizeForwardSlashPath(
    '$mountedDirectory/$normalizedFilename',
  );
  return _looksLikeInferredFlutterAssetKey(inferredAssetKey)
      ? inferredAssetKey
      : null;
}

/// Returns whether [filename] uses a common fragment-shader asset extension.
bool _looksLikeFlutterShaderAssetFilename(String filename) {
  final lower = filename.toLowerCase();
  return lower.endsWith('.frag') ||
      lower.endsWith('.glsl') ||
      lower.endsWith('.fsh') ||
      lower.endsWith('.fs');
}

/// Returns whether [source] looks like Flutter fragment-shader source instead
/// of LOVE effect code.
bool _looksLikeFlutterFragmentShaderSource(String source) {
  final trimmed = source.trimLeft();
  if (trimmed.startsWith('// LOVE2D_FLUTTER_FRAGMENT_ASSET:') ||
      trimmed.startsWith('/* LOVE2D_FLUTTER_FRAGMENT_ASSET:')) {
    return true;
  }

  if (trimmed.contains('vec4 effect(') || trimmed.contains('void effect(')) {
    return false;
  }

  return trimmed.contains('#include <flutter/runtime_effect.glsl>') ||
      trimmed.contains('FlutterFragCoord(') ||
      (trimmed.contains('out vec4 fragColor') &&
          trimmed.contains('void main('));
}

/// Returns whether [path] is already an explicit Flutter asset key.
bool _looksLikeExplicitFlutterAssetKey(String path) {
  return path.startsWith('assets/') ||
      path.startsWith('packages/') ||
      path.startsWith('test_assets/');
}

/// Returns whether [path] looks like a valid inferred Flutter asset key.
bool _looksLikeInferredFlutterAssetKey(String path) {
  return path.isNotEmpty &&
      path.contains('/') &&
      !path.startsWith('/') &&
      !path.startsWith(r'\') &&
      !path.contains('://');
}

/// Returns the directory portion of a mounted LOVE source path.
String _mountedSourceDirectory(String source) {
  final normalized = _normalizeForwardSlashPath(source);
  if (normalized.isEmpty) {
    return '';
  }

  final lastSlash = normalized.lastIndexOf('/');
  if (lastSlash < 0) {
    return normalized.contains('.') ? '' : normalized;
  }

  final lastSegment = normalized.substring(lastSlash + 1);
  return lastSegment.contains('.')
      ? normalized.substring(0, lastSlash)
      : normalized;
}

/// Normalizes [path] to a forward-slash relative path without `.` segments.
String _normalizeForwardSlashPath(String path) {
  final segments = <String>[];
  for (final segment in path.replaceAll('\\', '/').split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (segments.isNotEmpty) {
        segments.removeLast();
      }
      continue;
    }
    segments.add(segment);
  }
  return segments.join('/');
}

/// Whether [source] already looks like inline shader source text.
bool _looksLikeInlineShaderSourceText(String source) {
  if (source.contains('\n') || source.contains('\r')) {
    return true;
  }

  final trimmed = source.trimLeft();
  return trimmed.startsWith('// LOVE2D_FLUTTER_FRAGMENT_ASSET:') ||
      trimmed.startsWith('#version ') ||
      trimmed.startsWith('#pragma language ') ||
      trimmed.contains('uniform ') ||
      trimmed.contains('extern ') ||
      trimmed.contains('void main(') ||
      trimmed.contains('vec4 effect(') ||
      trimmed.contains('void effect(');
}
