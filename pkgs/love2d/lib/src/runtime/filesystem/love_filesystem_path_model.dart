part of 'love_filesystem_runtime.dart';

enum LoveFilesystemNodeType { file, directory, symlink, other }

class LoveFilesystemInfo {
  const LoveFilesystemInfo({required this.type, this.size, this.modtime});

  final LoveFilesystemNodeType type;
  final int? size;
  final int? modtime;
}

class LoveFilesystemFileData {
  LoveFilesystemFileData({required List<int> bytes, required this.filename})
    : bytes = List<int>.unmodifiable(bytes);

  final List<int> bytes;
  final String filename;

  String get extension {
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }

    return filename.substring(dotIndex + 1);
  }

  int get size => bytes.length;

  LoveFilesystemFileData clone() {
    return LoveFilesystemFileData(bytes: bytes, filename: filename);
  }
}

class _LoveFilesystemVirtualNode {
  _LoveFilesystemVirtualNode.file({required List<int> bytes, this.modtime})
    : type = LoveFilesystemNodeType.file,
      bytes = List<int>.unmodifiable(bytes);

  const _LoveFilesystemVirtualNode.directory({this.modtime})
    : type = LoveFilesystemNodeType.directory,
      bytes = null;

  final LoveFilesystemNodeType type;
  final List<int>? bytes;
  final DateTime? modtime;

  int? get size => bytes?.length;
}

class _LoveFilesystemRoot {
  _LoveFilesystemRoot.physical({
    required this.key,
    required this.physicalRoot,
    required this.mountpoint,
    required this.realDirectory,
  }) : virtualNodes = null;

  _LoveFilesystemRoot.virtual({
    required this.key,
    required this.mountpoint,
    required this.realDirectory,
    required Map<String, _LoveFilesystemVirtualNode> virtualNodes,
  }) : physicalRoot = null,
       virtualNodes = Map<String, _LoveFilesystemVirtualNode>.unmodifiable(
         virtualNodes,
       );

  final String key;
  final String? physicalRoot;
  final String mountpoint;
  final String? realDirectory;
  final Map<String, _LoveFilesystemVirtualNode>? virtualNodes;

  bool get isVirtual => virtualNodes != null;

  bool appliesTo(String logicalPath) {
    if (mountpoint.isEmpty) {
      return true;
    }

    return logicalPath == mountpoint || logicalPath.startsWith('$mountpoint/');
  }

  String relativePathFor(String logicalPath) {
    if (mountpoint.isEmpty) {
      return logicalPath;
    }

    if (logicalPath == mountpoint) {
      return '';
    }

    return logicalPath.substring(mountpoint.length + 1);
  }

  String? physicalPathFor(String relativePath) {
    final root = physicalRoot;
    if (root == null) {
      return null;
    }

    return _joinPhysicalPath(root, relativePath);
  }

  _LoveFilesystemVirtualNode? virtualNodeFor(String relativePath) {
    return virtualNodes?[relativePath];
  }

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

class _LoveResolvedPath {
  const _LoveResolvedPath({
    required this.root,
    required this.relativePath,
    required this.realDirectory,
    this.physicalPath,
  });

  final _LoveFilesystemRoot root;
  final String relativePath;
  final String? realDirectory;
  final String? physicalPath;

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

String _logicalToPlatformPath(String logicalPath) {
  if (logicalPath.isEmpty) {
    return '';
  }

  return path.joinAll(logicalPath.split('/'));
}

String _normalizeLogicalPath(String input) {
  final normalized = path.posix.normalize(input.replaceAll('\\', '/'));
  if (normalized == '.' || normalized == '/') {
    return '';
  }

  return normalized.replaceFirst(RegExp(r'^/+'), '');
}

String _joinPhysicalPath(String basePath, String relativePath) {
  if (relativePath.isEmpty) {
    return path.normalize(basePath);
  }

  return path.normalize(
    path.join(basePath, path.joinAll(relativePath.split('/'))),
  );
}

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

List<int> _bytesFromIODeviceValue(Object? value) {
  return switch (value) {
    null => const <int>[],
    LuaString(:final bytes) => List<int>.from(bytes),
    final String text => utf8.encode(text),
    final List<int> bytes => List<int>.from(bytes),
    _ => utf8.encode(value.toString()),
  };
}

int? _secondsSinceEpoch(DateTime? value) {
  if (value == null) {
    return null;
  }
  return value.millisecondsSinceEpoch ~/ 1000;
}
