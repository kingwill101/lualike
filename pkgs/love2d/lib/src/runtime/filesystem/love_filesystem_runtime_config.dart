part of 'love_filesystem_runtime.dart';

/// Configures adapter, source, save-root, and require-path state.
extension LoveFilesystemRuntimeConfig on LoveFilesystemState {
  /// Replaces the active host filesystem [adapter] and marks derived roots dirty.
  void replaceAdapter(LoveFilesystemAdapter adapter) {
    _adapter = adapter;
    _rebindSaveRootForCurrentAdapter();
    _sourceRootDirty = _source.isNotEmpty;
    _stringMountRootsDirty = _stringMountSpecs.isNotEmpty;
  }

  /// Initializes filesystem runtime defaults.
  void init([String? arg0]) {
    _initialized = true;
    _symlinksEnabled = true;
  }

  /// Sets whether the game should be treated as fused.
  ///
  /// LOVE only honors the first fused assignment, so later calls are ignored.
  void setFused(bool fused) {
    if (_fusedSet) {
      return;
    }
    _fused = fused;
    _fusedSet = true;
  }

  /// Sets whether Android save data should use external storage.
  void setAndroidSaveExternal(bool useExternal) {
    _androidSaveExternal = useExternal;
  }

  /// Sets whether symlink handling is enabled.
  void setSymlinksEnabled(bool enabled) {
    _symlinksEnabled = enabled;
  }

  /// Allows mounting a specific physical [physicalPath] directly.
  void allowMountingForPath(String physicalPath) {
    final normalized = path.normalize(physicalPath);
    if (normalized.isEmpty || normalized == '.') {
      return;
    }

    _allowedMountPaths.add(normalized);
  }

  /// Sets the save identity to [value] and binds the save root.
  bool setIdentity(String value, {bool appendToPath = false}) {
    final saveDirectory = _saveDirectoryForIdentity(value);
    if (saveDirectory.isEmpty) {
      return false;
    }

    _identity = value;
    _identitySet = true;
    _saveRootAppendToPath = appendToPath;
    _replaceRoot(
      _LoveFilesystemRoot.physical(
        key: '__save__',
        physicalRoot: saveDirectory,
        mountpoint: '',
        realDirectory: saveDirectory,
      ),
      append: appendToPath,
    );
    return true;
  }

  /// Sets the source path to [value] without probing the host filesystem.
  bool setSource(String value) {
    if (_source.isNotEmpty) {
      return false;
    }

    final normalized = path.normalize(value);
    final cachedRoot = _resolvedSourceRoot(normalized);
    if (cachedRoot != null) {
      _source = normalized;
      _sourceSetFromFilesystem = false;
      _sourceRootDirty = false;
      _replaceRoot(cachedRoot, append: true);
      return true;
    }

    if (_looksLikeArchivePath(normalized)) {
      return false;
    }

    _source = normalized;
    _sourceSetFromFilesystem = false;
    _sourceRootDirty = false;
    final physicalRoot = _sourcePhysicalRoot(normalized);
    _replaceRoot(
      _LoveFilesystemRoot.physical(
        key: '__source__',
        physicalRoot: physicalRoot,
        mountpoint: '',
        realDirectory: physicalRoot,
      ),
      append: true,
    );
    return true;
  }

  /// Sets the source path to [value] after probing the host filesystem.
  Future<bool> setSourceFromFilesystem(String value) async {
    if (_source.isNotEmpty) {
      return false;
    }

    final normalized = path.normalize(value);
    final root = await _sourceRootFromFilesystem(normalized);
    if (root == null) {
      return false;
    }

    if (root.isVirtual) {
      _cacheResolvedSourceRoot(normalized, root);
    }

    _source = normalized;
    _sourceSetFromFilesystem = true;
    _sourceRootDirty = false;
    _replaceRoot(root, append: true);
    return true;
  }

  /// Sets the semicolon-delimited Lua require path template list.
  void setRequirePath(String value) {
    _requirePath = _splitPathTemplates(value);
  }

  /// Sets the semicolon-delimited C require path template list.
  void setCRequirePath(String value) {
    _cRequirePath = _splitPathTemplates(value);
  }

  /// The current Lua require path list encoded as a semicolon-delimited string.
  String getRequirePathString() => _requirePath.join(';');

  /// The current C require path list encoded as a semicolon-delimited string.
  String getCRequirePathString() => _cRequirePath.join(';');

  /// The current working directory exposed by the host adapter.
  String getWorkingDirectory() => adapter.workingDirectory ?? '';

  /// The current user directory exposed by the host adapter.
  String getUserDirectory() => adapter.userDirectory ?? '';

  /// The app data directory exposed by the host adapter.
  String getAppdataDirectory() => adapter.appdataDirectory ?? '';

  /// The executable path exposed by the host adapter.
  String getExecutablePath() => adapter.executablePath ?? '';

  /// The resolved save directory for the current identity, if one exists.
  String getSaveDirectory() {
    if (!_identitySet) {
      return '';
    }

    return _saveDirectoryForIdentity(_identity);
  }

  /// Resolves the physical save directory used for [identity].
  String _saveDirectoryForIdentity(String identity) {
    final baseDirectory = getAppdataDirectory();
    if (baseDirectory.isEmpty) {
      return '';
    }

    final folder = _loveAppdataFolderName();
    if (_fused) {
      return path.normalize(path.join(baseDirectory, identity));
    }

    return path.normalize(path.join(baseDirectory, folder, identity));
  }

  /// The base directory portion of the configured source path.
  String getSourceBaseDirectory() {
    if (_source.isEmpty) {
      return '';
    }

    final normalizedSource = _source.replaceAll('\\', '/');
    final trimmedSource =
        normalizedSource.length > 1 && normalizedSource.endsWith('/')
        ? normalizedSource.substring(0, normalizedSource.length - 1)
        : normalizedSource;
    final lastSeparator = trimmedSource.lastIndexOf('/');
    if (lastSeparator < 0) {
      return '';
    }
    if (lastSeparator == 0) {
      return '/';
    }

    return trimmedSource.substring(0, lastSeparator);
  }

  /// Builds a source root from a filesystem path when it exists.
  Future<_LoveFilesystemRoot?> _sourceRootFromFilesystem(
    String normalizedSource,
  ) async {
    if (await adapter.directoryExists(normalizedSource)) {
      return _LoveFilesystemRoot.physical(
        key: '__source__',
        physicalRoot: normalizedSource,
        mountpoint: '',
        realDirectory: normalizedSource,
      );
    }

    if (await adapter.fileExists(normalizedSource)) {
      final bytes = await _readPhysicalBytesIfPresent(normalizedSource);
      if (bytes != null) {
        final nodes = _decodeArchiveNodes(bytes, archiveName: normalizedSource);
        if (nodes != null) {
          return _LoveFilesystemRoot.virtual(
            key: '__source__',
            mountpoint: '',
            realDirectory: normalizedSource,
            virtualNodes: nodes,
          );
        }
      }

      if (_looksLikeArchivePath(normalizedSource)) {
        return null;
      }

      return null;
    }

    return null;
  }
}
