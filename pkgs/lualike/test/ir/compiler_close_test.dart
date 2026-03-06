@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler to-be-closed locals', () {
    test('emits TBC and CLOSE for <close> locals', () {
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

      final closeIndex = instructions.indexWhere(
        (instruction) => instruction.opcode == LualikeIrOpcode.close,
      );
      expect(closeIndex, isNonNegative);

      final returnIndex = instructions.lastIndexWhere(
        (instruction) =>
            instruction.opcode == LualikeIrOpcode.return0 ||
            instruction.opcode == LualikeIrOpcode.return1 ||
            instruction.opcode == LualikeIrOpcode.ret,
      );
      expect(returnIndex, greaterThan(closeIndex));
    });

    test('rejects multiple to-be-closed variables in same declaration', () {
      const source = 'local a <close>, b <close> = factory()';
      expect(
        () => LualikeIrCompiler().compile(parse(source)),
        throwsUnsupportedError,
      );
    });

    test('requires to-be-closed variable to be last in declaration', () {
      const source = 'local a <close>, b = factory()';
      expect(
        () => LualikeIrCompiler().compile(parse(source)),
        throwsUnsupportedError,
      );
    });
  });
}
