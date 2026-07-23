@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/compile/compiler_pass.dart';
import 'package:lualike/src/compile/constant_folding_pass.dart';
import 'package:lualike/src/compile/metatable_folding_pass.dart';
import 'package:lualike/src/runtime/lua_results.dart';
import 'package:test/test.dart';

CompilePipeline _pipeline() => CompilePipeline(
  config: const CompilePipelineConfig(
    enableConstantFolding: true,
    enableMetatableFolding: true,
    enablePeephole: true,
    enableBytecodePeephole: true,
    target: CompileBackend.luaBytecode,
  ),
);

Future<List<Object?>> _execute(String source) async {
  final artifact = _pipeline().compileSource(source) as LuaBytecodeArtifact;
  final runtime = LuaBytecodeRuntime();
  final chunk = await runtime.loadBytecode(
    artifact.serializedBytes,
    moduleName: 'metatable-folding.lua',
  );
  final result = await runtime.callFunction(chunk, const <Object?>[]);
  return (result as LuaResults).values
      .map((value) => value is Value ? value.unwrap() : value)
      .toList(growable: false);
}

void main() {
  group('metatable-folding safety boundary', () {
    test('does not annotate setmetatable calls as constants', () {
      final program = parse('local value = setmetatable({}, {})');
      final context = CompilerContext(program);
      ConstantFoldingPass().run(program, context);
      MetatableFoldingPass().run(program, context);

      final declaration = program.statements.single as LocalDeclaration;
      final call = declaration.exprs.single;
      expect(context.foldingResult!.isConstant(call), isFalse);
    });

    test('preserves shadowed calls and later metatable mutation', () async {
      final result = await _execute(r'''
local realSetmetatable = setmetatable
local calls = 0
local function setmetatable(value, mt)
  calls = calls + 1
  return realSetmetatable(value, mt)
end

local value = setmetatable({}, {})
local mt = getmetatable(value)
mt.__index = function() return "mutated" end
return calls, value.missing, getmetatable(value) == mt
''');

      expect(result, equals(<Object?>[1, 'mutated', true]));
    });

    test('preserves table identity and late metamethod lookup', () async {
      final result = await _execute(r'''
local value = setmetatable({}, {})
local alias = value
local mt = getmetatable(value)
mt.__add = function(left, right) return left end
return value == alias, getmetatable(value) == mt, value + value == value
''');

      expect(result, equals(<Object?>[true, true, true]));
    });
  });
}
