import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/instruction.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/bytecode/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler tables', () {
    test('compiles table field access', () {
      final program = parse('return tbl.value');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final fieldIndex = proto.constants.indexWhere(
        (constant) =>
            constant is ShortStringConstant && constant.value == 'value',
      );
      expect(fieldIndex, isNonNegative);

      final getField = proto.instructions[1] as ABCInstruction;
      expect(getField.opcode, BytecodeOpcode.getField);
      expect(getField.b, equals(0));
      expect(getField.c, equals(fieldIndex));
    });

    test('compiles table index access with integer literal', () {
      final program = parse('return arr[1]');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final getI = proto.instructions[1] as ABCInstruction;
      expect(getI.opcode, BytecodeOpcode.getI);
      expect(getI.a, equals(0));
      expect(getI.b, equals(0));
      expect(getI.c, equals(1));
    });

    test('compiles table index access with dynamic key', () {
      final program = parse('return arr[idx]');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      expect(proto.instructions, hasLength(4));

      final getTable = proto.instructions[2] as ABCInstruction;
      expect(getTable.opcode, BytecodeOpcode.getTable);
      expect(getTable.a, equals(0));
      expect(getTable.b, equals(0));
      expect(getTable.c, equals(1));
    });
  });
}
