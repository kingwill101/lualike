part of '../love_api_bindings.dart';

/// Matches the source header used to associate LOVE shader source with a
/// registered Flutter fragment asset.
final RegExp _registeredFlutterFragmentAssetSourcePattern = RegExp(
  r'(?:^|\n)\s*//\s*LOVE2D_FLUTTER_FRAGMENT_ASSET\s*:\s*(\S+)\s*(?:$|\n)',
);

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
      ? _registeredFlutterFragmentAssetKeyFromSource(first)
      : null;
  if (registeredFragmentAssetKey != null) {
    final shader = LoveShader(
      pixelCode: first,
      kind: LoveShaderKind.generic,
      flutterFragmentAssetKey: registeredFragmentAssetKey,
    );
    return shader;
  }

  final selection = _resolveShaderStageSourcesForBackend(
    firstSource: first,
    secondSource: second,
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
    return _wrapShader(context, shader);
  };
}

/// Resolves one shader source argument into source text.
Future<String> _resolveShaderSourceArgument(
  LibraryRegistrationContext context,
  Object? value, {
  required String symbol,
  required int argumentIndex,
}) async {
  final fileData = _filesystemFileDataCompatIfPresent(value);
  if (fileData != null) {
    return utf8.decode(fileData.bytes);
  }

  final source = _stringLike(value);
  if (source != null) {
    if (_looksLikeInlineShaderSourceText(source)) {
      return source;
    }

    final mounted = await _readMountedResourceFileData(
      context,
      source,
      symbol: symbol,
    );
    if (mounted != null) {
      return utf8.decode(mounted.bytes);
    }

    if (_looksLikeShaderFilePath(source)) {
      throw LuaError('Could not open file $source. Does not exist.');
    }

    return source;
  }

  final coerced = await _coerceResourceFileDataViaFilesystem(
    context,
    value,
    symbol,
  );
  if (coerced != null) {
    return utf8.decode(coerced.bytes);
  }

  throw LuaError(
    '$symbol expected shader source, filename, FileData, or File at argument $argumentIndex',
  );
}

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
