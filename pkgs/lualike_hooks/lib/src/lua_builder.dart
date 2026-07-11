import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:lualike/lualike.dart' hide Logger;

/// A builder that compiles Lua scripts to bytecode at build time.
///
/// This builder implements the [Builder] interface from `package:hooks` and
/// can be used in a `hook/build.dart` to compile Lua scripts at build time.
///
/// Compiled bytecode is written to `<package_root>/build/lua/` so that
/// consumers can reference the files directly (e.g. via `flutter: assets:`
/// in Flutter or via file path in Dart CLI).
///
/// Example:
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:lualike_hooks/lualike_hooks.dart';
///
/// void main(List<String> args) async {
///   await build(args, (input, output) async {
///     final builder = LuaBuilder(
///       sources: ['assets/lua/'],
///     );
///     await builder.run(input: input, output: output);
///   });
/// }
/// ```
final class LuaBuilder implements Builder {
  /// Creates a [LuaBuilder] with the supplied configuration.
  const LuaBuilder({
    required this.sources,
    this.outputDirName = 'lua',
    this.enableConstantFolding = true,
    this.enablePeephole = true,
    this.stripDebug = false,
  });

  /// The directories containing Lua source files to compile.
  ///
  /// Each path is relative to the package root. For example:
  /// ```dart
  /// sources: ['assets/lua/', 'lib/scripts/']
  /// ```
  final List<String> sources;

  /// The name of the output directory under `build/`.
  ///
  /// For example, if `outputDirName` is `'lua'`, compiled bytecode will be
  /// written to `<package_root>/build/lua/`. Defaults to `'lua'`.
  final String outputDirName;

  /// Whether to enable constant folding during compilation.
  ///
  /// When enabled, constant expressions are evaluated at compile time.
  /// Defaults to `true`.
  final bool enableConstantFolding;

  /// Whether to enable peephole optimization during compilation.
  ///
  /// When enabled, redundant instructions are removed from the bytecode.
  /// Defaults to `true`.
  final bool enablePeephole;

  /// Whether to strip debug information from the compiled bytecode.
  ///
  /// When enabled, the resulting bytecode is smaller but stack traces will
  /// not contain line numbers. Defaults to `false`.
  final bool stripDebug;

  /// Runs the Lua compilation process.
  ///
  /// Scans the [sources] directories for `.lua` files, compiles them to
  /// bytecode, and writes the compiled files to `build/<outputDirName>/`.
  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    final packageRoot = input.packageRoot;

    // Write compiled bytecode into build/<outputDirName>/ within the package.
    // This is the "write to build/" pattern used by flutter_scene and others
    // until dartDataAssets is enabled by default.
    final buildDir = packageRoot.resolve('build/$outputDirName/');

    for (final sourcePath in sources) {
      final sourceDir = packageRoot.resolve(sourcePath);

      if (!await Directory.fromUri(sourceDir).exists()) {
        logger?.fine('Source directory not found: $sourcePath');
        continue;
      }

      await _compileDirectory(
        sourceDir: sourceDir,
        buildDir: buildDir,
        sourcePath: sourcePath,
        logger: logger,
      );
    }
  }

  Future<void> _compileDirectory({
    required Uri sourceDir,
    required Uri buildDir,
    required String sourcePath,
    Logger? logger,
  }) async {
    // Ensure the build output directory exists.
    await Directory.fromUri(buildDir).create(recursive: true);

    await for (final entity
        in Directory.fromUri(sourceDir).list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.lua')) {
        continue;
      }

      // Preserve directory structure relative to the source directory.
      final relativePath = entity.path.substring(sourceDir.path.length);
      // Remove leading /
      final assetName = relativePath.startsWith('/')
          ? relativePath.substring(1)
          : relativePath;

      logger?.fine('Compiling: ${entity.path}');

      final source = await entity.readAsString();
      final bytecode = _compileToBytecode(source, assetName);

      final outputPath = buildDir.resolve(assetName);
      await Directory.fromUri(outputPath.resolve('..'))
          .create(recursive: true);
      await File.fromUri(outputPath).writeAsBytes(bytecode);

      logger?.info('Compiled: $assetName (${bytecode.length} bytes)');
    }
  }

  /// Compiles Lua source to bytecode.
  List<int> _compileToBytecode(String source, String name) {
    final program = parse(source, url: name);

    final compiler = CompilePipeline(
      config: CompilePipelineConfig(
        target: CompileBackend.luaBytecode,
        enableConstantFolding: enableConstantFolding,
        enablePeephole: enablePeephole,
        stripDebug: stripDebug,
      ),
    );

    final artifact = compiler.compile(program) as LuaBytecodeArtifact;
    return artifact.serializedBytes;
  }
}
