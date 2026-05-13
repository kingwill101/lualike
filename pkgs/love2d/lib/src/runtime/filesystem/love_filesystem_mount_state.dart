part of 'love_filesystem_runtime.dart';

/// Recorded string-based mount request that can be reapplied later.
class _LoveFilesystemStringMountSpec {
  /// Creates a recorded string mount specification.
  _LoveFilesystemStringMountSpec({
    required this.archiveArgument,
    required this.mountpoint,
    required this.appendToPath,
    required this.key,
  });

  /// The original archive argument passed to the mount API.
  final String archiveArgument;

  /// The mountpoint used for this recorded mount.
  final String mountpoint;

  /// Whether this mount should be appended instead of prepended to the path.
  final bool appendToPath;

  /// The current root key associated with this mount.
  String key;

  /// The last known index of the mounted root in the root list.
  int? lastKnownIndex;
}

/// Internal mount-state bookkeeping helpers for [LoveFilesystemState].
extension _LoveFilesystemMountState on LoveFilesystemState {
  /// Replaces any mounted root sharing [root.key] and reinserts it by order.
  void _replaceRoot(_LoveFilesystemRoot root, {required bool append}) {
    _removeRoot(root.key);
    if (append) {
      _roots.add(root);
    } else {
      _roots.insert(0, root);
    }
  }

  /// Whether a mounted root with [key] exists.
  bool _hasRoot(String key) {
    return _roots.any((root) => root.key == key);
  }

  /// Removes the mounted root with [key] and any recorded string mount entry.
  bool _removeRoot(String key) {
    final before = _roots.length;
    _roots.removeWhere((root) => root.key == key);
    _stringMountSpecs.removeWhere((spec) => spec.key == key);
    return _roots.length != before;
  }

  /// Caches a clone of the resolved source [root] for [normalizedSource].
  void _cacheResolvedSourceRoot(
    String normalizedSource,
    _LoveFilesystemRoot root,
  ) {
    final cache = LoveFilesystemState._resolvedSourceRoots[_adapter] ??=
        <String, _LoveFilesystemRoot>{};
    cache[normalizedSource] = _cloneSourceRoot(root);
  }

  /// Returns a cloned cached source root for [normalizedSource], if present.
  _LoveFilesystemRoot? _resolvedSourceRoot(String normalizedSource) {
    final root =
        LoveFilesystemState._resolvedSourceRoots[_adapter]?[normalizedSource];
    if (root == null) {
      return null;
    }

    return _cloneSourceRoot(root);
  }

  /// Returns a `__source__` clone of [root] for source-path mounting.
  _LoveFilesystemRoot _cloneSourceRoot(_LoveFilesystemRoot root) {
    if (root.isVirtual) {
      return _LoveFilesystemRoot.virtual(
        key: '__source__',
        mountpoint: '',
        realDirectory: root.realDirectory,
        virtualNodes: root.virtualNodes!,
      );
    }

    return _LoveFilesystemRoot.physical(
      key: '__source__',
      physicalRoot: root.physicalRoot!,
      mountpoint: '',
      realDirectory: root.realDirectory ?? root.physicalRoot!,
    );
  }

  /// Returns the stable root key used for archive data mounts.
  String _dataMountKey(String archiveName) {
    return 'mount-data::${_normalizeDataMountArchiveName(archiveName)}';
  }

  /// Removes the data mount identified by [key] and detaches source tracking.
  bool _removeDataMountByKey(String key) {
    final removed = _removeRoot(key);
    if (!removed) {
      return false;
    }

    final sourceIdentity = _dataMountSources.remove(key);
    if (sourceIdentity != null) {
      _detachDataMountKey(sourceIdentity, key);
    }
    return true;
  }

  /// Detaches [key] from the tracked mount keys for [sourceIdentity].
  void _detachDataMountKey(Object sourceIdentity, String key) {
    final keys = _dataMountKeys[sourceIdentity];
    if (keys == null) {
      return;
    }

    keys.remove(key);
    if (keys.isEmpty) {
      _dataMountKeys.remove(sourceIdentity);
    }
  }

  /// Increments the open-handle count for [physicalPath].
  void _registerOpenPath(String physicalPath) {
    final normalized = path.normalize(physicalPath);
    _openPathCounts.update(normalized, (count) => count + 1, ifAbsent: () => 1);
  }

  /// Decrements the open-handle count for [physicalPath].
  void _unregisterOpenPath(String physicalPath) {
    final normalized = path.normalize(physicalPath);
    final count = _openPathCounts[normalized];
    if (count == null) {
      return;
    }

    if (count <= 1) {
      _openPathCounts.remove(normalized);
      return;
    }

    _openPathCounts[normalized] = count - 1;
  }

  /// Rebinds the special save root for the current adapter and identity state.
  void _rebindSaveRootForCurrentAdapter() {
    final saveRootIndex = _roots.indexWhere((root) => root.key == '__save__');
    if (!_identitySet) {
      if (saveRootIndex >= 0) {
        _roots.removeAt(saveRootIndex);
      }
      return;
    }

    if (saveRootIndex < 0) {
      final saveDirectory = getSaveDirectory();
      if (saveDirectory.isNotEmpty) {
        _replaceRoot(
          _LoveFilesystemRoot.physical(
            key: '__save__',
            physicalRoot: saveDirectory,
            mountpoint: '',
            realDirectory: saveDirectory,
          ),
          append: _saveRootAppendToPath,
        );
      }
      return;
    }

    final saveDirectory = getSaveDirectory();
    if (saveDirectory.isEmpty) {
      _roots.removeAt(saveRootIndex);
      return;
    }

    _roots[saveRootIndex] = _LoveFilesystemRoot.physical(
      key: '__save__',
      physicalRoot: saveDirectory,
      mountpoint: '',
      realDirectory: saveDirectory,
    );
  }

  /// Records a string-based mount so it can be replayed later.
  void _recordStringMount({
    required String archiveArgument,
    required String key,
    required String mountpoint,
    required bool appendToPath,
  }) {
    final existingIndex = _stringMountSpecs.indexWhere(
      (spec) => spec.archiveArgument == archiveArgument,
    );
    final recorded = _LoveFilesystemStringMountSpec(
      archiveArgument: archiveArgument,
      mountpoint: mountpoint,
      appendToPath: appendToPath,
      key: key,
    )..lastKnownIndex = _roots.indexWhere((root) => root.key == key);

    if (existingIndex >= 0) {
      _stringMountSpecs[existingIndex] = recorded;
      return;
    }

    _stringMountSpecs.add(recorded);
  }

  /// Returns the recorded string mount spec for [archiveArgument], if any.
  _LoveFilesystemStringMountSpec? _stringMountSpecForArchiveArgument(
    String archiveArgument,
  ) {
    for (final spec in _stringMountSpecs) {
      if (spec.archiveArgument == archiveArgument) {
        return spec;
      }
    }

    return null;
  }

  /// Returns the LOVE appdata directory name for the current platform.
  String _loveAppdataFolderName() {
    if (adapter.isWindows || adapter.isMacOS) {
      return 'LOVE';
    }

    if (adapter.isLinux) {
      return 'love';
    }

    return '.love';
  }

  /// Returns the physical root directory implied by [source].
  String _sourcePhysicalRoot(String source) {
    final extension = path.extension(source);
    if (extension.isEmpty) {
      return source;
    }

    return path.dirname(source);
  }

  /// Returns whether [input] looks like a mountable archive path.
  bool _looksLikeArchivePath(String input) {
    final normalized = input.toLowerCase();
    return normalized.endsWith('.love') ||
        normalized.endsWith('.zip') ||
        normalized.endsWith('.grp') ||
        normalized.endsWith('.pak') ||
        normalized.endsWith('.7z') ||
        normalized.endsWith('.iso') ||
        normalized.endsWith('.slb') ||
        normalized.endsWith('.tar') ||
        normalized.endsWith('.tgz') ||
        normalized.endsWith('.tar.gz') ||
        normalized.endsWith('.tbz') ||
        normalized.endsWith('.tbz2') ||
        normalized.endsWith('.tar.bz2') ||
        normalized.endsWith('.txz') ||
        normalized.endsWith('.tar.xz') ||
        normalized.endsWith('.wad') ||
        normalized.endsWith('.vdf') ||
        normalized.endsWith('.mvl') ||
        normalized.endsWith('.hog');
  }

  /// Returns whether [input] is an absolute filesystem path.
  bool _isAbsoluteFilesystemPath(String input) {
    final normalized = input.replaceAll('\\', '/');
    return path.posix.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
  }

  /// Returns whether [input] should be rejected as an unsafe archive path.
  bool _isUnsafeMountArchivePath(String input) {
    if (input.isEmpty || input == '/') {
      return true;
    }

    return input.replaceAll('\\', '/').contains('..');
  }

  /// Normalizes [archiveName] for data-mount bookkeeping.
  String _normalizeDataMountArchiveName(String archiveName) {
    if (archiveName.isEmpty) {
      return '';
    }

    final normalized = path.normalize(archiveName);
    return normalized == '.' ? archiveName : normalized;
  }
}
