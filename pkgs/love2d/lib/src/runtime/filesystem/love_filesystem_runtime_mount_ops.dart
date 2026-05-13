part of 'love_filesystem_runtime.dart';

/// Implements mount, query, and write operations on the filesystem runtime.
extension LoveFilesystemRuntimeMountOperations on LoveFilesystemState {
  /// Mounts [archive] at [mountpoint].
  ///
  /// Returns `false` when the archive path is unsafe, cannot be resolved, or
  /// cannot be decoded as a supported mount source.
  Future<bool> mount(
    String archive, {
    required String mountpoint,
    bool appendToPath = false,
  }) async {
    await _ensureAdapterBoundRoots();
    if (_isUnsafeMountArchivePath(archive)) {
      return false;
    }

    final normalizedArchiveArgument = path.normalize(archive);
    final normalizedMountpoint = _normalizeLogicalPath(mountpoint);
    final resolvedArchive = await _resolveMountArchivePathWithoutRebind(
      archive,
    );
    if (resolvedArchive == null) {
      return false;
    }

    if (!_isAbsoluteFilesystemPath(archive) &&
        _isInPhysicalSourceRoot(resolvedArchive)) {
      return false;
    }

    final key = 'mount::$resolvedArchive';
    if (_hasRoot(key)) {
      return true;
    }

    if (await adapter.directoryExists(resolvedArchive)) {
      _replaceRoot(
        _LoveFilesystemRoot.physical(
          key: key,
          physicalRoot: resolvedArchive,
          mountpoint: normalizedMountpoint,
          realDirectory: resolvedArchive,
        ),
        append: appendToPath,
      );
      _recordStringMount(
        archiveArgument: normalizedArchiveArgument,
        key: key,
        mountpoint: normalizedMountpoint,
        appendToPath: appendToPath,
      );
      return true;
    }

    if (!await adapter.fileExists(resolvedArchive)) {
      return false;
    }

    final bytes = await _readPhysicalBytesIfPresent(resolvedArchive);
    final nodes = bytes == null
        ? null
        : _decodeArchiveNodes(bytes, archiveName: resolvedArchive);
    if (nodes == null) {
      return false;
    }

    _replaceRoot(
      _LoveFilesystemRoot.virtual(
        key: key,
        mountpoint: normalizedMountpoint,
        realDirectory: resolvedArchive,
        virtualNodes: nodes,
      ),
      append: appendToPath,
    );
    _recordStringMount(
      archiveArgument: normalizedArchiveArgument,
      key: key,
      mountpoint: normalizedMountpoint,
      appendToPath: appendToPath,
    );
    return true;
  }

  /// Mounts archive [bytes] from an in-memory source at [mountpoint].
  Future<bool> mountArchiveBytes(
    List<int> bytes, {
    required Object sourceIdentity,
    required String archiveName,
    required String mountpoint,
    bool appendToPath = false,
  }) async {
    final nodes = _decodeArchiveNodes(bytes, archiveName: archiveName);
    if (nodes == null) {
      return false;
    }

    final normalizedMountpoint = _normalizeLogicalPath(mountpoint);
    final key = _dataMountKey(archiveName);
    if (_hasRoot(key)) {
      final previousSourceIdentity = _dataMountSources[key];
      if (previousSourceIdentity != null &&
          !identical(previousSourceIdentity, sourceIdentity)) {
        _detachDataMountKey(previousSourceIdentity, key);
      }

      final sourceKeys = _dataMountKeys[sourceIdentity] ??= <String>[];
      if (!sourceKeys.contains(key)) {
        sourceKeys.add(key);
      }
      _dataMountSources[key] = sourceIdentity;
      return true;
    }

    final sourceKeys = _dataMountKeys[sourceIdentity] ??= <String>[];
    if (!sourceKeys.contains(key)) {
      sourceKeys.add(key);
    }
    _dataMountSources[key] = sourceIdentity;

    _replaceRoot(
      _LoveFilesystemRoot.virtual(
        key: key,
        mountpoint: normalizedMountpoint,
        realDirectory: null,
        virtualNodes: nodes,
      ),
      append: appendToPath,
    );
    return true;
  }

  /// Unmounts a previously mounted [archive].
  Future<bool> unmount(String archive) async {
    await _ensureAdapterBoundRoots();
    if (_isUnsafeMountArchivePath(archive)) {
      return false;
    }

    final normalizedArchive = path.normalize(archive);
    if (_removeDataMountByKey(_dataMountKey(normalizedArchive))) {
      return true;
    }

    if (_removeRoot('mount::$normalizedArchive')) {
      return true;
    }

    final resolvedArchive = await _resolveMountArchivePathWithoutRebind(
      archive,
    );
    if (resolvedArchive != null &&
        _removeRoot('mount::${path.normalize(resolvedArchive)}')) {
      return true;
    }

    final spec = _stringMountSpecForArchiveArgument(normalizedArchive);
    if (spec != null) {
      _removeRoot(spec.key);
      _stringMountSpecs.remove(spec);
      return true;
    }

    return false;
  }

  /// Unmounts the first in-memory archive associated with [sourceIdentity].
  bool unmountData(Object sourceIdentity) {
    final keys = _dataMountKeys[sourceIdentity];
    if (keys == null || keys.isEmpty) {
      return false;
    }

    final key = (keys.toList()..sort()).first;
    return _removeDataMountByKey(key);
  }

  /// The real directory currently providing [logicalPath], if any.
  Future<String?> getRealDirectory(String logicalPath) async {
    await _ensureAdapterBoundRoots();
    return _getRealDirectoryResolved(_normalizeLogicalPath(logicalPath));
  }

  /// Returns filesystem information for [logicalPath], if it exists.
  Future<LoveFilesystemInfo?> getInfo(
    String logicalPath, {
    LoveFilesystemNodeType? filterType,
  }) async {
    await _ensureAdapterBoundRoots();
    final normalized = _normalizeLogicalPath(logicalPath);

    for (final candidate in _readCandidatesResolved(normalized)) {
      final info = await candidate.getInfo(adapter);
      if (info != null) {
        if (filterType == null || filterType == info.type) {
          return info;
        }
        return null;
      }
    }

    if (_isProjectedDirectory(normalized)) {
      final info = const LoveFilesystemInfo(
        type: LoveFilesystemNodeType.directory,
      );
      if (filterType == null || filterType == info.type) {
        return info;
      }
    }

    return null;
  }

  /// Lists the direct entries visible under [logicalPath].
  Future<List<String>> getDirectoryItems(String logicalPath) async {
    await _ensureAdapterBoundRoots();
    final normalized = _normalizeLogicalPath(logicalPath);
    final items = <String>{..._projectedEntries(normalized)};

    for (final candidate in _readCandidatesResolved(normalized)) {
      final entries = await candidate.listDirectory(adapter);
      if (entries == null) {
        continue;
      }
      for (final entry in entries) {
        items.add(entry);
      }
    }

    final sorted = items.toList()..sort();
    return sorted;
  }

  /// Creates a directory at [logicalPath] inside the writable save root.
  Future<bool> createDirectory(String logicalPath) async {
    final targetPath = await resolveWritablePhysicalPath(logicalPath);
    if (targetPath == null) {
      return false;
    }

    if (await _hasFileAncestorInSaveDirectory(targetPath) ||
        await adapter.fileExists(targetPath) ||
        await adapter.directoryExists(targetPath)) {
      return false;
    }

    return adapter.createDirectory(targetPath, recursive: true);
  }

  /// Removes a writable file or directory at [logicalPath].
  Future<bool> remove(String logicalPath) async {
    final targetPath = await resolveWritablePhysicalPath(logicalPath);
    if (targetPath == null) {
      return false;
    }

    if (_openPathCounts.containsKey(path.normalize(targetPath))) {
      return false;
    }

    return adapter.deletePath(targetPath, recursive: false);
  }
}
