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
      final instructions = _stripVarArgPrep(proto);

      final fieldIndex = proto.constants.indexWhere(
        (constant) =>
            constant is ShortStringConstant && constant.value == 'value',
      );
      expect(fieldIndex, isNonNegative);

      final setField = instructions.whereType<ABCInstruction>().firstWhere(
        (instr) => instr.opcode == BytecodeOpcode.setField,
      );
      expect(setField.opcode, BytecodeOpcode.setField);
      expect(setField.b, equals(fieldIndex));
      final loadValue =
          instructions.firstWhere(
                (instr) =>
                    instr is ABxInstruction &&
                    instr.opcode == BytecodeOpcode.loadK,
              )
              as ABxInstruction;
      expect(setField.c, equals(loadValue.a));
    });

    test('compiles table index assignment with integer literal', () {
      final program = parse('arr[1] = 5');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final loadValue =
          instructions.firstWhere(
                (instr) =>
                    instr is ABxInstruction &&
                    instr.opcode == BytecodeOpcode.loadK,
              )
              as ABxInstruction;
      final setI = instructions.whereType<ABCInstruction>().firstWhere(
        (instr) => instr.opcode == BytecodeOpcode.setI,
      );
      expect(setI.opcode, BytecodeOpcode.setI);
      expect(setI.b, equals(1));
      expect(setI.c, equals(loadValue.a));
    });

    test('compiles table index assignment with dynamic key', () {
      final program = parse('arr[key] = value');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final setTable = instructions.whereType<ABCInstruction>().firstWhere(
        (instr) => instr.opcode == BytecodeOpcode.setTable,
      );
      expect(setTable.opcode, BytecodeOpcode.setTable);
      expect(setTable.a, equals(0));
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
