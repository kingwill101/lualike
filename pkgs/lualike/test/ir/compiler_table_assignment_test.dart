@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler table assignments', () {
    test('compiles table field assignment', () {
      final program = parse('tbl.value = 42');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final fieldIndex = proto.constants.indexWhere(
        (constant) =>
            constant is ShortStringConstant && constant.value == 'value',
      );
      expect(fieldIndex, isNonNegative);

      final setField = instructions.whereType<ABCInstruction>().firstWhere(
        (instr) => instr.opcode == LualikeIrOpcode.setField,
      );
      expect(setField.opcode, LualikeIrOpcode.setField);
      expect(setField.b, equals(fieldIndex));
      final loadValue =
          instructions.firstWhere(
                (instr) =>
                    instr is ABxInstruction &&
                    instr.opcode == LualikeIrOpcode.loadK,
              )
              as ABxInstruction;
      expect(setField.c, equals(loadValue.a));
    });

    test('compiles table index assignment with integer literal', () {
      final program = parse('arr[1] = 5');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final loadValue =
          instructions.firstWhere(
                (instr) =>
                    instr is ABxInstruction &&
                    instr.opcode == LualikeIrOpcode.loadK,
              )
              as ABxInstruction;
      final setI = instructions.whereType<ABCInstruction>().firstWhere(
        (instr) => instr.opcode == LualikeIrOpcode.setI,
      );
      expect(setI.opcode, LualikeIrOpcode.setI);
      expect(setI.b, equals(1));
      expect(setI.c, equals(loadValue.a));
    });

    test('compiles table index assignment with dynamic key', () {
      final program = parse('arr[key] = value');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = _stripVarArgPrep(chunk.mainPrototype);

      final setTable = instructions.whereType<ABCInstruction>().firstWhere(
        (instr) => instr.opcode == LualikeIrOpcode.setTable,
      );
      expect(setTable.opcode, LualikeIrOpcode.setTable);
      expect(setTable.b, isNot(equals(setTable.a)));
      expect(setTable.c, isNot(anyOf(equals(setTable.a), equals(setTable.b))));
    });

    test('compiles large integer literal assignment with SETTABLE fallback', () {
      final program = parse('arr[999] = value');
      final instructions = _stripVarArgPrep(
        LualikeIrCompiler().compile(program).mainPrototype,
      );

      expect(
        instructions.any((instr) => instr.opcode == LualikeIrOpcode.setI),
        isFalse,
      );
      expect(
        instructions.any((instr) => instr.opcode == LualikeIrOpcode.setTable),
        isTrue,
      );
    });

    test('compiles multi-target table field assignment', () {
      final program = parse('tbl.alpha, tbl.beta = 1, 2');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      int constantIndexFor(String value) {
        return proto.constants.indexWhere(
          (constant) =>
              constant is ShortStringConstant && constant.value == value,
        );
      }

      final alphaIndex = constantIndexFor('alpha');
      final betaIndex = constantIndexFor('beta');
      expect(alphaIndex, isNonNegative);
      expect(betaIndex, isNonNegative);

      final setFields = instructions
          .whereType<ABCInstruction>()
          .where((instr) => instr.opcode == LualikeIrOpcode.setField)
          .toList();
      expect(setFields, hasLength(2));
      expect(setFields[0].b, equals(alphaIndex));
      expect(setFields[1].b, equals(betaIndex));
    });
  });
}

List<LualikeIrInstruction> _stripVarArgPrep(LualikeIrPrototype proto) {
  final instructions = proto.instructions;
  if (instructions.isNotEmpty &&
      instructions.first.opcode == LualikeIrOpcode.varArgPrep) {
    return instructions.sublist(1);
  }
  return instructions;
}
