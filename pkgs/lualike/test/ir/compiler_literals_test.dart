@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler literals', () {
    test('compiles return number literal', () {
      final program = parse('return 42');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;

      expect(proto.registerCount, equals(1));
      expect(proto.constants, hasLength(1));
      expect(
        proto.constants.first,
        isA<IntegerConstant>().having((c) => c.value, 'value', 42),
      );

      expect(proto.instructions, hasLength(3));
      expect(
        proto.instructions.first.opcode,
        equals(LualikeIrOpcode.varArgPrep),
      );

      final load = proto.instructions[1] as ABxInstruction;
      expect(load.opcode, LualikeIrOpcode.loadK);
      expect(load.a, equals(0));
      expect(load.bx, equals(0));

      final ret = proto.instructions[2] as ABCInstruction;
      expect(ret.opcode, LualikeIrOpcode.return1);
      expect(ret.a, equals(0));
    });

    test('compiles boolean literal return', () {
      final program = parse('return true');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;

      expect(proto.constants, isEmpty);
      expect(proto.instructions, hasLength(3));
      expect(
        proto.instructions.first.opcode,
        equals(LualikeIrOpcode.varArgPrep),
      );

      final load = proto.instructions[1] as ABCInstruction;
      expect(load.opcode, LualikeIrOpcode.loadTrue);
      expect(load.a, equals(0));

      final ret = proto.instructions[2] as ABCInstruction;
      expect(ret.opcode, LualikeIrOpcode.return1);
      expect(ret.a, equals(0));
    });

    test('adds implicit return when absent', () {
      final program = parse('');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;

      expect(proto.instructions, hasLength(2));
      expect(
        proto.instructions.first.opcode,
        equals(LualikeIrOpcode.varArgPrep),
      );
      final ret = proto.instructions.last as ABCInstruction;
      expect(ret.opcode, LualikeIrOpcode.return0);
    });
  });
}
