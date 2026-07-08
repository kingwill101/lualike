/// One-call setup helpers for wiring the AssetBundle backend into lualike.
///
/// {@category Configuration}
library;

import 'package:flutter/services.dart' show AssetBundle;
import 'package:lualike/lualike.dart'
    show FileSystemProvider, setFileSystemBackend, setFileSystemProvider;

import 'asset_bundle_backend.dart';
import 'asset_bundle_io_device.dart';

/// Configures the current lualike runtime to use [bundle] as its filesystem
/// backend for all read-only file operations.
///
/// Wires two integration points:
///   1. [setFileSystemBackend] — so metadata operations (`dofile()`, `require()`,
///      module loading) resolve files from [bundle].
///   2. [setFileSystemProvider] — so `io.open()` creates [AssetBundleIODevice]
///      instances backed by [bundle].
///
/// ## Usage
/// ```dart
/// import 'package:flutter_lualike/flutter_lualike.dart';
///
/// await useAssetBundle(rootBundle, assetRoot: 'assets/plugins');
/// ```
///
/// ## Desktop with local filesystem fallback
/// ```dart
/// import 'package:file/local.dart';
/// import 'package:file_lualike/file_lualike.dart';
/// import 'package:flutter_lualike/flutter_lualike.dart';
///
/// final backend = CompositeFileSystemBackend([
///   AssetBundleFileSystemBackend(rootBundle, assetRoot: 'assets/plugins'),
///   PackageFileSystemBackend(LocalFileSystem()),
/// ]);
/// setFileSystemBackend(backend);
/// ```
Future<void> useAssetBundle(
  AssetBundle bundle, {
  String? assetRoot,
  FileSystemProvider? provider,
}) async {
  final target = provider ?? FileSystemProvider();

  target.setIODeviceFactory(
    (path, mode) => AssetBundleIODevice.open(bundle, path, mode),
    providerName: 'AssetBundle',
  );

  setFileSystemProvider(target);

  setFileSystemBackend(
    AssetBundleFileSystemBackend(bundle, assetRoot: assetRoot),
  );
}
