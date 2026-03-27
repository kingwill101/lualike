@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/ir/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler comparisons', () {
    test('compiles not-equals comparison', () {
      final program = parse('return a ~= 1');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(instructions, hasLength(4));
      final eq = instructions[1] as ABCInstruction;
      expect(eq.opcode, LualikeIrOpcode.eqI);
      expect(eq.c, equals(1));

      final notInstr = instructions[2] as ABCInstruction;
      expect(notInstr.opcode, LualikeIrOpcode.notOp);
      expect(notInstr.a, equals(0));
      expect(notInstr.b, equals(0));
    });

    test('compiles equality with string literal', () {
      final program = parse('return a == "foo"');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final fooIndex = proto.constants.indexWhere(
        (constant) =>
            constant is ShortStringConstant && constant.value == 'foo',
      );
      expect(fooIndex, isNonNegative);

      final instructions = _stripVarArgPrep(proto);

      final eqInstr = instructions[1] as ABCInstruction;
      expect(eqInstr.opcode, LualikeIrOpcode.eqK);
      expect(eqInstr.c, equals(fooIndex));
    });

    test('compiles equality with integer literal', () {
      final program = parse('return a == 5');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final eqInstr = instructions[1] as ABCInstruction;
      expect(eqInstr.opcode, LualikeIrOpcode.eqI);
      expect(eqInstr.c, equals(5));
    });

    test('compiles less-than integer literal', () {
      final program = parse('return a < 10');
      final chunk = LualikeIrCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final ltInstr = instructions[1] as ABCInstruction;
      expect(ltInstr.opcode, LualikeIrOpcode.ltI);
      expect(ltInstr.c, equals(10));
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
