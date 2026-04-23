part of '../love_api_bindings.dart';

/// Returns the filesystem state used to resolve mounted resource paths.
LoveFilesystemState _filesystemStateForResource(
  LibraryContext context,
  String symbol,
) {
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No Lua runtime available for $symbol');
  }

  return LoveFilesystemState.of(interpreter);
}

/// Returns the standard LÖVE error for a missing resource file.
LuaError _missingResourceFileError(String filename) {
  return LuaError('Could not open file $filename. Does not exist.');
}

/// Writes [bytes] to [filename] or rethrows filesystem errors as [LuaError].
Future<void> _writeResourceBytesOrThrow(
  LibraryContext context,
  String filename,
  List<int> bytes, {
  required String symbol,
}) async {
  try {
    await _filesystemStateForResource(
      context,
      symbol,
    ).writeBytesOrThrow(filename, bytes, append: false);
  } on StateError catch (error) {
    throw LuaError(error.message);
  }
}

/// Reads mounted file data for [source] when it exists.
Future<LoveFilesystemFileData?> _readMountedResourceFileData(
  LibraryRegistrationContext context,
  String source, {
  required String symbol,
}) async {
  try {
    return await _filesystemStateForResource(
      context,
      symbol,
    ).readFileDataIfExistsOrThrow(source, filename: source);
  } on StateError catch (error) {
    throw LuaError(error.message);
  }
}

/// Tries to coerce [source] through `love.filesystem.newFileData`.
Future<LoveFilesystemFileData?> _coerceResourceFileDataViaFilesystem(
  LibraryRegistrationContext context,
  Object? source,
  String symbol,
) async {
  final interpreter = context.interpreter;
  if (interpreter == null) {
    throw StateError('No Lua runtime available for $symbol');
  }

  final loveTable = _tableIfPresent(interpreter.getCurrentEnv().get('love'));
  final filesystemTable = _tableIfPresent(loveTable?['filesystem']);
  final callable = filesystemTable?['newFileData'];
  if (callable == null) {
    return null;
  }

  final function = switch (callable) {
    final Value wrapped => wrapped,
    final BuiltinFunction builtIn => Value(builtIn),
    _ => null,
  };
  if (function == null) {
    return null;
  }

  Object? result;
  try {
    result = await interpreter.callFunction(
      function,
      <Object?>[source],
      debugName: 'love.filesystem.newFileData',
      debugNameWhat: 'function',
    );
  } on LuaError {
    return null;
  }

  final data = _filesystemFileDataCompatIfPresent(result);
  if (data != null) {
    return data;
  }

  final raw = _rawValue(result);
  if (raw is List && raw.isNotEmpty) {
    final first = raw.first;
    final nested = _filesystemFileDataCompatIfPresent(first);
    if (nested != null) {
      return nested;
    }
    if (first == null && raw.length >= 2 && raw[1] is String) {
      throw LuaError('$symbol ${raw[1]}');
    }
  }

  return null;
}

/// Returns resource file data for [source] or throws a Lua-facing type error.
Future<LoveFilesystemFileData> _requireResourceFileData(
  LibraryRegistrationContext context,
  Object? source,
  String symbol, {
  int argumentIndex = 1,
  String expectedKinds = 'filename, FileData, or File',
}) async {
  final coerced = await _resourceFileDataIfPresent(context, source, symbol);
  if (coerced != null) {
    return coerced;
  }

  throw LuaError('$symbol expected $expectedKinds at argument $argumentIndex');
}

/// Returns resource file data for [source] when it can be resolved.
Future<LoveFilesystemFileData?> _resourceFileDataIfPresent(
  LibraryRegistrationContext context,
  Object? source,
  String symbol,
) async {
  final compat = _filesystemFileDataCompatIfPresent(source);
  if (compat != null) {
    return compat;
  }

  final filename = _stringLike(source);
  if (filename != null) {
    final mounted = await _readMountedResourceFileData(
      context,
      filename,
      symbol: symbol,
    );
    if (mounted != null) {
      return mounted;
    }

    throw _missingResourceFileError(filename);
  }

  return _coerceResourceFileDataViaFilesystem(context, source, symbol);
}

/// Resolves a source object to its mounted or synthesized resource path.
Future<String?> _resolveResourceSourcePath(
  LibraryRegistrationContext context,
  Object? source, {
  required String symbol,
}) async {
  final compat = _filesystemFileDataCompatIfPresent(source);
  if (compat != null) {
    return compat.filename;
  }

  final filename = _stringLike(source);
  if (filename != null) {
    final data = await _readMountedResourceFileData(
      context,
      filename,
      symbol: symbol,
    );
    if (data != null) {
      return data.filename;
    }

    throw _missingResourceFileError(filename);
  }

  final coerced = await _coerceResourceFileDataViaFilesystem(
    context,
    source,
    symbol,
  );
  return coerced?.filename;
}

/// Resolves the Flutter asset key backing [source], when it is bundle-backed.
///
/// This converts LOVE-visible relative source paths into the mounted asset key
/// rooted at the active source entry path. Non-bundle mounts return `null`,
/// which lets the host keep using decoded bytes without probing Flame's image
/// cache with an invalid asset key.
Future<String?> _resolveResourceAssetKeyIfPresent(
  LibraryRegistrationContext context,
  Object? source, {
  required String symbol,
}) async {
  final compat = _filesystemFileDataCompatIfPresent(source);
  final filename = compat?.filename ?? _stringLike(source);
  if (filename == null || filename.isEmpty) {
    return null;
  }

  final filesystem = _filesystemStateForResource(context, symbol);
  final normalizedFilename = path.posix.normalize(filename.replaceAll('\\', '/'));
  final candidates = <String>{normalizedFilename};
  final sourceBaseDirectory = filesystem
      .getSourceBaseDirectory()
      .replaceAll('\\', '/');
  if (sourceBaseDirectory.isNotEmpty) {
    candidates.add(
      path.posix.normalize(
        path.posix.join(sourceBaseDirectory, normalizedFilename),
      ),
    );
  }

  for (final candidate in candidates) {
    if (candidate.isEmpty || candidate == '.') {
      continue;
    }
    if (await filesystem.adapter.fileExists(candidate)) {
      return candidate;
    }
  }

  return null;
}
