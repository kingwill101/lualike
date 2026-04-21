// ignore_for_file: implementation_imports

import 'package:flutter/services.dart';
import 'package:lualike/src/io/io_device.dart';
import 'package:path/path.dart' as p;

import 'love_readonly_bytes_io_device.dart';
import 'love_filesystem_runtime.dart';

class LoveAssetBundleFilesystemAdapter implements LoveFilesystemAdapter {
  LoveAssetBundleFilesystemAdapter({
    required AssetBundle bundle,
    required Iterable<String> assetKeys,
    LoveFilesystemAdapter? fallback,
  }) : _bundle = bundle,
       _fallback = fallback ?? const _LoveNoopFilesystemAdapter(),
       _assetKeys = assetKeys
           .map(_normalizeAssetPath)
           .where((key) => key.isNotEmpty && key != '.')
           .toSet() {
    for (final assetKey in _assetKeys) {
      _indexAsset(assetKey);
    }
  }

  static Future<LoveAssetBundleFilesystemAdapter> load({
    AssetBundle? bundle,
    LoveFilesystemAdapter? fallback,
  }) async {
    final resolvedBundle = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(resolvedBundle);
    return LoveAssetBundleFilesystemAdapter(
      bundle: resolvedBundle,
      assetKeys: manifest.listAssets(),
      fallback: fallback,
    );
  }

  final AssetBundle _bundle;
  final LoveFilesystemAdapter _fallback;
  final Set<String> _assetKeys;
  final Set<String> _directories = <String>{''};
  final Map<String, Set<String>> _directoryEntries = <String, Set<String>>{
    '': <String>{},
  };

  bool get hasExplicitFallback => _fallback is! _LoveNoopFilesystemAdapter;

  LoveAssetBundleFilesystemAdapter withFallback(
    LoveFilesystemAdapter fallback,
  ) {
    return LoveAssetBundleFilesystemAdapter(
      bundle: _bundle,
      assetKeys: _assetKeys,
      fallback: fallback,
    );
  }

  @override
  String? get workingDirectory => _fallback.workingDirectory;

  @override
  String? get userDirectory => _fallback.userDirectory;

  @override
  String? get appdataDirectory => _fallback.appdataDirectory;

  @override
  String? get executablePath => _fallback.executablePath;

  @override
  bool get isWindows => _fallback.isWindows;

  @override
  bool get isLinux => _fallback.isLinux;

  @override
  bool get isMacOS => _fallback.isMacOS;

  @override
  Future<IODevice> openFile(String path, String mode) async {
    final normalized = _normalizeAssetPath(path);
    if (_assetKeys.contains(normalized) && !_isWriteMode(mode)) {
      final bytes = await _loadAssetBytes(normalized);
      if (bytes != null) {
        return LoveReadonlyBytesIODevice(bytes);
      }
    }

    if (!_shouldUseFallback(path)) {
      throw UnsupportedError(
        'No bundled asset exists for "$path" (mode "$mode").',
      );
    }

    return _fallback.openFile(path, mode);
  }

  @override
  Future<bool> fileExists(String path) async {
    final normalized = _normalizeAssetPath(path);
    if (_assetKeys.contains(normalized)) {
      return true;
    }

    if (!_shouldUseFallback(path)) {
      return false;
    }

    return _fallback.fileExists(path);
  }

  @override
  Future<bool> directoryExists(String path) async {
    final normalized = _normalizeAssetPath(path);
    if (_directories.contains(normalized)) {
      return true;
    }

    if (!_shouldUseFallback(path)) {
      return false;
    }

    return _fallback.directoryExists(path);
  }

  @override
  Future<List<int>?> readFileBytes(String path) async {
    final normalized = _normalizeAssetPath(path);
    final bytes = await _loadAssetBytes(normalized);
    if (bytes != null) {
      return bytes;
    }

    if (!_shouldUseFallback(path)) {
      return null;
    }

    return _fallback.readFileBytes(path);
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    final normalized = _normalizeAssetPath(path);
    final items = <String>{...?_directoryEntries[normalized]};
    if (_shouldUseFallback(path)) {
      items.addAll(await _fallback.listDirectory(path));
    }
    final result = items.toList()..sort();
    return result;
  }

  @override
  Future<DateTime?> modified(String path) async {
    final normalized = _normalizeAssetPath(path);
    if (_assetKeys.contains(normalized)) {
      return null;
    }

    if (!_shouldUseFallback(path)) {
      return null;
    }

    return _fallback.modified(path);
  }

  @override
  Future<int?> fileSize(String path) async {
    final normalized = _normalizeAssetPath(path);
    final bytes = await _loadAssetBytes(normalized);
    if (bytes != null) {
      return bytes.length;
    }

    if (!_shouldUseFallback(path)) {
      return null;
    }

    return _fallback.fileSize(path);
  }

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) {
    return _fallback.createDirectory(path, recursive: recursive);
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) {
    return _fallback.deletePath(path, recursive: recursive);
  }

  void _indexAsset(String assetKey) {
    final segments = p.posix.split(assetKey);
    if (segments.isEmpty) {
      return;
    }

    var parent = '';
    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      _directoryEntries.putIfAbsent(parent, () => <String>{}).add(segment);
      final candidate = parent.isEmpty
          ? segment
          : p.posix.join(parent, segment);
      if (index < segments.length - 1) {
        _directories.add(candidate);
        _directoryEntries.putIfAbsent(candidate, () => <String>{});
      }
      parent = candidate;
    }
  }

  Future<List<int>?> _loadAssetBytes(String assetKey) async {
    if (!_assetKeys.contains(assetKey)) {
      return null;
    }

    try {
      final data = await _bundle.load(assetKey);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (_) {
      return null;
    }
  }

  static String _normalizeAssetPath(String value) {
    final normalized = p.posix.normalize(value.replaceAll('\\', '/'));
    return normalized == '.' ? '' : normalized;
  }

  static bool _isWriteMode(String mode) {
    return mode.contains('w') || mode.contains('a') || mode.contains('+');
  }

  static bool _shouldUseFallback(String path) {
    final normalized = _normalizeAssetPath(path);
    return p.posix.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized);
  }
}

class _LoveNoopFilesystemAdapter implements LoveFilesystemAdapter {
  const _LoveNoopFilesystemAdapter();

  @override
  String? get appdataDirectory => null;

  @override
  String? get executablePath => null;

  @override
  String? get userDirectory => null;

  @override
  String? get workingDirectory => null;

  @override
  bool get isWindows => false;

  @override
  bool get isLinux => false;

  @override
  bool get isMacOS => false;

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async =>
      false;

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async => false;

  @override
  Future<bool> directoryExists(String path) async => false;

  @override
  Future<bool> fileExists(String path) async => false;

  @override
  Future<int?> fileSize(String path) async => null;

  @override
  Future<List<String>> listDirectory(String path) async => const <String>[];

  @override
  Future<DateTime?> modified(String path) async => null;

  @override
  Future<IODevice> openFile(String path, String mode) async {
    throw UnsupportedError(
      'No fallback filesystem is configured for "$path" (mode "$mode").',
    );
  }

  @override
  Future<List<int>?> readFileBytes(String path) async => null;
}
