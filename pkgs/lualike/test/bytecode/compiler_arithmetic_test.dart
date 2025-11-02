import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/instruction.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/bytecode/prototype.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler arithmetic', () {
    test('compiles identifier arithmetic expression', () {
      final program = parse('return a + 2');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(proto.registerCount, greaterThanOrEqualTo(1));
      expect(instructions, hasLength(3));

      final nameIndex = proto.constants.indexWhere(
        (constant) => constant is ShortStringConstant && constant.value == 'a',
      );
      final twoIndex = proto.constants.indexWhere(
        (constant) => constant is IntegerConstant && constant.value == 2,
      );
      expect(nameIndex, isNonNegative);
      expect(twoIndex, isNonNegative);

      final getTab = instructions[0] as ABCInstruction;
      expect(getTab.opcode, BytecodeOpcode.getTabUp);
      expect(getTab.c, equals(nameIndex));

      final add = instructions[1] as ABCInstruction;
      expect(add.opcode, BytecodeOpcode.addK);
      expect(add.a, equals(0));
      expect(add.b, equals(0));
      expect(add.c, equals(twoIndex));
      expect(add.k, isTrue);
    });

    test('compiles bitwise and expression', () {
      final program = parse('return a & 3');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(instructions, hasLength(4));
      final band = instructions[2] as ABCInstruction;
      expect(band.opcode, BytecodeOpcode.band);
      expect(band.a, equals(0));
      expect(band.b, equals(0));
      expect(band.c, equals(1));
    });

    test('compiles unary not expression', () {
      final program = parse('return not flag');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(instructions, hasLength(3));
      final notInstr = instructions[1] as ABCInstruction;
      expect(notInstr.opcode, BytecodeOpcode.notOp);
      expect(notInstr.a, equals(0));
      expect(notInstr.b, equals(0));
    });

    test('compiles modulo expression', () {
      final program = parse('return a % 2');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final constantIndex = proto.constants.indexWhere(
        (constant) => constant is IntegerConstant && constant.value == 2,
      );
      expect(constantIndex, isNonNegative);

      final instructions = _stripVarArgPrep(proto);

      final modInstr = instructions[1] as ABCInstruction;
      expect(modInstr.opcode, BytecodeOpcode.modK);
      expect(modInstr.a, equals(0));
      expect(modInstr.b, equals(0));
      expect(modInstr.c, equals(constantIndex));
      expect(modInstr.k, isTrue);
    });

    test('compiles floor division expression', () {
      final program = parse('return a // 2');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final constantIndex = proto.constants.indexWhere(
        (constant) => constant is IntegerConstant && constant.value == 2,
      );
      expect(constantIndex, isNonNegative);

      final instructions = _stripVarArgPrep(proto);

      final idivInstr = instructions[1] as ABCInstruction;
      expect(idivInstr.opcode, BytecodeOpcode.idivK);
      expect(idivInstr.a, equals(0));
      expect(idivInstr.b, equals(0));
      expect(idivInstr.c, equals(constantIndex));
      expect(idivInstr.k, isTrue);
    });

    test('compiles exponent expression', () {
      final program = parse('return a ^ 2');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;

      final constantIndex = proto.constants.indexWhere(
        (constant) => constant is IntegerConstant && constant.value == 2,
      );
      expect(constantIndex, isNonNegative);

      final instructions = _stripVarArgPrep(proto);

      final powInstr = instructions[1] as ABCInstruction;
      expect(powInstr.opcode, BytecodeOpcode.powK);
      expect(powInstr.a, equals(0));
      expect(powInstr.b, equals(0));
      expect(powInstr.c, equals(constantIndex));
      expect(powInstr.k, isTrue);
    });

    test('compiles string concatenation expression', () {
      final program = parse('return a .. b');
      final chunk = BytecodeCompiler().compile(program);
      final proto = chunk.mainPrototype;
      final instructions = _stripVarArgPrep(proto);

      expect(instructions, hasLength(4));
      final concatInstr = instructions[2] as ABCInstruction;
      expect(concatInstr.opcode, BytecodeOpcode.concat);
      expect(concatInstr.a, equals(0));
      expect(concatInstr.b, equals(0));
      expect(concatInstr.c, equals(1));
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
