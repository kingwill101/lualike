part of 'love_filesystem_runtime.dart';

extension LoveFilesystemRuntimeConfig on LoveFilesystemState {
  void replaceAdapter(LoveFilesystemAdapter adapter) {
    _adapter = adapter;
    _rebindSaveRootForCurrentAdapter();
    _sourceRootDirty = _source.isNotEmpty;
    _stringMountRootsDirty = _stringMountSpecs.isNotEmpty;
  }

  void init([String? arg0]) {
    _initialized = true;
    _symlinksEnabled = true;
  }

  void setFused(bool fused) {
    if (_fusedSet) {
      return;
    }
    _fused = fused;
    _fusedSet = true;
  }

  void setAndroidSaveExternal(bool useExternal) {
    _androidSaveExternal = useExternal;
  }

  void setSymlinksEnabled(bool enabled) {
    _symlinksEnabled = enabled;
  }

  void allowMountingForPath(String physicalPath) {
    final normalized = path.normalize(physicalPath);
    if (normalized.isEmpty || normalized == '.') {
      return;
    }

    _allowedMountPaths.add(normalized);
  }

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

  void setRequirePath(String value) {
    _requirePath = _splitPathTemplates(value);
  }

  void setCRequirePath(String value) {
    _cRequirePath = _splitPathTemplates(value);
  }

  String getRequirePathString() => _requirePath.join(';');

  String getCRequirePathString() => _cRequirePath.join(';');

  String getWorkingDirectory() => adapter.workingDirectory ?? '';

  String getUserDirectory() => adapter.userDirectory ?? '';

  String getAppdataDirectory() => adapter.appdataDirectory ?? '';

  String getExecutablePath() => adapter.executablePath ?? '';

  String getSaveDirectory() {
    if (!_identitySet) {
      return '';
    }

    return _saveDirectoryForIdentity(_identity);
  }

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
