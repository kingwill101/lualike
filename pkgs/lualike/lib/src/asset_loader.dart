import 'dart:io';

/// A loader for Lua bytecode compiled by the lualike build hook.
///
/// Loads compiled bytecode files from a `build/lua/` directory.
/// Files keep their original `.lua` names so they can be referenced
/// naturally in Flutter `assets:`.
class LuaAssetLoader {
  /// Creates a [LuaAssetLoader] rooted at [buildDir].
  ///
  /// If not provided, defaults to `build/lua/` relative to the current
  /// working directory.
  LuaAssetLoader({Uri? buildDir})
      : buildDir =
            buildDir ?? Directory.current.uri.resolve('build/lua/');

  /// The directory containing compiled bytecode files.
  final Uri buildDir;

  /// Loads the compiled bytecode for [assetName].
  ///
  /// [assetName] is the path of the original `.lua` file relative to its
  /// source directory (e.g. `'hello.lua'` or `'sub/module.lua'`).
  ///
  /// Returns the raw bytecode bytes, or `null` if the file does not exist.
  Future<List<int>?> loadBytecode(String assetName) async {
    final file = File.fromUri(buildDir.resolve(assetName));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  /// Returns the file path for a compiled asset.
  Uri assetPath(String assetName) => buildDir.resolve(assetName);
}
