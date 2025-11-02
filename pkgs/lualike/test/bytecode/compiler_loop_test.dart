import 'package:lualike/src/bytecode/compiler.dart';
import 'package:lualike/src/bytecode/instruction.dart';
import 'package:lualike/src/bytecode/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('BytecodeCompiler loops', () {
    test('numeric for loop emits forPrep and forLoop', () {
      final program = parse(
        'for i = 1, 3 do tbl.sum = tbl.sum + i end',
      );
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasForPrep = instructions.any(
        (instruction) => instruction.opcode == BytecodeOpcode.forPrep,
      );
      final forLoop = instructions.whereType<AsBxInstruction>().firstWhere(
            (instruction) => instruction.opcode == BytecodeOpcode.forLoop,
          );

      expect(hasForPrep, isTrue);
      expect(forLoop.sBx, lessThan(0));
    });

    test('numeric for loop with negative step emits backward jump', () {
      final program = parse(
        'for i = 3, 1, -1 do tbl.count = tbl.count + 1 end',
      );
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final forLoop = instructions.whereType<AsBxInstruction>().firstWhere(
            (instruction) => instruction.opcode == BytecodeOpcode.forLoop,
          );
      expect(forLoop.sBx, lessThan(0));
    });

    test('generic for loop emits tfor opcodes', () {
      final program = parse(
        'for idx, value in iter, state, control do tbl.sum = tbl.sum + value end',
      );
      final chunk = BytecodeCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasPrep = instructions.any(
        (instruction) => instruction.opcode == BytecodeOpcode.tForPrep,
      );
      final hasCall = instructions.any(
        (instruction) => instruction.opcode == BytecodeOpcode.tForCall,
      );
      final hasLoop = instructions.any(
        (instruction) => instruction.opcode == BytecodeOpcode.tForLoop,
      );

      expect(hasPrep, isTrue);
      expect(hasCall, isTrue);
      expect(hasLoop, isTrue);
    });
  });
}
