@Tags(['ir'])
library;

import 'package:lualike/parsers.dart';
import 'package:lualike/src/ir/bytecode_lowering.dart';
import 'package:lualike/src/ir/runtime.dart';
import 'package:lualike/src/lua_bytecode/vm.dart';
import 'package:lualike/lualike.dart';
import 'package:test/test.dart';

void main() {
  group('textual lualike_ir lowering', () {
    test('parsed textual IR lowers to bytecode and executes', () async {
      const source = '''
      chunk has_debug_info=true {
        prototype main register_count=1 param_count=0 is_vararg=true {
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
  });
}
