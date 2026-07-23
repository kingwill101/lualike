import 'dart:io';

/// Loads compiled Lua bytecode from the filesystem or the CLI bundle.
///
/// By default the loader checks the legacy build hook output in
/// `build/lua/`. It also probes the bundle-local `assets/` directory beside
/// the resolved executable, which is where `dart build cli` places data
/// assets.
class LuaAssetLoader {
  /// Creates a [LuaAssetLoader].
  ///
  /// [buildDir] defaults to `build/lua/` relative to the current directory.
  /// [bundleDir] defaults to the executable's parent directory.
  LuaAssetLoader({Uri? buildDir, Uri? bundleDir})
      : buildDir = buildDir ?? Directory.current.uri.resolve('build/lua/'),
        bundleDir = bundleDir ??
            Directory.fromUri(Uri.file(Platform.resolvedExecutable)).parent.uri;

  /// The legacy directory containing compiled bytecode files.
  final Uri buildDir;

  /// The directory containing the running executable.
  final Uri bundleDir;

  /// Loads the compiled bytecode for [assetName].
  ///
  /// [assetName] is the path of the original `.lua` file relative to its
  /// source directory (for example `hello.lua` or `sub/module.lua`).
  ///
  /// The loader checks the bundle-local `assets/` directory first, then the
  /// legacy `build/lua/` output.
  Future<List<int>?> loadBytecode(String assetName) async {
    for (final directory in <Uri>[
      bundleDir.resolve('assets/'),
      buildDir,
    ]) {
      final file = File.fromUri(directory.resolve(assetName));
      if (await file.exists()) {
        return file.readAsBytes();
      }
    }
    return null;
  }

  /// Returns the legacy filesystem path for a compiled asset.
  Uri assetPath(String assetName) => buildDir.resolve(assetName);

  /// Returns the bundle-local path for a compiled asset.
  Uri bundleAssetPath(String assetName) => bundleDir.resolve('assets/$assetName');
}
