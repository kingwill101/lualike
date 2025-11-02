import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/instruction.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/bytecode/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler table assignments', () {
    test('compiles table field assignment', () {
      final program = parse('tbl.value = 42');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final fieldIndex = proto.constants.indexWhere(
        (constant) =>
            constant is ShortStringConstant && constant.value == 'value',
      );
      expect(fieldIndex, isNonNegative);

      final setField = proto.instructions[2] as ABCInstruction;
      expect(setField.opcode, BytecodeOpcode.setField);
      expect(setField.b, equals(fieldIndex));
      final loadValue = proto.instructions[1] as ABxInstruction;
      expect(setField.c, equals(loadValue.a));
    });

    test('compiles table index assignment with integer literal', () {
      final program = parse('arr[1] = 5');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final loadValue = proto.instructions[1] as ABxInstruction;
      final setI = proto.instructions[2] as ABCInstruction;
      expect(setI.opcode, BytecodeOpcode.setI);
      expect(setI.b, equals(1));
      expect(setI.c, equals(loadValue.a));
    });

    test('compiles table index assignment with dynamic key', () {
      final program = parse('arr[key] = value');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final getTable = proto.instructions[0] as ABCInstruction;
      final getKey = proto.instructions[1] as ABCInstruction;
      final getValue = proto.instructions[2] as ABCInstruction;
      final setTable = proto.instructions[3] as ABCInstruction;
      expect(setTable.opcode, BytecodeOpcode.setTable);
      expect(setTable.a, equals(0));
      expect(setTable.b, equals(getKey.a));
      expect(setTable.c, equals(getValue.a));
    });
  });
}
