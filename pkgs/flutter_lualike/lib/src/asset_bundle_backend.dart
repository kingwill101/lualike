/// A [FileSystemBackend] that delegates reads to a Flutter [AssetBundle].
///
/// All write/delete/rename operations are no-ops — asset bundles are
/// read-only at runtime.
///
/// ## Path resolution
/// Paths are resolved relative to [assetRoot]. For example, with
/// `assetRoot = 'assets'`, a request for `'plugins/my_plugin/plugin.lua'`
/// will try `'assets/plugins/my_plugin/plugin.lua'` in the bundle.
///
/// ## Caching
/// The asset manifest is loaded once and cached for the lifetime of the
/// backend. Call [prewarm] at startup to avoid a cold-start penalty on
/// the first file operation.
library;

import 'dart:async';

import 'package:flutter/services.dart' show AssetBundle, AssetManifest;
import 'package:lualike/lualike.dart' show FileSystemBackend;

/// A [FileSystemBackend] that serves files from a Flutter [AssetBundle].
///
/// Read-only. All mutating operations silently succeed without effect.
class AssetBundleFileSystemBackend implements FileSystemBackend {
  /// The underlying asset bundle (typically `rootBundle`).
  final AssetBundle bundle;

  /// The root prefix stripped from asset paths (e.g. `'assets'`).
  ///
  /// When non-null, this prefix is stripped from [assetRoot] before looking
  /// up files in the bundle. Paths passed to methods like [readFileAsString]
  /// should NOT include this prefix.
  final String? assetRoot;

  List<String>? _cachedManifest;

  /// Creates a backend backed by [bundle].
  ///
  /// [assetRoot] is an optional prefix that is prepended to all requested
  /// paths before looking them up in the bundle. For example, if assets are
  /// stored under `'assets/plugins/'`, set `assetRoot = 'assets/plugins'`
  /// so that callers can request `'my_plugin/plugin.lua'` directly.
  AssetBundleFileSystemBackend(this.bundle, {this.assetRoot});

  /// Pre-loads the asset manifest into the cache.
  ///
  /// Call this at app startup to avoid a cold-start delay on the first
  /// file operation.
  Future<void> prewarm() async {
    await _manifest();
  }

  Future<List<String>> _manifest() async {
    if (_cachedManifest != null) return _cachedManifest!;
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    _cachedManifest = manifest.listAssets().toList();
    return _cachedManifest!;
  }

  String _resolve(String path) {
    if (assetRoot != null && !path.startsWith('$assetRoot/')) {
      return '$assetRoot/$path';
    }
    return path;
  }

  @override
  Future<bool> fileExists(String path) async {
    try {
      final resolved = _resolve(path);
      final manifest = await _manifest();
      return manifest.any((a) => a == resolved);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> directoryExists(String path) async {
    try {
      final resolved = _resolve(path);
      final prefix = resolved.endsWith('/') ? resolved : '$resolved/';
      final manifest = await _manifest();
      return manifest.any((a) => a.startsWith(prefix));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> readFileAsString(String path) async {
    try {
      final resolved = _resolve(path);
      return await bundle.loadString(resolved);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<int>?> readFileAsBytes(String path) async {
    try {
      final resolved = _resolve(path);
      final data = await bundle.load(resolved);
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<DateTime?> getLastModified(String path) async => null;

  @override
  String? getCurrentDirectory() => assetRoot;

  @override
  Future<bool> createDirectory(String path, {bool recursive = true}) async =>
      false;

  @override
  Future<void> writeFile(String path, String content) async {
    // no-op: asset bundles are read-only
  }

  @override
  Future<List<String>> listDirectory(String path) async {
    try {
      final resolved = _resolve(path);
      final prefix = resolved.endsWith('/') ? resolved : '$resolved/';
      final manifest = await _manifest();
      return manifest.where((a) => a.startsWith(prefix)).toList();
    } catch (_) {
      return <String>[];
    }
  }

  @override
  Future<int?> fileSize(String path) async {
    try {
      final resolved = _resolve(path);
      final data = await bundle.load(resolved);
      return data.lengthInBytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> deleteFile(String path) async {
    // no-op: asset bundles are read-only
  }

  @override
  Future<bool> deletePath(String path, {bool recursive = true}) async => false;

  @override
  Future<void> renameFile(String oldPath, String newPath) async {
    // no-op: asset bundles are read-only
  }
}
