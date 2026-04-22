part of 'love_filesystem_runtime.dart';

extension _LoveFilesystemMountResolution on LoveFilesystemState {
  Future<String?> _resolveMountArchivePathWithoutRebind(String archive) async {
    final normalizedArchive = path.normalize(archive);

    if (_allowedMountPaths.contains(normalizedArchive)) {
      return normalizedArchive;
    }

    if (fused &&
        normalizedArchive == path.normalize(getSourceBaseDirectory())) {
      return normalizedArchive;
    }

    if (_isAbsoluteFilesystemPath(normalizedArchive)) {
      return null;
    }

    final realDirectory = await _getRealDirectoryResolved(normalizedArchive);
    if (realDirectory == null || realDirectory.isEmpty) {
      return null;
    }

    final resolvedArchive = path.normalize(
      path.join(realDirectory, _logicalToPlatformPath(normalizedArchive)),
    );

    if (await adapter.fileExists(resolvedArchive) ||
        await adapter.directoryExists(resolvedArchive)) {
      return resolvedArchive;
    }

    return null;
  }

  Future<String?> _getRealDirectoryResolved(String logicalPath) async {
    for (final candidate in _readCandidatesResolved(logicalPath)) {
      if (await candidate.exists(adapter)) {
        return candidate.realDirectory;
      }
    }

    final projectedRoot = _projectedRoot(logicalPath);
    return projectedRoot?.realDirectory;
  }

  bool _isInPhysicalSourceRoot(String physicalPath) {
    final sourceRoot = _currentPhysicalSourceRoot();
    if (sourceRoot == null || sourceRoot.isEmpty) {
      return false;
    }

    final normalizedSourceRoot = path.normalize(sourceRoot);
    final normalizedPhysicalPath = path.normalize(physicalPath);
    return normalizedPhysicalPath == normalizedSourceRoot ||
        path.isWithin(normalizedSourceRoot, normalizedPhysicalPath);
  }

  String? _currentPhysicalSourceRoot() {
    for (final root in _roots) {
      if (root.key == '__source__' && root.physicalRoot != null) {
        return root.physicalRoot;
      }
    }

    return null;
  }

  Future<List<_LoveResolvedPath>> _readCandidates(String logicalPath) async {
    await _ensureAdapterBoundRoots();
    return _readCandidatesResolved(logicalPath);
  }

  List<_LoveResolvedPath> _readCandidatesResolved(String logicalPath) {
    final candidates = <_LoveResolvedPath>[];

    for (final root in _roots) {
      if (!root.appliesTo(logicalPath)) {
        continue;
      }

      final relative = root.relativePathFor(logicalPath);
      final physical = root.physicalPathFor(relative);
      candidates.add(
        _LoveResolvedPath(
          root: root,
          relativePath: relative,
          physicalPath: physical,
          realDirectory: root.realDirectory,
        ),
      );
    }

    return candidates;
  }

  bool _isProjectedDirectory(String logicalPath) {
    if (logicalPath.isEmpty) {
      return _roots.any((root) => root.mountpoint.isNotEmpty);
    }

    return _roots.any(
      (root) =>
          root.mountpoint == logicalPath ||
          root.mountpoint.startsWith('$logicalPath/'),
    );
  }

  Set<String> _projectedEntries(String logicalPath) {
    final entries = <String>{};

    for (final root in _roots) {
      final mountpoint = root.mountpoint;
      if (mountpoint.isEmpty) {
        continue;
      }

      if (logicalPath.isEmpty) {
        entries.add(mountpoint.split('/').first);
        continue;
      }

      if (!mountpoint.startsWith('$logicalPath/')) {
        continue;
      }

      final remainder = mountpoint.substring(logicalPath.length + 1);
      if (remainder.isEmpty) {
        continue;
      }

      entries.add(remainder.split('/').first);
    }

    return entries;
  }

  _LoveFilesystemRoot? _projectedRoot(String logicalPath) {
    for (final root in _roots) {
      if (root.mountpoint == logicalPath ||
          root.mountpoint.startsWith('$logicalPath/')) {
        return root;
      }
    }

    return null;
  }
}
