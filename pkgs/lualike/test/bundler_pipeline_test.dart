@TestOn('!browser')
@Tags(['ir', 'lua_bytecode'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/lua_string.dart';
import 'package:lualike/src/parse.dart';
import 'package:lualike/src/runtime/lua_runtime.dart';
import 'package:lualike/src/value.dart';
import 'package:test/test.dart';

void main() {
  test('bundles, folds, and executes a transitive module graph', () async {
    final directory = await Directory.systemTemp.createTemp('lualike_bundle_');
    addTearDown(() => directory.delete(recursive: true));

    File('${directory.path}/constants.lua').writeAsStringSync('''
local M = {}
M.answer = 6 * 7
M.banner = "fold" .. "ed"
M.unused = (100 + 23) * 4
return M
''');
    File('${directory.path}/ops.lua').writeAsStringSync('''
local constants = require("constants")
local M = {}
function M.compute(value)
  return value * 2 + constants.answer
end
function M.unused(value)
  return value + constants.unused
end
return M
''');
    final entry = File('${directory.path}/main.lua')
      ..writeAsStringSync('''
local ops = require("ops")
local constants = require("constants")
local constants_again = require("constants")
return ops.compute(5), constants.answer, constants.banner,
  constants == constants_again
''');

    final artifact =
        CompilePipeline(
              config: CompilePipelineConfig.luaBytecodeOptimized(
                enableBundling: true,
                bundleSearchPaths: <String>[directory.path],
              ),
            ).compile(parse(entry.readAsStringSync(), url: entry.path))
            as LuaBytecodeArtifact;

    final constantsInChunk = artifact.chunk.mainPrototype.constants
        .map(_constantValue)
        .toList(growable: false);
    expect(constantsInChunk, isNot(contains('require')));
    expect(constantsInChunk, isNot(contains(492)));

    final runtime = LuaBytecodeRuntime();
    final loadResult = await runtime.loadChunk(
      LuaChunkLoadRequest(
        source: Value(
          LuaString.fromBytes(Uint8List.fromList(artifact.serializedBytes)),
        ),
        chunkName: entry.path,
        mode: 'b',
      ),
    );
    expect(loadResult.isSuccess, isTrue);

    final result = await loadResult.chunk!.call(const []);
    expect(_flatten(result), equals(<Object?>[52, 42, 'folded', true]));
  });
}

Object? _constantValue(LuaBytecodeConstant constant) => switch (constant) {
  LuaBytecodeNilConstant() => null,
  LuaBytecodeBooleanConstant(:final value) => value,
  LuaBytecodeIntegerConstant(:final value) => value,
  LuaBytecodeFloatConstant(:final value) => value,
  LuaBytecodeStringConstant(:final value) => value,
};

List<Object?> _flatten(Object? result) {
  final values = switch (result) {
    final Value value when value.isMulti => value.raw as List<Object?>,
    final Value value => <Object?>[value],
    final List<Object?> list => list,
    _ => <Object?>[result],
  };
  return values
      .map<Object?>((value) {
        final raw = value is Value ? value.raw : value;
        return raw is LuaString ? raw.toString() : raw;
      })
      .toList(growable: false);
}
