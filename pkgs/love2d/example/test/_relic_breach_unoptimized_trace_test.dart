import 'dart:convert' as convert;

import 'package:flutter_test/flutter_test.dart';
import 'package:love2d/love2d.dart';
import 'package:love2d/src/runtime/filesystem/love_filesystem_runtime.dart';
import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/parse.dart';

const String _entry = 'assets/relic_breach/main.lua';

void main() {
  test('trace unoptimized relic breach failure', () async {
    final runtime = LoveScriptRuntime(
      runtime: LuaBytecodeRuntime(),
      host: LoveHeadlessHost(),
      filesystemAdapter: LoveLualikeFilesystemAdapter(),
    );
    final filesystem = LoveFilesystemState.of(runtime.runtime);
    expect(filesystem.setSource(_entry), isTrue);
    await runtime.loadConfIfPresent();
    final entryData = await filesystem.readFileData('main.lua', filename: _entry);
    final source = convert.utf8.decode(entryData!.bytes);
    final program = parse(source, url: entryData.filename);
    final pipeline = CompilePipeline(
      config: const CompilePipelineConfig(
        target: CompileBackend.luaBytecode,
        enableAnalyzer: false,
        enableConstantFolding: false,
        enableConstPropagation: false,
        enableTypeNarrowing: false,
        enableMetatableFolding: false,
        enablePeephole: false,
        enableBytecodePeephole: false,
        enableSsaDeadCodeElimination: false,
        enableSsaGlobalValueNumbering: false,
        enableSsaSccp: false,
        enableSsaLicm: false,
        enableSsaCoalesce: false,
        enableSsaEscape: false,
        enableFunctionInlining: false,
        enableLoopUnrolling: false,
        enableBundling: false,
        bundleSearchPaths: ['.'],
        enableDeadCodeElimination: false,
      ),
    );
    final artifact = pipeline.compile(program) as LuaBytecodeArtifact;
    final chunk = await runtime.runtime.loadBytecode(artifact.serializedBytes, moduleName: _entry);
    await runtime.runtime.callFunction(chunk, const <Object?>[]);
    await runtime.callLoadIfDefined();
    await runtime.callUpdateIfDefined(1 / 60);
    runtime.context.beginDrawFrame();
    runtime.context.graphics.origin();
    try {
      await runtime.callDrawIfDefined();
      fail('expected failure');
    } catch (e, st) {
      // ignore: avoid_print
      print('ERROR: $e');
      // ignore: avoid_print
      print(st);
      rethrow;
    }
  });
}
