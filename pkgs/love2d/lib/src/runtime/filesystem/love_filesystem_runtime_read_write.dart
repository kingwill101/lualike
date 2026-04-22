part of 'love_filesystem_runtime.dart';

/// Implements read, write, and chunk-loading operations on the filesystem
/// runtime.
extension LoveFilesystemRuntimeReadWrite on LoveFilesystemState {
  /// Reads up to [size] bytes from [logicalPath].
  ///
  /// Returns `null` when the path does not resolve to a readable file.
  Future<List<int>?> readAllBytes(String logicalPath, {int size = -1}) async {
    return readAllBytesIfExistsOrThrow(logicalPath, size: size);
  }

  /// Writes [bytes] to [logicalPath].
  ///
  /// Returns `false` when the save directory cannot be prepared or the target
  /// file cannot be opened for writing.
  Future<bool> writeBytes(
    String logicalPath,
    List<int> bytes, {
    required bool append,
  }) async {
    try {
      await writeBytesOrThrow(logicalPath, bytes, append: append);
      return true;
    } on StateError {
      return false;
    }
  }

  /// Writes [bytes] to [logicalPath] and throws a [StateError] on failure.
  Future<void> writeBytesOrThrow(
    String logicalPath,
    List<int> bytes, {
    required bool append,
  }) async {
    final targetPath = await resolveWritablePhysicalPath(logicalPath);
    if (targetPath == null) {
      throw StateError('Could not set write directory.');
    }

    if (!await _ensureSaveDirectoryExists()) {
      throw StateError('Could not set write directory.');
    }

    final parent = path.dirname(targetPath);
    final saveDirectory = getSaveDirectory();
    if (path.normalize(parent) != path.normalize(saveDirectory) &&
        !await adapter.directoryExists(parent)) {
      throw StateError('Could not open file $logicalPath.');
    }

    final device = await _openFilesystemDeviceOrThrow(
      adapter,
      targetPath,
      append ? 'a' : 'w',
      logicalPath: logicalPath,
    );
    try {
      final result = await device.writeBytes(bytes);
      if (!result.success) {
        throw StateError(result.error ?? 'Data could not be written.');
      }
      await device.flush();
    } finally {
      await device.close();
    }
  }

  /// Reads [logicalPath] into a [LoveFilesystemFileData] object.
  ///
  /// Returns `null` when the file does not exist.
  Future<LoveFilesystemFileData?> readFileData(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) async {
    final bytes = await readAllBytesIfExistsOrThrow(logicalPath, size: size);
    if (bytes == null) {
      return null;
    }

    return LoveFilesystemFileData(
      bytes: bytes,
      filename: filename ?? logicalPath,
    );
  }

  /// Reads [logicalPath] into a [LoveFilesystemFileData] object when it
  /// exists.
  Future<LoveFilesystemFileData?> readFileDataIfExistsOrThrow(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) async {
    final bytes = await readAllBytesIfExistsOrThrow(logicalPath, size: size);
    if (bytes == null) {
      return null;
    }

    return LoveFilesystemFileData(
      bytes: bytes,
      filename: filename ?? logicalPath,
    );
  }

  /// Reads [logicalPath] into a [LoveFilesystemFileData] object.
  ///
  /// Throws a [StateError] when the file cannot be opened.
  Future<LoveFilesystemFileData> readFileDataOrThrow(
    String logicalPath, {
    int size = -1,
    String? filename,
  }) async {
    final bytes = await readAllBytesOrThrow(logicalPath, size: size);
    return LoveFilesystemFileData(
      bytes: bytes,
      filename: filename ?? logicalPath,
    );
  }

  /// Resolves [logicalPath] to the first readable physical host path.
  ///
  /// Returns `null` for paths backed only by virtual archive mounts or for
  /// logical paths that are not currently visible.
  Future<String?> resolveReadablePhysicalPath(String logicalPath) async {
    await _ensureAdapterBoundRoots();
    final normalized = _normalizeLogicalPath(logicalPath);
    for (final candidate in _readCandidatesResolved(normalized)) {
      final candidatePath = await candidate.resolveExistingPhysicalPath(
        adapter,
      );
      if (candidatePath != null) {
        return candidatePath;
      }
    }

    return null;
  }

  /// Opens the first readable handle that matches [logicalPath].
  Future<_LoveReadableHandle?> _openReadable(String logicalPath) async {
    final normalized = _normalizeLogicalPath(logicalPath);
    for (final candidate in await _readCandidates(normalized)) {
      final readable = await candidate.openReadable(adapter);
      if (readable != null) {
        return readable;
      }
    }

    return null;
  }

  /// Resolves [logicalPath] to a writable path under the save directory.
  ///
  /// Returns `null` when no save directory is configured or the normalized path
  /// would escape the writable root.
  Future<String?> resolveWritablePhysicalPath(String logicalPath) async {
    final saveDirectory = getSaveDirectory();
    if (saveDirectory.isEmpty) {
      return null;
    }

    final normalized = _normalizeLogicalPath(logicalPath);
    final platformRelative = normalized.isEmpty
        ? ''
        : path.joinAll(normalized.split('/'));
    final resolved = normalized.isEmpty
        ? saveDirectory
        : path.normalize(path.join(saveDirectory, platformRelative));

    if (resolved != saveDirectory && !path.isWithin(saveDirectory, resolved)) {
      return null;
    }

    return resolved;
  }

  /// Ensures that the writable save directory exists.
  Future<bool> _ensureSaveDirectoryExists() async {
    final saveDirectory = getSaveDirectory();
    if (saveDirectory.isEmpty) {
      return false;
    }

    return adapter.createDirectory(saveDirectory, recursive: true);
  }

  /// Returns whether any ancestor of [targetPath] inside the save directory is
  /// already a file.
  Future<bool> _hasFileAncestorInSaveDirectory(String targetPath) async {
    final saveDirectory = path.normalize(getSaveDirectory());
    var current = path.normalize(path.dirname(targetPath));

    while (current.isNotEmpty &&
        current != '.' &&
        current != saveDirectory &&
        path.isWithin(saveDirectory, current)) {
      if (await adapter.fileExists(current)) {
        return true;
      }

      final parent = path.dirname(current);
      if (parent == current) {
        break;
      }
      current = parent;
    }

    return false;
  }

  /// Returns the first readable file candidate for [logicalPath], if one
  /// exists.
  Future<_LoveResolvedPath?> _readableFileCandidate(String logicalPath) async {
    final normalized = _normalizeLogicalPath(logicalPath);
    for (final candidate in await _readCandidates(normalized)) {
      if (candidate.root.isVirtual) {
        final node = candidate.root.virtualNodeFor(candidate.relativePath);
        if (node != null && node.type == LoveFilesystemNodeType.file) {
          return candidate;
        }
        continue;
      }

      final candidatePath = candidate.physicalPath;
      if (candidatePath != null && await adapter.fileExists(candidatePath)) {
        return candidate;
      }
    }

    return null;
  }

  /// Reads bytes from [candidate] and throws LOVE-style errors when the read
  /// fails.
  Future<List<int>> _readCandidateBytesOrThrow(
    _LoveResolvedPath candidate, {
    required String logicalPath,
    required int size,
  }) async {
    if (candidate.root.isVirtual) {
      final node = candidate.root.virtualNodeFor(candidate.relativePath);
      if (node == null || node.type != LoveFilesystemNodeType.file) {
        throw StateError('Could not open file $logicalPath. Does not exist.');
      }

      final bytes = List<int>.from(node.bytes!);
      if (size >= 0 && bytes.length > size) {
        return bytes.sublist(0, size);
      }
      return bytes;
    }

    final candidatePath = candidate.physicalPath;
    if (candidatePath == null || !await adapter.fileExists(candidatePath)) {
      throw StateError('Could not open file $logicalPath. Does not exist.');
    }

    try {
      final bytes = await adapter.readFileBytes(candidatePath);
      if (bytes != null) {
        if (size >= 0 && bytes.length > size) {
          return bytes.sublist(0, size);
        }
        return bytes;
      }
    } catch (_) {
      // Fall through to the IODevice path below so we can surface a LOVE-style
      // open/read error instead of a raw adapter exception.
    }

    final device = await _openFilesystemDeviceOrThrow(
      adapter,
      candidatePath,
      'r',
      logicalPath: logicalPath,
    );
    try {
      final result = await device.read(size < 0 ? 'a' : '$size');
      if (!result.isSuccess) {
        throw StateError(result.error ?? 'Could not read from file.');
      }

      return _bytesFromIODeviceValue(result.value);
    } finally {
      await device.close();
    }
  }

  /// Reads all bytes from [physicalPath] when the host path exists and is
  /// readable.
  Future<List<int>?> _readPhysicalBytesIfPresent(String physicalPath) async {
    try {
      final bytes = await adapter.readFileBytes(physicalPath);
      if (bytes != null) {
        return bytes;
      }
    } catch (_) {
      // Fall through to the IODevice path below so archive mounts can still
      // succeed when direct byte reads are unavailable in the adapter.
    }

    late final IODevice device;
    try {
      device = await _openFilesystemDeviceOrThrow(
        adapter,
        physicalPath,
        'r',
        logicalPath: physicalPath,
      );
    } on StateError {
      return null;
    }

    try {
      final result = await device.read('a');
      if (!result.isSuccess) {
        return null;
      }
      return _bytesFromIODeviceValue(result.value);
    } finally {
      await device.close();
    }
  }

  /// Reads up to [size] bytes from [logicalPath] when it exists.
  ///
  /// Throws a [StateError] when the file exists but cannot be opened or read.
  Future<List<int>?> readAllBytesIfExistsOrThrow(
    String logicalPath, {
    int size = -1,
  }) async {
    final candidate = await _readableFileCandidate(logicalPath);
    if (candidate == null) {
      return null;
    }

    return _readCandidateBytesOrThrow(
      candidate,
      logicalPath: logicalPath,
      size: size,
    );
  }

  /// Reads up to [size] bytes from [logicalPath].
  ///
  /// Throws a [StateError] when the file does not exist or cannot be read.
  Future<List<int>> readAllBytesOrThrow(
    String logicalPath, {
    int size = -1,
  }) async {
    final bytes = await readAllBytesIfExistsOrThrow(logicalPath, size: size);
    if (bytes == null) {
      throw StateError('Could not open file $logicalPath. Does not exist.');
    }

    return bytes;
  }

  /// Loads the Lua chunk stored at [logicalPath] into [runtime].
  ///
  /// Throws a [LuaError] when the source cannot be parsed.
  Future<Value?> loadChunk(LuaRuntime runtime, String logicalPath) async {
    final bytes = await readAllBytesOrThrow(logicalPath);

    final result = await runtime.loadChunk(
      LuaChunkLoadRequest(
        source: runtime.constantStringValue(bytes),
        chunkName: '@$logicalPath',
      ),
    );
    if (!result.isSuccess) {
      throw LuaError(formatLoveFilesystemLoadSyntaxError(result.errorMessage));
    }
    return result.chunk;
  }
}
