/// Flutter AssetBundle filesystem backend for lualike.
///
/// Provides transparent read-only file access for `dofile()`, `require()`,
/// `io.open()`, and module loading from Flutter's asset bundle.
///
/// ## Quick start
/// ```dart
/// import 'package:flutter_lualike/flutter_lualike.dart';
///
/// await useAssetBundle(rootBundle, assetRoot: 'assets');
///
/// // Now dofile('config.lua') resolves to assets/config.lua
/// ```
///
/// ## Composite backend (desktop)
/// On desktop, plugins may live on the local filesystem or in assets.
/// Use [CompositeFileSystemBackend] from `package:lualike/lualike.dart`
/// to check both:
/// ```dart
/// import 'package:lualike/lualike.dart';
/// import 'package:flutter_lualike/flutter_lualike.dart';
///
/// final assetBackend = AssetBundleFileSystemBackend(rootBundle);
/// final localBackend = PackageFileSystemBackend(LocalFileSystem());
/// setFileSystemBackend(CompositeFileSystemBackend([assetBackend, localBackend]));
/// ```
library;

export 'src/asset_bundle_backend.dart';
export 'src/asset_bundle_io_device.dart';
export 'src/config.dart';
