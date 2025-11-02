import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/instruction.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/bytecode/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler comparisons', () {
    test('compiles not-equals comparison', () {
      final program = parse('return a ~= 1');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(instructions, hasLength(4));
      final eq = instructions[1] as ABCInstruction;
      expect(eq.opcode, BytecodeOpcode.eqI);
      expect(eq.c, equals(1));

      final notInstr = instructions[2] as ABCInstruction;
      expect(notInstr.opcode, BytecodeOpcode.notOp);
      expect(notInstr.a, equals(0));
      expect(notInstr.b, equals(0));
    });

    test('compiles equality with string literal', () {
      final program = parse('return a == "foo"');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final fooIndex = proto.constants.indexWhere(
        (constant) =>
            constant is ShortStringConstant && constant.value == 'foo',
      );
      expect(fooIndex, isNonNegative);

      final instructions = _stripVarArgPrep(proto);

      final eqInstr = instructions[1] as ABCInstruction;
      expect(eqInstr.opcode, BytecodeOpcode.eqK);
      expect(eqInstr.c, equals(fooIndex));
    });

    test('compiles equality with integer literal', () {
      final program = parse('return a == 5');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final eqInstr = instructions[1] as ABCInstruction;
      expect(eqInstr.opcode, BytecodeOpcode.eqI);
      expect(eqInstr.c, equals(5));
    });

    test('compiles less-than integer literal', () {
      final program = parse('return a < 10');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      final ltInstr = instructions[1] as ABCInstruction;
      expect(ltInstr.opcode, BytecodeOpcode.ltI);
      expect(ltInstr.c, equals(10));
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
