part of 'love_filesystem_runtime.dart';

/// Rebinds adapter-dependent mount roots after filesystem configuration changes.
extension _LoveFilesystemMountRebinding on LoveFilesystemState {
  /// Ensures adapter-dependent source and string-mount roots are up to date.
  Future<void> _ensureAdapterBoundRoots() async {
    await _ensureSourceRootForCurrentAdapter();
    await _ensureStringMountRootsForCurrentAdapter();
  }

  /// Ensures the current source root has been rebound for the active adapter.
  Future<void> _ensureSourceRootForCurrentAdapter() async {
    final inFlight = _sourceRootRebindFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    if (!_sourceRootDirty) {
      return;
    }

    final future = _rebindSourceRootForCurrentAdapter();
    _sourceRootRebindFuture = future;
    try {
      await future;
    } finally {
      if (identical(_sourceRootRebindFuture, future)) {
        _sourceRootRebindFuture = null;
      }
    }
  }

  /// Rebuilds the mounted `__source__` root for the active adapter.
  Future<void> _rebindSourceRootForCurrentAdapter() async {
    _sourceRootDirty = false;

    if (_source.isEmpty) {
      _removeRoot('__source__');
      return;
    }

    final normalizedSource = path.normalize(_source);
    final root = await _sourceRootForCurrentAdapter(normalizedSource);
    if (root == null) {
      _removeRoot('__source__');
      return;
    }

    if (root.isVirtual) {
      _cacheResolvedSourceRoot(normalizedSource, root);
    }

    _replaceRoot(root, append: true);
  }

  /// Resolves the correct `__source__` root for the active adapter.
  Future<_LoveFilesystemRoot?> _sourceRootForCurrentAdapter(
    String normalizedSource,
  ) async {
    if (_sourceSetFromFilesystem || _looksLikeArchivePath(normalizedSource)) {
      return _sourceRootFromFilesystem(normalizedSource);
    }

    final cachedRoot = _resolvedSourceRoot(normalizedSource);
    if (cachedRoot != null) {
      return cachedRoot;
    }

    final physicalRoot = _sourcePhysicalRoot(normalizedSource);
    return _LoveFilesystemRoot.physical(
      key: '__source__',
      physicalRoot: physicalRoot,
      mountpoint: '',
      realDirectory: physicalRoot,
    );
  }

  /// Ensures recorded string mounts have been rebound for the active adapter.
  Future<void> _ensureStringMountRootsForCurrentAdapter() async {
    final inFlight = _stringMountRootRebindFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }

    if (!_stringMountRootsDirty) {
      return;
    }

    final future = _rebindStringMountRootsForCurrentAdapter();
    _stringMountRootRebindFuture = future;
    try {
      await future;
    } finally {
      if (identical(_stringMountRootRebindFuture, future)) {
        _stringMountRootRebindFuture = null;
      }
    }
  }

  /// Rebuilds every recorded string mount for the active adapter.
  Future<void> _rebindStringMountRootsForCurrentAdapter() async {
    _stringMountRootsDirty = false;

    for (final spec in _stringMountSpecs) {
      final currentIndex = _roots.indexWhere((root) => root.key == spec.key);
      if (currentIndex >= 0) {
        spec.lastKnownIndex = currentIndex;
      }
    }

    final specs = _stringMountSpecs.toList()
      ..sort((a, b) {
        final aIndex = a.lastKnownIndex ?? 1 << 30;
        final bIndex = b.lastKnownIndex ?? 1 << 30;
        return aIndex.compareTo(bIndex);
      });

    for (final spec in specs) {
      final previousIndex = _roots.indexWhere((root) => root.key == spec.key);
      final rebound = await _stringMountRootForCurrentAdapter(spec);
      if (rebound == null) {
        if (previousIndex >= 0) {
          _roots.removeAt(previousIndex);
        }
        continue;
      }

      spec.key = rebound.key;
      if (previousIndex >= 0) {
        _roots[previousIndex] = rebound;
        spec.lastKnownIndex = previousIndex;
        continue;
      }

      final insertIndex = _stringMountRestoreIndex(spec);
      _roots.insert(insertIndex, rebound);
      spec.lastKnownIndex = insertIndex;
    }
  }

  /// Rebuilds the mounted root described by [spec] for the active adapter.
  Future<_LoveFilesystemRoot?> _stringMountRootForCurrentAdapter(
    _LoveFilesystemStringMountSpec spec,
  ) async {
    final resolvedArchive = await _resolveMountArchivePathWithoutRebind(
      spec.archiveArgument,
    );
    if (resolvedArchive == null) {
      return null;
    }

    if (!_isAbsoluteFilesystemPath(spec.archiveArgument) &&
        _isInPhysicalSourceRoot(resolvedArchive)) {
      return null;
    }

    final key = 'mount::$resolvedArchive';
    if (await adapter.directoryExists(resolvedArchive)) {
      return _LoveFilesystemRoot.physical(
        key: key,
        physicalRoot: resolvedArchive,
        mountpoint: spec.mountpoint,
        realDirectory: resolvedArchive,
      );
    }

    if (!await adapter.fileExists(resolvedArchive)) {
      return null;
    }

    final bytes = await _readPhysicalBytesIfPresent(resolvedArchive);
    final nodes = bytes == null
        ? null
        : _decodeArchiveNodes(bytes, archiveName: resolvedArchive);
    if (nodes == null) {
      return null;
    }

    return _LoveFilesystemRoot.virtual(
      key: key,
      mountpoint: spec.mountpoint,
      realDirectory: resolvedArchive,
      virtualNodes: nodes,
    );
  }

  /// The insertion index used when replaying a recorded string mount.
  int _stringMountRestoreIndex(_LoveFilesystemStringMountSpec spec) {
    final index = spec.lastKnownIndex;
    if (index == null) {
      return spec.appendToPath ? _roots.length : 0;
    }

    if (index < 0) {
      return 0;
    }

    if (index > _roots.length) {
      return _roots.length;
    }

    return index;
  }
}
