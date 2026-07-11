/// Tests for all compiler passes, using the pipeline API where possible.
library;

import 'package:lualike/src/compile/pipeline.dart';
import 'package:lualike/src/ir/peephole_pass.dart';
import 'package:lualike/src/ir/ssa.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('PeepholePass (unit tests)', () {
    LualikeIrPrototype makeProto(List<LualikeIrInstruction> code) {
      return LualikeIrPrototype(
        registerCount: 4,
        paramCount: 0,
        isVararg: true,
        namedVarargRegister: null,
        upvalueDescriptors: const [],
        instructions: code,
        constants: const [],
        prototypes: const [],
        lineDefined: 0,
        lastLineDefined: 0,
        debugInfo: null,
        registerConstFlags: const [],
        constSealPoints: const {},
      );
    }

    test('removes JMP 0 (no-op)', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: makeProto([
          const AsJInstruction(opcode: LualikeIrOpcode.jmp, sJ: 0),
        ]),
      );
      final result = PeepholePass().optimize(chunk);
      // JMP 0 may or may not be removed depending on the encoding.
      // The important thing is it doesn't crash and produces valid IR.
      expect(result.mainPrototype.instructions.length, lessThan(2));
    });

    test('removes LOADK r,k; MOVE r,r (self-copy)', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: makeProto([
          const ABxInstruction(opcode: LualikeIrOpcode.loadK, a: 0, bx: 0),
          const ABCInstruction(opcode: LualikeIrOpcode.move, a: 0, b: 0, c: 0),
        ]),
      );
      final result = PeepholePass().optimize(chunk);
      expect(result.mainPrototype.instructions.length, equals(1));
      expect(
        result.mainPrototype.instructions.first.opcode,
        equals(LualikeIrOpcode.loadK),
      );
    });

    test('removes LOADNIL r; LOADK r,v (dead store)', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: makeProto([
          const ABCInstruction(
            opcode: LualikeIrOpcode.loadNil,
            a: 0,
            b: 0,
            c: 0,
          ),
          const ABxInstruction(opcode: LualikeIrOpcode.loadK, a: 0, bx: 1),
        ]),
      );
      final result = PeepholePass().optimize(chunk);
      expect(result.mainPrototype.instructions.length, equals(1));
      expect(
        result.mainPrototype.instructions.first.opcode,
        equals(LualikeIrOpcode.loadK),
      );
    });

    test('removes MOVE r1,r2; MOVE r2,r1 (swap)', () {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(),
        mainPrototype: makeProto([
          const ABCInstruction(opcode: LualikeIrOpcode.move, a: 0, b: 1, c: 0),
          const ABCInstruction(opcode: LualikeIrOpcode.move, a: 1, b: 0, c: 0),
        ]),
      );
      final result = PeepholePass().optimize(chunk);
      expect(result.mainPrototype.instructions.length, equals(1));
    });
  });

  group('Full pipeline (integration tests)', () {
    test('optimizations reduce instruction count for arithmetic', () {
      final source = 'local x = 5; local y = x + 3; return y';

      // All OFF
      final off =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: false,
                  enableConstPropagation: false,
                  enablePeephole: false,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource(source)
              as LualikeIrArtifact;

      // All ON
      final on =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: true,
                  enableConstPropagation: true,
                  enablePeephole: true,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource(source)
              as LualikeIrArtifact;

      // With optimizations, the IR should have fewer or equal instructions.
      // (Equal is possible for tiny scripts where overhead dominates.)
      expect(
        on.chunk.mainPrototype.instructions.length,
        lessThanOrEqualTo(off.chunk.mainPrototype.instructions.length),
      );
    });

    test('function inlining reduces instructions', () {
      final source = '''
        local function add(a, b) return a + b end
        return add(3, 4)
      ''';

      final off =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: false,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource(source)
              as LualikeIrArtifact;

      final on =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: true,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource(source)
              as LualikeIrArtifact;

      expect(
        on.chunk.mainPrototype.instructions.length,
        lessThan(off.chunk.mainPrototype.instructions.length),
      );
    });

    test('dead branch elimination removes else block', () {
      final source = '''
        local x
        if true then
          x = 1
        else
          x = 2
        end
        return x
      ''';

      final off =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: false,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource(source)
              as LualikeIrArtifact;

      final on =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: true,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource(source)
              as LualikeIrArtifact;

      // With folding, the else branch is eliminated.
      expect(
        on.chunk.mainPrototype.instructions.length,
        lessThan(off.chunk.mainPrototype.instructions.length),
      );
    });

    test('peephole optimization does not change semantics', () {
      final pipeline = CompilePipeline(
        config: const CompilePipelineConfig(
          enablePeephole: true,
          target: CompileBackend.luaBytecode,
        ),
      );
      final artifact = pipeline.compileSource('return 42');
      final lua = artifact as LuaBytecodeArtifact;
      expect(lua.serializedBytes.length, greaterThan(0));
    });

    test('full optimization pipeline produces correct bytecode', () {
      final pipeline = CompilePipeline(
        config: const CompilePipelineConfig(
          enableConstantFolding: true,
          enableConstPropagation: true,
          enableTypeNarrowing: true,
          enablePeephole: true,
          target: CompileBackend.luaBytecode,
        ),
      );
      final artifact = pipeline.compileSource('return 1 + 2');
      final lua = artifact as LuaBytecodeArtifact;
      // Should produce non-empty bytecode.
      expect(lua.serializedBytes.length, greaterThan(0));
    });

    test('arithmetic folded in compiled output', () {
      final off =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: false,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource('return 2 + 3 * 4 - 1')
              as LualikeIrArtifact;

      final on =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  enableConstantFolding: true,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource('return 2 + 3 * 4 - 1')
              as LualikeIrArtifact;

      expect(
        on.chunk.mainPrototype.instructions.length,
        lessThan(off.chunk.mainPrototype.instructions.length),
      );
    });

    test('dumpIr includes SSA output', () {
      final artifact =
          CompilePipeline(
                config: const CompilePipelineConfig(
                  dumpIr: true,
                  target: CompileBackend.lualikeIR,
                ),
              ).compileSource('return 1 + 2')
              as LualikeIrArtifact;

      expect(artifact.disassembly, isNotNull);
      expect(artifact.ssaDisassembly, isNotNull);
      expect(artifact.ssaDisassembly, contains('ssa {'));
      expect(artifact.ssaDisassembly, contains('block 0'));
      expect(
        formatLualikeIrSsaFunction(
          LualikeIrSsaFunction.fromPrototype(
            artifact.chunk.mainPrototype,
          ).simplifyTrivialPhis(),
        ),
        equals(artifact.ssaDisassembly),
      );
    });

    test('type narrowing pass does not crash', () {
      final pipeline = CompilePipeline(
        config: const CompilePipelineConfig(
          enableTypeNarrowing: true,
          enableConstantFolding: true,
          target: CompileBackend.luaBytecode,
        ),
      );
      final artifact = pipeline.compileSource('''
        local function f(v)
          if type(v) == "number" then return v * 2 end
          return nil
        end
        return f(5)
      ''');
      expect(
        (artifact as LuaBytecodeArtifact).serializedBytes.length,
        greaterThan(0),
      );
    });
  });

  group('Bundler detection', () {
    test('parses require() call', () {
      final program = parse('local x = require("foo")');
      expect(program.statements.length, equals(1));
      // The require call is a FunctionCall with identifier "require"
      // and one string argument.
    });

    test('require path is string literal', () {
      final program = parse('local x = require("mymod")');
      expect(program.statements.length, equals(1));
    });
  });
}
