@Tags(['ir'])
library;

import 'package:lualike/lualike.dart';
import 'package:lualike/src/lua_bytecode/vm_value_helpers.dart';
import 'package:test/test.dart';

void main() {
  group('textual lualike_ir lowering', () {
    test('parsed textual IR lowers to bytecode and executes', () async {
      const source = '''
      chunk has_debug_info=true {
        prototype main register_count=1 param_count=0 is_vararg=true {
          upvalue_descriptors {
            upvalue in_stack=1 index=0 kind=0;
          }
          constants {
            int 42;
          }
          instructions {
            // pc=0 line=1
            abc VARARGPREP a=0 b=0 c=0;
            // pc=1 line=2
            abx LOADK a=0 bx=0;
            // pc=2 line=2
            abc RETURN1 a=0 b=0 c=0;
          }
          debug_info {
            line_info [1, 2, 2];
            upvalue_names ["_ENV"];
            preferred_name "main";
            preferred_name_what "global";
            local_names {
              local name="tmp" start_pc=1 end_pc=2 register=0;
            }
          }
        }
      }
      ''';

      final chunk = LualikeIrReader.parse(source);
      final lowered = lowerIrChunkToLuaBytecodeChunk(chunk);
      final runtime = LualikeIrRuntime();
      final closure = LuaBytecodeClosure.main(
        runtime: runtime,
        chunk: lowered,
        chunkName: '=(text-ir)',
        environment: runtime.globals,
      );

      final result = await closure.call(const <Object?>[]);
      final unwrapped = switch (result) {
        Value(:final raw) => raw is LuaString ? raw.toString() : raw,
        LuaString() => result.toString(),
        _ => result,
      };
      expect(unwrapped, equals(42));
      expect(lowered.mainPrototype.localVariables.single.register, equals(0));
      expect(lowered.mainPrototype.lineInfo, isNotEmpty);
    });

    test('lowering tolerates extra debug line entries', () async {
      final chunk = LualikeIrChunk(
        flags: const LualikeIrChunkFlags(hasDebugInfo: true),
        mainPrototype: LualikeIrPrototype(
          registerCount: 1,
          paramCount: 0,
          isVararg: true,
          upvalueDescriptors: const [
            LualikeIrUpvalueDescriptor(inStack: 1, index: 0),
          ],
          instructions: const <LualikeIrInstruction>[
            ABCInstruction(
              opcode: LualikeIrOpcode.varArgPrep,
              a: 0,
              b: 0,
              c: 0,
            ),
            ABxInstruction(opcode: LualikeIrOpcode.loadK, a: 0, bx: 0),
            ABCInstruction(opcode: LualikeIrOpcode.return1, a: 0, b: 0, c: 0),
          ],
          constants: const [IntegerConstant(42)],
          prototypes: const [],
          lineDefined: 1,
          lastLineDefined: 3,
          debugInfo: const LualikeIrDebugInfo(
            lineInfo: [1, 2, 3, 4],
            upvalueNames: ['_ENV'],
            absoluteSourcePath: '=(text-ir-extra-lines)',
            preferredName: 'main',
            preferredNameWhat: 'global',
          ),
          registerConstFlags: const [false],
          constSealPoints: const {},
        ),
      );

      final lowered = lowerIrChunkToLuaBytecodeChunk(chunk);
      final runtime = LualikeIrRuntime();
      final closure = LuaBytecodeClosure.main(
        runtime: runtime,
        chunk: lowered,
        chunkName: '=(text-ir-extra-lines)',
        environment: runtime.globals,
      );

      final result = await closure.call(const <Object?>[]);
      final unwrapped = switch (result) {
        Value(:final raw) => raw is LuaString ? raw.toString() : raw,
        LuaString() => result.toString(),
        _ => result,
      };
      expect(unwrapped, equals(42));
      expect(lowered.mainPrototype.lineInfo, isNotEmpty);
    });
  });
}
