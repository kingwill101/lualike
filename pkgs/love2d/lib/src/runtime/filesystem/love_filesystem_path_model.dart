part of 'love_filesystem_runtime.dart';

/// The node type returned by [LoveFilesystemInfo].
enum LoveFilesystemNodeType { file, directory, symlink, other }

/// Metadata about a path resolved through the LOVE filesystem.
class LoveFilesystemInfo {
  /// Creates path metadata.
  const LoveFilesystemInfo({required this.type, this.size, this.modtime});

  /// The resolved node type.
  final LoveFilesystemNodeType type;

  /// The file size in bytes, when the node is a file.
  final int? size;

  /// The modification time in seconds since the Unix epoch, if known.
  final int? modtime;
}

/// In-memory file data read through the LOVE filesystem.
class LoveFilesystemFileData {
  /// Creates file data for [filename].
  LoveFilesystemFileData({required List<int> bytes, required this.filename})
    : bytes = List<int>.unmodifiable(bytes);

  /// The immutable file contents.
  final List<int> bytes;

  /// The logical filename associated with [bytes].
  final String filename;

  /// The filename extension without a leading dot.
  String get extension {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }

    return filename.substring(dotIndex + 1);
  }

  /// The number of bytes stored in this file data object.
  int get size => bytes.length;

  /// Returns a defensive copy of this file data object.
  LoveFilesystemFileData clone() {
    return LoveFilesystemFileData(bytes: bytes, filename: filename);
  }
}

/// A virtual file or directory stored inside an in-memory mounted archive.
class _LoveFilesystemVirtualNode {
  /// Creates a virtual file node backed by immutable [bytes].
  _LoveFilesystemVirtualNode.file({required List<int> bytes, this.modtime})
    : type = LoveFilesystemNodeType.file,
      bytes = List<int>.unmodifiable(bytes);

  /// Creates a virtual directory node.
  const _LoveFilesystemVirtualNode.directory({this.modtime})
    : type = LoveFilesystemNodeType.directory,
      bytes = null;

  /// The type of filesystem node represented by this entry.
  final LoveFilesystemNodeType type;

  /// The file contents, when [type] is [LoveFilesystemNodeType.file].
  final List<int>? bytes;

  /// The archived modification time, if one was recorded.
  final DateTime? modtime;

  /// The file size in bytes, when this node represents a file.
  int? get size => bytes?.length;
}

/// A mounted root that contributes logical paths to the runtime.
class _LoveFilesystemRoot {
  /// Creates a root backed by a physical host directory.
  _LoveFilesystemRoot.physical({
    required this.key,
    required this.physicalRoot,
    required this.mountpoint,
    required this.realDirectory,
  }) : virtualNodes = null;

  /// Creates a root backed by in-memory virtual nodes.
  _LoveFilesystemRoot.virtual({
    required this.key,
    required this.mountpoint,
    required this.realDirectory,
    required Map<String, _LoveFilesystemVirtualNode> virtualNodes,
  }) : physicalRoot = null,
       virtualNodes = Map<String, _LoveFilesystemVirtualNode>.unmodifiable(
         virtualNodes,
       );

  /// The stable identifier used to track this root in runtime state.
  final String key;

  /// The physical host directory for this root, when it is file-backed.
  final String? physicalRoot;

  /// The logical mountpoint where this root appears inside the runtime.
  final String mountpoint;

  /// The host directory that should be reported for visible paths in this root.
  final String? realDirectory;

  /// The virtual nodes exposed by this root, when it is archive-backed.
  final Map<String, _LoveFilesystemVirtualNode>? virtualNodes;

  /// Whether this root is backed by [virtualNodes] instead of [physicalRoot].
  bool get isVirtual => virtualNodes != null;

  /// Returns whether [logicalPath] resolves inside this mounted root.
  bool appliesTo(String logicalPath) {
    if (mountpoint.isEmpty) {
      return true;
    }

    return logicalPath == mountpoint || logicalPath.startsWith('$mountpoint/');
  }

  /// Returns the path inside this root that corresponds to [logicalPath].
  String relativePathFor(String logicalPath) {
    if (mountpoint.isEmpty) {
      return logicalPath;
    }

    if (logicalPath == mountpoint) {
      return '';
    }

    return logicalPath.substring(mountpoint.length + 1);
  }

  /// Resolves [relativePath] to a host path when this root is physical.
  String? physicalPathFor(String relativePath) {
    final root = physicalRoot;
    if (root == null) {
      return null;
    }

    return _joinPhysicalPath(root, relativePath);
  }

  /// Returns the virtual node stored at [relativePath], if any.
  _LoveFilesystemVirtualNode? virtualNodeFor(String relativePath) {
    return virtualNodes?[relativePath];
  }

  /// Lists the direct child names visible under the virtual [relativePath].
  List<String> listVirtualDirectory(String relativePath) {
    final nodes = virtualNodes;
    if (nodes == null) {
      return const <String>[];
    }

    final prefix = relativePath.isEmpty ? '' : '$relativePath/';
    final items = <String>{};
    for (final key in nodes.keys) {
      if (key == relativePath || !key.startsWith(prefix)) {
        continue;
      }

      final remainder = key.substring(prefix.length);
      if (remainder.isEmpty) {
        continue;
      }

      items.add(remainder.split('/').first);
    }

    final sorted = items.toList()..sort();
    return sorted;
  }
}

/// A logical path resolved against a specific mounted root.
class _LoveResolvedPath {
  /// Creates a resolved path view for a root-relative path.
  const _LoveResolvedPath({
    required this.root,
    required this.relativePath,
    required this.realDirectory,
    this.physicalPath,
  });

  /// The root that produced this resolution.
  final _LoveFilesystemRoot root;

  /// The root-relative logical path.
  final String relativePath;

  /// The host directory that should be reported for this path, if any.
  final String? realDirectory;

  /// The resolved host path, when the root is physical.
  final String? physicalPath;

  /// Returns whether this resolved path currently exists.
  Future<bool> exists(LoveFilesystemAdapter adapter) async {
    if (root.isVirtual) {
      return root.virtualNodeFor(relativePath) != null;
    }

    final candidatePath = physicalPath;
    if (candidatePath == null) {
      return false;
    }

    return await adapter.fileExists(candidatePath) ||
        await adapter.directoryExists(candidatePath);
  }

  /// Returns filesystem metadata for this resolved path, if it exists.
  Future<LoveFilesystemInfo?> getInfo(LoveFilesystemAdapter adapter) async {
    if (root.isVirtual) {
      final node = root.virtualNodeFor(relativePath);
      if (node == null) {
        return null;
      }

      return LoveFilesystemInfo(
        type: node.type,
        size: node.size,
        modtime: _secondsSinceEpoch(node.modtime),
      );
    }

    final candidatePath = physicalPath;
    if (candidatePath == null) {
      return null;
    }

    if (await adapter.fileExists(candidatePath)) {
      return LoveFilesystemInfo(
        type: LoveFilesystemNodeType.file,
        size: await adapter.fileSize(candidatePath),
        modtime: _secondsSinceEpoch(await adapter.modified(candidatePath)),
      );
    }

    if (await adapter.directoryExists(candidatePath)) {
      return LoveFilesystemInfo(
        type: LoveFilesystemNodeType.directory,
        modtime: _secondsSinceEpoch(await adapter.modified(candidatePath)),
      );
    }

    return null;
  }

  /// Lists the direct entries for this resolved path when it is a directory.
  Future<List<String>?> listDirectory(LoveFilesystemAdapter adapter) async {
    if (root.isVirtual) {
      final node = root.virtualNodeFor(relativePath);
      if (node == null || node.type != LoveFilesystemNodeType.directory) {
        return null;
      }

      return root.listVirtualDirectory(relativePath);
    }

    final candidatePath = physicalPath;
    if (candidatePath == null ||
        !await adapter.directoryExists(candidatePath)) {
      return null;
    }

    final entries = await adapter.listDirectory(candidatePath);
    return entries.map(path.basename).toList(growable: false);
  }

  /// Reads file bytes from this resolved path when it is a file.
  Future<List<int>?> readFileBytes(LoveFilesystemAdapter adapter) async {
    if (root.isVirtual) {
      final node = root.virtualNodeFor(relativePath);
      if (node == null || node.type != LoveFilesystemNodeType.file) {
        return null;
      }

      return List<int>.from(node.bytes!);
    }

    final candidatePath = physicalPath;
    if (candidatePath == null) {
      return null;
    }

    return adapter.readFileBytes(candidatePath);
  }

  /// Resolves this path to an existing physical host path.
  Future<String?> resolveExistingPhysicalPath(
    LoveFilesystemAdapter adapter,
  ) async {
    final candidatePath = physicalPath;
    if (candidatePath == null) {
      return null;
    }

    if (await adapter.fileExists(candidatePath) ||
        await adapter.directoryExists(candidatePath)) {
      return candidatePath;
    }

    return null;
  }

  /// Opens this path for reading when it resolves to a file.
  Future<_LoveReadableHandle?> openReadable(
    LoveFilesystemAdapter adapter,
  ) async {
    if (root.isVirtual) {
      final node = root.virtualNodeFor(relativePath);
      if (node == null || node.type != LoveFilesystemNodeType.file) {
        return null;
      }

      return _LoveReadableHandle(
        device: LoveReadonlyBytesIODevice(node.bytes!),
      );
    }

    final candidatePath = physicalPath;
    if (candidatePath == null || !await adapter.fileExists(candidatePath)) {
      return null;
    }

    return _LoveReadableHandle(
      device: await _openFilesystemDeviceOrThrow(
        adapter,
        candidatePath,
        'r',
        logicalPath: relativePath,
      ),
      path: candidatePath,
    );
  }
}

/// Converts a normalized logical path to the current platform's separator
/// convention.
String _logicalToPlatformPath(String logicalPath) {
  if (logicalPath.isEmpty) {
    return '';
  }

  return path.joinAll(logicalPath.split('/'));
}

/// Normalizes a user-facing logical path to LOVE's canonical slash-separated
/// form.
String _normalizeLogicalPath(String input) {
  final normalized = path.posix.normalize(input.replaceAll('\\', '/'));
  if (normalized == '.' || normalized == '/') {
    return '';
  }

  return normalized.replaceFirst(RegExp(r'^/+'), '');
}

/// Joins [basePath] with [relativePath] and normalizes the result.
String _joinPhysicalPath(String basePath, String relativePath) {
  if (relativePath.isEmpty) {
    return path.normalize(basePath);
  }

  return path.normalize(
    path.join(basePath, path.joinAll(relativePath.split('/'))),
  );
}

/// Splits a semicolon-delimited package path template string.
List<String> _splitPathTemplates(String rawPath) {
  if (rawPath.isEmpty) {
    return <String>[];
  }

  final entries = rawPath.split(';');
  if (rawPath.endsWith(';')) {
    entries.removeLast();
  }
  return entries;
}

/// Converts an IO device read result to raw bytes.
List<int> _bytesFromIODeviceValue(Object? value) {
  return switch (value) {
    null => const <int>[],
    LuaString(:final bytes) => List<int>.from(bytes),
    final String text => utf8.encode(text),
    final List<int> bytes => List<int>.from(bytes),
    _ => utf8.encode(value.toString()),
  };
}

/// Converts [value] to whole seconds since the Unix epoch.
int? _secondsSinceEpoch(DateTime? value) {
  if (value == null) {
    return null;
  }
  return value.millisecondsSinceEpoch ~/ 1000;
}
