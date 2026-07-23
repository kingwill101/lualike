import 'dart:io';

import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:lualike/lualike.dart' hide Logger;

/// How Lua scripts should be compiled and embedded.
///
/// Each mode targets a different runtime strategy:
///
/// * [CompileMode.bytecode] -- Compiles to Lua 5.5 bytecode and writes
///   `.lua` files to `build/<outputDirName>/`. At runtime, load the bytes
///   with `rootBundle.load()` (Flutter) or `LuaAssetLoader` (Dart CLI)
///   and execute via `LuaBytecodeRuntime`.
///
/// * [CompileMode.dartSource] -- Compiles to Dart source code that embeds
///   the bytecode as a literal list. The generated `.dart` file imports
///   the lualike runtime and can be imported directly. No asset loading
///   needed at runtime.
///
/// * [CompileMode.dartEmbed] -- Compiles to Lua bytecode, then wraps the
///   bytes in a Dart file as a `List<int>` constant. Similar to
///   `--dart-output` from the lualike CLI. The generated file exports a
///   single top-level variable containing the raw bytecode bytes.
enum CompileMode {
  /// Compile Lua source to Lua 5.5 bytecode files.
  ///
  /// Output: `build/<outputDirName>/*.lua` (binary bytecode)
  ///
  /// Runtime: Load bytes via asset bundle or file, execute with
  /// `LuaBytecodeRuntime`.
  bytecode,

  /// Compile Lua source to standalone Dart source code.
  ///
  /// Output: `build/<outputDirName>/*.lua.dart` (Dart source)
  ///
  /// Runtime: Import the generated `.dart` file and call the emitted
  /// function directly. No asset loading or bytecode VM needed.
  dartSource,

  /// Compile Lua source to bytecode, then embed as a Dart literal.
  ///
  /// Output: `build/<outputDirName>/*.lua.dart` (Dart source with
  ///   `final List<int> scriptModule = <int>[...];`)
  ///
  /// Runtime: Import the generated file, pass the byte list to
  /// `LuaBytecodeRuntime.loadBytecode()`.
  dartEmbed,
}

/// A builder that compiles Lua scripts at build time.
///
/// This builder implements the [Builder] interface from `package:hooks` and
/// can be used in a `hook/build.dart` to compile Lua scripts at build time.
///
/// ## Compilation modes
///
/// | Mode | Output | Runtime |
/// |------|--------|---------|
/// | [CompileMode.bytecode] | `build/lua/*.lua` (binary) | Load bytes, run bytecode VM |
/// | [CompileMode.dartSource] | `build/lua/*.lua.dart` (Dart src) | Import & call directly |
/// | [CompileMode.dartEmbed] | `build/lua/*.lua.dart` (Dart src) | Import bytes, run bytecode VM |
///
/// ## Example -- bytecode mode (default)
///
/// ```dart
/// import 'package:hooks/hooks.dart';
/// import 'package:lualike_hooks/lualike_hooks.dart';
///
/// void main(List<String> args) async {
///   await build(args, (input, output) async {
///     final builder = LuaBuilder(
///       sources: ['assets/lua/'],
///     );
///     await builder.run(input: input, output: output, logger: null);
///   });
/// }
/// ```
///
/// ## Example -- Dart source mode
///
/// ```dart
/// void main(List<String> args) async {
///   await build(args, (input, output) async {
///     final builder = LuaBuilder(
///       sources: ['assets/lua/'],
///       mode: CompileMode.dartSource,
///     );
///     await builder.run(input: input, output: output, logger: null);
///   });
/// }
/// ```
final class LuaBuilder implements Builder {
  /// Creates a [LuaBuilder] with the supplied configuration.
  const LuaBuilder({
    required this.sources,
    this.mode = CompileMode.bytecode,
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

  /// How the Lua source should be compiled and embedded.
  ///
  /// Defaults to [CompileMode.bytecode].
  final CompileMode mode;

  /// The name of the output directory under `build/`.
  ///
  /// For example, if `outputDirName` is `'lua'`, compiled output will be
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
  /// Scans the [sources] directories for `.lua` files, compiles them
  /// according to [mode], and writes the output to `build/<outputDirName>/`.
  @override
  Future<void> run({
    required BuildInput input,
    required BuildOutputBuilder output,
    required Logger? logger,
  }) async {
    final packageRoot = input.packageRoot;

    // Write compiled output into build/<outputDirName>/ within the package.
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

      switch (mode) {
        case CompileMode.bytecode:
          await _compileBytecode(
            source: source,
            assetName: assetName,
            buildDir: buildDir,
            logger: logger,
          );
        case CompileMode.dartSource:
          await _compileDartSource(
            source: source,
            assetName: assetName,
            buildDir: buildDir,
            logger: logger,
          );
        case CompileMode.dartEmbed:
          await _compileDartEmbed(
            source: source,
            assetName: assetName,
            buildDir: buildDir,
            logger: logger,
          );
      }
    }
  }

  /// Compiles Lua source to bytecode and writes a `.lua` binary file.
  Future<void> _compileBytecode({
    required String source,
    required String assetName,
    required Uri buildDir,
    Logger? logger,
  }) async {
    final bytecode = _compileToBytecode(source, assetName);

    final outputPath = buildDir.resolve(assetName);
    await Directory.fromUri(outputPath.resolve('..')).create(recursive: true);
    await File.fromUri(outputPath).writeAsBytes(bytecode);

    logger?.info('Compiled (bytecode): $assetName (${bytecode.length} bytes)');
  }

  /// Compiles Lua source to standalone Dart source code.
  ///
  /// The generated `.dart` file contains a function that, when called,
  /// executes the Lua script using the lualike IR runtime.
  Future<void> _compileDartSource({
    required String source,
    required String assetName,
    required Uri buildDir,
    Logger? logger,
  }) async {
    final program = parse(source, url: assetName);

    final compiler = CompilePipeline(
      config: CompilePipelineConfig(
        target: CompileBackend.lualikeIR,
        enableConstantFolding: enableConstantFolding,
        enablePeephole: enablePeephole,
        stripDebug: stripDebug,
      ),
    );

    final artifact = compiler.compile(program) as LualikeIrArtifact;
    final emitter = LualikeIrToDart(chunk: artifact.chunk);
    final dartSource = emitter.generateModule();

    final outputPath = buildDir.resolve('$assetName.dart');
    await Directory.fromUri(outputPath.resolve('..')).create(recursive: true);
    await File.fromUri(outputPath).writeAsString(dartSource);

    logger?.info('Compiled (dart source): $assetName.dart');
  }

  /// Compiles Lua source to bytecode, then wraps it in a Dart file.
  ///
  /// The generated `.dart` file exports a `List<int>` constant containing
  /// the raw bytecode bytes. This is similar to the lualike CLI's
  /// `--dart-output` flag.
  Future<void> _compileDartEmbed({
    required String source,
    required String assetName,
    required Uri buildDir,
    Logger? logger,
  }) async {
    final bytecode = _compileToBytecode(source, assetName);

    // Generate a Dart file with the bytecode as a literal list.
    final varName = _toLowerCamelIdentifier(assetName);
    final buf = StringBuffer();
    buf.writeln('/// Pre-compiled Lua bytecode for `$assetName`.');
    buf.writeln('/// Generated by lualike_hooks. Do not edit.');
    buf.writeln('final List<int> ${varName}Module = <int>[');
    for (var i = 0; i < bytecode.length; i += 16) {
      final end = (i + 16) > bytecode.length ? bytecode.length : (i + 16);
      buf.write('  ');
      for (var j = i; j < end; j++) {
        buf.write('${bytecode[j]}');
        if (j < end - 1) buf.write(', ');
      }
      buf.writeln(',');
    }
    buf.writeln('];');

    final outputPath = buildDir.resolve('$assetName.dart');
    await Directory.fromUri(outputPath.resolve('..')).create(recursive: true);
    await File.fromUri(outputPath).writeAsString(buf.toString());

    logger?.info(
      'Compiled (dart embed): $assetName.dart (${bytecode.length} bytes)',
    );
  }

  /// Compiles Lua source to bytecode bytes.
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

  String _toLowerCamelIdentifier(String input) {
    final parts = input
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return 'lua';
    }
    final buffer = StringBuffer();
    final first = parts.first;
    buffer.write(first[0].toLowerCase());
    buffer.write(first.length > 1 ? first.substring(1) : '');
    for (final part in parts.skip(1)) {
      buffer.write(part[0].toUpperCase());
      buffer.write(part.length > 1 ? part.substring(1) : '');
    }
    final result = buffer.toString();
    if (RegExp(r'^[0-9]').hasMatch(result)) {
      return '_$result';
    }
    return result;
  }
}
