import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/instruction.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/bytecode/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler literals', () {
    test('compiles return number literal', () {
      final program = parse('return 42');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      expect(proto.registerCount, equals(1));
      expect(proto.constants, hasLength(1));
      expect(
        proto.constants.first,
        isA<IntegerConstant>().having((c) => c.value, 'value', 42),
      );

      expect(proto.instructions, hasLength(2));
      final load = proto.instructions[0] as ABxInstruction;
      expect(load.opcode, BytecodeOpcode.loadK);
      expect(load.a, equals(0));
      expect(load.bx, equals(0));

      final ret = proto.instructions[1] as ABCInstruction;
      expect(ret.opcode, BytecodeOpcode.return1);
      expect(ret.a, equals(0));
    });

    test('compiles boolean literal return', () {
      final program = parse('return true');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      expect(proto.constants, isEmpty);
      expect(proto.instructions, hasLength(2));

      final load = proto.instructions[0] as ABCInstruction;
      expect(load.opcode, BytecodeOpcode.loadTrue);
      expect(load.a, equals(0));

      final ret = proto.instructions[1] as ABCInstruction;
      expect(ret.opcode, BytecodeOpcode.return1);
      expect(ret.a, equals(0));
    });

    test('adds implicit return when absent', () {
      final program = parse('');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      expect(proto.instructions, hasLength(1));
      final ret = proto.instructions.single as ABCInstruction;
      expect(ret.opcode, BytecodeOpcode.return0);
    });
  });
}
