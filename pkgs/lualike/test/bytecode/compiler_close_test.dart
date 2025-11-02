import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler to-be-closed locals', () {
    test('emits TBC and CLOSE for <close> locals', () {
      final source = '''
local resource <close> = factory()
return 0
''';
      final chunk = BytecodeCompiler().compile(parse(source));
      final instructions = chunk.mainPrototype.instructions;

      final hasTbc = instructions.any(
        (instruction) => instruction.opcode == BytecodeOpcode.tbc,
      );
      expect(hasTbc, isTrue);

      final closeIndex = instructions.indexWhere(
        (instruction) => instruction.opcode == BytecodeOpcode.close,
      );
      expect(closeIndex, isNonNegative);

      final returnIndex = instructions.lastIndexWhere(
        (instruction) =>
            instruction.opcode == BytecodeOpcode.return0 ||
            instruction.opcode == BytecodeOpcode.return1 ||
            instruction.opcode == BytecodeOpcode.ret,
      );
      expect(returnIndex, greaterThan(closeIndex));
    });

    test('rejects multiple to-be-closed variables in same declaration', () {
      const source = 'local a <close>, b <close> = factory()';
      expect(
        () => BytecodeCompiler().compile(parse(source)),
        throwsUnsupportedError,
      );
    });

    test('requires to-be-closed variable to be last in declaration', () {
      const source = 'local a <close>, b = factory()';
      expect(
        () => BytecodeCompiler().compile(parse(source)),
        throwsUnsupportedError,
      );
    });
  });
}
