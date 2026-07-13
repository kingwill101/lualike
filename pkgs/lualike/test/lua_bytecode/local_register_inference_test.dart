/// Regression coverage for debug locals across serialize/load and the fold SSA
/// pipeline.
///
/// Guards:
/// * [inferLocalRegisters] stack discipline
/// * parse-time register recovery after serialize
/// * main `lineDefined == 0`
/// * full SSA fold path still usable for `debug.getlocal`
///
/// See `doc/decisions.md` and `IR_NEXT_PHASE_PLAN.md`.
@TestOn('!browser')
@Tags(['lua_bytecode'])
library;

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/lua_bytecode/chunk.dart';
import 'package:lualike/src/lua_bytecode/debug_local_caches.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/lua_bytecode/parser.dart';
import 'package:lualike/src/lua_bytecode/runtime.dart';
import 'package:lualike/src/lua_bytecode/serializer.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('local register inference', () {
    test('infers stack registers from start/end pc ranges', () {
      final locals = <LuaBytecodeLocalVariableDebugInfo>[
        const LuaBytecodeLocalVariableDebugInfo(
          name: 'a',
          startPc: 1,
          endPc: 10,
        ),
        const LuaBytecodeLocalVariableDebugInfo(
          name: 'b',
          startPc: 2,
          endPc: 5,
        ),
        const LuaBytecodeLocalVariableDebugInfo(
          name: 'c',
          startPc: 5,
          endPc: 10,
        ),
      ];

      final inferred = inferLocalRegisters(locals);
      expect(
        inferred.map((local) => local.register).toList(),
        equals([0, 1, 1]),
      );
    });

    test('roundtrip through serialize/parse restores registers', () {
      final program = parse('''
local a, b = 1, 2
local function f(x)
  local y = x
  return y
end
return f(a + b)
''', url: 'regs.lua');

      final emitted = const LuaBytecodeEmitter()
          .compileProgram(program, chunkName: 'regs.lua')
          .chunk;
      final original = <String, int?>{};
      void collect(LuaBytecodePrototype proto, String path) {
        for (final local in proto.localVariables) {
          if (local.name != null) {
            original['$path/${local.name}'] = local.register;
          }
        }
        for (var i = 0; i < proto.prototypes.length; i++) {
          collect(proto.prototypes[i], '$path/$i');
        }
      }

      collect(emitted.mainPrototype, 'main');
      expect(original.values.every((reg) => reg != null), isTrue);

      final parsed = const LuaBytecodeParser().parse(
        serializeLuaBytecodeChunk(emitted),
      );
      final restored = <String, int?>{};
      void collectRestored(LuaBytecodePrototype proto, String path) {
        for (final local in proto.localVariables) {
          if (local.name != null) {
            restored['$path/${local.name}'] = local.register;
          }
        }
        for (var i = 0; i < proto.prototypes.length; i++) {
          collectRestored(proto.prototypes[i], '$path/$i');
        }
      }

      collectRestored(parsed.mainPrototype, 'main');
      expect(restored, equals(original));
    });

    test('pipeline fold path keeps getlocal-visible local names', () {
      final program = parse('''
local a = 10
local n, v = debug.getlocal(1, 1)
assert(n == "a", "expected local name a, got " .. tostring(n))
assert(v == 10 or v == nil, "unexpected value " .. tostring(v))
''', url: 'getlocal.lua');

      final artifact = CompilePipeline(
        config: const CompilePipelineConfig(
          enableConstantFolding: true,
          enablePeephole: true,
          enableSsaDeadCodeElimination: true,
          enableSsaGlobalValueNumbering: true,
          enableSsaSccp: true,
          enableSsaLicm: true,
          enableSsaCoalesce: true,
          enableSsaEscape: true,
          target: CompileBackend.luaBytecode,
        ),
      ).compile(program);
      expect(artifact, isA<LuaBytecodeArtifact>());

      final locals =
          (artifact as LuaBytecodeArtifact).chunk.mainPrototype.localVariables;
      final a = locals.firstWhere((local) => local.name == 'a');
      expect(a.register, isNotNull);

      final reloaded = const LuaBytecodeParser().parse(
        artifact.serializedBytes,
      );
      final reloadedA = reloaded.mainPrototype.localVariables.firstWhere(
        (local) => local.name == 'a',
      );
      expect(reloadedA.register, equals(a.register));
      expect(reloaded.mainPrototype.lineDefined, equals(0));
    });

    test('full SSA pipeline runtime preserves debug.getlocal', () async {
      final program = parse('''
local a = 10
assert(debug.getlocal(1, 1) == "a")
assert(select(2, debug.getlocal(1, 1)) == 10)
local b = 20
assert(debug.getlocal(1, 2) == "b")
assert(select(2, debug.getlocal(1, 2)) == 20)
''', url: 'getlocal_runtime.lua');

      final artifact =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: true,
                  enablePeephole: true,
                  enableSsaDeadCodeElimination: true,
                  enableSsaGlobalValueNumbering: true,
                  enableSsaSccp: true,
                  enableSsaLicm: true,
                  enableSsaCoalesce: true,
                  enableSsaEscape: true,
                  target: CompileBackend.luaBytecode,
                ),
              ).compile(program)
              as LuaBytecodeArtifact;

      expect(artifact.chunk.mainPrototype.lineDefined, equals(0));
      for (final local in artifact.chunk.mainPrototype.localVariables) {
        expect(local.register, isNotNull, reason: local.name);
      }

      final runtime = LuaBytecodeRuntime();
      final chunk = await runtime.loadBytecode(
        artifact.serializedBytes,
        moduleName: 'getlocal_runtime.lua',
      );
      await runtime.callFunction(chunk, const <Object?>[]);
    });
  });
}
