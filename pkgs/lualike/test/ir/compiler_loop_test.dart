@Tags(['ir'])
library;

import 'package:lualike/src/ir/compiler.dart';
import 'package:lualike/src/ir/instruction.dart';
import 'package:lualike/src/ir/opcode.dart';
import 'package:lualike/src/parse.dart';
import 'package:test/test.dart';

void main() {
  group('LualikeIrCompiler loops', () {
    test('repeat-until emits loop test and backward jump', () {
      final program = parse('repeat count = count + 1 until count >= 3');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final testIndex = instructions.indexWhere(
        (instruction) => instruction.opcode == LualikeIrOpcode.test,
      );
      final jump = instructions.whereType<AsJInstruction>().last;

      expect(testIndex, isNonNegative);
      expect(jump.opcode, equals(LualikeIrOpcode.jmp));
      expect(jump.sJ, lessThan(0));
    });

    test('numeric for loop emits forPrep and forLoop', () {
      final program = parse('for i = 1, 3 do tbl.sum = tbl.sum + i end');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasForPrep = instructions.any(
        (instruction) => instruction.opcode == LualikeIrOpcode.forPrep,
      );
      final forLoop = instructions.whereType<AsBxInstruction>().firstWhere(
        (instruction) => instruction.opcode == LualikeIrOpcode.forLoop,
      );

      expect(hasForPrep, isTrue);
      expect(forLoop.sBx, lessThan(0));
    });

    test('numeric for loop with negative step emits backward jump', () {
      final program = parse(
        'for i = 3, 1, -1 do tbl.count = tbl.count + 1 end',
      );
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final forLoop = instructions.whereType<AsBxInstruction>().firstWhere(
        (instruction) => instruction.opcode == LualikeIrOpcode.forLoop,
      );
      expect(forLoop.sBx, lessThan(0));
    });

    test('generic for loop emits tfor opcodes', () {
      final program = parse(
        'for idx, value in iter, state, control do tbl.sum = tbl.sum + value end',
      );
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final hasPrep = instructions.any(
        (instruction) => instruction.opcode == LualikeIrOpcode.tForPrep,
      );
      final hasCall = instructions.any(
        (instruction) => instruction.opcode == LualikeIrOpcode.tForCall,
      );
      final hasLoop = instructions.any(
        (instruction) => instruction.opcode == LualikeIrOpcode.tForLoop,
      );

      expect(hasPrep, isTrue);
      expect(hasCall, isTrue);
      expect(hasLoop, isTrue);
    });

    test('generic for loop with close value emits loop close', () {
      final program = parse(
        'for k, v in next, {}, nil, closer do tbl.sum = tbl.sum + v end',
      );
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final closeIndices = <int>[];
      for (var i = 0; i < instructions.length; i++) {
        if (instructions[i].opcode == LualikeIrOpcode.close) {
          closeIndices.add(i);
        }
      }
      final tforLoopIndex = instructions.indexWhere(
        (instruction) => instruction.opcode == LualikeIrOpcode.tForLoop,
      );

      expect(tforLoopIndex, isNonNegative);
      expect(closeIndices, isNotEmpty);
      expect(closeIndices.last, greaterThan(tforLoopIndex));
    });

    test('break emits jump patched to loop exit', () {
      final program = parse('while flag do break end return 1');
      final chunk = LualikeIrCompiler().compile(program);
      final instructions = chunk.mainPrototype.instructions;

      final jumps = instructions.whereType<AsJInstruction>().toList();
      expect(jumps, isNotEmpty);
      expect(jumps.any((instruction) => instruction.sJ >= 0), isTrue);
    });
  });
}
