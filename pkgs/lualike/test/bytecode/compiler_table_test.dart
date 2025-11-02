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
      final instructions = _stripVarArgPrep(proto);

      final fieldIndex = proto.constants.indexWhere(
        (constant) =>
            constant is ShortStringConstant && constant.value == 'value',
      );
      expect(fieldIndex, isNonNegative);

      final getField = instructions[1] as ABCInstruction;
      expect(getField.opcode, BytecodeOpcode.getField);
      expect(getField.b, equals(0));
      expect(getField.c, equals(fieldIndex));
    });

    test('compiles table index access with integer literal', () {
      final program = parse('return arr[1]');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final getI = instructions[1] as ABCInstruction;
      expect(getI.opcode, BytecodeOpcode.getI);
      expect(getI.a, equals(0));
      expect(getI.b, equals(0));
      expect(getI.c, equals(1));
    });

    test('compiles table index access with dynamic key', () {
      final program = parse('return arr[idx]');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(instructions, hasLength(4));

      final getTable = instructions[2] as ABCInstruction;
      expect(getTable.opcode, BytecodeOpcode.getTable);
      expect(getTable.a, equals(0));
      expect(getTable.b, equals(0));
      expect(getTable.c, equals(1));
    });

    test('compiles empty table constructor', () {
      final program = parse('return {}');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final newTable = instructions[0] as ABCInstruction;
      expect(newTable.opcode, BytecodeOpcode.newTable);
      expect(newTable.a, equals(0));

      final ret = instructions.last as ABCInstruction;
      expect(ret.opcode, BytecodeOpcode.return1);
      expect(ret.a, equals(0));
    });

    test('compiles mixed table constructor entries', () {
      final program = parse('return {1, foo = 2, [bar()] = 3, 4}');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.newTable,
        ),
        isTrue,
      );
      final setIIndices = instructions
          .where((instruction) => instruction.opcode == BytecodeOpcode.setI)
          .map((instruction) => (instruction as ABCInstruction).b);
      expect(setIIndices, containsAll(<int>[1, 2]));

      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.setField,
        ),
        isTrue,
      );
      expect(
        instructions.any(
          (instruction) => instruction.opcode == BytecodeOpcode.setTable,
        ),
        isTrue,
      );
    });
  });
}

List<BytecodeInstruction> _stripVarArgPrep(BytecodePrototype proto) {
  final instructions = proto.instructions;
  if (instructions.isNotEmpty &&
      instructions.first.opcode == BytecodeOpcode.varArgPrep) {
    return instructions.sublist(1);
  }
  return instructions;
}
