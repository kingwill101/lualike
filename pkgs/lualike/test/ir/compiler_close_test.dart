@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/bytecode_lowering.dart';
import 'package:lualike/src/ir/disassembler.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/lua_bytecode/disassembler.dart';
import 'package:lualike/src/lua_bytecode/emitter.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler to-be-closed locals', () {
    test('marks <close> locals without a premature close before return', () {
      final source = '''
local resource <close> = factory()
return 0
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final instructions = chunk.mainPrototype.instructions;

      final hasTbc = instructions.any(
        (instruction) => instruction.opcode == LualikeIrOpcode.tbc,
      );
      expect(hasTbc, isTrue);

      final returnIndex = instructions.lastIndexWhere(
        (instruction) =>
            instruction.opcode == LualikeIrOpcode.return0 ||
            instruction.opcode == LualikeIrOpcode.return1 ||
            instruction.opcode == LualikeIrOpcode.ret,
      );
      expect(returnIndex, isNonNegative);

      final closeIndex = instructions.indexWhere(
        (instruction) => instruction.opcode == LualikeIrOpcode.close,
      );
      expect(closeIndex, equals(-1));
    });

    test('rejects multiple to-be-closed variables in same declaration', () {
      const source = 'local a <close>, b <close> = factory()';
      expect(
        () => LualikeIrCompiler().compile(parse(source)),
        throwsUnsupportedError,
      );
    });

    test('allows a single to-be-closed variable in mixed declarations', () {
      const source = 'local a <close>, b = factory(), 2';
      final chunk = LualikeIrCompiler().compile(parse(source));
      final instructions = chunk.mainPrototype.instructions;

      final hasTbc = instructions.any(
        (instruction) => instruction.opcode == LualikeIrOpcode.tbc,
      );
      expect(hasTbc, isTrue);
    });

    test('debug probe goto around to-be-closed variable', () {
      const source = r'''
do
  global *

  local function newobj (var)
    _ENV[var] = true
    return setmetatable({}, {__close = function ()
      _ENV[var] = nil
    end})
  end

  goto L1

  ::L4:: assert(not varX); goto L5

  ::L1::
  local varX <close> = newobj("X")
  assert(varX); goto L2

  ::L3::
  assert(varX); goto L4

  ::L2:: assert(varX); goto L3

  ::L5::
end
''';
      final chunk = LualikeIrCompiler().compile(parse(source));
      print(disassembleChunk(chunk));
      print(const LuaBytecodeDisassembler().render(
        lowerIrChunkToLuaBytecodeChunk(chunk),
      ));
      print(
        const LuaBytecodeDisassembler().render(
          const LuaBytecodeEmitter().compileSource(source).chunk,
        ),
      );
      expect(chunk.mainPrototype.instructions, isNotEmpty);
    });
  });
}
